#!/usr/bin/env bash
# test-per-unit-series-contract.sh — cross-file contract test for the per-unit
# series block (§12) and the prose bar that shipped with it (#304).
#
# THE DRIFT CLASS. §12 is the one recap block whose value depends entirely on
# constraints that are invisible in its own output. A per-unit series that
# renders every unit as a real <section> and one that swaps a single stage's
# innerHTML look identical in a screenshot; the second one violates
# visual-recap-design.md §10's stop-rule ("no framework, no state library; if
# this grows routing or a store it has become the app the surface exists to
# avoid") and defeats the unit-to-unit comparison the block exists to enable.
# The same is true of the all-units matrix and the feedback serializer: both are
# REQUIRED by §12's prose, and prose is not a mechanism.
#
# THE INCIDENT (#304). The artifact that motivated the block was a nine-panel
# router — `let cur`, `render(i)`, `stage.innerHTML =` — and the verdict that
# approved the block explicitly rejected the router: "the user asked for
# granularity and per-unit before/afters. They did not ask for innerHTML
# swapping. Give them the first; refuse the second." An agent copying §12's
# markup has both shapes available in its head. Only a check keeps the doc from
# shipping the one it forbids.
#
# THE PRECEDENT. #245 added the options-comparison block to the existing docs
# and pinned it with scripts/test-options-comparison-contract.sh. This suite is
# that precedent applied to §12, and it deliberately does NOT re-assert what
# that suite already covers (the §3 block count against its own table rows).
#
# WHAT IT PINS, every side extracted from the real files rather than restated:
#   1. §12's gate (one root cause at four or more near-identical sites) agrees
#      between the design doc and visual-recap/SKILL.md.
#   2. §12's two REQUIRED elements are actually present in its markup: the
#      all-units matrix (reusing §11's .oc-matrix) and the copy-feedback
#      serializer, with every unit carrying a note input as a real descendant.
#   3. §12 obeys §10's stop-rule — no innerHTML swap, no store, and every unit
#      is a real <section> in the document.
#   4. Every §12 unit uses a `u-` feedback id, and that id shape is registered
#      in the core's §4 id registry, so a feedback blob parses back.
#   5. The toggle subtraction stayed subtracted — no setSide, no ba-* ids, no
#      "toggle variant" anywhere outside docs/solutions/ and CHANGELOG history.
#   6. The prose bar is wired: both manifest rows exist and both skills point at
#      the bundled copy.
#   7. The depth-vs-population distinction is stated in both the core and the
#      skill, because a 3-8 budget read as a population cap is exactly what
#      makes a sweep render as a sampled file tree.
#
# DELIBERATELY NOT ASSERTED: that the design doc and the skill word the gate
# identically beyond the threshold phrase. They should not — the doc carries the
# markup, the skill carries the decision. Only the parts that must agree are
# pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md
SKILL=visual-recap/SKILL.md
WALK=walk-commits/SKILL.md
MANIFEST=scripts/skill-references.manifest

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then ok "$label"
    else bad "$label" "expected [$expected], got [$actual]"; fi
}

assert_found() {
    local needle="$1" file="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then ok "$label"
    else bad "$label" "not found in $file: $needle"; fi
}

assert_absent() {
    local needle="$1" file="$2" label="$3"
    if grep -qF -- "$needle" "$file"; then bad "$label" "found in $file, expected gone: $needle"
    else ok "$label"; fi
}

for f in "$DESIGN" "$CORE" "$SKILL" "$WALK" "$MANIFEST"; do
    [ -f "$f" ] || fatal "$f is missing — the contract has no subject to read."
done

# ---------------------------------------------------------------------------
# §12's span, extracted from the real heading structure. Everything that
# reasons about "inside §12" reads this file, never the whole document —
# otherwise an assertion passes on markup that lives in §7 or §11.
# ---------------------------------------------------------------------------
span="$(mktemp)"
trap 'rm -f "$span"' EXIT
awk '/^## 12\./ { inside = 1 } inside && /^## 1[3-9]\./ { inside = 0 } inside' "$DESIGN" > "$span"

span_lines="$(wc -l < "$span" | tr -d ' ')"
# Non-vacuity floor. Every assertion below is a grep over $span; an empty span
# would make the absent-checks pass and only the found-checks fail, which reads
# as "three problems" instead of "the section is missing".
if [ "${span_lines:-0}" -lt 20 ]; then
    fatal "§12 extracted to only ${span_lines:-0} line(s) of $DESIGN — the section is absent or the heading shape changed, and every assertion below would be measuring nothing."
fi
ok "§12 extracted: $span_lines lines"

# ---------------------------------------------------------------------------
section "the gate agrees between the design doc and the skill"
# ---------------------------------------------------------------------------
# The block is gated rather than offered as a default because the incident that
# produced it is N=1 and confounded. A threshold that drifts between the doc
# that describes the block and the skill that decides to render it is the same
# as no threshold.

assert_found "four or more near-identical sites" "$span"  "§12 states the site threshold"
assert_found "four or more near-identical sites" "$SKILL" "the skill states the same threshold"
assert_found "one root cause"                    "$span"  "§12 states the one-root-cause condition"
assert_found "one root cause"                    "$SKILL" "the skill states the same condition"

# ---------------------------------------------------------------------------
section "§12's two required elements are present in its own markup"
# ---------------------------------------------------------------------------
# Without the matrix, stepping units is Tufte's sequential-display anti-pattern
# with extra steps: a unit-to-unit question ("which sites got the operator fix
# too?") becomes a memory test. Without the serializer, the artifact renders
# comprehension and drops the round-trip the core §4 owns.

assert_found "oc-matrix"    "$span" "§12 requires the all-units matrix"
assert_found "oc-matrix"    "$DESIGN" "§11 still defines the matrix §12 reuses"
assert_found "copyFeedback" "$span" "§12 wires the core's copy-feedback serializer"

# Every unit header must contain a note input as a real DESCENDANT, not merely
# on the same source line: the §4 serializer calls el.querySelector(...), so an
# input sitting past the unit's closing tag serializes nothing while a line-wise
# grep still passes. This walks div depth from the unit's opening tag.
# Counted from the opening tags, not from every line mentioning the attribute:
# §12's own prose quotes `data-feedback-kind="unit"` when stating requirement 3,
# and counting that inflates the population against which the note-descendant
# check below is compared — reporting a wired serializer as unwired.
unit_headers="$(grep -cE '<section id="unit-' "$span" || true)"
if [ "${unit_headers:-0}" -lt 2 ]; then
    bad "§12's worked example renders at least two units" \
        "found ${unit_headers:-0} unit(s); a one-unit example cannot demonstrate a series"
else
    ok "§12's worked example renders $unit_headers units"
fi

# Walks from the unit marker forward across LINES until the section closes, so a
# note input several lines below its unit header still counts. A line-wise scan
# would report zero here and read as "the serializer is unwired" when it is not.
scoped_notes="$(awk -v marker='<section id="unit-' '
  {
    if (!inunit) {
      i = index($0, marker)
      if (i == 0) next
      inunit = 1
      buf = substr($0, i + length(marker))
    } else {
      buf = buf "\n" $0
    }
    t1 = buf; opens  = gsub(/<section/, "", t1)
    t2 = buf; closes = gsub(/<\/section>/, "", t2)
    if (closes > opens) {
      if (buf ~ /data-feedback-note/) { n++ }
      inunit = 0; buf = ""
    }
  }
  END {
    if (inunit && buf ~ /data-feedback-note/) { n++ }
    print n + 0
  }' "$span")"
assert_eq "$unit_headers" "$scoped_notes" "every unit contains a note input as a descendant"

# ---------------------------------------------------------------------------
section "§12 obeys §10's stop-rule — sections, not a router"
# ---------------------------------------------------------------------------
# This is the whole reason the block was approved narrowly. The artifact that
# motivated it swapped the innerHTML of one stage; the verdict took the decomposition
# and refused the router. A doc that ships both is a doc whose rules stop being
# believed.

# The needle is the <script> tag rather than a bare "innerHTML", because §12's own
# prose forbids an innerHTML swap by name and a bare needle would fire on the rule
# itself. §12 ships zero JavaScript, so the tag is both the stronger claim and the
# one that cannot be satisfied by deleting a sentence.
assert_absent "<script"          "$span" "§12 ships no JavaScript of its own"
if grep -qE 'innerHTML[[:space:]]*=' "$span"; then
    bad "§12 contains no innerHTML assignment" "the router shape §10 forbids is present in the markup"
else
    ok "§12 contains no innerHTML assignment"
fi
assert_found  "No framework" "$DESIGN" "§10's stop-rule is still stated"

# Units must be real <section> elements in the document, which is what makes
# unit-to-unit comparison a scroll rather than a memory test.
unit_sections="$(grep -cE '<section id="unit-' "$span" || true)"
if [ "${unit_sections:-0}" -ge 2 ]; then
    ok "§12 renders $unit_sections units as real <section> elements"
else
    bad "§12 renders every unit as a real <section>" \
        "found ${unit_sections:-0} <section id=\"unit-…\"> element(s); a stage swapped in place is the router §10 forbids"
fi

# ---------------------------------------------------------------------------
section "the unit id shape agrees between its registry and its use"
# ---------------------------------------------------------------------------
# §4 of the core is the stable-id registry. An id used in the skeleton but
# absent from the registry cannot be parsed back out of a feedback blob.

assert_found 'u-<unit-slug>' "$CORE" "core registers the u- id shape"

bad_ids=0
while IFS= read -r id; do
    case "$id" in
        u-*) ;;
        *) bad_ids=$((bad_ids + 1)); printf '       non-conforming id: %s\n' "$id" ;;
    esac
done < <(grep -E '<section id="unit-' "$span" \
         | grep -oE 'data-feedback-id="[^"]+"' | sed 's/.*"\(.*\)"/\1/')
kinded="$(grep -E '<section id="unit-' "$span" | grep -cF 'data-feedback-kind="unit"' || true)"
assert_eq "$unit_headers" "$kinded" "every unit section declares data-feedback-kind=\"unit\""

assert_eq "0" "$bad_ids" "every unit in §12 uses a u- id"

# ---------------------------------------------------------------------------
section "the toggle subtraction stayed subtracted"
# ---------------------------------------------------------------------------
# §7's toggle was the doc's only instance of the sequential-display anti-pattern
# it elsewhere warns against, and the sole consumer of the singular ba-* ids
# that blocked a repeatable comparison. It is easy to re-add from memory,
# because five earlier revisions of this doc shipped it.
# CHANGELOG.md and docs/solutions/ are excluded: both are history, and history
# correctly records that the toggle once existed.

live_toggle="$( { grep -rn --include='*.md' \
    -e 'setSide' -e 'ba-thumb' -e 'toggle variant' \
    docs/ visual-recap/ walk-commits/ pre-merge/ 2>/dev/null || true; } \
    | { grep -v '^docs/solutions/' || true; } \
    | wc -l | tr -d ' ')"
assert_eq "0" "$live_toggle" "no live file still carries the toggle variant"

assert_found "sec-compare-<slug>" "$DESIGN" "§7's section id carries a slug so a comparison can repeat"

# ---------------------------------------------------------------------------
section "the prose bar is wired into both rendering skills"
# ---------------------------------------------------------------------------
# Under the Grounding Rule prose is the ENTIRE authored layer of these two
# skills, and it was the only authored layer in the pack with no stated bar. A
# pointer without a manifest row does not survive install; a manifest row
# without a pointer is a file nobody reads.

for skill in visual-recap walk-commits; do
    rows="$(awk -v s="$skill" '!/^[[:space:]]*#/ && $1 == "docs/writing-for-humans.md" && $2 == s' "$MANIFEST" | wc -l | tr -d ' ')"
    assert_eq "1" "$rows" "$skill has exactly one writing-for-humans manifest row"
done

assert_found "references/writing-for-humans.md" "$SKILL" "visual-recap points at the bundled prose bar"
assert_found "references/writing-for-humans.md" "$WALK"  "walk-commits points at the bundled prose bar"
for skill in visual-recap walk-commits; do
    if [ -f "$skill/references/writing-for-humans.md" ]; then
        ok "$skill/references/writing-for-humans.md exists"
    else
        bad "$skill/references/writing-for-humans.md exists" "run scripts/sync-skill-references.sh"
    fi
done

# ---------------------------------------------------------------------------
section "depth and population are distinguished where the budget is stated"
# ---------------------------------------------------------------------------
# The 3-8 budget read as a population cap is the exact mechanism that renders a
# sweep as a sampled file tree — which is the finding #304 opened on.

assert_found "per-unit series" "$CORE"  "the core's vocabulary names the block"
assert_found "population"      "$CORE"  "the core distinguishes depth from population"
assert_found "never a population cap" "$SKILL" "the skill states the budget is depth, not population"

# ---------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
