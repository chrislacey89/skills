#!/usr/bin/env bash
# test-recap-pair-contract.sh — static contract for the visual recap's
# before/after pair rows (docs/visual-recap-design.md §6, §7, §12, §D4).
#
# THE DRIFT CLASS. The recap's layout rule is that a pair of frames sits in ONE
# row, the row is the block's one horizontal scroller, and no code line scrolls
# on its own. A pair row without the scroller lets a long line grow the whole
# document sideways; a line with its own overflow paints a scrollbar under
# every long line and scrolls each one out of step with its neighbors. Neither
# shows up in any existing suite, so a layout that broke the rule passed six
# recap-related suites while the defect was live (the review of the PR that made
# pairs wrap found it by measuring a render, not by any check).
#
# WHAT IT READS. The real design doc, extracted: every html fenced block's
# inline styles and <style> rules. Nothing is restated here. It checks:
#   1. every inline pair row (a flex-wrap row of `flex:1 0 max-content`
#      frames) carries overflow-x:auto on the row itself;
#   2. every CSS pair row (`.vr-pair`, `.panes`) declares overflow-x:auto;
#   3. every `.vr-pair` in markup sits inside a `.vr-series` that names its
#      layout once, as split or stacked;
#   4. no element or rule that sets white-space:pre (a code line) also sets
#      overflow.
#
# EVERY DETECTOR HAS A SELF-TEST. Healthy output is zero problems, so a
# detector that matches nothing looks exactly like a pass. Each check below is
# run against a doc with the fault planted and must report it, and against the
# unplanted doc and must report nothing; a floor on how many rows were found
# stops "found nothing" from passing.
#
# This is a static check on the source. It does not render anything, so it
# cannot see a layout that scrolls for another reason; the measured numbers
# for the same rules came from a headless browser and live in the PR that
# introduced them.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
doc="$repo_root/docs/visual-recap-design.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

[[ -f "$doc" ]] || fatal "no design doc at $doc"
command -v python3 >/dev/null 2>&1 || fatal "python3 is required to read the doc's blocks"

# check <doc-file> — prints one line per problem, then a summary line
# "rows inline=<n> css=<n> markup=<n> lines=<n>".
check() {
    python3 -I - "$1" <<'PY'
import re, sys

text = open(sys.argv[1]).read()
blocks = re.findall(r'```html\n(.*?)\n```', text, re.S)
problems = []

styles = []   # (selector, declarations) from every <style> block
inline = []   # every style="..." value, with its tag
tags = []     # every opening tag with class and style
for b in blocks:
    for css in re.findall(r'<style>(.*?)</style>', b, re.S):
        css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
        for sel, decl in re.findall(r'([^{}@][^{}]*)\{([^{}]*)\}', css):
            styles.append((' '.join(sel.split()), decl))
    for m in re.finditer(r'<(\w+)\b([^>]*)>', b):
        attrs = m.group(2)
        st = re.search(r'style="([^"]*)"', attrs)
        cl = re.search(r'class="([^"]*)"', attrs)
        tags.append((m.group(1), cl.group(1) if cl else '', st.group(1) if st else '', attrs, m.start(), b))

# 1. inline pair rows: a flex-wrap row whose frames are flex:1 0 max-content
inline_rows = 0
for b in blocks:
    for m in re.finditer(r'<div style="([^"]*flex-wrap:wrap[^"]*)">\s*(?:<!--.*?-->\s*)?<div[^>]*style="[^"]*flex:1 0 max-content', b, re.S):
        inline_rows += 1
        if 'overflow-x:auto' not in m.group(1):
            problems.append('inline pair row lacks overflow-x:auto: ' + m.group(1)[:70])

# 2. CSS pair rows
css_rows = 0
for sel, decl in styles:
    if sel in ('.vr-pair', '.panes'):
        css_rows += 1
        if 'overflow-x:auto' not in decl.replace(' ', ''):
            problems.append('CSS pair row %s lacks overflow-x:auto' % sel)

# 3. markup pair rows sit in a series that names its layout
markup_rows = 0
for b in blocks:
    for m in re.finditer(r'class="vr-pair"', b):
        markup_rows += 1
        before = b[:m.start()]
        opens = [(x.start(), x.group(0)) for x in re.finditer(r'<div class="vr-series"[^>]*>', before)]
        closes = before.count('</div><!-- /.vr-series -->')
        if len(opens) <= closes:
            problems.append('a .vr-pair sits outside any .vr-series')
        elif not re.search(r'data-layout="(split|stacked)"', opens[-1][1]):
            problems.append('a .vr-series does not name its layout: ' + opens[-1][1])

# 4. a code line (white-space:pre) never scrolls on its own
line_rules = 0
for sel, decl in styles:
    if 'white-space:pre' in decl.replace(' ', ''):
        line_rules += 1
        if 'overflow' in decl:
            problems.append('CSS line rule %s sets overflow' % sel)
for _tag, _cl, st, _attrs, _pos, _b in tags:
    if 'white-space:pre' in st.replace(' ', ''):
        line_rules += 1
        if 'overflow' in st:
            problems.append('inline code line sets overflow: ' + st[:70])

for p in problems:
    print('PROBLEM ' + p)
print('rows inline=%d css=%d markup=%d lines=%d' % (inline_rows, css_rows, markup_rows, line_rules))
PY
}

real="$(check "$doc")"

section "the real doc"
problems="$(printf '%s\n' "$real" | grep '^PROBLEM' || true)"
if [[ -z "$problems" ]]; then ok "no pair row lacks its one scroller and no line scrolls on its own"; else bad "$problems"; fi

# Floors: the doc has inline rows in §6 and §7, the .vr-pair and .panes CSS
# rows, the §12 markup pairs, and several code-line rules. Fewer than this
# means the extractor stopped seeing the doc, not that the doc got cleaner.
summary="$(printf '%s\n' "$real" | grep '^rows ')"
# floor <label> <found> <minimum>
floor() {
    if [[ "$2" -ge "$3" ]]; then ok "found $2 $1 (floor $3)"; else bad "found $2 $1, expected at least $3"; fi
}
read -r inline_n css_n markup_n lines_n <<<"$(printf '%s' "$summary" | sed 's/[^0-9]/ /g')"
floor "inline pair rows" "${inline_n:-0}" 2
floor "CSS pair rows" "${css_n:-0}" 2
floor "markup pairs in a series" "${markup_n:-0}" 2
floor "code-line declarations" "${lines_n:-0}" 5

section "each detector fires on a planted fault and stays quiet on a near-miss"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# plant <label> <python-replace-expression> — write a mutated copy of the doc,
# run the check, require a PROBLEM line. The mutation must change the file.
plant() {
    local label="$1" old="$2" new="$3" out
    if ! python3 -I - "$doc" "$work/planted.md" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src).read()
if old not in t:
    sys.exit('mutation target not found: ' + old)
open(dst, 'w').write(t.replace(old, new, 1))
PY
    then
        bad "$label: the mutation did not apply, so the doc changed shape under this test"
        return
    fi
    out="$(check "$work/planted.md" | grep '^PROBLEM' || true)"
    if [[ -n "$out" ]]; then ok "$label"; else bad "$label: planted fault not reported"; fi
}

# shellcheck disable=SC2016  # literal CSS and markup, never an expansion
{
plant "an inline pair row without overflow-x:auto is reported" \
    '<div style="display:flex;flex-wrap:wrap;overflow-x:auto">' '<div style="display:flex;flex-wrap:wrap">'
plant "the .vr-pair rule without overflow-x:auto is reported" \
    '.vr-pair{display:grid;gap:var(--s4);align-items:start;overflow-x:auto}' '.vr-pair{display:grid;gap:var(--s4);align-items:start}'
plant "a .vr-series that does not name its layout is reported" \
    '<div class="vr-series" data-layout="split">' '<div class="vr-series">'
plant "a code line with its own overflow is reported" \
    '.term .tl{display:block;padding:0 var(--s4);white-space:pre;' '.term .tl{display:block;overflow-x:auto;padding:0 var(--s4);white-space:pre;'
}

# Near-miss: overflow on the pair row's scroller and on a frame container is
# fine. Only a white-space:pre declaration with overflow is a scrolling line.
python3 -I - "$doc" "$work/near.md" <<'PY'
import sys
t = open(sys.argv[1]).read()
old = '.term pre{margin:0;'
assert old in t
open(sys.argv[2], 'w').write(t.replace(old, '.term pre{overflow-y:hidden;margin:0;', 1))
PY
near="$(check "$work/near.md" | grep '^PROBLEM' || true)"
if [[ -z "$near" ]]; then ok "overflow on the .term pre scroller (not a line) is not reported"; else bad "near-miss reported: $near"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
