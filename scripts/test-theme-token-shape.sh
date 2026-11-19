#!/usr/bin/env bash
# test-theme-token-shape.sh — the recap token core themes itself in the
# three-state shape, so one source works as a local file and as a hosted page.
#
# THE DRIFT CLASS. docs/visual-recap-design.md §1 is copied verbatim into every
# /visual-recap and /walk-commits artifact. It used to flip to dark only on a
# `[data-theme="dark"]` attribute that the shell set on its own <div>. A host
# that follows the viewer's system theme and sets no attribute then showed the
# light tokens on a dark page, and publishing a recap meant hand-editing the
# block (#763, split from #758).
#
# The shape that fixes it carries the dark values twice: once under
# `@media (prefers-color-scheme: dark)` guarded by `:root:not([data-theme="light"])`,
# and once under `:root[data-theme="dark"]`. Two copies of one palette drift,
# and the drift is invisible: the page looks right in whichever mode the editor
# happened to check.
#
# WHAT THIS PINS:
#   1. SHAPE — light on `:root{`, a media-guarded dark copy, an attribute dark
#      copy, and no bare `[data-theme="dark"]{` selector left over.
#   2. PARITY — the two dark copies declare the same properties with the same
#      values, line for line, and every dark token is also defined in light.
#   3. WHERE THE ATTRIBUTE LIVES — `:root[data-theme]` only matches <html>, so
#      no example element other than <html> carries `data-theme=`, and every
#      script that writes the theme writes it on `document.documentElement`.
#   4. COVERAGE — every light token except the layout-only ones (`--sans`, `--measure`,
#      `--mono`, `--s<n>`, `--r<n>`) is also defined in both dark copies, so a
#      new light color cannot land without a dark value. Each `--flag-*` color is
#      reported by name (#769). Names are read from every `;`-separated field
#      after `/* … */` comments are stripped, so packed lines such as
#      `--s1:4px;--s2:8px;`, a name after a same-line comment, and a name with
#      `_` or uppercase all count. Before this, deleting `--flag-fw`
#      from both dark copies still passed, and dark pages fell back to the light
#      value (#772).
#   5. MEASURE — the literal `74ch` appears exactly once in the design doc, on the
#      `--measure:` declaration, so a fifth `max-width:74ch` cannot land unseen.
#
# The native-Mermaid exception is prose, and a grep over prose passes a sentence
# that reverses it, so it is not pinned here; core §6 and design §5 both state it (#772,
# docs/solutions/testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md).

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
design="$repo_root/docs/visual-recap-design.md"

fail=0
pass() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1"; fail=1; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 1; }
# check <pass-message> <fail-message> <command...> — runs the command, reports one line.
check() {
    local good="$1" badmsg="$2"; shift 2
    if "$@"; then pass "$good"; else bad "$badmsg"; fi
}

[[ -f "$design" ]] || fatal "$design not found"

# block <opener> — the declarations inside the first rule whose line contains
# <opener>, one per line, leading and trailing whitespace stripped. Ends at the
# brace that closes the opener's own rule, so a nested rule reads correctly.
block() {
    awk -v opener="$1" '
        !inblock && index($0, opener) { inblock = 1; depth = 1; next }
        inblock {
            n = gsub(/{/, "{"); depth += n
            m = gsub(/}/, "}"); depth -= m
            if (depth <= 0) exit
            line = $0
            sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
            if (line != "") print line
        }
    ' "$design"
}

# 1. SHAPE
light="$(block ':root{')"
media_line="$(grep -nF '@media (prefers-color-scheme: dark){' "$design" | head -1 | cut -d: -f1 || true)"
guarded="$(block ':root:not([data-theme="light"]){')"
attr="$(block ':root[data-theme="dark"]{')"

check "light theme block :root{ present" "no :root{ block in $design" test -n "$light"
check "@media (prefers-color-scheme: dark) present" "no @media (prefers-color-scheme: dark){ in $design" test -n "$media_line"
check ':root:not([data-theme="light"]){ block present' 'no :root:not([data-theme="light"]){ block' test -n "$guarded"
check ':root[data-theme="dark"]{ block present' 'no :root[data-theme="dark"]{ block' test -n "$attr"

guard_line="$(grep -nF ':root:not([data-theme="light"]){' "$design" | head -1 | cut -d: -f1 || true)"
if [[ -n "$media_line" && -n "$guard_line" && $((guard_line - media_line)) -eq 1 ]]; then
    pass "the guarded dark block sits directly inside the media query"
else
    bad "the :root:not([data-theme=\"light\"]) block must open on the line after @media (prefers-color-scheme: dark){ (media line ${media_line:-none}, guard line ${guard_line:-none})"
fi

if grep -nE '^[[:space:]]*\[data-theme="dark"\][[:space:]]*\{' "$design" >/dev/null; then
    bad 'a bare [data-theme="dark"]{ selector is left in the token core; it matches any element, not :root'
else
    pass 'no bare [data-theme="dark"]{ selector left'
fi

# 2. PARITY
if [[ -n "$guarded" && "$guarded" == "$attr" ]]; then
    pass "the media-guarded and attribute dark blocks are identical ($(printf '%s\n' "$attr" | wc -l | tr -d ' ') lines)"
else
    bad "the two dark blocks differ; diff (media-guarded vs attribute):"
    diff <(printf '%s\n' "$guarded") <(printf '%s\n' "$attr") || true
fi

# names <declarations> — every custom-property name declared, one per line,
# sorted. Strips `/* … */` comments (they can span lines), then splits on `;`,
# so each name on a packed line or after a comment counts. Custom-property
# names are case-sensitive and may carry `_`, so the class admits both.
names() {
    printf '%s\n' "$1" | perl -0pe 's{/\*.*?\*/}{}gs' | tr ';' '\n' | sed -E 's/^[[:space:]]+//' \
        | grep -oE '^--[A-Za-z0-9_-]+:' | sed 's/:$//' | sort -u || true
}
# self-test: the reader's own claims about names(), on a planted declaration list
probe="$(names '  --s1:4px;--s2:8px; /* note; --gone:1px */ --after-comment:red;
  --Mixed_Case:blue; /* a comment
  across lines */ --wrapped:green;')"
want="$(printf '%s\n' --Mixed_Case --after-comment --s1 --s2 --wrapped | sort -u)"
check "self-test: names() reads packed, post-comment, and _/uppercase names and skips commented ones" \
    "names() read: $(printf '%s' "$probe" | tr '\n' ' ')" test "$probe" = "$want"

light_names="$(names "$light")"
guarded_names="$(names "$guarded")"
dark_names="$(names "$attr")"
extra="$(comm -13 <(printf '%s\n' "$light_names") <(printf '%s\n' "$dark_names"))"
check "every dark token is also defined in light" "dark defines tokens light lacks: $(printf '%s' "$extra" | tr '\n' ' ')" test -z "$extra"

# 3. WHERE THE ATTRIBUTE LIVES
stray="$(grep -nE '<[a-zA-Z][a-zA-Z0-9]*[^>]*[[:space:]]data-theme=' "$design" | grep -vE '<html[[:space:]>]' || true)"
check "no element other than <html> carries data-theme=" \
    "these elements carry data-theme=, which :root[data-theme] never matches: $stray" test -z "$stray"

writes="$(grep -nE 'dataset\.theme[[:space:]]*=[^=]' "$design" || true)"
off_root="$(printf '%s\n' "$writes" | grep -v 'document\.documentElement\.dataset\.theme[[:space:]]*=' || true)"
check "a script writes dataset.theme" "no script writes dataset.theme; the theme toggles are gone" test -n "$writes"
check "every theme write targets document.documentElement" \
    "these theme writes do not target document.documentElement: $off_root" test -z "$off_root"

# 4. COVERAGE
# Layout tokens are theme-independent, so light is their only home.
themed="$(printf '%s\n' "$light_names" | grep -vE '^--(sans|mono|measure|s[0-9]+|r[0-9]+)$' || true)"
check "light declares themed tokens to check" "no themed tokens found in the light block" test -n "$themed"
for copy in guarded attr; do
    if [[ "$copy" == guarded ]]; then have="$guarded_names"; label='the media-guarded dark copy'
    else have="$dark_names"; label='the :root[data-theme="dark"] copy'; fi
    missing="$(comm -23 <(printf '%s\n' "$themed") <(printf '%s\n' "$have"))"
    check "every themed light token is also defined in $label" \
        "light tokens with no value in $label: $(printf '%s' "$missing" | tr '\n' ' ')" test -z "$missing"
done

flags="$(printf '%s\n' "$light_names" | grep -E '^--flag-' || true)"
check "light declares --flag-* colors" "no --flag-* tokens found in the light block" test -n "$flags"
while IFS= read -r flag; do
    [[ -n "$flag" ]] || continue
    if grep -qxF -- "$flag" <<< "$guarded_names" && grep -qxF -- "$flag" <<< "$dark_names"; then
        pass "$flag is defined in light and both dark copies"
    else
        bad "$flag is defined in light but missing from a dark copy"
    fi
done <<< "$flags"

# 5. THE MEASURE LIVES IN ONE TOKEN
# `--measure` names the reading width once, and every width that wants it says
# `var(--measure)`. A second literal `74ch` anywhere in the file (a `max-width`
# in a rule, an inline style) is the measure held in two places. Count the
# literal over the whole file, in any markup, and require its one occurrence to
# be the `--measure:` declaration. Other `ch` values are not the measure.
measure_is_one_token() { [[ "$1" == 1 && "$2" =~ ^[0-9]+:[[:space:]]*--measure:[[:space:]]*74ch ]]; }
measure_hits="$(grep -n '74ch' "$design" || true)"
measure_count="$(printf '%s' "$measure_hits" | grep -c . || true)"
check "the 74ch measure appears once, as the --measure declaration" \
    "74ch appears $measure_count times, or not as --measure:; use var(--measure): $measure_hits" \
    measure_is_one_token "$measure_count" "$measure_hits"

if [[ "$fail" -ne 0 ]]; then
    printf '\nFAILED\n'; exit 1
fi
printf '\nAll theme-token shape checks passed.\n'
