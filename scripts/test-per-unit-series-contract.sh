#!/usr/bin/env bash
# test-per-unit-series-contract.sh — cross-file contract test for the per-unit
# series block (§12) and the prose bar that shipped with it (#304).
#
# THE DRIFT CLASS. §12 is the one recap block whose value depends entirely on
# constraints that are invisible in its own output. A per-unit series that
# renders every unit as a real <section> and one that swaps a single stage's
# innerHTML look identical in a screenshot; the second violates
# visual-recap-design.md §10's stop-rule and defeats the unit-to-unit
# comparison the block exists to enable. The same is true of the all-units
# matrix and the feedback serializer: both are REQUIRED by §12's prose, and
# prose is not a mechanism.
#
# THE INCIDENT (#304). The artifact that motivated the block was a nine-panel
# router — `let cur`, `render(i)`, `stage.innerHTML =`. The verdict that
# approved the block explicitly rejected the router. An agent copying §12's
# markup has both shapes available in its head; only a check keeps the doc from
# shipping the one it forbids.
#
# THE SECOND INCIDENT, IN THIS FILE (#304 review). The first version of this
# suite shipped FIVE assertions that passed when the thing they named was
# deleted, and its CHANGELOG entry claimed "every assertion was mutation-
# checked". The author's mutation battery had perturbed only things that were
# PRESENT; none tested for vacuity under ABSENCE. Review caught all five:
#
#   1. `bad_ids` started at 0 and incremented only for a malformed id, so
#      deleting every id passed.
#   2. The matrix assertion read the whole §12 span, which contains the word
#      `.oc-matrix` in PROSE, so deleting the matrix markup passed.
#   3. The two gate assertions read all of visual-recap/SKILL.md, and both
#      phrases also appear in the frontmatter `description`, so deleting the
#      operative Step 3 instruction passed.
#   4. `assert_found "population" "$CORE"` matched a bare word surviving in
#      another section, so deleting the depth-vs-population bullet passed.
#   5. The toggle census keyed on three literal strings, so reinstating a
#      hide-one-side toggle under a renamed handler passed.
#
# Two structural rules come out of that and are applied throughout below:
#   (a) An assertion about MARKUP reads the extracted markup, never the span
#       that also holds the prose describing the markup.
#   (b) A detector whose healthy state is ZERO hits gets a self-test — plant
#       the shape it exists to find and require a hit, plant a near-miss and
#       require silence. A floor is not a substitute
#       (docs/solutions/testing-patterns/
#        mechanism-generality-lags-the-pattern-2026-08-23.md § Prevention #2).
#
# WHAT IT PINS, every side extracted from the real files rather than restated:
#   1. §12's gate (one root cause at four or more near-identical sites) agrees
#      between the design doc and visual-recap/SKILL.md's OPERATIVE body — the
#      frontmatter description is stripped before matching.
#   2. §12's two REQUIRED elements are present in its MARKUP: the all-units
#      matrix (reusing §11's .oc-matrix) and a note input as a real descendant
#      of every unit, with the id count floored against the unit count.
#   3. §12 obeys §10's stop-rule — no <script>, no innerHTML assignment, and
#      every unit a real <section>.
#   4. Every §12 unit uses a `u-` id, registered in the core's §4 registry.
#   5. The toggle subtraction stayed subtracted — detected by BEHAVIOR (any
#      `ba-` panel id, any handler that hides one comparison side) rather than
#      by the three literal names the deleted code happened to use.
#   6. The prose bar is wired: manifest row AND pointer, per skill.
#   7. The depth-vs-population distinction is stated in the core and the skill,
#      each pinned on a needle specific enough to disappear with the sentence.
#
# DELIBERATELY NOT ASSERTED: that the design doc and the skill word the gate
# identically beyond the threshold phrase. They should not — the doc carries
# the markup, the skill carries the decision.

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
span="$work/span"; markup="$work/markup"; outside="$work/outside"; skillbody="$work/skillbody"

# ---------------------------------------------------------------------------
# §12's span. Terminates on the NEXT `## ` heading of any kind, not on a
# numbered successor: §12 is the last numbered section, so `/^## 1[3-9]\./`
# ran to end-of-file and swept in `## Do's and Don'ts`. That let an assertion
# about §12 be satisfied by text outside it — the precise failure the span
# exists to prevent, in the other direction.
# ---------------------------------------------------------------------------
awk '/^## 12\./ { inside = 1; print; next } inside && /^## / { exit } inside' "$DESIGN" > "$span"
awk '/^## 12\./ { inside = 1; next } inside && /^## / { inside = 0 } !inside' "$DESIGN" > "$outside"

# §12's MARKUP only — the fenced html blocks, with the surrounding prose
# removed. Rule (a): a requirement about the skeleton an agent copies must be
# read from the skeleton, never from the sentence that describes it.
awk '/^```html$/ { fence = 1; next } /^```$/ { fence = 0; next } fence' "$span" > "$markup"

# visual-recap/SKILL.md with its YAML frontmatter stripped. The gate phrases
# also appear in the `description:`, which is a trigger string, not an
# instruction — matching there certified an instruction that had been deleted.
awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' "$SKILL" > "$skillbody"

span_lines="$(wc -l < "$span" | tr -d ' ')"
markup_lines="$(wc -l < "$markup" | tr -d ' ')"
body_lines="$(wc -l < "$skillbody" | tr -d ' ')"

# Non-vacuity floors. Every assertion below greps one of these extracts; an
# empty extract makes the absent-checks pass and only the found-checks fail,
# which reads as "three problems" instead of "the extractor broke".
[ "${span_lines:-0}" -ge 40 ] \
    || fatal "§12 extracted to only ${span_lines:-0} line(s) of $DESIGN — the section is absent or the heading shape changed."
[ "${markup_lines:-0}" -ge 20 ] \
    || fatal "§12's fenced markup extracted to only ${markup_lines:-0} line(s) — the fence shape changed, and every markup assertion below would be measuring nothing."
[ "${body_lines:-0}" -ge 40 ] \
    || fatal "$SKILL body extracted to only ${body_lines:-0} line(s) after stripping frontmatter — the frontmatter delimiters changed."
# The span must NOT reach the closing prose section. This is the regression
# guard for the end-of-file bug described in the header.
if grep -qF "Do's and Don'ts" "$span"; then
    fatal "§12's span swept in the Do's-and-Don'ts section — the terminator is wrong again, and assertions about §12 can be satisfied from outside it."
fi
ok "§12 extracted: $span_lines lines of prose+markup, $markup_lines lines of markup"

# ---------------------------------------------------------------------------
section "the gate agrees between the design doc and the skill's operative body"
# ---------------------------------------------------------------------------
assert_found "four or more near-identical sites" "$span"      "§12 states the site threshold"
assert_found "four or more near-identical sites" "$skillbody" "the skill's body states the same threshold"
assert_found "one root cause"                    "$span"      "§12 states the one-root-cause condition"
assert_found "one root cause"                    "$skillbody" "the skill's body states the same condition"
assert_found "Then choose the axis"              "$skillbody" "the skill's Step 3 carries the axis question itself"

# ---------------------------------------------------------------------------
section "§12's two required elements are present in its MARKUP, not its prose"
# ---------------------------------------------------------------------------
assert_found "oc-matrix" "$markup" "§12's skeleton renders the all-units matrix"

# §11 owns the CSS rule. Assert the RULE (with its brace) outside §12, so
# deleting §11's style block cannot be masked by §12's own class attribute.
if grep -qF '.oc-matrix{' "$outside"; then ok "§11 still defines the .oc-matrix rule §12 reuses"
else bad "§11 still defines the .oc-matrix rule §12 reuses" "no '.oc-matrix{' outside §12 — the matrix would render unstyled"; fi

# The serializer: §7's review block must still wire the button, and §12 must
# still point at it.
assert_found 'onclick="copyFeedback()"' "$outside" "§7's review block still wires the Copy feedback button"
assert_found "copyFeedback"             "$span"   "§12 points at the core's copy-feedback serializer"

# `|| true` inside the substitution: with `set -o pipefail`, a zero-match grep
# aborts the run here rather than letting the floor below report "found 0 units".
# Third instance of that shape in this file — see the census guard above.
unit_headers="$( { grep -oE '<section id="unit-' "$markup" || true; } | wc -l | tr -d ' ')"
if [ "${unit_headers:-0}" -lt 2 ]; then
    bad "§12's worked example renders at least two units" \
        "found ${unit_headers:-0}; a one-unit example cannot demonstrate a series"
else
    ok "§12's worked example renders $unit_headers units"
fi

# Multi-line descendant walk: the §4 serializer calls querySelector, so an
# input past the unit's closing tag serializes nothing while a line-wise grep
# still passes.
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
  }' "$markup")"
assert_eq "$unit_headers" "$scoped_notes" "every unit contains a note input as a descendant"

# ---------------------------------------------------------------------------
section "§12 obeys §10's stop-rule — sections, not a router"
# ---------------------------------------------------------------------------
# Read from $markup: §12's prose forbids a script and an innerHTML swap BY
# NAME, so a needle run over the span matches the rule that forbids the shape.
assert_absent "<script"          "$markup" "§12's skeleton ships no JavaScript"
assert_absent "addEventListener" "$markup" "§12's skeleton installs no keyboard stepper"
if grep -qE 'innerHTML[[:space:]]*=' "$markup"; then
    bad "§12's skeleton contains no innerHTML assignment" "the router shape §10 forbids is present"
else
    ok "§12's skeleton contains no innerHTML assignment"
fi
assert_found  "No framework" "$outside" "§10's stop-rule is still stated"

if [ "${unit_headers:-0}" -ge 2 ]; then
    ok "§12 renders $unit_headers units as real <section> elements"
else
    bad "§12 renders every unit as a real <section>" "a stage swapped in place is the router §10 forbids"
fi

# ---------------------------------------------------------------------------
section "the unit id shape agrees between its registry and its use"
# ---------------------------------------------------------------------------
assert_found 'u-<unit-slug>' "$CORE" "core registers the u- id shape"

# The FLOOR is the point. The previous version initialized bad_ids=0 and
# incremented only for a malformed id, so deleting every id passed — the
# vacuity that made this assertion decoration.
unit_ids="$( { grep -E '<section id="unit-' "$markup" || true; } \
    | { grep -oE 'data-feedback-id="[^"]+"' || true; } | wc -l | tr -d ' ')"
assert_eq "$unit_headers" "$unit_ids" "every unit section carries a data-feedback-id"

kinded="$( { grep -E '<section id="unit-' "$markup" || true; } \
    | { grep -cF 'data-feedback-kind="unit"' || true; } )"
assert_eq "$unit_headers" "$kinded" "every unit section declares data-feedback-kind=unit"

bad_ids=0
while IFS= read -r id; do
    case "$id" in
        u-*) ;;
        *) bad_ids=$((bad_ids + 1)); printf '       non-conforming id: %s\n' "$id" ;;
    esac
done < <( { grep -E '<section id="unit-' "$markup" || true; } \
          | { grep -oE 'data-feedback-id="[^"]+"' || true; } | sed 's/.*"\(.*\)"/\1/')
assert_eq "0" "$bad_ids" "every unit id in §12 uses the u- prefix"

# ---------------------------------------------------------------------------
section "the toggle subtraction stayed subtracted — detected by behavior"
# ---------------------------------------------------------------------------
# The first version censused three literal names (`setSide`, `ba-thumb`,
# `toggle variant`). Reinstating a working hide-one-side toggle under the
# handler name `showSide` passed it. What makes the toggle the sequential-
# display anti-pattern is not its name — it is that one comparison state is
# hidden. So detect THAT: any `ba-` panel id, and any handler assigning to
# `.hidden`. The census reads every tracked markdown file, not four
# directories; docs/solutions/ and CHANGELOG.md are history and are excluded.
# `|| true` on each stage: under `set -e` a failing `git ls-files` (run outside a
# repository) or a zero-match `grep` aborts the script at this line, BEFORE the
# floor below can report why. That is the dead-guard shape
# scripts/test-guards-can-fire.sh exists for — the guard names what it protects
# and cannot fire. Found by running this suite in a non-git scratch tree.
live_md="$( { git ls-files '*.md' 2>/dev/null || true; } \
    | { grep -v '^docs/solutions/' || true; } \
    | { grep -v '^CHANGELOG.md$' || true; } )"
[ -n "$live_md" ] || fatal "the tracked-markdown census came back empty — not a git repository, or the glob is wrong. Every assertion in this section would be vacuous."

# What makes the toggle the anti-pattern is that one COMPARISON state is
# hidden. Two earlier drafts of this detector matched the WORDS rather than the
# shape and produced two false positives, both found by running it:
#   - `\.hidden *=` flagged the core serializer's `ta.hidden = false`, which
#     REVEALS the clipboard fallback textarea — the opposite behavior.
#   - `hidden.*after` flagged shape/SKILL.md's prose "Probe hidden functions …
#     only surface after rollout." In a repo whose product is English, a
#     detector built from English words is a detector built from noise.
# So every form below is anchored to MARKUP: a `ba-` panel id, a `hidden`
# attribute on an element whose id names a comparison side, or a DOM lookup of
# such an element. Both false positives are pinned as self-tests below.
detect_hidden_side() {   # stdin: file text. stdout: offending lines.
    grep -nE 'id="ba-|getElementById\('"'"'[^'"'"']*(before|after)|id="[^"]*(before|after)[^"]*"[^>]*[[:space:]]hidden|[[:space:]]hidden[^>]*id="[^"]*(before|after)|toggle variant' || true
}

toggle_hits=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(detect_hidden_side < "$f")"
    if [ -n "$hits" ]; then toggle_hits="$toggle_hits$f: $hits"$'\n'; fi
done <<< "$live_md"
if [ -n "$toggle_hits" ]; then
    bad "no live document reinstates a hide-one-side comparison" "$(printf '%s' "$toggle_hits" | tr '\n' ' ')"
else
    ok "no live document reinstates a hide-one-side comparison"
fi

assert_found "sec-compare-<slug>" "$DESIGN" "§7's section id carries a slug so a comparison can repeat"

# ---------------------------------------------------------------------------
section "the prose bar is wired into both rendering skills"
# ---------------------------------------------------------------------------
for skill in visual-recap walk-commits; do
    rows="$(awk -v s="$skill" '!/^[[:space:]]*#/ && $1 == "docs/writing-for-humans.md" && $2 == s' "$MANIFEST" | wc -l | tr -d ' ')"
    assert_eq "1" "$rows" "$skill has exactly one writing-for-humans manifest row"
    if [ -f "$skill/references/writing-for-humans.md" ]; then
        ok "$skill/references/writing-for-humans.md exists"
    else
        bad "$skill/references/writing-for-humans.md exists" "run scripts/sync-skill-references.sh"
    fi
done

assert_found "references/writing-for-humans.md" "$skillbody" "visual-recap's body points at the bundled prose bar"
assert_found "references/writing-for-humans.md" "$WALK"      "walk-commits points at the bundled prose bar"

# ---------------------------------------------------------------------------
section "depth and population are distinguished, on needles that die with the sentence"
# ---------------------------------------------------------------------------
# The previous needle was the bare word "population", which survives in the §3
# vocabulary row — so deleting the §5 bullet that #304 asked for passed.
assert_found "per-unit series"                       "$CORE"      "the core's vocabulary names the block"
assert_found "The budget measures depth, not population" "$CORE"  "the core carries the depth-vs-population bullet"
assert_found "never a population cap"                "$skillbody" "the skill states the budget is depth, not population"

# ---------------------------------------------------------------------------
section "the zero-hit detectors still detect (self-test)"
# ---------------------------------------------------------------------------
# Three detectors above have a healthy state of ZERO hits, which is exactly the
# state that rots silently. Plant the shape each exists to find and require a
# hit; plant a near-miss and require silence.

planted_toggle='<div id="ba-before"></div>
<button onclick="showSide(and)">After</button>'
clean_columns='<div style="display:grid;grid-template-columns:1fr 1fr">
<div>Before</div><div>After</div></div>'
if [ -n "$(printf '%s' "$planted_toggle" | detect_hidden_side)" ]; then
    ok "the hide-one-side detector flags a renamed toggle"
else
    fatal "the hide-one-side detector no longer matches a reinstated toggle — its section above now passes everything."
fi
if [ -z "$(printf '%s' "$clean_columns" | detect_hidden_side)" ]; then
    ok "the hide-one-side detector leaves labeled columns alone"
else
    fatal "the hide-one-side detector flags the CORRECT form, so the shape it prescribes does not clear it."
fi

# The exact false positive the first run of this detector produced. Pinned so a
# future widening of the regex cannot silently re-acquire it.
serializer_reveal='ta.value = blob; ta.hidden = false; ta.select();'
if [ -z "$(printf '%s' "$serializer_reveal" | detect_hidden_side)" ]; then
    ok "the hide-one-side detector ignores the serializer revealing its fallback textarea"
else
    fatal "the hide-one-side detector flags \`ta.hidden = false\`, which REVEALS an element — the detector is matching the word, not the behavior."
fi

# The second false positive: ordinary English using both words. In a repo whose
# product is prose, this near-miss is the one most likely to recur.
english_prose='Probe hidden functions for stability failures — omissions that only surface after rollout.'
if [ -z "$(printf '%s' "$english_prose" | detect_hidden_side)" ]; then
    ok "the hide-one-side detector ignores English prose using \"hidden\" and \"after\""
else
    fatal "the hide-one-side detector flags ordinary prose — it is matching words, not markup, and every skill body is a false positive."
fi

# A toggle that renames the handler AND the ids still hides a comparison side
# through the attribute form. This is the evasion the literal-name census missed.
renamed_attr='<div id="cmp-after" hidden>after state</div>'
if [ -n "$(printf '%s' "$renamed_attr" | detect_hidden_side)" ]; then
    ok "the hide-one-side detector flags a hidden attribute on a comparison side"
else
    fatal "the hide-one-side detector misses the attribute form, which is the evasion the literal-name census already failed on."
fi

planted_script='<section id="unit-x"><script>var a = 1</script></section>'
if printf '%s' "$planted_script" | grep -qF '<script'; then
    ok "the no-JavaScript needle matches a planted script tag"
else
    fatal "the <script absence check cannot fire."
fi

planted_ih='<div id="stage"></div>
stage.innerHTML = units[i]'
if printf '%s' "$planted_ih" | grep -qE 'innerHTML[[:space:]]*='; then
    ok "the innerHTML-assignment regex matches a planted router"
else
    fatal "the innerHTML-assignment regex cannot fire."
fi
if printf '%s' 'the rule forbids an innerHTML swap' | grep -qE 'innerHTML[[:space:]]*='; then
    fatal "the innerHTML-assignment regex matches PROSE mentioning innerHTML — it would fire on the rule that forbids the shape."
else
    ok "the innerHTML-assignment regex ignores prose that merely names innerHTML"
fi

# ---------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
