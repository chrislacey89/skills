#!/usr/bin/env bash
# test-post-review-edit-lock.sh — contract test for the post-review edit lock:
# the second clause of `.claude/hooks/enforce-classification.sh` and the five
# runnable blocks, spread across five skills, that drive it.
#
# THE DRIFT CLASS. #327 built a lock out of one hook clause and four commands
# that live in four different files. `/pre-merge` Phase 4 touches the stamp
# flag; `/fix-findings`' harness line touches the fixer flag and its Step 3
# removes it; `/closeout` Step 3 removes the stamp flag at merge; and the hook —
# documented in `/init-pipeline`, installed into somebody else's repo — is the
# only thing that reads either. Nothing pinned any of it: `rg -l review-stamped
# scripts/` and `rg -l "enforce-classification|IMPL_PATTERNS" scripts/` both
# returned empty, so no suite had ever run the hook body at all.
#
# The two failure directions are not symmetric, which is why prose was the wrong
# medium for it. A lock that refuses too much is loud — somebody hits it within
# a minute and says so. A lock that never engages is silent: a flag written to a
# path the hook does not read, or a condition that can no longer be true, looks
# from the outside exactly like a branch nobody edited after review. That is the
# state the mechanism exists to make impossible, reported as success.
#
# CLAUDE.md § "Commands a skill documents" rule (b) is the standing response —
# a checkable claim about tool behavior is routed to a mechanism, not to careful
# reading. #243 is the incident behind that rule: six successive drafts of one
# passage each shipped a wrong claim, every wrong draft was caught by a human or
# a review sub-agent, and none by a check.
#
# SO THIS SUITE RUNS THE THING. It extracts the hook body and all five commands
# verbatim from the skills that document them and executes them against real
# files in a scratch project. It types no flag path of its own: the flag paths
# are read out of `/pre-merge`'s `touch` and `/fix-findings`' harness line, and
# section 5 drives the whole lifecycle — classified, cleared, stamped, opened,
# shut, released — using only text the skills supply. A rename in one file that
# the other four do not mirror fails here, rather than in a downstream repo at
# merge time.
#
# THE CLASSIFICATION CONTEXT IS PART OF THE SUBJECT, not scenery. The first
# version of this suite set `.tdd-active` in every lock fixture and drove the
# round trip without `/execute` Step 6's removal — so it never once observed the
# state the lock actually operates in, which is a STAMPED and MARKERLESS branch.
# In that state a strictly ordered pair of clauses never reaches the second one:
# the `/fix-findings` fixer is refused despite holding the flag written for it,
# and the human is refused by a message naming `/tdd` that never names the route
# the lock exists to offer. Every assertion was green. Section 3 now drives both
# contexts, section 5 runs Step 6's removal in sequence, and section 9's second
# control rebuilds that exact hook and requires both halves to come back.
#
# NOT COVERED, stated so nobody over-trusts it. Whether Claude Code actually
# invokes the hook on Write/Edit, and whether the harness sets
# `$CLAUDE_PROJECT_DIR` at all, are properties of the harness and not of any
# text in this repo — no suite here can reach them. Section 6 covers only the
# fallback the skills themselves wrote for that variable's absence. And the
# hook is documented prose, not an installed file: this proves the block a
# downstream agent copies is correct, not that any given project copied it.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %q\n       got:      %q\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

command -v jq >/dev/null || fatal "jq is not installed — the hook body parses its stdin with it, so this suite cannot run the subject"

# --- One reader, used by every extraction and by the apparatus check ----------
#
# Emits the first ```bash fenced block in <file> whose body matches <regex>;
# exits 1 when there is none. It does not call fatal: a helper that aborts from
# inside a command substitution exits only the subshell (test-guards-can-fire.sh
# detector C), so the caller in the main shell decides what an empty capture
# means.
fenced_bash_block() {  # $1 = file, $2 = ERE matched against the block body
    awk -v re="$2" '
        /^```bash$/        { buf = ""; inblock = 1; next }
        inblock && /^```$/ { if (buf ~ re) { printf "%s", buf; found = 1; exit }
                             inblock = 0; next }
        inblock            { buf = buf $0 "\n" }
        END                { exit(found ? 0 : 1) }
    ' "$1"
}

# --- Pull the subject out of the skills that document it ---------------------

# The hook body /init-pipeline tells a downstream agent to write to
# .claude/hooks/enforce-classification.sh.
# The same reader for the ```json fence, used below to read the hook's own
# registration — which tool calls the harness presents it with — out of the
# settings block /init-pipeline tells a downstream agent to write.
fenced_json_block() {  # $1 = file, $2 = ERE matched against the block body
    awk -v re="$2" '
        /^```json$/        { buf = ""; inblock = 1; next }
        inblock && /^```$/ { if (buf ~ re) { printf "%s", buf; found = 1; exit }
                             inblock = 0; next }
        inblock            { buf = buf $0 "\n" }
        END                { exit(found ? 0 : 1) }
    ' "$1"
}

hook_body="$(fenced_bash_block init-pipeline/SKILL.md 'IMPL_PATTERNS' || true)"
[ -n "$hook_body" ] || fatal "no IMPL_PATTERNS hook body found in init-pipeline/SKILL.md — either the hook moved or its fence changed; update this suite with it"

# The stamp flag's writer (/pre-merge Phase 4) and remover (/closeout Step 3).
# Both sit at the tail of a larger fenced block, so the slice is anchored on the
# PROJECT_DIR assignment that opens them rather than on their content.
stamp_block="$(fenced_bash_block pre-merge/SKILL.md 'review-stamped' || true)"
[ -n "$stamp_block" ] || fatal "no stamp block found in pre-merge/SKILL.md"

stamp_write="$(sed -n '/^PROJECT_DIR=/,$p' <<<"$stamp_block")"
[ -n "$stamp_write" ] || fatal "no PROJECT_DIR-anchored stamp-flag write found in pre-merge/SKILL.md"

stamp_remove="$(fenced_bash_block closeout/SKILL.md 'review-stamped' | sed -n '/^PROJECT_DIR=/,$p' || true)"
[ -n "$stamp_remove" ] || fatal "no PROJECT_DIR-anchored stamp-flag removal found in closeout/SKILL.md"

# The fixer flag's writer is /fix-findings' harness line — `!`…`` at the top of
# the file, not a fenced block — and its remover is Step 3's fenced rm.
# shellcheck disable=SC2016  # the `$` and backticks are markdown/sed literals being matched, not shell expansions
fixer_write="$(sed -n 's/^!`\(.*\)`$/\1/p' fix-findings/SKILL.md || true)"
[ -n "$fixer_write" ] || fatal "no harness line found in fix-findings/SKILL.md"

fixer_remove="$(fenced_bash_block fix-findings/SKILL.md 'fix-findings-active' || true)"
[ -n "$fixer_remove" ] || fatal "no fixer-flag removal found in fix-findings/SKILL.md"

# /fix-findings Step 2's throwaway copy for the breaker.
archive_block="$(fenced_bash_block fix-findings/SKILL.md 'git archive' || true)"
[ -n "$archive_block" ] || fatal "no git archive block found in fix-findings/SKILL.md"

# /execute Step 6's removal of both classification markers. This is the
# lifecycle step that makes the post-review state MARKERLESS, and leaving it out
# of section 5 is what let the two clauses' ordering defect ship green: the round
# trip stamped a branch that still carried .tdd-active, a state /execute has
# already destroyed by the time /pre-merge runs.
tdd_marker_remove="$(fenced_bash_block execute/SKILL.md 'tdd-active' || true)"
[ -n "$tdd_marker_remove" ] || fatal "no classification-marker removal found in execute/SKILL.md Step 6"

# --- The flag paths, read out of the writers rather than typed here ----------

stamp_arg="$(sed -n 's|.*touch "\([^"]*\)".*|\1|p' <<<"$stamp_write")"
stamp_rel="${stamp_arg#*/}"                      # strip the $PROJECT_DIR/ prefix
# `if [ -z … ] || [ -z … ]` rather than `[ -n … ] && [ … ] || fatal`: the second
# form is SC2015, which local shellcheck 0.11.0 accepts and the pinned CI 0.9.0
# rejects. test-markdown-diff-attribute.sh:132 states the same house idiom for
# the same reason.
if [ -z "$stamp_rel" ] || [ "$stamp_rel" = "$stamp_arg" ]; then
    fatal "could not read a project-relative stamp-flag path out of /pre-merge's touch"
fi

fixer_arg="$(sed -n 's|.*touch "\([^"]*\)".*|\1|p' <<<"$fixer_write")"
fixer_rel="${fixer_arg#*/}"                      # strip the $PROJECT_DIR/ prefix
if [ -z "$fixer_rel" ] || [ "$fixer_rel" = "$fixer_arg" ]; then
    fatal "could not read a project-relative fixer-flag path out of /fix-findings' harness line"
fi

# The fixer flag's THIRD site: the path Step 3's removal aims at. Read, not
# typed, for the same reason the other two are — the flag had three different
# path resolutions when this suite first went green, and nothing compared them.
# shellcheck disable=SC2016  # `$PROJECT_DIR` is the literal text being searched for in the extracted block, not an expansion
fixer_remove_rel="$(grep -o '\$PROJECT_DIR/[^" ]*' <<<"$fixer_remove" | sed 's|^\$PROJECT_DIR/||' | sort -u || true)"

# Every "$CLAUDE_PROJECT_DIR/…" path the hook tests, project-relative.
# shellcheck disable=SC2016  # `$CLAUDE_PROJECT_DIR` is the literal text being searched for in the hook, not an expansion
hook_paths="$(grep -o '\$CLAUDE_PROJECT_DIR/[^"]*' <<<"$hook_body" | sed 's|^\$CLAUDE_PROJECT_DIR/||' | sort -u || true)"
[ -n "$hook_paths" ] || fatal "the extracted hook body tests no \$CLAUDE_PROJECT_DIR paths at all"

printf 'hook body:      %s lines from init-pipeline/SKILL.md\n' "$(grep -c '' <<<"$hook_body")"
printf 'stamp flag:     %s   (written by /pre-merge, removed by /closeout)\n' "$stamp_rel"
printf 'fixer flag:     %s   (written and removed by /fix-findings)\n' "$fixer_rel"

# The classification gate's own markers: whatever the hook tests that is not one
# of the lock's two flags. Derived so that renaming a marker does not require
# editing this suite, and counted so that a derivation returning the wrong set
# is loud rather than quietly reducing the fixture to nothing.
tdd_flags="$(grep -vxF "$stamp_rel" <<<"$hook_paths" | grep -vxF "$fixer_rel" || true)"
tdd_active="$(sed -n 1p <<<"$tdd_flags")"
tdd_skipped="$(sed -n 2p <<<"$tdd_flags")"

# --- Scratch project the hook and the four commands act on -------------------

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
proj="$scratch/project"
mkdir -p "$proj/.claude"

hook_file="$scratch/enforce-classification.sh"
printf '%s' "$hook_body" > "$hook_file"

hook_status=0
hook_err=""
# Feed the hook the PreToolUse payload shape it reads with jq, and capture the
# refusal it writes to stderr. $hook_file is a variable because section 9 points
# it at a mutant and re-runs these same assertions through this same reader.
run_hook() {  # $1 = the file path the harness would present
    hook_status=0
    hook_err="$(printf '{"tool_input":{"file_path":"%s"}}' "$1" \
        | CLAUDE_PROJECT_DIR="$proj" bash "$hook_file" 2>&1 >/dev/null)" || hook_status=$?
}

set_flags() {  # each argument is a project-relative flag path to create
    find "$proj/.claude" -mindepth 1 -delete
    local flag
    for flag in "$@"; do
        mkdir -p "$proj/$(dirname "$flag")"
        touch "$proj/$flag"
    done
}

# The one runner for all four documented commands. An empty $3 means "run with
# CLAUDE_PROJECT_DIR unset", which is the case the skills' `${CLAUDE_PROJECT_DIR
# :-$(git rev-parse --show-toplevel)}` fallback was written for.
run_documented() {  # $1 = directory, $2 = command text, $3 = CLAUDE_PROJECT_DIR
    if [ -n "$3" ]; then
        ( cd "$1" && CLAUDE_PROJECT_DIR="$3" bash -c "$2" ) >/dev/null
    else
        ( cd "$1" && env -u CLAUDE_PROJECT_DIR bash -c "$2" ) >/dev/null
    fi
}

# -----------------------------------------------------------------------------

section "1. the hook is a runnable script, and the five files agree on two paths"

status=0
bash -n "$hook_file" || status=$?
assert_eq 0 "$status" "the hook body /init-pipeline documents parses as bash"

assert_eq 2 "$(grep -c '' <<<"$tdd_flags")" \
    "the hook tests exactly two classification markers besides the lock's two flags"

if grep -qxF "$stamp_rel" <<<"$hook_paths"; then
    assert_eq "$stamp_rel" "$stamp_rel" "the hook reads the same stamp-flag path /pre-merge writes"
else
    assert_eq "$stamp_rel" "(absent from the hook)" "the hook reads the same stamp-flag path /pre-merge writes"
fi

if grep -qxF "$fixer_rel" <<<"$hook_paths"; then
    assert_eq "$fixer_rel" "$fixer_rel" "the hook reads the same fixer-flag path /fix-findings writes"
else
    assert_eq "$fixer_rel" "(absent from the hook)" "the hook reads the same fixer-flag path /fix-findings writes"
fi

# Three sites, one path. The harness line's `touch`, the hook's `-f` test, and
# Step 3's `rm` each resolve the fixer flag independently, and the first version
# of this lock had them resolving to three different files: a cwd-relative
# create, a `$CLAUDE_PROJECT_DIR` read, and an unguarded `$CLAUDE_PROJECT_DIR`
# removal. Either end of that spread is a silent failure — the flag lands where
# the hook does not look and the lock refuses its own fixer, or the removal
# misses and the lock stands open with nothing to say so.
assert_eq "$fixer_rel" "$fixer_remove_rel" \
    "/fix-findings' Step 3 removal aims at the same fixer-flag path its harness line writes"

# -----------------------------------------------------------------------------

section "2. the classification gate still fires (clause 1)"

# Nothing executed this clause before this suite existed either. It is pinned
# here so the lock's arrival on the same trigger surface cannot break it
# silently — the two clauses share IMPL_PATTERNS and the skip logic by design.

set_flags
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "an unclassified implementation write is refused"

set_flags "$tdd_active"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "a write under $tdd_active is allowed"

set_flags "$tdd_skipped"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "a write under $tdd_skipped is allowed"

# -----------------------------------------------------------------------------

section "3. the lock's truth table (clause 2), in both classification contexts"

# Driven TWICE, because the classification context is not incidental to it.
#
# Every row here used to run with `$tdd_active` present, and that state cannot
# occur: /execute Step 6 removes both classification markers before it hands off
# to /pre-merge, so a stamped branch is always markerless. Under a strictly
# ordered pair of clauses that is the whole defect — clause 1 short-circuits, the
# /fix-findings fixer is refused despite holding the flag written for it, and the
# human is refused by a message that names /tdd and never names /fix-findings.
# Green rows with a marker in place could not see any of it.
#
# So the outcomes below must be IDENTICAL in both contexts. That is the property
# the `.review-stamped` term in clause 1 establishes: on a stamped branch the
# classification clause stands down, and this clause is the sole decider.

# The two refusal messages, read out of the hook rather than typed here, so that
# "which clause refused this" is a measurement and not a guess. Clause 1's echo
# precedes clause 2's in the body.
class_msg="$(grep -o '"reason":"BLOCKED:[^"]*"' <<<"$hook_body" | sed -n 1p)"
lock_msg="$(grep -o '"reason":"BLOCKED:[^"]*"' <<<"$hook_body" | sed -n 2p)"
if [ -z "$class_msg" ] || [ -z "$lock_msg" ]; then
    fatal "could not read two BLOCKED reasons out of the hook body"
fi
[ "$class_msg" != "$lock_msg" ] || fatal "the hook's two refusals are byte-identical — 'which clause refused' is unmeasurable"

set_context() {  # $1 = classification marker, or "" for none; rest = extra flags
    local marker="$1"; shift
    if [ -n "$marker" ]; then set_flags "$marker" "$@"; else set_flags "$@"; fi
}

for context in "$tdd_active" ""; do
    if [ -n "$context" ]; then
        where="under $context"
    else
        where="with no classification marker (the state /execute Step 6 leaves)"
    fi

    set_context "$context"
    run_hook "src/service.ts"
    if [ -n "$context" ]; then
        assert_eq 0 "$hook_status" "unstamped, $where: the write lands"
    else
        # Unstamped and unclassified is clause 1's own case, and it must keep
        # refusing — the stand-down is scoped to stamped branches only.
        assert_eq 2 "$hook_status" "unstamped, $where: the classification gate still refuses"
    fi

    set_context "$context" "$stamp_rel"
    run_hook "src/service.ts"
    assert_eq 2 "$hook_status" "stamped, no fixer flag, $where: the write is refused"

    if grep -qF "$lock_msg" <<<"$hook_err"; then
        assert_eq "the lock refused it" "the lock refused it" \
            "the refusal routes the human to /fix-findings, $where"
    else
        assert_eq "the lock refused it" "$hook_err" \
            "the refusal routes the human to /fix-findings, $where"
    fi

    if grep -qF "$class_msg" <<<"$hook_err"; then
        assert_eq "not the classification clause" "the classification clause refused it" \
            "clause 1 does not preempt the lock, $where"
    else
        assert_eq "not the classification clause" "not the classification clause" \
            "clause 1 does not preempt the lock, $where"
    fi

    set_context "$context" "$stamp_rel" "$fixer_rel"
    run_hook "src/service.ts"
    assert_eq 0 "$hook_status" "stamped with the fixer flag present, $where: the fixer's write lands"

    set_context "$context" "$fixer_rel"
    run_hook "src/service.ts"
    if [ -n "$context" ]; then
        assert_eq 0 "$hook_status" "fixer flag alone, nothing stamped, $where: the write lands"
    else
        # The fixer flag is not a classification marker and must not act as one
        # off a stamped branch — otherwise a leaked flag opens the TDD gate too.
        assert_eq 2 "$hook_status" "fixer flag alone, nothing stamped, $where: still unclassified, still refused"
    fi
done

# -----------------------------------------------------------------------------

section "4. what the lock does not refuse, which is more than the prose used to say"

# Both skills say, in prose, what the lock does NOT refuse. Everything below is
# a measurement of that claim rather than a restatement of it, and the section
# is cited by name from both skills, so the two halves stay attached: what the
# skip logic lets through, what the substring matching lets through that a
# reader of "a test file" would not predict, and which writes the armed lock
# permits outright. #327's review found the prose wrong on the last two.

set_context "" "$stamp_rel"

run_hook "src/service.test.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a test file"

run_hook "src/service.spec.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a spec file"

run_hook "src/types.d.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a type declaration"

run_hook "vite.config.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a config file"

run_hook "README.md"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a file off the pattern list"

# --- The skip patterns match a SUBSTRING OF THE PATH, not a file's role ------
#
# #327's own review found both skills describing this surface in intent
# vocabulary — "a test file", "a type declaration", "a config file" — while the
# matcher does `[[ "$FILE_PATH" == *test* ]]` against whatever path the harness
# hands it, which Claude Code makes ABSOLUTE. A reader of those sentences would
# not predict any of the rows below, and the five assertions above could not
# tell the two readings apart: every fixture in them was a file whose role
# matched its name. These are the same clause, measured where the two readings
# diverge.
run_hook "src/latest-news.ts"
assert_eq 0 "$hook_status" "…nor src/latest-news.ts, whose name contains 'test'"

run_hook "src/respectful.ts"
assert_eq 0 "$hook_status" "…nor src/respectful.ts, whose name contains 'spec'"

run_hook "src/testimonials/Card.tsx"
assert_eq 0 "$hook_status" "…nor a file under a testimonials/ directory"

run_hook "src/app.config.local.ts"
assert_eq 0 "$hook_status" "…nor src/app.config.local.ts, which carries '.config.' mid-name"

run_hook "/Users/tester/proj/src/app.ts"
assert_eq 0 "$hook_status" "…nor ANY file in a project checked out under a path containing 'test'"

# The control that makes the row above a measurement of the substring rather
# than of absoluteness: the same absolute shape, one directory name changed.
run_hook "/Users/dev/proj/src/app.ts"
assert_eq 2 "$hook_status" "…while the same absolute path under /Users/dev is refused"

# --- Routes past the lock, three of which leave no trace ---------------------
#
# The prose in both skills used to say the lock had "two exits," "both
# deliberate acts." It has more, because it is a PreToolUse hook on Write|Edit
# over an implementation-pattern list, not an enclosure. Each row is a write
# that the armed lock permits; the paths are derived, not typed, so a rename
# that closes one of these routes fails here and the prose gets revisited.
hook_command="$(fenced_json_block init-pipeline/SKILL.md 'enforce-classification' \
    | jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("enforce-classification")) | .hooks[].command')"
[ -n "$hook_command" ] || fatal "no enforce-classification hook registration found in /init-pipeline § 3"

hook_rel="${hook_command#*\"/}"                       # strip the "$CLAUDE_PROJECT_DIR"/ prefix
settings_rel="$(dirname "$(dirname "$hook_rel")")/settings.json"
if [ -z "$hook_rel" ] || [ "$hook_rel" = "$hook_command" ]; then
    fatal "could not read a project-relative hook path out of /init-pipeline's settings block"
fi

run_hook "$fixer_rel"
assert_eq 0 "$hook_status" "the armed lock permits a write to $fixer_rel, which opens it with no sub-agent behind it"

run_hook "$hook_rel"
assert_eq 0 "$hook_status" "…and a write to $hook_rel, so the session can rewrite its own gate"

run_hook "$settings_rel"
assert_eq 0 "$hook_status" "…and a write to $settings_rel, which deregisters the hook"

# The fourth route is not a path at all: the hook is only ever consulted for the
# tool calls its matcher names, so anything done from Bash — `sed -i`, `tee`, a
# heredoc, `printf >`, or `rm` on the stamp flag itself — is never presented to
# it. That is a property of the registration, so the registration is what is
# read.
hook_matcher="$(fenced_json_block init-pipeline/SKILL.md 'enforce-classification' \
    | jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("enforce-classification")) | .matcher')"
assert_eq "Write|Edit" "$hook_matcher" \
    "the hook is registered on Write|Edit only, so no Bash write is presented to it"

# -----------------------------------------------------------------------------

section "5. round trip: the five documented commands drive the hook"

# The load-bearing section. Every state change below is made by running text
# extracted from a skill, and every observation is made by running the hook.
# No flag path appears as a literal anywhere in it, so the five files can only
# stay green by continuing to agree with each other.
#
# /execute Step 6's removal is the fifth command and was the missing one. Without
# it this walk stamped a branch that still carried `.tdd-active` — a state the
# real pipeline destroys one step before /pre-merge runs — and every assertion
# after the stamp was answered by a marker that would not have been there. The
# sequence below is now the sequence the pipeline actually performs.

set_flags "$tdd_active"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "classified, before anything else: open"

run_documented "$proj" "$tdd_marker_remove" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /execute Step 6's rm: the branch is markerless, so the classification gate refuses"

run_documented "$proj" "$stamp_write" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /pre-merge Phase 4's touch: shut"

# On a markerless stamped branch, WHICH clause refuses is the whole finding. If
# clause 1 answers here, the lock's designed affordance never prints and the
# fixer below is refused too.
if grep -qF "$lock_msg" <<<"$hook_err"; then
    assert_eq "the lock" "the lock" "…and it is the lock that refuses, not the classification gate"
else
    assert_eq "the lock" "$hook_err" "…and it is the lock that refuses, not the classification gate"
fi

run_documented "$proj" "$fixer_write" "$proj"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "after /fix-findings' harness line: open for the fixer, with no classification marker in reach"

run_documented "$proj" "$fixer_remove" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /fix-findings Step 3's rm: shut again"

run_documented "$proj" "$stamp_remove" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /closeout Step 3's rm at merge: still refused, because the branch is markerless"

# Released means the LOCK stopped refusing, not that everything is permitted —
# the classification gate is a separate question and answers this one now.
if grep -qF "$class_msg" <<<"$hook_err"; then
    assert_eq "the classification gate" "the classification gate" \
        "…and the lock is released: the refusal is clause 1's, not the lock's"
else
    assert_eq "the classification gate" "$hook_err" \
        "…and the lock is released: the refusal is clause 1's, not the lock's"
fi

touch "$proj/$tdd_active"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "…and re-classifying the next slice's work reopens the gate with no stamp left to fight"

# -----------------------------------------------------------------------------

section "6. the \$CLAUDE_PROJECT_DIR fallback both skills wrote"

# /pre-merge's comment states the reason for the `:-` form outright: the
# variable is unset outside a Claude Code session, and an unguarded expansion
# would resolve to "/.claude" — a silent no-write that leaves the lock
# disengaged while everything above reports success. That is a claim about what
# a command does, so it is run rather than read. The run happens from a
# SUBDIRECTORY, because $PWD and `--show-toplevel` only differ there, and the
# difference is the whole reason `--show-toplevel` is in the line.

gitrepo="$scratch/gitrepo"
mkdir -p "$gitrepo/src"
printf 'export const x = 1\n' > "$gitrepo/src/service.ts"
if ! git -C "$gitrepo" init -q; then fatal "could not git init the scratch repo"; fi
if ! git -C "$gitrepo" add -A; then fatal "could not stage the scratch repo"; fi
if ! git -C "$gitrepo" -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
        commit -q --no-verify -m "fixture"; then
    fatal "could not commit in the scratch repo"
fi

status=0
run_documented "$gitrepo/src" "$stamp_write" "" || status=$?
assert_eq 0 "$status" "/pre-merge's write runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$stamp_rel" ]; then
    assert_eq "at the repo root" "at the repo root" "the fallback lands the flag where the hook would look, not beside \$PWD"
else
    assert_eq "at the repo root" "not written" "the fallback lands the flag where the hook would look, not beside \$PWD"
fi

status=0
run_documented "$gitrepo/src" "$stamp_remove" "" || status=$?
assert_eq 0 "$status" "/closeout's removal runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$stamp_rel" ]; then
    assert_eq "gone" "still present" "/closeout's removal reaches the same path /pre-merge's write created"
else
    assert_eq "gone" "gone" "/closeout's removal reaches the same path /pre-merge's write created"
fi

# The fixer flag runs the same gauntlet, and it is the one that failed it. Its
# harness line used to be cwd-relative (`mkdir -p .claude && touch
# .claude/.fix-findings-active`), so run from a subdirectory it wrote a flag the
# hook — which only ever looks under $CLAUDE_PROJECT_DIR — could not see. Every
# assertion in sections 3 and 5 stayed green, because both run with the variable
# set and the cwd already at the project root. Only the fallback case, from a
# subdirectory, can tell the two resolutions apart.

status=0
run_documented "$gitrepo/src" "$fixer_write" "" || status=$?
assert_eq 0 "$status" "/fix-findings' harness line runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$fixer_rel" ]; then
    assert_eq "at the repo root" "at the repo root" "the harness line lands the fixer flag where the hook would look, not beside \$PWD"
else
    assert_eq "at the repo root" "not written there" "the harness line lands the fixer flag where the hook would look, not beside \$PWD"
fi

status=0
remove_out="$( cd "$gitrepo/src" && env -u CLAUDE_PROJECT_DIR bash -c "$fixer_remove" 2>&1 >/dev/null )" || status=$?
assert_eq 0 "$status" "/fix-findings' Step 3 removal runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$fixer_rel" ]; then
    assert_eq "gone" "still present" "/fix-findings' removal reaches the same path its harness line created"
else
    assert_eq "gone" "gone" "/fix-findings' removal reaches the same path its harness line created"
fi

assert_eq "" "$remove_out" "…and says nothing on stderr when the flag was really there"

# A miss must be sayable. `rm -f` reports success on a removal that removed
# nothing, which reads identically to a removal that worked — and the state it
# hides is the open lock, the silent direction this whole mechanism exists to
# close. Run the same removal a second time, with the flag already gone.
status=0
miss_out="$( cd "$gitrepo/src" && env -u CLAUDE_PROJECT_DIR bash -c "$fixer_remove" 2>&1 >/dev/null )" || status=$?

if [ -n "$miss_out" ] && grep -qF "$fixer_rel" <<<"$miss_out"; then
    assert_eq "reported" "reported" "removing a fixer flag that is not there reports the miss, naming the path it looked at"
else
    assert_eq "reported" "silent (exit $status, stderr: ${miss_out:-empty})" \
        "removing a fixer flag that is not there reports the miss, naming the path it looked at"
fi

# -----------------------------------------------------------------------------

section "7. the stamp flag is written only if the PR body write succeeded"

# The comment beside /pre-merge's touch says the flag is written only after the
# stamp write succeeded, because "a flag written beside a stamp that aborted
# would lock the branch on the strength of a review nothing recorded." That
# sentence was half true. The READ half was guarded — `if ! gh pr view … ; then
# … exit 1; fi` — and the write half was a bare `gh pr edit` whose exit status
# nothing looked at, so a failing edit left no stamp in the PR body and a
# .review-stamped flag on disk. From outside, a branch locked by that flag is
# indistinguishable from one locked by a review that actually happened.
#
# So the block is RUN, whole and extracted verbatim, against a `gh` stub — once
# with an edit that fails and once with an edit that succeeds. `gh pr view`
# always answers with a non-empty body, so the read half's two guards pass and
# both runs reach the write half, which is the only half under test here.

stamprepo="$scratch/stamprepo"
mkdir -p "$stamprepo"
if ! git -C "$stamprepo" init -q; then fatal "could not git init the stamp scratch repo"; fi
printf 'export const x = 1\n' > "$stamprepo/service.ts"
if ! git -C "$stamprepo" add -A; then fatal "could not stage the stamp scratch repo"; fi
if ! git -C "$stamprepo" -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
        commit -q --no-verify -m "fixture"; then
    fatal "could not commit in the stamp scratch repo"
fi

ghbin="$scratch/ghbin"
mkdir -p "$ghbin"

stamp_block_status=0
run_stamp_block() {  # $1 = the exit status the stub's `pr edit` reports
    cat > "$ghbin/gh" <<STUB
#!/usr/bin/env bash
case "\$2" in
  view) printf '## Summary\n\nfixture body\n' ;;
  edit) exit $1 ;;
  *)    exit 9 ;;
esac
STUB
    chmod +x "$ghbin/gh"
    rm -f "$stamprepo/$stamp_rel"
    stamp_block_status=0
    ( cd "$stamprepo" \
        && PATH="$ghbin:$PATH" CLAUDE_PROJECT_DIR="$stamprepo" \
           bash -c "${stamp_block//<pr-number>/1}" ) >/dev/null 2>&1 || stamp_block_status=$?
}

run_stamp_block 1
assert_eq 1 "$stamp_block_status" "a failing \`gh pr edit\` aborts the block instead of running on"

if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "no flag" "flag written" "…and leaves no $stamp_rel behind, so nothing locks the branch on a stamp the PR never received"
else
    assert_eq "no flag" "no flag" "…and leaves no $stamp_rel behind, so nothing locks the branch on a stamp the PR never received"
fi

# The control. "No flag was written" would pass just as well for a block that
# never writes one, or for a run that died before it got there for some unrelated
# reason — so the same block, same fixture, with the edit succeeding, must write
# the flag. Without this run the assertion above measures nothing.
run_stamp_block 0
assert_eq 0 "$stamp_block_status" "a succeeding \`gh pr edit\` runs the block through to the flag"

if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "flag written" "flag written" "…and the flag is written on that path, which is what makes the abort above a measurement"
else
    assert_eq "flag written" "no flag" "…and the flag is written on that path, which is what makes the abort above a measurement"
fi

# -----------------------------------------------------------------------------

section "8. the breaker's copy is structurally unable to write to the branch"

# /fix-findings chooses `git archive` over `git worktree add` on the stated
# ground that it "writes a plain directory with no .git inside it, so 'the
# breaker cannot write to the branch' is structural rather than promised."
# Structural is a checkable word.

breaker_dir="$( cd "$gitrepo" && bash -c "$archive_block"$'\n''printf "%s" "$BREAKER_DIR"' )"

if [ -f "$breaker_dir/src/service.ts" ]; then
    assert_eq "extracted" "extracted" "the archive block extracts the committed tree"
else
    assert_eq "extracted" "empty" "the archive block extracts the committed tree"
fi

if [ -e "$breaker_dir/.git" ]; then
    assert_eq "no .git" "a .git is present" "the copy has no .git, so the breaker has no branch to write to"
else
    assert_eq "no .git" "no .git" "the copy has no .git, so the breaker has no branch to write to"
fi

rm -rf "$breaker_dir"

# …and it fails CLOSED. `git archive <unresolvable-rev> | tar -x` prints its
# `fatal:` to stderr and exits 0: without `pipefail` the pipeline reports tar's
# status, and tar succeeded at unpacking nothing. The block then hands the
# breaker an empty directory and a success, and a breaker that ran its mutation
# there could report a verdict on no tree at all — a green result that is green
# for a reason nobody checked, in the one skill whose thesis is that such a
# result is not self-validating.
#
# The revision is swapped for one that cannot resolve, which is the finding's own
# reproduction. Everything else about the block is the shipped text.
bogus_archive="${archive_block//git rev-parse HEAD/echo deadbeef}"
if [ "$bogus_archive" = "$archive_block" ]; then
    fatal "the archive block no longer resolves its revision with \`git rev-parse HEAD\` — update this control with it"
fi

status=0
bogus_out="$( cd "$gitrepo" && bash -c "$bogus_archive"$'\n''printf "%s" "$BREAKER_DIR"' 2>/dev/null )" || status=$?
assert_eq 1 "$status" "an unresolvable revision aborts the extraction rather than reporting success"
assert_eq "" "$bogus_out" "…and no directory path reaches the breaker, so there is no empty tree to run a mutation in"

# -----------------------------------------------------------------------------

section "9. apparatus: the refusal in section 3 measures the clause"

# A green suite proves nothing until a known-killable control has gone red
# through it. Point the lock's condition at a path that cannot exist — by
# substituting the flag's own name, taken from /pre-merge's touch — and the
# stamped write in section 3 must flip from refused to allowed. If it does not,
# every assertion above is passing for some other reason.

mutant="$scratch/mutant-hook.sh"
stamp_basename="${stamp_rel##*/}"
printf '%s' "${hook_body//$stamp_basename/$stamp_basename-absent}" > "$mutant"

status=0
bash -n "$mutant" || status=$?
assert_eq 0 "$status" "the control is still a valid script (a syntax error would fail for the wrong reason)"

set_flags "$tdd_active" "$stamp_rel"
if [ -f "$proj/$stamp_rel" ]; then
    assert_eq "stamped" "stamped" "the fixture reaches the state the control is about to be run against"
else
    assert_eq "stamped" "not stamped" "the fixture reaches the state the control is about to be run against"
fi

real_hook="$hook_file"
hook_file="$mutant"
run_hook "src/service.ts"
hook_file="$real_hook"
assert_eq 0 "$hook_status" "with the lock's condition pointed at a path that cannot exist, the same stamped write is allowed"

run_hook "src/service.ts"
assert_eq 2 "$hook_status" "and the unmutated hook refuses it again on the very next run"

# --- Control 2: the shipped defect, rebuilt and re-killed --------------------
#
# The control above proves clause 2's CONDITION is live. It cannot see the defect
# this section was extended for, because that defect was in the clauses' ORDER,
# and order is invisible to any fixture that leaves a classification marker lying
# around. So: strip the `.review-stamped` stand-down term out of clause 1 — built
# from /pre-merge's own flag path, not typed — and the hook becomes the version
# that shipped. Both halves of the finding must come back.

stand_down="[ ! -f \"\$CLAUDE_PROJECT_DIR/$stamp_rel\" ] && "
ordering_mutant="$scratch/ordering-mutant-hook.sh"
printf '%s' "${hook_body/"$stand_down"/}" > "$ordering_mutant"

if [ "$(grep -c '' <"$ordering_mutant")" -lt "$(grep -c '' <<<"$hook_body")" ] \
   || [ "$(wc -c <"$ordering_mutant")" -lt "$(printf '%s' "$hook_body" | wc -c)" ]; then
    assert_eq "removed" "removed" "the stand-down term was found in clause 1 and taken out"
else
    assert_eq "removed" "not found — clause 1 no longer carries the term in this shape" \
        "the stand-down term was found in clause 1 and taken out"
fi

status=0
bash -n "$ordering_mutant" || status=$?
assert_eq 0 "$status" "the ordering control is still a valid script"

real_hook="$hook_file"
hook_file="$ordering_mutant"

set_context "" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "without the stand-down: the /fix-findings fixer is refused despite holding its flag"

set_context "" "$stamp_rel"
run_hook "src/service.ts"
if grep -qF "$class_msg" <<<"$hook_err"; then
    assert_eq "clause 1's message" "clause 1's message" \
        "without the stand-down: the human is refused by the wrong clause, and /fix-findings is never named"
else
    assert_eq "clause 1's message" "$hook_err" \
        "without the stand-down: the human is refused by the wrong clause, and /fix-findings is never named"
fi

hook_file="$real_hook"

set_context "" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "and the shipped hook lets that same fixer write on the very next run"

# -----------------------------------------------------------------------------

section "10. neither flag can be committed into this repo"

# Both flags are transient by construction, which is the condition under which
# this pack tolerates filesystem state at all. A committed copy would hold the
# lock shut, or hold it open, across every future branch — so this is measured
# with git's own matcher rather than by reading .gitignore.

for flag in "$stamp_rel" "$fixer_rel"; do
    if git check-ignore -q "$flag"; then
        assert_eq "ignored" "ignored" "$flag is ignored by this repo"
    else
        assert_eq "ignored" "tracked" "$flag is ignored by this repo"
    fi
done

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
