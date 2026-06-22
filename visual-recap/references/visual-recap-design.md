# Visual Recap — Canonical Design Skeleton

The fixed token system and per-block markup that Skill Kit's visual review surfaces copy
from. It is the **canonical skeleton** referenced by `visual-rendering-core.md` §3 and §6,
shared by `/visual-recap`, the `/walk-commits` per-commit callouts, and the future
`/visual-plan`.

> **This is a reference you inline, not a library you ship.** Exactly like the
> `recap-feedback v1` serializer in `visual-rendering-core.md` §4: copy the token core and
> the block markup below into your single self-contained `.html` file, then fill only the
> grounded data (paths, line numbers, hunk text — per the Grounding Rule) and the prose
> (notes, intent summaries, flags). There is no npm package, no build step, no import, and
> no runtime call. The output stays one hand-authored file that reads identically offline.
> **Deviate where the change genuinely needs it** — a diagram-heavy recap may drop the
> before/after block, a one-hunk change may skip the file-tree — but start from this shape
> so two recaps of similar changes come out recognizably the same, and a reviewer reads the
> diff instead of re-learning the layout each run (Refactoring UI: *systematize choices*;
> Norman: *knowledge in the world, not in the head*).

The values below are the proven reference (the "Visual Recap v2" surface): dark-first deep
blue-ink canvas, a single electric-violet accent, monospace-forward dense layout, a fixed
272px rail beside a centered ≤1000px scrolling column running overview → files → diagram →
annotated changes → before/after → review. Every semantic color is tuned for WCAG AA
contrast against its surface in **both** themes — light is the `:root` default, dark flips
on `[data-theme="dark"]`.

---

## 1. The token core (copy verbatim)

Paste this `<style>` block into `<head>`. It is the load-bearing layer — named CSS variables
flipped on `[data-theme]`, no CDN, no web fonts (two native system stacks so the surface
works fully offline). These variable names are the canonical set; do not rename them per run.

```html
<style>
  :root{
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
    --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace;
    /* spacing — base-16, non-linear (Refactoring UI scale) */
    --s1:4px;--s2:8px;--s3:12px;--s4:16px;--s5:24px;--s6:32px;--s7:48px;--s8:72px;
    /* radii */
    --r1:5px;--r2:8px;--r3:14px;
    /* light theme (default) */
    --bg:hsl(225 30% 99%);
    --bg-subtle:hsl(225 28% 97%);
    --bg-inset:hsl(225 24% 95%);
    --bg-elev:hsl(0 0% 100%);
    --fg:hsl(225 32% 12%);
    --fg-muted:hsl(222 13% 42%);
    --fg-faint:hsl(222 12% 62%);
    --border:hsl(225 20% 90%);
    --border-strong:hsl(225 16% 82%);
    --accent:hsl(255 78% 58%);
    --accent-dim:hsla(255 78% 58% / 0.12);
    --accent-glow:hsla(255 78% 58% / 0.45);
    --add:hsl(150 68% 32%);
    --add-bg:hsl(150 58% 95.5%);
    --del:hsl(356 66% 47%);
    --del-bg:hsl(356 84% 97%);
    --risk:hsl(32 90% 42%);
    --mark-bg:hsla(255 78% 58% / 0.10);
    /* file change-type flags — five calm, distinct hues */
    --flag-new:hsl(212 78% 50%);
    --flag-moved:hsl(265 60% 58%);
    --flag-load:hsl(28 84% 46%);
    --flag-mech:hsl(220 9% 50%);
    --flag-risky:hsl(356 66% 52%);
    /* syntax tokens — tuned to never clash with add/del */
    --sx-k:hsl(265 60% 52%);  /* keyword */
    --sx-f:hsl(212 74% 44%);  /* function */
    --sx-s:hsl(160 60% 34%);  /* string */
    --sx-n:hsl(28 80% 44%);   /* number */
    --sx-t:hsl(32 72% 42%);   /* type */
    --sx-c:hsl(222 12% 56%);  /* comment */
    --shadow:0 1px 2px hsla(225 40% 20% / 0.04),0 8px 24px -12px hsla(225 40% 20% / 0.12);
  }
  [data-theme="dark"]{
    --bg:hsl(228 24% 6%);
    --bg-subtle:hsl(228 20% 8.5%);
    --bg-inset:hsl(228 18% 12%);
    --bg-elev:hsl(228 19% 10%);
    --fg:hsl(222 24% 92%);
    --fg-muted:hsl(222 12% 58%);
    --fg-faint:hsl(222 10% 40%);
    --border:hsl(228 16% 16%);
    --border-strong:hsl(228 14% 24%);
    --accent:hsl(256 92% 74%);
    --accent-dim:hsla(256 92% 74% / 0.14);
    --accent-glow:hsla(256 92% 74% / 0.5);
    --add:hsl(150 58% 56%);
    --add-bg:hsla(150 66% 46% / 0.12);
    --del:hsl(2 82% 70%);
    --del-bg:hsla(356 76% 60% / 0.12);
    --risk:hsl(38 96% 64%);
    --mark-bg:hsla(256 92% 74% / 0.13);
    --flag-new:hsl(212 90% 68%);
    --flag-moved:hsl(265 80% 76%);
    --flag-load:hsl(32 94% 64%);
    --flag-mech:hsl(220 12% 62%);
    --flag-risky:hsl(2 82% 70%);
    --sx-k:hsl(266 86% 80%);
    --sx-f:hsl(212 94% 78%);
    --sx-s:hsl(155 64% 64%);
    --sx-n:hsl(35 92% 70%);
    --sx-t:hsl(35 88% 72%);
    --sx-c:hsl(222 12% 48%);
    --shadow:0 1px 2px hsla(0 0% 0% / 0.3),0 16px 40px -16px hsla(0 0% 0% / 0.6);
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg)}
  a{color:inherit}
  ::selection{background:var(--accent-dim)}

  /* A few stateful classes — the one place classes beat inline styles, because the
     active state is toggled by the small script in §8. Everything else stays inline. */
  .vr-callout{border:1px solid var(--border);border-radius:var(--r2);background:var(--bg-elev)}
  .vr-callout.is-active{box-shadow:0 0 0 1px var(--accent),0 18px 40px -16px var(--accent-glow)}
  .vr-line.is-active{background:var(--mark-bg)}
  .vr-marker{display:inline-flex;align-items:center;justify-content:center;border-radius:999px;
    border:none;background:var(--accent);color:#fff;font-weight:700;font-family:var(--sans);cursor:pointer}
  .vr-marker.is-active{box-shadow:0 0 0 3px var(--accent-dim)}

  /* Embedded Mermaid sizes to its frame, never its intrinsic size. CSS-first and
     offline-safe — this rule alone fixes the too-small diagram even with the network off
     (the §5 Mermaid-init script is enhancement-only). */
  .mermaid svg{width:100%;max-width:100%;height:auto;display:block}
</style>
```

**Type scale** (set inline where used; built with weight + tracking, not size inflation):
display 30px/600/−0.02em · stat 22px/680 tabular · title 15px/650 · body 14–16px/1.5–1.6 ·
overline 11px/600 uppercase 0.16em · meta (mono) 11px · code (split) 12.5px/1.75 · code
(before/after) 13px/1.9.

---

## 2. The shell (rail + scrolling column)

```html
<div id="vr-root" data-theme="dark" style="min-height:100vh;background:var(--bg);color:var(--fg);font-family:var(--sans);font-size:14px;line-height:1.5;-webkit-font-smoothing:antialiased">
  <div style="display:grid;grid-template-columns:272px minmax(0,1fr);align-items:start">

    <!-- RAIL: brand · change scale · scroll-spy TOC · theme toggle -->
    <aside style="position:sticky;top:0;height:100vh;border-right:1px solid var(--border);padding:var(--s6) var(--s5);display:flex;flex-direction:column;gap:var(--s6);background:var(--bg-subtle);overflow:hidden">
      <div style="display:flex;align-items:center;gap:var(--s2)">
        <span style="display:inline-flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:7px;background:var(--accent);color:#fff;font-weight:700;font-size:13px">R</span>
        <span style="font-size:15px;font-weight:650;letter-spacing:-0.01em">Visual Recap</span>
      </div>
      <div style="font-family:var(--mono);font-size:11px;color:var(--fg-muted);display:flex;align-items:center;gap:6px">
        <span style="width:6px;height:6px;border-radius:99px;background:var(--add)"></span>BRANCH_NAME
      </div>
      <!-- change scale (grounded: git diff --stat) -->
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:var(--s3) var(--s4)">
        <div><div style="font-size:22px;font-weight:680;letter-spacing:-0.02em;font-variant-numeric:tabular-nums">N</div><div style="font-size:11px;color:var(--fg-muted)">files changed</div></div>
        <div><div style="font-size:22px;font-weight:680;letter-spacing:-0.02em;font-variant-numeric:tabular-nums">N</div><div style="font-size:11px;color:var(--fg-muted)">commits</div></div>
        <div><div style="font-family:var(--mono);font-size:15px;font-weight:600;font-variant-numeric:tabular-nums"><span style="color:var(--add)">+N</span> <span style="color:var(--del)">−N</span></div><div style="font-size:11px;color:var(--fg-muted)">net diff</div></div>
        <div><div style="font-size:15px;font-weight:600;display:flex;align-items:center;gap:5px"><span aria-hidden="true">🔒</span>N</div><div style="font-size:11px;color:var(--fg-muted)">secrets masked</div></div>
      </div>
      <!-- scroll-spy TOC: brighten the in-view section's label + accent spine -->
      <nav style="display:flex;flex-direction:column;margin-top:auto">
        <div style="font-size:10px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s2)">Contents</div>
        <a href="#sec-overview" style="display:flex;align-items:center;gap:11px;padding:7px 0;text-decoration:none;font-size:13px;font-weight:500;color:var(--fg-muted)"><span style="width:2px;height:15px;background:var(--accent);border-radius:2px"></span><span style="font-family:var(--mono);font-size:11px;width:14px">01</span>Overview</a>
        <!-- …files 02, diagram 03, changes 04, compare 05, review 06 — same shape -->
      </nav>
      <div style="display:flex;align-items:center;justify-content:flex-end;padding-top:var(--s4);border-top:1px solid var(--border)">
        <button onclick="toggleTheme()" style="display:inline-flex;align-items:center;gap:7px;padding:5px 11px;border:1px solid var(--border-strong);border-radius:999px;background:var(--bg-elev);color:var(--fg);font-family:var(--sans);font-size:12px;font-weight:550;cursor:pointer">◐ Theme</button>
      </div>
    </aside>

    <!-- MAIN: one scrolling column, ≤1000px, centered -->
    <main style="max-width:1000px;width:100%;margin:0 auto;padding:var(--s8) var(--s7)">
      <!-- the six blocks of §3–§7 drop in here, each separated by margin-top:var(--s8) -->
    </main>
  </div>
</div>
```

Each `<section>` carries `style="scroll-margin-top:var(--s7)"` and is separated from the
previous by `margin-top:var(--s8)`. An **overline label** heads each section:

```html
<div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">04</span> &nbsp;Annotated changes</div>
```

---

## 3. Block: overview

Read-intent-first header — the one-line thesis, the 1–3 sentence "what this change is," and
a magnitude bar (segment width = change size, color = flag). The bar's widths are grounded
in `git diff --stat`.

```html
<section id="sec-overview" style="scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--accent);margin-bottom:var(--s4)">Pull request recap</div>
  <h1 style="margin:0;font-size:30px;line-height:1.28;font-weight:600;letter-spacing:-0.02em;max-width:22ch;text-wrap:balance">ONE-LINE THESIS, with the key noun in <span style="color:var(--accent)">accent</span>.</h1>
  <p style="margin:var(--s5) 0 0;font-size:16px;line-height:1.6;color:var(--fg-muted);max-width:64ch;text-wrap:pretty">1–3 sentences of intent — what this change is and why.</p>
  <div style="margin-top:var(--s6)">
    <div style="display:flex;height:9px;gap:3px;border-radius:99px;overflow:hidden">
      <span title="path · load-bearing" style="width:26%;background:var(--flag-load);border-radius:99px"></span>
      <span title="path · new"          style="width:36%;background:var(--flag-new);border-radius:99px"></span>
      <span title="path · risky"        style="width:8%;background:var(--flag-risky);border-radius:99px"></span>
      <span title="path · moved"        style="width:3%;background:var(--flag-moved);border-radius:99px"></span>
      <span title="path · mechanical"   style="width:27%;background:var(--flag-mech);border-radius:99px"></span>
    </div>
    <div style="margin-top:var(--s2);font-size:12px;color:var(--fg-faint)">N lines touched across N files · segment width = change magnitude, color = type</div>
  </div>
</section>
```

---

## 4. Block: file-tree + change-flags

The topology — one row per file: flag · path (mono) · magnitude bar · ±counts. Each row
links to its hunk in §6. The five flag hues are fixed: `new` `moved` `load-bearing`
`mechanical` `risky`.

```html
<section id="sec-files" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">02</span> &nbsp;Changed files</div>
  <div style="display:flex;flex-direction:column;gap:6px">

    <!-- one row per file — flag color set by --flag-* var -->
    <a href="#sec-changes" style="display:grid;grid-template-columns:120px 1fr 120px auto;align-items:center;gap:var(--s4);padding:13px var(--s4);border:1px solid var(--border);border-radius:var(--r2);background:var(--bg-elev);text-decoration:none">
      <span style="justify-self:start;border:1px solid var(--flag-load);color:var(--flag-load);background:color-mix(in srgb,var(--flag-load) 12%,transparent);border-radius:999px;padding:2px 10px;font-size:11px;font-weight:600;white-space:nowrap">load-bearing</span>
      <span style="font-family:var(--mono);font-size:13px;color:var(--fg)">src/auth/session.ts</span>
      <span style="justify-self:end;display:flex;width:54px;height:6px;border-radius:99px;overflow:hidden;gap:2px"><span style="flex:48;background:var(--add)"></span><span style="flex:22;background:var(--del)"></span></span>
      <span style="font-family:var(--mono);font-size:12px;font-variant-numeric:tabular-nums;justify-self:end"><span style="color:var(--add)">+48</span> <span style="color:var(--del)">−22</span></span>
    </a>

    <!-- a moved file shows the rename inline -->
    <a href="#sec-changes" style="display:grid;grid-template-columns:120px 1fr 120px auto;align-items:center;gap:var(--s4);padding:13px var(--s4);border:1px solid var(--border);border-radius:var(--r2);background:var(--bg-elev);text-decoration:none">
      <span style="justify-self:start;border:1px solid var(--flag-moved);color:var(--flag-moved);background:color-mix(in srgb,var(--flag-moved) 12%,transparent);border-radius:999px;padding:2px 10px;font-size:11px;font-weight:600;white-space:nowrap">moved</span>
      <span style="font-family:var(--mono);font-size:13px;color:var(--fg-muted)"><span style="text-decoration:line-through;opacity:.6">authGuard.ts</span> → <span style="color:var(--fg)">middleware/authGuard.ts</span></span>
      <span style="justify-self:end;display:flex;width:54px;height:6px;border-radius:99px;overflow:hidden;gap:2px"><span style="flex:4;background:var(--add)"></span><span style="flex:4;background:var(--del)"></span></span>
      <span style="font-family:var(--mono);font-size:12px;font-variant-numeric:tabular-nums;justify-self:end"><span style="color:var(--add)">+4</span> <span style="color:var(--del)">−4</span></span>
    </a>
  </div>
</section>
```

---

## 5. Block: diagram (embed only)

When topology needs a picture, **reuse `/mermaid`** and embed the result in this frame — do
not hand-roll graph layout (Skill Kit chose embedded Mermaid as its diagram answer, #83).
`/visual-recap` (and `/walk-commits`) can invoke `/mermaid` directly to produce the source;
prefer that for any non-trivial diagram (see the label-safety note below).

The container is a **full-width block** (not flex-centered) and the `.mermaid svg` rule from
§1 stretches the diagram to fill it. The `<pre class="mermaid">` carries the diagram source —
which is also the offline fallback: with the network off (no Mermaid CDN) it renders as
readable source text rather than a blank frame.

```html
<section id="sec-diagram" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">03</span> &nbsp;Diagram</div>
  <figure style="margin:0">
    <div style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);padding:var(--s8) var(--s6);overflow:auto">
      <!-- Diagram source AND offline fallback. Mermaid (if loaded) replaces this with an
           SVG that the §1 `.mermaid svg` rule sizes to the frame. Quote every label. -->
      <pre class="mermaid" style="margin:0;font-family:var(--mono);font-size:12px;color:var(--fg-muted)">
flowchart LR
  A["session.ts"] -->|"reads token"| B["tokenStore.get()"]
  B --> C["middleware/authGuard"]
      </pre>
    </div>
    <figcaption style="margin-top:var(--s3);font-size:12px;color:var(--fg-muted)">Fig 1 · one-line caption.</figcaption>
  </figure>
</section>
```

**Label-safety (hand-authored Mermaid).** Mermaid's label grammar is unforgiving; a faithful
copy that ignores it ships a parse-error box instead of a diagram. When you write source by
hand:

- **Quote every node and edge label** — `A["text"]`, `A -->|"text"| B`. Quoting neutralizes
  the characters below.
- **Never leave raw `[ ] # ( ) { }` inside an *unquoted* label.** `[`/`]` are read as
  node-shape syntax; a bare `#` begins an HTML entity code (so `#23` breaks — write
  `"slice 23"`); `(` opens a round-node. Quote the label or rephrase.
- **No literal `<br/>` inside an unquoted label** — wrap the label in quotes first.
- **For any non-trivial diagram, author it via `/mermaid`** instead of hand-writing source.
  `/mermaid` has its own render-verification step (#94), so it catches these before the
  source reaches the artifact — the safer path the render-confirm gate (core §7) points at.

**Frame-filling render (enhancement-only; CDN per §6).** The `.mermaid svg` CSS rule already
sizes the diagram offline-first. When the Mermaid CDN is available, initialize it with
`flowchart.useMaxWidth:false` and run a post-render pass so the SVG fills the frame rather
than rendering at its intrinsic (tiny) size. This is enhancement-only — it must never replace
the `<pre class="mermaid">` source-text fallback above:

```html
<!-- enhancement-only: omit and the diagram still reads as source text offline (§6) -->
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ startOnLoad: true, flowchart: { useMaxWidth: false } });
  addEventListener('load', () => document.querySelectorAll('.mermaid svg').forEach(svg => {
    svg.removeAttribute('width'); svg.removeAttribute('height');   // drop intrinsic sizing;
    svg.style.width = '100%'; svg.style.height = 'auto';           // let §1's rule fill the frame
  }));
</script>
```

---

## 6. Block: annotated-diff + callouts

A card per hunk: header (flag · path · one-line intent), a split BEFORE/AFTER grid with
**identical scale and frame on both sides** (small-multiples constancy), and callout cards
below. Diff lines carry a 2px colored left spine and a 12%-opacity wash; the line-number
gutter is 36px. Added/removed line backgrounds use `--add-bg` / `--del-bg`. Each annotated
line gets a numbered `.vr-marker`; clicking it activates its callout (see §8). Callouts are
**direct labels** anchored at the line, never a separate legend.

Stable ids per `visual-rendering-core.md` §4: callout cards and their markers share a
`data-feedback-id="c-<file-slug>-L<line>"`.

```html
<section id="sec-changes" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">04</span> &nbsp;Annotated changes</div>

  <div style="border:1px solid var(--border);border-radius:var(--r3);overflow:hidden;background:var(--bg-elev);box-shadow:var(--shadow)">
    <!-- hunk header -->
    <div style="display:flex;align-items:flex-start;gap:var(--s3);padding:var(--s4);border-bottom:1px solid var(--border)">
      <span style="border:1px solid var(--flag-load);color:var(--flag-load);background:color-mix(in srgb,var(--flag-load) 12%,transparent);border-radius:999px;padding:2px 9px;font-size:10px;font-weight:600;white-space:nowrap;margin-top:1px">load-bearing</span>
      <div>
        <div style="font-family:var(--mono);font-size:12.5px;font-weight:600;color:var(--fg)">src/auth/session.ts</div>
        <div style="font-size:12.5px;color:var(--fg-muted);margin-top:2px;text-wrap:pretty">One-line intent summary (authored prose).</div>
      </div>
    </div>

    <!-- split diff -->
    <div style="display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr)">
      <div style="border-right:1px solid var(--border)">
        <div style="padding:6px var(--s4);font-size:10px;font-weight:600;letter-spacing:.1em;color:var(--del);border-bottom:1px solid var(--border);background:var(--bg-subtle)">BEFORE</div>
        <div style="padding:var(--s2) 0">
          <!-- a removed line: --del spine + --del-bg wash -->
          <div style="display:grid;grid-template-columns:36px minmax(0,1fr);border-left:2px solid var(--del);background:var(--del-bg)"><span style="text-align:right;padding:1px var(--s2);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">33</span><code style="font-family:var(--mono);font-size:12.5px;line-height:1.75;white-space:pre;overflow-x:auto;padding:1px var(--s3);color:var(--fg)">  <span style="color:var(--sx-k)">if</span> (!currentToken) {</code></div>
          <!-- a context line: transparent spine, no wash -->
          <div style="display:grid;grid-template-columns:36px minmax(0,1fr);border-left:2px solid transparent"><span style="text-align:right;padding:1px var(--s2);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">37</span><code style="font-family:var(--mono);font-size:12.5px;line-height:1.75;white-space:pre;overflow-x:auto;padding:1px var(--s3);color:var(--fg)">}</code></div>
        </div>
      </div>
      <div>
        <div style="padding:6px var(--s4);font-size:10px;font-weight:600;letter-spacing:.1em;color:var(--add);border-bottom:1px solid var(--border);background:var(--bg-subtle)">AFTER</div>
        <div style="padding:var(--s2) 0">
          <!-- an added + annotated line: --add spine + --add-bg, plus a numbered marker.
               The row carries .vr-line + id so the marker can wash it on activation. -->
          <div id="line-c-session-ts-L33" class="vr-line" style="display:grid;grid-template-columns:36px minmax(0,1fr);border-left:2px solid var(--add);background:var(--add-bg)"><span style="text-align:right;padding:1px var(--s2);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">33</span><code style="font-family:var(--mono);font-size:12.5px;line-height:1.75;white-space:pre;overflow-x:auto;padding:1px var(--s3);color:var(--fg)">  <span style="color:var(--sx-k)">const</span> token = <span style="color:var(--sx-k)">await</span> tokenStore.<span style="color:var(--sx-f)">get</span>(req.sessionId)<button class="vr-marker" data-feedback-id="c-session-ts-L33" onclick="setActive('c-session-ts-L33')" style="width:17px;height:17px;margin-left:8px;font-size:10px;vertical-align:middle">1</button></code></div>
        </div>
      </div>
    </div>

    <!-- callouts (direct labels, anchored below the hunk) -->
    <div style="border-top:1px solid var(--border);padding:var(--s4);display:flex;flex-direction:column;gap:var(--s3);background:var(--bg-subtle)">
      <div id="callout-c-session-ts-L33" class="vr-callout" data-feedback-id="c-session-ts-L33" data-feedback-kind="callout" onclick="setActive('c-session-ts-L33')" style="display:flex;gap:var(--s3);padding:var(--s3) var(--s4);cursor:pointer">
        <span class="vr-marker" style="flex:none;width:20px;height:20px;font-size:11px">1</span>
        <div>
          <div style="font-family:var(--mono);font-size:11px;color:var(--fg-muted);margin-bottom:3px"><span style="color:var(--flag-load)">load-bearing</span> · session.ts:33</div>
          <div style="font-size:13.5px;color:var(--fg);line-height:1.5;text-wrap:pretty">The note — one sentence of authored prose anchored to this exact line.</div>
        </div>
      </div>
    </div>
  </div>
</section>
```

A secret-masked value renders as an inert chip, never the value (per
`visual-rendering-core.md` §2): `<span style="…">••• masked</span>`.

---

## 7. Block: before/after toggle + review

**Before/after** — a segmented pill with a sliding accent thumb; both states render in an
identical frame and scale so only the code differs.

```html
<section id="sec-compare" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="display:flex;align-items:center;justify-content:space-between;gap:var(--s4);margin-bottom:var(--s4);flex-wrap:wrap">
    <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint)"><span style="font-family:var(--mono);color:var(--accent)">05</span> &nbsp;Compare</div>
    <div style="position:relative;display:inline-flex;border:1px solid var(--border-strong);border-radius:999px;padding:3px;background:var(--bg-subtle)">
      <button onclick="setSide('before')" style="position:relative;z-index:1;padding:5px 18px;border:none;border-radius:999px;background:transparent;font-family:var(--sans);font-size:12px;font-weight:600;cursor:pointer;color:var(--fg)">Before</button>
      <button onclick="setSide('after')" style="position:relative;z-index:1;padding:5px 18px;border:none;border-radius:999px;background:transparent;font-family:var(--sans);font-size:12px;font-weight:600;cursor:pointer;color:var(--fg-muted)">After</button>
      <span id="ba-thumb" style="position:absolute;top:3px;bottom:3px;width:calc(50% - 3px);border-radius:999px;background:var(--accent);left:3px;transition:left .28s cubic-bezier(.4,0,.2,1)"></span>
    </div>
  </div>
  <!-- Both panels live here. setSide() (§8) toggles their `hidden` attribute; they MUST
       carry exactly these ids. Render both in the same frame and scale — only the code differs. -->
  <div style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);min-height:200px;padding:var(--s4) 0">
    <div id="ba-before">
      <div style="display:grid;grid-template-columns:40px minmax(0,1fr)"><span style="text-align:right;padding:1px var(--s3);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">1</span><code style="font-family:var(--mono);font-size:13px;line-height:1.9;white-space:pre;overflow-x:auto;padding:1px var(--s4);color:var(--fg)"><span style="color:var(--sx-k)">let</span> currentToken = <span style="color:var(--sx-n)">null</span></code></div>
      <!-- …rest of the BEFORE state, one row per line… -->
    </div>
    <div id="ba-after" hidden>
      <div style="display:grid;grid-template-columns:40px minmax(0,1fr)"><span style="text-align:right;padding:1px var(--s3);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">1</span><code style="font-family:var(--mono);font-size:13px;line-height:1.9;white-space:pre;overflow-x:auto;padding:1px var(--s4);color:var(--fg)"><span style="color:var(--sx-k)">const</span> token = <span style="color:var(--sx-k)">await</span> tokenStore.<span style="color:var(--sx-f)">get</span>(req.sessionId)</code></div>
      <!-- …rest of the AFTER state, identical frame and scale… -->
    </div>
  </div>
  <p style="margin:var(--s3) 0 0;font-size:12px;color:var(--fg-faint)">Same frame, same scale on both sides — only the code differs.</p>
</section>
```

**Review** — verdict chips + a notes textarea + the **Copy feedback** button. The serializer
and the layered-clipboard ladder are owned by `visual-rendering-core.md` §4 — wire the
button to that `copyFeedback()` and give annotatable units their stable `data-feedback-id`s;
do not reinvent the format here.

```html
<section id="sec-review" style="margin-top:var(--s8);scroll-margin-top:var(--s7);padding-bottom:var(--s8)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">06</span> &nbsp;Your review</div>
  <div style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);padding:var(--s5)">
    <div style="display:flex;gap:var(--s2);margin-bottom:var(--s4);flex-wrap:wrap">
      <button data-verdict-chip="approve" onclick="setVerdict('approve')" style="display:inline-flex;align-items:center;gap:8px;padding:7px 15px;border-radius:999px;border:none;background:var(--bg-subtle);color:var(--fg);font-family:var(--sans);font-size:13px;font-weight:600;cursor:pointer"><span style="width:9px;height:9px;border-radius:999px;background:var(--add)"></span>approve</button>
      <button data-verdict-chip="needs-change" onclick="setVerdict('needs-change')" style="display:inline-flex;align-items:center;gap:8px;padding:7px 15px;border-radius:999px;border:none;background:var(--bg-subtle);color:var(--fg);font-family:var(--sans);font-size:13px;font-weight:600;cursor:pointer"><span style="width:9px;height:9px;border-radius:999px;background:var(--risk)"></span>needs-change</button>
      <button data-verdict-chip="block" onclick="setVerdict('block')" style="display:inline-flex;align-items:center;gap:8px;padding:7px 15px;border-radius:999px;border:none;background:var(--bg-subtle);color:var(--fg);font-family:var(--sans);font-size:13px;font-weight:600;cursor:pointer"><span style="width:9px;height:9px;border-radius:999px;background:var(--del)"></span>block</button>
    </div>
    <textarea data-feedback-note placeholder="Notes, risks, verdicts…" style="width:100%;min-height:120px;resize:vertical;padding:var(--s4);border:1px solid var(--border-strong);border-radius:var(--r2);background:var(--bg-subtle);color:var(--fg);font-family:var(--mono);font-size:13px;line-height:1.65;outline:none"></textarea>
    <div style="display:flex;align-items:center;gap:var(--s3);margin-top:var(--s4)">
      <button onclick="copyFeedback()" style="display:inline-flex;align-items:center;gap:8px;padding:9px 17px;border:none;border-radius:var(--r2);background:var(--accent);color:#fff;font-family:var(--sans);font-size:13px;font-weight:600;cursor:pointer;box-shadow:0 6px 20px -8px var(--accent-glow)">Copy feedback</button>
      <span style="font-size:12px;color:var(--fg-faint)">Copies verdict + notes as plain text.</span>
    </div>
    <!-- the visible pre-selected fallback textarea from §4 lives here too -->
  </div>
</section>
```

---

## 8. The minimal vanilla interactions

Three tiny handlers — theme toggle, callout active-state, before/after side. No framework,
no state library; if this grows routing or a store it has become the app the surface exists
to avoid (`visual-rendering-core.md` §4). The §4 `copyFeedback()` serializer is separate and
unchanged.

```html
<script>
  const root = document.getElementById('vr-root');
  function toggleTheme(){
    root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
  }
  let activeId = null;
  function setActive(id){
    if (activeId){
      document.querySelectorAll('[data-feedback-id="'+activeId+'"]').forEach(el=>el.classList.remove('is-active'));
      document.getElementById('line-'+activeId)?.classList.remove('is-active');
    }
    activeId = id;
    document.querySelectorAll('[data-feedback-id="'+id+'"]').forEach(el=>el.classList.add('is-active'));
    document.getElementById('line-'+id)?.classList.add('is-active');
  }
  function setSide(side){
    document.getElementById('ba-thumb').style.left = side === 'after' ? 'calc(50% + 0px)' : '3px';
    document.getElementById('ba-before').hidden = side === 'after';
    document.getElementById('ba-after').hidden = side !== 'after';
  }
  function setVerdict(v){
    document.querySelectorAll('[data-verdict-chip]').forEach(el=>{
      const on = el.dataset.verdictChip === v;
      el.style.background = on ? 'var(--accent-dim)' : 'var(--bg-subtle)';
      el.style.color = on ? 'var(--accent)' : 'var(--fg)';
      el.dataset.verdict = on ? v : '';        // read by the §4 serializer
    });
  }
</script>
```

---

## Do's and Don'ts

- **Do** copy the §1 token core verbatim and keep the variable names — that fixed system is
  what makes two recaps look like the same surface. Deviate in *content*, not in *tokens*.
- **Do** use the violet `--accent` only for interaction and the active state — one signal,
  used sparingly.
- **Don't** color syntax tokens with `--add` / `--del`; reserve those hues for diff
  semantics so meaning never blurs.
- **Do** annotate only the few changes that matter (3–8 callouts per recap; the core's
  reading budget).
- **Don't** add decorative drop shadows or gradients beyond `--shadow`; separate with
  whitespace, a hairline, or a tonal step (Tufte: subtract weight).
- **Do** keep both themes equal — every semantic color is already WCAG-AA-tuned in §1;
  verify any color you add against its surface in light *and* dark.
- **Don't** let the container compete with the code: no heavy borders or card chrome around
  the diff.
- **Don't** introduce a third font family or a web font — two native system stacks only, so
  the file reads identically offline.
- **Don't** turn this skeleton into a shipped/versioned/imported component library — it is a
  copyable reference, exactly like the §4 serializer. If you reach for an npm package, a
  build step, or a CDN runtime, pull it back.
