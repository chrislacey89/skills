#!/usr/bin/env bash
# The needles here are HTML, JavaScript, and jq, full of quotes and dollars.
# shellcheck disable=SC2016
# test-staged-scene-contract.sh — contract test for /visual-recap's staged
# scene (visual-recap-design.md §18, chrislacey89/skills#798).
#
#   bash scripts/test-staged-scene-contract.sh               run the suite
#   bash scripts/test-staged-scene-contract.sh --emit <file> write the §18
#                                                            example as a page
#
# THE DRIFT CLASS: a vivid picture that carries more than the plan does. A
# scene draws what does not exist yet and shows it moving, so it reads as
# settled. It stays honest through structure, and every piece of that structure
# is easy to lose when the example is edited: a step with no source, a view put
# behind a control, a list that falls behind its frame, a static frame that
# disagrees with the data the script plays. The example is copied verbatim into
# artifacts, so what is wrong in it ships in every scene.
#
# THE STATE IS WRITTEN TWICE, on purpose. The markup holds each view's last
# frame so the page reads with no script, and the data holds the steps the
# script plays. The suite computes each last frame from the data and compares
# it with the markup, which is what keeps the two one picture.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. §18 is the last numbered block, and core §3, core §4, and SKILL.md
#      carry it.
#   2. The example, as markup alone: views present and visible, the key above
#      them, one list item per step with the same caption and source, every
#      step cited or marked, each view's split and chip, the example-values
#      label, every token defined in §1.
#   3. The script: closed to the network and to storage, no handle on what is
#      visible, and, under node, parsed and run: nothing plays by itself, Next
#      moves one view one step, and the last step is the authored frame.
#   4. SKILL.md Step 1 maps each category of shape/SKILL.md's closing summary.
#
# WHAT IT DOES NOT CHECK: that a caption is true or that a picture is clear.
# No prose is searched for a rule's wording
# (docs/solutions/testing-patterns/a-planted-term-cannot-discriminate-meaning-2026-09-04.md).
# The one number it reads from prose is core §1's chip bar, and it stops when
# that is no longer two-thirds.
#
# node is optional locally: without it the parse check, which also runs the
# script it parsed, prints one SKIP line and everything else still runs.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

emit_to=""
case "${1:-}" in
    "") ;;
    --emit)
        [ -n "${2:-}" ] || { printf 'usage: bash scripts/test-staged-scene-contract.sh [--emit <file>]\n' >&2; exit 2; }
        case "$2" in /*) emit_to="$2" ;; *) emit_to="$PWD/$2" ;; esac ;;
    *) printf 'usage: bash scripts/test-staged-scene-contract.sh [--emit <file>]\n' >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1
DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md
SKILL=visual-recap/SKILL.md
SHAPE=shape/SKILL.md

pass=0; fail=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()    { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()   { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
clean() { if [ -z "$2" ]; then ok "$1"; else bad "$1" "$2"; fi; }
flags() { if [ -n "$2" ]; then ok "self-test, caught: $1"; else bad "self-test, missed: $1" "the detector printed nothing for a broken copy"; fi; }
fatal() { printf '  FATAL %s\n' "$1" >&2; printf '\n---\n%d passed, %d failed\n' "$pass" "$((fail + 1))"; exit 1; }

# --- readers -----------------------------------------------------------------

# span <start-regex> <end-regex>: stdin from the start line up to the end line.
span() { awk -v s="$1" -v e="$2" 'on && $0 ~ e {exit} !on && $0 ~ s {on = 1} on'; }
# html_fences: the bodies of every html fence, in order.
html_fences() { awk '/^```html$/ {on = 1; next} on && /^```$/ {on = 0; next} on'; }
first_html_fence() { awk '/^```html$/ {on = 1; next} on && /^```$/ {exit} on'; }
scene_data() { awk '/^<script type="application\/json" data-scene>$/ {on = 1; next} on && /^<\/script>$/ {exit} on'; }
scene_script() { awk '/^<script>$/ {on = 1; next} on && /^<\/script>$/ {exit} on'; }
scene_css() { awk '/^<style>$/ {on = 1; next} on && /^<\/style>$/ {exit} on'; }
without_scripts() { awk '/^<script/ {on = 1} !on {print} /^<\/script>$/ {on = 0}'; }
# view_markup <id>: one view's section, from the markup on stdin.
view_markup() { awk -v v="data-view=\"$1\"" '/<section / && index($0, v) {on = 1} on {print} on && /<\/section>/ {exit}'; }
# attr <name>: that attribute's value on each line that has it.
attr() { sed -nE "s/.* $1=\"([^\"]*)\".*/\1/p"; }
# inner <marker>: the text of the first element on each line whose tag has the marker.
inner() { sed -nE "s/.*<[^>]*$1[^>]*>([^<]*)<.*/\1/p"; }
unescape() { sed -e 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&amp;/\&/g'; }

design_s18="$(span '^## 18[.] Block: staged scene' '^## ' <"$DESIGN")"
[ -n "$design_s18" ] || fatal "$DESIGN has no '## 18. Block: staged scene' section"
example="$(html_fences <<<"$design_s18")"
[ -n "$example" ] || fatal "§18 has no html example"
tokens="$(span '^## 1[.] ' '^## 2[.] ' <"$DESIGN" | first_html_fence)"
[ -n "$tokens" ] || fatal "§1 has no token block"

page() {
    printf '%s\n' '<!doctype html>' '<html lang="en">' '<meta charset="utf-8">' \
        '<meta name="viewport" content="width=device-width, initial-scale=1">' \
        '<title>Staged scene example</title>'
    printf '%s\n' "$tokens"
    printf '%s\n' '<body style="background:var(--bg);color:var(--fg);font-family:var(--sans);padding:var(--s4)">'
    printf '%s\n' "$example" '</body>' '</html>'
}

if [ -n "$emit_to" ]; then
    page >"$emit_to" || { printf 'could not write %s\n' "$emit_to" >&2; exit 1; }
    printf 'wrote %s\n' "$emit_to"
    exit 0
fi

command -v jq >/dev/null 2>&1 || fatal "jq is required"
tmp="$(mktemp -d)" || fatal "could not create a temp directory"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

markup="$(without_scripts <<<"$example")"
data="$(scene_data <<<"$example")"
script="$(scene_script <<<"$example")"
css="$(scene_css <<<"$example")"
[ -n "$script" ] || fatal "§18 has no script"
[ -n "$css" ] || fatal "§18 has no style block"
jq -e '.views | type == "array" and length > 0' <<<"$data" >/dev/null 2>&1 || fatal "§18's scene data is not JSON with views"
slug="$(jq -r '.id' <<<"$data")"
view_ids="$(jq -r '.views[].id' <<<"$data")"

# -----------------------------------------------------------------------------
section "§18 is the last numbered block and is registered"
# -----------------------------------------------------------------------------
check "§18 follows §17 and nothing numbered follows it" "17 18" \
    "$(sed -n '/^# Part II/q; p' "$DESIGN" | sed -nE 's/^## ([0-9]+)[.] .*/\1/p' | tail -2 | paste -sd' ' -)"
check "Do's and Don'ts follows §18" "## Do's and Don'ts" \
    "$(awk '/^## 18[.] / {on = 1; next} on && /^## / {print; exit}' "$DESIGN")"
if grep -qF '§18' < <(span '^## §D2[.] ' '^## §D3[.] ' <"$DESIGN"); then ok "§D2 places §18 in a deck"; else bad "§D2 does not mention §18"; fi
if grep -qE '^\| \*\*staged scene\*\* \|.*forward-looking' "$CORE"; then ok "core §3's table has a forward-looking staged scene row"; else bad "core §3's table has no forward-looking staged scene row"; fi

class="$(span '^### Forward-looking blocks' '^---$' <"$CORE")"
members="$(sed -nE 's/^- the \*\*([^*]+)\*\*.*/\1/p' <<<"$class" | sort)"
rows="$(sed -nE '/forward-looking/ s/^\| \*\*([^*]+)\*\* \|.*/\1/p' "$CORE" | sort)"
check "core §1's class list is §3's forward-looking rows" "$rows" "$members"
if grep -qxF 'staged scene' <<<"$members"; then ok "core §1 lists the staged scene in the class"; else bad "core §1's class list lacks the staged scene" "$members"; fi
if grep -qF 'visual-recap-design.md` §18' < <(span '^## 6[.] ' '^## 7[.] ' <"$CORE"); then ok "core §6 names §18"; else bad "core §6 does not name §18"; fi

registry="$(span '^### Stable ids' '^### The Copy-feedback' <"$CORE")"
for shape in 'scene-<slug>' 'scene-<slug>/<view>'; do
    if grep -qF "\`$shape\`" <<<"$registry"; then ok "core §4 registers $shape"; else bad "core §4 does not register $shape"; fi
done

# -----------------------------------------------------------------------------
section "every view is in the document and visible, with the script removed"
# -----------------------------------------------------------------------------
n_views="$(jq '.views | length' <<<"$data")"
if [ "$n_views" -ge 2 ]; then ok "the example has $n_views views"; else bad "the example has fewer than two views"; fi
check "the markup has one frame per view, in the data's order" "$view_ids" "$(grep -F '<section class="vr-scene-view"' <<<"$markup" | attr data-view)"

# visibility_defects <markup> <css> <script>: one line per way to hide a view.
visibility_defects() {
    local elements
    elements="$(awk '/^<style>$/ {on = 1} !on {print} /^<\/style>$/ {on = 0}' <<<"$1")"
    grep -nE '[[:space:]]hidden([=[:space:]>]|$)|display:[[:space:]]*none|visibility:[[:space:]]*(hidden|collapse)|opacity:[[:space:]]*0([;}" ]|$)|<details|role="tab|type="radio"' <<<"$elements" | sed 's/^/markup /'
    grep -nE 'display:[[:space:]]*none|visibility:[[:space:]]*(hidden|collapse)|opacity:[[:space:]]*0([;} ]|$)|content-visibility' <<<"$2" | sed 's/^/css /'
    grep -nE 'hidden|display|visibility|opacity|classList|className|cssText|innerHTML|outerHTML|replaceChildren|[.]remove[(]' <<<"$3" | sed 's/^/script /'
}
clean "nothing in the markup, CSS, or script can hide a view" "$(visibility_defects "$markup" "$css" "$script")"
flags "a hidden view" "$(visibility_defects "${markup/<section class=\"vr-scene-view\"/<section hidden class=\"vr-scene-view\"}" "$css" "$script")"
flags "a display:none rule" "$(visibility_defects "$markup" "$css
.vr-scene-view.is-off{display:none}" "$script")"
flags "a handler that toggles a class" "$(visibility_defects "$markup" "$css" "$script
view.classList.toggle('is-off');")"

key_line="$(grep -nF 'class="vr-scene-key"' <<<"$markup" | head -1 | cut -d: -f1)"
first_view="$(grep -nF '<section class="vr-scene-view"' <<<"$markup" | head -1 | cut -d: -f1)"
if [ "${key_line:-999999}" -lt "${first_view:-0}" ]; then ok "the key sits above the first frame"; else bad "the key is not above the first frame"; fi

check "the figure's id has the registered shape" "scene-$slug" "$(grep -F '<figure class="vr-scene"' <<<"$markup" | attr data-feedback-id)"
fig_note="$(grep -nF 'data-feedback-note' <<<"$markup" | head -1 | cut -d: -f1)"
if [ "${fig_note:-999999}" -lt "${first_view:-0}" ]; then ok "the scene's own note is the first one the serializer finds"; else bad "the scene has no note of its own before its views"; fi

while IFS= read -r v; do
    [ -n "$v" ] || continue
    vm="$(view_markup "$v" <<<"$markup")"
    check "$v: the view's id" "scene-$slug/$v" "$(grep -F '<section ' <<<"$vm" | attr data-feedback-id)"
    for part in '<svg role="img"' 'aria-label="' 'class="vr-scene-cap" aria-live="polite"' '<ol class="vr-scene-steps">' 'data-feedback-note'; do
        if grep -qF -- "$part" <<<"$vm"; then ok "$v: the script-free page has $part"; else bad "$v: the script-free page lacks $part"; fi
    done
done <<<"$view_ids"

# -----------------------------------------------------------------------------
section "every step is cited or visibly asserted"
# -----------------------------------------------------------------------------
unmarked_items() {
    local li
    while IFS= read -r li; do
        grep -qE ' data-src="[^"]+"' <<<"$li" && continue
        grep -qE '<li[^>]* class="([^"]* )?asserted( [^"]*)?"' <<<"$li" && continue
        printf '%s\n' "$li"
    done < <(grep -E '<li[ >]')
}
# listed_steps: caption, source, and mark for each list item. A function
# because bash 3.2 cannot parse a case inside a command substitution.
listed_steps() {
    local li mark
    while IFS= read -r li; do
        mark=cited
        case "$li" in *'class="asserted"'*) mark=asserted ;; esac
        printf '%s | %s | %s\n' "$(inner 'class="vr-scene-c"' <<<"$li" | unescape)" "$(attr data-src <<<"$li" | unescape)" "$mark"
    done < <(grep -E '<li[ >]')
}
unmarked_steps() {
    jq -r '.views[] | .id as $v | .steps[]
        | select(.asserted != true and (((.src // []) | map(select(length > 0)) | length) == 0))
        | $v + ": " + .c'
}
clean "every list item has a source or the asserted class" "$(unmarked_items <<<"$markup")"
clean "every step in the data has a source or asserted: true" "$(unmarked_steps <<<"$data")"
one_src="$(grep -F '<li data-src="' <<<"$markup" | head -1 | attr data-src)"
[ -n "$one_src" ] || fatal "the example has no cited list item to build a fixture from"
flags "one list item's source removed" "$(unmarked_items <<<"${markup/<li data-src=\"$one_src\"/<li}")"
flags "one step's source removed" "$(jq '(first(.views[].steps[] | select(.asserted != true))).src = []' <<<"$data" | unmarked_steps)"

if grep -qF 'two-thirds or more of its cells asserted' <<<"$class"; then ok "core §1's chip bar is the one this suite computes"; else fatal "core §1's chip bar is no longer two-thirds; update the arithmetic here with it"; fi
if grep -qF 'visual-rendering-core.md` §1' <<<"$design_s18"; then ok "§18 points at core §1"; else bad "§18 does not point at core §1"; fi
clean "§18 does not restate the bar's number" "$(grep -niE 'two[ -]thirds|2/3|66 ?%|67 ?%' <<<"$design_s18")"

# chip_defect <chips> <asserted> <total>
chip_defect() {
    local want=0
    [ $((3 * $2)) -ge $((2 * $3)) ] && want=1
    [ "$1" -eq "$want" ] || printf '%s chips for %s of %s asserted\n' "$1" "$2" "$3"
}
chipped=0
while IFS= read -r v; do
    [ -n "$v" ] || continue
    vm="$(view_markup "$v" <<<"$markup")"
    total="$(jq --arg v "$v" '.views[] | select(.id == $v) | .steps | length' <<<"$data")"
    asserted="$(jq --arg v "$v" '[.views[] | select(.id == $v) | .steps[] | select(.asserted == true)] | length' <<<"$data")"
    check "$v: one list item per step" "$total" "$(grep -cE '<li[ >]' <<<"$vm")"
    check "$v: captions, sources, and marks match the data" \
        "$(jq -r --arg v "$v" '.views[] | select(.id == $v) | .steps[] | [.c, ((.src // []) | join("; ")), (if .asserted == true then "asserted" else "cited" end)] | join(" | ")' <<<"$data")" \
        "$(listed_steps <<<"$vm")"
    check "$v: the stated split" "$((total - asserted)) cited · $asserted asserted" "$(inner 'class="vr-scene-split"' <<<"$vm")"
    if [ "$asserted" -lt "$total" ]; then ok "$v: at least one cited step"; else bad "$v: no cited step"; fi
    chips="$(grep -cF 'class="vr-scene-chip"' <<<"$vm")"
    clean "$v: chipped exactly when core §1's bar says so" "$(chip_defect "$chips" "$asserted" "$total")"
    chipped=$((chipped + chips))
done <<<"$view_ids"
if [ "$chipped" -ge 1 ]; then ok "the example shows a chipped view to copy"; else bad "the example shows no chipped view"; fi
flags "two of three asserted and no chip" "$(chip_defect 0 2 3)"
flags "one of three asserted and a chip" "$(chip_defect 1 1 3)"
clean "two of three asserted and a chip passes" "$(chip_defect 1 2 3)"

# -----------------------------------------------------------------------------
section "each static frame is the last step of its data"
# -----------------------------------------------------------------------------
states='focus ok fail risk maybe dim new'
clean "the data uses the closed set of states" "$(jq -r --arg s "$states" '
    ($s | split(" ") + [""]) as $known
    | .views[] | (.init // {}), .steps[] | (.set // {})[] | . as $x
    | select(($known | index([$x])) == null)' <<<"$data")"

# expected_frame <view>: id|state|title|subtitle for each item the view shows.
expected_frame() {
    jq -r --arg v "$1" '
        .items as $items
        | (.views[] | select(.id == $v)) as $view
        | (reduce (($view.init // {}), $view.steps[]) as $d ({set: {}, text: {}};
            .set += ($d.set // {}) | .text += ($d.text // {}))) as $last
        | $items[]
        | select((.only // "") as $o | $o == "" or (($o | split(",") | index($v)) != null))
        | [.id, ($last.set[.id] // ""), ($last.text[.id + ".t"] // .t // ""), ($last.text[.id + ".s"] // .s // "")]
        | join("|")' <<<"$data"
}
drawn_frame() {
    local row
    while IFS= read -r row; do
        printf '%s|%s|%s|%s\n' "$(attr data-item <<<"$row")" "$(attr data-state <<<"$row")" \
            "$(inner 'data-slot="t"' <<<"$row" | unescape)" "$(inner 'data-slot="s"' <<<"$row" | unescape)"
    done < <(grep -F ' data-item="')
}
glyph_of() { grep -F "class=\"vr-scene-sw\" data-state=\"$1\"" <<<"$markup" | head -1 | inner 'class="vr-scene-sw"'; }

seen_glyphs=""
for st in $states; do
    g="$(glyph_of "$st")"
    if [ -n "$g" ]; then ok "the key draws '$st' with a glyph or tag"; else bad "the key has no glyph or tag for '$st'"; fi
    if grep -qF "\"$g\"" <<<"$script" || grep -qF "'$g'" <<<"$script"; then ok "the script draws the key's mark for '$st'"; else bad "the script does not draw the key's mark for '$st'"; fi
    if grep -qF "[data-state=\"$st\"]" <<<"$css"; then ok "the CSS styles '$st'"; else bad "the CSS has no rule for '$st'"; fi
    seen_glyphs="$seen_glyphs$g
"
done
clean "no two states share a mark" "$(sed '/^$/d' <<<"$seen_glyphs" | sort | uniq -d)"

while IFS= read -r v; do
    [ -n "$v" ] || continue
    vm="$(view_markup "$v" <<<"$markup")"
    check "$v: items, states, and text equal the last step" "$(expected_frame "$v")" "$(drawn_frame <<<"$vm")"
    while IFS= read -r row; do
        id="$(attr data-item <<<"$row")"; st="$(attr data-state <<<"$row")"
        want=""; [ -z "$st" ] || want="$(glyph_of "$st")"
        check "$v: $id draws the mark of its state" "$want" "$(inner 'class="vr-scene-g"' <<<"$row")"
    done < <(grep -F ' data-item="' <<<"$vm")
    marked="$(grep -cF 'data-example' <<<"$vm")"
    label="$(grep -cF 'class="vr-scene-ex"' <<<"$vm")"
    if { [ "$marked" -gt 0 ] && [ "$label" -eq 1 ]; } || { [ "$marked" -eq 0 ] && [ "$label" -eq 0 ]; }; then
        ok "$v: the example-values label is there exactly when an example value is"
    else
        bad "$v: example values and their label disagree" "$marked marked, $label labels"
    fi
done <<<"$view_ids"
if grep -qF 'data-example' <<<"$markup"; then ok "the example shows a marked example value"; else bad "the example shows no marked example value"; fi

# -----------------------------------------------------------------------------
section "§1 tokens only, and motion is opt-out"
# -----------------------------------------------------------------------------
undefined_tokens() {
    local used
    used="$(grep -oE 'var[(]--[a-z0-9-]+' | sed 's/var(//' | sort -u)"
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        grep -qF -- "$t:" <<<"$tokens" || printf '%s\n' "$t"
    done <<<"$used"
}
clean "every token §18 uses is defined in §1" "$(undefined_tokens <<<"$example")"
flags "a token §1 does not define" "$(undefined_tokens <<<"$example
.x{color:var(--editor-keyword)}")"
clean "§18 defines no color of its own" "$(grep -nE '#[0-9a-fA-F]{6}([^0-9a-zA-Z_-]|$)|(rgba?|hsla?)[(]' <<<"$css")"

reduced="$(awk '/@media[ ]*[(]prefers-reduced-motion:[ ]*reduce[)]/ {on = 1} on' <<<"$css")"
for rule in 'transition:none' 'animation:none'; do
    if grep -qF "$rule!important" <<<"$reduced"; then ok "reduced motion sets $rule"; else bad "reduced motion does not set $rule"; fi
done
clean "no transition is stronger than the reduced-motion rule" \
    "$(grep -nE '(transition|animation):[^;}]*!important' <<<"$css" | grep -vE '(transition|animation):none!important' )"

# -----------------------------------------------------------------------------
section "the script is closed, and plays only when asked"
# -----------------------------------------------------------------------------
closed_defects() {
    local word
    for word in 'fetch(' 'import ' 'import(' 'http' 'localStorage' 'sessionStorage' 'indexedDB' 'XMLHttpRequest' 'WebSocket' 'sendBeacon' '.cookie' 'new Image'; do
        if grep -qF -- "$word" <<<"$1"; then printf '%s\n' "$word"; fi
    done
}
clean "no network call and no storage" "$(closed_defects "$script")"
flags "a fetch" "$(closed_defects "$script
fetch(where);")"
autoplay_defects() {
    grep -nE 'setInterval|requestAnimationFrame|autoplay|IntersectionObserver|DOMContentLoaded|[.]animate[(]|[.]click[(]' <<<"$1"
    # tick is the only thing that advances by itself, and only play starts it.
    grep -nE 'setTimeout' <<<"$1" | grep -vF 'setTimeout(tick,'
    grep -nE '(^|[^A-Za-z])play[(][)]' <<<"$1" | grep -vE 'function play[(][)]'
}
clean "the script starts no playback by itself" "$(autoplay_defects "$script")"
flags "a call to play at load" "$(autoplay_defects "$script
play();")"

if ! command -v node >/dev/null 2>&1; then
    printf '  SKIP parse check: node is not on PATH, so the §18 script was not parsed and run\n'
else
    printf '%s\n' "$script" >"$tmp/scene.js"
    if node --check "$tmp/scene.js" 2>"$tmp/parse.err"; then
        ok "the script parses under node --check"
        page >"$tmp/page.html"
        # A document just big enough for the script: a tree, the selectors it
        # uses, and a clock that records what was scheduled.
        cat >"$tmp/run.js" <<'JS'
const fs = require('fs');
const [file, scriptFile] = process.argv.slice(2);
const key = k => 'data-' + k.replace(/[A-Z]/g, c => '-' + c.toLowerCase());
const decode = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
class El {
  constructor(tag, attrs = {}, text = '') {
    Object.assign(this, { tag, attrs, text, kids: [], parent: null, on: {} });
    this.dataset = new Proxy({}, { get: (_, k) => this.attrs[key(k)], set: (_, k, v) => { this.attrs[key(k)] = String(v); return true; } });
    this.style = new Proxy({}, { set: (_, k, v) => { if (k !== 'transform') throw new Error('script set style.' + k); this.attrs.style = k + ':' + v; return true; } });
  }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  removeAttribute(k) { delete this.attrs[k]; }
  get textContent() { return this.tag === '#' ? this.text : this.kids.map(k => k.textContent).join(''); }
  set textContent(v) { this.kids = [new El('#', {}, String(v))]; }
  append(...els) { els.forEach(e => { e.parent = this; this.kids.push(e); }); }
  before(e) { e.parent = this.parent; this.parent.kids.splice(this.parent.kids.indexOf(this), 0, e); }
  addEventListener(k, fn) { this.on[k] = fn; }
  matches(sel) {
    const m = /^([a-z]*)(?:\.([\w-]+))?(?:\[([\w-]+)(?:="([^"]*)")?\])?$/.exec(sel);
    if (!m) throw new Error('selector not supported by the test document: ' + sel);
    return this.tag !== '#' && (!m[1] || this.tag === m[1])
      && (!m[2] || (this.attrs.class || '').split(' ').includes(m[2]))
      && (!m[3] || (m[3] in this.attrs && (m[4] === undefined || this.attrs[m[3]] === m[4])));
  }
  querySelectorAll(sel) { return this.kids.flatMap(k => [...(k.matches(sel) ? [k] : []), ...k.querySelectorAll(sel)]); }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
}
const root = new El('root');
let at = root;
for (const t of fs.readFileSync(file, 'utf8').match(/<!--[\s\S]*?-->|<style>[\s\S]*?<\/style>|<script>[\s\S]*?<\/script>|<\/[^>]+>|<[^>]+>|[^<]+/g)) {
  if (t.startsWith('<!') || t.startsWith('<style>') || t.startsWith('<script>')) continue;
  if (t.startsWith('</')) {
    const tag = t.slice(2, -1);
    let p = at;
    while (p && p.tag !== tag) p = p.parent;
    if (p && p.parent) at = p.parent;
  } else if (t.startsWith('<')) {
    const tag = /^<([^\s/>]+)/.exec(t)[1];
    const attrs = {};
    for (const a of t.slice(tag.length + 1).matchAll(/([^\s=\/>"]+)(?:="([^"]*)")?/g)) attrs[a[1]] = decode(a[2] ?? '');
    const el = new El(tag, attrs);
    at.append(el);
    if (!t.endsWith('/>') && !['meta', 'br', 'input'].includes(tag)) at = el;
  } else at.append(new El('#', {}, decode(t)));
}
const fig = root.querySelector('figure.vr-scene');
const views = fig.querySelectorAll('.vr-scene-view');
const frame = v => JSON.stringify([
  v.querySelectorAll('[data-item]').map(g => [g.attrs['data-item'], g.attrs['data-state'],
    g.querySelector('.vr-scene-g').textContent, g.querySelectorAll('[data-slot]').map(s => s.textContent)]),
  ['.vr-scene-n', '.vr-scene-c', '.vr-scene-src'].map(s => v.querySelector('.vr-scene-cap').querySelector(s).textContent),
  v.querySelector('.vr-scene-cap').attrs['data-asserted'],
  v.querySelectorAll('.vr-scene-dot').map(d => [d.attrs.r, d.attrs.style]),
]);
const authored = views.map(frame);
const timers = [];
new Function('document', 'setTimeout', 'clearTimeout', fs.readFileSync(scriptFile, 'utf8'))(
  { querySelectorAll: s => root.querySelectorAll(s), querySelector: s => root.querySelector(s), createElement: t => new El(t) },
  fn => timers.push(fn), id => { if (id) timers[id - 1] = null; });
const say = (good, what) => console.log((good ? 'ok ' : 'FAIL ') + what);
say(timers.length === 0, 'loading schedules nothing');
say(views.every(v => !('data-moving' in v.attrs)), 'loading turns no motion on');
const press = (v, name) => v.querySelector(`button[data-act="${name}"]`).on.click();
const data = JSON.parse(fig.querySelector('script[data-scene]').textContent);
const first = views.map(frame);
press(views[0], 'next');
say(frame(views[0]) !== first[0] && views.slice(1).every((v, i) => frame(v) === first[i + 1]), 'Next moves its own view and no other');
say(views[0].querySelector('.vr-scene-n').textContent === `step 2 of ${data.views[0].steps.length}`, 'Next moves one step');
press(views[0], 'back');
say(frame(views[0]) === first[0], 'Back returns to the step before');
views.forEach((v, i) => {
  data.views[i].steps.forEach(() => press(v, 'next'));
  say(frame(v) === authored[i], `${data.views[i].id}: its last step is the authored frame`);
});
say(timers.length === 0, 'Next and Back schedule nothing');
press(views[0], 'play');
for (let i = 0; i < timers.length && i < 99; i++) if (timers[i]) timers[i]();
say(timers.length > 0 && timers.length < 99 && frame(views[0]) === authored[0], 'Play runs to the last step and stops');
say(root.querySelectorAll('.vr-scene-view').every(v => !('hidden' in v.attrs)) && views.length === data.views.length, 'every view is still there');
JS
        if node "$tmp/run.js" "$tmp/page.html" "$tmp/scene.js" >"$tmp/run.out" 2>"$tmp/run.err"; then
            while IFS= read -r line; do
                case "$line" in "ok "*) ok "run: ${line#ok }" ;; *) bad "run: ${line#FAIL }" ;; esac
            done <"$tmp/run.out"
        else
            bad "the script runs against the example" "$(cat "$tmp/run.err")"
        fi
    else
        bad "the script parses under node --check" "$(cat "$tmp/parse.err")"
    fi
fi

# -----------------------------------------------------------------------------
section "SKILL.md Step 1 maps a shape's closing summary"
# -----------------------------------------------------------------------------
step1="$(span '^### 1[.] ' '^### 2[.] ' <"$SKILL")"
if grep -qF '§18' <<<"$step1"; then ok "Step 1 points at §18"; else bad "Step 1 does not point at §18"; fi
if grep -qF '§18' < <(span '^## Handoff' '^#[^#]' <"$SKILL"); then ok "Handoff points at §18"; else bad "Handoff does not point at §18"; fi

# subject <name>: that subject's part of Step 1.
subject() { span "^#### Subject: $1" '^#### |^### ' <<<"$step1"; }
# unmapped <mapping> <names>: each name with no `| **name** | <block or prose> |` row.
unmapped() {
    local name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "
$1" in
            *"
| **$name** | "[!\ \|]*) ;;
            *) printf '%s\n' "$name" ;;
        esac
    done <<<"$2"
}

categories="$(span '^[*][*]Present a closing summary' '^[*][*]Confidence tags' <"$SHAPE" | sed -nE 's/^- \*\*([^*]+)\*\*.*/\1/p')"
[ -n "$categories" ] || fatal "could not read the closing summary's categories from $SHAPE"
shape_map="$(subject 'a .*/shape' | grep '^|')"
clean "every closing-summary category has a row" "$(unmapped "$shape_map" "$categories")"
flags "a category with no row" "$(unmapped "$shape_map" "$categories
A category with no row")"
tags="$(span '^[*][*]Confidence tags' '^Ask the user' <"$SHAPE" | sed -nE 's/^\| `([A-Za-z]+)` \|.*/\1/p')"
[ -n "$tags" ] || fatal "could not read the confidence tags from $SHAPE"
assumption_row="$(grep -F '| **Assumptions** |' <<<"$shape_map")"
while IFS= read -r tag; do
    if grep -qF "\`$tag\`" <<<"$assumption_row"; then ok "the Assumptions row places $tag"; else bad "the Assumptions row does not place $tag"; fi
done <<<"$tags"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
