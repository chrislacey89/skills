#!/usr/bin/env bash
# The needles here are HTML and JavaScript, full of quotes and brackets.
# shellcheck disable=SC2016
# test-sitting-plan-contract.sh — contract test for /visual-recap's sitting
# plan (visual-recap-design.md §17, chrislacey89/skills#762): hunks grouped
# into sittings inside one reading budget, each with a reviewed count mirrored
# in the rail, and the reader's state held in browser storage.
#
# THE DRIFT CLASS: per-reader state that breaks the page when storage is not
# there. localStorage throws in a private window, a sandboxed preview, or with
# site data blocked; an unguarded read at load stops every script after it, so
# the theme toggle and Copy feedback die with it. The example is copied
# verbatim into recaps, so its script is RUN here under node, once with working
# storage and once with storage that throws on every access.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. Design §17 exists, core §3 lists the block, and SKILL.md and core §5
#      point at §17.
#   2. In the example, every reviewed checkbox links the callout card it names,
#      that card exists in the design doc, every sitting has a count and a rail
#      line under the same name, and nothing in §17 carries a feedback id.
#   3. The script, run: counts and rail lines update on a check, persist across
#      a reload with working storage, and still update when storage throws.
#      Self-tested on a copy with the read's try/catch removed.

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

# --- 1. where the block is, and who points at it ------------------------------
N="$(sed -nE 's/^## ([0-9]+)\. Block: sitting plan.*/\1/p' "$DESIGN" | head -1 || true)"
sec=""
[[ -n "$N" ]] && sec="$(awk -v h="^## $N\\. Block: sitting plan" '$0 ~ h {on=1; print; next} on&&/^## /{exit} on' "$DESIGN")"
if [[ -n "$sec" ]]; then ok "design has §$N Block: sitting plan"; else bad "design has no '## <n>. Block: sitting plan' section"; fi
if grep -qE '^\| \*\*sitting plan\*\* \|' "$CORE"; then ok "core §3 table lists the sitting plan"; else bad "core §3 table has no sitting plan row"; fi
# coverage: enumerated — the two files that send a reader to the block.
for f in "$SKILL" "$CORE"; do
  if grep -q "visual-recap-design.md\` §$N\b" "$f" && grep -qi 'sitting' "$f"; then ok "$f points at design §$N"; else bad "$f does not point at the sitting plan in design §$N"; fi
done

# --- 2. the example's links and names ----------------------------------------
example="$(awk '/^```html$/{on=1; next} on&&/^```$/{exit} on' <<<"$sec")"
[[ -n "$example" ]] || bad "design §$N has no html example"
reviewed_ids="$(grep -oE 'data-reviewed="[^"]+"' <<<"$example" | sed 's/^data-reviewed="//; s/"$//' || true)"
[[ -n "$reviewed_ids" ]] || bad "the example has no reviewed checkbox"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  line="$(grep -F "data-reviewed=\"$id\"" <<<"$example")"
  if grep -qF "href=\"#callout-$id\"" <<<"$line" && grep -qF "id=\"callout-$id\" class=\"vr-callout\"" "$DESIGN"; then
    ok "checkbox $id links #callout-$id, a callout card in the design"
  else
    bad "checkbox $id does not link a callout card the design has"
  fi
done <<<"$reviewed_ids"
sittings="$(grep -oE 'data-sitting="[^"]+"' <<<"$example" | sed 's/^data-sitting="//; s/"$//' || true)"
[[ -n "$sittings" ]] || bad "the example has no data-sitting attribute"
while IFS= read -r s; do
  [[ -n "$s" ]] || continue
  li="$(awk -v s="data-sitting=\"$s\"" 'index($0, s) {on=1} on {print} on && /<\/li>$/ && !/<label>/ {exit}' <<<"$example")"
  if grep -q 'data-sitting-count' <<<"$li"; then ok "sitting $s shows its own count"; else bad "sitting $s has no data-sitting-count"; fi
  if grep -qF "data-sitting-progress=\"$s\"" <<<"$example"; then ok "sitting $s has a rail progress line"; else bad "sitting $s has no rail progress line"; fi
done <<<"$sittings"
if grep -q 'data-feedback-id' <<<"$example"; then bad "the sitting plan carries a feedback id; reviewed state must stay out of the feedback"; else ok "the sitting plan carries no feedback id"; fi

# --- 3. run the script ----------------------------------------------------------
script="$(awk '/^<script>$/{on=1; next} on&&/^<\/script>$/{exit} on' <<<"$example")"
[[ -n "$script" ]] || bad "the example has no <script>"
unguarded="$(grep -n 'localStorage' <<<"$script" | grep -v 'try {' || true)"
if [[ -z "$unguarded" ]]; then ok "every localStorage access sits inside a try"; else bad "localStorage outside a try: $unguarded"; fi

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP script run: node not on PATH"
elif [[ -z "$sittings" ]]; then
  echo "SKIP script run: no sittings to run it against (already failed above)"
else
  # One JSON line per sitting: name and its reviewed ids, read from the example.
  model="$(while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    ids="$(awk -v s="data-sitting=\"$s\"" 'index($0, s) {on=1; next} on && /data-sitting=/ {exit} on' <<<"$example" | grep -oE 'data-reviewed="[^"]+"' | sed 's/^data-reviewed="//; s/"$//' | paste -sd, -)"
    printf '%s:%s\n' "$s" "$ids"
  done <<<"$sittings")"
  run_node() { # run_node <script> <mode: ok|throws|noslug> (noslug: RECAP_SLUG left undeclared, storage working)
    SCRIPT="$1" MODEL="$model" MODE="$2" node -e '
      const model = process.env.MODEL.trim().split("\n").map(l => { const [name, ids] = l.split(":"); return { name, ids: ids.split(",") }; });
      const store = {};
      const good = { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); } };
      function page() {
        const rail = {}, sittings = [];
        for (const m of model) {
          const count = { textContent: "" };
          const boxes = m.ids.map(id => ({ dataset: { reviewed: id }, checked: false }));
          rail[m.name] = { textContent: "" };
          sittings.push({ dataset: { sitting: m.name }, boxes, count,
            querySelectorAll: () => boxes, querySelector: () => count });
        }
        const document = {
          querySelectorAll: s => s === "[data-sitting]" ? sittings : [],
          querySelector: s => { const m = /data-sitting-progress="([^"]+)"/.exec(s); return m ? rail[m[1]] : null; } };
        return { document, sittings, rail };
      }
      function load() {
        const p = page();
        let api;
        const noslug = process.env.MODE === "noslug";
        try {
          api = noslug
            ? new Function("document", "location", "localStorage", process.env.SCRIPT + "\nreturn { markReviewed };")(p.document, { pathname: "/t" }, good)
            : new Function("document", "RECAP_SLUG", "localStorage", process.env.SCRIPT + "\nreturn { markReviewed };")(p.document, "t", good);
        }
        catch (e) { return { error: String(e) }; }
        return { api, p };
      }
      // throws: every property access on localStorage throws, as a blocked one does
      if (process.env.MODE === "throws") {
        const throwing = new Proxy({}, { get() { throw new Error("SecurityError"); } });
        const p = page();
        let api;
        try { api = new Function("document", "RECAP_SLUG", "localStorage", process.env.SCRIPT + "\nreturn { markReviewed };")(p.document, "t", throwing); }
        catch (e) { console.log("error " + e.message); process.exit(0); }
        const s0 = p.sittings[0]; s0.boxes[0].checked = true; api.markReviewed(s0.boxes[0]);
        console.log("count " + s0.count.textContent);
        console.log("rail " + p.rail[s0.dataset.sitting].textContent);
        process.exit(0);
      }
      const first = load();
      if (first.error) { console.log("error " + first.error); process.exit(0); }
      const s0 = first.p.sittings[0];
      console.log("initial " + s0.count.textContent);
      s0.boxes[0].checked = true; first.api.markReviewed(s0.boxes[0]);
      console.log("count " + s0.count.textContent);
      console.log("rail " + first.p.rail[s0.dataset.sitting].textContent);
      const again = load();
      console.log("reload " + again.p.sittings[0].count.textContent + " | box " + again.p.sittings[0].boxes[0].checked);
    ' 2>&1
  }
  n0="$(awk -F: 'NR==1{print split($2, a, ",")}' <<<"$model")"
  out="$(run_node "$script" ok)"
  want() { if grep -qxF -- "$1" <<<"$2"; then ok "$3"; else bad "$3 — wanted '$1', got: $(tr '\n' '|' <<<"$2")"; fi; }
  want "initial 0 of $n0 reviewed" "$out" "storage working: a sitting starts at 0 of $n0 reviewed"
  want "count 1 of $n0 reviewed" "$out" "storage working: checking a hunk updates the sitting's count"
  want "rail 1 of $n0 reviewed" "$out" "storage working: the rail line tracks the sitting"
  want "reload 1 of $n0 reviewed | box true" "$out" "storage working: reviewed state survives a reload"
  out="$(run_node "$script" throws)"
  want "count 1 of $n0 reviewed" "$out" "storage throwing: the page loads and still counts"
  want "rail 1 of $n0 reviewed" "$out" "storage throwing: the rail line still tracks the sitting"
  out="$(run_node "$script" noslug)"
  want "count 1 of $n0 reviewed" "$out" "RECAP_SLUG undeclared: the page loads and still counts"
  want "reload 1 of $n0 reviewed | box true" "$out" "RECAP_SLUG undeclared: reviewed state still survives a reload"
  # self-test: an unguarded RECAP_SLUG read must fail the undeclared run
  bare="$(sed -E "s/\(typeof RECAP_SLUG === 'string' \? RECAP_SLUG : location\.pathname\)/RECAP_SLUG/" <<<"$script")"
  if [[ "$bare" != "$script" ]] && grep -q '^error ' <<<"$(run_node "$bare" noslug)"; then ok "self-test: an unguarded RECAP_SLUG fails the undeclared run"; else bad "self-test: removing the RECAP_SLUG guard went unnoticed"; fi
  # self-test: strip the guard from the read; the throwing run must now fail
  naked="$(sed -E 's/^(  )try \{ (reviewed = new Set\(JSON\.parse\(localStorage\.getItem\(SIT_KEY\) \|\| .\[\].\)\);) \} catch \(_\) \{\}$/\1\2/' <<<"$script")"
  if [[ "$naked" != "$script" ]] && grep -q '^error ' <<<"$(run_node "$naked" throws)"; then ok "self-test: an unguarded read fails the throwing run"; else bad "self-test: removing the read's try/catch went unnoticed"; fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
