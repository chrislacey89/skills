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
# Covered today: /triage-issue Step 2's regression-bisect block (all three of
# its lines) and its "prior incident patterns" fix-commit grep (#236). Extend
# the suite when a skill documents another runnable command; do not maintain a
# list of the commands in prose, since that list is itself the thing that
# drifts.
#
# Highest-value next extension: /closeout, which documents 13 runnable git
# invocations including `git worktree remove`, `git branch -d`, and
# `git pull --ff-only` — the destructive ones, run unsupervised at merge time.
#
# Two lessons from this suite's own first draft, both found in review and both
# worth keeping in mind when extending it:
#   1. Assert the *answer*, not the presence of its parts. The first draft
#      checked for the expected SHA anywhere in bisect's output and for the
#      phrase "is the first bad commit" anywhere, independently. Both passed
#      while git named a different commit.
#   2. Mutate the fixture's oracle, not only the command under test. The same
#      draft's oracle answered "good" on every revision, so the bisect half
#      verified nothing at all — and every mutation of the *command* still went
#      red, which is what made it look verified.
#   3. Match git's own prose loosely; match the fixture's prose exactly. An
#      assertion on text *git* emits must tolerate wording drift across git
#      versions (see the `'?bad'?` regex below, added after this suite passed on
#      git 2.43 and failed on 2.55 for every PR in the repo). An assertion on
#      text the *fixture* planted — the commit subjects around line 230 — is a
#      string this suite controls, so it stays exact.

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

assert_matches() {
    local haystack="$1" pattern="$2" label="$3"
    if [[ "$haystack" =~ $pattern ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       no match: %q\n       in:      %q\n' "$label" "$pattern" "$haystack"
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
bisect_reset="$(grep -m1 '^git bisect reset' "$triage_skill" || true)"
fix_grep="$(grep -m1 '^git log --oneline .*--grep=' "$triage_skill" || true)"

[[ -n "$bisect_start" ]] || fatal "no 'git bisect start' line found in $triage_skill"
[[ -n "$bisect_run" ]]   || fatal "no 'git bisect run' line found in $triage_skill"
[[ -n "$bisect_reset" ]] || fatal "no 'git bisect reset' line found in $triage_skill"
[[ -n "$fix_grep" ]]     || fatal "no 'git log --grep' fix-commit line found in $triage_skill"

# The placeholder tokens are a private format shared between the skill's fenced
# blocks and this file, and the greps above do not notice if one is renamed —
# the substitutions below would silently no-op and the failure would surface as
# an assertion about a command that is in fact correct. Name them here so a
# rename fails loudly, pointing at the real cause.
for placeholder in '<bad-ref>' '<good-ref>'; do
    [[ "$bisect_start" == *"$placeholder"* ]] || fatal "placeholder $placeholder is gone from the 'git bisect start' line"
done
[[ "$bisect_run" == *'<the-loop-command>'* ]] || fatal "placeholder <the-loop-command> is gone from the 'git bisect run' line"
[[ "$fix_grep" == *'<candidate-path>'* ]]     || fatal "placeholder <candidate-path> is gone from the 'git log --grep' line"

printf 'bisect start (triage-issue/SKILL.md): %s\n' "$bisect_start"
printf 'bisect run   (triage-issue/SKILL.md): %s\n' "$bisect_run"
printf 'bisect reset (triage-issue/SKILL.md): %s\n' "$bisect_reset"
printf 'fix grep     (triage-issue/SKILL.md): %s\n' "$fix_grep"

# -----------------------------------------------------------------------------

section "the subcommands the skill names still exist in this git"

# `git bisect -h` prints usage to stdout and exits 0 without needing man pages
# installed, so this works on a bare CI image where `git bisect --help` cannot
# render. The skill points readers at the man page for the exit-status
# contract; this pins only that the subcommands it invokes are still spelled
# the way it spells them.
#
# The subcommand names are taken from the extracted lines, not typed here. A
# hardcoded literal would keep passing if the skill renamed a subcommand, which
# is restatement — the exact thing this suite's header says not to do.
bisect_usage="$(git bisect -h 2>&1 || true)"
# coverage: enumerated — the three bisect lines triage-issue/SKILL.md documents.
# Derived is not available: each is extracted by its own anchor above, and the
# set is fixed by what the skill actually documents, not by what a scan finds.
for extracted in "$bisect_start" "$bisect_run" "$bisect_reset"; do
    subcommand="$(printf '%s' "$extracted" | awk '{print $1, $2, $3}')"
    assert_contains "$bisect_usage" "$subcommand" "git still declares '${subcommand#git }'"
done

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

# Neutralize global and system git config for every command in this suite.
# Without this the fixture is not hermetic: `grep.patternType` is a common
# personal setting and it silently changes the dialect `git log --grep` parses,
# so a contributor who sets it would get red assertions unrelated to anything
# they changed. Exported rather than set per-command, because the invocations
# under test are extracted verbatim from the skill and cannot carry test-only
# environment of their own.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

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
    #
    # The marker is "spoiled", not "broken": the oracle greps for a whole line
    # equal to "ok", and "broken" *contains* "ok" (br-ok-en). A substring oracle
    # answered "good" on every revision here, bisect walked to HEAD, and the
    # suite still reported green — the defect this fixture now exists to prevent.
    # Keeping the word distinct means the fixture stays correct even if some
    # future edit relaxes the oracle back to a substring match.
    echo spoiled > value.txt
    git add value.txt
    git commit -q -m 'the regression'
    git rev-parse HEAD > .expected-first-bad

    # One commit per alternative in the documented --grep pattern, so dropping
    # any of the four from the skill fails an assertion below. 'FIX' is
    # uppercase so it is matched only by -i.
    echo 4 > noise.txt
    git add noise.txt
    git commit -q -m 'FIX: guard the null boundary'

    echo 5 > noise.txt
    git add noise.txt
    git commit -q -m 'Revert "an earlier change"'

    echo 6 > noise.txt
    git add noise.txt
    git commit -q -m 'handle the bug in the parser'

    echo 7 > noise.txt
    git add noise.txt
    git commit -q -m 'stop the layout regressing on resize'

    echo 8 > noise.txt
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

# One assertion per alternative in the documented pattern. Without all four,
# half the pattern can be deleted from the skill and this suite stays green —
# it did, before this was written.
assert_contains "$grep_out" 'FIX: guard the null boundary' \
    "matches the 'fix' alternative, case-insensitively (the -i flag is doing work)"
assert_contains "$grep_out" 'Revert "an earlier change"' \
    "matches the 'revert' alternative (the alternation is doing work)"
assert_contains "$grep_out" 'handle the bug in the parser' \
    "matches the 'bug' alternative"
assert_contains "$grep_out" 'stop the layout regressing on resize' \
    "matches the 'regress' alternative"

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

# The documented command must mean the same thing in every repo the skill runs
# in. `git log --grep` honors `grep.patternType`, so a pattern that relies on
# the default dialect returns zero matches — silently — for any user who sets
# it. Zero is the dangerous answer here, because the skill's "best-effort"
# bullet reads it as "this repo has no fix-commit convention" and skips the
# step. Run the skill's own line under each hostile setting and require it to
# keep matching.
#
# Each dialect's result is compared against the baseline run above rather than
# against a hardcoded commit subject. Keying on a specific subject would couple
# these four assertions to whichever alternative that subject exercises, so
# deleting one alternative from the skill would redden them too — reporting a
# dialect problem to a reader whose actual mistake was a missing alternative.
# Comparing to the baseline isolates the one thing this loop is about: whether
# the config key changes the result.
for dialect in extended perl fixed basic; do
    set +e
    (cd "$sandbox" && git config grep.patternType "$dialect"); dialect_set=$?
    dialect_out="$(cd "$sandbox" && eval "$grep_cmd" 2>&1)"
    set -e
    # --unset exits 5 when the key is absent, which would kill the run under
    # `set -e` with no assertion summary if the set above ever failed.
    (cd "$sandbox" && git config --unset grep.patternType) || true
    if [[ "$dialect_set" -ne 0 ]]; then
        printf '  FAIL could not set grep.patternType=%s, so this dialect went unchecked\n' "$dialect"
        fail=$((fail + 1))
    elif [[ "$dialect_out" == "$grep_out" ]]; then
        printf '  ok   the documented pattern survives grep.patternType=%s\n' "$dialect"
        pass=$((pass + 1))
    else
        printf '  FAIL grep.patternType=%s changes what the documented pattern matches\n' "$dialect"
        fail=$((fail + 1))
    fi
done

# The skill ships this line for downstream repos, so it must also be a valid
# invocation here. Exit status only — this repo is cloned shallow in CI, so
# what it matches is not a stable assertion.
set +e
(cd "$repo_root" && eval "${fix_grep//<candidate-path>/triage-issue/SKILL.md}" >/dev/null 2>&1)
home_status=$?
set -e
assert_eq 0 "$home_status" "the same line runs against Skill Kit's own repository"

# -----------------------------------------------------------------------------

section "the bisect block finds a known first-bad commit"

expected_bad="$(cat "$sandbox/.expected-first-bad")"
good_ref="$(cd "$sandbox" && git rev-list --max-parents=0 HEAD)"

# `grep -qx ok value.txt` is the stand-in for Step 2's deterministic loop: exit 0
# on a good revision, non-zero on a bad one, which is the contract the skill
# sends the reader to `git bisect --help` § "Bisect run" to satisfy.
#
# -x (whole-line match) is load-bearing, not stylistic. A substring oracle
# reports "good" on a revision whose marker merely contains "ok", which is the
# oracle-polarity failure the skill's first rider now warns about — and it is
# the failure this suite shipped with: bisect walked to HEAD and the assertions
# passed anyway.
start_cmd="${bisect_start//<bad-ref>/HEAD}"
start_cmd="${start_cmd//<good-ref>/$good_ref}"
run_cmd="${bisect_run//<the-loop-command>/grep -qx ok value.txt}"

# Verify the oracle's polarity at both ends before trusting anything it says
# mid-bisect — the same pre-flight the skill now asks its readers to run.
#
# The checkout and the oracle are run as separate statements on purpose. Chained
# with && they share one exit status, and the bad-end assertion passes on
# *non-zero* — so a failed checkout would satisfy it just as well as a working
# oracle, and the check would silently measure nothing. That is the same
# pass-for-the-wrong-reason shape this whole suite exists to catch, so it is not
# allowed to live inside the safety net.
oracle_setup() { ( cd "$sandbox" && git checkout -q "$1" -- value.txt ); }
oracle_run()   { ( cd "$sandbox" && grep -qx ok value.txt ); }

set +e
oracle_setup "$good_ref"; good_setup=$?
oracle_run;               good_end=$?
oracle_setup HEAD;        bad_setup=$?
oracle_run;               bad_end=$?
oracle_setup HEAD >/dev/null 2>&1
set -e

assert_eq 0 "$good_setup" "the known-good end can be checked out (the polarity probe is really running)"
assert_eq 0 "$bad_setup"  "the known-bad end can be checked out (the polarity probe is really running)"
assert_eq 0 "$good_end" "the oracle answers 'good' (exit 0) at the known-good end"

# git bisect run treats 1-127 except 125 as "bad"; 125 means untestable and
# anything above 127 aborts the run. Asserting the range rather than merely
# "non-zero" means a fixture whose oracle dies for an unrelated reason fails
# here instead of passing as a healthy negative.
if [[ "$bad_end" -ge 1 && "$bad_end" -le 127 && "$bad_end" -ne 125 ]]; then
    printf '  ok   the oracle answers "bad" at the known-bad end with exit %s, in git bisect'"'"'s bad range\n' "$bad_end"
    pass=$((pass + 1))
else
    printf '  FAIL the oracle returned %s at the known-bad end; it is not a "bad" verdict, so bisect would name a commit regardless\n' "$bad_end"
    fail=$((fail + 1))
fi

set +e
bisect_out="$(cd "$sandbox" && eval "$start_cmd" 2>&1 && eval "$run_cmd" 2>&1)"
bisect_status=$?
set -e
# Extracted from the skill like its siblings rather than restated — this is the
# third command in the documented block, and a restated copy of it shipped here
# with an invalid `-q` flag that `|| true` hid.
#
# `set +e` around it is what makes an invalid reset line surface as a named
# failed assertion instead of killing the run at this line under `set -e`,
# where it would report no assertions at all and send the reader hunting.
set +e
reset_err="$(cd "$sandbox" && eval "$bisect_reset" 2>&1 >/dev/null)"
reset_status=$?
set -e

assert_eq 0 "$bisect_status" "the skill's bisect start + run pair completes successfully"
assert_eq 0 "$reset_status" "the skill's 'git bisect reset' line is a valid invocation"
[[ "$reset_status" -eq 0 ]] || printf '       git said: %s\n' "$reset_err"

# Bind the SHA to the answer. Asserting the SHA and the phrase separately lets
# both pass while git names a different commit: the planted SHA appears in an
# intermediate "Bisecting: ... [<sha>]" checkout line, and the phrase attaches
# to whatever git actually concluded. That is precisely how this suite reported
# a wrong answer as green. The regex below keeps that binding — the SHA and the
# phrase must be adjacent in one line, never matched independently.
#
# `'?bad'?` because git's wording of this line is not stable across versions:
# git 2.43 prints `<sha> is the first bad commit`, git 2.55 prints
# `<sha> is the first 'bad' commit` (the term is now quoted, since `bad` is a
# renameable bisect term). Pinning either spelling makes the suite pass on one
# git and fail on the other — which is what it did: green on 2.43 locally,
# red on 2.55 in CI, for every PR in the repo until this fix. That is CLAUDE.md
# rule (a) — do not re-author a third-party tool's output — applied to a suite
# whose own purpose is enforcing rule (a) one layer up.
assert_matches "$bisect_out" "$expected_bad is the first '?bad'? commit" \
    "bisect names the planted regression commit as the first bad commit"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
