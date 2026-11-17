#!/usr/bin/env bash
# The needles here are CSS and markdown, full of quotes and backticks.
# shellcheck disable=SC2016
# test-reader-palette-contract.sh — contract test for /visual-recap's reader
# palette (chrislacey89/skills#764): visual-recap-design.md §1 "A reader
# palette", and the token-core forcing function in visual-rendering-core.md §6
# that now checks a reader palette by names and contrast instead of values.
#
# THE DRIFT CLASS: a relaxed check that relaxes too far. The forcing function
# used to compare values, which a reader's editor theme always fails. Once it
# compares names and contrast instead, the only things holding the line are
# those two checks, so they are RUN here against the design's own example, and
# each is self-tested against a planted palette that must fail it.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. The example sets only names the canonical token block defines, and its
#      --sx-* names are among the canonical six.
#   2. It keeps the three-state shape: the guarded dark copy sits inside the
#      media query, and the two dark copies are identical.
#   3. Applied over the canonical dark block, every text color reaches 4.5:1
#      against every surface, except the dark exceptions §1's header names.
#   4. Planted palettes with a seventh --sx-* name, or a --bg that sinks
#      contrast, fail checks 1 and 3.
#   5. Core §6 separates the subject's aesthetic from a reader palette and
#      points at the design section; SKILL.md §5 points at core §6.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md
SKILL=visual-recap/SKILL.md

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 is required for the contrast measurement"; exit 1; }

# rule_body <text> <opener> — declarations in the first rule whose line contains
# <opener>, ending at the brace that closes it, leading indentation stripped.
rule_body() {
  awk -v opener="$2" '
    !on && index($0, opener) { on = 1; depth = 1; next }
    on { depth += gsub(/{/, "{"); depth -= gsub(/}/, "}"); if (depth <= 0) exit; sub(/^[[:space:]]+/, ""); print }
  ' <<<"$1"
}
names() { printf '%s\n' "$1" | perl -0pe 's{/\*.*?\*/}{}gs' | tr ';' '\n' | grep -oE '^[[:space:]]*--[A-Za-z0-9_-]+:' | sed -E 's/^[[:space:]]+//; s/:$//' | sort -u || true; }

design_text="$(cat "$DESIGN")"
canon_light="$(rule_body "$design_text" ':root{')"
canon_dark="$(rule_body "$design_text" ':root[data-theme="dark"]{')"
[[ -n "$canon_light" && -n "$canon_dark" ]] || { echo "FAIL the canonical token block is not readable"; exit 1; }
canon_names="$(names "$canon_light")"

sec1="$(awk '/^## 1\. /{on=1} on&&/^## 2\. /{exit} on' "$DESIGN")"
palette="$(awk '/^```html$/{buf=""; on=1; next} on&&/^```$/{if (buf ~ /reader palette/) {printf "%s", buf; exit} on=0; next} on{buf = buf $0 "\n"}' <<<"$sec1")"
if [[ -n "$palette" ]]; then ok "design §1 carries a reader palette example"; else bad "design §1 has no html block marked 'reader palette'"; fi

# names_check <palette> -> ok | bad:<detail>
names_check() {
  local pn extra sx
  pn="$(names "$1")"
  extra="$(comm -13 <(printf '%s\n' "$canon_names") <(printf '%s\n' "$pn") | tr '\n' ' ')"
  sx="$(grep -c '^--sx-' <<<"$pn" || true)"
  if [[ -z "${extra// /}" && "$sx" -le 6 ]]; then echo ok; else echo "bad: names outside the canonical block: $extra"; fi
}
# contrast_check <palette> -> ok | bad:<detail>
dark_exceptions="$(grep -F 'body-text bar' "$DESIGN" | head -1 | sed 's/^.* in light,//' | grep -oE -- '--sx-[a-z]' | sort -u | tr '\n' ' ' || true)"
contrast_check() {
  local over
  over="$(rule_body "$1" ':root[data-theme="dark"]{')"
  BASE="$canon_dark" OVER="$over" EXC="$dark_exceptions" python3 -I -c '
import os, re, colorsys
def parse(t):
    d = {}
    for m in re.finditer(r"(--[A-Za-z0-9_-]+)\s*:\s*hsla?\(([^)]*)\)", t):
        v = m.group(2).replace("%", " ").replace(",", " ")
        a = 1.0
        if "/" in v:
            v, al = v.split("/"); a = float(al)
        h, s, l = [float(x) for x in v.split()[:3]]
        r, g, b = colorsys.hls_to_rgb(h / 360, l / 100, s / 100)
        d[m.group(1)] = (r * 255, g * 255, b * 255, a)
    return d
def lum(c):
    f = lambda v: v / 255 / 12.92 if v / 255 <= 0.03928 else ((v / 255 + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
p = {**parse(os.environ["BASE"]), **parse(os.environ["OVER"])}
bg = p["--bg"]
comp = lambda c: tuple(c[i] * c[3] + bg[i] * (1 - c[3]) for i in range(3))
surf = [k for k in ("--bg", "--bg-subtle", "--bg-inset", "--bg-elev", "--add-bg", "--del-bg") if k in p]
text = ["--fg", "--fg-muted", "--add", "--del", "--risk"] + [k for k in p if k.startswith(("--flag-", "--sx-"))]
exc = set(os.environ["EXC"].split())
low = []
for t in text:
    if t in exc: continue
    for s in surf:
        a, b = lum(comp(p[t])), lum(comp(p[s]))
        r = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        if r < 4.5: low.append("%s on %s %.2f" % (t, s, r))
print("ok" if not low else "bad: " + "; ".join(low))
'
}

if [[ -n "$palette" ]]; then
  r="$(names_check "$palette")"
  if [[ "$r" == ok ]]; then ok "the reader palette sets canonical names only"; else bad "the reader palette $r"; fi
  guarded="$(rule_body "$palette" ':root:not([data-theme="light"]){')"
  attr="$(rule_body "$palette" ':root[data-theme="dark"]{')"
  media_next="$(awk '/@media \(prefers-color-scheme: dark\)\{/{getline; print; exit}' <<<"$palette")"
  if [[ -n "$attr" && "$guarded" == "$attr" ]] && grep -qF ':root:not([data-theme="light"]){' <<<"$media_next"; then
    ok "the reader palette keeps the three-state shape with identical dark copies"
  else
    bad "the reader palette's dark copies differ, or the guarded copy is not inside the media query"
  fi
  [[ -n "$dark_exceptions" ]] || bad "could not read the dark exceptions from §1's header"
  r="$(contrast_check "$palette")"
  if [[ "$r" == ok ]]; then ok "every text color reaches 4.5:1 on every surface under the reader palette (dark exceptions: $dark_exceptions)"; else bad "reader palette contrast $r"; fi
  # self-tests: each check must fire on a palette that breaks it
  seventh="${palette//--sx-c:hsl(200 13% 45%);/--sx-c:hsl(200 13% 45%); --sx-x:hsl(0 0% 50%);}"
  if [[ "$seventh" != "$palette" && "$(names_check "$seventh")" != ok ]]; then ok "self-test: names check rejects a seventh --sx-* name"; else bad "self-test: names check accepted a seventh --sx-* name"; fi
  greybg="${palette//--bg:hsl(210 47% 12%);/--bg:hsl(210 10% 55%);}"
  if [[ "$greybg" != "$palette" && "$(contrast_check "$greybg")" != ok ]]; then ok "self-test: contrast check rejects a mid-gray --bg"; else bad "self-test: contrast check accepted a mid-gray --bg"; fi
fi

# --- 5. the forcing function and its pointers --------------------------------
ff="$(grep -F 'Forcing function — confirm the token core is canonical' "$CORE" || true)"
if grep -qF "the subject's aesthetic is forbidden; a reader's palette is allowed" <<<"$ff" && grep -qF '(*A reader palette*)' <<<"$ff"; then
  ok "core §6 forcing function separates the subject's aesthetic from a reader palette and points at design §1"
else
  bad "core §6 forcing function does not separate the two cases, or does not point at design §1 (*A reader palette*)"
fi
if grep -qF '**A reader palette: the reader' <<<"$sec1"; then ok "design §1 has the 'A reader palette' section core points at"; else bad "design §1 has no 'A reader palette' section"; fi
skill_ff="$(grep -F 'Confirm the token core is canonical' "$SKILL" || true)"
if grep -qF '`references/visual-rendering-core.md` §6' <<<"$skill_ff"; then ok "SKILL.md §5 points at core §6 for the reader palette"; else bad "SKILL.md §5 does not point at core §6"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
