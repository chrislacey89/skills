#!/usr/bin/env bash
# test-post-review-edit-lock.sh — contract test for the post-review edit lock:
# the second clause of `.claude/hooks/enforce-classification.sh` and the four
# runnable blocks, spread across four skills, that drive it.
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
# SO THIS SUITE RUNS THE THING. It extracts the hook body and all four commands
# verbatim from the skills that document them and executes them against real
# files in a scratch project. It types no flag path of its own: the flag paths
# are read out of `/pre-merge`'s `touch` and `/fix-findings`' harness line, and
# section 5 drives the whole lifecycle — stamped, opened, shut, released — using
# only text the skills supply. A rename in one file that the other three do not
# mirror fails here, rather than in a downstream repo at merge time.
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
hook_body="$(fenced_bash_block init-pipeline/SKILL.md 'IMPL_PATTERNS' || true)"
[ -n "$hook_body" ] || fatal "no IMPL_PATTERNS hook body found in init-pipeline/SKILL.md — either the hook moved or its fence changed; update this suite with it"

# The stamp flag's writer (/pre-merge Phase 4) and remover (/closeout Step 3).
# Both sit at the tail of a larger fenced block, so the slice is anchored on the
# PROJECT_DIR assignment that opens them rather than on their content.
stamp_write="$(fenced_bash_block pre-merge/SKILL.md 'review-stamped' | sed -n '/^PROJECT_DIR=/,$p' || true)"
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

# --- The flag paths, read out of the writers rather than typed here ----------

stamp_arg="$(sed -n 's|.*touch "\([^"]*\)".*|\1|p' <<<"$stamp_write")"
stamp_rel="${stamp_arg#*/}"                      # strip the $PROJECT_DIR/ prefix
[ -n "$stamp_rel" ] && [ "$stamp_rel" != "$stamp_arg" ] || fatal "could not read a project-relative stamp-flag path out of /pre-merge's touch"

fixer_rel="$(sed -n 's|.*touch \([^ ]*\).*|\1|p' <<<"$fixer_write")"
[ -n "$fixer_rel" ] || fatal "could not read a project-relative fixer-flag path out of /fix-findings' harness line"

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
# refusal it writes to stderr. $hook_file is a variable because section 8 points
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

section "1. the hook is a runnable script, and the four files agree on two paths"

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

section "3. the lock's truth table (clause 2)"

set_flags "$tdd_active"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "unstamped branch: the write lands"

set_flags "$tdd_active" "$stamp_rel"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "stamped, no fixer flag: the write is refused"

if grep -qF "/fix-findings" <<<"$hook_err"; then
    assert_eq "names /fix-findings" "names /fix-findings" "the refusal routes the human to the skill that can take the edit"
else
    assert_eq "names /fix-findings" "$hook_err" "the refusal routes the human to the skill that can take the edit"
fi

set_flags "$tdd_active" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "stamped with the fixer flag present: the write lands"

set_flags "$tdd_active" "$fixer_rel"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "fixer flag alone, nothing stamped: the write lands"

# -----------------------------------------------------------------------------

section "4. the non-coverage /init-pipeline and /fix-findings both state in prose"

# Both skills say, in prose, that the lock reuses the classification gate's
# *test* / *spec* / *.d.ts / *.config.* skip logic unchanged, so a post-review
# edit to a test, a type declaration, a config file, or anything off the pattern
# list is NOT refused. That is a measured claim now rather than an asserted one.

set_flags "$tdd_active" "$stamp_rel"

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

# -----------------------------------------------------------------------------

section "5. round trip: the four documented commands drive the hook"

# The load-bearing section. Every state change below is made by running text
# extracted from a skill, and every observation is made by running the hook.
# No flag path appears as a literal anywhere in it, so the four files can only
# stay green by continuing to agree with each other.

set_flags "$tdd_active"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "before /pre-merge stamps: open"

run_documented "$proj" "$stamp_write" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /pre-merge Phase 4's touch: shut"

run_documented "$proj" "$fixer_write" "$proj"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "after /fix-findings' harness line: open for the fixer"

run_documented "$proj" "$fixer_remove" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /fix-findings Step 3's rm: shut again"

run_documented "$proj" "$stamp_remove" "$proj"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "after /closeout Step 3's rm at merge: released"

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

# -----------------------------------------------------------------------------

section "7. the breaker's copy is structurally unable to write to the branch"

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

# -----------------------------------------------------------------------------

section "8. apparatus: the refusal in section 3 measures the clause"

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

# -----------------------------------------------------------------------------

section "9. neither flag can be committed into this repo"

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
