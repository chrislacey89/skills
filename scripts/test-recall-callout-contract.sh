#!/usr/bin/env bash
# The needles here are HTML and JavaScript, full of quotes and backticks.
# shellcheck disable=SC2016
# test-recall-callout-contract.sh — contract test for the question-first
# framework callout (visual-rendering-core.md §3 "Ask first, then reveal",
# visual-recap-design.md §6) and the recall part of the §4 serializer.
#
# THE DRIFT CLASS: a round-trip that exists in the markup and not in the
# serializer, or the reverse. The recall field is only worth rendering because
# the reader's attempt comes back to the author. Two files carry the two halves:
# the design doc names the field's attribute, and core §4's serializer reads it.
# Rename one and every recap still renders, every field still takes typing, and
# Copy feedback silently drops the attempts. Nothing on the page shows the loss.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. Core §4's serializer, run under node against stub units, emits
#      `recall "…"` on the callout's own id, after any verdict and note; skips a
#      framework callout nobody answered; and does not report a nested callout's
#      attempt a second time on the unit that contains it.
#   2. Core §4's format example carries a recall line, so the documented format
#      and the serializer agree.
#   3. The design doc's framework callout example puts the recall field above a
#      <details> that holds the answer, and the field is not a note field.
#   4. The attribute the design doc's markup uses is the one the serializer reads.
#
# The order detector in 3 is healthy at zero hits, so it is self-tested against
# a perturbed copy of the real example (answer moved above the field), per
# docs/solutions/testing-patterns/dead-guards-report-coverage-they-do-not-have.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# --- 4. one attribute name across both files -------------------------------
ATTR=data-feedback-recall
if grep -qF "<textarea $ATTR" "$DESIGN"; then ok "design §6 markup uses $ATTR"; else bad "design §6 markup does not use $ATTR"; fi
if grep -qF "querySelector('[$ATTR]')" "$CORE"; then ok "core §4 serializer reads [$ATTR]"; else bad "core §4 serializer does not read [$ATTR]"; fi

# --- 2. the documented format carries a recall line ------------------------
format_block="$(awk '/^### The serialized format/{on=1} on&&/^```$/{n++; if(n==2) exit} on&&n==1' "$CORE")"
if grep -qE '^- callout#c-[a-z0-9-]+-L[0-9]+: recall "' <<<"$format_block"; then
  ok "core §4 format example has a callout recall line"
else
  bad "core §4 format example has no callout recall line"
fi

# --- 3. field above a <details> that holds the answer ----------------------
# Prints "ok" when, inside the framework callout example, the recall field comes
# before <details>, and the <dl> answer sits between <details> and </details>.
order_check() {
  awk -v attr="$ATTR" '
    /<textarea data-feedback-recall/ { if (!f) f = NR; if ($0 ~ /data-feedback-note/) note = 1 }
    /<details/ && !d { d = NR }
    /<dl / && !l { l = NR }
    /<\/details>/ && !e { e = NR }
    END { if (f && d && l && e && f < d && d < l && l < e && !note) print "ok"; else print "bad" }'
}
example="$(awk '/^### The framework callout/{on=1} on&&/^```html$/{grab=1; next} grab&&/^```$/{exit} grab' "$DESIGN")"
if [ -z "$example" ]; then
  bad "design §6 framework callout example not found"
elif [ "$(order_check <<<"$example")" = ok ]; then
  ok "design §6: recall field precedes a <details> holding the <dl> answer"
else
  bad "design §6: recall field / <details> / answer order is wrong"
fi
# self-test: move the answer <dl> above the field; the detector must fail it
perturbed="$(printf '<dl data-early>\n%s\n' "$example")"
if [ "$(order_check <<<"$perturbed")" = bad ]; then ok "self-test: detector rejects answer above the field"; else bad "self-test: detector accepted answer above the field"; fi
perturbed2="${example//<textarea data-feedback-recall/<textarea data-feedback-recall data-feedback-note}"
if [ "$(order_check <<<"$perturbed2")" = bad ]; then ok "self-test: detector rejects a recall field that is also a note"; else bad "self-test: detector accepted a recall field that is also a note"; fi

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
        const e = { dataset: { feedbackId: id, feedbackKind: kind }, kids: [], parent: null };
        if (opts.verdict) e.dataset.verdict = opts.verdict;
        e.attrs = { feedbackId: true };
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
      // answered framework callout
      add(root, add(el("c-app-ts-L18", "callout"), field("recall", "  runs after the handler  ")));
      // unanswered framework callout: skipped
      add(root, add(el("c-app-ts-L24", "callout"), field("recall", "")));
      // change card with verdict, note, and a nested framework half
      add(root, add(el("c-session-ts-L33", "callout", { verdict: "needs-change" }), field("note", "reuse getSession()"), field("recall", "the router calls it")));
      // per-unit series unit holding a nested callout that was answered
      add(root, add(el("u-closeout", "unit"), add(el("c-closeout-L9", "callout"), field("recall", "inner answer"))));
      decorate(root);
      global.document = { querySelectorAll: s => all(root, c => c.attrs[key(s)]) };
      global.RECAP_SLUG = "t";
      eval(process.env.SERIALIZER + "\nprocess.stdout.write(buildBlob());");
    ' 2>&1)" || { bad "serializer run failed: $out"; out=""; }
    if [ -n "$out" ]; then
      want_line() { if grep -qxF -- "$1" <<<"$out"; then ok "serializer emits: $1"; else bad "serializer missing: $1"; printf '%s\n' "$out" | sed 's/^/     | /'; fi; }
      want_line '- callout#c-app-ts-L18: recall "runs after the handler"'
      want_line '- callout#c-session-ts-L33: needs-change — "reuse getSession()" — recall "the router calls it"'
      want_line '- callout#c-closeout-L9: recall "inner answer"'
      if grep -q 'c-app-ts-L24' <<<"$out"; then bad "serializer emitted an unanswered framework callout"; else ok "serializer skips an unanswered framework callout"; fi
      if grep -q 'u-closeout' <<<"$out"; then bad "serializer reported a nested callout's attempt on its containing unit"; else ok "serializer does not report a nested attempt on its containing unit"; fi
    fi
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
