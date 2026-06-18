# Visual Rendering Core

The shared rendering vocabulary and quality bar for Skill Kit's visual review surfaces — `/visual-recap` and the `/walk-commits` callout enhancement. It is the kit-native analog of Builder.io's shared `wireframe.md` / `canvas.md` cores, with one deliberate difference: **this is a vocabulary the agent authors HTML against, not a renderer we ship and version.** There is no npm package, no build step, no committed app, no MCP connector, and no hosted database. The agent is the renderer; this file is the spec it writes to.

> **Why a shared core at all.** Two skills render line-anchored callouts over a diff. Without one quality bar they drift — two callout shapes, two copy formats, two dark-mode palettes, and "renderer" quietly grows into an app. This file is the single bar both author against. If you are tempted to ship reusable JavaScript instead of describing what the agent should hand-author, stop: that is the lock-in this whole surface exists to avoid (Norman, *featuritis*; the artifact must stay knowledge-in-the-world, not a maintained component library).

---

## 1. The Grounding Rule (load-bearing, not decorative)

**Every structured block is mechanically derived from the real diff. The model writes prose only.**

A confidently-wrong recap is *more* dangerous than plain text, because a reviewer who trusts the summary will skip the exact line it got wrong. So the split is strict:

- **Derived by tooling, never by the model:** file paths, line numbers, line ranges, hunk contents, added/removed counts, the before/after text, commit hashes, which files a commit touches. These come from `git show`, `git diff`, `git diff --stat` — copied, never retyped or "cleaned up."
- **Authored by the model:** the *prose* — a callout's note, a diff hunk's one-line intent summary, a file's change flag, the reading-order narrative. Judgment and explanation only.

Concrete consequences:

- A callout's `lines` attribute must name lines that exist in the real hunk. If you cannot point at a real line, you have an observation, not a callout — write it as overview prose instead.
- **Lie Factor ≤ 1** (Tufte, *graphical integrity*): visual emphasis must not exceed the real change. Do not render a one-line tweak with the same weight as a 200-line rewrite; do not flag a file as "high-risk, load-bearing" when the diff is a rename. The visual restatement of this rule *is* the Grounding Rule — emphasis tracks the diff, never the narrative you wish the diff told.
- If a derived value and your prose disagree, the derived value wins and the prose is wrong. Fix the prose.

A recap that violates grounding is worse than no recap. When in doubt, show less and assert less.

---

## 2. Secret redaction (runs before any HTML is written)

The diff may contain secrets — `.env` values, tokens, keys, connection strings, signed URLs. The artifact is portable (it gets copied, pasted, and sometimes attached to a PR), so redaction is not optional and not best-effort.

Before emitting any hunk text:

- Drop or mask values for any line matching a high-signal secret shape: `*_KEY`, `*_SECRET`, `*_TOKEN`, `*_PASSWORD`, `AKIA…`, `sk-…`, `ghp_…`, `xox[baprs]-…`, bearer tokens, `postgres://user:pass@…` and other credentialed URIs, PEM blocks.
- Mask the *value*, keep the *key* — `STRIPE_SECRET_KEY=sk_live_••••••••` tells the reviewer a secret changed without leaking it. The change-shape is the data-ink; the secret is not.
- When in doubt, redact. A redacted line the reviewer can ask about is recoverable; a leaked one in a copied artifact is not.

If redaction removed anything, say so once in the overview ("N value(s) masked") so the reviewer knows the artifact is sanitized, not complete.

---

## 3. Component vocabulary

Six blocks cover the review surface. Each is a *semantic role*, not a shipped widget — hand-roll the HTML each time, keep it minimal, and only render the blocks the change actually needs.

| Block | Role | Grounded inputs (tooling) | Authored (prose) |
|---|---|---|---|
| **overview** | Read-intent-first header: scale (files, ±LOC, commits), reading mode, what moved | `git diff --stat`, commit count | the 1–3 sentence "what this change is" |
| **file-tree + change-flags** | The topology — which files moved, each flagged | file list, ±LOC per file | per-file flag: `new` / `moved` / `load-bearing` / `mechanical` / `risky` |
| **annotated-diff** | Split before/after for one hunk, callouts anchored to after-side lines, with a one-line intent summary above it | the hunk text, line numbers | the hunk `summary` (intent) and each callout `note` |
| **callout** | A note anchored to a line range, rendered *at* that line | `lines: "42-47"` from the real hunk | the `note` |
| **before/after toggle** | Small-multiple comparison of two states of the same unit | both states' text | which difference matters |
| **diagram** | Architecture / data-flow / sequence when topology needs a picture | — | reuse `/mermaid`; do not hand-roll graph layout |

**Do not reinvent diagrams.** When the change needs an architecture, data-flow, or sequence picture, emit a Mermaid block via `/mermaid` and embed it — Skill Kit already chose embedded Mermaid as its diagram answer (issue #83). The rendering core owns callouts and diffs, not graph layout.

**Callouts are direct labels, not legends** (Tufte, *direct labeling over legends*; Norman, *natural mapping*). The note lives spatially where the thing it explains is — clicking the inline marker highlights the exact line and rings its card. Never collect notes into a separate keyed legend the reviewer has to cross-reference; that puts the topology back in their head, which is the whole problem this surface exists to remove.

**Scope the line highlight to the code cell**, not the whole split-diff row — otherwise the empty before-cell of an added line also lights up (a real spike finding).

---

## 4. The copy-text feedback loop (the backend-free `get-plan-feedback`)

The artifact has no server, so the reviewer's answers travel by clipboard and the human is the courier. **Stable element ids are the one load-bearing implementation detail** — they are the anchors the agent parses the feedback back against (mirroring Builder.io's `anchorDetails` / `consumedCommentIds`, without their backend).

### Stable ids

Every annotatable unit carries a stable, diff-derived `data-feedback-id` — never a random or positional id, so the same callout keeps the same id if the artifact is regenerated:

- callout → `c-<file-slug>-L<line>` (e.g. `c-auth-ts-L42`)
- open-question field → `q-<n>`
- per-commit sign-off → `signoff-<short-hash>`
- per-finding response → `r-<file-slug>-L<line>`

### The Copy-feedback button (a forcing function)

A persistent **Copy feedback** button runs a small vanilla-JS serializer that reads all in-page state and writes a compact, agent-readable block to the clipboard. The button is a Norman *forcing function*: it makes the whole round-trip a single deliberate action, so feedback is never half-captured.

**Clipboard transport must be layered** — never depend on `navigator.clipboard` alone (it is blocked outside secure contexts and in some sandboxes). The proven, always-works ladder:

1. `navigator.clipboard.writeText(blob)` (works on `https://`, `http://localhost`, and `file://` — all secure contexts in real browsers),
2. fall back to `document.execCommand('copy')` over a selected textarea,
3. always also render the blob into a **visible, pre-selected `<textarea>`** so the reviewer can copy by hand even if both APIs are blocked.

The visible textarea is the guarantee, not a nicety — keep it.

### The serialized format (`recap-feedback v1`)

Stable-id-keyed, emoji-safe, one item per line, agent-parseable:

```
## recap-feedback v1  (recap: <recap-slug>)
- callout#c-auth-ts-L42: needs-change — "this should reuse getSession(), not inline it"
- question#q-1: "yes, ship behind the existing flag"
- signoff#signoff-a1b2c3d: 🟡 — "confirm the migration is reversible before merge"
```

The agent reading this back parses each line by its stable id and either (a) patches the HTML it generated, (b) drives the change into code, or (c) promotes durable items to GitHub PR review comments. **GitHub PR review comments remain the durable, line-anchored channel** for anything that must outlive the session — the clipboard loop is for the working round-trip, not the system of record.

A minimal serializer (hand-roll per artifact; this is the shape, not a shipped library):

```html
<textarea id="feedback-blob" readonly></textarea>
<button onclick="copyFeedback()">Copy feedback</button>
<script>
  function buildBlob() {
    const lines = ['## recap-feedback v1  (recap: ' + RECAP_SLUG + ')'];
    document.querySelectorAll('[data-feedback-id]').forEach(el => {
      const id = el.dataset.feedbackId;
      const kind = el.dataset.feedbackKind;     // callout | question | signoff
      const verdict = el.dataset.verdict || ''; // e.g. needs-change, 🟡
      const note = (el.querySelector('[data-feedback-note]')?.value || '').trim();
      if (!verdict && !note) return;            // skip untouched units
      lines.push(`- ${kind}#${id}: ${verdict}${note ? ' — "' + note + '"' : ''}`);
    });
    return lines.join('\n');
  }
  function copyFeedback() {
    const blob = buildBlob();
    const ta = document.getElementById('feedback-blob');
    ta.value = blob; ta.hidden = false; ta.select();
    (navigator.clipboard?.writeText(blob) ?? Promise.reject())
      .catch(() => { try { document.execCommand('copy'); } catch (_) {} });
  }
</script>
```

Keep it roughly this small. If the serializer grows state management, routing, or a framework, it has become the app this surface exists to avoid — pull it back.

---

## 5. Rendering quality bar (Tufte)

The diff and its callouts are the data; everything else recedes.

- **Maximize data-ink / "above all else, show the data."** No chartjunk, no decorative shadows, no gradients, no busy borders. A muted hairline grid at most. Every pixel that is not the change or its label is spending the reviewer's attention for nothing.
- **Small multiples + constancy of design** for before/after and per-file panels: identical scale, identical frame on both sides, so the eye reads the *difference*, not a layout change. Never restyle the after-side relative to the before-side.
- **Subtraction of weight (1 + 1 = 3).** Adjacent heavy borders create phantom third shapes that read as content. Prefer whitespace and a single light rule to separate panels; delete every border that is not doing work.
- **Value-scale semantic color, checked for simultaneous contrast in both themes.** Add/remove and risk colors must hold their meaning and contrast on light *and* GitHub-dark backgrounds — flip the palette on `[data-theme]`, and verify red/green stay legible against each other and the background (the principled answer to the #94 dark-mode contrast concern: a value scale, not a one-off patch).
- **Respect the reading budget** (Cohen / Rigby: ~100–300 LOC, 30–60 min, <400–500 LOC/hr). The recap is *author preparation*, so it must itself stay inside the budget: **3–8 key-change callouts, focused excerpts, not every hunk.** A recap that reproduces the whole diff has rebuilt the thing the reviewer was already going to scroll. If the change is too big for one budget, say so and recommend chunking — do not render a wall.

---

## 6. Inline CSS is load-bearing; CDN libraries are enhancement-only

The artifact must read *identically* with no network. Proven by spike: a real recap used **zero** Tailwind utility classes — it was 100% inline CSS and degraded to an identical file offline.

- **Hand-roll a small themeable CSS core** with CSS variables flipped on `[data-theme]` (`--bg`, `--fg`, `--add`, `--del`, `--risk`, `--muted`, …). This is the load-bearing layer; it must not depend on any CDN.
- **Reach for a CDN library only where it earns its place** — e.g. highlight.js for syntax coloring — and **always with a no-CDN fallback** so the artifact still reads when the CDN is blocked. Tailwind-via-CDN works but is not needed; do not make the artifact depend on it.
- The test: open the file with the network off. If it still reads, you built it right.

---

## 7. Open / serve guidance the skill should emit

`file://` is a secure context in real browsers, so the simplest path is:

```
open <artifact>.html      # macOS; xdg-open on Linux, start on Windows
```

Some sandboxes and automation block `file://`. Always also emit the one-line local-server fallback:

```
python3 -m http.server 8000   # then visit http://localhost:8000/<artifact>.html
```

Both are secure contexts, so clipboard copy works under either.

---

## 8. The transient-artifact rule (hard constraint)

**The HTML is never committed.** `SYSTEM-OVERVIEW.md` §Philosophy: *"Nothing persists in the filesystem that isn't code, skills, or the compounding knowledge base."* The recap is the same discipline `/prototype` uses — the answer is durable, the artifact is throwaway.

- Write it to a gitignored `.context/` path or a `mktemp` file, never into the tracked tree.
- Delete it (and any screenshots) when the review round is done. What persists is the *decision* — sign-offs and any items promoted to GitHub PR review comments — not the file.
- If you find yourself wanting to keep the HTML "for reference," that is the signal to promote its durable content to a PR comment or `docs/solutions/` entry instead.
