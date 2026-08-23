#!/usr/bin/env bash
# test-options-comparison-contract.sh — cross-file contract test for the
# options-comparison block (#245).
#
# The block's rules are deliberately restated rather than referenced, because
# four of the six skills that hold docs/next-step-menu.md do not hold the
# rendering docs and cannot follow a pointer to them. Restatement is the
# consequence of that decision, and restatement is exactly the shape
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md
# says needs a mechanism: "Adopt this whenever prose claims cross-file
# agreement. The assertion and the test should be added in the same change."
#
# next-step-menu.md states outright that visual-rendering-core.md §1 "states it
# once canonically." Nothing constructed that agreement before this suite. The
# model-authored-block count drifted twice while #245 was in review — caught by
# a reviewer both times, which is the mechanism the entry above says not to
# rely on.
#
# The suite extracts the real text from the real files rather than restating
# it, following scripts/test-selection-idiom-consistency.sh.
#
# Deliberately NOT asserted: that the restatements are byte-identical. They are
# not, and should not be — the core carries the render treatments, the menu doc
# carries the trigger, the design doc carries the markup. Only the parts that
# must agree are pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

CORE=docs/visual-rendering-core.md
MENU=docs/next-step-menu.md
DESIGN=docs/visual-recap-design.md

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

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

# ---------------------------------------------------------------------------
section "the threshold's three conditions agree wherever they are restated"
# ---------------------------------------------------------------------------
# The menu doc owns the threshold; the design doc restates it for §11's readers.
# Both must carry the same two numbers and the same third condition.

# `|| true` throughout: under `set -e` a missed grep would abort the run with no
# FAIL row and no summary, leaving the operator to bisect for the broken rule.
menu_opts=$( { grep -oE '≥[0-9]+ mutually exclusive options' "$MENU" || true; } | head -1)
assert_eq "≥3 mutually exclusive options" "$menu_opts" "menu doc states the option count"

menu_attrs=$( { grep -oE 'Each carries ≥[0-9]+ attributes' "$MENU" || true; } | head -1)
assert_eq "Each carries ≥3 attributes" "$menu_attrs" "menu doc states the attribute count"

# The design doc and both consuming skills restate the same threshold in prose.
# coverage: enumerated — the four holders of the options-comparison contract.
# Not derivable: the set is 'the files that must agree on this block', which is
# a property of the contract rather than something a scan of the tree can find.
for f in "$DESIGN" pre-merge/SKILL.md visual-recap/SKILL.md walk-commits/SKILL.md; do
    assert_found "three or more mutually exclusive options" "$f" \
        "$(basename "$(dirname "$f")")/$(basename "$f"): option count agrees"
    assert_found "three or more attributes" "$f" \
        "$(basename "$(dirname "$f")")/$(basename "$f"): attribute count agrees"
    assert_found "not orderable on one axis" "$f" \
        "$(basename "$(dirname "$f")")/$(basename "$f"): third condition agrees"
done

assert_found "not orderable on one axis" "$MENU" "menu doc states the third condition"

# ---------------------------------------------------------------------------
section "the cited/asserted floor agrees across all three docs"
# ---------------------------------------------------------------------------
# The floor is the block's Lie-Factor defense. If one doc drops it, a reader
# holding only that doc renders an all-asserted comparison and never learns why
# that is the failure the block exists to prevent.

assert_found "at least one cited cell" "$CORE"   "core states the one-cited-cell floor"
assert_found "at least one cited cell" "$MENU"   "menu doc restates the floor"
assert_found "at least one cited cell" "$DESIGN" "design doc restates the floor"

# ---------------------------------------------------------------------------
section "the chip bar is numeric, and the worked example obeys it"
# ---------------------------------------------------------------------------
# A "mostly asserted" judgment call at the rule becomes a different judgment
# call at every render, because §11's example is copied verbatim. The bar is
# two-thirds; the example must not contradict it.

assert_found "two-thirds or more of its cells asserted" "$CORE" "core states a numeric chip bar"

# Every option header declaring N cited / M asserted must carry the asserted
# chip if and only if M/(N+M) >= 2/3.
chip_violations=0
floor_violations=0
while IFS= read -r line; do
    cited=$( { printf '%s' "$line" | grep -oE '[0-9]+ cited' || true; } | grep -oE '[0-9]+' || true)
    asserted=$( { printf '%s' "$line" | grep -oE '[0-9]+ asserted' || true; } | grep -oE '[0-9]+' || true)
    if [ -z "$cited" ] || [ -z "$asserted" ]; then
        floor_violations=$((floor_violations + 1))
        printf '       option unit declares no cited/asserted split\n'
        continue
    fi
    # The floor, checked against the example rather than only as prose. §11's markup
    # is copied verbatim, so a zero-cited column in the skeleton would propagate as the
    # sanctioned shape of the exact Lie Factor the block exists to prevent.
    if [ "$cited" -lt 1 ]; then
        floor_violations=$((floor_violations + 1))
        printf '       option unit has %s cited cells; the floor is at least 1\n' "$cited"
    fi
    total=$((cited + asserted))
    has_chip=0
    printf '%s' "$line" | grep -qF 'oc-chip is-asserted' && has_chip=1
    # asserted/total >= 2/3  <=>  3*asserted >= 2*total
    should_chip=0
    [ $((3 * asserted)) -ge $((2 * total)) ] && should_chip=1
    if [ "$has_chip" -ne "$should_chip" ]; then
        chip_violations=$((chip_violations + 1))
        printf '       %s cited / %s asserted: chip=%s, bar says %s\n' \
            "$cited" "$asserted" "$has_chip" "$should_chip"
    fi
done < <(grep -F 'data-feedback-kind="option"' "$DESIGN")
assert_eq "0" "$chip_violations" "worked example's chips obey the two-thirds bar"
assert_eq "0" "$floor_violations" "every option in the worked example carries a cited cell"

# ---------------------------------------------------------------------------
section "the opt- id shape agrees between its registry and its use"
# ---------------------------------------------------------------------------
# §4 of the core is the stable-id registry. An id used in the skeleton but
# absent from the registry cannot be parsed back out of a feedback blob.

assert_found 'opt-<option-slug>' "$CORE" "core registers the opt- id shape"

bad_ids=0
while IFS= read -r id; do
    case "$id" in
        opt-*) ;;
        *) bad_ids=$((bad_ids + 1)); printf '       non-conforming id: %s\n' "$id" ;;
    esac
done < <(grep -F 'data-feedback-kind="option"' "$DESIGN" \
         | grep -oE 'data-feedback-id="[^"]+"' | sed 's/.*"\(.*\)"/\1/')
assert_eq "0" "$bad_ids" "every option unit in §11 uses an opt- id"

# ---------------------------------------------------------------------------
section "every option unit can actually serialize"
# ---------------------------------------------------------------------------
# The §4 serializer returns early when a unit has neither a verdict nor a note,
# so an option header without a [data-feedback-note] descendant is skipped
# unconditionally and its handle is inert — while §11's prose describes a
# working round-trip.

assert_found 'data-feedback-note' "$CORE" "core's serializer reads a note field"

# Scoped to the unit's own element, not merely its source line: the serializer calls
# el.querySelector('[data-feedback-note]'), so an input that sits on the same line but
# outside the unit's closing tag serializes nothing while a line-wise grep still passes.
option_units=$(grep -cF 'data-feedback-kind="option"' "$DESIGN")

# Walks div depth from the unit's opening tag and counts a note only if it appears
# before the matching close. A line-wise grep would also pass on markup where the
# input sits after the unit's </div>, which serializes nothing.
notes=$(awk '
  /data-feedback-kind="option"/ {
    rest = $0; sub(/^.*data-feedback-kind="option"/, "", rest)
    depth = 1; scoped = ""
    while (length(rest) > 0 && depth > 0) {
      if (substr(rest, 1, 6) == "</div>") { depth--; if (depth == 0) break
                                            scoped = scoped "</div>"; rest = substr(rest, 7) }
      else if (substr(rest, 1, 4) == "<div") { depth++; scoped = scoped "<div"; rest = substr(rest, 5) }
      else { scoped = scoped substr(rest, 1, 1); rest = substr(rest, 2) }
    }
    if (scoped ~ /data-feedback-note/) n++
  }
  END { print n + 0 }' "$DESIGN")
assert_eq "$option_units" "$notes" "every option unit contains a note input as a descendant"

# ---------------------------------------------------------------------------
section "the block count in the core matches its own table"
# ---------------------------------------------------------------------------
# §3 asserts a countable number of blocks. It said "Nine" against a ten-row
# table for one commit of #245's review.

declared=$(grep -oE '^(Ten|Nine|Eleven|Twelve) blocks' "$CORE" | head -1 | cut -d' ' -f1)
rows=$(awk '/^\| Block \| Role \|/{t=1;next} t&&/^\|---/{next} t&&/^\|/{n++} t&&!/^\|/{t=0} END{print n+0}' "$CORE")
case "$declared" in
    Nine) declared_n=9 ;; Ten) declared_n=10 ;; Eleven) declared_n=11 ;; Twelve) declared_n=12 ;;
    *) declared_n=-1 ;;
esac
assert_eq "$declared_n" "$rows" "§3's declared block count matches its table rows"

# ---------------------------------------------------------------------------
section "the model-authored carve-out count agrees everywhere it is stated"
# ---------------------------------------------------------------------------
# This is the drift that actually happened, twice, during #245's review: §1 was
# changed to "two" while §9, the §3 table cell, and visual-recap/SKILL.md kept
# the singular. Generated references/ copies are excluded — sync covers those.

singular=$( { grep -rn --include='*.md' \
    -e 'the one model-authored' -e 'the one \*\*model-authored\*\*' -e 'the model-authored exception' \
    docs/ visual-recap/ walk-commits/ pre-merge/ 2>/dev/null || true; } \
    | { grep -v '/references/' || true; } \
    | { grep -v '^docs/solutions/' || true; } \
    | wc -l | tr -d ' ')
assert_eq "0" "$singular" "no file still calls the wireframe the ONE model-authored block"

assert_found "there are two" "$CORE" "core states the carve-out count"

# ---------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
