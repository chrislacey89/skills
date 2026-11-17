#!/usr/bin/env bash
# The needles here are HTML and shell, full of quotes and braces.
# shellcheck disable=SC2016
# test-recap-generator-checklist.sh — contract test for /visual-recap's
# generator checklist (chrislacey89/skills#765): the placeholder check in
# visual-recap/SKILL.md §5, and the excerpt rules in visual-recap-design.md §6
# (scope an excerpt to the method; mark every line-number jump with a gap row).
#
# THE DRIFT CLASS: a check that reports clean for the wrong reason. A bare `{{`
# search fires on every JSX `style={{…}}` line, so an author learns to ignore
# it, and a real leftover `{{TITLE}}` ships. An excerpt whose numbers jump from
# 33 to 37 with nothing between reads as adjacent lines, and the copied example
# is where that habit comes from.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. The placeholder block, RUN against planted files: it fails on an
#      upper-case `{{NAME}}` leftover and passes on JSX and template syntax that
#      legitimately contains `{{`.
#   2. In design §6's annotated-diff example, every jump in a pane's line
#      numbers has a `.vr-gap` row between the two lines, and its data-gap names
#      exactly the skipped range. Self-tested on a copy with the gap removed.
#   3. Design §6 states the method-scope rule, and SKILL.md §2 points at it.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

SKILL=visual-recap/SKILL.md
DESIGN=docs/visual-recap-design.md

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# --- 1. the placeholder check, run ------------------------------------------
MARK='# visual-recap: placeholder check'
block="$(awk -v m="$MARK" '
  /^```bash$/ { inb=1; buf=""; first=1; next }
  inb && /^```$/ { if (keep) { printf "%s", buf; exit } inb=0; keep=0; next }
  inb { if (first && $0 == m) keep=1; first=0; buf = buf $0 "\n" }
' "$SKILL")"
if [[ -n "$block" ]]; then ok "SKILL.md carries the placeholder check block"; else bad "SKILL.md has no fenced bash block starting with '$MARK'"; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
run_check() { # run_check <file> -> exit status of the documented block on it
  local filled
  filled="$(F="$1" awk '/^ARTIFACT=/ { print "ARTIFACT=\"" ENVIRON["F"] "\""; next } { print }' <<<"$block")"
  bash -c "$filled" >/dev/null 2>&1
}
printf '<h1>{{TITLE}}</h1>\n' >"$work/leftover.html"
printf '<p>ok</p>\n<td>{{SESSION_HUNK}}</td>\n' >"$work/leftover2.html"
cat >"$work/clean.html" <<'HTML'
<code>&lt;div style={{color: 'red'}} /&gt;</code>
<code>{{ user.name }}</code>
<code>{{#each items}}{{this}}{{/each}}</code>
<code>{{Title}}</code>
HTML
if ! run_check "$work/leftover.html"; then ok "refuses a {{TITLE}} leftover"; else bad "passed a file with {{TITLE}} left in it"; fi
if ! run_check "$work/leftover2.html"; then ok "refuses a {{SESSION_HUNK}} leftover on a later line"; else bad "passed a file with {{SESSION_HUNK}} left in it"; fi
if run_check "$work/clean.html"; then ok "passes JSX and template syntax that contains {{"; else bad "fired on JSX or template syntax that is correct output"; fi
if grep -qE "grep[^|]*'\{\{'" <<<"$block" || grep -qF "grep -n '{{'" <<<"$block"; then bad "the block searches for a bare {{"; else ok "the block does not search for a bare {{"; fi

# --- 2. gap rows in the §6 example ------------------------------------------
sec6="$(awk '/^## 6\. /{on=1} on&&/^## 7\. /{exit} on' "$DESIGN")"
example="$(awk '/^```html$/{n++; if(n==1){on=1; next}} on&&/^```$/{exit} on' <<<"$sec6")"
[[ -n "$example" ]] || bad "design §6 has no annotated-diff example"

# gap_check: prints ok, or bad:<detail>. A pane starts at its BEFORE/AFTER
# header. Within a pane, a line number more than one past the previous must be
# preceded by a .vr-gap row whose data-gap is "<prev+1>-<this-1>".
gap_check() {
  awk '
    />(BEFORE|AFTER)</ { prev = ""; gap = ""; next }
    /class="vr-gap"/ { if (match($0, /data-gap="[0-9]+-[0-9]+"/)) gap = substr($0, RSTART + 10, RLENGTH - 11); next }
    match($0, /user-select:none">[0-9]+</) {
      n = substr($0, RSTART + 18, RLENGTH - 19) + 0
      if (prev != "" && n > prev + 1) {
        want = (prev + 1) "-" (n - 1)
        if (gap != want) bad = bad " " prev "->" n "(gap:" (gap == "" ? "none" : gap) ")"
        jumps++
      }
      prev = n; gap = ""
    }
    END { if (bad != "") print "bad:" bad; else if (jumps == 0) print "bad: no jump in the example to check"; else print "ok" }'
}
res="$(gap_check <<<"$example")"
if [[ "$res" == ok ]]; then ok "design §6: every line-number jump in the example has a matching gap row"; else bad "design §6: ${res#bad:}"; fi
stripped="$(grep -v 'class="vr-gap"' <<<"$example")"
if [[ "$(gap_check <<<"$stripped")" != ok ]]; then ok "self-test: gap check rejects a jump with no gap row"; else bad "self-test: gap check accepted a jump with no gap row"; fi
wrong="${example//data-gap=\"34-36\"/data-gap=\"34-35\"}"
if [[ "$wrong" != "$example" && "$(gap_check <<<"$wrong")" != ok ]]; then ok "self-test: gap check rejects a gap row naming the wrong range"; else bad "self-test: gap check accepted a wrong range"; fi

# --- 3. the method-scope rule and its pointer --------------------------------
if grep -qF '**Scope it to the method, not the file.**' <<<"$sec6"; then ok "design §6 states the method-scope rule"; else bad "design §6 does not state the method-scope rule"; fi
step2="$(awk '/^### 2\. /{on=1; next} on&&/^### /{exit} on' "$SKILL")"
if grep -qF 'gap row (`references/visual-recap-design.md` §6)' <<<"$step2"; then ok "SKILL.md §2 points at design §6 for excerpts and gaps"; else bad "SKILL.md §2 does not point at design §6 for excerpts and gaps"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
