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
# base branch every skill asks `sidecar.sh base-ref` for (#298, #598): the verb
# is run once in a clone whose local base is stale, every skill's whole block
# is run there with its range lines scored one at a time (#616), /closeout's
# `--name` block is run for the bare name (#310), and a census fails, naming
# the file, if any skill derives the base itself again. Every fenced bash block in
# /excavate's process section is also run, against a fixture dated 2020 with an
# absolute SINCE; its gh blocks are an explicit, named, counted skip set rather
# than a silent one. Extend the suite when a skill
# documents another runnable command; do not maintain a list of the commands in
# prose, since that list is itself the thing that drifts.
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
#            plant the corrected shape and require silence. EACH detector here
#            carries one — say "each", never a count: this file shipped
#            "both detectors" at four sites and then grew a third, and every
#            one of the four went stale in the same PR. The oracle needed one
#            too and was missed precisely because it is not a detector; its
#            healthy state on a claimless line is silence, so when it stopped
#            extracting, the assertion it feeds vanished with no message. A floor says
#            "we looked at N lines"; it never says the predicate still
#            discriminates, and drafts (c)(1) and (c)(2) both passed a floor.
#            Likewise a floor over the whole population is not a floor over any
#            site in it: the first draft's global `-ge 6` let a seventh claim
#            planted anywhere mask the deletion of the one site this section
#            exists for. It is now per-site. (The global floor was then deleted
#            outright in the next round — once the per-site loop existed, the
#            floor could not fail while those checks passed, which is 7(b)
#            again, one round later, in the fix for 7(e).)
#        (f) A check that reads an environment variable to decide what the
#            SUBJECT produced cannot tell the subject from its caller. The
#            harvest fell back to `$BASE_BRANCH` to catch a line that assigns
#            rather than prints — and the subshell inherits that variable, so
#            with `BASE_BRANCH=prod` exported a /closeout line rewritten to emit
#            NOTHING passed every assertion and the suite reported 138/0. It is
#            cleared before the eval now. The variable is not exotic: it is the
#            one five skills in this pack tell an agent to assign, three lines
#            from where they say to run these blocks.
#        (g) An oracle built from a line's prose must key on the CLAIM, not on
#            the punctuation the claim happens to use. The comment-claim check
#            first grabbed every `→` on the line and treated each right-hand
#            side as an expected output. Trimming /closeout's comment to one
#            worked example reddened a correct command, and an unrelated arrow
#            elsewhere produced `claimed: the` — the parser reading English. It
#            now reads the mapping whose left-hand side is the ref the fixture
#            actually resolves, and skips a comment that claims nothing about it.
#   8. Do not hand a block what its own earlier lines compute. This suite ran
#      each skill's range lines with BASE_REF preset, so a wrong SC path, a
#      BASE_REF= line below its readers, and a range line in a later block than
#      its assignment all stayed green (#616). The last of those was live at
#      three sites, /compound, /help, and /execute's guard sweep, where a fresh
#      shell reads an empty BASE_REF and git answers with an empty range.
#
# WHAT THIS SUITE DOES NOT HOLD, said plainly so a green run is not misread:
# the derivation census keys on the ways of asking a remote for its default
# branch, and the candidate-name lists, that it names. A skill that finds the base some way the signal does
# not list is not caught; widen the signal when one appears. The verb's own
# outcomes are pinned in test-sidecar-resolution.sh, not here.

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

# A caller that reached this suite via a git hook (pre-push, run from a linked
# worktree) has GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE set in its environment.
# The fixture below runs `git init -q .` and `git config` in $sandbox, and would
# inherit them: git prefers an explicit GIT_DIR to discovering a repository from
# the working directory, so the fixture would re-initialize and configure the
# real repository instead, writing `core.bare=true` and the fixture identity
# into the shared .git/config while the suite still reports green. See
# docs/solutions/testing-patterns/scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md.
# Unset before the first fixture git call.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

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
# Base branch: one verb, one clone-bearing fixture (#298, #597, #598)
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
# Every skill now asks `sidecar.sh base-ref` for the base instead of deriving
# it, so the derivation is run once (below), a census forbids a copy from
# coming back, and each skill's whole block runs in the fixture and asks the
# verb itself. The wrong forms are built by mutating those extracted blocks, so
# a site that stops carrying the documented shape fails loudly rather than
# being skipped.

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
    printf '  ok   the clone has refs/remotes/origin/HEAD set, so base-ref exercises its origin/HEAD path\n'
    pass=$((pass + 1))
else
    printf '  FAIL refs/remotes/origin/HEAD is unset; base-ref would fall through to its candidate loop\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "the base-ref verb answers a ref and a name in the stale-base clone"

# The one run of the derivation (#598). Five skills each carried a copy of it
# until then, and this section ran every copy against the fixture; the copies
# are gone, so the verb is run here once instead. Its three outcomes (declared,
# fallback, refusal) are pinned in depth by test-sidecar-resolution.sh. What
# only this fixture can show is the stale-local case: the answer must be the
# remote-tracking ref, because the local `prod` is four commits behind it.
# A literal dollar, spliced in from a variable rather than written inside
# quotes: inline, it is indistinguishable to a reader and to the linter alike
# from a variable that failed to expand. Used by the census checks below.
d='$'
sidecar="$repo_root/init-pipeline/scripts/sidecar.sh"
[[ -f "$sidecar" ]] || fatal "init-pipeline/scripts/sidecar.sh is gone; every skill asks it for the base"
placeholder="<this skill's directory>/references/sidecar.sh"
# An empty sidecar root, so the verb takes its no-sidecar path here no matter
# what sidecars exist on the machine running this suite.
no_sidecars="$base_sandbox/no-sidecars"
mkdir -p "$no_sidecars"
run_base_ref() {
    local dir="$1"; shift
    ( cd "$dir" && SKILL_KIT_SIDECAR_ROOT="$no_sidecars" bash "$sidecar" base-ref "$@" )
}

set +e
fixture_ref="$(run_base_ref "$work" 2>"$base_sandbox/base-ref.err")"
ref_status=$?
fixture_name="$(run_base_ref "$work" --name 2>/dev/null)"
name_status=$?
set -e
assert_eq 0 "$ref_status" "base-ref exits 0 in a clone with origin/HEAD set"
assert_eq 'origin/prod' "$fixture_ref" \
    "base-ref answers the remote-tracking ref, not the stale local branch"
assert_eq '' "$(cat "$base_sandbox/base-ref.err")" \
    "base-ref says nothing on stderr when origin/<base> resolves"
assert_eq 0 "$name_status" "base-ref --name exits 0 in the same clone"
assert_eq 'prod' "$fixture_name" "base-ref --name answers the bare branch name"

# With no remote, `origin/<base>` cannot resolve and the verb falls back to the
# local branch. That is stale-local behavior by construction, so the note on
# stderr is the only thing telling the operator the measurement is degraded.
# It is checked by RUNNING the verb with the streams kept apart: a note on
# stdout would land in the value a skill assigns to BASE_REF.
fallback_note='does not resolve — measuring against the local branch, which may be stale'
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
set +e
fb_out="$(run_base_ref "$noremote" 2>"$base_sandbox/base-ref-fb.err")"
fb_status=$?
set -e
assert_eq 0 "$fb_status" "base-ref exits 0 when it falls back to the local branch"
assert_eq 'prod' "$fb_out" "base-ref falls back to the local branch, and stdout carries only the ref"
assert_contains "$(cat "$base_sandbox/base-ref-fb.err")" "$fallback_note" \
    "base-ref announces the fallback on stderr"

# -----------------------------------------------------------------------------

section "no skill carries its own base-branch derivation"

# The contract half of the sweep, added in the sweep's own change as
# docs/solutions/architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md
# requires. The derivation lives once, in init-pipeline/scripts/sidecar.sh; a
# skill that derives the base itself is a copy that can drift from it, which is
# how #298 and #310 happened.
#
# The signal is loose on purpose (header lesson 7(a)). It is not the one wording
# the copies used: it is any `symbolic-ref`, any `git` command that names
# `origin/HEAD`, any other way of asking a remote for its default branch,
# BASE_REF assigned from the `--name` form, which is a name used as a ref, and
# two candidate branch names in a row, the fallback loop that runs on any repo
# where `origin/HEAD` is unset (#618). A citation inside inline code counts: execute/SKILL.md's cited
# `git symbolic-ref` was one an agent was told to run (#310).
#
# The scan set is every markdown file one level down (`*/SKILL.md`,
# `pre-merge/review-checklist.md`, `docs/*.md`) plus the bundled `references/`
# copies. Not scanned, deliberately: `docs/solutions/**`, whose entries quote
# defective lines on purpose, the root files (CHANGELOG.md, README.md), and
# init-pipeline/scripts/sidecar.sh, which is where the derivation belongs.
# shellcheck disable=SC2016  # the pattern matches literal markdown, not expansions
derivation_signal='symbolic-ref|(^|[^[:alnum:]_])git [^`]*origin/HEAD|defaultBranchRef|ls-remote --symref|remote show origin|BASE_REF="?\$\(bash "\$SC" base-ref --name|(^|[^[:alnum:]_-])(main|master|prod|develop|trunk) +(main|master|prod|develop|trunk)([^[:alnum:]_-]|$)'
derivation_copies() {
    # Prints <file>:<line> for every line under $1 that derives the base itself.
    ( cd "$1" && for f in ./*/*.md ./*/references/*.md; do
        [ -f "$f" ] || continue
        { grep -nE "$derivation_signal" "$f" || true; } | cut -d: -f1 | sed "s|^|${f#./}:|"
    done )
}

# Self-check: a detector whose healthy state is silence needs a planted hit
# (header lesson 7(e)). Each planted copy must be named by file and line, and
# the clean file and the excluded docs/solutions entry must stay silent.
planted="$base_sandbox/planted-copies"
mkdir -p "$planted/fenced" "$planted/cited" "$planted/bundled/references" \
    "$planted/asname" "$planted/fallback" "$planted/clean" "$planted/docs/solutions/x"
# shellcheck disable=SC2016  # planted fixtures are literal markdown
{
    printf '# Fenced\n\n```bash\n'
    printf '%s\n' 'BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed '"'"'s@^origin/@@'"'"')'
    printf '```\n'
} > "$planted/fenced/SKILL.md"
# shellcheck disable=SC2016
printf '%s\n' 'The base is whatever `git rev-parse --abbrev-ref origin/HEAD` prints.' > "$planted/cited/notes.md"
# shellcheck disable=SC2016
printf '%s\n' 'BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)' > "$planted/bundled/references/copy.md"
# shellcheck disable=SC2016
printf '%s\n' 'BASE_REF="$(bash "$SC" base-ref --name)"' > "$planted/asname/SKILL.md"
# shellcheck disable=SC2016
{
    printf '%s\n' 'for b in main master prod develop trunk; do'
    printf '%s\n' '  git rev-parse --verify -q "origin/$b" >/dev/null && { BASE_BRANCH="$b"; break; }'
    printf '%s\n' 'done'
} > "$planted/fallback/SKILL.md"
# shellcheck disable=SC2016
{
    printf '%s\n' 'SC="<this skill'"'"'s directory>/references/sidecar.sh"'
    printf '%s\n' 'BASE_REF="$(bash "$SC" base-ref)" || exit 1'
    printf '%s\n' 'BASE_BRANCH="$(bash "$SC" base-ref --name)" || exit 1'
    printf '%s\n' 'It answers the `origin/HEAD` default when no base_ref is declared.'
    printf '%s\n' 'Many repos use `prod`, `develop`, or `trunk` rather than `main` or `master`.'
} > "$planted/clean/SKILL.md"
cp "$planted/fenced/SKILL.md" "$planted/docs/solutions/x/entry.md"
assert_eq 'asname/SKILL.md:1 bundled/references/copy.md:1 cited/notes.md:1 fallback/SKILL.md:1 fenced/SKILL.md:4' \
    "$(derivation_copies "$planted" | sort | tr '\n' ' ' | sed 's/ $//')" \
    "the census names each planted copy by file and line, and nothing else"

live_copies="$(derivation_copies "$repo_root" | tr '\n' ' ' | sed 's/ $//')"
assert_eq '' "$live_copies" \
    "no skill derives the base branch itself; each asks sidecar.sh base-ref"

# -----------------------------------------------------------------------------

section "every skill that measures a branch asks the verb, and bundles it"

# Every line the skill runs with a base-branch variable as a range endpoint.
# Anchored at line start so prose restatements (which sit inside sentences)
# are not collected here.
extract_range_lines() {
    # `|| true` because this file runs under `set -o pipefail`: a site that
    # stops carrying a range line would otherwise make the assignment fail and
    # kill the run at that line, *before* the `fatal` guard that names the
    # cause. Found by mutation — reverting compound/SKILL.md to a hardcoded
    # `main` produced a silent exit 1 with no assertion and no message.
    { grep -hE '^[[:space:]]*git (diff|log) .*\$\{?BASE_' "$1" || true; } | sed 's/^[[:space:]]*//'
}

# Derived, not listed: a skill joins by carrying the ref-form assignment.
# shellcheck disable=SC2016  # the marker is literal skill text
verb_marker='BASE_REF="$(bash "$SC" base-ref)"'
verb_sites="$(cd "$repo_root" && { grep -lF "$verb_marker" ./*/SKILL.md || true; } \
    | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//')"
verb_site_count="$(printf '%s\n' "$verb_sites" | tr ' ' '\n' | grep -c . || true)"
# The floor is today's count: /pre-merge and /respond-to-review from #597, and
# the five #598 converted. A drop below it means a site lost the assignment, or
# the derivation above broke and every loop below is running on nothing.
if [[ "$verb_site_count" -ge 7 ]]; then
    printf '  ok   derived %s skills that ask base-ref for the ref\n' "$verb_site_count"
    pass=$((pass + 1))
else
    printf '  FAIL derived only %s skills that ask base-ref for the ref: %s\n' "$verb_site_count" "$verb_sites"
    fail=$((fail + 1))
fi

# A skill that calls "$SC" must ship the resolver it calls, or the installed
# skill runs a path that does not exist. The manifest row is what puts it there.
for site in $verb_sites closeout/SKILL.md; do
    skill="${site%/SKILL.md}"
    if grep -qE "^init-pipeline/scripts/sidecar\.sh[[:space:]]+$skill\$" "$repo_root/scripts/skill-references.manifest" \
        && [[ -f "$repo_root/$skill/references/sidecar.sh" ]]; then
        printf '  ok   %s bundles references/sidecar.sh through the manifest\n' "$skill"
        pass=$((pass + 1))
    else
        printf '  FAIL %s asks base-ref but has no manifest row or no synced references/sidecar.sh\n' "$skill"
        fail=$((fail + 1))
    fi
done

# The range-running sections below run a skill's whole block. /respond-to-review
# is out by name: its two blocks need trailers and a stubbed Bitbucket API this
# fixture does not have, and test-respond-to-review-contract.sh runs both whole.
# The range census further down still checks their endpoints and operators.
# shellcheck disable=SC2086  # word-splitting the space-separated list is the point
run_sites="$(printf '%s\n' $verb_sites | grep -vx 'respond-to-review/SKILL.md' | tr '\n' ' ' | sed 's/ $//')"

# Each fenced block holding a range line, one file per block. The indent is
# stripped the way extract_block_with strips it, so a block lifted from a
# numbered list still matches extract_range_lines' output.
block_root="$base_sandbox/range-blocks"
for site in $run_sites; do
    mkdir -p "$block_root/${site%%/*}"
    awk -v dir="$block_root/${site%%/*}" '
        /^[[:space:]]*```/ {
            if (inblock) {
                if (found) { k++; for (i = 1; i <= n; i++) print buf[i] > (dir "/" k); close(dir "/" k) }
                inblock = 0; next
            }
            inblock = 1; n = 0; found = 0; next
        }
        inblock {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            buf[++n] = line
            if (line ~ /^git (diff|log) .*[$][{]?BASE_/) found = 1
        }
    ' "$repo_root/$site"
done

block_holding() {
    # Prints the block of site $1 that holds range line $2.
    local f
    for f in "$block_root/${1%%/*}"/*; do
        [[ -f "$f" ]] || continue
        if grep -qxF -- "$2" "$f"; then cat "$f"; return 0; fi
    done
    return 0
}

# Runs the whole block in $1, in order and in one shell, and prints what line $3
# of it printed. Only two echoes are added, around that line. Nothing is
# preset: BASE_REF and BASE_BRANCH are cleared, so the block has to compute them
# the way it does in the fresh shell an agent runs it in. The block's status is
# swallowed for the reason run_base_ref's callers use `set +e`: a broken block
# must redden its own named check, not end the run. A block that stops before
# the line prints $block_stopped, so a check whose right answer is empty cannot
# pass on a block that never got there.
range_mark='@@range-line'
block_stopped='<the block stopped before this line>'
run_range_line() {
    local dir="$1" block="$2" line="$3" script out
    # shellcheck disable=SC2016  # the awk program reads ENVIRON, not the shell
    script="$(printf '%s\n' "${block//"$placeholder"/$sidecar}" | LINE="$line" MARK="$range_mark" awk '
        $0 == ENVIRON["LINE"] { print "echo \"" ENVIRON["MARK"] " start\""; print; print "echo \"" ENVIRON["MARK"] " end\""; next }
        { print }')"
    out="$( ( cd "$dir" && env -u BASE_REF -u BASE_BRANCH SKILL_KIT_SIDECAR_ROOT="$no_sidecars" bash -c "$script" 2>&1 </dev/null ) || true )"
    if [[ "$out" != *"$range_mark start"* ]]; then
        printf '%s' "$block_stopped"
        return 0
    fi
    printf '%s\n' "$out" | MARK="$range_mark" awk '
        $0 == ENVIRON["MARK"] " end" { on = 0 }
        on { print }
        $0 == ENVIRON["MARK"] " start" { on = 1 }'
}

# The instrument first (header lesson 7(e)): the three faults #616 exists for
# must each reach the check, and a BASE_REF exported by this suite's caller must
# not stand in for the assignment.
# shellcheck disable=SC2016  # planted blocks are literal skill text
probe_line='git log --oneline "$BASE_REF..HEAD"'
probe_good="SC=\"$placeholder\"
$verb_marker || exit 1
$probe_line"
probe_bad_path="${probe_good//references\/sidecar.sh/scripts/sidecar.sh}"
probe_late="$probe_line
SC=\"$placeholder\"
$verb_marker || exit 1"
probe_no_assign="$probe_line"
assert_eq 2 "$(run_range_line "$work" "$probe_good" "$probe_line" | grep -c .)" \
    "run_range_line reads the probe line's own output from a whole block"
assert_eq "$block_stopped" "$(run_range_line "$work" "$probe_bad_path" "$probe_line")" \
    "a block whose SC path does not exist never reaches its range line"
assert_eq '' "$(run_range_line "$work" "$probe_late" "$probe_line")" \
    "a BASE_REF= line below its reader leaves the range empty, so the oracle reddens"
assert_eq '' "$(BASE_REF=origin/prod run_range_line "$work" "$probe_no_assign" "$probe_line")" \
    "a BASE_REF exported by the caller does not reach the block"

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

for site in $run_sites; do
    lines="$(extract_range_lines "$repo_root/$site")"
    [[ -n "$lines" ]] || fatal "no 'git diff'/'git log' range line found in $site"
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        block="$(block_holding "$site" "$line")"
        # A range line in a block that does not ask the verb reads an empty
        # BASE_REF in a fresh shell, and git answers with an empty range.
        if [[ "$block" != *"$verb_marker"* ]]; then
            printf "  FAIL %s: '%s' sits in a block that does not set BASE_REF from base-ref\n" "$site" "$line"
            fail=$((fail + 1))
            continue
        fi
        out="$(run_range_line "$work" "$block" "$line")"
        # Keyed on the FLAGS, not on the subcommand. The first version of this
        # case matched every `git diff` line and asserted a stat triple against
        # it, so /execute's `--diff-filter=DR --name-status` line — which emits
        # paths, never a summary sentence — parsed as 0/0/0 and reddened four
        # assertions that were describing correct prose. A `git diff` shape this
        # loop does not recognize now fails by name instead of being scored
        # against the wrong oracle or, worse, dropped silently.
        case "$line" in
            "git diff"*--stat*|"git diff"*--shortstat*)
                assert_eq "$truth_files/$truth_ins/$truth_del" "$(stat_triple "$out")" \
                    "$site: '$line' reports the branch's real size"
                ;;
            "git diff"*--diff-filter=*)
                # Asserted against its own planted fixture further down, where a
                # deletion and a rename actually exist. This fixture has neither,
                # so the only thing checkable here is that the line is a valid
                # invocation that stays silent when nothing was deleted — which
                # is the half the rung's prose gates on ("empty output skips it").
                assert_eq '' "$out" \
                    "$site: '$line' stays silent on a branch that deletes nothing"
                ;;
            "git diff -U0 "*)
                # /execute's removed-guard sweep. This fixture branch removes no
                # lines, so the candidate list must be empty; the section below
                # plants a removed guard and checks the list names it.
                assert_eq '' "$out" \
                    "$site: '$line' stays silent on a branch that removes no lines"
                ;;
            "git log"*)
                assert_eq "$truth_commits" "$(printf '%s' "$out" | grep -c .)" \
                    "$site: '$line' lists only the branch's own commits"
                ;;
            *)
                printf '  FAIL %s documents a range line this suite has no oracle for: %q\n' "$site" "$line"
                fail=$((fail + 1))
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
# The name mutant is the block asking `base-ref --name` for BASE_REF, which is
# the #298 defect in the shape it would take today.
#
#   bare name, three-dot  -> 4/30/0   (sweeps in c4+c5, merged before the cut)
#   ref, two-dot          -> 4/10/50  (invents deletions for c6+c7)
#   bare name, two-dot    -> 4/30/0   (/walk-commits and /visual-recap before #298:
#                                      the operator fault is *masked* while the
#                                      ref fault is live, which is why the two
#                                      fixes had to ship together)
first_diff_line=""
for site in $run_sites; do
    # `--stat` selected explicitly: the mutants below are scored with
    # stat_triple, so a site whose first documented diff line is a
    # `--diff-filter` line would have its controls run against an oracle that
    # returns 0/0/0 for every mutant — three green negative controls that
    # separate nothing.
    line="$(extract_range_lines "$repo_root/$site" | grep -m1 '^git diff .*--stat' || true)"
    [[ -n "$line" ]] || continue

    block="$(block_holding "$site" "$line")"
    verb_ref='base-ref)"'
    verb_name='base-ref --name)"'
    stale_name="${block//"$verb_ref"/$verb_name}"
    assert_eq '4/30/0' "$(stat_triple "$(run_range_line "$work" "$stale_name" "$line")")" \
        "$site: using the bare name as the endpoint inflates the diff (the #298 defect is reachable here)"

    two_dot="${line/\.\.\./..}"
    if [[ "$two_dot" == "$line" ]]; then
        printf '  FAIL %s: could not build a two-dot mutant from %q; the documented diff is not three-dot\n' "$site" "$line"
        fail=$((fail + 1))
    else
        assert_eq '4/10/50' "$(stat_triple "$(run_range_line "$work" "${block/"$line"/$two_dot}" "$two_dot")")" \
            "$site: two-dot 'git diff' invents deletions for base-side work (the operator defect propagates here)"
    fi

    assert_eq '4/30/0' "$(stat_triple "$(run_range_line "$work" "${stale_name/"$line"/$two_dot}" "$two_dot")")" \
        "$site: with the bare name, two-dot and three-dot agree — the operator defect is masked until the ref is fixed"

    [[ -n "$first_diff_line" ]] || first_diff_line="$line"
done

[[ -n "$first_diff_line" ]] || fatal "no site documents a 'git diff' range line; the controls above ran on nothing"

# -----------------------------------------------------------------------------

section "the deletion-trigger line finds a real deletion and a real rename"

# /execute Step 4's Deletion Completeness rung and the Boundary Map Contracts
# dimension in /pre-merge review-checklist.md both gate on this line. #326 is
# the incident: the rung gated on a section header that had readers and no
# writer, so it never fired. The header was replaced by the diff, so the diff
# command IS the gate now, and a wrong one fails the same way the header did:
# silently, with the rung reporting nothing to sweep.
#
# The main fixture cannot check this. Its feature branch adds files and deletes
# nothing, so the line correctly emits empty there and an empty result is
# indistinguishable from a broken command. This fixture plants one deletion and
# one rename on the feature branch, and one file deleted on the BASE side after
# the branch was cut — the last one is the negative control that separates
# three-dot from two-dot, exactly as merged-c/merged-d do for the stat line.
deltrig="$base_sandbox/deltrig"
deltrig_up="$base_sandbox/deltrig-upstream"
(
    mkdir -p "$deltrig_up"
    cd "$deltrig_up"
    git init -q -b prod .
    git config user.email skillkit@example.invalid
    git config user.name 'Skill Kit Test'
    git config commit.gpgsign false
    echo keep > keep.txt
    echo doomed > doomed.txt
    printf 'a\nb\nc\nd\ne\nf\ng\nh\n' > moved.txt
    git add -A && git commit -q -m c1
)
git clone -q "$deltrig_up" "$deltrig"
git -C "$deltrig" config user.email skillkit@example.invalid
git -C "$deltrig" config user.name 'Skill Kit Test'
git -C "$deltrig" config commit.gpgsign false
git -C "$deltrig" checkout -q -b feature origin/prod
(
    cd "$deltrig"
    git rm -q doomed.txt
    git mv moved.txt renamed.txt
    echo more >> keep.txt
    git add -A && git commit -q -m F1
)
# Base-side work lands AFTER the branch point. Under `--diff-filter=DR` the
# separating case is an ADDITION on the base, not a deletion: two-dot compares
# origin/prod's tree to HEAD's, so a file the base gained and the branch never
# had reads as `D` — a deletion the branch did not make, which would open a
# consumer-surface sweep for a module nobody removed. (A base-side *deletion*
# reads as `A` under two-dot and the DR filter drops it, so it separates
# nothing here — that mistake was in this section's first draft and the fixture
# caught it.)
(
    cd "$deltrig_up"
    echo base-side > base-added.txt
    git add base-added.txt && git commit -q -m c2
)
git -C "$deltrig" fetch -q origin

# The oracle: sorted status letter + final path, so a rename's similarity score
# (R100 today, R09x if git's heuristic shifts) does not make the assertion
# brittle while the D/R distinction it exists to check stays pinned.
del_oracle() {
    printf '%s\n' "$1" | awk 'NF { print substr($1, 1, 1) " " $NF }' | sort | tr '\n' ';'
}
assert_eq 'D doomed.txt;R renamed.txt;' "$(del_oracle "$(printf 'D\tdoomed.txt\nR100\tmoved.txt\trenamed.txt\n')")" \
    "del_oracle reduces planted name-status output to status letter + final path"
assert_eq '' "$(del_oracle '')" "del_oracle stays empty on empty input"

deltrig_sites=0
for site in $run_sites; do
    line="$(extract_range_lines "$repo_root/$site" | grep -m1 '^git diff .*--diff-filter=' || true)"
    [[ -n "$line" ]] || continue
    deltrig_sites=$((deltrig_sites + 1))

    block="$(block_holding "$site" "$line")"
    out="$(run_range_line "$deltrig" "$block" "$line")"
    assert_eq 'D doomed.txt;R renamed.txt;' "$(del_oracle "$out")" \
        "$site: the deletion-trigger line reports the branch's own deletion and rename"

    # Negative control 1 — two-dot. It sweeps in the base-side deletion, so the
    # rung would open a consumer-surface sweep for a module this branch never
    # touched. Built by mutating the real extracted line, so a site that stops
    # documenting a three-dot range cannot skip its own control.
    two_dot="${line/\.\.\./..}"
    if [[ "$two_dot" == "$line" ]]; then
        printf '  FAIL %s: could not build a two-dot mutant from %q; the documented deletion trigger is not three-dot\n' "$site" "$line"
        fail=$((fail + 1))
    else
        two_out="$(run_range_line "$deltrig" "${block/"$line"/$two_dot}" "$two_dot")"
        assert_eq 'D base-added.txt;D doomed.txt;R renamed.txt;' "$(del_oracle "$two_out")" \
            "$site: two-dot invents a deletion for base-side work the branch never touched"
    fi

    # Negative control 2 — drop the filter. Without it the line reports every
    # modified file too, so the rung fires on any diff at all and the trigger
    # stops discriminating. This is the mutation that most resembles a
    # well-meaning simplification.
    unfiltered="${line/--diff-filter=DR /}"
    if [[ "$unfiltered" == "$line" ]]; then
        printf '  FAIL %s: could not build an unfiltered mutant from %q; the documented filter is not --diff-filter=DR\n' "$site" "$line"
        fail=$((fail + 1))
    else
        unf_out="$(run_range_line "$deltrig" "${block/"$line"/$unfiltered}" "$unfiltered")"
        assert_eq 'D doomed.txt;M keep.txt;R renamed.txt;' "$(del_oracle "$unf_out")" \
            "$site: without --diff-filter=DR the line also reports plain modifications, so the trigger stops discriminating"
    fi
done

# The floor. #326 replaced a trigger that had readers and no writer; a suite
# that silently checks zero sites would be the same failure one level up. Only
# SKILL.md files are in $run_sites, so the reachable floor here is 1;
# review-checklist.md is checked by name below.
if [[ "$deltrig_sites" -ge 1 ]]; then
    printf '  ok   derived %s site(s) documenting the deletion-trigger line\n' "$deltrig_sites"
    pass=$((pass + 1))
else
    printf '  FAIL no site documents a --diff-filter deletion-trigger line; every check in this section ran on nothing\n'
    fail=$((fail + 1))
fi

# review-checklist.md is not a SKILL.md, so it is outside $run_sites and outside
# every loop above. It documents the same command and must not drift from the
# canonical statement in /execute, which is what its own prose promises (it
# names /execute Step 4's Tier 1 rung as "the canonical statement"). Compare the
# two literals directly — this is the mechanism behind that sentence.
exec_del="$(extract_range_lines "$repo_root/execute/SKILL.md" | grep -m1 '^git diff .*--diff-filter=' || true)"
check_del="$(extract_range_lines "$repo_root/pre-merge/review-checklist.md" | grep -m1 '^git diff .*--diff-filter=' || true)"
[[ -n "$exec_del" ]]  || fatal "execute/SKILL.md no longer documents a --diff-filter deletion-trigger line"
[[ -n "$check_del" ]] || fatal "pre-merge/review-checklist.md no longer documents a --diff-filter deletion-trigger line"
assert_eq "$exec_del" "$check_del" \
    "pre-merge/review-checklist.md's deletion trigger is byte-identical to /execute's canonical one"

# -----------------------------------------------------------------------------

section "the sentence that gates the rung names the diff, not a header"

# The command above is pinned to the byte. The sentence an agent reads to decide
# whether to run it at all is a second operative site for the same trigger, and
# a sentence nothing checks can regress to the header gate while the command
# and its assertions stay green — #326's defect one level in. So pin the gate
# sentence at both sites: it names the diff as the trigger and does not name
# the header as one.
# coverage: enumerated — the two sites that carry the deletion-trigger line,
# the same pair the byte-identity check above fatals on if either drops it.
for site in execute/SKILL.md pre-merge/review-checklist.md; do
    gate_line="$(grep -m1 -E '^\*\*(Deletion Completeness|For deletion orphan surfaces) \(' "$repo_root/$site" || true)"
    [[ -n "$gate_line" ]] || fatal "$site no longer opens the deletion rung with a bolded gate sentence"
    if grep -q 'diff.*deletes or renames' <<<"$gate_line"; then
        printf '  ok   %s gates the deletion rung on the diff deleting or renaming\n' "$site"
        pass=$((pass + 1))
    else
        printf '  FAIL %s gate sentence no longer names the diff as the trigger: %q\n' "$site" "$gate_line"
        fail=$((fail + 1))
    fi
    if grep -q 'only when the slice body' <<<"$gate_line"; then
        printf '  FAIL %s gate sentence regressed to the header gate: %q\n' "$site" "$gate_line"
        fail=$((fail + 1))
    else
        printf '  ok   %s gate sentence does not gate on a ### Deletes header\n' "$site"
        pass=$((pass + 1))
    fi
done

# -----------------------------------------------------------------------------

section "the checklist's author-mode block refuses to run without a base ref"

# Found by an independent probe of #333: with $BASE_REF unset, git reads the
# empty left endpoint of `...HEAD` as HEAD itself, exits 0, and prints nothing —
# which the rung's own prose reads as "nothing deleted, skip." review-checklist.md
# does not ask base-ref itself (Phase 1 resolves the ref), so a reviewer who
# copies the author-mode block without Phase 1 gets a confident clean pass.
# The block's first line now refuses instead; this runs the block both ways.
extract_block_with() {
    # The first fenced block in $1 whose body contains the literal $2.
    awk -v needle="$2" '
        /^[[:space:]]*```/ {
            if (inblock) {
                if (found) { for (i = 1; i <= n; i++) print buf[i]; exit }
                inblock = 0; n = 0; next
            }
            inblock = 1; n = 0; found = 0; next
        }
        inblock {
            buf[++n] = $0
            if (index($0, needle)) found = 1
        }
    ' "$1" | sed 's/^[[:space:]]*//'
}
check_block="$(extract_block_with "$repo_root/pre-merge/review-checklist.md" '--diff-filter=DR')"
[[ -n "$check_block" ]] || fatal "pre-merge/review-checklist.md has no fenced block carrying the deletion trigger"

set +e
unset_out="$(cd "$deltrig" && env -u BASE_REF bash -c "$check_block" 2>&1)"
unset_status=$?
set -e
if [[ "$unset_status" -ne 0 ]]; then
    printf '  ok   with BASE_REF unset the checklist block exits %s instead of printing an empty pass\n' "$unset_status"
    pass=$((pass + 1))
else
    printf '  FAIL with BASE_REF unset the checklist block exited 0 with output %q — a silent clean pass\n' "$unset_out"
    fail=$((fail + 1))
fi
assert_eq '' "$(printf '%s' "$unset_out" | grep -E '^[DR]' || true)" \
    "with BASE_REF unset the checklist block reports no deletions it could not have measured"

set +e
set_out="$(cd "$deltrig" && BASE_REF=origin/prod bash -c "$check_block" 2>&1)"
set_status=$?
set -e
assert_eq 0 "$set_status" "with BASE_REF set the checklist block is a valid invocation"
assert_eq 'D doomed.txt;R renamed.txt;' "$(del_oracle "$set_out")" \
    "with BASE_REF set the checklist block reports the planted deletion and rename"

# -----------------------------------------------------------------------------

section "the reviewer-mode filter keeps removed and renamed rows and nothing else"

# The reviewer-mode command in review-checklist.md asks GitHub for the PR's file
# list and filters it with jq. GitHub's half — the `status` vocabulary — is
# referenced to its docs from the prose (CLAUDE.md § Commands a skill documents,
# rule a). The jq half is ours, so it is pinned here against a fixture in the
# documented response shape: one row per status the filter must keep, plus the
# two it must drop. The filter is read from the checklist, not restated.
gh_block="$(extract_block_with "$repo_root/pre-merge/review-checklist.md" 'pulls/<pr-number>/files')"
[[ -n "$gh_block" ]] || fatal "pre-merge/review-checklist.md has no fenced block carrying the reviewer-mode file-list query"
# Join backslash-continued lines only; the filter's own backslashes (`\(.status)`,
# `\t`) are part of the program and must survive.
jq_filter="$(printf '%s\n' "$gh_block" | awk '{ if (sub(/\\$/, "")) printf "%s", $0; else print }' | sed -n "s/.*--jq '\([^']*\)'.*/\1/p")"
[[ -n "$jq_filter" ]] || fatal "could not extract a single-quoted --jq filter from the reviewer-mode block"
if grep -q -- '--paginate' <<<"$gh_block"; then
    printf '  ok   the reviewer-mode query carries --paginate\n'
    pass=$((pass + 1))
else
    printf '  FAIL the reviewer-mode query no longer carries --paginate\n'
    fail=$((fail + 1))
fi
if command -v jq >/dev/null 2>&1; then
    files_fixture='[
      {"filename": "kept.txt",    "status": "modified"},
      {"filename": "new.txt",     "status": "added"},
      {"filename": "gone.txt",    "status": "removed"},
      {"filename": "new-name.txt","status": "renamed", "previous_filename": "old-name.txt"}
    ]'
    expected="$(printf 'removed\t\tgone.txt\nrenamed\told-name.txt\tnew-name.txt')"
    set +e
    actual="$(printf '%s' "$files_fixture" | jq -r "$jq_filter" 2>&1)"
    jq_status=$?
    set -e
    assert_eq 0 "$jq_status" "the reviewer-mode --jq filter parses and runs"
    assert_eq "$expected" "$actual" \
        "the reviewer-mode --jq filter keeps the removed and renamed rows, in the documented tab-separated shape, and drops the rest"
else
    printf '  FAIL jq is not installed, so the reviewer-mode filter was not checked; install jq\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "no skill uses a base branch NAME where a ref belongs — anywhere"

# This is the census the #298 fix needed and the first draft of this suite did
# not run. `$verb_sites` above enumerates skills that carry *one assignment*,
# which is enumeration by the assignment's wording. The defect is not the wording; it
# is "a base branch used as a range endpoint," and a site can commit it without
# ever adopting the block. Review found exactly that: compound/SKILL.md shipped
# a runnable `git diff main...HEAD --stat`, a hardcoded name that does not even
# reach the stale-local behavior — it exits 128 on every repo whose base is not
# `main`, including this one. It could never enter that population, so nothing
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
# The flag arm carries an optional `=value` because #326's deletion trigger is
# the first documented range line with a valued flag (`--diff-filter=DR`). Before
# that arm existed the line matched nothing, dropped out of the census, and the
# raw-`..HEAD` reconciliation below is the only reason that was visible at all
# rather than a silently unchecked endpoint — which is the exact failure this
# section exists to prevent. The value class carries `%` for the same reason:
# #347's `--format=%H` and `--format=%B` were the first valued flags with one,
# and without it both lines dropped out and the reconciliation caught it again.
# `blame` joined the verbs with #566's fixup-target block, whose range is two-dot
# for the same reason a log's is: the commits on this branch, not the base's.
# Its `-L "$START,$END"` is the first flag with a separate, quoted value, so the
# flag arm also takes one quoted variable after a space.
# The fixup-target block also pins blame's display config with leading
# `-c key=value` pairs before the verb, so the pattern allows those.
range_pattern='git( +-c +[A-Za-z.]+=[a-z]+)* +(diff|log|blame)( +--?[A-Za-z0-9-]+(=[A-Za-z0-9%,._-]+| +"[$][^"]*")?)* +"?[$]?\{?[A-Za-z_][A-Za-z0-9_{}]*\}?\.\.\.?HEAD'
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
# derived: every skill that asks base-ref for the ref must document at least
# one range, and so must the review checklist that restates the command.
for site in $verb_sites pre-merge/review-checklist.md; do
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
    verb="$(printf '%s' "$hit" | sed -E 's/^git( +-c +[A-Za-z.]+=[a-z]+)* +/git /' | awk '{print $2}')"
    # The endpoint char class excludes '.' so the greedy prefix cannot eat the
    # first dot of a three-dot range and leave it in the captured name.
    endpoint="$(printf '%s' "$hit" | sed -E 's/.*[ "]([^ ".]*)\.\.\.?HEAD$/\1/')"
    dots="$(printf '%s' "$hit" | grep -oE '\.\.\.?HEAD$')"

    # #347 adds two endpoints. $REVIEWED_SHA is the stamped 40-hex OID, read by
    # the sed script test-review-currency-marker.sh pins (a name cannot come out
    # of `[0-9a-f]\{40\}`). $SCOPE_FROM is assigned only from $BASE_REF,
    # $REVIEWED_SHA, or HEAD (#566), and the same suite pins that assignment set.
    # All are refs by construction, never names.
    case "$endpoint" in
        "${d}BASE_REF"|"${d}SCOPE_FROM"|"${d}REVIEWED_SHA") ;;
        *) printf '  FAIL %s uses %q as a range endpoint; only %sBASE_REF, %sSCOPE_FROM and %sREVIEWED_SHA are refs — a name is frozen at checkout time\n' \
               "$verb" "$endpoint" "$d" "$d" "$d"
           bad_endpoint=$((bad_endpoint + 1)) ;;
    esac
    # Three-dot diffs from the merge base; two-dot subtracts base-side work and
    # reports it as deletions this branch never made. `git log` is the mirror:
    # two-dot is the commits on this branch, three-dot is the symmetric
    # difference and pulls in the base's own commits.
    case "$verb:$dots" in
        diff:...HEAD|log:..HEAD|blame:..HEAD) ;;
        *) printf '  FAIL %s uses %q; diff must be three-dot and log must be two-dot\n' "$verb" "$dots"
           bad_operator=$((bad_operator + 1)) ;;
    esac
done <<< "$range_hits"

assert_eq 0 "$bad_endpoint" "every documented range endpoint is a ref, not a branch name"
# $SCOPE_FROM may only appear in the skill that assigns it. A second skill
# writing `$SCOPE_FROM...HEAD` would inherit the permission above without the
# assignment the permission rests on.
# shellcheck disable=SC2086
scope_users="$(cd "$repo_root" && { grep -lE 'SCOPE_FROM\.\.\.?HEAD' $scan_files || true; } | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "pre-merge/SKILL.md" "$scope_users" "only /pre-merge, which assigns \$SCOPE_FROM, documents a range against it"
# shellcheck disable=SC2086
stamp_users="$(cd "$repo_root" && { grep -lE 'REVIEWED_SHA\.\.\.?HEAD' $scan_files || true; } | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//')"
assert_eq "pre-merge/SKILL.md" "$stamp_users" "only /pre-merge, which reads \$REVIEWED_SHA with the pinned sed, documents a range against it"
assert_eq 0 "$bad_operator" "every documented range uses the operator its verb requires"

# -----------------------------------------------------------------------------

section "/closeout asks base-ref for the name, never the ref"

# /closeout wants the base branch's NAME: it feeds `git switch`, which rejects a
# remote-tracking ref outright. Its old line emitted `origin/prod` where its own
# comment claimed `prod`, and nothing ran it (#310). It now asks
# `base-ref --name`, and this section runs the block it documents in the
# stale-base clone, so a block that asks for the ref instead prints
# `origin/prod` and fails here.
closeout_block="$(extract_block_with "$repo_root/closeout/SKILL.md" 'base-ref')"
[[ -n "$closeout_block" ]] || fatal "closeout/SKILL.md has no fenced block that asks base-ref"
assert_contains "$closeout_block" 'base-ref --name' "/closeout's base block asks for --name"
# Every base-ref call in the block carries --name. A second call in the ref form
# would print a line the operator could hand to `git switch`.
ref_calls="$(printf '%s\n' "$closeout_block" | grep -E 'base-ref' | grep -vc -- 'base-ref --name' || true)"
assert_eq 0 "$ref_calls" "/closeout's base block never asks base-ref for the ref form"
[[ "$closeout_block" == *"$placeholder"* ]] || fatal "closeout/SKILL.md's base block no longer carries the $placeholder placeholder"
set +e
closeout_out="$(cd "$work" && SKILL_KIT_SIDECAR_ROOT="$no_sidecars" bash -c "${closeout_block//"$placeholder"/$sidecar}" 2>/dev/null)"
closeout_status=$?
set -e
assert_eq 0 "$closeout_status" "/closeout's base block runs in the clone"
assert_eq 'prod' "$closeout_out" "/closeout's base block prints the bare name git switch takes"

# The note is what stops the next sweep from "fixing" /closeout to match the
# range-endpoint skills. Two assertions, not one conditional: a check that fired
# only if closeout mentioned BASE_REF would vanish with the note (lesson 5).
closeout_note="deliberately \*not\* the ref form"
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

section "/closeout's Step 8 remote-branch check, run in both polarities"

# #344's second finding: `gh pr merge --delete-branch` aborted at its LOCAL step
# in a multi-worktree checkout ('main' is already used by worktree) *after* the
# remote merge succeeded, and the remote branch stayed alive. Every check
# /closeout had passed in that state — Step 3 confirms the PR reports MERGED,
# Step 6 prunes local and remote-TRACKING refs, and Step 8's "Branch pruned"
# reads `git branch`, which is local. Nothing asked the remote.
#
# So Step 8 grew a line that does, and it is run here rather than believed,
# because its whole contract is an exit status: `--exit-code` is what makes
# "found" and "not found" distinguishable at all, and a line that lost the flag
# would exit 0 in BOTH states and read as permanently clean. Both polarities are
# exercised for exactly that reason — a one-sided test passes on a broken flag.
#
# The line is extracted from the skill, never restated here (header rule).
ls_remote_line="$(grep -m1 '^git ls-remote ' "$repo_root/closeout/SKILL.md" || true)"
[[ -n "$ls_remote_line" ]] || fatal "no 'git ls-remote' line found in closeout/SKILL.md"
[[ "$ls_remote_line" == *'<feature-branch>'* ]] \
    || fatal "placeholder <feature-branch> is gone from /closeout's 'git ls-remote' line"
printf 'ls-remote (closeout/SKILL.md): %s\n' "$ls_remote_line"

remote_sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox" "$base_sandbox" "$remote_sandbox"' EXIT

git init -q --bare "$remote_sandbox/origin.git"
git init -q "$remote_sandbox/work"
(
    cd "$remote_sandbox/work"
    git remote add origin "$remote_sandbox/origin.git"
    printf 'x\n' > f.txt
    git add f.txt
    git -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
        commit -q --no-verify -m "seed"
    git branch -m closeout-fixture-base
    git push -q origin closeout-fixture-base
    git switch -qc issue-9-widget
    git push -q origin issue-9-widget
)
# Check the fixture's OUTCOME, not the subshell's status: `set -e` is suppressed
# in the left operand of `||`, so a `) || fatal` here could not report a failure
# that happened inside (scripts/test-guards-can-fire.sh detector A). What the
# polarity runs below actually depend on is the branch being on the remote.
git -C "$remote_sandbox/origin.git" show-ref --verify --quiet refs/heads/issue-9-widget \
    || fatal "the ls-remote fixture never got issue-9-widget onto the fixture remote; the polarity runs would measure nothing"

# Polarity 1 — the branch is still on the remote. This is the state the field
# incident left behind, and the check must NOT read as clean here.
alive_status=0
( cd "$remote_sandbox/work" && eval "${ls_remote_line//<feature-branch>/issue-9-widget}" >/dev/null 2>&1 ) || alive_status=$?
if [[ "$alive_status" -eq 0 ]]; then
    printf '  ok   the check exits 0 while the branch is still on the remote (a surviving branch is visible)\n'
    pass=$((pass + 1))
else
    printf '  FAIL the check exits %d on a branch that IS on the remote; it cannot see the failure it exists for\n' "$alive_status"
    fail=$((fail + 1))
fi

# Polarity 2 — the branch is gone from the remote, which is what a successful
# --delete-branch leaves. `--exit-code`'s own documented contract (git-ls-remote(1))
# names exactly one status for this — 2, "no matching refs" — and it is the half
# that dies silently if --exit-code is ever dropped. The assertion checks for 2
# specifically, not merely non-zero: #345's finding is that "non-zero" is not one
# outcome (see polarity 3), so the pass condition here has to be as narrow as the
# contract it is standing in for.
git -C "$remote_sandbox/work" push -q origin --delete issue-9-widget \
    || fatal "could not delete the fixture branch from the fixture remote"
gone_status=0
( cd "$remote_sandbox/work" && eval "${ls_remote_line//<feature-branch>/issue-9-widget}" >/dev/null 2>&1 ) || gone_status=$?
if [[ "$gone_status" -eq 2 ]]; then
    printf '  ok   the check exits 2 (git-ls-remote'"'"'s documented "no matching refs" status) once the branch is gone from the remote\n'
    pass=$((pass + 1))
else
    printf '  FAIL the check exits %d, not 2, on a branch that is NOT on the remote; confirmed-gone is not distinguishable from other outcomes\n' "$gone_status"
    fail=$((fail + 1))
fi

# Polarity 3 — the check itself cannot run, because the remote cannot be reached.
# #345's finding: `--exit-code` only documents status 2; every other status it can
# exit with is still non-zero and, under a bare "expect non-zero" reading, reads as
# the confirmed-gone case in polarity 2 above — an expired credential, a renamed
# `origin`, or a transient network blip would silently pass the same check a real
# deletion passes. This polarity proves the command's own exit status is actually
# distinguishable in the two cases, which is what the prose fix in closeout/SKILL.md
# now depends on. Pointed at a missing local path rather than a live unreachable
# host: same "could not access the remote" failure git-ls-remote takes, with no
# network dependency in the suite (validate-the-instrument-not-only-the-subject:
# prefer an instrument with fewer preconditions). git-ls-remote(1) documents status
# 2 for --exit-code but no fixed status for this path, so the assertion below only
# pins "not 0, not 2" — distinguishable from confirmed-gone — not a specific number.
unreachable_status=0
git -C "$remote_sandbox/work" remote set-url origin "$remote_sandbox/does-not-exist.git" \
    || fatal "could not repoint the fixture's origin at a missing path"
( cd "$remote_sandbox/work" && eval "${ls_remote_line//<feature-branch>/issue-9-widget}" >/dev/null 2>&1 ) || unreachable_status=$?
if [[ "$unreachable_status" -ne 0 && "$unreachable_status" -ne 2 ]]; then
    printf '  ok   the check exits %d (non-zero, not 2) when the remote cannot be reached — distinguishable from confirmed-gone\n' "$unreachable_status"
    pass=$((pass + 1))
else
    printf '  FAIL the check exits %d when the remote cannot be reached; that is indistinguishable from confirmed-gone (2) or from success (0)\n' "$unreachable_status"
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "/excavate: every git block in § Process, run against a planted 2020 fixture"

# /excavate tells a downstream agent to run twenty fenced blocks
# unsupervised in a repository it has never seen; most are awk/sort pipelines
# over `git log` output, which is exactly the shape of command that goes quietly
# wrong (an unanchored grep, a missing pathspec, a guard that is only there
# because `git show ":path"` reads the index). So the blocks are RUN, extracted
# verbatim from the skill, against a fixture that plants one answer per block.
#
# Three decisions are worth stating because the obvious alternative is wrong:
#   - The census is derived by an awk state machine over the fences AND by a
#     plain grep of the opening fences; they must agree (header lesson 7b — two
#     different patterns that can disagree).
#   - A block that is neither `gh` nor runnable FAILS rather than skipping. The
#     `gh` blocks are the only skip set; each is named in the output, and
#     "run + skipped == census" is checked per block, not as a sum.
#   - The fixture is dated 2020 and SINCE is overridden to an absolute date
#     AFTER the setup block runs, so the block's own `SINCE='12 months ago'`
#     still executes and START is recomputed from the override. A relative
#     window would make every in-window assertion a function of today's date.
# Blocks are identified by a distinctive substring that must match exactly one
# block, never by position, so a reordered skill fails loudly instead of
# running the wrong block against the wrong assertion.

excavate_skill="$repo_root/excavate/SKILL.md"
[[ -f "$excavate_skill" ]] || fatal "no excavate/SKILL.md at $excavate_skill"

excavate_sandbox="$(mktemp -d)"
excavate_out="$(mktemp -d)"
trap 'rm -rf "$sandbox" "$base_sandbox" "$remote_sandbox" "$excavate_sandbox" "$excavate_sandbox.shallow" "$excavate_out"' EXIT

# --- Extraction: the Nth fenced bash block, verbatim -------------------------

excavate_extract() {
    awk -v want="$1" '
        /^```/ {
            if (state == "") { if ($0 ~ /^```bash[ \t]*$/) { n++; state = "bash" } else state = "other" }
            else if ($0 ~ /^```[ \t]*$/) state = ""
            next
        }
        state == "bash" && n == want { print }
    ' "$excavate_skill"
}

excavate_total="$(awk '
    /^```/ {
        if (state == "") { if ($0 ~ /^```bash[ \t]*$/) c++; state = "x" }
        else if ($0 ~ /^```[ \t]*$/) state = ""
    }
    END { print c + 0 }' "$excavate_skill")"
excavate_grep_total="$(grep -c '^```bash' "$excavate_skill" || true)"

assert_eq "$excavate_grep_total" "$excavate_total" "the fence state machine and a plain grep agree on the number of bash blocks ($excavate_total)"
if [[ "$excavate_total" -ge 12 ]]; then
    printf '  ok   census floor: %d bash blocks (>= 12)\n' "$excavate_total"
    pass=$((pass + 1))
else
    printf '  FAIL census floor: only %d bash blocks found (< 12); the extractor or the skill lost most of its commands\n' "$excavate_total"
    fail=$((fail + 1))
fi

excavate_blocks=()
excavate_class=()
excavate_setup_n=0
excavate_gh_n=0
excavate_git_n=0
excavate_gh_list=""
excavate_empty_n=0
i=1
while [[ "$i" -le "$excavate_total" ]]; do
    excavate_blocks[i]="$(excavate_extract "$i")"
    [[ -n "${excavate_blocks[i]}" ]] || excavate_empty_n=$((excavate_empty_n + 1))
    first_tok="$(awk 'NF { print $1; exit }' <<<"${excavate_blocks[i]}")"
    if [[ "$i" -eq 1 ]]; then
        excavate_class[i]=setup
        excavate_setup_n=$((excavate_setup_n + 1))
    elif [[ "$first_tok" == gh ]]; then
        excavate_class[i]=gh
        excavate_gh_n=$((excavate_gh_n + 1))
        excavate_gh_list="$excavate_gh_list $i"
    else
        excavate_class[i]=git
        excavate_git_n=$((excavate_git_n + 1))
    fi
    i=$((i + 1))
done
assert_eq 0 "$excavate_empty_n" "no extracted block is empty"

# Independent check on the "block 1 is the shared setup" premise: a DIFFERENT
# pattern (the array definition every later block depends on) must pick out
# exactly block 1 and nothing else.
setup_holders=""
i=1
while [[ "$i" -le "$excavate_total" ]]; do
    [[ "${excavate_blocks[i]}" == *'NONDOMAIN=('* ]] && setup_holders="$setup_holders $i"
    i=$((i + 1))
done
assert_eq " 1" "$setup_holders" "the block that defines NONDOMAIN is block 1, and only block 1 (it is the shared setup)"
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
for needle in 'SINCE=' 'WORK="${TMPDIR:-/tmp}/excavate-' 'mkdir -p -m 700 "$WORK"' 'START=$(' 'BOTS=' 'MAXFILES='; do
    [[ "${excavate_blocks[1]}" == *"$needle"* ]] || fatal "the shared setup block no longer contains '$needle'; every later block assumes it"
done

if [[ "$excavate_gh_n" -ge 1 ]]; then
    printf '  ok   the gh class is non-empty (%d blocks)\n' "$excavate_gh_n"
    pass=$((pass + 1))
else
    printf '  FAIL the gh class is empty; either /excavate lost its gh blocks or the classifier no longer sees them\n'
    fail=$((fail + 1))
fi
for g in $excavate_gh_list; do
    printf '  skip gh block %d (network call, not run): %s\n' "$g" "$(awk 'NF { print; exit }' <<<"${excavate_blocks[g]}")"
done
assert_eq "$excavate_total" "$((excavate_setup_n + excavate_gh_n + excavate_git_n))" "setup + gh + git partition the census, every block in exactly one class"

# --- Locating blocks by content ----------------------------------------------

excavate_find() {   # $1 = fixed substring that must occur in exactly one block; $2 = variable to set
    # Sets a variable in the caller's shell rather than printing, so the fatal
    # below runs in the main shell: inside `$( … )` an exit kills only the
    # subshell and the suite carries on (test-guards-can-fire.sh, detector C).
    local found="" cnt=0 j=1
    while [[ "$j" -le "$excavate_total" ]]; do
        if [[ "${excavate_blocks[j]}" == *"$1"* ]]; then
            found="$j"
            cnt=$((cnt + 1))
        fi
        j=$((j + 1))
    done
    [[ "$cnt" -eq 1 ]] || fatal "expected exactly one /excavate block containing '$1', found $cnt"
    printf -v "$2" '%s' "$found"
}

# Declared here so ShellCheck can see the assignments excavate_find makes via printf -v.
b_cover=; b_log=; b_rev1=; b_rev2=; b_rename=; b_manifest=; b_freq=; b_loc=; b_hot=; b_conv=
b_fix=; b_pairs=; b_soc=; b_trend=; b_contrib=; b_persist=; b_baseline=; b_base=; b_names=; b_vars=
b_dups=; b_rerank=
excavate_find 'is-shallow-repository' b_cover
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/dups.txt"' b_dups
excavate_find 'top five without duplicates' b_rerank
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/log.txt"' b_log
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/vars.sh"' b_vars
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/names.txt"' b_names
excavate_find "--grep='^Revert \"'" b_rev1
excavate_find '^This reverts commit' b_rev2
excavate_find '--diff-filter=RD' b_rename
excavate_find 'manifest-diffs.txt' b_manifest
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/freq.txt"' b_freq
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/loc.txt"' b_loc
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/hotspots.txt"' b_hot
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find 'rev-list --count --since="$SINCE" --no-merges -i -E' b_conv
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/fix.txt"' b_fix
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/pairs.txt"' b_pairs
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/soc.txt"' b_soc
excavate_find 'FILE=<path>' b_trend
excavate_find 'git shortlog' b_contrib
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
excavate_find '> "$WORK/persist.txt"' b_persist
excavate_find 'knee share' b_baseline

for b in "$b_cover" "$b_dups" "$b_rerank" "$b_vars" "$b_log" "$b_names" "$b_rev1" "$b_rev2" "$b_rename" "$b_manifest" "$b_freq" "$b_loc" "$b_hot" "$b_conv" "$b_fix" "$b_pairs" "$b_soc" "$b_trend" "$b_contrib" "$b_persist" "$b_baseline"; do
    [[ "${excavate_class[b]}" == git ]] || fatal "block $b was located by content but is classed '${excavate_class[b]}', not git"
done

# --- The fixture -------------------------------------------------------------
#
# Position p (1..20) is the in-window commit's place in history; the quartile
# points the trend block samples are therefore positions 5, 10, 15, 19. Hot
# changes sit on both sides of each point so its LOC and indentation move
# strictly between samples.
#
#   p1 add flag              A  flag.txt                   (the revert's target)
#   p2 FIX: null guard       A  hot, coupled, lock         fix-labeled
#   p4 tidy [body: reverting the flag by hand]
#                            A  hot, lock                  fix-labeled via BODY
#   p7, p17                  A  hot, coupled, lock
#   p9                       B  hot, lock
#   p12 Revert "add flag"    B  hot, coupled, lock         fix-labeled
#   p14 bump deps            dependabot[bot]  hot, package.json
#   p3,5,6,8,10,11,13        churny.txt only (2 lines, under the LOC floor)
#   p15 big.txt (200 lines)  p16 bulk/f01..f40.txt (> MAXFILES)
#   p18 git mv old_dir/x.txt new_dir/x.txt    p19 A adds a dependency
#   p20 "configure dependabot alerts"  B  ci-notes.txt, café.txt   a HUMAN whose SUBJECT
#                            names a bot; the bot filter must read the author field only.
#                            café.txt (60 lines at the root, 61 after p20) has a non-ASCII
#                            name: under the default core.quotePath git prints it as
#                            "caf\303\251.txt", wc cannot open that, and the file vanishes
#                            from loc.txt and so from hotspots.txt
excavate_dates=(2020-07-01 2020-07-10 2020-07-20 2020-08-01 2020-08-10 2020-08-20 2020-09-01 2020-09-10 2020-09-20 2020-10-01 2020-10-08 2020-10-15 2020-10-22 2020-11-01 2020-11-08 2020-11-15 2020-11-22 2020-11-28 2020-12-01 2020-12-05)
excavate_in_window="${#excavate_dates[@]}"
excavate_planted_fix_commits=3   # FIX: null guard, Revert "add flag", tidy (via its body)
excavate_planted_hot_revs=6      # human commits touching hot.txt (the bot's seventh is filtered)
excavate_planted_pair=4          # human commits touching hot.txt AND coupled.txt
excavate_planted_churny=7
author_a='Alice Author'
author_b='Bob Builder'
bot_name='dependabot[bot]'

(
    cd "$excavate_sandbox"
    git init -q -b main .
    git config commit.gpgsign false

    xc_commit() {   # date author subject [body]
        local d="$1T12:00:00+0000" who="$2"
        export GIT_AUTHOR_NAME="$who" GIT_COMMITTER_NAME="$who"
        export GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_EMAIL=noreply@example.invalid
        export GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d"
        if [[ -n "${4:-}" ]]; then
            git commit -q -m "$3" -m "$4"
        else
            git commit -q -m "$3"
        fi
    }
    xc_hot_grow() { local k; for k in 1 2 3 4 5 6 7 8 9 10; do printf '    hot %s-%s\n' "$1" "$k" >> hot.txt; done; git add hot.txt; }
    xc_coupled_shrink() {
        local n; n="$(wc -l < coupled.txt | tr -d ' ')"
        head -n "$((n - 10))" coupled.txt > coupled.tmp && mv coupled.tmp coupled.txt
        git add coupled.txt
    }
    xc_lock() { printf 'lock %s\n' "$1" >> package-lock.json; git add package-lock.json; }
    xc_day() { printf '%s' "${excavate_dates[$(($1 - 1))]}"; }

    # Pre-window root commit.
    mkdir old_dir
    for k in $(seq 1 40); do printf 'hot line %d\n' "$k"; done > hot.txt
    for k in $(seq 1 60); do printf '    coupled line %d\n' "$k"; done > coupled.txt
    printf 'a\nb\n' > churny.txt
    for k in $(seq 1 200); do printf 'big line %d\n' "$k"; done > big.txt
    printf '{"dependencies":{}}\n' > package.json
    printf 'lock 0\n' > package-lock.json
    printf 'x one\nx two\nx three\n' > old_dir/x.txt
    for k in $(seq 1 60); do printf 'cafe line %d\n' "$k"; done > café.txt
    git add -A
    xc_commit 2020-01-15 "$author_a" "seed fixture"

    # Created strictly in position order: history is linear, so position p IS
    # rev-list's p-th commit, and the quartile points are what the comments say.
    for p in $(seq 1 "$excavate_in_window"); do
        d="$(xc_day "$p")"
        case "$p" in
            1)  printf 'on\n' > flag.txt; git add flag.txt
                xc_commit "$d" "$author_a" "add flag"
                flag_sha="$(git rev-parse HEAD)" ;;
            2)  xc_hot_grow "$p"; xc_coupled_shrink; xc_lock "$p"
                xc_commit "$d" "$author_a" "FIX: null guard" ;;
            3|5|6|8|10|11|13)
                printf 'a\n%s\n' "$p" > churny.txt; git add churny.txt
                xc_commit "$d" "$author_a" "tweak knob $p" ;;
            4)  xc_hot_grow "$p"; xc_lock "$p"
                xc_commit "$d" "$author_a" "tidy" "reverting the flag by hand" ;;
            7)  xc_hot_grow "$p"; xc_coupled_shrink; xc_lock "$p"
                xc_commit "$d" "$author_a" "add widget" ;;
            9)  xc_hot_grow "$p"; xc_lock "$p"
                xc_commit "$d" "$author_b" "add gizmo" ;;
            12) xc_hot_grow "$p"; xc_coupled_shrink; xc_lock "$p"
                xc_commit "$d" "$author_b" 'Revert "add flag"' "This reverts commit $flag_sha." ;;
            14) xc_hot_grow "$p"; printf '{"dependencies":{"bot-dep":"2.0.0"}}\n' > package.json; git add package.json
                xc_commit "$d" "$bot_name" "bump deps" ;;
            15) awk 'NR == 100 { print "big line changed"; next } 1' big.txt > big.tmp && mv big.tmp big.txt; git add big.txt
                xc_commit "$d" "$author_a" "update big table" ;;
            16) mkdir bulk
                for k in $(seq -w 1 40); do printf 'bulk %s\n' "$k" > "bulk/f$k.txt"; done
                git add bulk
                xc_commit "$d" "$author_a" "import bulk files" ;;
            17) xc_hot_grow "$p"; xc_coupled_shrink; xc_lock "$p"
                xc_commit "$d" "$author_a" "add gadget" ;;
            18) mkdir new_dir; git mv old_dir/x.txt new_dir/x.txt
                xc_commit "$d" "$author_a" "move x" ;;
            19) printf '{"dependencies":{"bot-dep":"2.0.0","left-pad":"1.0.0"}}\n' > package.json; git add package.json
                xc_commit "$d" "$author_a" "add left-pad dependency" ;;
            20) printf 'alerts on\n' > ci-notes.txt; printf 'cafe line 61\n' >> café.txt; git add ci-notes.txt café.txt
                xc_commit "$d" "$author_b" "configure dependabot alerts" ;;
            *)  echo "fixture has no step for position $p" >&2; exit 1 ;;
        esac
    done
)
# Outcome checks, not the subshell's status (see the /closeout fixture above).
[[ "$(git -C "$excavate_sandbox" rev-list --count HEAD)" -eq "$((excavate_in_window + 1))" ]] \
    || fatal "the /excavate fixture did not produce $((excavate_in_window + 1)) commits (20 planned positions + 1 pre-window root)"
[[ "$(git -C "$excavate_sandbox" rev-list --count --since=2020-06-01 HEAD)" -eq "$excavate_in_window" ]] \
    || fatal "the /excavate fixture's in-window commits are not all dated after 2020-06-01"
git clone -q --depth 1 "file://$excavate_sandbox" "$excavate_sandbox.shallow" \
    || fatal "could not make the shallow clone of the /excavate fixture"

# The bulk commit must exceed the ceiling the skill documents, read from the
# skill rather than restated: if MAXFILES is ever raised past 40 the plant no
# longer expresses the fault and every bulk assertion below becomes vacuous.
excavate_maxfiles="$(sed -n 's/^MAXFILES=\([0-9][0-9]*\).*/\1/p' <<<"${excavate_blocks[1]}")"
[[ -n "$excavate_maxfiles" && "$excavate_maxfiles" -lt 40 ]] \
    || fatal "MAXFILES is '${excavate_maxfiles:-unreadable}' in the shared setup; the fixture's 40-file bulk commit must exceed it"

hot_loc="$(wc -l < "$excavate_sandbox/hot.txt" | tr -d ' ')"

# --- Running blocks ----------------------------------------------------------

# `timeout` is coreutils on Linux and `gtimeout` under Homebrew on macOS; with
# neither, a background killer. Returns 124 on timeout in every branch.
run_timed() {   # secs cmd...
    local secs="$1" st=0 pid killer
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@" || st=$?
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@" || st=$?
    else
        "$@" &
        pid=$!
        ( sleep "$secs"; kill "$pid" 2>/dev/null ) &
        killer=$!
        wait "$pid" || st=$?
        kill "$killer" 2>/dev/null || true
        wait "$killer" 2>/dev/null || true
        [[ "$st" -eq 143 ]] && st=124
    fi
    return "$st"
}

excavate_start_line="$(grep -m1 '^START=' <<<"${excavate_blocks[1]}" || true)"
[[ -n "$excavate_start_line" ]] || fatal "no '^START=' line in the shared setup block; the SINCE override cannot recompute it"

# Run the shared setup, override SINCE to the fixture's absolute window, recompute
# START, then the listed blocks in the order given. Each block's stdout/stderr go
# to $out/b<N>.out/.err and its exit status to $out/rc. stdin is a pipe that stays
# open for 30 s and never carries data: a block that reads stdin (a bare `git
# shortlog`) blocks instead of seeing EOF, which is the hang the skill warns about.
# A harness that handed it /dev/null would make that guard unfireable.
xc_run() {   # outdir secs pathval idx...
    local out="$1" secs="$2" pathval="$3" idx text st=0
    shift 3
    mkdir -p "$out/tmp"
    {
        printf 'XO_OUT=%q\n' "$out"
        # WORK is a deterministic path under TMPDIR, so passes that share the
        # sandbox would share a directory; a private TMPDIR per pass keeps one
        # pass's files (and a mutant's missing ones) from standing in for another's.
        printf 'export TMPDIR=%q\n' "$out/tmp"
        printf 'cd %q || exit 97\n' "$excavate_sandbox"
        printf '%s\n' "${excavate_blocks[1]}"
        # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
        printf 'printf "1 %%s\\n" "$?" >> "$XO_OUT/rc"\n'
        printf 'SINCE=2020-06-01\n'
        printf '%s\n' "$excavate_start_line"
        # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
        printf 'printf "%%s\\n" "$START" > "$XO_OUT/start"\n'
        for idx in "$@"; do
            text="${excavate_blocks[idx]//<path>/$pathval}"
            # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
            printf '{\n%s\n} > "$XO_OUT/b%s.out" 2> "$XO_OUT/b%s.err"\n' "$text" "$idx" "$idx"
            # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
            printf 'printf "%s %%s\\n" "$?" >> "$XO_OUT/rc"\n' "$idx"
        done
        # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
        printf 'mkdir -p "$XO_OUT/work" && cp -R "$WORK/." "$XO_OUT/work/"\n'
    } > "$out/run.sh"
    run_timed "$secs" bash "$out/run.sh" > "$out/stdout" 2> "$out/stderr" < <(exec sleep 30 2>/dev/null) || st=$?
    return "$st"
}

# Every non-gh, non-setup block that does NOT take a <path> runs once, in file
# order, in one process (they share $WORK). Blocks that take <path> are run
# separately below, once per path under test.
main_idx=""
path_idx=""
i=2
while [[ "$i" -le "$excavate_total" ]]; do
    if [[ "${excavate_class[i]}" == git ]]; then
        if [[ "${excavate_blocks[i]}" == *'<path>'* ]]; then
            path_idx="$path_idx $i"
        else
            main_idx="$main_idx $i"
        fi
    fi
    i=$((i + 1))
done

# shellcheck disable=SC2086  # the index lists are space-separated by construction
{
    run_main=0; xc_run "$excavate_out/main" 120 UNUSED $main_idx || run_main=$?
    run_trend_hot=0; xc_run "$excavate_out/trend-hot" 120 hot.txt "$b_trend" || run_trend_hot=$?
    run_trend_coupled=0; xc_run "$excavate_out/trend-coupled" 120 coupled.txt "$b_trend" || run_trend_coupled=$?
    run_contrib=0; xc_run "$excavate_out/contrib" 20 hot.txt "$b_contrib" || run_contrib=$?
}

assert_eq 0 "$run_main" "the main pass (every non-gh block without a <path>) completes"
assert_eq 0 "$run_trend_hot" "the trend block completes on hot.txt"
assert_eq 0 "$run_trend_coupled" "the trend block completes on coupled.txt"
if [[ "$run_contrib" -eq 124 ]]; then
    printf '  FAIL shortlog read stdin: the contributors block did not finish in 20 s\n'
    fail=$((fail + 1))
else
    assert_eq 0 "$run_contrib" "the contributors block completes without reading stdin"
fi

# --- Accounting: run + skipped == census, per block --------------------------

ran_list=" "
for d in main trend-hot trend-coupled contrib; do
    if [[ -f "$excavate_out/$d/rc" ]]; then
        while read -r idx rc; do
            ran_list="$ran_list$idx "
            if [[ "$rc" -ne 0 ]]; then
                printf '  FAIL block %s exited %s in the %s pass\n       stderr: %s\n' "$idx" "$rc" "$d" "$(cat "$excavate_out/$d/b$idx.err" 2>/dev/null || true)"
                fail=$((fail + 1))
            fi
        done < "$excavate_out/$d/rc"
    fi
done
ran_n=0
skipped_n=0
unaccounted=""
i=1
while [[ "$i" -le "$excavate_total" ]]; do
    is_ran=no; is_skipped=no
    [[ "$ran_list" == *" $i "* ]] && is_ran=yes
    [[ " $excavate_gh_list " == *" $i "* ]] && is_skipped=yes
    if [[ "$is_ran" == yes && "$is_skipped" == no ]]; then
        ran_n=$((ran_n + 1))
    elif [[ "$is_skipped" == yes && "$is_ran" == no ]]; then
        skipped_n=$((skipped_n + 1))
    else
        unaccounted="$unaccounted $i"
    fi
    i=$((i + 1))
done
assert_eq "" "$unaccounted" "every block was run or explicitly skipped as gh, never both and never neither"
assert_eq "$excavate_total" "$((ran_n + skipped_n))" "blocks run ($ran_n) + blocks skipped ($skipped_n) == census ($excavate_total)"

# --- Placeholders: no <...> may survive into a block that ran ----------------

leftover=""
for i in $main_idx; do
    if grep -qE '<[a-z][a-z-]*>' <<<"${excavate_blocks[i]}"; then leftover="$leftover $i"; fi
done
assert_eq "" "$leftover" "no unsubstituted <placeholder> sits in a block the main pass ran"

assert_eq "2020-07-01" "$(cat "$excavate_out/main/start")" "START was recomputed from the overridden SINCE (first in-window commit date)"

# --- Answers -----------------------------------------------------------------

xo() { cat "$excavate_out/main/$1"; }   # file written under $WORK
xb() { cat "$excavate_out/main/b$1.out"; }
count_lines() { if [[ -z "$1" ]]; then printf 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }
# uniq -c style "   N path" file -> N for a path, empty when absent
count_for() { awk -v p="$2" '{ c = $1; sub(/^ *[0-9]+ /, ""); if ($0 == p) print c }' "$1"; }
tab=$'\t'

# Coverage block
cover="$(xb "$b_cover")"
assert_eq 4 "$(count_lines "$cover")" "coverage block prints exactly its four documented lines"
assert_eq false "$(sed -n 1p <<<"$cover")" "coverage: is-shallow-repository prints false in the full fixture"
assert_eq "$excavate_in_window" "$(sed -n 2p <<<"$cover")" "coverage: in-window non-merge count == commits planted in the window (bot included)"
assert_eq 2020-01-15 "$(sed -n 3p <<<"$cover")" "coverage: root-commit date is the pre-window commit's"
assert_matches "$(sed -n 4p <<<"$cover")" '^0 of [0-9]+ subjects end in \(#N\)$' "coverage: squash ratio line, zero planted (#N) subjects"
assert_eq "0 of $excavate_in_window subjects end in (#N)" "$(sed -n 4p <<<"$cover")" "coverage: squash ratio counts every in-window subject"

# Shallow polarity: the line extracted from the block, run in both repos.
shallow_line="$(grep 'is-shallow-repository' <<<"${excavate_blocks[b_cover]}")"
assert_eq 1 "$(count_lines "$shallow_line")" "the shallow check is exactly one line of the coverage block"
assert_eq true "$(cd "$excavate_sandbox.shallow" && eval "$shallow_line")" "shallow check prints true in a --depth 1 clone"
assert_eq false "$(cd "$excavate_sandbox" && eval "$shallow_line")" "shallow check prints false in the full fixture"

# names.txt: the scrub list Step 7 greps docs/solutions/ against. It must exist,
# be non-empty, hold exactly the two planted humans, and carry no bot and no blank
# line (one blank line in an `rg -F -f` pattern file matches everything).
names_file="$excavate_out/main/work/names.txt"
assert_eq 1 "$([[ -s "$names_file" ]] && echo 1 || echo 0)" "names: the scrub list is written and non-empty"
assert_eq "$author_a
$author_b" "$(cat "$names_file")" "names: the scrub list is exactly the two planted human authors, one per line"
assert_eq 0 "$(grep -c -e '^$' -e 'dependabot' "$names_file" || true)" "names: no blank line and no bot in the scrub list"

# The bot filter reads the author field, not the whole header: a human commit
# whose SUBJECT names a bot (p20) keeps its header in the shared log.
log_file="$excavate_out/main/work/log.txt"
assert_eq 1 "$(awk -F'\t' -v a="$author_b" '/^@@/ && $2 == a && $4 == "configure dependabot alerts"' "$log_file" | wc -l | tr -d ' ')" "log: the human commit whose subject says dependabot keeps its header in the shared log"
assert_eq 0 "$(awk -F'\t' '/^@@/ && $2 ~ /bot/' "$log_file" | wc -l | tr -d ' ')" "log: no header carries the bot as its author"

# freq.txt
freq_file="$excavate_out/main/work/freq.txt"
assert_eq "$excavate_planted_hot_revs" "$(count_for "$freq_file" hot.txt)" "freq: hot.txt has exactly its $excavate_planted_hot_revs human in-window revisions (bot filtered, pre-window excluded)"
assert_eq "$excavate_planted_churny" "$(count_for "$freq_file" churny.txt)" "freq: churny.txt has its $excavate_planted_churny revisions"
assert_eq 1 "$(count_for "$freq_file" ci-notes.txt)" "freq: ci-notes.txt counts once (the human commit whose subject names a bot)"
assert_eq "" "$(count_for "$freq_file" package-lock.json)" "freq: package-lock.json is absent (NONDOMAIN)"
assert_eq 0 "$(grep -Fc 'bulk/' "$freq_file" || true)" "freq: no bulk/ file (the 40-file commit exceeds MAXFILES)"

# hotspots.txt
hotspots="$(cat "$excavate_out/main/work/hotspots.txt")"
assert_eq "$excavate_planted_hot_revs${tab}${hot_loc}${tab}hot.txt" "$(sed -n 1p <<<"$hotspots")" "hotspots: line 1 is hot.txt with 6 revisions and LOC == its final line count ($hot_loc)"
assert_eq 0 "$(grep -Fc 'churny.txt' <<<"$hotspots" || true)" "hotspots: churny.txt (2 lines, 7 revisions) is below the LOC floor and absent"
assert_eq "1${tab}200${tab}big.txt" "$(sed -n 2p <<<"$hotspots")" "hotspots: big.txt (1 revision, 200 lines) ranks below hot.txt"
assert_eq "1${tab}61${tab}café.txt" "$(sed -n 3p <<<"$hotspots")" "hotspots: café.txt (non-ASCII name, 1 revision, 61 lines) survives unquoted with its LOC"
assert_eq 61 "$(awk -F'\t' '$2 == "café.txt" { print $1 }' "$excavate_out/main/work/loc.txt")" "loc: café.txt is listed by its real name with its real line count"

# fix.txt and the convention rate
fix_file="$excavate_out/main/work/fix.txt"
assert_eq "$excavate_planted_fix_commits" "$(count_for "$fix_file" hot.txt)" "fix: hot.txt has the FIX, the Revert and tidy (matched through its BODY, since the grep is -i and unanchored)"
assert_eq "$excavate_planted_fix_commits" "$(xb "$b_conv")" "fix: the convention-rate line prints the planted fix-labeled commit count, an integer"
assert_matches "$(xb "$b_conv")" '^[0-9]+$' "fix: the convention-rate line is a bare integer"

# reverts: one fenced block holding two commands (by subject, then by body
# trailer). b_rev1 and b_rev2 are the same block, so its output is two lines, one
# per command, told apart by the field count their --pretty formats give.
assert_eq "$b_rev1" "$b_rev2" "both revert commands live in one fenced block"
rev_out="$(xb "$b_rev1")"
rev1="$(sed -n 1p <<<"$rev_out")"
rev2="$(sed -n 2p <<<"$rev_out")"
assert_eq 2 "$(count_lines "$rev_out")" "revert block prints exactly two lines: one match per command, one planted revert"
assert_eq 3 "$(awk -F'\t' '{ print NF }' <<<"$rev1")" "revert command 1 (by subject) printed one hash/date/subject row"
assert_eq 2 "$(awk -F'\t' '{ print NF }' <<<"$rev2")" "revert command 2 (by body trailer) printed one hash/subject row"
assert_contains "$rev1" 'Revert "add flag"' "revert command 1 names the planted revert"
assert_contains "$rev2" 'Revert "add flag"' "revert command 2 names the planted revert"
if [[ "$rev_out" == *tidy* ]]; then
    printf '  FAIL the revert block matched the tidy commit, whose BODY begins "reverting"; the pattern lost its anchor\n'
    fail=$((fail + 1))
else
    printf '  ok   the revert block does not match tidy (case-sensitive, anchored)\n'
    pass=$((pass + 1))
fi
assert_eq "$(cut -f1 <<<"$rev1")" "$(cut -f1 <<<"$rev2")" "revert commands 1 and 2 report the same commit"

# rename
rename_out="$(xb "$b_rename")"
if grep -Eq "^R[0-9]+${tab}old_dir/x.txt${tab}new_dir/x.txt" <<<"$rename_out"; then
    printf '  ok   rename block emits an R<score> row old_dir/x.txt -> new_dir/x.txt\n'
    pass=$((pass + 1))
else
    printf '  FAIL rename block has no R<score> row for the planted git mv\n       got: %q\n' "$rename_out"
    fail=$((fail + 1))
fi

# manifest
manifest="$(cat "$excavate_out/main/work/manifest-diffs.txt")"
if grep -Eq '^\+.*left-pad' <<<"$manifest"; then
    printf '  ok   manifest block emits a + line for the dependency author A added\n'
    pass=$((pass + 1))
else
    printf '  FAIL manifest block has no + line naming left-pad\n       got: %q\n' "$manifest"
    fail=$((fail + 1))
fi

# pairs and SOC
pairs_file="$excavate_out/main/work/pairs.txt"
pair_n=""
while IFS="$tab" read -r c a b; do
    if [[ "$a" == coupled.txt && "$b" == hot.txt ]]; then pair_n="$c"; fi
done < "$pairs_file"
assert_eq "$excavate_planted_pair" "$pair_n" "pairs: coupled.txt<TAB>hot.txt (sorted order) co-changed exactly $excavate_planted_pair times"
assert_eq 0 "$(grep -Fc 'package-lock.json' "$pairs_file" || true)" "pairs: no pair involves package-lock.json (NONDOMAIN)"
assert_eq 0 "$(grep -Fc 'bulk/' "$pairs_file" || true)" "pairs: no pair involves bulk/ (MAXFILES)"
hot_pair_sum=0
while IFS="$tab" read -r c a b; do
    if [[ "$a" == hot.txt || "$b" == hot.txt ]]; then hot_pair_sum=$((hot_pair_sum + c)); fi
done < "$pairs_file"
soc_hot=""
while IFS="$tab" read -r c f; do
    if [[ "$f" == hot.txt ]]; then soc_hot="$c"; fi
done < "$excavate_out/main/work/soc.txt"
assert_eq "$hot_pair_sum" "$soc_hot" "soc: hot.txt's SOC equals the sum of its pair counts in pairs.txt ($hot_pair_sum)"

# persistence: the shared log split at its median commit date; hot.txt has
# in-window commits on both sides of every quartile point, so it must appear
# in both halves. Nothing may appear in a third half.
persist_file="$excavate_out/main/work/persist.txt"
[[ -f "$persist_file" ]] || { printf '  FAIL persistence block wrote no persist.txt\n'; fail=$((fail + 1)); }
persist_hot_first=0; persist_hot_second=0; persist_other=0
while IFS="$tab" read -r c h f; do
    case "$h" in
        first)  [[ "$f" == hot.txt ]] && persist_hot_first="$c" ;;
        second) [[ "$f" == hot.txt ]] && persist_hot_second="$c" ;;
        *)      persist_other=$((persist_other + 1)) ;;
    esac
done < "$persist_file"
assert_eq 0 "$persist_other" "persist: every row is tagged first or second"
if [[ "$persist_hot_first" -ge 1 && "$persist_hot_second" -ge 1 ]]; then
    printf '  ok   persist: hot.txt counted in both halves (%s + %s)\n' "$persist_hot_first" "$persist_hot_second"
    pass=$((pass + 1))
else
    printf '  FAIL persist: hot.txt missing from a half (first=%s second=%s)\n' "$persist_hot_first" "$persist_hot_second"
    fail=$((fail + 1))
fi
assert_eq 6 "$((persist_hot_first + persist_hot_second))" "persist: the two halves of hot.txt sum to its in-window revision count"
assert_eq 0 "$(grep -Fc 'package-lock.json' "$persist_file" || true)" "persist: NONDOMAIN exclusion carries through the shared log"

# baselines: one line, derived from hotspots.txt, whose knee share is computed
# from the file's own first five rows
excavate_find 'knee share' b_base
base_line="$(cat "$excavate_out/main/b$b_base.out")"
if [[ "$base_line" =~ ^files\ [0-9]+.median\ [0-9]+.p90\ [0-9]+.knee\ share\ [0-9]+%\ of\ [0-9]+\ revisions$ ]]; then
    printf '  ok   baselines: one line with files, median, p90, knee share, total (%s)\n' "$base_line"; pass=$((pass + 1))
else
    printf '  FAIL baselines line has the wrong shape: %s\n' "$base_line"; fail=$((fail + 1))
fi
base_total="${base_line##* of }"; base_total="${base_total%% revisions}"
hot_total="$(awk -F'\t' '{ t += $1 } END { print t + 0 }' "$excavate_out/main/work/hotspots.txt")"
assert_eq "$hot_total" "$base_total" "baselines: the revision total equals the sum of hotspots.txt's revision column"

# trend
excavate_monotone() {   # file col -> inc | dec | other (exactly four rows required)
    awk -F'\t' -v c="$2" 'NR > 1 { if ($c > prev) up++; else if ($c < prev) down++ } { prev = $c } END { if (NR == 4 && up == 3) print "inc"; else if (NR == 4 && down == 3) print "dec"; else print "other" }' "$1"
}
trend_hot="$excavate_out/trend-hot/b${b_trend}.out"
trend_cpl="$excavate_out/trend-coupled/b${b_trend}.out"
assert_eq 4 "$(count_lines "$(cat "$trend_hot")")" "trend on hot.txt prints four rows"
assert_eq inc "$(excavate_monotone "$trend_hot" 3)" "trend on hot.txt: LOC strictly increases across the four points"
assert_eq inc "$(excavate_monotone "$trend_hot" 4)" "trend on hot.txt: indentation strictly increases across the four points"
assert_eq 4 "$(count_lines "$(cat "$trend_cpl")")" "trend on coupled.txt prints four rows"
assert_eq dec "$(excavate_monotone "$trend_cpl" 3)" "trend on coupled.txt: LOC strictly decreases"
assert_eq dec "$(excavate_monotone "$trend_cpl" 4)" "trend on coupled.txt: indentation strictly decreases"

# contributors and last-active (one block, two commands: 2 + 2 lines)
contrib="$(cat "$excavate_out/contrib/b${b_contrib}.out")"
assert_eq 4 "$(count_lines "$contrib")" "contributors block prints two shortlog lines then two last-active lines"
assert_matches "$(sed -n 1p <<<"$contrib")" "^ *4[[:space:]]+${author_a}\$" "contributors: first line is author A with 4 commits"
assert_matches "$(sed -n 2p <<<"$contrib")" "^ *2[[:space:]]+${author_b}\$" "contributors: second line is author B with 2 commits"
if [[ "$contrib" == *dependabot* ]]; then
    printf '  FAIL contributors block lists the bot\n'
    fail=$((fail + 1))
else
    printf '  ok   contributors block does not list the bot\n'
    pass=$((pass + 1))
fi
assert_eq "${author_a}${tab}${excavate_dates[16]}" "$(sed -n 3p <<<"$contrib")" "last-active: author A's last hot.txt commit is p17's date"
assert_eq "${author_b}${tab}${excavate_dates[11]}" "$(sed -n 4p <<<"$contrib")" "last-active: author B's last hot.txt commit is p12's date"

# vars.sh: a later shell (a miner's, or the next Bash tool call) has none of the
# variables the blocks read. The persisted file must carry the RESOLVED values
# (the SINCE override, not the setup block's default), and a block run in a
# second, fresh process after sourcing it must reproduce the main pass. This is
# the property the single-process main pass cannot see on its own.
vars_file="$excavate_out/main/work/vars.sh"
assert_eq 1 "$([[ -s "$vars_file" ]] && echo 1 || echo 0)" "vars.sh: the persisted variables file is written and non-empty"
excavate_nondomain_n="$(bash -c 'eval "$(grep -m1 "^NONDOMAIN=(" <<<"$1")"; printf "%s" "${#NONDOMAIN[@]}"' _ "${excavate_blocks[1]}")"
[[ "$excavate_nondomain_n" -ge 1 ]] || fatal "could not count the NONDOMAIN entries the shared setup declares"
# shellcheck disable=SC2016  # the script is for the child shell to expand
vars_probe='. "$1"; printf "%s\n%s\n%s\n%s\n" "$SINCE" "${#NONDOMAIN[@]}" "$START" "$(git -C "$2" config --get core.quotePath)"'
vars_fresh="$(bash -c "$vars_probe" _ "$vars_file" "$excavate_sandbox")"
assert_eq "2020-06-01" "$(sed -n 1p <<<"$vars_fresh")" "vars.sh: a fresh shell reads the overridden SINCE, not the setup block's default"
assert_eq "$excavate_nondomain_n" "$(sed -n 2p <<<"$vars_fresh")" "vars.sh: a fresh shell reads NONDOMAIN as an array of the declared length ($excavate_nondomain_n)"
assert_eq "2020-07-01" "$(sed -n 3p <<<"$vars_fresh")" "vars.sh: a fresh shell reads START recomputed from the overridden SINCE"
assert_eq "false" "$(sed -n 4p <<<"$vars_fresh")" "vars.sh: a fresh shell inherits the core.quotePath export"

# Re-run the shared-log block in a second process that only sources vars.sh. The
# file lives in the pass's private TMPDIR, so the child writes its own log.txt.
vars_second_log() {   # the block text to run after sourcing
    local out="$excavate_out/second"
    mkdir -p "$out"
    # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
    { printf 'cd %q || exit 97\n. %q\n' "$excavate_sandbox" "$vars_file"; printf '%s\n' "$1"; printf 'wc -l < "$WORK/log.txt" | tr -d " "\n'; } > "$out/run.sh"
    run_timed 60 bash "$out/run.sh" 2>"$out/stderr" </dev/null
}
assert_eq "$(wc -l < "$log_file" | tr -d ' ')" "$(vars_second_log "${excavate_blocks[b_log]}")" "vars.sh: the shared log rebuilt in a second process that only sources it has the main pass's line count"

# Duplicates in the main fixture: every planted change is distinct, so the
# count is zero and the re-rank changes nothing.
assert_eq 0 "$(xb "$b_dups")" "dups: the main fixture plants no repeated patch, so the count is 0"
assert_eq 0 "$(wc -l < "$excavate_out/main/work/dups.txt" | tr -d ' ')" "dups: dups.txt is written and empty in the main fixture"
assert_eq "$(printf 'top five without duplicates (revisions with copies counted -> copies left out):\n'; head -5 "$excavate_out/main/work/hotspots.txt" | awk -F'\t' '{ printf "%d -> %d\t%s\n", $1, $1, $3 }')" "$(xb "$b_rerank")" "rerank: with no duplicates every top-five file keeps its count"

# --- Duplicated history: a release-branch flow -------------------------------
#
# One fix lands three times: on main (oldest), as a cherry-pick on a hotfix
# branch, and inside a "Release" roll-up on a release branch, both branches
# merged back. The hotfix branch also carries a change of its own, as release
# branches do: a merge whose tree equals the main line is skipped by git log's
# history simplification under a pathspec, and its copies never reach the log.
# hot.txt therefore counts 3 revisions to warm.txt's 2, and only 1
# once the copies are set aside. The roll-up is the NEWEST copy, so a dedupe
# that kept the first line of newest-first output would keep the roll-up and
# list the original fix as the duplicate (the #546/#573 case in #514).
#
# A second backport branch carries nothing but a cherry-pick of a change already
# on main (tidy.txt), merged back with no change of its own. That merge is
# TREESAME to main, so the pathspec in the shared log skips the branch and its
# copy never reaches log.txt. The dups block reads the same pathspec, so the
# copy must stay off dups.txt too; drop the pathspec from the block and it is
# listed (M-dup-pathspec below).
dup_repo="$excavate_out/dup-repo"
mkdir -p "$dup_repo"
(
    cd "$dup_repo"
    git init -q -b main .
    git config commit.gpgsign false
    dc() {   # date author subject
        GIT_AUTHOR_NAME="$2" GIT_COMMITTER_NAME="$2" \
            GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_EMAIL=noreply@example.invalid \
            GIT_AUTHOR_DATE="$1T12:00:00+0000" GIT_COMMITTER_DATE="$1T12:00:00+0000" \
            git commit -q -m "$3"
    }
    for k in $(seq 1 60); do printf 'hot line %d\n' "$k"; done > hot.txt
    for k in $(seq 1 60); do printf 'warm line %d\n' "$k"; done > warm.txt
    git add -A; dc 2020-01-15 "$author_a" "seed fixture"
    root="$(git rev-parse HEAD)"
    printf 'guard\n' >> hot.txt; git add hot.txt; dc 2020-07-01 "$author_a" "fix: guard hot"
    git rev-parse HEAD > ../dup-original
    printf 'w1\n' >> warm.txt; git add warm.txt; dc 2020-07-05 "$author_a" "edit warm 1"
    printf 'w2\n' >> warm.txt; git add warm.txt; dc 2020-07-10 "$author_b" "edit warm 2"
    printf 'tidy\n' > tidy.txt; git add tidy.txt; dc 2020-07-11 "$author_a" "tidy"
    git switch -q -c backport "$root"
    printf 'tidy\n' > tidy.txt; git add tidy.txt; dc 2020-07-12 "$author_a" "tidy"
    git rev-parse HEAD > ../dup-skipped
    git switch -q main
    GIT_AUTHOR_NAME="$author_a" GIT_COMMITTER_NAME="$author_a" \
        GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_EMAIL=noreply@example.invalid \
        GIT_AUTHOR_DATE=2020-07-12T13:00:00+0000 GIT_COMMITTER_DATE=2020-07-12T13:00:00+0000 \
        git merge -q --no-ff --no-edit backport >/dev/null
    git switch -q -c hotfix "$root"
    printf 'guard\n' >> hot.txt; git add hot.txt; dc 2020-07-12 "$author_a" "fix: guard hot (cherry picked)"
    git rev-parse HEAD > ../dup-cherry
    printf 'hotfix notes\n' > notes.txt; git add notes.txt; dc 2020-07-13 "$author_a" "hotfix notes"
    git switch -q -c release "$root"
    printf 'guard\n' >> hot.txt; git add hot.txt; dc 2020-07-15 "$author_b" "Release v1 (#9)"
    git rev-parse HEAD > ../dup-rollup
    git switch -q main
    GIT_AUTHOR_NAME="$author_a" GIT_COMMITTER_NAME="$author_a" \
        GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_EMAIL=noreply@example.invalid \
        GIT_AUTHOR_DATE=2020-07-20T12:00:00+0000 GIT_COMMITTER_DATE=2020-07-20T12:00:00+0000 \
        git merge -q --no-edit hotfix release >/dev/null
)
[[ "$(git -C "$dup_repo" rev-list --count --no-merges HEAD)" -eq 9 ]] \
    || fatal "the duplicated-history fixture did not produce 9 non-merge commits (seed, fix, 2 warm edits, tidy twice, cherry-pick, notes, roll-up)"
[[ "$(git -C "$dup_repo" rev-list --count --merges HEAD)" -eq 2 ]] \
    || fatal "the duplicated-history fixture did not merge the backport branch and the octopus back"

dup_run() {   # outdir dups-block-text [repo]
    local saved_sandbox="$excavate_sandbox" saved_dups="${excavate_blocks[b_dups]}" st=0
    excavate_sandbox="${3:-$dup_repo}"
    excavate_blocks[b_dups]="$2"
    xc_run "$1" 120 UNUSED "$b_dups" "$b_log" "$b_freq" "$b_loc" "$b_hot" "$b_rerank" || st=$?
    excavate_sandbox="$saved_sandbox"
    excavate_blocks[b_dups]="$saved_dups"
    return "$st"
}
dup_out="$excavate_out/dup"
rd=0; dup_run "$dup_out" "${excavate_blocks[b_dups]}" || rd=$?
assert_eq 0 "$rd" "the duplicated-history pass completes"
assert_eq 2 "$(cat "$dup_out/b$b_dups.out")" "dups: the cherry-pick and the roll-up repeat the fix's patch ID (count 2)"
assert_eq "$(sort "$excavate_out/dup-cherry" "$excavate_out/dup-rollup")" "$(sort "$dup_out/work/dups.txt")" "dups: dups.txt lists the cherry-pick and the roll-up, and not the original fix (the oldest copy is kept)"
dups_in_log="$(awk -v d="$dup_out/work/dups.txt" 'BEGIN { while ((getline s < d) > 0) x[s] = 1 } /^@@/ && (substr($1, 3) in x) { n++ } END { print n + 0 }' "$dup_out/work/log.txt")"
assert_eq 2 "$dups_in_log" "dups: every listed copy is a commit the shared log reads (same window and pathspec)"
if grep -qxF "$(cat "$excavate_out/dup-skipped")" "$dup_out/work/dups.txt" || grep -qF "@@$(cat "$excavate_out/dup-skipped")" "$dup_out/work/log.txt"; then
    printf '  FAIL dups: the backport branch'"'"'s copy (a TREESAME merge the pathspec skips) reached dups.txt or log.txt\n'
    fail=$((fail + 1))
else
    printf '  ok   dups: a copy on a branch the pathspec skips is absent from both dups.txt and log.txt\n'
    pass=$((pass + 1))
fi
assert_eq 3 "$(count_for "$dup_out/work/freq.txt" hot.txt)" "dups: the shared log still counts all three copies (counted, not excluded)"
assert_eq "hot.txt" "$(sed -n 1p "$dup_out/work/hotspots.txt" | cut -f3)" "dups: hot.txt leads the ranking with its copies counted"
assert_eq "warm.txt" "$(sed -n 1p "$dup_out/work/hotspots-dedup.txt" | cut -f3)" "rerank: warm.txt leads once the copies are set aside"
assert_eq 1 "$(awk -F'\t' '$3 == "hot.txt" { print $1 }' "$dup_out/work/hotspots-dedup.txt")" "rerank: hot.txt counts its one original revision"
assert_eq "$(printf 'top five without duplicates (revisions with copies counted -> copies left out):\n3 -> 1\thot.txt\n2 -> 2\twarm.txt')" "$(cat "$dup_out/b$b_rerank.out")" "rerank: the block prints both counts, so hot.txt's drop from 3 to 1 shows"

# M-dup: drop --reverse, so the first copy seen is the newest. The original fix
# is then listed as the duplicate, and the keep-oldest assertion above must fail.
mut="${excavate_blocks[b_dups]/ --reverse/}"
[[ "$mut" != "${excavate_blocks[b_dups]}" ]] || fatal "mutation M-dup did not change the dups block; --reverse moved"
rm_dup=0; dup_run "$excavate_out/dup-m" "$mut" || rm_dup=$?
assert_eq 0 "$rm_dup" "M-dup (no --reverse) still runs"
if grep -qxF "$(cat "$excavate_out/dup-original")" "$excavate_out/dup-m/work/dups.txt"; then
    printf '  ok   M-dup: without --reverse the original fix is listed as the duplicate, so the keep-oldest assertion bites\n'
    pass=$((pass + 1))
else
    printf '  FAIL M-dup: dropping --reverse still left the original fix off dups.txt; the keep-oldest assertion cannot see the order\n'
    fail=$((fail + 1))
fi

# M-dup-pathspec: drop the pathspec from the dups block. Nothing is simplified
# away then, so the backport branch's copy is listed and the assertion above
# must fail on it.
# shellcheck disable=SC2016  # literal text to match against, not an expansion
pathspec=' -- . "${NONDOMAIN[@]}"'
mut="${excavate_blocks[b_dups]/"$pathspec"/}"
[[ "$mut" != "${excavate_blocks[b_dups]}" ]] || fatal "mutation M-dup-pathspec did not change the dups block; the pathspec moved"
rm_dp=0; dup_run "$excavate_out/dup-p" "$mut" || rm_dp=$?
assert_eq 0 "$rm_dp" "M-dup-pathspec (no pathspec) still runs"
if grep -qxF "$(cat "$excavate_out/dup-skipped")" "$excavate_out/dup-p/work/dups.txt"; then
    printf '  ok   M-dup-pathspec: without the pathspec the skipped branch'"'"'s copy is listed, so the same-pathspec assertion bites\n'
    pass=$((pass + 1))
else
    printf '  FAIL M-dup-pathspec: dropping the pathspec left dups.txt unchanged; the same-pathspec assertion cannot see it\n'
    fail=$((fail + 1))
fi

# --- Duplicated history: a file enters the top five ---------------------------
#
# The re-rank block's second clause lists a file that was NOT in the original top
# five and is in the top five once copies are set aside. The fixture above has two
# files over the LOC floor, so that clause never fires there. Here six files clear
# the floor: a.txt carries a fix that lands three times (main, hotfix cherry-pick,
# release roll-up) for 3 revisions in the window (the seed predates it), b..e carry 2
# each, and f.txt carries 2 but ranks sixth on LOC. Set the copies aside and a.txt
# falls to 1, so f.txt enters. Delete
# the clause and the block stops printing f.txt's row; only this fixture sees it.
ent_repo="$excavate_out/ent-repo"
mkdir -p "$ent_repo"
(
    cd "$ent_repo"
    git init -q -b main .
    git config commit.gpgsign false
    ec() {   # date author subject
        GIT_AUTHOR_NAME="$2" GIT_COMMITTER_NAME="$2" \
            GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_EMAIL=noreply@example.invalid \
            GIT_AUTHOR_DATE="$1T12:00:00+0000" GIT_COMMITTER_DATE="$1T12:00:00+0000" \
            git commit -q -m "$3"
    }
    for f in a:60 b:80 c:70 d:65 e:62 f:60; do
        for k in $(seq 1 "${f#*:}"); do printf '%s line %d\n' "${f%%:*}" "$k"; done > "${f%%:*}.txt"
    done
    git add -A; ec 2020-01-15 "$author_a" "seed fixture"
    root="$(git rev-parse HEAD)"
    printf 'guard\n' >> a.txt; git add a.txt; ec 2020-07-01 "$author_a" "fix: guard a"
    printf 'e1\n' | tee -a b.txt c.txt d.txt e.txt f.txt >/dev/null; git add -A; ec 2020-07-05 "$author_a" "edit b-f 1"
    printf 'e2\n' | tee -a b.txt c.txt d.txt e.txt f.txt >/dev/null; git add -A; ec 2020-07-10 "$author_b" "edit b-f 2"
    git switch -q -c hotfix "$root"
    printf 'guard\n' >> a.txt; git add a.txt; ec 2020-07-12 "$author_a" "fix: guard a (cherry picked)"
    printf 'hotfix notes\n' > notes.txt; git add notes.txt; ec 2020-07-13 "$author_a" "hotfix notes"
    git switch -q -c release "$root"
    printf 'guard\n' >> a.txt; git add a.txt; ec 2020-07-15 "$author_b" "Release v1 (#9)"
    git switch -q main
    GIT_AUTHOR_NAME="$author_a" GIT_COMMITTER_NAME="$author_a" \
        GIT_AUTHOR_EMAIL=noreply@example.invalid GIT_COMMITTER_EMAIL=noreply@example.invalid \
        GIT_AUTHOR_DATE=2020-07-20T12:00:00+0000 GIT_COMMITTER_DATE=2020-07-20T12:00:00+0000 \
        git merge -q --no-edit hotfix release >/dev/null
)
[[ "$(git -C "$ent_repo" rev-list --count --no-merges HEAD)" -eq 7 ]] \
    || fatal "the top-five-entry fixture did not produce 7 non-merge commits (seed, fix, 2 edits, cherry-pick, notes, roll-up)"
[[ "$(git -C "$ent_repo" rev-list --count --merges HEAD)" -eq 1 ]] \
    || fatal "the top-five-entry fixture did not merge the octopus back"
ent_out="$excavate_out/ent"
re=0; dup_run "$ent_out" "${excavate_blocks[b_dups]}" "$ent_repo" || re=$?
assert_eq 0 "$re" "the top-five-entry pass completes"
assert_eq "$(printf 'a.txt\nb.txt\nc.txt\nd.txt\ne.txt')" "$(head -5 "$ent_out/work/hotspots.txt" | cut -f3)" "enter: with copies counted, f.txt is sixth and a.txt is in the top five"
assert_eq "$(printf 'top five without duplicates (revisions with copies counted -> copies left out):\n3 -> 1\ta.txt\n2 -> 2\tb.txt\n2 -> 2\tc.txt\n2 -> 2\td.txt\n2 -> 2\te.txt\n2 -> 2\tf.txt')" "$(cat "$ent_out/b$b_rerank.out")" "enter: f.txt is listed with both counts because a.txt's copies pushed it into the top five"

# --- Mutations: prove the assertions bite ------------------------------------
#
# Each mutant is the extracted block string with one clause removed, run through
# the same harness. The skill text on disk is never edited. The shared-log block
# carries the window and the exclusions that freq.txt and pairs.txt merely read,
# so that is where those two clauses live and where they are removed.

freq_is_six() { [[ "$(count_for "$1" hot.txt)" == "$excavate_planted_hot_revs" ]]; }
orig_log="${excavate_blocks[b_log]}"

# M1: drop --since from the shared log.
mut="${orig_log/--since=\"\$SINCE\" /}"
[[ "$mut" != "$orig_log" ]] || fatal "mutation M1 did not change the shared-log block; the clause it removes moved"
excavate_blocks[b_log]="$mut"
m1=0; xc_run "$excavate_out/m1" 120 UNUSED "$b_log" "$b_freq" || m1=$?
excavate_blocks[b_log]="$orig_log"
assert_eq 0 "$m1" "M1 (no --since) still runs"
assert_eq 7 "$(count_for "$excavate_out/m1/work/freq.txt" hot.txt)" "M1: without --since hot.txt counts 7 (the pre-window commit leaks in)"
if freq_is_six "$excavate_out/m1/work/freq.txt"; then
    printf '  FAIL M1: the hot.txt == 6 assertion still passes on the --since-less output; it does not bite\n'
    fail=$((fail + 1))
else
    printf '  ok   M1: the hot.txt == 6 assertion FAILS on the --since-less output\n'
    pass=$((pass + 1))
fi
if freq_is_six "$freq_file"; then
    printf '  ok   M1 control: the same assertion passes on the unmutated output\n'
    pass=$((pass + 1))
else
    printf '  FAIL M1 control: the assertion fails on the unmutated output\n'
    fail=$((fail + 1))
fi

# M2: drop the NONDOMAIN pathspec from the shared log.
mut="${orig_log/ \"\$\{NONDOMAIN\[@\]\}\"/}"
[[ "$mut" != "$orig_log" ]] || fatal "mutation M2 did not change the shared-log block; the clause it removes moved"
excavate_blocks[b_log]="$mut"
m2=0; xc_run "$excavate_out/m2" 120 UNUSED "$b_log" "$b_pairs" || m2=$?
excavate_blocks[b_log]="$orig_log"
assert_eq 0 "$m2" "M2 (no NONDOMAIN) still runs"
if grep -Fq 'package-lock.json' "$excavate_out/m2/work/pairs.txt"; then
    printf '  ok   M2: without NONDOMAIN a package-lock.json pair appears, so the pairs assertion bites\n'
    pass=$((pass + 1))
else
    printf '  FAIL M2: dropping NONDOMAIN produced no package-lock.json pair; the pairs assertion cannot see the exclusion\n'
    fail=$((fail + 1))
fi

# M3: the trend guard. Force an empty revision (the sed address past the end of
# revs.txt) so the guard is what separates "skip" from "report the index as
# history", then remove the guard and show the tree's LOC comes back as data.
orig_trend="${excavate_blocks[b_trend]}"
forced="${orig_trend//\$(( (total * q + 3) \/ 4 ))p/\$(( total + 100 ))p}"
[[ "$forced" != "$orig_trend" ]] || fatal "mutation M3 could not force an empty revision; the trend block's sed address changed"
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
guard='[ -n "$r" ] || continue'
[[ "$forced" == *"$guard"* ]] || fatal "the trend block no longer carries '$guard'"
unguarded="${forced/$guard/}"
[[ "$unguarded" != "$forced" ]] || fatal "mutation M3 did not remove the guard"
excavate_blocks[b_trend]="$forced"
m3a=0; xc_run "$excavate_out/m3a" 120 hot.txt "$b_trend" || m3a=$?
excavate_blocks[b_trend]="$unguarded"
m3b=0; xc_run "$excavate_out/m3b" 120 hot.txt "$b_trend" || m3b=$?
excavate_blocks[b_trend]="$orig_trend"
assert_eq 0 "$((m3a + m3b))" "M3 (forced-empty revision, with and without the guard) runs"
assert_eq 0 "$(wc -c < "$excavate_out/m3a/b${b_trend}.out" | tr -d ' ')" "M3: with the guard, an empty revision prints no row"
assert_eq 4 "$(count_lines "$(cat "$excavate_out/m3b/b${b_trend}.out")")" "M3: without the guard, an empty revision still prints four rows"
assert_eq "$hot_loc" "$(awk -F'\t' 'NR == 1 { print $3 }' "$excavate_out/m3b/b${b_trend}.out")" "M3: and those rows carry the working tree's LOC ($hot_loc) as if it were history"

# M4: the hang guard. Strip the revision and the stdin redirect from the
# contributors block; with the harness's open-but-silent stdin the block must
# time out, proving the 20 s guard above can fire.
orig_contrib="${excavate_blocks[b_contrib]}"
mut="${orig_contrib// HEAD -- / -- }"
mut="${mut// <\/dev\/null/}"
[[ "$mut" != "$orig_contrib" ]] || fatal "mutation M4 did not change the contributors block"
excavate_blocks[b_contrib]="$mut"
m4=0; xc_run "$excavate_out/m4" 3 hot.txt "$b_contrib" || m4=$?
excavate_blocks[b_contrib]="$orig_contrib"
assert_eq 124 "$m4" "M4: without HEAD and </dev/null the contributors block hangs on stdin and is killed (shortlog read stdin)"

# M5: test the bots regex against the whole header instead of the author field.
m5_from='h[2] ~ bots'
# shellcheck disable=SC2016  # literal awk text, not an expansion
m5_to='$0 ~ bots'
mut="${orig_log//"$m5_from"/$m5_to}"
[[ "$mut" != "$orig_log" ]] || fatal "mutation M5 did not change the shared-log block; the author-field test moved"
excavate_blocks[b_log]="$mut"
m5=0; xc_run "$excavate_out/m5" 120 UNUSED "$b_log" "$b_freq" || m5=$?
excavate_blocks[b_log]="$orig_log"
assert_eq 0 "$m5" "M5 (whole-header bot test) still runs"
assert_eq "" "$(count_for "$excavate_out/m5/work/freq.txt" ci-notes.txt)" "M5: a whole-header bot test drops the human commit, so the ci-notes.txt assertion bites"

# M6: drop the core.quotePath export from the shared setup. Every later block
# then sees the default, quoted spelling of café.txt.
orig_setup="${excavate_blocks[1]}"
mut="$(grep -vF 'GIT_CONFIG_KEY_0=core.quotePath' <<<"$orig_setup")"
[[ "$mut" != "$orig_setup" ]] || fatal "mutation M6 did not change the shared setup block; the quotePath export moved"
excavate_blocks[1]="$mut"
m6=0; xc_run "$excavate_out/m6" 120 UNUSED "$b_log" "$b_freq" "$b_loc" "$b_hot" || m6=$?
excavate_blocks[1]="$orig_setup"
assert_eq 0 "$m6" "M6 (no core.quotePath export) still runs"
assert_eq "" "$(awk -F'\t' '$2 == "café.txt" { print $1 }' "$excavate_out/m6/work/loc.txt")" "M6: under the default quotePath café.txt never reaches loc.txt, so the loc assertion bites"
assert_eq 0 "$(grep -Fc 'café.txt' "$excavate_out/m6/work/hotspots.txt" || true)" "M6: and café.txt is absent from hotspots.txt, so the hotspots assertion bites"

# M7: the second process re-runs the Step 0 variables block (the old advice)
# instead of sourcing vars.sh. SINCE resets to '12 months ago', which is empty
# against a 2020 fixture, so the log it builds has no lines and the vars.sh
# line-count assertion above bites.
m7_log="$(
    out="$excavate_out/m7"; mkdir -p "$out"
    # shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
    { printf 'export TMPDIR=%q\ncd %q || exit 97\n' "$excavate_out/main/tmp" "$excavate_sandbox"; printf '%s\n' "${excavate_blocks[1]}"; printf '%s\n' "${excavate_blocks[b_log]}"; printf 'wc -l < "$WORK/log.txt" | tr -d " "\n'; } > "$out/run.sh"
    run_timed 60 bash "$out/run.sh" 2>"$out/stderr" </dev/null
)"
assert_eq 0 "$m7_log" "M7: re-running the Step 0 block in the second process builds an empty log against the fixture window"
if [[ "$m7_log" == "$(wc -l < "$log_file" | tr -d ' ')" ]]; then
    printf '  FAIL M7: the stale-window rerun matches the main pass; the vars.sh line-count assertion does not bite\n'
    fail=$((fail + 1))
else
    printf '  ok   M7: the vars.sh line-count assertion FAILS when the second process re-runs Step 0 instead of sourcing\n'
    pass=$((pass + 1))
fi

# -----------------------------------------------------------------------------

section "the removed-guard sweep lists a guard removed from a file that survives"

# /execute Step 4's removed-guard sweep (#487). The module rung above only sees
# deleted files; this line exists for a guard edited out of a file that stays.
# Plant exactly that: one surviving file loses an `exit`, an `||` fallback, a
# plain assignment, and a line whose only guard-like word is a substring
# (`exitcode`). The first two must be listed; the last two must not.
guard_line="$(extract_range_lines "$repo_root/execute/SKILL.md" | grep -m1 '^git diff -U0 ' || true)"
[[ -n "$guard_line" ]] || fatal "execute/SKILL.md no longer documents the removed-guard sweep's 'git diff -U0' line"
guard_repo="$base_sandbox/guard"
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
(
    mkdir -p "$guard_repo" && cd "$guard_repo"
    git init -q -b prod .
    git config user.email skillkit@example.invalid
    git config user.name 'Skill Kit Test'
    git config commit.gpgsign false
    printf '%s\n' 'slug=$(parse "$line")' '[ -n "$slug" ] || exit 1' 'resolve "$x" || fallback' 'count=3' 'exitcode=4' 'echo kept' > owner.sh
    git add owner.sh && git commit -q -m base
    git switch -q -c feature
    printf '%s\n' 'slug=$(owner archive-dir)' 'echo kept' > owner.sh
    git commit -q -am feature
)
guard_out="$(run_range_line "$guard_repo" "$(block_holding execute/SKILL.md "$guard_line")" "$guard_line")"
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
assert_contains "$guard_out" '-[ -n "$slug" ] || exit 1' "the sweep lists a removed 'exit' guard inside a surviving file"
# shellcheck disable=SC2016  # literal text to match against, or a script to write; never an expansion
assert_contains "$guard_out" '-resolve "$x" || fallback' "the sweep lists a removed '||' fallback"
assert_eq 0 "$(printf '%s\n' "$guard_out" | grep -cE '^-(count=3|exitcode=4)$' || true)" \
    "the sweep skips a removed assignment and a substring-only match ('exitcode')"
assert_eq 0 "$(printf '%s\n' "$guard_out" | grep -c '^---' || true)" \
    "the sweep drops the diff's '---' file header"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
