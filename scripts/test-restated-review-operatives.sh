#!/usr/bin/env bash
# test-restated-review-operatives.sh — contract test for the operative details
# of /pre-merge's review dimensions: their gates, their numeric bands, the
# severity vocabulary they may classify into, and how other files refer to them.
#
# THE DRIFT CLASS: #291 de-duplicated the review-dimension *roster* and
# `scripts/test-review-dimension-partition.sh` pinned it. One layer in, the
# same class survived untouched — reported as #293:
#
#   1. `pre-merge/SKILL.md` restated, in unchecked prose, several dimensions'
#      gates, one dimension's three numeric bands, and one dimension's
#      procedure. Change a band in the canon and the other file ships a stale
#      operative claim. The partition suite cannot see this: it asserts that
#      markers exist, not that thresholds agree.
#   2. `pre-merge/SKILL.md` and its siblings referred to dimensions by number
#      ("Dimension 4", "Dim 8") against a roster whose own canon declares the
#      `## N.` numbering to be the roster. Inserting a dimension silently
#      retargets every one of them, and nothing guarded it.
#   3. The canon's Coverage Matrix Reconciliation section classified an
#      unmapped Must as **Blocker** and an unmapped Want as **Concern/Warning**
#      — two labels the Severity Classification section does not define, in a
#      skill whose own header says findings are advisory and block nothing.
#      Phase 4's output format had no tier to print either into.
#
# WHAT THIS SUITE HOLDS. Four detectors, each reading its expectation OUT of
# the canon rather than restating it. Three carry a planted self-test — a
# positive that must hit and a near-miss that must stay silent — because a
# detector whose healthy state is zero hits needs a self-test, not a floor
# (docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md
# § Prevention). Detector 2 does not; it carries only a `gate_count >= 2`
# floor, which is the substitute that rule names as insufficient.
#
# WHAT IS MECHANIZED AND WHAT IS HELD BY REVIEW. #293 §3 enumerated five
# restated operatives in pre-merge/SKILL.md; §5 added by-number references;
# the issue's comment thread added an undefined severity tier. This suite does
# not cover all of them, and reading a green run as though it did is the
# failure this header exists to prevent
# (docs/solutions/testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md).
#
#   MECHANIZED
#     - by-number dimension references, across the scanned population
#       (Detector 1). #293 §5.
#     - severity labels on `- **Name (Label):**` violation bullets
#       (Detector 4). The comment-thread item. That bullet shape ONLY —
#       an inline `flag as \`Concern\`` is not reached.
#
#   PARTIALLY MECHANIZED — a paraphrase defeats both, by construction
#     - a dimension's gate (Detector 2): a VERBATIM 60-character prefix of
#       the canon's `**Only runs when …**` line. #293 called one of the two
#       gate restatements "near-verbatim"; a near-verbatim copy is outside
#       the fingerprint and passes green. Verified.
#     - the review-size ladder (Detector 3): three or more distinct band
#       thresholds in one file, or the Observation bound anywhere outside
#       the canon. A copy carrying fewer thresholds and not the Observation
#       bound passes green. Verified.
#
#   NOT MECHANIZED — held by review, and by nothing else
#     - a dimension's verification procedure (#293 §3, docs/solutions/
#       Adherence). No detector matches a procedure.
#     - a dimension's applicability statement (#293 §3, Surgical Scope).
#       No detector matches one.
#     Both were restored verbatim-minus-the-numbers during review and the
#     suite stayed green.
#
# So: three of #293 §3's five items are covered only against verbatim or
# near-complete copies, and two are not covered at all. Widen this suite
# against a real miss rather than on speculation — but do not read it as
# closing the class.
#
# WHAT IT DOES NOT HOLD, deliberately: whether SKILL.md's prose *instructs* a
# reader correctly. That property's only competent oracle is a reader, and the
# boundary is recorded in test-review-dimension-partition.sh's header (#284).
# These are syntactic detectors for text that should not exist.
#
# CENSUS SCOPE follows the sibling suite: ALL tracked files, minus dated
# history (CHANGELOG, docs/solutions/ — records of what was true then),
# generated copies (manifest targets, regenerated from sources already
# scanned), and the two test scripts that plant offending strings as fixtures.
#
# PORTABILITY: re-execs under /bin/bash when available, so on macOS every run
# exercises bash 3.2. No bash-4 builtins.
#
# Lineage: #291, #293, docs/restated-claims.md.

if [ -z "${OPERATIVES_SUITE_REEXEC:-}" ] && [ -x /bin/bash ]; then
    OPERATIVES_SUITE_REEXEC=1 exec /bin/bash "$0" "$@"
fi

set -euo pipefail
export LC_ALL=C

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
# Census population
# ============================================================================

targets_file="$(mktemp)"
population_file="$(mktemp)"
trap 'rm -f "$targets_file" "$population_file"' EXIT

awk '!/^#/ && NF == 2 { split($1, a, "/"); print $2 "/references/" a[length(a)] }' "$manifest" \
    | sort -u > "$targets_file"

git -C "$repo_root" ls-files \
    | grep -v '^CHANGELOG\.md$' \
    | grep -v '^docs/solutions/' \
    | grep -v '^scripts/test-restated-review-operatives\.sh$' \
    | grep -v '^scripts/test-review-dimension-partition\.sh$' \
    | grep -v -F -x -f "$targets_file" \
    > "$population_file"

pop_count="$(grep -c . "$population_file" || true)"
[ "$pop_count" -ge 50 ] || fatal "census population has $pop_count file(s); expected at least 50. git ls-files or the allowlist filtering broke. Refusing to report a vacuous pass."

section "Census population (set-membership pins)"

# The canon must be IN the population — several detectors below assert a
# literal occurs there and nowhere else, and an excluded canon would invert
# that into a silent pass.
assert_true "$(grep -qx 'pre-merge/review-checklist.md' "$population_file" && echo true || echo false)" \
    "population contains the canon (pre-merge/review-checklist.md)"
assert_true "$(grep -qx 'pre-merge/SKILL.md' "$population_file" && echo true || echo false)" \
    "population contains pre-merge/SKILL.md (where #293's restatements lived)"
# #293's census tell: the first pass scoped to pre-merge/ and docs/ and missed
# numeric references in four sibling skills. Pin one of them.
assert_true "$(grep -qx 'prd-to-issues/SKILL.md' "$population_file" && echo true || echo false)" \
    "population reaches sibling skills (prd-to-issues/SKILL.md — a first-pass miss)"

# ============================================================================
# Detector 1 — dimensions referred to by number
# ============================================================================
#
# The canon declares its `## N.` headings to BE the roster, so the numbering
# moves whenever a dimension is inserted. Any prose that names a dimension by
# number is a reference that renumbering silently retargets. Titles survive it.

detect_numeric_dimension_refs() {
    grep -onE '\b([Dd]imensions?|Dim) [0-9]+' || true
}

section "Detector 1 self-tests"

hit="$(printf 'The mirror check runs at /pre-merge Dimension 4 under Spec-reality.\n' | detect_numeric_dimension_refs)"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "numeric-ref detector: flags 'Dimension 4'"
hit="$(printf 'This is the failure mode /pre-merge Dim 8 backstops.\n' | detect_numeric_dimension_refs)"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "numeric-ref detector: flags the abbreviated 'Dim 8'"
miss="$(printf '## 4. Boundary Map Contracts\n\nThe Boundary Map Contracts dimension runs in Phase 3.\n' | detect_numeric_dimension_refs)"
assert_eq "" "$miss" "numeric-ref detector: silent on a canon heading and a by-title reference"

# ============================================================================
# Detector 2 — a dimension's own gate, restated elsewhere
# ============================================================================
#
# Each conditional dimension states its gate once, under its own heading, as a
# bold "**Only runs when …**" line. The expectation is EXTRACTED from the canon
# so a reworded gate cannot leave a stale fingerprint behind.

gates_file="$(mktemp)"
trap 'rm -f "$targets_file" "$population_file" "$gates_file"' EXIT
grep -E '^\*\*Only runs (when|if) ' "$checklist" \
    | sed -E 's/^\*\*Only runs (when|if) //; s/\*\*$//' \
    | cut -c1-60 > "$gates_file"

gate_count="$(grep -c . "$gates_file" || true)"
[ "$gate_count" -ge 2 ] || fatal "extracted $gate_count gate line(s) from the canon; expected at least 2. The '**Only runs when …**' shape changed. Refusing to report a vacuous pass."

# ============================================================================
# Detector 3 — the review-size ladder, restated
# ============================================================================
#
# Deliberately NOT scoped to a tier→threshold pairing: the restatement #293
# reported wrote the pair the other way round (">300 LOC Observation"), so a
# pairing fingerprint extracted from the canon's own bullet order would have
# missed it. Scoped to the thresholds themselves, with two assertions:
#
#   A. Three or more distinct band thresholds in one non-canon file is the
#      ladder copied. /prd-to-issues legitimately carries two of them —
#      Tacke's ">500 LOC / >20 files" is a shared literature threshold it
#      applies at planning time, and the canon's own Out-of-scope line names
#      that as the mirror rather than a duplicate.
#   B. The Observation bound belongs to the review dimension alone (Cohen's
#      upper bound, cited nowhere else in the pack), so a single occurrence
#      outside the canon is already a restatement.
#
# Both are read out of the canon's band bullets; neither hardcodes a number.

bands_file="$(mktemp)"
trap 'rm -f "$targets_file" "$population_file" "$gates_file" "$bands_file"' EXIT

band_bullets="$(grep -E '^- \*\*(Observation|Suggestion|Concern): >' "$checklist")"
printf '%s\n' "$band_bullets" | grep -oE '>[0-9]+ (LOC|files)' | sort -u > "$bands_file"

band_count="$(grep -c . "$bands_file" || true)"
[ "$band_count" -ge 3 ] || fatal "extracted $band_count review-size threshold(s) from the canon's band bullets; expected at least 3. The band-bullet shape changed. Refusing to report a vacuous pass."

observation_bound="$(printf '%s\n' "$band_bullets" | grep -E '^- \*\*Observation:' | grep -oE '>[0-9]+ (LOC|files)' | head -1 || true)"
[ -n "$observation_bound" ] || fatal "could not extract the Observation band's threshold from the canon. Refusing to report a vacuous pass."

printf 'band thresholds: %s (Observation bound: %s)\n' "$(tr '\n' ' ' < "$bands_file")" "$observation_bound"

# Reads a file path as $1; emits a line when 3+ distinct band thresholds appear.
detect_ladder_restatement() {
    _n="$(grep -oF -f "$bands_file" "$1" | sort -u | grep -c . || true)"
    [ "$_n" -ge 3 ] && printf '%s distinct band thresholds\n' "$_n"
    return 0
}

section "Detector 3 self-tests"

fixture="$(mktemp)"
printf 'bands documented in review-checklist.md (>300 LOC Observation, >500 LOC or >20 files Suggestion, >800 LOC + multi-domain Concern).\n' > "$fixture"
hit="$(detect_ladder_restatement "$fixture")"
assert_true "$([ -n "$hit" ] && echo true || echo false)" "ladder detector: flags the threshold-first restatement #293 reported"
printf "Size batches for reviewability (\xc2\xa76's >500 LOC / >20 files signal), not for speed.\n" > "$fixture"
miss="$(detect_ladder_restatement "$fixture")"
assert_eq "" "$miss" "ladder detector: silent on /prd-to-issues' two-threshold planning-time mirror"
rm -f "$fixture"

# ============================================================================
# Detector 4 — severity labels the canon does not define
# ============================================================================
#
# The tier vocabulary is whatever `## Severity Classification` defines, read
# out of the canon. A violation-pattern bullet that classifies into anything
# else — "Blocker", "Concern/Warning" — emits a tier no consumer can print.
# A trailing em-dash qualifier is allowed and stripped; a slash-compound is not.

tiers="$(sed -n '/^## Severity Classification/,$p' "$checklist" \
    | grep -oE '^- \*\*[A-Za-z]+:\*\*' \
    | sed -E 's/^- \*\*//; s/:\*\*$//')"
tier_count="$(printf '%s\n' "$tiers" | grep -c '[A-Za-z]' || true)"
[ "$tier_count" -ge 2 ] || fatal "extracted $tier_count severity tier(s) from the canon's Severity Classification section; expected at least 2. Refusing to report a vacuous pass."

printf 'defined severity tiers: %s\n' "$(printf '%s' "$tiers" | tr '\n' ' ')"

# Reads a markdown body on stdin; emits one line per violation-pattern bullet
# whose parenthetical severity label is outside the defined set.
detect_undefined_severity_labels() {
    { grep -oE '^- \*\*[^*(]+\([A-Z][^)]*\):\*\*' \
        | sed -E 's/^- \*\*[^*(]+\(//; s/\):\*\*$//' \
        | sed -E 's/ *—.*$//' \
        | while IFS= read -r label; do
            [ -n "$label" ] || continue
            grep -qx "$label" <<<"$tiers" || printf '%s\n' "$label"
        done
    } || true
}

section "Detector 4 self-tests"

hit="$(printf -- '- **Unmapped Must (Blocker):** A Must-commitment has no merged slice.\n' | detect_undefined_severity_labels)"
assert_eq "Blocker" "$hit" "severity detector: flags the undefined 'Blocker' tier"
hit="$(printf -- '- **Unmapped Want (Concern/Warning):** A Want-commitment has no merged slice.\n' | detect_undefined_severity_labels)"
assert_eq "Concern/Warning" "$hit" "severity detector: flags the slash-compound 'Concern/Warning'"
miss="$(printf -- '- **Unmapped Want (Suggestion):** A Want-commitment has no merged slice.\n' | detect_undefined_severity_labels)"
assert_eq "" "$miss" "severity detector: silent on a defined tier"
miss="$(printf -- '- **Unmapped Must (Concern — with the withheld action named):** x\n' | detect_undefined_severity_labels)"
assert_eq "" "$miss" "severity detector: silent on a defined tier carrying an em-dash qualifier"

# ============================================================================
# The corpus scan
# ============================================================================

section "Corpus scan (each label states its matcher's reach, not the property)"

numeric_hits=""
gate_hits=""
band_hits=""
label_hits=""

while IFS= read -r f; do
    p="$repo_root/$f"
    [ -f "$p" ] || continue

    h="$(detect_numeric_dimension_refs < "$p" | head -3 || true)"
    [ -n "$h" ] && numeric_hits="$numeric_hits$f: $h
"

    h="$(detect_undefined_severity_labels < "$p")"
    [ -n "$h" ] && label_hits="$label_hits$f: $h
"

    # Gates and bands belong to the canon; every OTHER file must be free of them.
    [ "$f" = "pre-merge/review-checklist.md" ] && continue

    h="$(grep -F -f "$gates_file" "$p" | head -1 || true)"
    [ -n "$h" ] && gate_hits="$gate_hits$f: $h
"

    h="$(detect_ladder_restatement "$p")"
    [ -n "$h" ] && band_hits="$band_hits$f: $h
"
    h="$(grep -oF "$observation_bound" "$p" | head -1 || true)"
    [ -n "$h" ] && band_hits="$band_hits$f: carries the Observation bound '$h'
"
done < "$population_file"

assert_eq "" "$numeric_hits" "no '[Dd]imensions?|Dim <N>' match in the $pop_count scanned files"
assert_eq "" "$gate_hits" "no verbatim copy of a gate's first 60 characters outside the canon ($gate_count gates extracted)"
assert_eq "" "$band_hits" "no file outside the canon carries 3+ of the $band_count band thresholds, nor the Observation bound $observation_bound"
assert_eq "" "$label_hits" "every '- **Name (Label):**'-shaped severity label found is a tier the canon defines"

printf '\n%d passed, %d failed  (bash %s)\n' "$pass" "$fail" "${BASH_VERSION%%(*}"
[ "$fail" -eq 0 ]
