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
    # NAMED FOR SUBJECT FILES, SO IT MATCHES SUBJECT FILES. An earlier revision
    # matched any `for` over two-or-more quoted variables, regardless of what
    # they held. Its three hits in this repo were: one real file population, one
    # loop over extracted *git command strings*, and one over *HTML comment
    # templates*. Two false positives out of three, in a section titled "every
    # hand-listed population of subject FILES" — and the response at the time
    # was to annotate around them, which this suite's own miss() message warns
    # is how you get "a 'coverage:' comment that is a lie."
    #
    # The variable-list arms now require the variable NAMES to look like they
    # hold paths (file/path/doc/skill/md/sh/yml/checklist/iface/refac/suite/
    # template is deliberately excluded). That is a heuristic on naming rather
    # than on values — bash cannot see values statically — so it is the honest
    # ceiling, and it is stated rather than implied. Literal-path arms need no
    # such guess: a `/` and a known extension are visible in the source text.
    local pathish='(file|path|doc|docs|skill|skills|md|sh|yml|iface|refac|checklist|suite|entry|target|src|source)'
    { # a="$x $y"  — list of path-named variables
      grep -nEi "^[[:space:]]*[a-z_]*${pathish}[a-z_]*=\"(\\\$[a-z_]*${pathish}[a-z_]*[[:space:]]+){1,}\\\$[a-z_]*${pathish}[a-z_]*\"[[:space:]]*$" "$1" || true
      # a="tdd/x.md tdd/y.md"  — list of literal paths (the literal twin of the
      # incident's own shape, which the first revision missed entirely)
      grep -nEi "^[[:space:]]*[a-z_]+=\"([a-z0-9_.-]+/[a-z0-9_.-]+\\.(md|sh|yml)[[:space:]]+){1,}[a-z0-9_.-]+/[a-z0-9_.-]+\\.(md|sh|yml)\"" "$1" || true
      # for f in "$a" "$b"  — path-named variables in a loop header
      grep -nEi "^[[:space:]]*for [a-z_]+ in (\"?\\\$\\{?[a-z_]*${pathish}[a-z_]*\\}?\"?[[:space:]]+){1,}\"?\\\$\\{?[a-z_]*${pathish}[a-z_]*\\}?\"?;?[[:space:]]*do" "$1" || true
      # for f in a/X.md b/Y.md  — literal paths in a loop header, any case
      grep -nEi "^[[:space:]]*for [a-z_]+ in (\"?[a-z0-9_.-]+/[a-z0-9_.-]+\\.(md|sh|yml)\"?[[:space:]]+){1,}\"?[a-z0-9_.-]+/[a-z0-9_.-]+\\.(md|sh|yml)\"?;?[[:space:]]*do" "$1" || true
    } | sort -t: -k1,1n -u
}


# -----------------------------------------------------------------------------
# THE ESCAPE PREDICATE, extracted so there is exactly ONE implementation.
# A `coverage:` declaration excuses a population only if it sits within
# DECL_WINDOW lines above it — that proximity is what ties the declaration to the
# thing it declares, instead of letting them merely coexist in one file.
#
# It is a function rather than an inline expression because the first version was
# inline and its probe RESTATED it: the probe ran a verbatim copy of the same
# `sed | grep` against a synthetic fixture, so it certified its own copy. Neuter
# the real check and the copy stayed green — 18/0, verified. That is the third
# instance on this branch of a guard whose self-check duplicates its subject
# instead of calling it, and duplication is the defect, not the pattern used.
# One implementation; the check calls it, both probes call it.
DECL_WINDOW=6
declared_within_window() {  # $1 = file, $2 = line number of the population
    local start
    start=$(( $2 > DECL_WINDOW ? $2 - DECL_WINDOW : 1 ))
    sed -n "${start},${2}p" "$1" | grep -q 'coverage:'
}

populations=0
undeclared=0

# PER POPULATION, NOT PER FILE. The first revision asked whether the token
# `coverage:` appeared anywhere in the suite, so one declaration permanently
# exempted the whole file: adding a second, entirely undeclared population to an
# already-declared suite passed 15/0 — verified. The header states the rule per
# population, so the check has to be per population. A declaration must sit
# within DECL_WINDOW lines above the population it excuses, which is what ties
# the two together instead of letting them merely coexist. The constant is
# declared once, above declared_within_window() — a second assignment here
# shadowed it and made the ceiling check below unfalsifiable, which is the
# restated-constant defect one more time.

while IFS= read -r suite; do
    [ -n "$suite" ] || continue
    found="$(hand_listed "$suite")"
    [ -n "$found" ] || continue
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        populations=$((populations + 1))
        lineno="${hit%%:*}"
        if declared_within_window "$suite" "$lineno"; then
            ok "$(basename "$suite"):${lineno}: hand-listed population, declared"
        else
            undeclared=$((undeclared + 1))
            bad "$(basename "$suite"):${lineno}: iterates a hand-listed population of subject files and never says so" \
                "the set and the thing it stands for are written in two places and agree only because someone made them agree; derive the set, or add a one-line 'coverage:' note directly above it — ${hit#*:}"
        fi
    done <<EOF
$found
EOF
done <<< "$(suites)"

section "the population detector still detects (self-test)"

# C4 FIX. Without this the section above is one broken regex from a permanent
# silent pass -- and unlike the table check it has no floor to catch that. The
# first draft planted ONE of the shapes the detector claims: breaking the second
# regex alone left the suite at 7/0, verified. A self-check over an enumerable
# set must enumerate all of it (partial-oracle-selfcheck-2026-08-22, Prevention
# #1) -- so every form the detector advertises gets a probe, and every near-miss
# that must stay silent gets one too.
probe="$(mktemp)"

plant() {  # $1 = label, $2 = body that MUST be detected
    printf '%s\n' "$2" > "$probe"
    if [ -n "$(hand_listed "$probe")" ]; then
        ok "detector finds: $1"
    else
        bad "detector no longer finds: $1" \
            "the section above is passing vacuously for this form; a suite could hand-list it and go unreported"
    fi
}

miss() {  # $1 = label, $2 = body that MUST NOT be detected
    printf '%s\n' "$2" > "$probe"
    if [ -z "$(hand_listed "$probe")" ]; then
        ok "detector ignores: $1"
    else
        bad "detector fires on: $1" \
            "a false positive here pushes an author toward a 'coverage:' comment that is a lie"
    fi
}

# shellcheck disable=SC2016  # the probes are literal source text; expansion would defeat them
plant "path-named variables in an assignment"   'skill_files="$iface_doc $skill_doc"'
# shellcheck disable=SC2016
plant "literal paths in an assignment"          'citers="tdd/refactoring.md tdd/SKILL.md"'
# shellcheck disable=SC2016
plant "path-named variables in a loop header"   'for f in "$iface_file" "$checklist_file"; do'
plant "literal paths in a loop header"          'for f in tdd/SKILL.md tdd/tests.md; do'
plant "quoted literal paths"                    'for f in "a/x.md" "b/y.md"; do'
miss  "a single named subject"                  'compound_skill="compound/SKILL.md"'
miss  "a loop over non-file labels"             'for label in Discipline Candidates; do'
# shellcheck disable=SC2016
miss  "a loop over one variable"                'for f in "$only_file"; do'
# The two false positives an earlier revision produced in this repo. Both are
# real loops in real suites over values that are not files; pinning them as
# required non-matches is what keeps the section's title true.
# shellcheck disable=SC2016
miss  "a loop over extracted command strings"   'for extracted in "$bisect_start" "$bisect_run"; do'
# shellcheck disable=SC2016
miss  "a loop over comment templates"           'for template in "$pass_template" "$judge_template"; do'
# shellcheck disable=SC2016
miss  "ordinary string concatenation"           'msg="$greeting $name"'

rm -f "$probe"

# The escape check itself had no probe. Replacing it with `if true` left the
# suite at 15/0, because every population in this tree is declared and the
# failure branch is therefore unreachable — an assertion that cannot fail is not
# an assertion. Plant both states.
esc_probe="$(mktemp)"

probe_escape() {  # $1 = label, $2 = fixture body, $3 = expected (declared|undeclared)
    printf '%s' "$2" > "$esc_probe"
    local hit ln
    hit="$(hand_listed "$esc_probe" | head -1)"; ln="${hit%%:*}"
    if [ -z "$ln" ]; then
        bad "escape probe fixture was not detected at all: $1" \
            "the fixture no longer trips hand_listed(), so this probe proves nothing"
        return
    fi
    if declared_within_window "$esc_probe" "$ln"; then
        if [ "$3" = "declared" ]; then
            ok "escape check: $1"
        else
            bad "escape check: $1 — an UNdeclared population read as declared" "the coverage: gate is not gating"
        fi
    else
        if [ "$3" = "undeclared" ]; then
            ok "escape check: $1"
        else
            bad "escape check: $1 — a DECLARED population was not excused" "the window is too narrow; correct suites would redden"
        fi
    fi
}

probe_escape "an undeclared population is not excused" \
    'for f in tdd/a.md tdd/b.md; do :; done
' undeclared
probe_escape "a declared population is excused" \
    '# coverage: enumerated — probe
for f in tdd/a.md tdd/b.md; do :; done
' declared
# DERIVED FROM THE CONSTANT, not calibrated to its current value. The first
# version hardcoded a run of filler lines sized for a window of 6, so the
# fixture's distance was fixed while the window was not: widening the constant
# made the "too far" fixture no longer too far, and the probe went on reporting
# ok while asserting the opposite of its own name — verified at 19/0.
too_far_fixture() {  # DECL_WINDOW + 1 filler lines: always just outside the window
    printf '# coverage: enumerated — probe\n'
    local i=0
    while [ "$i" -le "$DECL_WINDOW" ]; do printf '#\n'; i=$((i + 1)); done
    printf 'for f in tdd/a.md tdd/b.md; do :; done\n'
}
probe_escape "a declaration DECL_WINDOW+1 lines above does not reach" \
    "$(too_far_fixture)
" undeclared
# AND A BOUND ON THE CONSTANT ITSELF, which the derived probe above cannot give.
# That probe sizes its fixture from DECL_WINDOW, so it is correct at the boundary
# for ANY value — and therefore blind to the value being wrong. A window of 9999
# means a `coverage:` note anywhere above in the file excuses any population
# below it, which is exactly the per-file behavior the per-population gate was
# written to remove: the constant would silently revert the fix with every probe
# still green.
#
# The bound is asserted on the value, not through a fixture. A fixture-based
# version was tried first and is the wrong instrument — it must encode a
# distance, and any distance is either derived from the constant (blind) or
# hardcoded (drifts). The property is numeric, so assert the number. Tuning 6 to
# 8 stays legal; tuning it to 9999 does not.
DECL_WINDOW_CEILING=40
if [ "$DECL_WINDOW" -le "$DECL_WINDOW_CEILING" ]; then
    ok "DECL_WINDOW is $DECL_WINDOW, within the ceiling of $DECL_WINDOW_CEILING"
else
    bad "DECL_WINDOW is $DECL_WINDOW, above the ceiling of $DECL_WINDOW_CEILING" \
        "a window this wide lets a coverage: note anywhere above excuse any population below it — the per-file behavior the per-population gate removed, restored by a constant"
fi

rm -f "$esc_probe"

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
