#!/usr/bin/env bash
# The needles here are markdown and HTML, both full of backticks and quotes.
# Single quotes keep them literal; there is nothing to expand.
# shellcheck disable=SC2016
# test-decision-card-grounding.sh — contract test for the decision card (§13)
# and for the forward-looking grounding rule being a rule about a CLASS.
#
# THE DRIFT CLASS: a forward-looking block that renders assertion at the weight
# of evidence.
#
# Issue #317 is the incident, and its shape is worth stating because it is not
# the usual one. The Grounding Rule that governs every other structured block
# ("derived by tooling, never by the model") cannot apply here at all: a plan
# has no diff. So the rule is replaced by a weaker one — every field is either
# CITED, showing its source, or visibly ASSERTED — and a weaker rule that goes
# unenforced degrades to no rule, silently, while still looking like a render
# that knows what it is talking about.
#
# Why that matters more here than for the options-comparison (§11). An options
# matrix announces that nothing is settled; the reader arrives knowing they are
# looking at futures. A decision card announces the opposite. Lovallo &
# Kahneman's finding is that inside-view plans read as authoritative BECAUSE
# they are vivid and detailed, so rendering a plan's decisions crisply amplifies
# exactly that bias unless the render separates settled-and-sourced from
# proposed. An unmarked field in a decision card is not a cosmetic lapse — it is
# the block's whole failure mode.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. §13 exists, states its four fields in a fixed order, and carries the
#      floor and the chip bar (both phrased to match core §1's canonical text).
#   2. Every field in §13's worked example is marked cited or asserted. This is
#      the mechanical form of the rule — an unmarked cell fails.
#   3. Every card carries at least one cited field, and its stated split matches
#      the marks actually present. A card can lie by counting, not only by
#      omitting.
#   4. Every card serializes: a dc- id registered in core §4, and a
#      data-feedback-note descendant. Without the note the §4 serializer skips
#      the unit outright and the round-trip is fictional — the same defect
#      test-options-comparison-contract.sh pins for §11.
#   5. Core §1's forward-looking section is a CLASS rule naming both members,
#      not a rule about one block wearing a general heading.
#   6. The skill states the stricter skip gate for plans. The recap side skips
#      small diffs; the plan side must skip decisions that foreclose nothing,
#      which is the opposite direction from the usual "when in doubt, include."
#
# WHY EVERY ZERO-HIT DETECTOR IS SELF-TESTED. Assertions 2, 3, and 4 are healthy
# at zero hits, which is the shape that reports green when the detector itself
# breaks (docs/solutions/testing-patterns/dead-guards-report-coverage-they-do-not-have).
# Each one is therefore driven through the SAME function the live assertion
# calls, against fixtures in both directions. The fixtures are perturbed copies
# of the real §13 markup rather than hand-written miniatures, per
# docs/solutions/testing-patterns/authored-mutations-inherit-the-authors-blind-spot.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md
SKILL=visual-recap/SKILL.md

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }
fatal() { printf '  FATAL %s\n' "$1" >&2; exit 2; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then ok "$label"
    else bad "$label" "expected [$expected], got [$actual]"; fi
}

# The haystack arrives on a here-string, never through `printf | grep -q`.
# `grep -q` exits at the first match and printf takes SIGPIPE while still
# writing, so under `set -o pipefail` the pipeline reports 141 instead of 0 —
# invisible on a small file and wrong on every assertion against a large one.
# test-recap-mode-contract.sh hit exactly that against this same design doc.
has() { grep -qF -- "$2" <<<"$1"; }

assert_has() {
    if has "$1" "$2"; then ok "$3"; else bad "$3" "not found: $2"; fi
}

# extract <file> <start-regex> <end-regex> — the half-open span [start, end).
extract() {
    awk -v s="$2" -v e="$3" '$0 ~ s {f=1} f && $0 ~ e && NR>1 && !first {exit} f {print; first=0}' "$1" \
        | awk -v e="$3" 'NR>1 && $0 ~ e {exit} {print}'
}

s13="$(extract "$DESIGN" '^## 13\. Block: decision card' "^## Do's and Don'ts")"
[ -n "$s13" ] || fatal "§13 extracted to 0 lines from $DESIGN — the heading moved."

# ---------------------------------------------------------------------------
section "§13 states its four fields, in order, with the floor and the chip bar"
# ---------------------------------------------------------------------------
prev=0
for field in 'decided' 'rules out' 'reverses if' 'source'; do
    n="$(grep -n -F "**$field**" <<<"$s13" | sed -n '1s/:.*//p')"
    if [ -z "$n" ]; then
        bad "§13 names the field '$field'"
    elif [ "$n" -le "$prev" ]; then
        bad "§13 field '$field' is out of order (line $n, after $prev)"
    else
        ok "§13 names the field '$field', in order"
        prev="$n"
    fi
done

# Both phrases are core §1's canonical wording. Pinning §13 against the same
# strings is what makes "the card obeys the class rule" checkable rather than
# asserted — and both must still be present in the core, or §13 is agreeing
# with text that no longer exists.
for needle in 'at least one cited cell' 'two-thirds or more of its cells asserted'; do
    assert_has "$s13" "$needle" "§13 carries core §1's phrasing: '$needle'"
    assert_has "$(cat "$CORE")" "$needle" "core §1 still states '$needle'"
done

# The reason grounding binds harder here than in §11, named rather than assumed.
assert_has "$s13" 'authoritative' "§13 says why a decision card needs grounding more than an options matrix does"

# ---------------------------------------------------------------------------
section "every field in the worked example is marked cited or asserted"
# ---------------------------------------------------------------------------
# THE DETECTOR, defined once and shared with its self-tests below. Re-typing the
# needles into fixtures is how test-per-unit-series-contract.sh's first version
# shipped a green suite over a broken operative check.
#
# A field row is `<div class="dc-row">…`. It is well-formed only if it carries
# an oc-cited or oc-asserted span. Emits one line per OFFENDING row, so healthy
# is empty.
detect_unmarked_row() {
    grep -oE '<div class="dc-row">.*' | grep -vE 'class="oc-(cited|asserted)"' || true
}

s13_html="$(printf '%s\n' "$s13" | awk '/^```/ { fence = !fence; next } fence { print }')"
[ -n "$s13_html" ] || fatal "§13 contains no fenced code blocks."

rows_total=$(grep -cE '<div class="dc-row">' <<<"$s13_html" || true)
[ "${rows_total:-0}" -ge 4 ] || fatal "§13's worked example has $rows_total field rows — expected at least one full card."

unmarked="$(printf '%s\n' "$s13_html" | detect_unmarked_row | wc -l | tr -d ' ')"
assert_eq "0" "$unmarked" "all $rows_total field rows in §13's example are marked cited or asserted"

# ---------------------------------------------------------------------------
section "every card carries a cited field, and its stated split is honest"
# ---------------------------------------------------------------------------
# A card can satisfy the rule above and still mislead, by claiming a split its
# marks do not support — so the header is checked against the marks, not trusted.
#
# TWO MORE DETECTORS, defined once and shared with their self-tests below. Each
# takes one flattened card on stdin and emits a line only when that card is bad,
# so healthy is empty for both.
detect_floor_violation() {
    local card; card="$(cat)"
    local cited; cited=$( { grep -o 'class="oc-cited"' <<<"$card" || true; } | wc -l | tr -d ' ')
    [ "$cited" -ge 1 ] || printf 'no cited field\n'
}

detect_split_violation() {
    local card; card="$(cat)"
    local cited asserted claimed
    # Guarded: zero cited is the exact state the floor detector exists to
    # report, and an unguarded grep would abort the run under pipefail instead.
    cited=$( { grep -o 'class="oc-cited"' <<<"$card" || true; } | wc -l | tr -d ' ')
    asserted=$( { grep -o 'class="oc-asserted"' <<<"$card" || true; } | wc -l | tr -d ' ')
    # The dc-split header states "<n> cited · <m> asserted". An absent header is
    # a violation too: an unstated split cannot be checked, and §1 requires each
    # option's split to be shown.
    claimed="$(grep -oE '[0-9]+ cited · [0-9]+ asserted' <<<"$card" | head -1 || true)"
    if [ -z "$claimed" ]; then
        printf 'no stated split\n'
    elif [ "$claimed" != "$cited cited · $asserted asserted" ]; then
        printf 'stated [%s], marks say [%s cited · %s asserted]\n' "$claimed" "$cited" "$asserted"
    fi
}

card_count=0
floor_violations=0
split_violations=0
real_card=""
while IFS= read -r card; do
    [ -n "$card" ] || continue
    card_count=$((card_count + 1))
    [ -n "$real_card" ] || real_card="$card"
    [ -z "$(printf '%s' "$card" | detect_floor_violation)" ] || floor_violations=$((floor_violations + 1))
    [ -z "$(printf '%s' "$card" | detect_split_violation)" ] || split_violations=$((split_violations + 1))
done < <(printf '%s\n' "$s13_html" | awk '
    # Flatten each card onto one line. Joining with a space rather than a
    # newline is what avoids gawk-only gensub — this suite runs under macOS
    # BWK awk in pre-push and GNU awk in CI, and must behave identically.
    /<div class="dc-card"/ { c = 1; buf = "" }
    c                      { buf = buf $0 " " }
    /<\/textarea>/         { if (c) { print buf; c = 0 } }
')

[ "$card_count" -ge 2 ] || fatal "found $card_count decision cards in §13's example — expected the documented pair."
assert_eq "0" "$floor_violations" "each of the $card_count cards carries at least one cited field"
assert_eq "0" "$split_violations" "each card's stated cited/asserted split matches its marks"

# ---------------------------------------------------------------------------
section "every card can actually serialize"
# ---------------------------------------------------------------------------
assert_has "$(cat "$CORE")" 'dc-<decision-slug>' "core §4 registers the dc- id shape"

ids=$( { grep -o 'data-feedback-id="dc-[a-z0-9-]*"' <<<"$s13_html" || true; } | wc -l | tr -d ' ')
assert_eq "$card_count" "$ids" "every card carries a dc- data-feedback-id"

bad_ids=$(grep -oE 'data-feedback-id="[^"]*"' <<<"$s13_html" | grep -cv 'data-feedback-id="dc-' || true)
assert_eq "0" "$bad_ids" "no card uses a non-dc- id"

notes=$(grep -c 'data-feedback-note' <<<"$s13_html" || true)
assert_eq "$card_count" "$notes" "every card contains a note field the §4 serializer will read"

# ---------------------------------------------------------------------------
section "core §1's forward-looking rule is a class rule, not a one-block rule"
# ---------------------------------------------------------------------------
fl="$(extract "$CORE" '^### Forward-looking blocks' '^---')"
[ -n "$fl" ] || fatal "§1's forward-looking subsection extracted to 0 lines from $CORE."

assert_has "$fl" 'class' "core §1's forward-looking section frames itself as a class rule"
for member in 'options-comparison' 'decision card'; do
    assert_has "$fl" "$member" "core §1 names '$member' as a member of the class"
done

# ---------------------------------------------------------------------------
section "the skill states the stricter skip gate for plans"
# ---------------------------------------------------------------------------
# A FOURTH DETECTOR, because polarity is the whole content of these two claims
# and a bare substring check cannot carry it. The first draft asserted the words
# 'stricter' and 'forecloses something' were present. Both survive their own
# inversion — "the skip gate gets looser, not stricter" contains 'stricter', and
# "a decision that never forecloses something" contains 'forecloses something' —
# and the suite was verified GREEN at 30/30 against both mutations before this
# replaced it. The keyword was present and the rule said the opposite.
#
# So each needle is anchored to the clause shape rather than to a word, and both
# real inversions are fixtures below. This is the same discipline the three
# detectors above already follow; these two assertions were the one place in the
# file it had been skipped, which is where the defect landed.
detect_gate_polarity_defect() {
    local txt; txt="$(cat)"
    has "$txt" 'skip gate gets stricter, not looser' \
        || printf 'gate-direction claim absent or inverted\n'
    has "$txt" 'only for a decision that forecloses something' \
        || printf 'foreclosure gate absent or negated\n'
}

skill_txt="$(cat "$SKILL")"
polarity="$(printf '%s' "$skill_txt" | detect_gate_polarity_defect)"
assert_eq "" "$polarity" "the skill's plan-side gate is stricter and keyed on foreclosure"

# ---------------------------------------------------------------------------
section "the zero-hit detectors still detect (self-test)"
# ---------------------------------------------------------------------------
# Assertions above are healthy at zero. Each fixture is a perturbed copy of the
# REAL first row of §13's example, so the battery cannot only contain shapes
# simpler than what the corpus holds.
real_row="$(grep -oE '<div class="dc-row">.*' <<<"$s13_html" | head -1)"
[ -n "$real_row" ] || fatal "could not lift a real dc-row from §13 to build fixtures."

# Direction 1: a genuinely broken row must be caught.
stripped="${real_row//class=\"oc-cited\"/class=\"dc-plain\"}"
renamed="${real_row//class=\"oc-cited\"/}"
while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    if [ -n "$(printf '%s' "$fixture" | detect_unmarked_row)" ]; then
        ok "detector catches: $label"
    else
        bad "detector MISSED: $label" "a broken row would ship green"
    fi
done <<EOF
grounding mark replaced by a neutral class|$stripped
grounding mark deleted outright|$renamed
EOF

# Direction 2: the real row, and a legitimately asserted one, must NOT be caught.
asserted_variant="${real_row//class=\"oc-cited\"/class=\"oc-asserted\"}"
while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    if [ -z "$(printf '%s' "$fixture" | detect_unmarked_row)" ]; then
        ok "detector passes: $label"
    else
        bad "detector FALSE-POSITIVES on: $label"
    fi
done <<EOF
the real cited row from §13|$real_row
the same row marked asserted instead|$asserted_variant
EOF

# The floor and split detectors are healthy at zero too. Fixtures are perturbed
# copies of the REAL first card, not miniatures — a card whose every citation is
# downgraded, and a card whose header keeps a split its marks no longer support.
[ -n "$real_card" ] || fatal "could not lift a real dc-card to build fixtures."
all_asserted="${real_card//class=\"oc-cited\"/class=\"oc-asserted\"}"
no_header="${real_card//class=\"dc-split\"/class=\"dc-quiet\"}"
no_header="$(sed -E 's/[0-9]+ cited · [0-9]+ asserted//' <<<"$no_header")"

while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    if [ -n "$(printf '%s' "$fixture" | detect_floor_violation)" ]; then
        ok "floor detector catches: $label"
    else
        bad "floor detector MISSED: $label" "an ungrounded card would ship green"
    fi
done <<EOF
every citation downgraded to asserted|$all_asserted
EOF

if [ -z "$(printf '%s' "$real_card" | detect_floor_violation)" ]; then
    ok "floor detector passes: the real first card from §13"
else
    bad "floor detector FALSE-POSITIVES on the real first card"
fi

while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    if [ -n "$(printf '%s' "$fixture" | detect_split_violation)" ]; then
        ok "split detector catches: $label"
    else
        bad "split detector MISSED: $label" "a card could misstate its evidence"
    fi
done <<EOF
marks changed but the stated split left alone|$all_asserted
split header removed entirely|$no_header
EOF

if [ -z "$(printf '%s' "$real_card" | detect_split_violation)" ]; then
    ok "split detector passes: the real first card from §13"
else
    bad "split detector FALSE-POSITIVES on the real first card"
fi

# The polarity detector, against the REAL sentence and its two REAL inversions.
# These are not hypotheticals: both were run against the previous draft of this
# section and both left the suite green at 30/30.
gate_ok="$skill_txt"
gate_looser="${skill_txt//skip gate gets stricter, not looser/skip gate gets looser, not stricter}"
gate_negated="${skill_txt//only for a decision that forecloses something/only for a decision that never forecloses something}"
[ "$gate_looser" != "$skill_txt" ]  || fatal "the 'stricter, not looser' clause is not in $SKILL — the fixture could not be built."
[ "$gate_negated" != "$skill_txt" ] || fatal "the foreclosure clause is not in $SKILL — the fixture could not be built."

# Checked directly rather than through a `read -r label|fixture` loop: these
# fixtures are the whole SKILL.md, and a `|`-delimited here-doc splits a
# multi-line fixture into one bogus case per line. The first draft of this
# section did exactly that and reported 302 assertions, nearly all of them
# "catches" verdicts on unrelated prose lines that happen to lack the clause —
# a suite that looks thorough and is measuring nothing.
if [ -n "$(printf '%s' "$gate_looser" | detect_gate_polarity_defect)" ]; then
    ok "polarity detector catches: gate direction flipped to looser"
else
    bad "polarity detector MISSED: gate direction flipped to looser" "the gate could be documented backwards"
fi

if [ -n "$(printf '%s' "$gate_negated" | detect_gate_polarity_defect)" ]; then
    ok "polarity detector catches: foreclosure condition negated"
else
    bad "polarity detector MISSED: foreclosure condition negated" "the gate could be documented backwards"
fi

if [ -z "$(printf '%s' "$gate_ok" | detect_gate_polarity_defect)" ]; then
    ok "polarity detector passes: the real sentence from $SKILL"
else
    bad "polarity detector FALSE-POSITIVES on the real sentence"
fi

# ---------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
