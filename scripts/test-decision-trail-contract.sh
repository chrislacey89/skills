#!/usr/bin/env bash
# The needles here are HTML and JavaScript, full of quotes and backticks.
# shellcheck disable=SC2016
# test-decision-trail-contract.sh — contract test for the decision trail
# (visual-recap-design.md §15) and the callout's decision reference that the
# visual-rendering-core.md §4 serializer carries (chrislacey89/skills#766).
#
# THE DRIFT CLASS: a link between two blocks that resolves in one file and not
# in the other. A callout names the decision it serves by `data-decision`; the
# trail entry carries the `dc-<slug>` it names; the serializer reads the
# attribute. Rename any one of the three and every recap still renders, every
# callout still takes notes, and the feedback silently loses which commitment
# each note was about. Nothing on the page shows the loss.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. Core §4's serializer, run under node against stub units, appends
#      `decision dc-<slug>` last on a callout the reader answered, and emits no
#      line for a callout that carries only the author's decision reference.
#   2. Core §4's format example carries a decision line, so the documented
#      format and the serializer agree.
#   3. The design doc's §6 callout example carries `data-decision` on the card,
#      and the serializer reads the same attribute name.
#   4. The trail block exists where SKILL.md and core §3 point (design §15).
#   5. Every entry in the §15 example is a dc- decision, cited with a source,
#      and linked to at least one callout card. The detector is healthy at zero
#      hits, so it is self-tested against perturbed copies of the real example.
#   6. The links resolve both ways: each trail link names a real callout card
#      in the design doc, each data-decision names an entry the trail lists, each
#      entry's linked cards name that same entry back (self-tested), and each
#      card's "serves" meta line links to its entry.

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

# --- 3. one attribute name across both files -------------------------------
if grep -qE 'class="vr-callout" data-feedback-id="c-[a-z0-9-]+-L[0-9]+" data-feedback-kind="callout" data-decision="dc-[a-z0-9-]+"' "$DESIGN"; then
  ok "design §6 callout card carries data-decision=\"dc-…\""
else
  bad "design §6 callout card carries no data-decision"
fi
if grep -qF 'el.dataset.decision' "$CORE"; then ok "core §4 serializer reads dataset.decision"; else bad "core §4 serializer does not read dataset.decision"; fi

# --- 2. the documented format carries a decision line ----------------------
format_block="$(awk '/^### The serialized format/{on=1} on&&/^```$/{n++; if(n==2) exit} on&&n==1' "$CORE")"
if grep -qE '^- callout#c-[a-z0-9-]+-L[0-9]+: .* — decision dc-[a-z0-9-]+$' <<<"$format_block"; then
  ok "core §4 format example has a callout line ending in a decision part"
else
  bad "core §4 format example has no callout line ending in a decision part"
fi

# --- 4. the trail block exists where the skill and the core point ----------
if grep -qE '^## 15\. Block: decision trail' "$DESIGN"; then ok "design §15 is the decision trail"; else bad "design has no '## 15. Block: decision trail'"; fi
if grep -qE '^\| \*\*decision trail\*\* \|' "$CORE"; then ok "core §3 table has a decision trail row"; else bad "core §3 table has no decision trail row"; fi
if grep -qF 'decision trail' "$SKILL" && grep -qF 'visual-recap-design.md` §15' "$SKILL"; then
  ok "SKILL.md names the decision trail and points at design §15"
else
  bad "SKILL.md does not point at the decision trail in design §15"
fi

# --- 5. every trail entry in the example is cited and linked ----------------
# Prints "ok" when every <li class="dt-entry"> block carries a dc- feedback id of
# kind decision, an .oc-cited span with an .oc-src source, and at least one link
# to a callout card. Entries are the lines between <li … dt-entry> and </li>.
entry_check() {
  awk '
    /<li [^>]*class="dt-entry"/ { open = 1; n++; id = ($0 ~ /data-feedback-id="dc-[a-z0-9-]+" data-feedback-kind="decision"/); src = 0; link = 0; next }
    open && /class="oc-cited".*class="oc-src"/ { src = 1 }
    open && /href="#callout-c-[a-z0-9-]+-L[0-9]+"/ { link = 1 }
    open && /<\/li>/ { open = 0; if (!(id && src && link)) badn++ }
    END { if (n >= 2 && !badn) print "ok"; else print "bad" }'
}
trail="$(awk '/^## 15\. Block: decision trail/{on=1} on&&/^```html$/{grab=1; next} grab&&/^```$/{exit} grab' "$DESIGN")"
if [ -z "$trail" ]; then
  bad "design §15 example not found"
elif [ "$(entry_check <<<"$trail")" = ok ]; then
  ok "design §15: every example entry is a dc- decision, cited with a source, and linked to a callout"
else
  bad "design §15: an example entry lacks its dc- id, its cited source, or its callout link"
fi
# self-test: strip every source; the detector must fail it
if [ "$(entry_check <<<"${trail//class=\"oc-src\"/class=\"x\"}")" = bad ]; then ok "self-test: detector rejects an uncited entry"; else bad "self-test: detector accepted an uncited entry"; fi
if [ "$(entry_check <<<"${trail//href=\"#callout-/href=\"#nowhere-}")" = bad ]; then ok "self-test: detector rejects an entry linked to no callout"; else bad "self-test: detector accepted an entry linked to no callout"; fi
if [ "$(entry_check <<<"${trail//data-feedback-kind=\"decision\"/data-feedback-kind=\"callout\"}")" = bad ]; then ok "self-test: detector rejects an entry not of kind decision"; else bad "self-test: detector accepted an entry not of kind decision"; fi

# --- 6. the links resolve both ways inside the design doc -------------------
# Every callout a trail entry links to exists as a callout card, and every
# data-decision on a callout card names an entry the trail example lists.
while IFS= read -r target; do
  [ -n "$target" ] || continue
  if grep -qF "id=\"$target\" class=\"vr-callout\"" "$DESIGN"; then ok "trail link #$target resolves to a callout card"; else bad "trail link #$target resolves to no callout card"; fi
done < <(grep -oE 'href="#callout-c-[a-z0-9-]+-L[0-9]+"' <<<"$trail" | sed 's/^href="#//; s/"$//' | sort -u)
refs="$(grep -oE 'data-decision="dc-[a-z0-9-]+"' "$DESIGN" | sed 's/^data-decision="//; s/"$//' | sort -u)"
[ -n "$refs" ] || bad "design has no data-decision reference to resolve"
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if grep -qF "id=\"trail-$ref\" class=\"dt-entry\" data-feedback-id=\"$ref\"" <<<"$trail"; then ok "data-decision=\"$ref\" names a trail entry"; else bad "data-decision=\"$ref\" names no trail entry"; fi
done <<<"$refs"

# Pairing, per entry: every callout an entry links to names that same entry back
# in its data-decision. Resolving each direction separately (above) passes when
# entry A links a card that names entry B, which is the pairing the trail promises.
pairing_check() { # pairing_check <trail-html> <design-html> -> ok | bad:<detail>
  local t="$1" d="$2" id target detail=""
  while IFS= read -r line; do
    id="$(grep -oE 'data-feedback-id="dc-[a-z0-9-]+"' <<<"$line" | sed 's/.*="//; s/"$//')"
    [ -n "$id" ] || continue
    entry="$(awk -v id="$id" 'index($0, "data-feedback-id=\"" id "\"") {on=1} on {print} on && /<\/li>/ {exit}' <<<"$t")"
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      grep -qE "id=\"callout-$target\" class=\"vr-callout\" [^>]*data-decision=\"$id\"" <<<"$d" || detail+=" $id->$target"
    done < <(grep -oE 'href="#callout-c-[a-z0-9-]+-L[0-9]+"' <<<"$entry" | sed 's/^href="#callout-//; s/"$//')
  done < <(grep 'class="dt-entry"' <<<"$t")
  if [ -z "$detail" ]; then echo ok; else echo "bad:$detail"; fi
}
design_html="$(cat "$DESIGN")"
pair="$(pairing_check "$trail" "$design_html")"
if [ "$pair" = ok ]; then ok "every trail entry's linked callouts name that entry back"; else bad "trail entry links a callout that does not name it back:${pair#bad:}"; fi
# self-test: swap one card's decision for a sibling entry's; the check must fail
swapped="${design_html/data-decision=\"dc-refuse-expired-tokens\"/data-decision=\"dc-server-side-sessions\"}"
if [ "$swapped" != "$design_html" ] && [ "$(pairing_check "$trail" "$swapped")" != ok ]; then ok "self-test: pairing check rejects a card naming another entry"; else bad "self-test: pairing check accepted a card naming another entry"; fi

# The card's "serves" meta line links back to the trail entry it names.
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  card="$(awk -v r="data-decision=\"$ref\"" 'index($0, r) {on=1; n=0} on {print; if (++n > 4) exit}' "$DESIGN")"
  if grep -qF "serves <a href=\"#trail-$ref\"" <<<"$card"; then ok "callout serving $ref links back to #trail-$ref"; else bad "callout serving $ref has no 'serves <a href=\"#trail-$ref\">' link"; fi
done <<<"$refs"

# --- 1. run the real serializer ---------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "SKIP serializer run: node not on PATH"
else
  script="$(awk '/^A minimal serializer/{on=1} on&&/^<script>$/{grab=1; next} grab&&/^<\/script>$/{exit} grab' "$CORE")"
  if [ -z "$script" ]; then
    bad "core §4 serializer <script> not found"
  else
    out="$(SERIALIZER="$script" node -e '
      // Minimal DOM stub: just what buildBlob touches.
      function el(id, kind, opts = {}) {
        const e = { dataset: { feedbackId: id, feedbackKind: kind }, kids: [], parent: null, attrs: { feedbackId: true } };
        if (opts.verdict) e.dataset.verdict = opts.verdict;
        if (opts.decision) e.dataset.decision = opts.decision;
        return e;
      }
      function field(attr, value) { return { attrs: { [attr]: true }, value, kids: [], parent: null }; }
      function add(p, ...cs) { for (const c of cs) { c.parent = p; p.kids.push(c); } return p; }
      const key = s => s === "[data-feedback-id]" ? "feedbackId" : s === "[data-feedback-note]" ? "note" : s === "[data-feedback-recall]" ? "recall" : null;
      function walk(n, f) { for (const c of n.kids) { if (f(c)) return c; const r = walk(c, f); if (r) return r; } return null; }
      function all(n, f, acc = []) { for (const c of n.kids) { if (f(c)) acc.push(c); all(c, f, acc); } return acc; }
      function decorate(n) {
        n.querySelector = s => walk(n, c => c.attrs[key(s)]);
        n.closest = s => { for (let x = n; x; x = x.parent) if (x.attrs[key(s)]) return x; return null; };
        n.kids.forEach(decorate);
      }
      const root = { kids: [], attrs: {} };
      // answered callout serving a decision: verdict, note, attempt, then decision
      add(root, add(el("c-session-ts-L33", "callout", { verdict: "needs-change", decision: "dc-server-side-sessions" }), field("note", "keep the expiry check"), field("recall", "the router calls it")));
      // untouched callout that only carries the author reference: no line
      add(root, add(el("c-session-ts-L40", "callout", { decision: "dc-server-side-sessions" }), field("note", "")));
      // answered callout with no decision: unchanged shape
      add(root, add(el("c-auth-ts-L42", "callout"), field("note", "reuse getSession()")));
      decorate(root);
      global.document = { querySelectorAll: s => all(root, c => c.attrs[key(s)]) };
      global.location = { pathname: "/recaps/x.html" };
      global.RECAP_SLUG = "t";
      eval(process.env.SERIALIZER + "\nprocess.stdout.write(buildBlob());");
    ' 2>&1)" || { bad "serializer run failed: $out"; out=""; }
    if [ -n "$out" ]; then
      want_line() { if grep -qxF -- "$1" <<<"$out"; then ok "serializer emits: $1"; else bad "serializer missing: $1"; printf '%s\n' "$out" | sed 's/^/     | /'; fi; }
      want_line '- callout#c-session-ts-L33: needs-change — "keep the expiry check" — recall "the router calls it" — decision dc-server-side-sessions'
      want_line '- callout#c-auth-ts-L42: "reuse getSession()"'
      if grep -q 'c-session-ts-L40' <<<"$out"; then bad "serializer emitted a callout carrying only the author's decision reference"; else ok "serializer skips a callout carrying only the author's decision reference"; fi
      want_line '## recap-feedback v1  (recap: t)'
    fi
    # RECAP_SLUG undeclared: the header must fall back to the path, the same identity the sitting plan keys on.
    hdr="$(SERIALIZER="$script" node -e '
      global.document = { querySelectorAll: () => [] };
      global.location = { pathname: "/recaps/x.html" };
      eval(process.env.SERIALIZER + "\nprocess.stdout.write(buildBlob());");
    ' 2>&1)" || hdr="run failed: $hdr"
    if [ "$hdr" = '## recap-feedback v1  (recap: /recaps/x.html)' ]; then ok "serializer header falls back to location.pathname when RECAP_SLUG is undeclared"; else bad "serializer header with RECAP_SLUG undeclared: $hdr"; fi
    guard="(typeof RECAP_SLUG === 'string' ? RECAP_SLUG : location.pathname)"
    bare="${script/"$guard"/RECAP_SLUG}"
    if [ "$bare" != "$script" ] && ! SERIALIZER="$bare" node -e 'global.document={querySelectorAll:()=>[]};global.location={pathname:"/p"};eval(process.env.SERIALIZER+"\nbuildBlob();")' >/dev/null 2>&1; then ok "self-test: an unguarded RECAP_SLUG read fails the undeclared run"; else bad "self-test: removing the RECAP_SLUG guard went unnoticed"; fi
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
