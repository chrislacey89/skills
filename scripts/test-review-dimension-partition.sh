#!/usr/bin/env bash
# test-review-dimension-partition.sh — contract test for /pre-merge's
# review-dimension partition.
#
# THE DRIFT CLASS: a hand-maintained restatement of the thing that defines it.
# `pre-merge/review-checklist.md` is the canon — one `## N. Title` heading per
# review dimension, each carrying a `**Runs in:**` marker naming its owner.
# `pre-merge/SKILL.md` used to restate that roster as two hand-written bullets;
# the restatement drifted from the canon at birth (ae362eb added Coverage
# Matrix Reconciliation to the canon and never touched SKILL.md), so on any
# diff large enough to split, the one dimension whose Concern names a withheld
# merge silently never ran — while the loop-mode ledger attested that every
# dimension had. Reported from a real PR review (#291).
#
# WHAT THIS SUITE CLAIMS, AND — DELIBERATELY — WHAT IT DOES NOT.
#
# Two earlier versions of this file also asserted SEMANTIC properties of the
# prose: "Phase 4 runs the controller-owned dimensions," "SKILL.md derives the
# split." Both shipped, and both were defeated in one review pass each,
# because a substring assertion cannot decide what a reader does with a
# sentence: prose that names the right marker while instructing the OPPOSITE
# ("skip every dimension whose marker reads…") satisfied every grep. Each
# hardening round reproduced the ticket's own defect class one level up — the
# assertions were themselves a hand-maintained restatement of what the prose
# means. That is the boundary #284 recorded: a contract test reconciles a
# writer and a reader across a machine-readable seam; a claim about how prose
# reads has one machine-readable surface and is not testable here.
#
# So this suite holds exactly two kinds of claim, and the third lives
# elsewhere:
#
#   1. WELL-FORMEDNESS of the canon's marker vocabulary (schema validation
#      over structured data): every dimension carries exactly one owner, the
#      three buckets partition the roster, the incident's dimension stays
#      controller-owned.
#   2. SYNTACTIC DETECTORS for roster restatements repo-wide: a literal
#      dimension count, a paragraph listing 4+ canon titles, a numeric roster
#      list. Detectors, not proofs — each carries a planted self-test (a
#      positive that must hit and a near-miss that must stay silent), because
#      a detector whose healthy state is zero hits needs a self-test, not a
#      floor (mechanism-generality-lags-the-pattern-2026-08-23 § Prevention).
#   3. NOT HERE: whether SKILL.md's Phase 3/4 prose actually instructs a
#      reader to derive the split and run the controller-owned dimensions.
#      That property's only competent oracle is a reader. It is held by
#      review — hand a fresh-context agent the two files and ask it to
#      produce the split — not by this script. On this ticket's branch that
#      reader-check caught every semantic defect and these greps caught none.
#
# CENSUS SCOPE, learned the hard way: v1 scanned three named files for
# `11|eleven` and missed "10 dimensions" one directory away; v2 scanned
# `pre-merge/*.md` and missed "seven structural dimensions" one directory the
# other way, plus a full roster in a .js file. The tell is recorded in
# docs/restated-claims.md: a census scoped by where the known sites live
# cannot find the site that lives elsewhere. The population is now ALL tracked
# files, minus a short explicit allowlist (dated history, generated copies,
# this file's own fixtures) — and the population check pins that the two
# historically-missed files are in it.
#
# PORTABILITY: re-execs under /bin/bash when available, so on macOS every run
# — CI, lefthook, manual — exercises bash 3.2, the strictest shell this file
# must survive. No bash-4 builtins.
#
# Lineage: docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md,
# docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md,
# docs/restated-claims.md, #284, #291. Gilb & Graham, Software Inspection,
# Ch. 11: "it was silly to rewrite a rule into a checklist question."

# Re-exec under /bin/bash so the strictest available shell is the one that
# runs. PATH bash here is 5.x (Homebrew/Linux); /bin/bash on macOS is 3.2.
if [ -z "${PARTITION_SUITE_REEXEC:-}" ] && [ -x /bin/bash ]; then
    PARTITION_SUITE_REEXEC=1 exec /bin/bash "$0" "$@"
fi

set -euo pipefail
export LC_ALL=C   # binary-safe scans; BSD awk multibyte conversion warnings otherwise

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
checklist="$repo_root/pre-merge/review-checklist.md"
manifest="$repo_root/scripts/skill-references.manifest"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

fatal() {
    printf '\nFATAL: %s\n' "$1" >&2
    exit 2
}

assert_eq() {
    expected="$1"; actual="$2"; label="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %s\n       got:      %s\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

assert_true() {
    cond="$1"; label="$2"
    if [ "$cond" = "true" ]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n' "$label"
        fail=$((fail + 1))
    fi
}

[ -f "$checklist" ] || fatal "canon not found: $checklist"
[ -f "$manifest" ] || fatal "manifest not found: $manifest"

# ============================================================================
# Part 1 — well-formedness of the canon's marker vocabulary
# ============================================================================

roster="$(grep -oE '^## [0-9]+\. ' "$checklist" | grep -oE '[0-9]+' || true)"
roster_count="$(printf '%s\n' "$roster" | grep -c '[0-9]' || true)"

# Empty-scan floor: a heading-format change must FATAL, not pass vacuously.
if [ "$roster_count" -lt 5 ]; then
    fatal "roster scan found $roster_count dimension heading(s) in $checklist; expected at least 5. The '^## N. ' heading format changed, or the scan is broken. Refusing to report a vacuous pass."
fi

# Walk the canon linearly, attributing each marker to the heading above it.
# (bash-3.2: no associative arrays — newline-delimited "N<TAB>bucket" records.)
owners=""
marker_counts=""
current=""
stray_markers=0

while IFS= read -r line; do
    case "$line" in
        '## '[0-9]*'. '*)
            current="$(printf '%s' "$line" | sed -E 's/^## ([0-9]+)\..*/\1/')"
            continue
            ;;
        '**Runs in:** sub-agent A'*) bucket="sub-agent A" ;;
        '**Runs in:** sub-agent B'*) bucket="sub-agent B" ;;
        '**Runs in:** the controller'*) bucket="the controller" ;;
        *) continue ;;
    esac
    if [ -z "$current" ]; then
        stray_markers=$((stray_markers + 1))
        continue
    fi
    owners="$owners$current	$bucket
"
    marker_counts="$marker_counts$current
"
done < "$checklist"

owner_of() {
    printf '%s' "$owners" | awk -F'\t' -v n="$1" '$1 == n { print $2 }' | tail -1
}

section "Every dimension declares exactly one owner"

assert_eq "0" "$stray_markers" "no '**Runs in:**' marker sits outside a numbered dimension section"

unique_count="$(printf '%s\n' "$roster" | grep '[0-9]' | sort -u | grep -c '[0-9]' || true)"
assert_eq "$roster_count" "$unique_count" "no two dimensions share a heading number"

missing=""
duplicated=""
for n in $roster; do
    c="$(printf '%s' "$marker_counts" | grep -cx "$n" || true)"
    case "$c" in
        0) missing="$missing $n" ;;
        1) ;;
        *) duplicated="$duplicated $n" ;;
    esac
done

assert_eq "" "${missing# }" "no dimension is missing a '**Runs in:**' marker (this is what ae362eb would have failed)"
assert_eq "" "${duplicated# }" "no dimension declares two owners"

section "Three-bucket total partition over the roster"

count_a=0; count_b=0; count_c=0
for n in $roster; do
    case "$(owner_of "$n")" in
        "sub-agent A")    count_a=$((count_a + 1)) ;;
        "sub-agent B")    count_b=$((count_b + 1)) ;;
        "the controller") count_c=$((count_c + 1)) ;;
    esac
done

partitioned=$((count_a + count_b + count_c))
assert_eq "$roster_count" "$partitioned" "{A} ∪ {B} ∪ {controller} covers the roster exactly ($roster_count dimensions)"
assert_true "$([ "$count_a" -gt 0 ] && echo true || echo false)" "sub-agent A's bucket is non-empty (has $count_a)"
assert_true "$([ "$count_b" -gt 0 ] && echo true || echo false)" "sub-agent B's bucket is non-empty (has $count_b)"
assert_true "$([ "$count_c" -gt 0 ] && echo true || echo false)" "the controller's bucket is non-empty (has $count_c)"

section "The incident's dimension is controller-owned"

# Found by title, not number, so renumbering cannot silently retarget the pin.
coverage_n="$(grep -oE '^## [0-9]+\. Coverage Matrix Reconciliation' "$checklist" | grep -oE '[0-9]+' || true)"
assert_true "$([ -n "$coverage_n" ] && echo true || echo false)" "Coverage Matrix Reconciliation is still in the canon"
if [ -n "$coverage_n" ]; then
    got="$(owner_of "$coverage_n")"
    assert_eq "the controller" "${got:-<none>}" "Dimension $coverage_n (Coverage Matrix Reconciliation) is controller-owned"
fi

# ============================================================================
# Part 2 — syntactic roster-restatement detectors, repo-wide
# ============================================================================
#
# Each detector is a function reading stdin, so the planted self-tests below
# exercise the identical code path the corpus scan uses.

# Detector 1: a literal dimension count, in a paragraph that is about the
# review. The context filter exists because the repo legitimately counts other
# things ("Zeller's six dimensions of uncontrolled input" in /triage-issue) —
# a bare count-near-"dimensions" match is not a roster claim; one inside a
# paragraph naming the review machinery is.
count_context='pre-merge|review-checklist|architectural review|review dimensions'
count_pattern='\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+)([- ][a-z]+){0,2}[- ]dimensions\b|\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+)-dimension\b'

detect_count_literals() {
    # stdin: file content. stdout: one line per offending paragraph.
    awk 'BEGIN { RS=""; ORS="\n" } { gsub(/\n/, " "); print }' \
        | grep -iE "$count_context" \
        | grep -iE "$count_pattern" || true
}

# Detector 2: a paragraph listing 4 or more canon dimension titles —
# a hand-written roster in any markup. Case-insensitive; a bullet list with
# no blank lines between items is one paragraph, so one-title-per-line
# restatements are caught too. Threshold 4: the retired restatement carried 5
# per line, any hand split of this roster puts ≥4 in some bucket, and the
# busiest legitimate contrast sentence in the corpus carries 3.
titles_tsv="$(grep -oE '^## [0-9]+\. [^(]+' "$checklist" | sed -E 's/^## [0-9]+\. //; s/ +$//' | tr '\n' '\t')"

detect_title_rosters() {
    awk -v titles="$titles_tsv" '
        BEGIN { RS=""; n = split(titles, T, "\t") }
        {
            rec = tolower($0); gsub(/\n/, " ", rec); hits = 0
            for (i = 1; i <= n; i++)
                if (T[i] != "" && index(rec, tolower(T[i])) > 0) hits++
            if (hits >= 4) { printf "[%d titles] %s\n", hits, substr(rec, 1, 120) }
        }' || true
}

# Detector 3: a numeric roster list ("Dimensions 1, 2, 3, 10, 11") — the most
# natural markup for a hand-written split, invisible to the title detector.
detect_number_rosters() {
    grep -iE '\bdimensions? [0-9]+(, ?[0-9]+){2,}' || true
}

section "Detector self-tests (planted positive must hit, near-miss must stay silent)"

# Detector 1
hit="$(printf 'The architectural review in pre-merge covers all 11 dimensions of the checklist.\n' | detect_count_literals)"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "count detector: flags 'all 11 dimensions' in a review paragraph"
hit="$(printf 'The eleven-dimension architectural review from pre-merge runs next.\n' | detect_count_literals)"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "count detector: flags the spelled hyphenated form 'eleven-dimension'"
miss="$(printf 'Scan Zellers six dimensions of uncontrolled input: data, time, randomness.\n' | detect_count_literals)"
assert_eq "" "$miss" "count detector: silent on a count about something other than the review"

# Detector 2
hit="$(printf -- '- deep modules, vertical slice integrity, state discipline\n- surgical scope, review-friendly size\n' | detect_title_rosters)"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "title detector: flags a lowercase 5-title roster split across bullet lines"
miss="$(printf 'Where Boundary Map Contracts and Coverage Matrix Reconciliation check plan-vs-actual, Surgical Scope checks drift.\n' | detect_title_rosters)"
assert_eq "" "$miss" "title detector: silent on a legitimate 3-title contrast sentence"

# Detector 3
hit="$(printf 'Sub-agent A gets Dimensions 1, 2, 3, 10, 11 as before.\n' | detect_number_rosters)"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "number detector: flags 'Dimensions 1, 2, 3, 10, 11'"
miss="$(printf 'Where Dimensions 4 and 5 check plan-vs-actual between slices.\n' | detect_number_rosters)"
assert_eq "" "$miss" "number detector: silent on a two-dimension contrast"

section "Census population (set-membership pins)"

# Population: every tracked file, minus dated history (CHANGELOG,
# docs/solutions/ entries are records of past states and legitimately quote
# old counts), generated copies (manifest targets — sync-skill-references.sh
# regenerates them from canonical sources this scan already covers), and this
# file (it plants offending strings as fixtures).
targets_file="$(mktemp)"
awk '!/^#/ && NF == 2 { split($1, a, "/"); print $2 "/references/" a[length(a)] }' "$manifest" | sort -u > "$targets_file"

population_file="$(mktemp)"
git -C "$repo_root" ls-files \
    | grep -v '^CHANGELOG\.md$' \
    | grep -v '^docs/solutions/' \
    | grep -v '^scripts/test-review-dimension-partition\.sh$' \
    | grep -v -F -x -f "$targets_file" \
    > "$population_file"

pop_count="$(grep -c . "$population_file" || true)"
[ "$pop_count" -ge 50 ] || fatal "census population has $pop_count file(s); expected at least 50. git ls-files or the allowlist filtering broke. Refusing to report a vacuous pass."

# Pin the two files earlier censuses missed — one per historical miss. If an
# allowlist edit ever drops them, this fails before the scan goes blind.
assert_true "$(grep -qx 'pre-merge/references/comment-craft.md' "$population_file" && echo true || echo false)" "population contains pre-merge/references/comment-craft.md (v1's miss)"
assert_true "$(grep -qx 'vite-project/src/data/workflow-data.js' "$population_file" && echo true || echo false)" "population contains vite-project/src/data/workflow-data.js (v2's miss — not a .md file)"

section "No roster restatement survives in the census population"

count_hits=""
title_hits=""
number_hits=""
while IFS= read -r f; do
    p="$repo_root/$f"
    [ -f "$p" ] || continue
    h="$(detect_count_literals < "$p")"
    [ -n "$h" ] && count_hits="$count_hits$f: $h
"
    h="$(detect_title_rosters < "$p")"
    [ -n "$h" ] && title_hits="$title_hits$f: $h
"
    h="$(detect_number_rosters < "$p" | head -1)"
    [ -n "$h" ] && number_hits="$number_hits$f: $h
"
done < "$population_file"

rm -f "$targets_file" "$population_file"

assert_eq "" "$count_hits" "no literal review-dimension count in any of $pop_count tracked files"
assert_eq "" "$title_hits" "no paragraph lists 4+ canon dimension titles in any tracked file"
assert_eq "" "$number_hits" "no numeric roster list ('Dimensions N, N, N…') in any tracked file"

# ============================================================================
# Summary
# ============================================================================

printf '\n%d passed, %d failed  (bash %s)\n' "$pass" "$fail" "${BASH_VERSION%%(*}"
[ "$fail" -eq 0 ]
