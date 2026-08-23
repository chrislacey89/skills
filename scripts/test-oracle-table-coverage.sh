#!/usr/bin/env bash
# test-oracle-table-coverage.sh — every lookup-table oracle in every contract
# suite must self-check its WHOLE table, not a sample of it.
#
# THE DRIFT CLASS. A contract suite that decides an assertion by consulting a
# fixed lookup table holds, in that table, the only value it does not read out
# of the subject under test. That makes the table the single thing capable of
# disagreeing with the subject — and therefore the single thing whose integrity
# the suite has to establish before trusting any assertion built on it. The
# established remedy is a self-check: run the table against literals and abort
# if it answers wrong.
#
# The defect this suite pins is one step past that remedy. A self-check that
# enumerates SOME of the table's labels reads exactly like one that enumerates
# all of them, and the comment above it will usually claim the full property.
# Every label it skips stays laundering-capable: rewrite that arm to return a
# value derived from the subject and the assertion consulting it can no longer
# disagree with the thing it measures. The mutation dies silently, and the
# suite reports full green.
#
# THE INCIDENT (PR #267, 2026-08-22). `test-q4-mechanism-names.sh` shipped a
# `word_to_int` table of nine labels self-checked against four of them. Review
# rewrote one of the five untested arms as `$p4_count` and a genuine
# 10-passed/1-failed drift became **11 passed, 0 failed**. The comment directly
# above the loop asserted the property the loop did not have: *"Up here there
# is no parsed count in scope for it to launder."* True for the four labels the
# loop exercised; false for the other five.
#
# WHY THIS IS NOT ALREADY COVERED. `mutate-the-oracle-not-only-the-subject-2026-08-19`
# requires a mutation battery to mutate the oracle and not only the subject.
# That rule was followed in #267 — the oracle WAS mutated, twice, and both
# mutations were caught. They landed on covered labels. A battery samples; a
# partial self-check leaves a region where sampling is what decides whether the
# hole is found. This suite removes the sampling by requiring the coverage to
# be total, which is the one form of that check a machine can settle.
#
# WHAT IT PINS, all extracted from the real files rather than restated here:
#   1. Every `case "$1" in` lookup function in every `scripts/test-*.sh` has a
#      self-check that calls it with literal expectations.
#   2. That self-check enumerates EVERY non-default label in the table.
#   3. The scan found both files AND tables, so an empty result can never pass
#      vacuously — a floor on the table count turns a broken detector into a
#      FATAL rather than a green run. The first draft lacked this and reported
#      full green when its own detection regex was mutated.
#   4. A suite that iterates a HAND-LISTED POPULATION OF SUBJECT FILES declares
#      how that population was obtained. See the second section below.
#
# THE SECOND SHAPE, and why it is here rather than in a new file. This suite's
# parent entry (docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md)
# closes with: "scripts/test-oracle-table-coverage.sh is bash-and-`case`-specific
# and *will* need extending if a suite adds a lookup table in another shape; that
# is a gap in the mechanism, not in the lesson." That prediction came true on the
# very next suite added to this repo. scripts/test-widened-domain-tell.sh (#268)
# held its enumerable set as `citers="$refac $skill"` — two files named in one
# string — and appending a THIRD citing file carrying a stale heading passed
# 17/17. Same class as a partial `case` table: a guard whose own coverage is a
# hand-maintained subset of the thing it guards. Different syntax, so the
# `case`-shaped detector above was silent throughout.
#
# The fix in that suite was to DERIVE the set (the parent entry's Prevention #2).
# The check below does not require deriving — sometimes you cannot, and the
# parent entry's Rule Scope allows enumeration provided the sampling is
# *declared* rather than implied by the absence of a statement. So it requires
# the declaration, which is the one part a machine can settle.
#
# Deliberately NOT pinned: whether the self-check's expected values are
# *correct*. The suite that owns the table asserts that itself, and asserting
# it twice would put the same claim in two places — the shape this whole family
# of suites exists to abolish. Coverage is the property that is checkable from
# outside; correctness is not.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

self="scripts/test-oracle-table-coverage.sh"

# Lowest number of lookup-table oracles the repo is known to contain. Its only
# job is to make a detector regression loud; see the check at the bottom.
MIN_TABLES=2

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# Every contract suite except this one. This file is excluded because its own
# body quotes the syntax it scans for, and a scanner that matches itself
# reports a function that does not exist.
suites() {
    for f in scripts/test-*.sh; do
        [ "$f" = "$self" ] && continue
        printf '%s\n' "$f"
    done
}

# Names of functions in $1 whose body opens a `case "$1" in` lookup.
lookup_fns() {
    awk '
        /^[a-z_][a-z0-9_]*\(\) \{/ { fn = $1; sub(/\(\).*/, "", fn); depth = 1; body = ""; next }
        fn != "" {
            body = body "\n" $0
            if ($0 ~ /^\}/) {
                if (body ~ /case "\$1" in/) print fn
                fn = ""
            }
        }
    ' "$1" || true
}

# Non-default labels of the `case` inside function $2 of file $1.
table_labels() {
    awk -v want="$2" '
        /^[a-z_][a-z0-9_]*\(\) \{/ { fn = $1; sub(/\(\).*/, "", fn); body = ""; next }
        fn != "" {
            body = body "\n" $0
            if ($0 ~ /^\}/) { if (fn == want) print body; fn = "" }
        }
    ' "$1" \
        | grep -oE '(^|[[:space:]])[a-zA-Z][a-zA-Z0-9_-]*\)' \
        | tr -d ' )' \
        | sort -u || true
}

# Literal keys a `for … in a:1 b:2; do` self-check loop passes to function $2.
# The call is matched as `<fn><space>` — a bare shell invocation, not `fn(` —
# because getting this wrong makes the function look un-self-checked and the
# suite reports a false red on a table that is fully covered. Every stage is
# `|| true`-guarded: a no-match grep exits 1, which under `set -e` would abort
# the whole scan mid-file and print a truncated report that reads like a crash
# rather than a finding.
selfcheck_keys() {
    awk -v want="$2" '
        /^[[:space:]]*for [a-z_]+ in / { loop = $0; next }
        loop != "" && index($0, want " ") > 0 { print loop; loop = "" }
        /^[[:space:]]*done/ { loop = "" }
    ' "$1" 2>/dev/null \
        | sed -E 's/^[[:space:]]*for [a-z_]+ in //; s/; do$//' \
        | tr ' ' '\n' \
        | sed 's/:.*$//' \
        | grep -vE '^[[:space:]]*$' \
        | sort -u || true
}

# -----------------------------------------------------------------------------
section "the scan is real (guards every assertion below)"

suite_count="$(suites | wc -l | tr -d ' ')"
[ "$suite_count" -ge 5 ] || fatal "scan found only $suite_count contract suites — the glob or the layout changed; an empty scan makes every check below pass vacuously."
ok "scanning $suite_count contract suites"

# -----------------------------------------------------------------------------
section "every lookup-table oracle self-checks its whole table"

tables_found=0

while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    while IFS= read -r fn; do
        [ -n "$fn" ] || continue
        tables_found=$((tables_found + 1))

        labels="$(table_labels "$suite" "$fn")"
        if [ -z "$labels" ]; then
            bad "$(basename "$suite"): $fn() opens a case but no labels parsed" \
                "the table's syntax changed; update this suite rather than leaving it silently green"
            continue
        fi

        keys="$(selfcheck_keys "$suite" "$fn")"
        if [ -z "$keys" ]; then
            bad "$(basename "$suite"): $fn() is a lookup table with no self-check" \
                "the table is the only value not read from the subject; nothing establishes it answers correctly"
            continue
        fi

        missing="$(comm -23 <(printf '%s\n' "$labels") <(printf '%s\n' "$keys") | tr '\n' ' ' | sed 's/ *$//')"
        if [ -z "$missing" ]; then
            ok "$(basename "$suite"): $fn() self-checks all $(printf '%s\n' "$labels" | wc -l | tr -d ' ') labels"
        else
            bad "$(basename "$suite"): $fn() self-checks only part of its table" \
                "unchecked labels: $missing — each one can be rewritten to launder a value from the subject and the mutation dies silently"
        fi
    done <<< "$(lookup_fns "$suite")"
done <<< "$(suites)"

# A floor, not a tolerance — and this branch is the suite's own defect, caught
# by the oracle half of its mutation battery. The first draft treated "found
# zero tables" as a legitimate pass, on the reasoning that a repo need not have
# any. True in the abstract, and vacuous here: breaking the case-detection regex
# made the scan find nothing and the suite reported FULL GREEN, which is exactly
# the class it exists to abolish, reproduced inside it. The repo has tables; a
# scan that finds none is a scanner regression, not an empty repo. Raise the
# floor deliberately if the real count ever drops.
if [ "$tables_found" -lt "$MIN_TABLES" ]; then
    fatal "scan found $tables_found lookup-table oracle(s), expected at least $MIN_TABLES.
       The detector is broken, not the repo — a scan that finds nothing passes every
       check below vacuously. If lookup tables were genuinely removed, lower MIN_TABLES
       in this file as a deliberate edit."
fi
ok "checked $tables_found lookup-table oracle(s) (floor: $MIN_TABLES)"

# -----------------------------------------------------------------------------
section "every hand-listed population of subject files is declared"

# THE DETECTOR. A suite iterating a population of subject FILES, written out by
# hand. Two syntaxes, both seen in this repo:
#     citers="$refac $skill"          -- a list of path-holding variables
#     for f in a/X.md b/Y.md; do      -- literal paths in the loop header
# One name is a subject, not a population (`compound_skill="compound/SKILL.md"`
# is how every suite here opens and is not the defect). Two or more is a claim
# about how many there are, and that claim is what goes stale.
#
# THE ESCAPE, and it is deliberately one that must be written down. A suite may
# enumerate rather than derive; it may not do so silently. `coverage:` on any
# line satisfies this — one sentence saying the set is derived, or that it is
# enumerated and why that is the honest ceiling here. An escape a reader can
# argue with beats one taken in silence, which is the shape this family exists
# to close.
hand_listed() {  # $1 = suite; prints each hand-listed population found
    grep -nE '^[[:space:]]*[a-z_]+="(\$[a-z_]+[[:space:]]+){1,}\$[a-z_]+"[[:space:]]*$' "$1" || true
    grep -nE '^[[:space:]]*for [a-z_]+ in ([^;]*[a-z0-9_-]+/[a-z0-9_.-]+\.(md|sh|yml)[^;]*){1}[^;]*[[:space:]]+[^;]*\.(md|sh|yml)' "$1" || true
}

populations=0
undeclared=0

while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    found="$(hand_listed "$suite")"
    [ -n "$found" ] || continue
    populations=$((populations + 1))
    if grep -q 'coverage:' "$suite"; then
        ok "$(basename "$suite"): hand-listed population, and it declares its coverage"
    else
        undeclared=$((undeclared + 1))
        bad "$(basename "$suite"): iterates a hand-listed population of subject files and never says so" \
            "the set and the thing it stands for are written in two places and agree only because someone made them agree; derive the set, or add a one-line 'coverage:' note saying why enumeration is the ceiling here — $(printf '%s' "$found" | head -1)"
    fi
done <<< "$(suites)"

# NO FLOOR HERE, and that is a real difference from the table check above. A
# repo can legitimately contain zero hand-listed populations — this one does,
# now that #268's suite derives its set — so "found none" is the healthy state
# rather than a detector regression, and flooring it would redden a clean repo.
#
# That leaves this detector able to rot silently, which the table check's floor
# exists to prevent. It is a disclosed asymmetry, not an oversight: the honest
# guard is the self-test below, which plants the shape and requires the detector
# to find it. A floor asserts the repo still has the defect; a self-test asserts
# the detector still sees it. The second is what is actually wanted.
if [ "$populations" -eq 0 ]; then
    ok "no hand-listed populations of subject files (detector self-tested below)"
else
    ok "checked $populations hand-listed population(s), $undeclared undeclared"
fi

# -----------------------------------------------------------------------------
section "the population detector still detects (self-test)"

# Without this, the section above is one broken regex away from a permanent
# silent pass -- and unlike the table check it has no floor to catch that. Plant
# the exact shape from #268's pre-fix suite and require a hit.
probe="$(mktemp)"
cat > "$probe" <<'PROBE'
#!/usr/bin/env bash
refac="tdd/refactoring.md"
skill="tdd/SKILL.md"
citers="$refac $skill"
for f in $citers; do
    echo "$f"
done
PROBE
if [ -n "$(hand_listed "$probe")" ]; then
    ok "the detector finds a planted hand-listed population"
else
    bad "the detector no longer finds the shape it was written for" \
        "the section above is passing vacuously; every suite could hand-list a population and none would be reported"
fi
# And the inverse, so the detector is not simply matching everything: a single
# named subject is the normal opening of every suite here and must NOT trip it.
cat > "$probe" <<'PROBE'
#!/usr/bin/env bash
compound_skill="compound/SKILL.md"
for label in Discipline Candidates; do
    echo "$label"
done
PROBE
if [ -z "$(hand_listed "$probe")" ]; then
    ok "the detector ignores a single named subject and a non-file loop"
else
    bad "the detector fires on a single named subject" \
        "every suite in this repo opens that way; a detector that reddens all of them gets deleted"
fi
rm -f "$probe"

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
