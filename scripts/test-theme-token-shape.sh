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
#      values, line for line.
#   3. WHERE THE ATTRIBUTE LIVES — `:root[data-theme]` only matches <html>, so
#      no example element other than <html> carries `data-theme=`, and every
#      script that writes the theme writes it on `document.documentElement`.
#   4. NATIVE MERMAID — the diagram section names hosts that render
#      `<pre class="mermaid">` themselves and need no loader.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
design="$repo_root/docs/visual-recap-design.md"
core="$repo_root/docs/visual-rendering-core.md"
skill="$repo_root/visual-recap/SKILL.md"

fail=0
pass() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1"; fail=1; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 1; }
# check <pass-message> <fail-message> <command...> — runs the command, reports one line.
check() {
    local good="$1" badmsg="$2"; shift 2
    if "$@"; then pass "$good"; else bad "$badmsg"; fi
}

for f in "$design" "$core" "$skill"; do
    [[ -f "$f" ]] || fatal "$f not found"
done

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

light_names="$(printf '%s\n' "$light" | grep -oE '^--[a-z0-9-]+:' | sort -u || true)"
dark_names="$(printf '%s\n' "$attr" | grep -oE '^--[a-z0-9-]+:' | sort -u || true)"
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

# 4. NATIVE MERMAID
# shellcheck disable=SC2016  # the backticks are literal Markdown, not a command
if grep -qE 'render[s]? `<pre class="mermaid">` (natively|itself|themselves)' "$design"; then
    pass "the diagram section names hosts that render Mermaid natively"
else
    bad "the diagram section does not name hosts that render <pre class=\"mermaid\"> natively"
fi

if [[ "$fail" -ne 0 ]]; then
    printf '\nFAILED\n'; exit 1
fi
printf '\nAll theme-token shape checks passed.\n'
