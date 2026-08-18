#!/usr/bin/env bash
# test-bisect-rider-claims.sh — pins the factual claims `/triage-issue`'s
# regression rider makes about `git bisect run` behavior.
#
# Why this exists. The rider (triage-issue/SKILL.md, Step 2, "A commit the loop
# cannot run on must be skipped, not marked bad") is copy-runnable instruction:
# a downstream agent reads it and executes what it says. Its claims are about a
# tool's observable behavior, so they are checkable — and across four review
# rounds on #237, four successive claims about that behavior shipped wrong,
# each replaced by a new wrong one. Every round was caught by a human or a
# review sub-agent reading carefully, which is the control this repo has already
# decided is too weak to rely on: the same argument as
# scripts/test-review-currency-marker.sh, where two skills shared a string with
# no shared definition of its shape.
#
# The recurring defect was never any single wrong sentence. It was shipping a
# claim about git with nothing but attention behind it. This suite is that
# missing feedback loop, and it is deliberately behavioral rather than textual:
# it builds real repositories and runs real bisects, so it fails when *git*
# changes as well as when the prose does.
#
# Scope. This pins behavior the rider asserts, not the prose. A reworded rider
# making the same claims still passes; a reworded rider making a *different*
# claim needs a matching case added here. The final section greps the skill for
# the literal error strings, so those cannot drift silently.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
skill="$repo_root/triage-issue/SKILL.md"

pass=0
fail=0

# --- git version floor -------------------------------------------------------
# The assertions below are statements about git's observable behavior, so the
# installed git is an untracked input to a suite that otherwise looks hermetic.
# One assertion is version-gated: the `bogus exit code N for good revision`
# guard was introduced in **git 2.36.0** (release notes: "A user can forget to
# make a script file executable before giving it to `git bisect run`… Try to
# recognize this situation and stop iteration early"). Established by bisecting
# git's own tags — v2.35.0 `builtin/bisect--helper.c` lacks the string, v2.36.0
# has it. Below 2.36 exit 126/127 is marked bad silently and that row fails.
#
# Fail here with the reason rather than letting four assertions fail opaquely.
# Measured green on 2.43.0 (local) and 2.54.0 (ubuntu-latest); see
# ~/.claude/research/chrislacey89-skills/git-version-floor-2026-08-16.md
GIT_FLOOR_MAJOR=2
GIT_FLOOR_MINOR=36

git_version="$(git --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
git_major="${git_version%%.*}"
git_minor_rest="${git_version#*.}"
git_minor="${git_minor_rest%%.*}"

if [[ -z "$git_version" ]]; then
    printf 'FAIL  could not parse a version from git --version (got: %q)\n' \
        "$(git --version)" >&2
    exit 1
fi

if (( git_major < GIT_FLOOR_MAJOR )) ||
   (( git_major == GIT_FLOOR_MAJOR && git_minor < GIT_FLOOR_MINOR )); then
    printf 'SKIPPED  git %s is below the required %d.%d.\n' \
        "$git_version" "$GIT_FLOOR_MAJOR" "$GIT_FLOOR_MINOR" >&2
    printf '         git bisect run gained its 126/127 broken-script guard in 2.36.0;\n' >&2
    printf '         before that the guarded behavior does not exist to assert.\n' >&2
    printf '         Upgrade git to run this suite.\n' >&2
    exit 1
fi
# -----------------------------------------------------------------------------

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

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

# build_repo <dir> <n_commits> "<untestable commit numbers>" <bug_commit>
#
# Commit cN gets the loop harness unless N is listed untestable, simulating the
# rider's stated causes (test file absent, build broken at that revision). The
# bug is introduced at <bug_commit> and persists to HEAD.
build_repo() {
    local dir="$1" n="$2" untestable="$3" bug="$4" i
    rm -rf "$dir"; mkdir -p "$dir"
    (
        cd "$dir"
        git init -q
        git config user.email t@t; git config user.name t
        for ((i = 1; i <= n; i++)); do
            echo "line$i" >> f.txt
            [[ "$i" == "$bug" ]] && echo BUG >> f.txt
            if [[ " $untestable " == *" $i "* ]]; then
                rm -f loop.sh
            else
                printf '#!/bin/sh\ngrep -q BUG f.txt && exit 1\nexit 0\n' > loop.sh
                chmod +x loop.sh
            fi
            git add -A
            git commit -qm "c$i"
        done
    )
}

# bisect_result <dir> <good_depth> <loop_expr> -> subject of reported commit,
# or a normalized token for the non-answer outcomes the rider names.
bisect_result() {
    local dir="$1" depth="$2" expr="$3" out sha
    (
        cd "$dir"
        git bisect start HEAD "$(git rev-parse "HEAD~$depth")" >/dev/null 2>&1
        out="$(git bisect run sh -c "$expr" 2>&1 || true)"
        git bisect reset >/dev/null 2>&1
        sha="$(printf '%s' "$out" | grep -oE '^[0-9a-f]{40} is the first bad commit' | cut -c1-40 || true)"
        if [[ -n "$sha" ]]; then
            git log --format='%s' -1 "$sha"
        elif printf '%s' "$out" | grep -q 'cannot continue any more'; then
            echo '<cannot-continue>'
        elif printf '%s' "$out" | grep -qE 'bogus exit code [0-9]+ for good revision'; then
            echo '<bogus-exit-code>'
        elif printf '%s' "$out" | grep -qE 'bisect run failed: exit code [0-9]+ .* is < 0 or >= 128'; then
            echo '<aborted>'
        else
            # Deliberately distinct from <aborted>. An earlier draft expected
            # <other> on the abort rows, which made them assert only "not one of
            # the known outcomes" — they passed even with the `git bisect start`
            # line removed entirely. Matching the real message is what makes
            # those rows mean what their labels say.
            echo '<other>'
        fi
    )
}

UNGUARDED='test -x ./loop.sh || exit 1; ./loop.sh'
GUARDED='test -x ./loop.sh || exit 125; ./loop.sh'

# ---------------------------------------------------------------------------
section 'Exit-code mapping: 125 skips, 1-127 (except 125) is bad, >=128 aborts'
# ---------------------------------------------------------------------------
# The rider states this mapping explicitly, contradicting the intuitive
# "non-zero means fail". Round 1 shipped the intuitive version.

build_repo "$workdir/map" 6 "" 5
for code in 1 5 124 126 127; do
    assert_eq 'c5' "$(bisect_result "$workdir/map" 5 "grep -q BUG f.txt && exit $code; exit 0")" \
        "exit $code is treated as bad"
done
for code in 128 137 139 255; do
    assert_eq '<aborted>' "$(bisect_result "$workdir/map" 5 "grep -q BUG f.txt && exit $code; exit 0")" \
        "exit $code aborts the run (rider's segfault/OOM clause)"
done

# ---------------------------------------------------------------------------
section 'The guard works; unguarded is untrustworthy at any size or position'
# ---------------------------------------------------------------------------
# The rider claims no size or position of untestable region is safe, and cites
# two measured cases. Rounds 2 and 3 each shipped a *predictive rule* for which
# commit an unguarded run returns; both were falsified. The rider now claims
# only that the answer need not be correct, which is what these cases pin.

build_repo "$workdir/small" 12 "2 3" 5
assert_eq 'c2' "$(bisect_result "$workdir/small" 11 "$UNGUARDED")" \
    'two-commit stretch near the good end returns a WRONG commit'
assert_eq 'c5' "$(bisect_result "$workdir/small" 11 "$GUARDED")" \
    'same repo, guarded, returns the real regression'

build_repo "$workdir/mid" 12 "6 7 8 9" 5
assert_eq 'c5' "$(bisect_result "$workdir/mid" 11 "$UNGUARDED")" \
    'four-commit stretch spanning the midpoint happens to return the RIGHT commit'

build_repo "$workdir/middle" 12 "5 6 7 8" 12
assert_eq 'c5' "$(bisect_result "$workdir/middle" 11 "$UNGUARDED")" \
    'a mid-history stretch misreports (refutes the "last-good + 1" rule, round 3)'
assert_eq 'c12' "$(bisect_result "$workdir/middle" 11 "$GUARDED")" \
    'same repo, guarded, returns the real regression'

# ---------------------------------------------------------------------------
section 'The failure is silent under exit 1 and loud under exit 127'
# ---------------------------------------------------------------------------
# This asymmetry is the rider's core warning: the dangerous case prints exactly
# what a correct run prints.

build_repo "$workdir/silent" 12 "1 2 3 4 5 6 7 8" 12
assert_eq 'c2' "$(bisect_result "$workdir/silent" 11 "$UNGUARDED")" \
    'exit 1 yields a confident wrong answer, indistinguishable from a right one'
assert_eq '<bogus-exit-code>' \
    "$(bisect_result "$workdir/silent" 11 'test -x ./loop.sh || exit 127; ./loop.sh')" \
    'exit 127 is caught at the good revision instead'

# ---------------------------------------------------------------------------
section "The guard's own edge case is one-sided about the boundary"
# ---------------------------------------------------------------------------
# Round 4 shipped "adjacent to a skipped stretch", which is wrong on the newer
# side. Skipped commits at or older than the first-bad block disambiguation;
# skipped commits newer than it are irrelevant.

build_repo "$workdir/older" 12 "7" 8
assert_eq '<cannot-continue>' "$(bisect_result "$workdir/older" 11 "$GUARDED")" \
    'skipping the commit immediately OLDER than first-bad blocks disambiguation'

build_repo "$workdir/isbug" 12 "8" 8
assert_eq '<cannot-continue>' "$(bisect_result "$workdir/isbug" 11 "$GUARDED")" \
    'skipping the first-bad commit ITSELF blocks disambiguation'

# Every case here must actually skip something. An earlier draft used untestable
# c5 (older, non-adjacent) and c10-c11 (far newer) with the bug at c8 — but the
# probe path for that configuration never visits those commits, so `git bisect
# log` recorded zero skips and both rows passed with their skip lists emptied
# entirely. Pick positions the search actually probes, and check `bisect skip`
# appears in the log when adding a case.

build_repo "$workdir/plural" 12 "6 7" 8
assert_eq '<cannot-continue>' "$(bisect_result "$workdir/plural" 11 "$GUARDED")" \
    'skipping the two commits immediately older blocks it too (pins the plural)'

# Pins the word "immediately". Without this case the rider could be reworded to
# "any commit older than first-bad blocks disambiguation" and stay green. c6 is
# probed and skipped here (c5 would not be), so the row measures its label.
build_repo "$workdir/gap" 12 "6" 8
assert_eq 'c8' "$(bisect_result "$workdir/gap" 11 "$GUARDED")" \
    'skipping an OLDER but non-adjacent commit still resolves cleanly'

build_repo "$workdir/newer" 12 "9" 8
assert_eq 'c8' "$(bisect_result "$workdir/newer" 11 "$GUARDED")" \
    'skipping the commit immediately NEWER than first-bad resolves cleanly'

# ---------------------------------------------------------------------------
section 'Exit 127 is only loud when the good reference is itself untestable'
# ---------------------------------------------------------------------------
# The rider claimed 126/127 fails loudly, full stop. Git re-runs the loop at the
# known-good reference and errors only if it fails there too — so the guard
# fires on an untestable good ref and not otherwise. These two rows differ only
# in whether the good reference is inside the untestable stretch.

build_repo "$workdir/badgood" 12 "1 2 3 4 5 6 7 8" 12
assert_eq '<bogus-exit-code>' \
    "$(bisect_result "$workdir/badgood" 11 'test -x ./loop.sh || exit 127; ./loop.sh')" \
    'untestable GOOD ref: exit 127 stops loudly'

build_repo "$workdir/goodgood" 12 "5 6 7" 12
assert_eq 'c5' \
    "$(bisect_result "$workdir/goodgood" 11 'test -x ./loop.sh || exit 127; ./loop.sh')" \
    'testable GOOD ref: exit 127 is silent and names the wrong commit'

# The guard's condition is rc == res (git's own source), not "the good ref also
# failed". Here the loop exits 127 where untestable and 1 everywhere else, so the
# good ref fails with a DIFFERENT code than the probes and the guard stays quiet.
# The expected value is c2, not <bogus-exit-code>: exiting 1 at every testable
# revision marks them all bad, so the search collapses to good+1. What this row
# pins is the absence of the guard. Without it the rider could say the guard
# fires when the loop "fails there too" — which it did, wrongly — and stay green.
build_repo "$workdir/diffcode" 12 "5 6 7" 12
assert_eq 'c2' \
    "$(bisect_result "$workdir/diffcode" 11 'test -x ./loop.sh || exit 127; exit 1')" \
    'GOOD ref failing with a DIFFERENT code (1 vs 127) does not trip the guard'

# ---------------------------------------------------------------------------
section 'The rider still documents what this suite pins'
# ---------------------------------------------------------------------------
# Behavioral cases above cannot notice the prose dropping a claim. These greps
# tie the two together, so deleting a documented string fails the suite rather
# than silently un-documenting verified behavior.

grep_skill() {
    if grep -qF "$1" "$skill"; then
        printf '  ok   %s\n' "$2"; pass=$((pass + 1))
    else
        printf '  FAIL %s\n       missing from %s: %q\n' "$2" "${skill#"$repo_root/"}" "$1"
        fail=$((fail + 1))
    fi
}

grep_skill 'git bisect run sh -c' 'rider carries the || exit 125 wrapper idiom'
grep_skill 'exit 125' 'rider names the skip code'
grep_skill 'bogus exit code 127 for good revision' 'rider quotes the loud-failure string'
grep_skill 'bisect run cannot continue any more' 'rider quotes the cannot-disambiguate string'
grep_skill 'The first bad commit could be any of:' 'rider quotes the candidate-list string'
grep_skill 'bisect found first bad commit' 'rider quotes the silent-failure string'

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
