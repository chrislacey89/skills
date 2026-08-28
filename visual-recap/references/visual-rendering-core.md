# Visual Rendering Core

The shared rendering vocabulary and quality bar for Skill Kit's visual review surfaces — `/visual-recap` and the `/walk-commits` callout enhancement. It is the kit-native analog of Builder.io's shared `wireframe.md` / `canvas.md` cores, with one deliberate difference: **this is a vocabulary the agent authors HTML against, not a renderer we ship and version.** There is no npm package, no build step, no committed app, no MCP connector, and no hosted database. The agent is the renderer; this file is the spec it writes to.

> **Why a shared core at all.** Two skills render line-anchored callouts over a diff. Without one quality bar they drift — two callout shapes, two copy formats, two dark-mode palettes, and "renderer" quietly grows into an app. This file is the single bar both author against. If you are tempted to ship reusable JavaScript instead of describing what the agent should hand-author, stop: that is the lock-in this whole surface exists to avoid (Norman, *featuritis*; the artifact must stay knowledge-in-the-world, not a maintained component library).
>
> **A copyable skeleton is not a runtime library.** The canonical token-and-markup skeleton in `visual-recap-design.md` (§3, §6) is a *reference the agent inlines* into a still-self-contained, still-hand-authored file — the same status as the §4 `recap-feedback v1` serializer. That is allowed and is the cure for run-to-run drift. What stays forbidden is a *runtime dependency*: a package, a build step, a server, a CDN call, or versioned JavaScript the artifact imports. The test is unchanged — open the file with the network off; if it still reads, you copied a skeleton, not shipped a library.

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
- Model-*authored* structured blocks are the exception, and there are two. The first is the **UI wireframe** (`visual-recap-design.md` §9). Its labels, controls, and states must still come from diff-visible strings and component names — never invented copy — and when the layout is inferred rather than read from the diff, the caption must say "layout inferred." The second is the **options-comparison**, below.

A recap that violates grounding is worse than no recap. When in doubt, show less and assert less.

### Forward-looking blocks: cited or visibly asserted

The **options-comparison** block (`visual-recap-design.md` §11) compares futures that have not been built. Most of its cells therefore have no diff to derive from, which makes it a *categorically wider* carve-out than the wireframe's — the wireframe is still bounded to diff-visible strings, and this one has no diff at all. Grounding cannot mean "derived by tooling" here, so it shifts to a question the block can actually answer: **does this claim have a source, and does the render say so?**

- **Cited** — the cell is quoted from, or directly derived from, something that already exists: the current text at `file:line`, an issue or PR body, a research-archive entry, test output, a published spec. The cell renders normally and **shows its source**.
- **Asserted** — the cell is the model's judgment about a state that does not exist yet: a projected cost, a claimed benefit, drafted replacement text. The cell renders with a visible `asserted` treatment and never carries a cited cell's weight.
- **Support asymmetry must render as visual asymmetry.** N identically-weighted panels claim N equally-evidenced options. If one option is three-quarters cited and another is three-quarters asserted, the panels must not look the same — show the per-option cited/asserted split, and chip any option with **two-thirds or more of its cells asserted**. The bar is a number rather than "mostly" because the example in `visual-recap-design.md` §11 is copied verbatim, so a judgment call at the rule becomes a different judgment call at every render; at two-thirds, a 4-of-5-asserted option chips and a 3-of-5 does not. This is **Lie Factor ≤ 1 applied to argument** rather than to magnitude: the same rule as "do not render a one-line tweak with the weight of a 200-line rewrite," measured in evidence instead of lines.
- **Floor — every option carries at least one cited cell.** An option grounded in nothing is not an alternative rendered at the same size as the alternatives; it is a fiction rendered at that size. If an option has nothing citable, *that is the finding* — say so in prose and drop or rework the option. Do not pad the panel to make the grid look even.

The status quo this replaces is not neutral. N prose bullets are also model-authored, also identically weighted, and carry **no** requirement to name their evidence — so the uncodified version is the same Lie Factor with no bar at all.

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

Ten blocks cover the surface — nine for reviewing a finished change, plus one forward-looking block for comparing options that do not exist yet. Each is a *semantic role* with a canonical shape: **copy the per-block markup from the canonical skeleton (`visual-recap-design.md`), fill the grounded data and prose, and deviate only where the change genuinely needs it.** Keep it minimal, and only render the blocks the change actually needs. The skeleton is a copyable reference you inline (exactly like the §4 serializer), not a shipped widget — copying it instead of re-deriving the markup each run is what keeps two recaps of similar changes recognizably the same surface, so the reviewer reads the diff instead of re-learning the layout.

| Block | Role | Grounded inputs (tooling) | Authored (prose) |
|---|---|---|---|
| **overview** | Read-intent-first header: scale (files, ±LOC, commits), reading mode, what moved | `git diff --stat`, commit count | the 1–3 sentence "what this change is" |
| **file-tree + change-flags** | The topology — which files moved, each flagged | file list, ±LOC per file | per-file flag: `new` / `moved` / `load-bearing` / `mechanical` / `risky` |
| **annotated-diff** | Split before/after for one hunk, callouts anchored to after-side lines, with a one-line intent summary above it | the hunk text, line numbers | the hunk `summary` (intent) and each callout `note` |
| **callout** | A note anchored to a line range, rendered *at* that line | `lines: "42-47"` from the real hunk | the `note` |
| **before/after** | Small-multiple comparison of two states of the same unit — labeled side-by-side columns; stacked frames when the content is too wide to halve, never a toggle that hides one side | both states' text | which difference matters |
| **diagram** | Architecture / data-flow / sequence when topology needs a picture | — | CSS primitive for simple flow/sequence (default); Mermaid opt-in for complex graphs |
| **data-model card** | The resulting schema shape of a changed entity, per-field change flags with struck-through `was:` prior types | the migration/schema diff text | the change-flag judgments and one compatibility sentence (breaking / risky / non-breaking, for whom) |
| **api-endpoint card** | The resulting API contract of a changed route — method, path, changed params/responses flagged | the route/handler diff text | same as data-model card |
| **wireframe** | The visible UI delta when the diff changes rendered UI: entry surface → interaction surface → resulting state (+ role variants when permissions changed) | diff-visible labels, strings, component names | the wireframe HTML itself (one of the two model-authored exceptions, §1) — mark inferred layout as inferred |
| **options-comparison** | N mutually exclusive options as identical panels in one eyespan — same attributes, same order, down every column (the forward-looking block; no diff exists yet) | the **cited** cells: current text at `file:line`, issue/PR bodies, research entries, test output | the **asserted** cells — projected costs, benefits, drafted resulting text — each marked `asserted` and each option's cited/asserted split shown (§1) |

**CSS-first diagrams; Mermaid for complex graphs.** A recap's diagrams are almost always a simple flow or short sequence — these have no layout problem to solve, so the default is the pure-CSS diagram primitive (`.fc-*`, `visual-recap-design.md` §1/§5): it renders identically offline, needs no CDN, and has no parse grammar. Reach for embedded Mermaid (via `/mermaid`) **only** for genuinely complex graphs — a dense DAG, ER, or class diagram — that need real auto-layout; that is the case the "do not hand-roll graph layout" rule still guards. This is a different context from issue #83, which chose Mermaid for **GitHub-bound markdown** (rendered natively, no CDN) — that decision stands. The boundary: GitHub-rendered markdown → Mermaid; self-contained offline HTML → CSS-first. The rendering core owns callouts and diffs, not graph layout.

**Contract changes headline as cards, not source.** When the diff changes a schema or an API
surface, the reviewer wants the *resulting contract* — "`sessions` gained `refresh_token_id`,
`expires_at` changed type" — before (often instead of) the literal `ALTER TABLE` or handler
hunk. Render it as a data-model / api-endpoint card (`visual-recap-design.md` §8), grounded
field-by-field in the real diff; keep the literal SQL/handler excerpt for when the exact
statement still matters.

**When the finding is a command's observed output, render the transcript, not prose.** Some changes are about what a command *does* rather than what its source says — the class `CLAUDE.md` § "Commands a skill documents" exists for, where a wrong exit code or flag behavior ships silently and no diff line shows it. Render those in the **annotated-diff** or **before/after** row with executed output as the grounded input: the exact invocation, then the real captured output, using the same `--add` / `--del` washes and margin markers those rows already use. §1 already admits test output as a *cited* grounded input for the forward-looking block; this is the retrospective placement of the same thing, so the output is copied from a real run and never retyped from memory — an invented transcript is the Grounding Rule's worst case, a fabrication wearing the costume of evidence. This is not an eleventh block: it is the existing rows with a different grounded input.

**Options compare as panels, never as sequence.** When a skill has generated N mutually exclusive options, prose describes them one after another — and Tufte names that as the comparison anti-pattern outright: *"The viewer cannot compare what they cannot see at the same time. Memory is not vision."* Constancy of Design is what makes panels comparable, so every option carries the same attributes in the same order, and only the content differs. Two things are visible in panels and invisible in prose by construction: **domination** (one option paying a cost while closing no question — a relation *between* options, which sequence never shows two of at once) and **a missing option**, which the empty space in a matrix makes obvious. The threshold that triggers this block, and its relationship to the `AskUserQuestion` menu that takes the choice afterward, live in `next-step-menu.md`; the markup lives in `visual-recap-design.md` §11.

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
- data-model card → `dm-<entity-slug>` (e.g. `dm-sessions`)
- api-endpoint card → `ep-<method>-<path-slug>` (e.g. `ep-post-api-auth-refresh`)
- wireframe → `wf-<slug>` (e.g. `wf-share-popover`)
- options-comparison option → `opt-<option-slug>` (e.g. `opt-reconcile-182-now`)

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
      const parts = [];                         // em-dash separates verdict from note,
      if (verdict) parts.push(verdict);         // and only appears when both are present —
      if (note) parts.push('"' + note + '"');   // so a verdict-less question serializes as
      lines.push(`- ${kind}#${id}: ${parts.join(' — ')}`); // `question#q-1: "…"`, per §4
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
- **A diagram fills its frame.** The default CSS primitive (`.fc-*`, §1/§5) is full-width by construction. If you take the Mermaid opt-in for a complex graph, never render its SVG at intrinsic size — size it to the column width (`.mermaid svg{width:100%;height:auto}`, per the `visual-recap-design.md` §1/§5 skeleton). A tiny centered diagram starves the data-ink the section exists to show.
- **Respect the reading budget — it is a ceiling *and* a floor** (Cohen / Rigby: ~100–300 LOC, 30–60 min, <400–500 LOC/hr). The recap is *author preparation*, so it must itself stay inside the budget: **3–8 key files/hunks, each with a one-line intent summary and a few high-signal callouts** — focused excerpts (~150 lines max each), not every hunk. A recap that reproduces the whole diff has rebuilt the thing the reviewer was already going to scroll. But the budget is also a floor: a surface that was worth rendering at all owes the reviewer substantially more than a file list — a sparse three-block recap of a 40-file change forces them back into the raw diff, which under-serves them exactly as much as a wall over-serves them. If the change is too big for one budget, say so and recommend chunking — do not render a wall, and do not render a stub.

---

## 6. Inline CSS is load-bearing; CDN libraries are enhancement-only

The artifact must read *identically* with no network. Proven by spike: a real recap used **zero** Tailwind utility classes — it was 100% inline CSS and degraded to an identical file offline.

- **Copy the canonical token core** from `visual-recap-design.md` §1 — a fixed `:root`/`[data-theme="dark"]` block of named CSS variables (`--bg`, `--fg`, `--add`, `--del`, `--risk`, the `--flag-*` and `--sx-*` ramps, a base-16 spacing scale, …), with light as the default and dark flipped on `[data-theme]`. Keep the variable names; do not re-derive a fresh palette per run. This is the load-bearing layer; it must not depend on any CDN.
- **Forcing function — confirm the token core is canonical before presenting.** The artifact's `:root`/`[data-theme]` block must be the canonical `visual-recap-design.md` §1 set (canonical variable names and values), **not** a palette, font stack, or chrome re-derived from the app under review. A review instrument stays visually independent of its subject; the temptation to theme the recap in a well-designed app's own aesthetic is the deviation most likely to occur and most harmful when it does. This is a checked step, not stated hope — verify it (Norman: *knowledge in the world, not the head*; Gawande: the killer-item an expert skips under load).
- **Reach for a CDN library only where it earns its place** — e.g. highlight.js for syntax coloring — and **always with a no-CDN fallback** so the artifact still reads when the CDN is blocked. Name that fallback rather than gesturing at one: it is `visual-recap-design.md` §1's `--sx-*` tokens, applied by hand at authoring time against that section's role table. Tailwind-via-CDN works but is not needed; do not make the artifact depend on it.
- **Do not hand-roll a tokenizer.** A regex lexer written into the artifact looks safe because it is easy to gate on losslessness — rendered `textContent` equal to the source — and losslessness is the wrong measurement: it proves no character was dropped, not that any token was typed correctly. Measured against 13 adversarial one-liners (#305), all 13 passed the losslessness gate and **11 were mis-colored** — `pnpm add zod` colored `add` as a git subcommand, `docs/log/README.md` colored `log`, `a=b#c` became a comment, a heredoc body of markdown tokenized as shell. Under the Grounding Rule a plausible wrong color is worse than no color, because the reviewer trusts it and skips the line it got wrong. You are reading the diff and you know its language: apply the §1 tokens by hand, or take highlight.js with the fallback above — either one carries the language context a bare-word regex list does not.
- The test: open the file with the network off. If it still reads, you built it right.

---

## 7. Open / serve guidance the skill should emit

**Confirm a Mermaid diagram renders before presenting (DO-CONFIRM).** The default CSS diagram
primitive (§5) needs no such check — it has no parse grammar and no CDN, so it is correct the
moment it is written. This gate applies **only when you took the Mermaid opt-in** for a complex
graph: verify it renders without a parse error before handing the artifact to the reviewer — a
quick load, or a re-check against the `visual-recap-design.md` §5 label-safety rules. The
`<pre class="mermaid">` source fallback is *not* a substitute: it shows the source text, which
is exactly what fails to parse. This is a lightweight verification, not a build dependency — it
must not mandate a headless browser or erode the offline-first ethos (§6). Authoring the
diagram via `/mermaid` (which verifies its own render, #94) discharges this check up front.

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
