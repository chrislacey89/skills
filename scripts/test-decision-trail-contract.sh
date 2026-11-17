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

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md

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
      global.RECAP_SLUG = "t";
      eval(process.env.SERIALIZER + "\nprocess.stdout.write(buildBlob());");
    ' 2>&1)" || { bad "serializer run failed: $out"; out=""; }
    if [ -n "$out" ]; then
      want_line() { if grep -qxF -- "$1" <<<"$out"; then ok "serializer emits: $1"; else bad "serializer missing: $1"; printf '%s\n' "$out" | sed 's/^/     | /'; fi; }
      want_line '- callout#c-session-ts-L33: needs-change — "keep the expiry check" — recall "the router calls it" — decision dc-server-side-sessions'
      want_line '- callout#c-auth-ts-L42: "reuse getSession()"'
      if grep -q 'c-session-ts-L40' <<<"$out"; then bad "serializer emitted a callout carrying only the author's decision reference"; else ok "serializer skips a callout carrying only the author's decision reference"; fi
    fi
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
