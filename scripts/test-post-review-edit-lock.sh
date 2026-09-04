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
#
# WHAT SECTION 11 ADDS TO THAT LIMIT, because the limit had nothing behind it.
# Sections 1-10 all assume the current hook is installed. In every project that
# ran /init-pipeline before #327 it is not, and /execute Step 0's gate was
# existence-only — the file is there, /init-pipeline is never re-invoked, and
# the shipped lock is inert in exactly the silent direction named above. Section
# 11 runs Step 0's gate against three installs (none, pre-lock, current) and
# requires it to separate them. It still cannot prove a downstream project runs
# the gate; it does prove the gate can tell the two installs apart, which is the
# half that lives in this repo's text.
#
# AND WHAT SECTION 11 DECLARES, because a gate named for currency does not have
# it. The gate's matcher is one literal, the lock's own flag path, so it knows
# exactly one version boundary: the term is absent on every pre-lock install and
# present on every install from the lock onward, forever. A hook change made
# AFTER that boundary — clause ordering, a message, a new skip pattern — leaves
# the term in place, so the gate reports the same verdict for it as for a hook
# that is genuinely current, and the change is never distributed. That is root
# cause #2 of
# docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md:
# zero hits is the mechanism's healthy state, so its silence carries no signal.
# That entry rules out widening the matcher past what
# it can do accurately and names the escape — make the narrowness DECLARED AND
# SELF-TESTED — so section 11 takes it in three moves: /execute Step 0's third
# verdict is named for the term it found rather than for currency and states the
# limit in prose; the blindness is asserted here against a post-lock hook that
# differs from the shipped body; and the shipped body is digested, which is the
# signal at the crossover the entry says a green run does not carry.
#
# AND WHAT SECTION 14 ADDS, which is about the sentence rather than the gate.
# Section 11 gave Step 0 a SECOND reason to call /init-pipeline. Adding a
# condition to a prose contract does not delete the sentence stating the old
# one, so the commit that added it updated seven sites and left six restating
# absence-alone — docs/restated-claims.md § "Why an additive edit is not a
# replacement", with that file's census tell attached: every site the first
# pass found shared one wording. Section 14 walks every tracked file for
# sentences that DO the job — name the skill, say /execute invokes it, state
# the absence half — and requires the pre-lock half beside them.

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
#
# WHAT THESE TWO CANNOT ANSWER, and the reason the route below is read from
# somewhere else. Both are copies of the strings under test, so matching a
# refusal against them measures only WHICH clause spoke — never WHAT it said.
# Deleting `Either invoke /fix-findings <numbers>, or ` from clause 2's message
# leaves a hook that still refuses, still refuses with clause 2's remaining
# bytes, and no longer names the one route out; every row here stayed green
# through exactly that edit. So the route is derived from /fix-findings' own
# frontmatter name, which is not the text under test and which a rename of the
# skill moves in lockstep with every other inventory surface.
class_msg="$(grep -o '"reason":"BLOCKED:[^"]*"' <<<"$hook_body" | sed -n 1p)"
lock_msg="$(grep -o '"reason":"BLOCKED:[^"]*"' <<<"$hook_body" | sed -n 2p)"
if [ -z "$class_msg" ] || [ -z "$lock_msg" ]; then
    fatal "could not read two BLOCKED reasons out of the hook body"
fi
[ "$class_msg" != "$lock_msg" ] || fatal "the hook's two refusals are byte-identical — 'which clause refused' is unmeasurable"

fixer_route="/$(sed -n 's/^name: *//p' fix-findings/SKILL.md | sed -n 1p)"
if [ "$fixer_route" = "/" ]; then
    fatal "could not read a skill name out of fix-findings/SKILL.md frontmatter"
fi

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

    # The label claims two things and both are checked: the LOCK is what
    # refused (matched against $lock_msg), and the refusal names the route the
    # human is supposed to take (matched against $fixer_route, which comes from
    # the skill rather than from the message). Dropping the second term is what
    # made this row vacuous once — see the note beside $lock_msg above.
    if grep -qF "$lock_msg" <<<"$hook_err" && grep -qF "$fixer_route" <<<"$hook_err"; then
        assert_eq "the lock refused it, naming $fixer_route" \
            "the lock refused it, naming $fixer_route" \
            "the refusal routes the human to $fixer_route, $where"
    else
        assert_eq "the lock refused it, naming $fixer_route" "$hook_err" \
            "the refusal routes the human to $fixer_route, $where"
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
# Same two halves as section 3's row, in the negative: clause 1 is what answers,
# and the route never appears. The second term is checked for the same reason it
# is checked there — a $class_msg match alone says which clause spoke, not what
# the human was left holding, and "never named" is the half of this label that
# describes the harm.
if grep -qF "$class_msg" <<<"$hook_err" && ! grep -qF "$fixer_route" <<<"$hook_err"; then
    assert_eq "clause 1's message, naming no route" "clause 1's message, naming no route" \
        "without the stand-down: the human is refused by the wrong clause, and $fixer_route is never named"
else
    assert_eq "clause 1's message, naming no route" "$hook_err" \
        "without the stand-down: the human is refused by the wrong clause, and $fixer_route is never named"
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

section "11. /execute Step 0's gate separates a pre-lock install from a current one"

# THE GAP THIS CLOSES. #327 shipped the lock as a hook clause and left /execute
# Step 0's gate existence-only: "if .claude/hooks/enforce-classification.sh does
# not exist, invoke /init-pipeline". In a project that ran /init-pipeline before
# the lock, the file exists, so /init-pipeline is never re-invoked and the hook
# keeps only clause 1. /pre-merge still writes the stamp flag and /fix-findings
# still writes the fixer flag; the pre-lock hook reads neither. The fixer is then
# refused by clause 1 under a message naming /tdd — the defect commit 93f5453
# fixed INSIDE the hook, reproduced verbatim in every repo that does not receive
# the new hook. Nothing above reaches it, because everything above installs the
# current hook by construction.
#
# The fixture is BUILT FROM THE SHIPPED HOOK, not typed: take clause 1's
# stand-down term back out (the surgery section 9's second control performs),
# then delete clause 2's if…fi block and the comment lines that named the two
# flags. What comes out is not required to be byte-identical to the hook on
# prod — it is required to be a hook with no stamp-flag term in it that still
# reproduces the refusal, and both of those are asserted before the gate is
# pointed at it.

hooks_gate="$(fenced_bash_block execute/SKILL.md 'hooks-stale' || true)"
[ -n "$hooks_gate" ] || fatal "no hook-staleness gate found in execute/SKILL.md Step 0 — either the gate moved or its fence changed; update this suite with it"

status=0
bash -n <<<"$hooks_gate" || status=$?
assert_eq 0 "$status" "the gate /execute Step 0 documents parses as bash"

# Two derived paths the gate has to agree with, so a rename in either writer
# fails here rather than turning the gate into a check that can never fire:
# the stamp flag (read out of /pre-merge's touch, above) and the hook script
# (read out of /init-pipeline's own settings registration, in section 4).
# Backslashes are stripped because the gate carries the path as a grep BRE.
gate_plain="${hooks_gate//\\/}"

if grep -qF "$stamp_rel" <<<"$gate_plain"; then
    assert_eq "$stamp_rel" "$stamp_rel" "the gate tests for the same stamp-flag path /pre-merge writes"
else
    assert_eq "$stamp_rel" "(absent from the gate)" "the gate tests for the same stamp-flag path /pre-merge writes"
fi

if grep -qF "$hook_rel" <<<"$gate_plain"; then
    assert_eq "$hook_rel" "$hook_rel" "the gate looks at the same hook path /init-pipeline registers"
else
    assert_eq "$hook_rel" "(absent from the gate)" "the gate looks at the same hook path /init-pipeline registers"
fi

# --- The pre-lock install, rebuilt from the shipped hook ---------------------

prelock_standdown="[ ! -f \"\$CLAUDE_PROJECT_DIR/$stamp_rel\" ] && "
prelock_body="${hook_body/"$prelock_standdown"/}"

if [ "$(printf '%s' "$prelock_body" | wc -c)" -lt "$(printf '%s' "$hook_body" | wc -c)" ]; then
    assert_eq "removed" "removed" "clause 1's stand-down term was found and taken back out"
else
    assert_eq "removed" "not found — clause 1 no longer carries the term in this shape" \
        "clause 1's stand-down term was found and taken back out"
fi

prelock_body="$(awk -v needle="-f \"\$CLAUDE_PROJECT_DIR/$stamp_rel\"" \
                    -v sb="${stamp_rel##*/}" -v fb="${fixer_rel##*/}" '
    index($0, needle)                                   { skip = 1 }
    skip                                                { if ($0 == "fi") skip = 0; next }
    /^[[:space:]]*#/ && (index($0, sb) || index($0, fb)) { next }
                                                        { print }
' <<<"$prelock_body")"

prelock="$scratch/prelock-hook.sh"
printf '%s\n' "$prelock_body" > "$prelock"

assert_eq 0 "$(grep -c -- "${stamp_rel##*/}" "$prelock" || true)" \
    "the rebuilt pre-lock hook mentions the stamp flag nowhere at all"

status=0
bash -n "$prelock" || status=$?
assert_eq 0 "$status" "the rebuilt pre-lock hook is still a valid script"

# The apparatus check for this section: the fixture must actually exhibit the
# finding, or the gate below is being asked to detect nothing. Drive it in the
# state the pipeline reaches — markerless (/execute Step 6 has run), stamped
# (/pre-merge Phase 4), fixer flag held (/fix-findings) — and require the two
# halves back: refused, by clause 1, with the fixer's route never named.
real_hook="$hook_file"
hook_file="$prelock"
set_context "" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
hook_file="$real_hook"

assert_eq 2 "$hook_status" "the pre-lock hook refuses the /fix-findings fixer that holds its own flag"
if grep -qF "$class_msg" <<<"$hook_err" && ! grep -qF "$fixer_route" <<<"$hook_err"; then
    assert_eq "clause 1's message, naming no route" "clause 1's message, naming no route" \
        "…by the classification clause, and $fixer_route is never named — the state every pre-lock project is in"
else
    assert_eq "clause 1's message, naming no route" "$hook_err" \
        "…by the classification clause, and $fixer_route is never named — the state every pre-lock project is in"
fi

# --- The gate, run against all three installs -------------------------------

gate_proj="$scratch/gate-project"
mkdir -p "$gate_proj/$(dirname "$hook_rel")"
git init -q "$gate_proj" >/dev/null 2>&1 || fatal "could not init a scratch git repo for the gate's fallback row"

run_gate() {  # $1 = CLAUDE_PROJECT_DIR, or "" to exercise the git-toplevel fallback
    if [ -n "$1" ]; then
        ( cd "$gate_proj" && CLAUDE_PROJECT_DIR="$1" bash -c "$hooks_gate" )
    else
        ( cd "$gate_proj" && env -u CLAUDE_PROJECT_DIR bash -c "$hooks_gate" )
    fi
}

rm -f "$gate_proj/$hook_rel"
assert_eq "hooks-absent" "$(run_gate "$gate_proj")" \
    "no hook installed: the gate reports it, and /init-pipeline scaffolds"

cp "$prelock" "$gate_proj/$hook_rel"
assert_eq "hooks-stale" "$(run_gate "$gate_proj")" \
    "the pre-lock hook installed: the gate fires, and /init-pipeline re-scaffolds"

cp "$hook_file" "$gate_proj/$hook_rel"
assert_eq "hooks-lock-present" "$(run_gate "$gate_proj")" \
    "the shipped hook installed: the gate stays silent"

# Same three-way separation with the variable the harness may not set, since the
# gate wrote the same ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
# fallback section 6 measures for /pre-merge and /fix-findings.
assert_eq "hooks-lock-present" "$(run_gate "")" \
    "…and with \$CLAUDE_PROJECT_DIR unset, the gate resolves the project by git toplevel"

cp "$prelock" "$gate_proj/$hook_rel"
assert_eq "hooks-stale" "$(run_gate "")" \
    "…and still fires on the pre-lock hook through that same fallback"

# --- Every verdict the gate emits is a verdict Step 0's prose defines --------
#
# The verdicts are DERIVED from the block rather than listed here, so renaming
# one in the code fence and leaving the paragraph describing the old name fails
# here. This is the routing surface: an agent reads a token out of the gate and
# looks for what to do with it, and a token the prose never mentions routes
# nowhere.

gate_verdicts="$(grep -oE 'echo "[a-z-]+"' <<<"$hooks_gate" | sed -E 's/^echo "(.*)"$/\1/' | sort -u)"
[ "$(grep -c '' <<<"$gate_verdicts")" -ge 3 ] || fatal "read fewer than three verdicts out of Step 0's gate — the gate has three branches, so that extractor no longer matches its echoes"

execute_prose="$(awk '/^```/ { inblock = ! inblock; next } ! inblock' execute/SKILL.md)"

while read -r verdict; do
    [ -n "$verdict" ] || continue
    if grep -qF -- "\`$verdict\`" <<<"$execute_prose"; then
        assert_eq "documented" "documented" "Step 0's prose says what to do with $verdict, which its gate emits"
    else
        assert_eq "documented" "unmentioned" "Step 0's prose says what to do with $verdict, which its gate emits"
    fi
done <<<"$gate_verdicts"

# --- The narrowness, declared in Step 0's prose and asserted here ------------
#
# The three rows above are the whole of what the gate can do, and the third one
# is the one that over-reads: it fired on the shipped hook, but it fires on ANY
# hook carrying the lock's term. Section 9's ordering control is exactly such a
# hook — the shipped body with clause 1's stand-down taken out, which is the
# version that shipped before 93f5453 and which section 9 has already proven
# reproduces both halves of that defect. So it is a hook that is demonstrably
# not current, and the gate is required here to call it lock-present anyway.
#
# This assertion is a REQUIRED NON-MATCH, and it goes red the day somebody
# widens the gate to a second boundary term. That is the point: the limit stops
# being an assumption nobody has to revisit and becomes a line that has to be
# rewritten deliberately, together with the paragraph in /execute Step 0 that
# states it. Same shape as the required non-match in test-oracle-table-
# coverage.sh, and for the same reason — a floor asserts the repo still has the
# defect, a self-test asserts the mechanism still behaves as documented.

if [ "$(cat "$ordering_mutant")" != "$hook_body" ]; then
    assert_eq "differs" "differs" "the post-lock control is a different hook body from the shipped one"
else
    assert_eq "differs" "identical" "the post-lock control is a different hook body from the shipped one"
fi

if grep -qF -- "${stamp_rel##*/}" "$ordering_mutant"; then
    assert_eq "carries the term" "carries the term" "…and still carries the lock's flag path, which is the only thing the gate reads"
else
    assert_eq "carries the term" "absent" "…and still carries the lock's flag path, which is the only thing the gate reads"
fi

cp "$ordering_mutant" "$gate_proj/$hook_rel"
assert_eq "hooks-lock-present" "$(run_gate "$gate_proj")" \
    "DECLARED LIMIT: a hook change made after the lock boundary is invisible to this gate, so it reports the same verdict as for the shipped body"

# --- The signal at the crossover: the shipped hook body cannot change quietly -
#
# The limit above says a later hook change is not distributed. Nothing so far
# would tell the author of that change, because a green suite looks the same on
# both sides of the crossover. A digest of the hook body is the cheapest thing
# that does: it is red exactly when the hook changes, and its message is the
# decision that has to be made at that moment. The value is restated rather than
# derived because there is nothing to derive it from — it is a baseline, "what
# the hook looked like when the gate was last thought about," which no state in
# this tree carries. Restating it is safe in the way a coverage list is not: it
# has one reader, and being stale makes it LOUD rather than silent.

if command -v shasum >/dev/null 2>&1; then
    digest_cmd=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
    digest_cmd=(sha256sum)
else
    fatal "neither shasum nor sha256sum is on PATH — the hook-body tripwire in section 11 cannot run"
fi

# The digest of init-pipeline § 2's hook body as of the commit that wrote
# /execute Step 0's "What this gate cannot see" paragraph.
hook_body_digest="212fd2c01346d7b8a515bc13380aa10ed929f87957fd9ed0e5603b3eb811b954"

assert_eq "$hook_body_digest" "$(printf '%s' "$hook_body" | "${digest_cmd[@]}" | cut -d' ' -f1)" \
    "the shipped hook body is the one the declared limit was written against — if you changed it, this gate does NOT distribute that change to upgraded projects: give the new boundary its own elif term in /execute Step 0, then update hook_body_digest here"

# -----------------------------------------------------------------------------

section "12. /init-pipeline § 2 gives the gate's two verdicts disjoint install-time paths"

# THE DRIFT CLASS THIS CLOSES, which is not the hook's behavior but the prose
# that tells a downstream agent how to write it. Section 11 proves the gate can
# separate a pre-lock install from a current one. It cannot see what happens
# next: both verdicts route to the same call, `invoke /init-pipeline now`, so
# § 2 is entered in two different situations and has to hold two different
# rules — ask/default on a fresh install, carry the installed list over on a
# re-scaffold. The lock upgrade added the second rule as a new paragraph and
# left the first one unconditional, which is docs/restated-claims.md
# § "Why an additive edit is not a replacement": both sentences present, both
# reading as true, and the one an agent reaches first re-defaults the trigger
# surface of every pre-lock project — the single harm the new paragraph exists
# to prevent, on exactly the population it was written for.
#
# So the two verdicts are DERIVED by running the gate against the fixtures
# section 11 built, and § 2's paths are required to partition them: each
# verdict named under exactly one path, no path claiming both, and no
# instruction touching IMPL_PATTERNS floating above the path labels where it
# reads as applying to every run.

rm -f "$gate_proj/$hook_rel"
v_absent="$(run_gate "$gate_proj")"
cp "$prelock" "$gate_proj/$hook_rel"
v_stale="$(run_gate "$gate_proj")"

if [ -z "$v_absent" ] || [ -z "$v_stale" ] || [ "$v_absent" = "$v_stale" ]; then
    fatal "the gate did not yield two distinct verdicts to partition (got '$v_absent' and '$v_stale')"
fi

install_block="$(awk '
    /^\*\*Install-time:/ { on = 1 }
    on && /^```bash$/     { exit }
    on                    { print }
' init-pipeline/SKILL.md)"
[ -n "$install_block" ] || fatal "no **Install-time: block found in init-pipeline/SKILL.md § 2 — either it moved or its opening changed; update this suite with it"

# A paragraph is blank-line-separated, and it is accumulated into one unwrapped
# string before anything is matched against it — not read with RS="" and matched
# against $0, which is test-guards-can-fire.sh detector B's shape: a wrap landing
# inside the anchor makes the match miss and the assertion pass for the wrong
# reason. "A path" is the bolded label plus the prose that rides with it, so the
# intro paragraph that names both verdicts to explain the fork is not itself a
# path and is not counted as one.
counts="$(awk -v a="$v_absent" -v b="$v_stale" '
    function flush(   is_path) {
        if (para == "") return
        is_path = (para ~ /^\*\*Path /)
        if (is_path) {
            labeled = 1
            if (index(para, a)) n_a++
            if (index(para, b)) n_b++
            if (index(para, a) && index(para, b)) n_both++
        }
        if (index(para, "IMPL_PATTERNS") && ! labeled) n_loose++
        para = ""
    }
    /^[[:space:]]*$/ { flush(); next }
                     { para = (para == "" ? $0 : para " " $0) }
    END              { flush(); printf "%d %d %d %d\n", n_a + 0, n_b + 0, n_both + 0, n_loose + 0 }
' <<<"$install_block")"
read -r n_absent n_stale n_both n_loose <<<"$counts"

assert_eq 1 "$n_absent" "exactly one path in § 2 is keyed to $v_absent"
assert_eq 1 "$n_stale"  "exactly one path in § 2 is keyed to $v_stale"
assert_eq 0 "$n_both"   "no single path claims both verdicts — the antecedent that covered both is what shipped the conflict"
assert_eq 0 "$n_loose"  "no unlabeled paragraph above the paths instructs on IMPL_PATTERNS"

# --- Path C's surgery instruction, checked against the hook it operates on ---
#
# The instruction is the only thing telling a downstream agent what to look for
# in the file already installed, and it shipped a count the pre-lock hook does
# not have: "replace only the two marker-check clauses" when that hook carries
# one. The second clause is what the upgrade ADDS. A count is unanchorable in
# somebody else's repo anyway — the agent cannot tell a miscount from a hook
# that was customized — so the prose now names a start anchor and an end anchor,
# and both are read back out of it here and required to exist in the pre-lock
# hook section 11 rebuilt AND in the shipped hook the surgery installs. Naming a
# landmark the installed file does not have fails here rather than stranding an
# agent mid-edit in a project nobody in this repo can see.

surgery="$(grep -o 'Replace everything from[^.]*\.' <<<"$install_block" || true)"
[ -n "$surgery" ] || fatal "no 'Replace everything from …' surgery instruction found in § 2's Path C — reword it back or update this suite with it"

# shellcheck disable=SC2016  # the backticks are markdown code-span delimiters being matched in prose, not command substitution
surgery_spans="$(grep -o '`[^`]*`' <<<"$surgery" | tr -d '`')"
surgery_start="$(sed -n 1p <<<"$surgery_spans")"
surgery_end="$(sed -n 2p <<<"$surgery_spans")"
if [ -z "$surgery_start" ] || [ -z "$surgery_end" ]; then
    fatal "Path C's surgery instruction no longer names two backticked anchors"
fi

for subject in "the pre-lock hook the instruction operates on:$prelock_body" "the shipped hook it installs:$hook_body"; do
    label="${subject%%:*}"
    text="${subject#*:}"
    if grep -qF -- "$surgery_start" <<<"$text"; then
        assert_eq "present" "present" "$label starts at the '$surgery_start' anchor Path C names"
    else
        assert_eq "present" "absent" "$label starts at the '$surgery_start' anchor Path C names"
    fi
    assert_eq "$surgery_end" "$(sed -n '$p' <<<"$text")" "…and ends at the '$surgery_end' Path C names"
done

# The replaced/added split the instruction now states instead of a bare count.
# A marker-check clause is an `if` testing a flag under $CLAUDE_PROJECT_DIR.
# shellcheck disable=SC2016  # `$CLAUDE_PROJECT_DIR` is the literal text being counted in the hook, not an expansion
count_marker_clauses() { grep -c '^if \[.*\$CLAUDE_PROJECT_DIR' <<<"$1" || true; }

assert_eq 1 "$(count_marker_clauses "$prelock_body")" \
    "the pre-lock hook carries one marker-check clause — the count Path C used to call two"
assert_eq 2 "$(count_marker_clauses "$hook_body")" \
    "…and the shipped hook carries two, so the surgery replaces one and adds one"

# -----------------------------------------------------------------------------

section "13. /init-pipeline § 2 routes a run with nobody to ask past the sections that ask"

# THE DRIFT CLASS. Section 12 pinned that § 2's three paths partition the gate's
# two verdicts. It says nothing about where a path GOES afterwards, and Path C's
# closing clause sent the re-scaffold on "through § 6" — back through § 4, which
# holds for a confirmation before invoking /setup-pre-commit, and § 5, which asks
# whether to install the optional quality gate. On a pre-lock project both were
# answered at its own install, and on the run that reaches them neither is
# answerable: /execute Step 0 holds Step 1 until this skill reports, and an AFK
# Ralph iteration drives `claude --message` with nobody at the keyboard. § 3
# ("merge — do not overwrite") and § 6 ("if not already present") were guarded
# against re-entry and § 4 and § 5 were not, so the guard covered the two
# sections that did not need it.
#
# So the asking sections are DERIVED — every section below § 2 whose prose waits
# on a human — and three things are then required of the text: § 2's per-path
# rule names each of them, each of them points back at that rule, and no path
# paragraph routes anywhere on its own, because a path that carries its own
# forward instruction is how the contradicting sentence got in. Adding a sixth
# section that asks a question, and not dispositioning it in the rule, fails here.
#
# THE LIMIT: the asking set is detected by phrasing. A section that starts
# waiting on a human in words this detector does not recognize drops out of the
# set silently, and nothing here would notice. The detector fatals on an empty
# set, which catches the total-rewrite case; it cannot catch a single new phrasing.

ip_skill="init-pipeline/SKILL.md"

# § 2 is excluded by construction: it is the router, and Path A's question is
# the thing the rule dispositions rather than a section the rule sends a run to.
asking_sections="$(awk '
    function flush() {
        if (n >= 3 && body ~ /[Aa]sk the user|[Aa]sk for confirmation|[Aa]fter user confirms/) print n
    }
    /^### [0-9]+\./ { flush(); n = $2 + 0; body = ""; next }
                    { body = body " " $0 }
    END             { flush() }
' "$ip_skill")"
[ -n "$asking_sections" ] || fatal "no section below /init-pipeline § 2 reads as waiting on a human — either the asks are gone or their phrasing moved; check which before updating this suite"

rule_para="$(awk '
    function flush() { if (para ~ /^\*\*The rest of the run/) { print para; found = 1; exit } para = "" }
    /^[[:space:]]*$/ { flush(); next }
                     { para = (para == "" ? $0 : para " " $0) }
    END              { if (! found) flush() }
' "$ip_skill")"
[ -n "$rule_para" ] || fatal "no '**The rest of the run, per path.**' rule found in init-pipeline/SKILL.md § 2 — either it moved or its opening changed; update this suite with it"

# The pointer the asking sections must carry is read out of the rule's own
# bolded lead-in, not typed here, so renaming the rule renames what is required
# of them and this stays one statement rather than three.
rule_anchor="$(sed -E 's/^\*\*([^*]+)\.\*\*.*/\1/' <<<"$rule_para")"
[ "$rule_anchor" != "$rule_para" ] || fatal "could not read the rule's bolded lead-in back out of it"

section_body() {  # $1 = section number, from init-pipeline/SKILL.md
    awk -v want="$1" '
        /^### [0-9]+\./ { n = $2 + 0 }
        n == want       { print }
    ' "$ip_skill"
}

# Reuses section 12's install_block, so the paths are read from § 2 alone.
path_paras="$(awk '
    function flush() { if (para ~ /^\*\*Path /) print para; para = "" }
    /^[[:space:]]*$/ { flush(); next }
                     { para = (para == "" ? $0 : para " " $0) }
    END              { flush() }
' <<<"$install_block")"
[ -n "$path_paras" ] || fatal "no **Path paragraphs extracted from § 2's install block"
path_letters="$(grep -oE '^\*\*Path [A-Z]' <<<"$path_paras" | grep -oE '[A-Z]$')"
[ -n "$path_letters" ] || fatal "no path labels read back out of § 2's path paragraphs"

# Every (path, asking section) pair has to be dispositioned, not merely
# mentioned somewhere in the rule. Checking presence in the whole paragraph
# passes on a rule that names § 5 once while saying nothing about what Path C
# does with it — which is the state the section-12-shaped assertion left
# reachable, and the exact shape of the defect this section exists to catch.
while read -r letter; do
    [ -n "$letter" ] || continue
    clause="$(awk -v want="$letter" '
        { n = split($0, part, /On \*\*Path /)
          for (i = 2; i <= n; i++) if (substr(part[i], 1, 1) == want) printf "%s", part[i] }
    ' <<<"$rule_para")"
    if [ -z "$clause" ]; then
        assert_eq "dispositioned" "absent" "§ 2's rule says what Path $letter does after § 2"
        continue
    fi
    while read -r n; do
        [ -n "$n" ] || continue
        if grep -qF -- "§ $n" <<<"$clause"; then
            assert_eq "dispositioned" "dispositioned" "§ 2's rule says what Path $letter does with § $n, which waits on a human answer"
        else
            assert_eq "dispositioned" "unmentioned" "§ 2's rule says what Path $letter does with § $n, which waits on a human answer"
        fi
    done <<<"$asking_sections"
done <<<"$path_letters"

while read -r n; do
    [ -n "$n" ] || continue
    if grep -qiF -- "$rule_anchor" <<<"$(section_body "$n")"; then
        assert_eq "points back" "points back" "§ $n points back at '$rule_anchor' before asking anything"
    else
        assert_eq "points back" "silent" "§ $n points back at '$rule_anchor' before asking anything"
    fi
done <<<"$asking_sections"

# No path paragraph may name a numbered section. Routing is stated once, in the
# rule; a path that also routes is two sentences both reading as true, which is
# what "then continue through § 6" was beside a Path C that must not re-enter
# § 4 or § 5.

assert_eq "" "$(grep -oE '§+ [0-9]+' <<<"$path_paras" | paste -sd, - || true)" \
    "no path paragraph routes to a numbered section on its own — the per-path rule is the only router"

# -----------------------------------------------------------------------------

section "14. Every site stating Step 0's auto-invoke condition states both halves of it"

# THE DRIFT CLASS, which is not the gate's behavior but the sentence describing
# it. Section 11 gave Step 0 a second reason to call /init-pipeline: the hook
# being present but pre-lock, alongside the hook being absent. That is an
# additive edit to a prose contract, and docs/restated-claims.md § "Why an
# additive edit is not a replacement" is exactly what followed — the commit
# updated seven sites and left six stating the superseded one-condition rule,
# one of them the skill's own frontmatter `description`, which CLAUDE.md
# § "Editing Skills" makes the surface that decides when the skill triggers. All
# six read as true. None of them fails anything. A reader who lands on one
# concludes a pre-lock project needs no re-scaffold, which is the population the
# second condition was written for.
#
# THE CENSUS TELL, from the same file § "The census comes before the remedy":
# every site the first pass found shared one wording. The seven updated sites
# all carry "is missing —"; the six missed ones do not, and two of them were not
# in a SKILL.md at all. So this detector keys on what the sentence DOES — names
# the scaffolding skill, says /execute invokes it, and states the absence half
# of the condition — rather than on any phrasing the known sites happen to
# share, and it runs over the whole tracked tree rather than the files the diff
# touched.
#
# THE LIMIT, declared rather than discovered later. The second half is
# recognized by four terms: the stamp flag's path and the gate's stale verdict,
# both DERIVED above from the subject rather than typed, plus the two prose
# names the lock goes by. A site that states the pre-lock condition in words
# none of those four reach drops out silently and passes green. That is the
# same narrowness section 11 declares for the gate itself, and the response is
# the same: the detector carries planted positives and near-misses below, and a
# floor on the two-condition sites so an empty population cannot read as clean.

census_pop="$scratch/census-population"
census_targets="$scratch/census-manifest-targets"

# Excluded: dated history (CHANGELOG.md and docs/solutions/ record what was true
# then, and rewriting either would be a lie about the past), generated copies
# (manifest targets, regenerated by sync-skill-references.sh from sources that
# are themselves scanned, and held by the check-skill-references CI job), and
# this file, which plants offending strings as fixtures immediately below.
awk '!/^#/ && NF == 2 { split($1, a, "/"); print $2 "/references/" a[length(a)] }' \
    scripts/skill-references.manifest | sort -u > "$census_targets"

git ls-files \
    | grep -v '^CHANGELOG\.md$' \
    | grep -v '^docs/solutions/' \
    | grep -v '^scripts/test-post-review-edit-lock\.sh$' \
    | grep -v -F -x -f "$census_targets" \
    > "$census_pop"

census_count="$(grep -c . "$census_pop" || true)"
if [ "$census_count" -lt 100 ]; then
    fatal "census population has $census_count file(s); expected at least 100. git ls-files or the exclusion filtering broke, and a vacuous pass is the failure this section exists to prevent"
fi

# mode=one   → sites stating the absence half and NOT the pre-lock half (must be empty)
# mode=both  → sites stating both halves (floored, so the detector cannot go
#              silent because its terms stopped matching anything)
census_sites() {  # $1 = mode; stdin = path:lineno:text triples
    awk -v mode="$1" -v stamp="$stamp_rel" -v stale="$v_stale" -v ipfile="$ip_skill" '
        {
            if (! match($0, /^[^:]+:[0-9]+:/)) next
            loc  = substr($0, 1, RLENGTH - 1)
            text = substr($0, RLENGTH + 1)
            split(loc, part, ":")
            path = part[1]

            # (1) names the skill being invoked — or IS the skill, which is how
            #     the frontmatter description escaped a name-keyed search.
            if (index(text, "/init-pipeline") == 0 && path != ipfile) next
            # (2) says /execute invokes it rather than merely mentioning it.
            if (text !~ /[Aa]uto-invoke|[Aa]utomatically invoked|automatically via/) next
            # (3) states the absence half of the condition.
            if (text !~ /missing/) next

            lower = tolower(text)
            both = (index(text, stamp) || index(text, stale) \
                    || index(lower, "pre-lock") || index(lower, "post-review edit lock"))

            if (mode == "both") { if (both)  print loc }
            else                { if (! both) print loc ": " text }
        }'
}

section "14a. Detector self-tests"

# The shipped defect, in each of the three shapes it took. The second carries no
# "/init-pipeline" at all — it is the frontmatter of the skill itself, and a
# detector keyed only on the name reports it clean.
planted="execute/SKILL.md:601:- **Auto-invokes:** \`/init-pipeline\` when enforcement hooks are missing, \`/setup-ralph-loop\` when the task comes from a multi-slice GitHub issue"
assert_eq "true" "$([ -n "$(printf '%s\n' "$planted" | census_sites one)" ] && echo true || echo false)" \
    "detector flags /execute's Handoff line stating only the absence half"

planted="$ip_skill:3:description: \"Infrastructure skill for scaffolding pipeline enforcement into a project. Run once per project, auto-invoked by /execute if hooks are missing.\""
assert_eq "true" "$([ -n "$(printf '%s\n' "$planted" | census_sites one)" ] && echo true || echo false)" \
    "…and the skill's own frontmatter description, which names no /init-pipeline for a name-keyed search to find"

planted="docs/using-this-pack.md:162:- \`/init-pipeline\` (orchestrates the others — auto-invoked by \`/execute\` when hooks are missing)"
assert_eq "true" "$([ -n "$(printf '%s\n' "$planted" | census_sites one)" ] && echo true || echo false)" \
    "…and a docs/ site outside the SKILL.md file class the first census stayed inside"

# Near-misses. Each is a real line from the tree that a looser predicate flags.
planted="CLAUDE.md:42:- \`/init-pipeline\` is auto-invoked by \`/execute\` Step 0 when \`.claude/hooks/enforce-classification.sh\` is missing, or when it exists but does not read \`$stamp_rel\`"
assert_eq "" "$(printf '%s\n' "$planted" | census_sites one)" \
    "detector silent on a site that states both halves"

planted="README.md:85:| [init-pipeline](init-pipeline/) | Scaffold pipeline enforcement — Claude Code hooks, git guardrails, pre-commit setup (auto-invoked by \`/execute\`) |"
assert_eq "" "$(printf '%s\n' "$planted" | census_sites one)" \
    "…on a mention that names no condition at all"

planted="$ip_skill:45:**Path B — no hook installed, and \`/init-pipeline\` is running non-interactively** (auto-invoked by \`/execute\` Step 0 on a project whose hooks gate reported \`$v_absent\`)."
assert_eq "" "$(printf '%s\n' "$planted" | census_sites one)" \
    "…on § 2's Path B, which describes one verdict's path rather than stating the condition"

planted="execute/SKILL.md:601:- **Auto-invokes:** \`/setup-ralph-loop\` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist, and \`/pre-merge\` when hooks are missing"
assert_eq "" "$(printf '%s\n' "$planted" | census_sites one)" \
    "…and on a sibling skill's auto-invoke condition, which this detector does not police"

section "14b. The census, over every tracked file"

# The set-membership pins: three files the detector must actually be reading,
# one per file class the first census failed to leave.
# coverage: enumerated — the three file classes the missed sites lived in (the
# gate's own skill, the scaffolding skill, and docs/). Not derivable: the set is
# "where the census stopped short", which is a property of the #327 incident
# rather than something a scan of the tree can find. It is a floor on the
# population, not the population — that is $census_pop, derived from git ls-files.
for required in "execute/SKILL.md" "$ip_skill" "docs/using-this-pack.md"; do
    if grep -qxF "$required" "$census_pop"; then
        assert_eq "in census" "in census" "population contains $required"
    else
        assert_eq "in census" "excluded" "population contains $required"
    fi
done

census_lines="$scratch/census-lines"
tr '\n' '\0' < "$census_pop" | xargs -0 grep -IHnE '.' -- > "$census_lines" 2>/dev/null || true
[ -s "$census_lines" ] || fatal "reading the census population produced no lines at all"

one_condition="$(census_sites one < "$census_lines" || true)"
assert_eq "" "$one_condition" \
    "no tracked site states Step 0's auto-invoke condition as absence alone"

two_condition="$(census_sites both < "$census_lines" | sort -u || true)"
two_count="$(grep -c . <<<"$two_condition" || true)"
# Eight sites state it in full today: CLAUDE.md, SYSTEM-OVERVIEW.md,
# /execute's Handoff, /init-pipeline's frontmatter description, its when-to-use
# bullet and its Handoff line, and both docs/using-this-pack.md sites. The
# floor is under that so a
# deliberate consolidation is not a false alarm, and above zero so the
# assertion above cannot pass because the terms stopped matching.
assert_eq "true" "$([ "$two_count" -ge 5 ] && echo true || echo false)" \
    "at least 5 tracked sites state both halves (found $two_count)"

printf 'two-condition sites:\n%s\n' "$two_condition" | sed 's/^/  /'

section "14c. The frontmatter description, against the paths § 2 actually has"

# /init-pipeline's description said "Run once per project" alongside the
# one-condition trigger. § 2 now carries a path keyed to the gate's stale
# verdict — a re-scaffold over a hook that is already installed — so a second
# run at the same project is the designed case, not an anomaly. The claim is
# read against that path's existence rather than asserted from memory.
if grep -qF -- "$v_stale" <<<"$path_paras"; then
    assert_eq "present" "present" "§ 2 carries a path keyed to $v_stale, so a project can be scaffolded more than once"
else
    assert_eq "present" "absent" "§ 2 carries a path keyed to $v_stale, so a project can be scaffolded more than once"
fi

ip_desc="$(awk 'NR == 1 && $0 == "---" { inside = 1; next }
                inside && /^---$/                { exit }
                inside && /^description:/        { print }' "$ip_skill")"
[ -n "$ip_desc" ] || fatal "no description: line found in $ip_skill frontmatter"

assert_eq "" "$(grep -oiE 'once per project|run once' <<<"$ip_desc" || true)" \
    "the description makes no once-per-project claim, which the $v_stale path contradicts"

assert_eq "true" "$([ -n "$(printf '%s\n' "$ip_skill:3:$ip_desc" | census_sites both)" ] && echo true || echo false)" \
    "the description states both halves of the trigger condition"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
