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
# its lines) and its "prior incident patterns" fix-commit grep (#236), the
# base-branch detection block that /pre-merge, /help, /walk-commits,
# /visual-recap and /compound each carry (#298), and every documented *name*
# claim, including /closeout's bare one-liner (#310). Extend the suite when a
# skill documents another runnable command; do not maintain a list of the
# commands in prose, since that list is itself the thing that drifts.
#
# Highest-value next extension: /closeout, which documents 13 runnable git
# invocations including `git worktree remove`, `git branch -d`, and
# `git pull --ff-only` — the destructive ones, run unsupervised at merge time.
# The clone-bearing fixture #298 added is reusable for it (#261).
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
#   4. A fixture that cannot express the fault proves nothing about it. #298's
#      defect — a base branch *name* used where a *ref* was required — was
#      unreachable in a `git init` fixture, because local and remote refs
#      cannot diverge in a repo with no remote. Every assertion here was green
#      and the fault was live at four sites. When adding coverage, ask what
#      state the fixture can reach before asking what the assertions check.
#   5. A guard that disappears along with the thing it guards is not a guard.
#      The /closeout check below first read "*if* this file mentions BASE_REF,
#      it must also carry the note explaining why it does not use one" — so
#      deleting the note deleted the trigger, and that mutation went green. It
#      is now two unconditional assertions.
#   6. Enumerate by what the claim DOES, not by how one site words it. The
#      base-branch census below first derived its population by grepping for
#      the detection block's own assignment — so a skill that committed the
#      same defect without adopting the block (compound/SKILL.md, a runnable
#      `git diff main...HEAD`) could not enter the population at all. Review
#      caught it; this suite did not. The census now scans every documented
#      `git diff`/`git log` range in every skill, and asserts it accounts for
#      every `..HEAD` in those files so a range in an unparseable shape fails
#      loudly instead of dropping out of the count.
#   7. Generalize a census lesson to the claim's SHAPE, not just its instance.
#      Lesson 6 was applied to *range* claims and stopped there. /closeout
#      makes a base-branch **name** claim: it wants the name for `git switch`,
#      so it documents no range and carries no `BASE_BRANCH=` assignment, and
#      it therefore fell in no block of either population. Its line emitted
#      `origin/prod` where its own inline comment claimed `prod` — wrong on
#      every healthy repo, for as long as the line existed, and never executed
#      by anything (#310). Two sub-lessons came out of building the fix:
#        (a) Derive the population from the LOOSEST signal, then fail loudly on
#            members the runner cannot execute. Deriving it from `git
#            symbolic-ref` would rebuild the same trap one level up: a claim
#            written as `git rev-parse --abbrev-ref origin/HEAD` (same wrong
#            output, same defect) would simply not be in the population, and
#            its absence would read as coverage.
#        (b) An "accounting" assertion is only non-vacuous when two DIFFERENT
#            patterns can disagree. The first draft here compared a partition
#            against a raw count of the same literal — total by construction,
#            and so a tautology wearing a non-vacuity label. Deleted rather
#            than kept as reassurance.
#        (c) The prose half of a partition needs a real discriminator, and it
#            took THREE drafts. (1) "does the line still say something once its
#            code spans are removed" — a bare recipe has no spans, so nothing
#            was removed and every bare recipe passed. (2) "is there a backtick
#            before the signal and one after it" — prose here is dense with
#            inline code, so a recipe dropped mid-sentence is almost always
#            straddled by unrelated spans; found in review with a planted line
#            whose signal sat between a `base` span and a `git switch` one.
#            (3) strip balanced spans and require the signal to VANISH, which
#            is the only form that asks the question the branch is named for.
#            Drafts 1 and 2 were each caught by a mutation the previous draft's
#            author did not think to write — see (e).
#        (d) `set -o pipefail` turns a no-match `grep` inside a command
#            substitution into a silent run-ending failure. The comment-claim
#            check shipped it: the suite exited mid-section at the first site
#            whose line carried no claim, printing no assertion and no message,
#            and every "green" reading of that draft was an early exit rather
#            than a pass. `|| true` goes INSIDE the substitution, before the
#            pipe. The range extractor above documents this same defect; it
#            recurred anyway, twenty lines from its own warning.
#        (e) A detector whose healthy state is zero hits needs a SELF-TEST, not
#            a count floor — plant the shape it must flag and require a hit,
#            plant the corrected shape and require silence. Both detectors here
#            carry one, in the shape test-guards-can-fire.sh uses. A floor says
#            "we looked at N lines"; it never says the predicate still
#            discriminates, and drafts (c)(1) and (c)(2) both passed a floor.
#            Likewise a floor over the whole population is not a floor over any
#            site in it: the first draft's global `-ge 6` let a seventh claim
#            planted anywhere mask the deletion of the one site this section
#            exists for. It is now per-site, derived.
#
# WHAT THIS SUITE DOES NOT HOLD, said plainly so a green run is not misread:
# the cross-site equality checks (fallback candidate list, **Residual:**
# paragraph) pin that the five copies stay IDENTICAL, not that they stay
# CORRECT. A sweep that edits all five the same wrong way keeps them equal.
# The named content assertions beside each one pin the load-bearing clauses;
# everything else in that prose is held by review, not by this file.

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
# Base-branch detection: every skill that carries the block, one clone-bearing fixture (#298)
# -----------------------------------------------------------------------------
#
# The suite above could never have caught #298, and the reason is its fixture,
# not its assertions. `git init -q .` creates a repository with no remote, and
# in a repository with no remote a local branch and its remote-tracking ref
# cannot diverge. The fault was *unreachable* in the state space that fixture
# can express (Ammann & Offutt: Reachability is the first of R-I-P, and it is
# necessary). So this half clones.
#
# The defect: four skills resolved the base branch's *name* and handed the bare
# name to `git diff`/`git log` as a range endpoint. A name is not a ref — in a
# worktree workflow nobody checks the base branch out, so the local branch is
# frozen at whenever the checkout was made while `origin/<base>` moves on.
# `/pre-merge` reported PR #297 as 145 files / 12,793 lines; it was 24 / 461.
#
# The second defect only exists because the first is being fixed: /walk-commits
# and /visual-recap used two-dot `git diff`. With a *stale local* base that is
# harmless, because the stale ref is an ancestor of HEAD and `..` and `...`
# agree — so a naive stale-base fixture would go green on those two sites while
# the fault is live (Ammann & Offutt: Propagation, the third condition). The
# fixture below plants four positions so all three wrong answers are distinct
# from the truth *and from each other*, and the negative controls at the end
# assert each wrong form produces its own wrong number rather than merely
# "something".
#
# Every command is extracted from the SKILL.md and evaluated. The wrong forms
# are built by mutating those extracted lines, so a site that stops carrying
# the documented shape fails loudly rather than being silently skipped.

section "build a clone whose local base is behind origin/<base>"

# Four positions, and each one is load-bearing:
#   c3  local `prod`         — the clone's local base, never fast-forwarded
#   c5  branch point         — where the feature branch was cut from origin/prod
#   c7  origin/prod          — the base moved on after the branch was cut
#   F2  HEAD                 — the feature commits under review
#
# Insertions are planted per file so the three wrong answers cannot collide:
#   feature-a 6 + feature-b 4  = 10   (the truth)
#   merged-a 10 + merged-b 10  = 20   (between local prod and the branch point)
#   merged-c 20 + merged-d 30  = 50   (after the branch point)
base_sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox" "$base_sandbox"' EXIT
upstream="$base_sandbox/upstream"
work="$base_sandbox/work"

(
    mkdir -p "$upstream"
    cd "$upstream"
    git init -q -b prod .
    git config user.email skillkit@example.invalid
    git config user.name 'Skill Kit Test'
    git config commit.gpgsign false
    for i in 1 2 3; do
        echo "base line $i" >> base.txt
        git add base.txt
        git commit -q -m "c$i"
    done
)

git clone -q "$upstream" "$work"
git -C "$work" config user.email skillkit@example.invalid
git -C "$work" config user.name 'Skill Kit Test'
git -C "$work" config commit.gpgsign false

# Two commits land on the base *before* the branch is cut. These are the files
# a stale local ref sweeps into the diff — other people's already-merged work.
(
    cd "$upstream"
    seq 1 10 | sed 's/^/merged-a /' > merged-a.txt
    git add merged-a.txt && git commit -q -m c4
    seq 1 10 | sed 's/^/merged-b /' > merged-b.txt
    git add merged-b.txt && git commit -q -m c5
)
git -C "$work" fetch -q origin

# Cut the feature branch from the *remote-tracking* tip, which is what a
# worktree host (Conductor, wt, Codespaces) does. The local `prod` is left at
# c3 from here on — nothing in this fixture ever fast-forwards it, which is the
# whole point.
git -C "$work" checkout -q -b feature origin/prod
(
    cd "$work"
    seq 1 6 | sed 's/^/feat-a /' > feature-a.txt
    git add feature-a.txt && git commit -q -m F1
    seq 1 4 | sed 's/^/feat-b /' > feature-b.txt
    git add feature-b.txt && git commit -q -m F2
)

# Two more commits land on the base *after* the branch was cut. These are what
# make `origin/prod` a non-ancestor of HEAD, which is what makes two-dot and
# three-dot disagree — without them the operator defect cannot propagate.
(
    cd "$upstream"
    seq 1 20 | sed 's/^/merged-c /' > merged-c.txt
    git add merged-c.txt && git commit -q -m c6
    seq 1 30 | sed 's/^/merged-d /' > merged-d.txt
    git add merged-d.txt && git commit -q -m c7
)
git -C "$work" fetch -q origin

stale_by="$(git -C "$work" rev-list --count prod..origin/prod)"
assert_eq 4 "$stale_by" "the fixture's local base really is behind origin/<base> (the fault is reachable)"

if git -C "$work" merge-base --is-ancestor origin/prod HEAD 2>/dev/null; then
    printf '  FAIL origin/<base> is an ancestor of HEAD, so two-dot and three-dot agree and the operator fault cannot propagate\n'
    fail=$((fail + 1))
else
    printf '  ok   origin/<base> is not an ancestor of HEAD (the operator fault can propagate)\n'
    pass=$((pass + 1))
fi

if git -C "$work" symbolic-ref refs/remotes/origin/HEAD >/dev/null 2>&1; then
    printf '  ok   the clone has refs/remotes/origin/HEAD set, so the blocks exercise their primary detection path\n'
    pass=$((pass + 1))
else
    printf '  FAIL refs/remotes/origin/HEAD is unset; every block below would fall through to its candidate loop\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "every documented detection block resolves a name and a ref, and they agree"

# The fenced block is pulled out of the skill and dedented — shell does not care
# about leading whitespace, and /pre-merge's block is indented inside a numbered
# list. Nothing about the block is restated here.
extract_detect_block() {
    awk '
        /^[[:space:]]*```/ {
            if (inblock) {
                if (found) { for (i = 1; i <= n; i++) print buf[i]; exit }
                inblock = 0; n = 0; next
            }
            inblock = 1; n = 0; found = 0; next
        }
        inblock {
            buf[++n] = $0
            if (index($0, "BASE_BRANCH=$(git symbolic-ref")) found = 1
        }
    ' "$1" | sed 's/^[[:space:]]*//'
}

# Every line the skill runs with a base-branch variable as a range endpoint.
# Anchored at line start so the prose restatements (which sit inside sentences)
# are not collected here — they get their own check further down.
extract_range_lines() {
    # `|| true` because this file runs under `set -o pipefail`: a site that
    # stops carrying a range line would otherwise make the assignment fail and
    # kill the run at that line, *before* the `fatal` guard that names the
    # cause. Found by mutation — reverting compound/SKILL.md to a hardcoded
    # `main` produced a silent exit 1 with no assertion and no message.
    { grep -hE '^[[:space:]]*git (diff|log) .*\$\{?BASE_' "$1" || true; } | sed 's/^[[:space:]]*//'
}

# A literal dollar, spliced in from a variable rather than written inside
# quotes: inline, it is indistinguishable to a reader and to the linter alike
# from a variable that failed to expand. Reused by the restatement checks.
d='$'
# Derived, not listed. #298 records that the block was copied from /help to
# /pre-merge once already and will be copied again — a hand-written roster of
# the four sites would leave the fifth copy silently unchecked, which is the
# exact failure mode that let two of these four drift apart. Anything that
# carries the assignment is in scope automatically.
detect_marker="BASE_BRANCH=${d}(git symbolic-ref"
# `|| true` so a derivation that finds nothing reaches the floor assertion
# below instead of killing the run under `set -e` with no assertion reported.
# The fallback's stderr note is the residual's operative half — the difference
# between an operator who sees the degradation and one who reads a plausible
# wrong number, which is how the original defect survived five months.
#
# It is pinned by RUNNING each block in both fixtures, never by grepping the
# source. A substring test cannot separate the note on stderr from: the same
# note on stdout (where it lands ahead of the `base=… ref=…` value a consumer
# reads), the note moved into the `then` arm (where it fires exactly when the
# fallback did *not* happen), or the note commented out. All three mutations
# were green against the grep this replaced.
fallback_note='does not resolve — measuring against the local branch, which may be stale'

base_sites="$(cd "$repo_root" && { grep -lF "$detect_marker" ./*/SKILL.md || true; } \
    | sed 's|^\./||' | sort | tr '\n' ' ')"
base_site_count="$(printf '%s\n' "$base_sites" | tr ' ' '\n' | grep -c . || true)"
# A derivation that returns nothing passes every loop below without running
# one. This floor is the count of skills that carry the block today; a new
# copier raises it, and a drop below it means either the derivation broke or a
# site was quietly removed from the population. It was a stale `4` for one
# commit after /compound became the fifth site, which made reverting /compound
# a green no-op — the review caught that, this comment is why it stays current.
if [[ "$base_site_count" -ge 5 ]]; then
    printf '  ok   derived %s skills carrying the base-branch detection block\n' "$base_site_count"
    pass=$((pass + 1))
else
    printf '  FAIL derived only %s skills carrying the detection block; every check below is running on almost nothing\n' "$base_site_count"
    fail=$((fail + 1))
fi

# The candidate list is the thing that already drifted: /pre-merge carried
# `develop` and the other three did not, while help/SKILL.md's own prose names
# `develop` as a real base. Compare the sites to each other rather than to a
# literal typed here, so this stays a drift check and not a restatement.
canonical_list=""
for site in $base_sites; do
    block="$(extract_detect_block "$repo_root/$site")"
    [[ -n "$block" ]] || fatal "no base-branch detection block found in $site"
    list="$(printf '%s\n' "$block" | grep -m1 -oE 'for [a-z_]+ in [a-z ]+; do' || true)"
    [[ -n "$list" ]] || fatal "no fallback candidate loop found in $site's detection block"
    if [[ -z "$canonical_list" ]]; then
        canonical_list="$list"
        printf '  ok   fallback candidate loop (%s): %s\n' "$site" "$list"
        pass=$((pass + 1))
    else
        assert_eq "$canonical_list" "$list" "$site's fallback candidate loop is byte-identical to the other sites'"
    fi
done

# Equality alone pins that the lists stay the *same*, not that they stay
# *correct*: dropping a candidate from all five in one sweep keeps them equal
# and goes green — the exact sweep-wide shape closeout/SKILL.md's note warns
# about, and a mutation that was green before this check existed. So pin the
# names too. This is content, not drift, and it is deliberately a short list of
# what the loop must still be able to find.
for candidate_name in main master prod develop trunk; do
    assert_contains "$canonical_list" " $candidate_name" \
        "the fallback loop can still find a repo whose base is '$candidate_name'"
done

for site in $base_sites; do
    block="$(extract_detect_block "$repo_root/$site")"

    # The mirror of the no-remote check further down: a note that fires when the
    # ref *does* resolve is the `then`-arm mutation, and it is exactly as wrong
    # as no note at all — it tells the operator the measurement is degraded when
    # it is not, which is how a warning gets trained out of a reader.
    set +e
    ok_err="$(cd "$work" && eval "$block" 2>&1 >/dev/null)"
    set -e
    if [[ "$ok_err" == *"$fallback_note"* ]]; then
        printf '  FAIL %s announces a fallback even though origin/<base> resolved\n' "$site"
        fail=$((fail + 1))
    else
        printf '  ok   %s stays quiet when origin/<base> resolves\n' "$site"
        pass=$((pass + 1))
    fi

    # Parse the block before running it. Without this, an edit that leaves the
    # guard half-deleted shows up only as an empty BASE_REF several assertions
    # later, which points the reader at the wrong thing.
    set +e
    syntax_err="$(printf '%s\n' "$block" | bash -n 2>&1)"
    syntax_status=$?
    set -e
    assert_eq 0 "$syntax_status" "$site's detection block is still valid shell"
    [[ "$syntax_status" -eq 0 ]] || printf '       bash said: %s\n' "$syntax_err"

    set +e
    resolved="$(cd "$work" && eval "$block" >/dev/null 2>&1; printf '%s|%s' "${BASE_BRANCH:-}" "${BASE_REF:-}")"
    set -e
    assert_eq 'prod|origin/prod' "$resolved" \
        "$site resolves BASE_BRANCH to the name and BASE_REF to the remote-tracking ref"
done

# -----------------------------------------------------------------------------

# The residual is the one thing about this guard that a reader cannot see by
# reading it: on a fork, or a remote not named `origin`, the `else` branch
# silently restores stale-local behavior. Four copies of a sentence is the same
# drift surface as four copies of a candidate list, and the candidate list had
# already drifted twice by the time #298 was filed — so compare the sites to
# each other rather than to a literal typed here.
canonical_residual=""
for site in $base_sites; do
    residual="$(grep -m1 -o '\*\*Residual:\*\*.*' "$repo_root/$site" || true)"
    if [[ -z "$residual" ]]; then
        printf '  FAIL %s states no residual for the guarded fallback\n' "$site"
        fail=$((fail + 1))
    elif [[ -z "$canonical_residual" ]]; then
        canonical_residual="$residual"
        printf '  ok   %s carries a **Residual:** paragraph\n' "$site"
        pass=$((pass + 1))
    else
        assert_eq "$canonical_residual" "$residual" "$site's **Residual:** paragraph is byte-identical to the other sites'"
    fi
done

# Presence and cross-site equality say nothing about what the paragraph claims:
# replacing all five with an identical "**Residual:** none — $BASE_REF is always
# correct" was green before this check existed. Pin the two clauses that carry
# the warning. The rest of the wording is held by review, not by this suite —
# see the header note.
assert_contains "$canonical_residual" 'falls back to the local branch' \
    "the residual still names what the fallback actually does"
assert_contains "$canonical_residual" 'only as fresh as the last' \
    "the residual still names the staleness window it cannot close"

# The fallback's stderr note is the residual's operative half — the difference
# between an operator who sees the degradation and one who reads a plausible
# wrong number, which is how the original defect survived five months.
#
# It is checked by RUNNING the block, not by grepping it — see `fallback_note`
# above and its two use sites, one per fixture.

# -----------------------------------------------------------------------------

section "every documented range endpoint reports the branch's real size"

# The planted truth. The *assertions* below compare planted numbers, never git's
# summary sentence — but `stat_triple` does read that sentence to find them: its
# awk keys on the literal tokens `files`, `insertions(+)` and `deletions(-)`.
# That is a real coupling to git's wording, which has already broken this suite
# once across versions (header lesson 3), so it is named rather than denied. If
# git rewords the summary, `stat_triple` returns 0/0/0 and roughly fifteen
# assertions redden pointing at the skills — which is why it gets the planted
# self-check immediately below, so a wording change fails as one accurate
# `fatal` instead of fifteen misleading ones.
truth_files=2
truth_ins=10
truth_del=0
truth_commits=2

stat_triple() {
    # "N files changed, X insertions(+), Y deletions(-)" -> "N/X/Y", zero-filled.
    printf '%s\n' "$1" | tail -1 | awk '
        {
            files = ins = del = 0
            for (i = 1; i < NF; i++) {
                if ($(i + 1) ~ /^files?$/)        files = $i
                if ($(i + 1) ~ /^insertions?\(\+\),?$/) ins = $i
                if ($(i + 1) ~ /^deletions?\(-\),?$/)   del = $i
            }
            printf "%d/%d/%d", files, ins, del
        }'
}

# Validate the instrument before trusting what it measures. `stat_triple` is the
# oracle every count assertion in this file runs through, and its three arms are
# otherwise exercised only indirectly. A planted input with all three fields
# non-zero and distinct catches an arm that silently returns 0 — and the last
# probe uses git's *singular* spellings (`1 insertion(+)`, `1 deletion(-)`),
# which a one-line change really emits and which plural-only patterns miss.
for probe in \
    '1 file changed, 2 insertions(+), 3 deletions(-)|1/2/3' \
    '4 files changed, 5 insertions(+)|4/5/0' \
    '6 files changed, 7 deletions(-)|6/0/7' \
    '8 files changed, 1 insertion(+), 1 deletion(-)|8/1/1'
do
    assert_eq "${probe#*|}" "$(stat_triple "${probe%|*}")" \
        "stat_triple parses a planted summary: ${probe%|*}"
done

run_in_fixture() {
    # Run a site's detection block, then one extracted command, in the clone.
    #
    # The status is deliberately swallowed. Assigning this to a variable is a
    # simple command whose status is the substitution's, so under `set -e` a
    # block that stops parsing would kill the run at that line and report no
    # assertions at all — the same "reader hunts for a cause that was never
    # named" failure the bisect-reset check above guards against. Let the
    # assertions speak instead: a broken block yields empty output and reddens
    # its own named check, and the `bash -n` probe below names the real cause.
    ( cd "$work" && eval "$1" >/dev/null 2>&1; eval "$2" 2>&1 ) || true
}

for site in $base_sites; do
    block="$(extract_detect_block "$repo_root/$site")"
    lines="$(extract_range_lines "$repo_root/$site")"
    [[ -n "$lines" ]] || fatal "no 'git diff'/'git log' range line found in $site"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        out="$(run_in_fixture "$block" "$line")"
        case "$line" in
            "git diff"*)
                assert_eq "$truth_files/$truth_ins/$truth_del" "$(stat_triple "$out")" \
                    "$site: '$line' reports the branch's real size"
                ;;
            "git log"*)
                assert_eq "$truth_commits" "$(printf '%s' "$out" | grep -c .)" \
                    "$site: '$line' lists only the branch's own commits"
                ;;
        esac
    done <<< "$lines"
done

# -----------------------------------------------------------------------------

section "the fixture separates the right answer from each wrong one"

# Negative controls. Without these the section above would pass on a fixture
# that cannot tell the forms apart — which is exactly the state this suite was
# in before #298. Each wrong form is built by mutating a *real* extracted line,
# so a site that stops carrying the documented shape cannot silently skip its
# control.
#
# The three wrong answers are deliberately distinct from each other:
#   bare name, three-dot  -> 4/30/0   (sweeps in c4+c5, merged before the cut)
#   ref, two-dot          -> 4/10/50  (invents deletions for c6+c7)
#   bare name, two-dot    -> 4/30/0   (today's /walk-commits and /visual-recap:
#                                      the operator fault is *masked* while the
#                                      ref fault is live, which is why the two
#                                      fixes had to ship together)
first_diff_line=""
for site in $base_sites; do
    line="$(extract_range_lines "$repo_root/$site" | grep -m1 '^git diff' || true)"
    [[ -n "$line" ]] || continue
    block="$(extract_detect_block "$repo_root/$site")"

    stale_name="${line//\$BASE_REF/\$BASE_BRANCH}"
    assert_eq '4/30/0' "$(stat_triple "$(run_in_fixture "$block" "$stale_name")")" \
        "$site: using the bare name as the endpoint inflates the diff (the #298 defect is reachable here)"

    two_dot="${line/\.\.\./..}"
    if [[ "$two_dot" == "$line" ]]; then
        printf '  FAIL %s: could not build a two-dot mutant from %q; the documented diff is not three-dot\n' "$site" "$line"
        fail=$((fail + 1))
    else
        assert_eq '4/10/50' "$(stat_triple "$(run_in_fixture "$block" "$two_dot")")" \
            "$site: two-dot 'git diff' invents deletions for base-side work (the operator defect propagates here)"
    fi

    both="${stale_name/\.\.\./..}"
    assert_eq '4/30/0' "$(stat_triple "$(run_in_fixture "$block" "$both")")" \
        "$site: with the bare name, two-dot and three-dot agree — the operator defect is masked until the ref is fixed"

    [[ -n "$first_diff_line" ]] || first_diff_line="$line"
done

[[ -n "$first_diff_line" ]] || fatal "no site documents a 'git diff' range line; the controls above ran on nothing"

# -----------------------------------------------------------------------------

section "the guarded fallback degrades to the local branch with no remote"

# The documented residual: with no remote (or a remote not named origin),
# `origin/$BASE_BRANCH` does not resolve and BASE_REF falls back to the bare
# name. That is stale-local behavior by construction, which is why each site
# states it in prose — but the block must still *run* and still produce an
# answer rather than a `fatal: ambiguous argument`.
noremote="$base_sandbox/noremote"
(
    mkdir -p "$noremote"
    cd "$noremote"
    git init -q -b prod .
    git config user.email skillkit@example.invalid
    git config user.name 'Skill Kit Test'
    git config commit.gpgsign false
    echo seed > seed.txt && git add seed.txt && git commit -q -m c1
    git checkout -q -b feature
    seq 1 7 | sed 's/^/feat /' > feature.txt
    git add feature.txt && git commit -q -m F1
)

for site in $base_sites; do
    block="$(extract_detect_block "$repo_root/$site")"
    set +e
    resolved="$(cd "$noremote" && eval "$block" >/dev/null 2>&1; printf '%s|%s' "${BASE_BRANCH:-}" "${BASE_REF:-}")"
    set -e
    assert_eq 'prod|prod' "$resolved" \
        "$site falls back to the local branch when origin/<base> does not resolve"

    # Run the block with the streams kept apart, and assert the note is on the
    # one that does not carry the block's answer. See the fallback_note comment
    # above for the three mutations a source grep cannot separate.
    set +e
    fb_out="$(cd "$noremote" && eval "$block" 2>/dev/null)"
    fb_err="$(cd "$noremote" && eval "$block" 2>&1 >/dev/null)"
    set -e
    assert_contains "$fb_err" "$fallback_note" \
        "$site announces the fallback on stderr when origin/<base> does not resolve"
    if [[ "$fb_out" == *"$fallback_note"* ]]; then
        printf '  FAIL %s puts the fallback note on stdout, where it lands ahead of the value a consumer reads\n' "$site"
        fail=$((fail + 1))
    else
        printf '  ok   %s keeps the fallback note off stdout\n' "$site"
        pass=$((pass + 1))
    fi

    line="$(extract_range_lines "$repo_root/$site" | grep -m1 '^git diff' || true)"
    [[ -n "$line" ]] || continue
    set +e
    out="$(cd "$noremote" && eval "$block" >/dev/null 2>&1; eval "$line" 2>&1)"
    status=$?
    set -e
    assert_eq 0 "$status" "$site's diff line is still a valid invocation with no remote"
    assert_eq '1/7/0' "$(stat_triple "$out")" "$site still measures the branch correctly with no remote"
done

# -----------------------------------------------------------------------------

section "no skill uses a base branch NAME where a ref belongs — anywhere"

# This is the census the #298 fix needed and the first draft of this suite did
# not run. `$base_sites` above enumerates skills that carry *this block*, which
# is enumeration by the assignment's wording. The defect is not the wording; it
# is "a base branch used as a range endpoint," and a site can commit it without
# ever adopting the block. Review found exactly that: compound/SKILL.md shipped
# a runnable `git diff main...HEAD --stat`, a hardcoded name that does not even
# reach the stale-local behavior — it exits 128 on every repo whose base is not
# `main`, including this one. It could never enter `$base_sites`, so nothing
# above ran against it.
#
# pre-merge/references/restated-claims.md names the tell: "every site found
# shares one wording, or they all live in one kind of file." Both were true.
# So this section enumerates by *what the claim does* — every `git diff` or
# `git log` range against HEAD, in every skill and in the review checklist —
# and it subsumes the narrow restatement check it replaces. Four defects fall
# under it at once: a hardcoded name, a bare `$BASE_BRANCH`, a two-dot `git
# diff`, and a three-dot `git log`.

# The endpoint is matched structurally (optional flags, optional quote, a
# variable or a bare word, then the dots) rather than by any site's phrasing,
# which is what makes this a census and not a fifth copy of one site's wording.
range_pattern='git (diff|log)( +--?[a-z-]+)* +"?[$]?\{?[A-Za-z_][A-Za-z0-9_{}]*\}?\.\.\.?HEAD'
# The scan set has to match the label above it, or this section commits the
# overclaim it exists to prevent. `*/references/*.md` install into the skill
# directories and are read at runtime; `docs/*.md` are the canonical copies
# those are synced from. A hardcoded range planted in either was invisible to
# an earlier draft that scanned only `*/SKILL.md` — same defect class, same
# file class the label claimed to cover.
scan_files="$(cd "$repo_root" && ls ./*/SKILL.md ./*/references/*.md ./docs/*.md 2>/dev/null) pre-merge/review-checklist.md"

# shellcheck disable=SC2086
range_hits="$(cd "$repo_root" && { grep -hoE "$range_pattern" $scan_files || true; })"
range_count="$(printf '%s\n' "$range_hits" | grep -c . || true)"

# Non-vacuity, and the specific kind this section needs. A count floor alone
# would not notice a range written in a shape the pattern cannot parse — it
# would just quietly drop out of the census, which is the failure this whole
# section exists to fix. So compare against the raw number of `..HEAD` ranges
# in the same files: the detector must account for every one of them.
# shellcheck disable=SC2086
raw_ranges="$(cd "$repo_root" && { grep -hoE '\.\.\.?HEAD' $scan_files | grep -c . || true; })"
assert_eq "$raw_ranges" "$range_count" \
    "the endpoint pattern accounts for every '..HEAD' range in the scanned files (none silently unparsed)"
# A global floor has slack in it, and slack is where a real loss hides: with 11
# ranges and a floor of 8, any three could be deleted silently — including all
# three of /pre-merge's, one of which is the line telling a reviewer to cite the
# diff-stat numbers in a Review-friendly Size finding. So the floor is per-file and
# derived: every skill that carries the detection block must document at least
# one range, and so must the review checklist that restates the command.
for site in $base_sites pre-merge/review-checklist.md; do
    site_ranges="$(cd "$repo_root" && { grep -cE "$range_pattern" "$site" || true; })"
    if [[ "$site_ranges" -ge 1 ]]; then
        printf '  ok   %s documents %s range endpoint(s) for the census to check\n' "$site" "$site_ranges"
        pass=$((pass + 1))
    else
        printf '  FAIL %s documents no range endpoint; the census is silent about a file it should cover\n' "$site"
        fail=$((fail + 1))
    fi
done

bad_endpoint=0
bad_operator=0
while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    verb="$(printf '%s' "$hit" | awk '{print $2}')"
    # The endpoint char class excludes '.' so the greedy prefix cannot eat the
    # first dot of a three-dot range and leave it in the captured name.
    endpoint="$(printf '%s' "$hit" | sed -E 's/.*[ "]([^ ".]*)\.\.\.?HEAD$/\1/')"
    dots="$(printf '%s' "$hit" | grep -oE '\.\.\.?HEAD$')"

    if [[ "$endpoint" != "${d}BASE_REF" ]]; then
        printf '  FAIL %s uses %q as a range endpoint; only %sBASE_REF is a ref — a name is frozen at checkout time\n' \
            "$verb" "$endpoint" "$d"
        bad_endpoint=$((bad_endpoint + 1))
    fi
    # Three-dot diffs from the merge base; two-dot subtracts base-side work and
    # reports it as deletions this branch never made. `git log` is the mirror:
    # two-dot is the commits on this branch, three-dot is the symmetric
    # difference and pulls in the base's own commits.
    case "$verb:$dots" in
        diff:...HEAD|log:..HEAD) ;;
        *) printf '  FAIL %s uses %q; diff must be three-dot and log must be two-dot\n' "$verb" "$dots"
           bad_operator=$((bad_operator + 1)) ;;
    esac
done <<< "$range_hits"

assert_eq 0 "$bad_endpoint" "every documented range endpoint is a ref, not a branch name"
assert_eq 0 "$bad_operator" "every documented range uses the operator its verb requires"

# -----------------------------------------------------------------------------

section "every documented base-branch NAME claim produces the name it claims"

# The census above enumerates by what a *range* claim does. It still cannot see
# a **name** claim. /closeout wants the base branch's name — it feeds `git
# switch` — so it documents no range and carries no `BASE_BRANCH=` assignment,
# and it therefore fell in no block of either population: the extraction census
# keyed on the assignment's wording, the range census on `..HEAD`. Nothing ran
# its line. It emitted `origin/prod` where its own inline comment claimed
# `prod`, on every healthy repo, for as long as the line has existed (#310).
# Header lesson 6 was learned for range claims and never generalized; this
# section is the generalization, and it is why lesson 7 exists.
#
# The population is every line carrying the literal `origin/HEAD`, partitioned
# into `fenced` (an agent copies it and runs it) and `prose` (a citation inside
# an inline-code span). Membership is total *with respect to that literal* —
# and that is the honest reach, not "anything that could be a name claim". A
# site resolving the base some other way (`git remote show origin`, `gh repo
# view --json defaultBranchRef`) makes the same claim with the same failure
# mode and does NOT enter this population. Widen the signal when such a site
# appears; do not read the current green as covering it. What the loose literal
# *does* buy is that the population is not keyed on the one command shape the
# runner knows: a claim written as `git rev-parse --abbrev-ref origin/HEAD` is
# in the population and fails loudly (below) rather than being absent, where
# its absence would read as coverage.
name_signal='origin/HEAD'
# The one shape the runner knows how to execute. A fenced claim that does NOT
# match this fails loudly rather than being skipped: extending the runner is a
# deliberate act, and a silent skip is what this whole section exists to end.
name_invocation='git symbolic-ref'

# Partition every line carrying the signal into `fenced` and `prose`.
classify_name_claims() {
    awk -v label="$2" -v signal="$3" '
        /^[[:space:]]*```/ { infence = !infence; next }
        index($0, signal) {
            printf "%s\t%s\t%d\t%s\n", (infence ? "fenced" : "prose"), label, FNR, $0
        }
    ' "$1"
}

# DETECTOR: is the signal INSIDE an inline-code span on this line?
#
# Strip balanced `...` pairs left to right; if the signal survives the strip it
# was never inside a span, so the line is a bare recipe an agent will copy and
# must be fenced instead. Two earlier drafts of this predicate were wrong, and
# both are recorded in header lesson 7(c):
#   - "does the line still say something once code spans are removed" — a bare
#     recipe has no spans, so nothing was removed and every bare recipe passed.
#   - "is there a backtick somewhere before the signal and somewhere after it"
#     — prose here is dense with inline code, so a recipe dropped mid-sentence
#     is almost always straddled by unrelated spans. Found in review, with a
#     planted line whose signal sat between a `base` span and a `git switch` one.
signal_is_inline_code() {
    # shellcheck disable=SC2016  # the backticks are markdown delimiters in a sed script, not command substitution
    ! printf '%s' "$1" | sed 's/`[^`]*`//g' | grep -qF "$name_signal"
}

# DETECTOR: can the runner execute this claim?
claim_is_runnable() { [ "${1#*"$name_invocation"}" != "$1" ]; }

# Both detectors have zero hits as their healthy state, which is the kind that
# rots silently — a floor says "we looked at N lines", never "the predicate
# still discriminates". So each is run against a fixture it MUST flag and a
# corrected fixture it MUST NOT, the shape test-guards-can-fire.sh uses and
# docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md
# Prevention #2 prescribes.
# shellcheck disable=SC2016  # fixtures are literal markdown, not expansions
bare_recipe='Use the `base` value: run git symbolic-ref refs/remotes/origin/HEAD --short to get it, then hand it to `git switch`.'
# shellcheck disable=SC2016
cited_recipe='The repo declares its base (`git symbolic-ref refs/remotes/origin/HEAD`). Do not assume `main`.'
if signal_is_inline_code "$bare_recipe"; then
    fatal "the inline-code detector calls a bare straddled recipe 'prose' — the prose branch below now passes every copyable recipe."
fi
printf '  ok   inline-code detector flags a bare recipe straddled by unrelated code spans\n'; pass=$((pass + 1))
if signal_is_inline_code "$cited_recipe"; then
    printf '  ok   inline-code detector leaves a genuinely cited command alone\n'; pass=$((pass + 1))
else
    fatal "the inline-code detector flags the CORRECTED form, so the fix it prescribes does not clear it."
fi
if claim_is_runnable 'git rev-parse --abbrev-ref origin/HEAD'; then
    fatal "the runnable detector calls an unknown shape runnable — the unknown-shape branch below can never fire."
fi
printf '  ok   runnable detector flags a name claim written in a shape the runner does not know\n'; pass=$((pass + 1))
# shellcheck disable=SC2016  # fixture is a literal skill line, not an expansion
if claim_is_runnable 'BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short)'; then
    printf '  ok   runnable detector accepts the shape the runner executes\n'; pass=$((pass + 1))
else
    fatal "the runnable detector rejects the shape it is named for; every fenced claim would fail as unrunnable."
fi

name_claims=""
# shellcheck disable=SC2086
for name_file in $scan_files; do
    name_claims="$name_claims$(classify_name_claims "$repo_root/$name_file" "${name_file#./}" "$name_signal")"$'\n'
done

fenced_claims="$(printf '%s\n' "$name_claims" | grep -c "^fenced$(printf '\t')" || true)"

# Per-site, not a global floor. A global floor has slack in it and slack is
# where a real loss hides — the range census says exactly this about itself
# ninety lines up, and the detection-block floor above carries the incident
# that proves it (a stale `4` made reverting /compound a green no-op). Review
# reproduced the hole here: add a seventh claim anywhere, delete /closeout's
# line, and the run went green with the assertion this section exists for
# silently absent. So every site that must carry a runnable name claim is named
# by derivation, and each must contribute at least one.
for site in $base_sites closeout/SKILL.md; do
    site_claims="$(printf '%s\n' "$name_claims" | grep -c "^fenced$(printf '\t')$site$(printf '\t')" || true)"
    if [[ "$site_claims" -ge 1 ]]; then
        printf '  ok   %s documents %s runnable base-branch name claim(s)\n' "$site" "$site_claims"
        pass=$((pass + 1))
    else
        printf '  FAIL %s documents no runnable base-branch name claim; the census is silent about a file it must cover\n' "$site"
        fail=$((fail + 1))
    fi
done

# The global floor stays as non-vacuity for the DERIVATION itself: the per-site
# loop above is silent about a site nobody thought to name.
if [[ "$fenced_claims" -ge 6 ]]; then
    printf '  ok   derived %s runnable base-branch name claims to execute\n' "$fenced_claims"
    pass=$((pass + 1))
else
    printf '  FAIL derived only %s runnable base-branch name claims; the checks below are running on almost nothing\n' "$fenced_claims"
    fail=$((fail + 1))
fi

# Run each one in the clone fixture, which has refs/remotes/origin/HEAD set and
# a base branch named `prod`. Harvest the name the line produced whichever way
# it produced it — printed to stdout, or left in $BASE_BRANCH — because *how*
# the claim delivers the name is the wording this census refuses to key on.
name_out="$base_sandbox/name-claim.out"
while IFS="$(printf '\t')" read -r kind site lineno line; do
    [[ "$kind" == "fenced" ]] || continue
    if ! claim_is_runnable "$line"; then
        printf '  FAIL %s:%s makes a base-branch name claim this census cannot run; teach the runner rather than letting it drop out\n       line: %s\n' \
            "$site" "$lineno" "$line"
        fail=$((fail + 1))
        continue
    fi
    resolved="$(
        cd "$work" || exit 1
        set +e
        eval "$line" > "$name_out" 2>/dev/null
        printed="$(cat "$name_out")"
        printf '%s' "${printed:-${BASE_BRANCH:-}}"
    )"
    assert_eq prod "$resolved" "$site:$lineno produces the base branch NAME (not a remote-tracking ref)"

    # The section is named "produces the name it CLAIMS", and equality against
    # the fixture's base does not test that: #310's defect was output
    # disagreeing with the line's own inline comment, and rewriting the comment
    # to claim `origin/prod` would leave the assertion above green. So when the
    # line carries `-> <name>` claims, the name it really produced must be among
    # them. Sites with no such comment skip this and keep the equality above.
    #
    # `|| true` INSIDE the substitution, before the pipe: this file runs under
    # `set -o pipefail`, so grep's exit 1 on a line with no claim would fail the
    # assignment and kill the run under `set -e` — silently, mid-section, with
    # no assertion and no message. That is the same defect the range extractor
    # above documents, and this section's first draft shipped it: the suite
    # exited after the first claim-less site and every "green" reading of it was
    # an early exit, not a pass.
    claimed="$({ printf '%s' "$line" | grep -oE '→ *[A-Za-z0-9/_.-]+' || true; } | sed 's/→ *//' | tr '\n' ' ')"
    if [[ -n "$claimed" ]]; then
        if [[ " $claimed" == *" $resolved "* ]]; then
            printf '  ok   %s:%s produces a name its own comment claims (claimed: %s)\n' "$site" "$lineno" "${claimed% }"
            pass=$((pass + 1))
        else
            printf '  FAIL %s:%s produces %q, which its own comment does not claim (claimed: %s)\n' \
                "$site" "$lineno" "$resolved" "${claimed% }"
            fail=$((fail + 1))
        fi
    fi
done <<< "$name_claims"

# The other half of the partition. An unfenced line is only *prose* if it cites
# the mechanism inside an inline-code span; a bare invocation outside a fence is
# a recipe an agent will copy, and it must be fenced — which puts it in the
# population above and gets it RUN — not left as unrun text.
while IFS="$(printf '\t')" read -r kind site lineno line; do
    [[ "$kind" == "prose" ]] || continue
    if signal_is_inline_code "$line"; then
        printf '  ok   %s:%s cites the command inside a sentence, not as a runnable recipe\n' "$site" "$lineno"
        pass=$((pass + 1))
    else
        printf '  FAIL %s:%s documents a base-branch name command outside any fence and outside inline code; fence it so the census runs it\n       line: %s\n' \
            "$site" "$lineno" "$line"
        fail=$((fail + 1))
    fi
done <<< "$name_claims"

# -----------------------------------------------------------------------------

# /closeout resolves the same base branch and must NOT grow a BASE_REF: it feeds
# the name to `git switch`, which rejects a remote-tracking ref outright. The
# census above already catches it growing a *range* endpoint of any shape, which
# is the half its note claims ("never uses the base as a range endpoint"). This
# pins the other half — the note itself — so a sweep across the five sites
# cannot quietly "fix" a correct one.
#
# Two assertions, not one conditional. The first draft here fired only *if*
# closeout mentioned BASE_REF at all — so deleting the note deleted the check's
# own trigger and the mutation went green. A guard that disappears with the
# thing it guards is not a guard.
closeout_note="does \*not\* grow the \`${d}BASE_REF\` guard"
if grep -q "$closeout_note" "$repo_root/closeout/SKILL.md"; then
    printf '  ok   /closeout still says why it deliberately does not take the ref\n'
    pass=$((pass + 1))
else
    printf '  FAIL /closeout no longer explains why it keeps the bare name; the next sweep will "fix" a correct site\n'
    fail=$((fail + 1))
fi

if grep -qE "^[[:space:]]*(git (diff|log) .*)?\\${d}\\{?BASE_REF" "$repo_root/closeout/SKILL.md"; then
    printf '  FAIL /closeout runs a command against BASE_REF; it needs the base branch name, not a ref\n'
    fail=$((fail + 1))
else
    printf '  ok   /closeout runs no command against a remote-tracking ref\n'
    pass=$((pass + 1))
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
