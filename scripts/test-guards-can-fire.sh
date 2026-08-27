#!/usr/bin/env bash
# test-guards-can-fire.sh — a guard whose condition cannot become true is worse
# than no guard, because it reports coverage while providing none.
#
# THE DRIFT CLASS. These suites are dense with guards: floors, non-vacuity
# checks, FATALs that stop a run before it reports on text it never read. Each
# one carries a message asserting what it protects. Nothing checks that the
# guard can actually fire, and a guard that cannot is invisible in exactly the
# way the defect it guards against is invisible — the suite prints its normal
# green, the message never appears, and the absence of an alarm reads as the
# absence of a problem. docs/solutions/testing-patterns/
# validate-the-instrument-not-only-the-subject-2026-08-23.md is the family.
#
# THE INCIDENT (PR #296, 2026-08-27). A change hardening three extractors that
# read a physical line where they meant a paragraph shipped four instances of
# its own defect class, all found by review and none by any check. Two were dead
# guards:
#
#   1. `( cd "$scratch"; …; git commit … ) || fatal "could not build the repo"`.
#      `set -e` is suppressed inside the left operand of `||`, so the subshell
#      ran past a failed commit and exited 0. Reproduced under a global
#      core.hooksPath whose pre-commit rejects: the commit failed, the guard
#      stayed silent, and the suite passed only because `git diff` fell back to
#      index-vs-worktree and happened to give the same answer.
#
#   2. A non-vacuity check comparing a value against itself after both sides had
#      been through the same prefix strip, so the condition was unreachable.
#      Deleting the operation it guarded left the suite at 13 passed, 0 failed.
#      Its comment said "Verified: removing the split turns this into a FATAL."
#      It had not been run.
#
# Shape 2 is not decidable by grep in general — it needs the two operands'
# provenance — so this suite does not attempt it. Shape 1 is decidable, and so
# is a third shape from the same PR: an awk paragraph reader that matches its
# anchor against the still-wrapped record. Both are pinned below.
#
# WHY A NEW SUITE RATHER THAN A ROW IN AN EXISTING ONE.
# scripts/test-duplicate-guard-programs.sh is the nearest neighbor and keys on a
# reader appearing twice in one suite; both shapes here appear exactly once, so
# it is silent on them. That is the recurrence docs/solutions/testing-patterns/
# mechanism-generality-lags-the-pattern-2026-08-23.md names — a mechanism
# inherits the syntax of the instance that produced it — which is also why the
# self-tests below plant fixtures instead of trusting a floor: its Prevention #2
# says a detector whose healthy state is zero hits needs a self-test, not a
# floor.
#
# WHAT THIS DOES NOT CATCH, stated so nobody over-trusts it. Only two syntactic
# shapes. A guard can be dead for reasons no grep can see — a comparison whose
# operands are always equal, a condition on a variable that is always empty, a
# `case` arm no value reaches. This narrows the class; it does not close it.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

self="scripts/test-guards-can-fire.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# Drop whole-line comments before scanning. This suite must NAME the shapes it
# forbids in its own header, and test-compound-clustering-single-source.sh
# records what happens when a suite that quotes what it forbids does not exclude
# its own quoting (its incident 3). A comment in ANY suite may legitimately
# discuss the defect — the fix in test-compound-clustering-single-source.sh does
# exactly that — so the exclusion is by comment, not by filename.
strip_comments() { sed 's/^[[:space:]]*#.*$//'; }

# ---------------------------------------------------------------------------
# Detector A — a subshell used as the left operand of `||`.
#
# `set -e` does not apply inside the left operand of `||`, so `( … ) || fatal`
# cannot report a failure that happens inside the subshell: the subshell keeps
# running and exits with the status of its LAST command. Any guard written this
# way is inert with respect to everything but its final line.
detect_subshell_guard() {  # stdin: file text. stdout: offending lines.
    strip_comments | grep -nE '^[[:space:]]*\)[[:space:]]*\|\|' || true
}

# ---------------------------------------------------------------------------
# Detector B — awk paragraph mode matching the anchor against the wrapped record.
#
# With RS="" the record is a whole markdown paragraph, newlines and all. A reader
# that unwraps (gsub(/\n/," ")) but tests `index($0, …)` is still matching
# line-wise at the anchor, so a wrap landing inside the anchor makes the match
# miss — producing a FATAL that names a rewording which never happened. Build the
# unwrapped record first, then match against it.
detect_wrapped_anchor_match() {  # stdin: file text. stdout: offending lines.
    local text; text="$(cat)"
    if printf '%s' "$text" | strip_comments | grep -q 'RS *= *""'; then
        # shellcheck disable=SC2016  # literal awk source being searched for, not a shell expansion
        printf '%s' "$text" | strip_comments | grep -nE 'index\(\$0,' || true
    fi
}

# ---------------------------------------------------------------------------
section "the scan covers a real file list"

# Excludes ITSELF. The self-tests below hold both forbidden shapes as fixture
# strings, and a fixture is not a comment, so the comment filter cannot reach
# them. scripts/test-compound-clustering-single-source.sh made the same
# exclusion for the same reason (its incident 3) and named the cost, which
# applies here verbatim: a genuine dead guard pasted into THIS file would not be
# caught by THIS file. That is the accepted price of letting a suite carry
# executable examples of what it forbids — and the self-tests are what make the
# exclusion survivable, since they exercise the detectors directly.
suites="$(git ls-files 'scripts/test-*.sh' | grep -v -x -- "$self")"
suite_count="$(printf '%s\n' "$suites" | grep -c . || true)"
[ "${suite_count:-0}" -ge 10 ] \
    || fatal "found only ${suite_count:-0} contract suite(s) — the glob is wrong, and an empty list passes every assertion below vacuously."
ok "scanning $suite_count contract suites"

# ---------------------------------------------------------------------------
section "no guard is a subshell on the left of \`||\`"

while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(detect_subshell_guard < "$f")"
    if [ -n "$hits" ]; then
        bad "$f guards a subshell with \`|| …\`, which cannot fire" \
            "set -e is suppressed in the left operand of ||; check the RESULT afterward instead: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done <<< "$suites"
[ "$fail" -eq 0 ] && ok "no inert subshell guards"

# ---------------------------------------------------------------------------
section "no awk paragraph reader matches its anchor against the wrapped record"

before_fail="$fail"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(detect_wrapped_anchor_match < "$f")"
    if [ -n "$hits" ]; then
        bad "$f uses RS=\"\" but matches with index(\$0, …)" \
            "unwrap into a variable first and match that, or a wrap inside the anchor false-reds: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done <<< "$suites"
[ "$fail" -eq "$before_fail" ] && ok "every paragraph reader matches an unwrapped record"

# ---------------------------------------------------------------------------
section "the detectors still detect (self-test)"

# A floor would say "we looked at N files." It would not say the regexes still
# match anything, and a detector whose healthy state is zero hits is exactly the
# one that rots silently. Each detector is run against a fixture it MUST flag and
# a corrected fixture it MUST NOT.

bad_subshell='#!/usr/bin/env bash
(
    cd /tmp
    false
) || fatal "cannot fire"'
good_subshell='#!/usr/bin/env bash
(
    cd /tmp
    false
)
[ -f /tmp/marker ] || fatal "this one can fire"'

if [ -n "$(printf '%s' "$bad_subshell" | detect_subshell_guard)" ]; then
    ok "detector A flags a subshell guarded by \`||\`"
else
    fatal "detector A no longer matches the shape it is named for — the regex rotted, and its section above now passes everything."
fi
if [ -z "$(printf '%s' "$good_subshell" | detect_subshell_guard)" ]; then
    ok "detector A leaves a result-checked subshell alone"
else
    fatal "detector A flags the CORRECTED form, so the fix it prescribes does not clear it."
fi

# shellcheck disable=SC2016  # fixtures are literal awk/shell source, not expansions
bad_awk='awk -v anchor="$2" '"'"'
    BEGIN { RS = "" }
    index($0, anchor) { gsub(/\n/, " "); print; exit }
'"'"' "$1"'
# shellcheck disable=SC2016  # fixtures are literal awk/shell source, not expansions
good_awk='awk -v anchor="$2" '"'"'
    BEGIN { RS = "" }
    { rec = $0; gsub(/\n/, " ", rec) }
    index(rec, anchor) { print rec; exit }
'"'"' "$1"'

if [ -n "$(printf '%s' "$bad_awk" | detect_wrapped_anchor_match)" ]; then
    ok "detector B flags a paragraph reader matching \$0"
else
    fatal "detector B no longer matches the shape it is named for."
fi
if [ -z "$(printf '%s' "$good_awk" | detect_wrapped_anchor_match)" ]; then
    ok "detector B leaves the unwrap-then-match form alone"
else
    fatal "detector B flags the CORRECTED form, so the fix it prescribes does not clear it."
fi

# The comment exclusion is load-bearing: this file's own header quotes both
# shapes, and so does the fix in test-compound-clustering-single-source.sh.
# Without it the detectors would flag the prose explaining them.
# shellcheck disable=SC2016  # literal fixture text
commented='# ) || fatal "this is prose about the defect"
#     index($0, anchor) { … }
BEGIN { RS = "" }'
if [ -z "$(printf '%s' "$commented" | detect_subshell_guard)" ] \
   && [ -z "$(printf '%s' "$commented" | detect_wrapped_anchor_match)" ]; then
    ok "both detectors ignore commented-out prose about the shapes"
else
    fatal "a detector flags a comment — every suite that documents this defect class, including this one, would go red for explaining it."
fi

# Pin the exclusion itself. It is load-bearing (see the scan list above), and an
# exclusion that silently stopped matching would put this file back in the scan
# where its own fixtures would redden it — a false red on a suite that is
# working, which is how a suite gets deleted rather than fixed.
printf '%s\n' "$suites" | grep -qx -- "$self" \
    && fatal "$self is in its own scan list; its fixture strings will flag as real defects."
ok "this suite is excluded from its own scan, and the exclusion still matches"

# ---------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
