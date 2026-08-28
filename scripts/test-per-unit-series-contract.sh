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
#   5. The toggle subtraction stayed subtracted — detected by SHAPE (a `ba-`
#      panel id, `display:none`, or a `hidden`/`aria-hidden` attribute on an
#      element whose id names a comparison side) rather than by the three literal
#      names the deleted code happened to use. The detector carries its own WHAT
#      THIS DOES NOT CATCH note: the class is narrowed, not closed.
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

# The gate is restated at five live surfaces. Review found it pinned at two and
# already drifted at a third: README.md rendered it as "four or more sites",
# dropping "near-identical" — the qualifier §12 says keeps the gate deliberately
# high. Enumerate the surfaces and hold them all to the same phrase.
# coverage: enumerated — the files that must agree on this block's trigger.
# Not derivable: "the surfaces that restate the gate" is a property of the
# contract, not something a scan of the tree can find.
for f in "$CORE" "$WALK" README.md SYSTEM-OVERVIEW.md; do
    assert_found "four or more near-identical sites" "$f" \
        "$f states the gate with its near-identical qualifier"
done

# walk-commits shares the rendering core, so a sweep walked commit-by-commit
# needs the same route to §12. It had none: it named §11 and stopped.
assert_found "per-unit series" "$WALK" "walk-commits routes a sweep to the per-unit series"
assert_found "§12"             "$WALK" "walk-commits names the block by section number"

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
# ONE detector, called by the assertion here AND by its self-tests below. The
# first version re-typed each needle into its fixture, so typo-ing the operative
# needle left all three self-tests green while a planted router shipped — a check
# satisfied by a decorative copy of the thing it names, which is this file's own
# subject arriving one level up. `detect_hidden_side` below already had the right
# shape; these did not.
#
# Read from $markup, and strip HTML comments first: §12's skeleton carries the
# comment "No stage, no innerHTML swap", and a detector that fires on the sentence
# forbidding a shape is prose-satisfies-markup in reverse.
detect_router() {   # stdin: markup. stdout: offending lines.
    sed 's/<!--.*-->//g' \
        | grep -nE '<script|addEventListener|innerHTML[[:space:]]*=' || true
}

router_hits="$(detect_router < "$markup")"
if [ -n "$router_hits" ]; then
    bad "§12's skeleton ships no router" \
        "§10 forbids a script, a listener, and an innerHTML swap: $(printf '%s' "$router_hits" | tr '\n' ' ')"
else
    ok "§12's skeleton ships no router (no <script>, no listener, no innerHTML assignment)"
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
#
# WIDENED after review. The first version keyed on `before|after` naming plus a
# `hidden` attribute, and a working toggle using `old`/`new` ids with
# `style="display:none"` walked straight through it. Side names are arbitrary, so
# the id half now covers the pairs an author actually reaches for, and the hiding
# half covers the three ways to hide a node in a self-contained file.
#
# `display:none` is flagged only when it sits on an element whose id names a
# comparison side — round 3 tried it unconditional, and ordinary prose
# ("Never hide a pane with display:none") plus a print stylesheet both went
# red. In a repo whose product is English, an unanchored token is noise; the
# near-miss self-tests below pin that prose sentence alongside the earlier
# false positives (`aria-hidden` on a glyph, `classList` on an active state).
#
# The `getElementById` arm requires the lookup to be FOLLOWED by a hide on the
# same statement — `.hidden` or `.style.display`. Without that it fired on
# `getElementById('dk-prev')`, the walkthrough deck's pager button (§D3/§D8):
# `prev`/`next` are in SIDE because a comparison half can be named that way, but
# a pager control is not a comparison and disabling a button is not hiding a
# side. The real case it must still catch — `getElementById('ba-before').hidden
# = side === 'after'` — carries the hide on the same line, which is what makes
# the narrowing safe rather than a hole.
#
# WHAT THIS DOES NOT CATCH, stated so nobody over-trusts it: a side pair named
# outside the list (`a`/`b`, `v1`/`v2`), `display:none` on an element whose id
# does not name a side, hiding through a CSS class defined elsewhere,
# `visibility:hidden`, `height:0`, a `<details>` element, or a lookup and a hide
# split across two statements. This narrows the
# class; it does not close it — which is why the header above says "detected by
# SHAPE" rather than "any handler that hides one comparison side".
# Braced on every use: bare `$SIDE[` reads as array indexing to shellcheck (SC1087).
SIDE='(before|after|old|new|left|right|prev|next)'
detect_hidden_side() {   # stdin: file text. stdout: offending lines.
    grep -nE "id=\"ba-|toggle variant|id=\"[^\"]*${SIDE}[^\"]*\"[^>]*(display:none|[[:space:]](hidden|aria-hidden))|(display:none|[[:space:]](hidden|aria-hidden))[^>]*id=\"[^\"]*${SIDE}|getElementById\('[^']*${SIDE}[^)]*\)[^;]*\.(hidden|style\.display)|classList\.[a-z]+\('hidden'" || true
}

toggle_hits=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    # `git ls-files` lists tracked-but-DELETED paths, and redirecting from one
    # aborts the run right here — 40 lines before the writing-for-humans guard
    # below that exists to report exactly that, with an actionable message.
    # Third instance of the dead-guard shape in this file, and the one that
    # arrives through a redirect rather than a pipeline, so Detector D in
    # test-guards-can-fire.sh cannot see it either.
    [ -f "$f" ] || continue
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
section "§12's chip strip uses the tokens its prose binds"
# ---------------------------------------------------------------------------
# The prose named a `--flag-*` ramp while the example used `--flag-load` for
# `fixed` (which means load-bearing in the file tree) and `--risk` for `exempt`
# (not a --flag-* token at all). Two agents rendering the same sweep then pick
# different colors and the strip stops being readable across recaps — the
# Constancy of Design property the block leans on. The prose now states an
# explicit mapping; this holds the example to it.
# The expected tokens are PARSED from §12's own table, never re-typed here — a
# re-typed heredoc was round 3's finding: flipping the doc's `fixed` row to
# `--del` left this green, because the check compared the markup against this
# file's copy of the mapping instead of against the mapping. Rows are
# `| \`kind\` | \`--token\` |`; parse both columns.
# shellcheck disable=SC2016  # literal backticks in a grep pattern, not a command substitution
# Backticks are NOT escaped: GNU grep reads \` as a buffer-start anchor (a GNU
# extension), so the escaped form matches zero rows in CI while matching all
# five under BSD — the same toolchain divergence that made Detector D's guard
# green locally and red 20/20 in CI.
chip_rows="$( { grep -oE '^\| `[a-z]+` \| `--[a-z-]+`' "$span" || true; } \
    | sed 's/^| `\([a-z]*\)` | `\(--[a-z-]*\)`/\1|\2/' )"
chip_row_n="$(printf '%s\n' "$chip_rows" | { grep -c . || true; } )"
assert_eq "5" "$chip_row_n" "§12's chip table carries five kind rows"

# The rule §12 states — no two kinds share a token — checked by shape over the
# parsed rows, so it survives a reword and reddens on any future collision.
dup_tokens="$(printf '%s\n' "$chip_rows" | cut -d'|' -f2 | sort | uniq -d)"
if [ -n "$dup_tokens" ]; then
    bad "no two chip kinds share a token" "duplicated: $(printf '%s' "$dup_tokens" | tr '\n' ' ') — an exempt site and an open one would be indistinguishable at a glance"
else
    ok "no two chip kinds share a token"
fi

# Every chip the worked example RENDERS must use the token the parsed table
# binds to its kind. Kinds the example does not render (missed, open,
# mechanical today) cannot be held to anything until a unit uses one — stated
# rather than left to read as full coverage.
chip_violations=0
rendered_chips=0
while IFS='|' read -r kind token; do
    [ -n "$kind" ] || continue
    if grep -qE '>'"$kind"'</span>' "$markup"; then
        rendered_chips=$((rendered_chips + 1))
        if grep -qE 'var\('"$token"'\)[^>]*>'"$kind"'</span>' "$markup"; then
            ok "the rendered $kind chip uses $token (parsed from the table)"
        else
            chip_violations=$((chip_violations + 1))
            bad "the rendered $kind chip uses $token" "§12's table binds $kind to $token; the worked example disagrees"
        fi
    fi
done <<EOF
$chip_rows
EOF
[ "${rendered_chips:-0}" -ge 2 ] \
    || bad "the worked example renders at least two chips from the table" \
           "found ${rendered_chips:-0}; the per-chip loop above was a universal over an empty set"
assert_eq "0" "$chip_violations" "every chip rendered in §12 matches the mapping its prose states"

# The sub-population rule came out of §12's first real use: the gate reads as
# "is this DIFF a sweep", and the case that actually occurred was a sweep inside
# a diff that was not one. Deleting the paragraph left the suite green.
assert_found "sub-population" "$span" "§12 states that the sweep may be a sub-population of the diff"
assert_found "must not share a token" "$span" "§12 states why exempt and open cannot share a token"
# §6's carve-out is the contradiction this branch was opened to fix: §12's
# exempt unit renders a lone `good` half, which §6's general rule outlaws.
# Deleting the exception paragraph went green in round 3.
assert_found "The exception is a §12 \`exempt\` unit" "$outside" "§6 carves out the exempt unit's lone good half"

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

clean_columns='<div style="display:grid;grid-template-columns:1fr 1fr">
<div>Before</div><div>After</div></div>'
if [ -z "$(printf '%s' "$clean_columns" | detect_hidden_side)" ]; then
    ok "the hide-one-side detector leaves labeled columns alone"
else
    fatal "the hide-one-side detector flags the CORRECT form, so the shape it prescribes does not clear it."
fi

# The exact false positive the first run of this detector produced. Pinned so a
# future widening of the regex cannot silently re-acquire it.


# A toggle that renames the handler AND the ids still hides a comparison side
# through the attribute form. This is the evasion the literal-name census missed.
toggle_rows=0
while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    toggle_rows=$((toggle_rows + 1))
    if [ -n "$(printf '%s' "$fixture" | detect_hidden_side)" ]; then
        ok "the hide-one-side detector flags $label"
    else
        fatal "the hide-one-side detector misses $label — an evasion review already demonstrated."
    fi
done <<'TOGGLES'
a hidden attribute on a comparison side|<div id="cmp-after" hidden>after state</div>
old/new naming with display:none|<div id="cmp-thumb-new" style="display:none">new</div>
a left/right pair hidden by attribute|<div id="pane-right" hidden></div>
a DOM lookup of a comparison side|document.getElementById('prev-state').hidden = true
TOGGLES
[ "${toggle_rows:-0}" -ge 4 ] \
    || fatal "the TOGGLES table ran only ${toggle_rows:-0} row(s) — an emptied body passes silently, and the evasions review demonstrated would go unpinned."

# Four near-misses: the two false positives this detector produced while being
# built, plus the two legitimate constructs the widening put at risk.
legit_rows=0
while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    legit_rows=$((legit_rows + 1))
    if [ -z "$(printf '%s' "$fixture" | detect_hidden_side)" ]; then
        ok "the hide-one-side detector ignores $label"
    else
        fatal "the hide-one-side detector flags $label — it is matching a word or a legitimate construct, not the anti-pattern."
    fi
done <<'LEGIT'
the serializer revealing its fallback textarea|ta.value = blob; ta.hidden = false; ta.select();
English prose using hidden and after|Probe hidden functions for failures that only surface after rollout.
prose naming display:none as the thing not to do|Never hide a pane with display:none.
a print stylesheet hiding the rail|@media print{.rail{display:none}}
aria-hidden on a decorative glyph|<span aria-hidden="true">lock</span>
classList toggling the active state|el.classList.remove('is-active')
LEGIT
[ "${legit_rows:-0}" -ge 6 ] \
    || fatal "the LEGIT table ran only ${legit_rows:-0} row(s) — an emptied body passes silently, and the recorded false positives could silently re-acquire."

# Every fixture goes through detect_router — the SAME function the assertion
# above calls. Typo the operative regex and every row here reddens, which is the
# whole point and was not true of the version these replaced.
router_rows=0
while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    router_rows=$((router_rows + 1))
    if [ -n "$(printf '%s' "$fixture" | detect_router)" ]; then
        ok "the router detector flags $label"
    else
        fatal "the router detector no longer matches $label — the stop-rule assertion above now passes everything."
    fi
done <<'ROUTERS'
a planted script tag|<section id="unit-x"><script>var a = 1</script></section>
a planted stage swap|stage.innerHTML = units[i]
a planted keyboard stepper|document.addEventListener('keydown', next)
ROUTERS
[ "${router_rows:-0}" -ge 3 ] \
    || fatal "the ROUTERS table ran only ${router_rows:-0} row(s) — an emptied body passes silently, and the router detector would be certified by nothing."

# Near-misses. §12's skeleton really does carry a comment forbidding the swap, so
# a detector that fires on it makes the doc unable to state its own rule.
nearmiss_rows=0
while IFS='|' read -r label fixture; do
    [ -n "$label" ] || continue
    nearmiss_rows=$((nearmiss_rows + 1))
    if [ -z "$(printf '%s' "$fixture" | detect_router)" ]; then
        ok "the router detector ignores $label"
    else
        fatal "the router detector flags $label — it is matching the rule rather than the violation."
    fi
done <<'NEARMISS'
the comment forbidding a stage swap|<!-- One real section per unit. No stage, no innerHTML swap. -->
prose that merely names innerHTML|the rule forbids an innerHTML swap
NEARMISS
[ "${nearmiss_rows:-0}" -ge 2 ] \
    || fatal "the NEARMISS table ran only ${nearmiss_rows:-0} row(s) — an emptied body passes silently, and the prose near-misses would go unpinned."

# ---------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
