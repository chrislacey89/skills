#!/usr/bin/env bash
# test-documented-git-commands.sh — contract test for the git commands a skill
# tells a downstream agent to run.
#
# Skills ship executable prose: an agent copies a fenced block out of a SKILL.md
# and runs it unsupervised in someone else's repo. A wrong command does not fail
# here — it fails later, quietly, somewhere the author never sees. #243 is the
# incident: six successive drafts of one passage each shipped a wrong claim
# about a git subcommand, every wrong draft was caught by a human or a review
# sub-agent, and none by a check. CLAUDE.md § "Commands a skill documents"
# rule (b) is the standing response — route the claim to a mechanism.
#
# So these tests do not read the commands. They RUN them, extracted verbatim
# from the skill rather than restated here, against real git in a real
# repository. A block that stops being a valid invocation fails this suite.
#
# Covered today: /triage-issue Step 2's regression-bisect block and its
# "prior incident patterns" fix-commit grep (#236). Extend the suite when a
# skill documents another runnable command; do not maintain a list of the
# commands in prose, since that list is itself the thing that drifts.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
triage_skill="$repo_root/triage-issue/SKILL.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

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

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       missing: %q\n       in:      %q\n' "$label" "$needle" "$haystack"
        fail=$((fail + 1))
    fi
}

fatal() {
    printf 'FATAL: %s\n' "$1" >&2
    printf '       The command moved or its shape changed; update this suite with it.\n' >&2
    exit 2
}

# --- Pull the commands out of the skill itself, never restate them -----------

bisect_start="$(grep -m1 '^git bisect start ' "$triage_skill" || true)"
bisect_run="$(grep -m1 '^git bisect run ' "$triage_skill" || true)"
fix_grep="$(grep -m1 '^git log --oneline .*--grep=' "$triage_skill" || true)"

[[ -n "$bisect_start" ]] || fatal "no 'git bisect start' line found in $triage_skill"
[[ -n "$bisect_run" ]]   || fatal "no 'git bisect run' line found in $triage_skill"
[[ -n "$fix_grep" ]]     || fatal "no 'git log --grep' fix-commit line found in $triage_skill"

printf 'bisect start (triage-issue/SKILL.md): %s\n' "$bisect_start"
printf 'bisect run   (triage-issue/SKILL.md): %s\n' "$bisect_run"
printf 'fix grep     (triage-issue/SKILL.md): %s\n' "$fix_grep"

# -----------------------------------------------------------------------------

section "the subcommands the skill names still exist in this git"

# `git bisect -h` prints usage to stdout and exits 0 without needing man pages
# installed, so this works on a bare CI image where `git bisect --help` cannot
# render. The skill points readers at the man page for the exit-status
# contract; this pins only that the subcommands it invokes are still spelled
# the way it spells them.
bisect_usage="$(git bisect -h 2>&1 || true)"
assert_contains "$bisect_usage" 'git bisect start' "git still declares 'bisect start'"
assert_contains "$bisect_usage" 'git bisect run' "git still declares 'bisect run'"

# -----------------------------------------------------------------------------

section "build a synthetic repository with a planted regression"

# Both command tests run against this fixture rather than against Skill Kit's
# own history. That is deliberate: `actions/checkout@v4` clones shallow by
# default, so any assertion about real commit history would pass locally and
# fail in CI for a reason that has nothing to do with the command under test.
# The fixture is a real git repository, just a hermetic one.
#
# value.txt reads "ok" until exactly one commit breaks it — the only correct
# bisect answer. The commit messages around it are shaped so the fix-commit
# grep has both matches and non-matches to separate.
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

(
    cd "$sandbox"
    git init -q .
    git config user.email skillkit@example.invalid
    git config user.name 'Skill Kit Test'
    git config commit.gpgsign false

    # Each commit must differ from the last or git refuses it, so an unrelated
    # file carries the churn while value.txt carries the regression.
    for i in 1 2 3; do
        echo ok > value.txt
        echo "$i" > noise.txt
        git add value.txt noise.txt
        git commit -q -m "good commit $i"
    done

    # Touches value.txt only — so the path-filtered grep below must NOT see it,
    # even though "the regression" matches the 'regress' alternative.
    echo broken > value.txt
    git add value.txt
    git commit -q -m 'the regression'
    git rev-parse HEAD > .expected-first-bad

    echo 4 > noise.txt
    git add noise.txt
    git commit -q -m 'FIX: guard the null boundary'   # uppercase — only -i matches

    echo 5 > noise.txt
    git add noise.txt
    git commit -q -m 'Revert "an earlier change"'

    echo 6 > noise.txt
    git add noise.txt
    git commit -q -m 'tidy up the module layout'      # matches nothing
)
printf '  ok   fixture built at %s\n' "$sandbox"
pass=$((pass + 1))

# -----------------------------------------------------------------------------

section "the fix-commit grep is a runnable invocation that filters correctly"

# Run the skill's own line, with only the placeholder substituted. A malformed
# --grep pattern or a dropped flag fails here rather than in a downstream repo
# halfway through a triage.
grep_cmd="${fix_grep//<candidate-path>/noise.txt}"
set +e
grep_out="$(cd "$sandbox" && eval "$grep_cmd" 2>&1)"
grep_status=$?
set -e
assert_eq 0 "$grep_status" "the fix-commit grep exits 0 against a real repository"

assert_contains "$grep_out" 'FIX: guard the null boundary' \
    "matches a fix commit case-insensitively (the -i flag is doing work)"
assert_contains "$grep_out" 'Revert "an earlier change"' \
    "matches a revert commit (the alternation is doing work)"

if [[ "$grep_out" != *'tidy up the module layout'* ]]; then
    printf '  ok   a non-incident commit is filtered out, so the pattern is not matching everything\n'
    pass=$((pass + 1))
else
    printf '  FAIL the pattern matched an unrelated commit; --grep is not filtering\n'
    fail=$((fail + 1))
fi

if [[ "$grep_out" != *'the regression'* ]]; then
    printf '  ok   a matching commit outside the candidate path is excluded, so the path filter binds\n'
    pass=$((pass + 1))
else
    printf '  FAIL a commit that never touched the candidate path was returned\n'
    fail=$((fail + 1))
fi

# The skill ships this line for downstream repos, so it must also be a valid
# invocation here. Exit status only — this repo is cloned shallow in CI, so
# what it matches is not a stable assertion.
set +e
(cd "$repo_root" && eval "${fix_grep//<candidate-path>/triage-issue\/SKILL.md}" >/dev/null 2>&1)
home_status=$?
set -e
assert_eq 0 "$home_status" "the same line runs against Skill Kit's own repository"

# -----------------------------------------------------------------------------

section "the bisect block finds a known first-bad commit"

expected_bad="$(cat "$sandbox/.expected-first-bad")"
good_ref="$(cd "$sandbox" && git rev-list --max-parents=0 HEAD)"

# `grep -q ok value.txt` is the stand-in for Step 2's deterministic loop: exit 0
# on a good revision, non-zero on a bad one, which is the contract the skill
# sends the reader to `git bisect --help` § "Bisect run" to satisfy.
start_cmd="${bisect_start//<bad-ref>/HEAD}"
start_cmd="${start_cmd//<good-ref>/$good_ref}"
run_cmd="${bisect_run//<the-loop-command>/grep -q ok value.txt}"

set +e
bisect_out="$(cd "$sandbox" && eval "$start_cmd" 2>&1 && eval "$run_cmd" 2>&1)"
bisect_status=$?
set -e
(cd "$sandbox" && git bisect reset -q >/dev/null 2>&1 || true)

assert_eq 0 "$bisect_status" "the skill's bisect start + run pair completes successfully"
assert_contains "$bisect_out" "$expected_bad" "bisect names the planted regression commit"
assert_contains "$bisect_out" 'is the first bad commit' "bisect reports a first-bad result"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
