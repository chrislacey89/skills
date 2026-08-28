# Visual Recap — Canonical Design Skeleton

The fixed token system and per-block markup that Skill Kit's visual review surfaces copy
from. It is the **canonical skeleton** referenced by `visual-rendering-core.md` §3 and §6,
shared by `/visual-recap`, the `/walk-commits` per-commit callouts, and the future
`/visual-plan`. §3–§9 are the blocks that render a change which already exists (§1, §2, and §10
are the token core, the shell, and the interactions they all share); §11 is the one
forward-looking block, used by any skill that emits an N-way fork of options that do not exist
yet.

**The document has two parts, and they are two rendering modes, not two layouts of one thing.**
Everything numbered §1–§11 is **Part I — the scroll recap**: a single scrolling column for a
reviewer *auditing* a change. **Part II — the walkthrough deck** (§D1–§D9, at the end of this
file) is a paged, one-idea-per-screen shell for a reviewer being *argued through* a change with a
causal arc. Both share the §1 token core, the Grounding Rule, secret-redaction, the reading
budget, and the transient-artifact rule; they differ in shell and reading order only. The
selection rule is one line and lives in §D1: **is there one story the screens advance? deck. Is
the reviewer auditing parallel hunks? scroll.**

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
272px rail beside a centered ≤1000px scrolling column running overview → files → contracts
(when schema/API surfaces changed) → diagram → wireframes (when rendered UI changed) →
annotated changes → before/after → review. Every semantic color is tuned for WCAG AA
contrast against its surface in **both** themes — light is the `:root` default, dark flips
on `[data-theme="dark"]` — with **one documented exception.** Three syntax tokens sit below
the 4.5:1 body-text bar: `--sx-s`, `--sx-n`, and `--sx-c` in light, and `--sx-c` again in
dark. They stay legible against every surface, but do not claim AA for them and do not put
anything a reviewer must not miss in one. That exception list is exact and pinned by a
contract test, so recoloring a token means editing this sentence — not quietly widening the
claim back to "every."

---

## 1. The token core (copy verbatim)

Paste this `<style>` block into `<head>`. It is the load-bearing layer — named CSS variables
flipped on `[data-theme]`, no CDN, no web fonts (two native system stacks so the surface
works fully offline). These variable names are the canonical set; do not rename them per run —
and specifically **do not adopt the visual language of the app under review** (its palette,
fonts, or chrome). A review instrument stays visually independent of its subject: the pull to
theme the recap in a well-designed app's own aesthetic is strongest exactly where it does most
harm, because it both destroys run-to-run constancy and sprays the subject's accent onto recap
chrome that carries no diff meaning (Tufte: decoration exceeding the data).

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
    /* syntax tokens — language-agnostic roles (mapping table below the block),
       tuned to never clash with add/del */
    --sx-k:hsl(265 60% 52%);  /* keyword / command */
    --sx-f:hsl(212 74% 44%);  /* callable / subcommand */
    --sx-v:hsl(310 58% 42%);  /* variable / interpolation */
    --sx-s:hsl(160 60% 34%);  /* string */
    --sx-n:hsl(28 80% 44%);   /* literal / flag */
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
    --sx-v:hsl(312 84% 78%);
    --sx-s:hsl(155 64% 64%);
    --sx-n:hsl(35 92% 70%);
    --sx-c:hsl(222 12% 48%);
    --shadow:0 1px 2px hsla(0 0% 0% / 0.3),0 16px 40px -16px hsla(0 0% 0% / 0.6);
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg)}
  a{color:inherit}
  ::selection{background:var(--accent-dim)}

  /* A few stateful classes — the one place classes beat inline styles, because the
     active state is toggled by the small script in §10. Everything else stays inline. */
  .vr-callout{border:1px solid var(--border);border-radius:var(--r2);background:var(--bg-elev)}
  .vr-callout.is-active{box-shadow:0 0 0 1px var(--accent),0 18px 40px -16px var(--accent-glow)}
  .vr-line.is-active{background:var(--mark-bg)}
  .vr-marker{display:inline-flex;align-items:center;justify-content:center;border-radius:999px;
    border:none;background:var(--accent);color:#fff;font-weight:700;font-family:var(--sans);cursor:pointer}
  .vr-marker.is-active{box-shadow:0 0 0 3px var(--accent-dim)}

  /* CSS diagram primitive — the DEFAULT diagram (see §5). Pure CSS, no CDN, no parse
     grammar: renders identically offline and fills its frame by construction. A vertical
     spine of node cards joined by connectors; .fc-fan lays out a parallel row of children.
     Reach for embedded Mermaid (below) only for complex graphs this can't express. */
  .fc{display:flex;flex-direction:column;align-items:center;gap:0;width:100%}
  .fc-node{width:100%;max-width:600px;border:1px solid var(--border-strong);border-radius:var(--r2);
    background:var(--bg-subtle);padding:var(--s3) var(--s4);text-align:center}
  .fc-node.is-accent{border-color:var(--accent);background:var(--accent-dim)}
  .fc-node.is-artifact{border-style:dashed;border-color:var(--accent);background:var(--bg-elev)}
  .fc-node.is-muted{background:var(--bg-elev)}
  .fc-step{display:inline-block;font-size:10px;font-weight:700;letter-spacing:.14em;
    text-transform:uppercase;color:var(--accent);margin-bottom:3px}
  .fc-title{font-family:var(--mono);font-size:13px;font-weight:600;color:var(--fg)}
  .fc-sub{font-size:12px;color:var(--fg-muted);margin-top:3px;text-wrap:pretty}
  .fc-conn{display:flex;flex-direction:column;align-items:center;padding:2px 0}
  .fc-conn .fc-line{width:2px;height:16px;background:var(--border-strong)}
  .fc-conn .fc-lbl{font-size:11px;color:var(--fg-muted);margin:4px 0 2px;font-style:italic}
  .fc-conn .fc-tip{font-size:13px;line-height:1;color:var(--accent)}
  .fc-conn.is-dashed .fc-line{background:repeating-linear-gradient(var(--accent) 0 3px,transparent 3px 7px)}
  .fc-fan{display:flex;gap:var(--s3);margin-top:var(--s3);flex-wrap:wrap}
  .fc-fan .fc-node{flex:1 1 150px;max-width:none;padding:var(--s2) var(--s3);text-align:left}
  .fc-fan .fc-title{font-size:12px}

  /* Embedded Mermaid (the §5 OPT-IN, complex graphs only) sizes to its frame, never its
     intrinsic size. The init script in §5 is enhancement-only; this rule keeps an
     already-rendered SVG full-width. */
  .mermaid svg{width:100%;max-width:100%;height:auto;display:block}
</style>
```

**Syntax tokens name roles, not a language.** These six are the whole vocabulary. Do not
invent a seventh and do not repurpose one whose name does not fit what you are coloring —
that is the run-to-run drift §6's "keep the variable names" rule exists to prevent, and both
failure modes have happened here (#305). The names abbreviate *roles*; the table maps each
role onto the concrete thing it colors, in a C-family language and in shell.

| Token | Role | C-family | Shell |
|---|---|---|---|
| `--sx-k` | keyword | `const`, `await`, `if` | command — `git`, `pnpm` |
| `--sx-f` | callable | function or method name | subcommand — `rev-parse`, `add` |
| `--sx-v` | variable / interpolation | a named binding at its use site | `$BASE_REF`, `${BASE_REF}` |
| `--sx-s` | string | `"…"`, `'…'`, template text | `"…"`, `'…'`, heredoc body |
| `--sx-n` | literal / modifier | number, `true`, `null` | flag — `--porcelain`, `-n` |
| `--sx-c` | comment | `//`, `/* … */` | `# …` |

A language outside the table maps onto the same six roles — a Python `def` is a keyword, a
YAML key is a variable at its binding site. If a construct genuinely has no role here, color
it `--fg` and move on: an unmodeled construct rendered plain is honest, one rendered in a
borrowed color is a wrong answer the reviewer trusts (the Grounding Rule,
`visual-rendering-core.md` §1).

Applied — one shell hunk exercising all six, as it appears inside a diff row:

```html
<code style="font-family:var(--mono);font-size:12.5px;line-height:1.75;white-space:pre;color:var(--fg)"><span style="color:var(--sx-k)">git</span> <span style="color:var(--sx-f)">rev-parse</span> <span style="color:var(--sx-n)">--abbrev-ref</span> <span style="color:var(--sx-v)">$BASE_REF</span>   <span style="color:var(--sx-c)"># the ref, not the branch name (#298)</span>
<span style="color:var(--sx-k)">echo</span> <span style="color:var(--sx-s)">"base is <span style="color:var(--sx-v)">$BASE_REF</span>"</span></code>
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
        <!-- …then one entry per rendered section (files, contracts, diagram, wireframes, changes, compare, review), numbered in render order — same shape -->
      </nav>
      <div style="display:flex;align-items:center;justify-content:flex-end;padding-top:var(--s4);border-top:1px solid var(--border)">
        <button onclick="toggleTheme()" style="display:inline-flex;align-items:center;gap:7px;padding:5px 11px;border:1px solid var(--border-strong);border-radius:999px;background:var(--bg-elev);color:var(--fg);font-family:var(--sans);font-size:12px;font-weight:550;cursor:pointer">◐ Theme</button>
      </div>
    </aside>

    <!-- MAIN: one scrolling column, ≤1000px, centered -->
    <main style="max-width:1000px;width:100%;margin:0 auto;padding:var(--s8) var(--s7)">
      <!-- the blocks of §3–§9 drop in here (render only what the change needs), each separated by margin-top:var(--s8) -->
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

## 5. Block: diagram

Two diagram forms, and the split is by what the picture has to say — not by a global
preference for one technology.

**Decision rule (one line):** a **trivial spine** — one straight flow, a short sequence, "step 1
then step 2," no labeled edges, no branches — takes the **CSS primitive** (`.fc-*`, §1).
Anything **multi-stage or behavioral** — labeled edges, fan-outs, guards, failure states, a
before/after pair of graphs, a dense DAG, an ER or class diagram — takes **Mermaid via CDN**.
When the review context is known to be offline (a plane, an air-gapped sandbox, a CI log), take
the CSS primitive regardless and say in the caption that you did.

**This reverses #131, and the fence it reopens is named rather than stepped over.** #128/#129/
#131 made CSS the default because a Mermaid figure with no network degrades to unparsed source
text, and the surface's invariant was "reads identically with the network off." That failure
mode is real and has not gone away. What changed is evidence about the other side of the trade:
the diagrams that carried the most comprehension in the field — a before/after of a mechanism,
with labeled edges, fan-outs, and styled failure and guard nodes — are exactly the ones the CSS
spine cannot express, and the pack was teaching authors away from them. So §6's invariant is
**scoped rather than deleted**: core blocks — prose, panes, diffs, cards, the feedback loop —
must still read identically offline; a **diagram figure** may degrade, and must say so on its
own face. #129's render-confirm gate is retained unchanged (core §7).

**Every Mermaid figure carries a visible degrade note.** Not once in a footer — beside the
figure, where a reader who jumped straight to it will see it:

```html
<div class="mmd-note" style="font-size:11px;color:var(--fg-faint);margin-top:var(--s2)">
  Best rendered with an active internet connection — this figure loads Mermaid from a CDN and
  shows its source text offline. The rest of this file reads identically either way.
</div>
```

**Neither half of this contradicts #83.** #83 chose Mermaid for **GitHub-bound markdown**
(issues, PR bodies), which GitHub renders natively with no CDN at all; that decision stands and
is untouched. The boundary that changed is only inside self-contained HTML, and it is now drawn
by *what the graph needs* rather than by *how it is delivered*.

### Trivial spines — the CSS diagram primitive

A spine of `.fc-node`s separated by `.fc-conn` connectors (add `.fc-lbl` for an edge label,
`.is-dashed` for a derived/handoff edge). Nest a `.fc-fan` inside a node for a parallel row of
children. Node variants: `.is-accent` (the focal step), `.is-artifact` (a file/handoff,
dashed), `.is-muted` (context).

```html
<section id="sec-diagram" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">03</span> &nbsp;Diagram</div>
  <figure style="margin:0">
    <div style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);padding:var(--s8) var(--s6);overflow:auto">
      <div class="fc">
        <div class="fc-node is-muted"><div class="fc-title">session.ts</div></div>
        <div class="fc-conn"><div class="fc-line"></div><div class="fc-lbl">reads token</div><div class="fc-tip">▼</div></div>
        <div class="fc-node is-accent">
          <span class="fc-step">step</span>
          <div class="fc-title">tokenStore.get()</div>
          <div class="fc-sub">Resolves the session token; fans out to its sources.</div>
          <div class="fc-fan">
            <div class="fc-node is-muted"><div class="fc-title">cookie</div></div>
            <div class="fc-node is-muted"><div class="fc-title">header</div></div>
          </div>
        </div>
        <div class="fc-conn is-dashed"><div class="fc-line"></div><div class="fc-lbl">validated</div><div class="fc-tip">▼</div></div>
        <div class="fc-node"><div class="fc-title">middleware/authGuard</div></div>
      </div>
    </div>
    <figcaption style="margin-top:var(--s3);font-size:12px;color:var(--fg-muted)">Fig 1 · one-line caption.</figcaption>
  </figure>
</section>
```

The container is a **full-width block** (not flex-centered); the spine centers itself and each
node stretches to `max-width`. No script, no CDN, no render-confirm step, and no degrade note to
write — it is correct the moment it is written, which is why it stays the answer whenever the
picture is simple enough to be drawn this way and the required answer when the review context is
known to be offline.

### Multi-stage and behavioral graphs — embedded Mermaid (the default for this case)

Author the source via `/mermaid` (which verifies its own render, #94) and embed it in the same
full-width frame; the `.mermaid svg` rule from §1 sizes it. The `<pre class="mermaid">` carries
the source, which Mermaid replaces with an SVG when the CDN loads. **Be honest about the offline
state:** with no network the `<pre>` shows source text, not a diagram — a degraded fallback,
*not* an offline-equivalent render, which is why the degrade note above is required rather than
recommended. **Confirm it renders before presenting** (core §7).

```html
<!-- embed inside the same <section>/<figure>/full-width <div> frame the default example shows -->
<pre class="mermaid" style="margin:0;font-family:var(--mono);font-size:12px;color:var(--fg-muted)">
flowchart LR
  A["session.ts"] -->|"reads token"| B["tokenStore.get()"]
  B --> C["middleware/authGuard"]
</pre>
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
- **Author it via `/mermaid`** rather than hand-writing source; its render-verification step
  (#94) catches these before the source reaches the artifact.

**Frame-filling render (enhancement-only; CDN per §6).** When the Mermaid CDN is available,
initialize with `flowchart.useMaxWidth:false` and run a post-render pass so the SVG fills the
frame rather than rendering at its intrinsic (tiny) size:

```html
<!-- enhancement-only: omit and the diagram degrades to source text offline (§6) -->
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
line gets a numbered `.vr-marker`; clicking it activates its callout (see §10). Callouts are
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

## 7. Block: before/after comparison + review

**Before/after — labeled columns are the default.** Two identical frames side by side, with
`Before` / `After` as column *headers* above each frame — never a label baked inside the
frame, where it reads as part of the product UI and lands in a random corner. Both frames
share the same scale, padding, and density (small-multiples constancy), so the eye reads the
*difference*, not a layout change — a comparison the toggle defeats by hiding one state.
Columns are the structured-comparison primitive: two states of a config, a schema shape, a
rendered surface (§9), or a short code unit — read in one glance, no interaction required.

**Decision rule (one line):** can both states be read side by side without crushing the
content into unreadably narrow columns? → **columns** (default, below). Content too wide —
long code lines, a dense full-width table → the **toggle variant** further down.

```html
<section id="sec-compare" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">05</span> &nbsp;Compare</div>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:var(--s4);align-items:start">
    <div>
      <div style="font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:var(--del);margin-bottom:var(--s2)">Before</div>
      <div style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);padding:var(--s4) 0">
        <div style="display:grid;grid-template-columns:40px minmax(0,1fr)"><span style="text-align:right;padding:1px var(--s3);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">1</span><code style="font-family:var(--mono);font-size:13px;line-height:1.9;white-space:pre;overflow-x:auto;padding:1px var(--s4);color:var(--fg)"><span style="color:var(--sx-k)">let</span> currentToken = <span style="color:var(--sx-n)">null</span></code></div>
        <!-- …rest of the BEFORE state, one row per line… -->
      </div>
    </div>
    <div>
      <div style="font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:var(--add);margin-bottom:var(--s2)">After</div>
      <div style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);padding:var(--s4) 0">
        <div style="display:grid;grid-template-columns:40px minmax(0,1fr)"><span style="text-align:right;padding:1px var(--s3);font-family:var(--mono);font-size:12px;color:var(--fg-faint);user-select:none">1</span><code style="font-family:var(--mono);font-size:13px;line-height:1.9;white-space:pre;overflow-x:auto;padding:1px var(--s4);color:var(--fg)"><span style="color:var(--sx-k)">const</span> token = <span style="color:var(--sx-k)">await</span> tokenStore.<span style="color:var(--sx-f)">get</span>(req.sessionId)</code></div>
        <!-- …rest of the AFTER state, identical frame and scale… -->
      </div>
    </div>
  </div>
  <p style="margin:var(--s3) 0 0;font-size:12px;color:var(--fg-faint)">Same frame, same scale on both sides — only the content differs.</p>
</section>
```

### Variant — the toggle (wide states only)

When each state is too wide to halve — long code lines, a dense table — fall back to a
segmented pill with a sliding accent thumb; both states render in an identical frame and
scale so only the code differs. The comparison cost is real (the reviewer holds one state in
memory while viewing the other), so take this variant only when columns would crush the
content.

```html
<!-- replaces the columns grid inside the same <section> -->
<section id="sec-compare" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="display:flex;align-items:center;justify-content:space-between;gap:var(--s4);margin-bottom:var(--s4);flex-wrap:wrap">
    <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint)"><span style="font-family:var(--mono);color:var(--accent)">05</span> &nbsp;Compare</div>
    <div style="position:relative;display:inline-flex;border:1px solid var(--border-strong);border-radius:999px;padding:3px;background:var(--bg-subtle)">
      <button onclick="setSide('before')" style="position:relative;z-index:1;padding:5px 18px;border:none;border-radius:999px;background:transparent;font-family:var(--sans);font-size:12px;font-weight:600;cursor:pointer;color:var(--fg)">Before</button>
      <button onclick="setSide('after')" style="position:relative;z-index:1;padding:5px 18px;border:none;border-radius:999px;background:transparent;font-family:var(--sans);font-size:12px;font-weight:600;cursor:pointer;color:var(--fg-muted)">After</button>
      <span id="ba-thumb" style="position:absolute;top:3px;bottom:3px;width:calc(50% - 3px);border-radius:999px;background:var(--accent);left:3px;transition:left .28s cubic-bezier(.4,0,.2,1)"></span>
    </div>
  </div>
  <!-- Both panels live here. setSide() (§10) toggles their `hidden` attribute; they MUST
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

## 8. Block: contract cards (data-model + api-endpoint)

When the diff changes a schema or an API surface, the **resulting contract is the headline**,
not the SQL or the handler code. A reviewer of a migration wants "the `sessions` table gained
`refresh_token_id` and `expires_at` changed type" before (often instead of) the literal
`ALTER TABLE`. Render the contract as a card, grounded field-by-field in the real
migration/route diff; reach for the literal SQL/handler hunk in §6 only when the exact
statement still matters.

**Field-level flags reuse the diff semantics** so meaning never blurs: `--add` for an added
field/param, `--del` for a removed one, `--risk` for a modified type/shape (a contract
change *is* the compatibility risk the reviewer must weigh), `--flag-moved` for a rename. A
modified field shows its prior type inline as struck-through `was:` text — the diff-aware
detail that turns a schema listing into a schema *change*.

Both card types carry a stable `data-feedback-id` (`dm-<entity-slug>`,
`ep-<method>-<path-slug>` — `visual-rendering-core.md` §4) so reviewer notes serialize with
the rest of the feedback.

**data-model card** — one per changed entity (table, model, collection). Show every field of
a small entity; for a large one show the changed fields plus their nearest unchanged
neighbors as context rows:

```html
<section id="sec-contracts" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">03</span> &nbsp;Contracts</div>

  <div data-feedback-id="dm-sessions" data-feedback-kind="model" style="border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);overflow:hidden">
    <div style="display:flex;align-items:center;gap:var(--s3);padding:var(--s4);border-bottom:1px solid var(--border)">
      <span style="font-family:var(--mono);font-size:13px;font-weight:600;color:var(--fg)">sessions</span>
      <span style="border:1px solid var(--risk);color:var(--risk);background:color-mix(in srgb,var(--risk) 12%,transparent);border-radius:999px;padding:2px 9px;font-size:10px;font-weight:600">modified</span>
      <span style="margin-left:auto;font-family:var(--mono);font-size:11px;color:var(--fg-muted)">db/migrations/0142_sessions.sql</span>
    </div>
    <div style="font-family:var(--mono);font-size:12.5px;padding:var(--s2) 0">
      <!-- unchanged context row: transparent spine, no wash -->
      <div style="display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr) 90px;gap:var(--s3);align-items:center;padding:6px var(--s4);border-left:2px solid transparent"><span style="color:var(--fg)">id</span><span style="color:var(--fg-muted)">uuid · pk</span><span></span></div>
      <!-- added field: --add spine + wash -->
      <div style="display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr) 90px;gap:var(--s3);align-items:center;padding:6px var(--s4);border-left:2px solid var(--add);background:var(--add-bg)"><span style="color:var(--fg)">refresh_token_id</span><span style="color:var(--fg-muted)">uuid · nullable</span><span style="justify-self:end;color:var(--add);font-size:10px;font-weight:600;font-family:var(--sans)">added</span></div>
      <!-- modified field: --risk spine, struck-through prior type -->
      <div style="display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr) 90px;gap:var(--s3);align-items:center;padding:6px var(--s4);border-left:2px solid var(--risk)"><span style="color:var(--fg)">expires_at</span><span style="color:var(--fg-muted)">timestamptz <span style="color:var(--fg-faint);text-decoration:line-through">was: integer</span></span><span style="justify-self:end;color:var(--risk);font-size:10px;font-weight:600;font-family:var(--sans)">modified</span></div>
      <!-- removed field: --del spine + wash, struck-through name -->
      <div style="display:grid;grid-template-columns:minmax(0,1.2fr) minmax(0,1fr) 90px;gap:var(--s3);align-items:center;padding:6px var(--s4);border-left:2px solid var(--del);background:var(--del-bg)"><span style="color:var(--fg-muted);text-decoration:line-through">legacy_ttl</span><span style="color:var(--fg-faint)">integer</span><span style="justify-self:end;color:var(--del);font-size:10px;font-weight:600;font-family:var(--sans)">removed</span></div>
    </div>
  </div>
</section>
```

**api-endpoint card** — method badge, path, endpoint-level change chip, then one row per
changed param / request field / response field with the same flag treatment. A wholly
removed endpoint renders its path struck-through with a `removed` chip and needs no rows:

```html
<div data-feedback-id="ep-post-api-auth-refresh" data-feedback-kind="endpoint" style="margin-top:var(--s4);border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);overflow:hidden">
  <div style="display:flex;align-items:center;gap:var(--s3);padding:var(--s4);border-bottom:1px solid var(--border)">
    <span style="font-family:var(--mono);font-size:11px;font-weight:700;padding:3px 8px;border-radius:var(--r1);background:var(--accent-dim);color:var(--accent)">POST</span>
    <span style="font-family:var(--mono);font-size:13px;font-weight:600;color:var(--fg)">/api/auth/refresh</span>
    <span style="border:1px solid var(--add);color:var(--add);background:color-mix(in srgb,var(--add) 12%,transparent);border-radius:999px;padding:2px 9px;font-size:10px;font-weight:600">added</span>
    <span style="margin-left:auto;font-family:var(--mono);font-size:11px;color:var(--fg-muted)">src/routes/auth.ts</span>
  </div>
  <div style="font-family:var(--mono);font-size:12.5px;padding:var(--s2) 0">
    <div style="display:grid;grid-template-columns:110px minmax(0,1.2fr) minmax(0,1fr) 90px;gap:var(--s3);align-items:center;padding:6px var(--s4);border-left:2px solid var(--add);background:var(--add-bg)"><span style="color:var(--fg-faint);font-size:11px">body</span><span style="color:var(--fg)">refreshToken</span><span style="color:var(--fg-muted)">string · required</span><span style="justify-self:end;color:var(--add);font-size:10px;font-weight:600;font-family:var(--sans)">added</span></div>
    <div style="display:grid;grid-template-columns:110px minmax(0,1.2fr) minmax(0,1fr) 90px;gap:var(--s3);align-items:center;padding:6px var(--s4);border-left:2px solid var(--risk)"><span style="color:var(--fg-faint);font-size:11px">200 body</span><span style="color:var(--fg)">expiresAt</span><span style="color:var(--fg-muted)">string (ISO) <span style="color:var(--fg-faint);text-decoration:line-through">was: number</span></span><span style="justify-self:end;color:var(--risk);font-size:10px;font-weight:600;font-family:var(--sans)">modified</span></div>
  </div>
</div>
```

A compatibility-sensitive change gets one short authored sentence directly beside its card
(is it breaking, risky, or non-breaking, and for whom) — that judgment is the prose the
model owns; the fields themselves stay mechanically derived.

---

## 9. Block: UI wireframe

When the diff changes rendered UI — layout, controls, navigation, dialogs, visible states,
design tokens — show the visual delta; code diffs are not a substitute for what the user
will see. Wireframes are one of the two **model-authored** structured blocks (the Grounding
Rule exceptions, `visual-rendering-core.md` §1; the other is the options-comparison, §11): every label, control, and state must come from
diff-visible strings and component names, and when the layout is inferred rather than read
from the diff, the caption says so ("layout inferred").

**Coverage:** show the **entry surface** where the change appears, the **interaction
surface** that opens or changes (popover, dialog, tab, inline editor), and the **resulting
state** — plus role variants when permissions changed. After-only is fine for purely
additive UI; skip wireframes entirely when the UI delta is trivial. Zoom in on the changed
sub-surface with the matching frame variant — never redraw a whole page for a popover
change.

Paste this style block alongside the §1 core only when the recap renders UI changes:

```html
<style>
  /* UI wireframe primitives (§9) — same tokens, no new palette */
  .wf-frame{border:1.5px solid var(--border-strong);border-radius:var(--r3);background:var(--bg);overflow:hidden}
  .wf-frame.is-popover{max-width:320px;border-radius:var(--r2)}
  .wf-frame.is-panel{max-width:360px}
  .wf-frame.is-mobile{max-width:260px;border-radius:18px}
  .wf-chrome{display:flex;align-items:center;gap:var(--s2);padding:8px var(--s3);border-bottom:1px solid var(--border);background:var(--bg-subtle)}
  .wf-dot{width:8px;height:8px;border-radius:99px;background:var(--border-strong)}
  .wf-url{flex:1;font-family:var(--mono);font-size:11px;color:var(--fg-muted);background:var(--bg-inset);border-radius:999px;padding:3px 10px;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .wf-body{display:flex;flex-direction:column;gap:var(--s3);padding:var(--s4)}
  .wf-card{border:1px solid var(--border);border-radius:var(--r2);background:var(--bg-elev);padding:var(--s3) var(--s4)}
  .wf-pill{display:inline-block;border:1px solid var(--border-strong);border-radius:999px;padding:2px 10px;font-size:11px;font-weight:600;color:var(--fg-muted)}
  .wf-pill.is-accent{border-color:var(--accent);color:var(--accent);background:var(--accent-dim)}
  .wf-btn{display:inline-flex;align-items:center;justify-content:center;border:1px solid var(--border-strong);border-radius:var(--r1);padding:6px 14px;font-size:12px;font-weight:600;background:var(--bg-elev);color:var(--fg)}
  .wf-btn.is-primary{border-color:var(--accent);background:var(--accent);color:#fff}
  .wf-muted{color:var(--fg-muted);font-size:12px}
  .wf-spacer{flex:1}
</style>
```

**Quality rules** (each exists because its violation has shipped a bad mockup):

- **Tokens, never hex; no decorative shadows.** The theme toggle must flip the wireframe
  too; fake depth reads as content (Tufte).
- **Real product content, never lorem or gray bars.** Labels, counts, and button text come
  from the diff and the code it touches — a wireframe with invented copy violates grounding.
- **Full-width chrome bars.** Headers/toolbars are one flex row spanning the frame with a
  `.wf-spacer` pushing trailing actions to the edge — never a centered clump. In a
  Before/After pair the bar stays full-width in both states; the spacer absorbs the
  difference so surviving controls hold their edge alignment.
- **Pin bottom bars.** Frame = flex column; body gets `flex:1`; the bottom bar sits last —
  never floating mid-frame above an empty band.
- **Comparable before/after.** Preserve the unchanged controls in both states so the
  reviewer sees exactly what moved or appeared, in the position the implementation puts it;
  same frame size, scale, and density on both sides. Label the states with the §7 column
  headers, never inside the frame.
- **Single-line rows stay single-line.** Toolbars, tab rails, breadcrumbs, path chips:
  `white-space:nowrap` on the row, `overflow:hidden;text-overflow:ellipsis` on growable
  labels.
- **Fill the frame.** No large empty bands; shorten copy rather than letting it wrap.

Worked example — a share popover gaining a "Copy link" action, as a §7 column pair
(`data-feedback-id="wf-share-popover"` on the wrapping unit so notes serialize):

```html
<div data-feedback-id="wf-share-popover" data-feedback-kind="wireframe" style="display:grid;grid-template-columns:1fr 1fr;gap:var(--s4);align-items:start;justify-items:center">
  <div style="width:100%;max-width:320px">
    <div style="font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:var(--del);margin-bottom:var(--s2)">Before</div>
    <div class="wf-frame is-popover">
      <div class="wf-chrome"><strong style="font-size:12.5px">Share document</strong><span class="wf-spacer"></span><span class="wf-muted">✕</span></div>
      <div class="wf-body">
        <input placeholder="Invite by email…" style="border:1px solid var(--border-strong);border-radius:var(--r1);padding:7px 10px;font-size:12px;background:var(--bg-elev);color:var(--fg)">
        <button class="wf-btn is-primary">Send invite</button>
      </div>
    </div>
  </div>
  <div style="width:100%;max-width:320px">
    <div style="font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:var(--add);margin-bottom:var(--s2)">After</div>
    <div class="wf-frame is-popover">
      <div class="wf-chrome"><strong style="font-size:12.5px">Share document</strong><span class="wf-spacer"></span><span class="wf-muted">✕</span></div>
      <div class="wf-body">
        <input placeholder="Invite by email…" style="border:1px solid var(--border-strong);border-radius:var(--r1);padding:7px 10px;font-size:12px;background:var(--bg-elev);color:var(--fg)">
        <button class="wf-btn is-primary">Send invite</button>
        <div class="wf-card" style="display:flex;align-items:center;gap:var(--s2)"><span style="font-size:12.5px">Copy link</span><span class="wf-spacer"></span><span class="wf-pill is-accent">new</span></div>
      </div>
    </div>
  </div>
</div>
<p style="margin:var(--s3) 0 0;font-size:12px;color:var(--fg-faint)">Labels from ShareDialog.tsx; layout inferred.</p>
```

---

## 10. The minimal vanilla interactions

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

## 11. Block: options-comparison (forward-looking)

**Scope note — this is the one block that is not about a finished diff.** Every block above
(§3–§9) renders a change that already exists. This one renders N mutually exclusive options that do
*not* exist yet, for any skill that emits an N-way fork: `/design-an-interface`'s candidate
shapes, `/api-design-review`'s REST/RPC/GraphQL weighing, `/improve-pipeline`'s four-way
verdict, `/correct-course`'s supersede/revise/discard, `/pre-merge` Phase 4's finding
disposition. It lives here so it inherits the §1 tokens rather than re-deriving a palette,
and it is numbered last because it is a sibling of the recap blocks, not one of them.

**Read `visual-rendering-core.md` §1 "Forward-looking blocks" before rendering this.** It is
the block's defining constraint, not background: every cell is either **cited** (quoted from
something that already exists, and showing its source) or **asserted** (the model's judgment
about a state that does not exist), asserted cells render visibly weaker, each option shows
its cited/asserted split, and **every option must carry at least one cited cell**. The
threshold for rendering at all — three or more mutually exclusive options,
each carrying three or more attributes, not orderable on one axis — lives in
`next-step-menu.md`, along with the rule that the comparison *shows* and
`AskUserQuestion` *commits*.

**The shape is a matrix, not N independent cards.** Attributes are rows, options are columns,
and the row label is written once on the left instead of repeated inside every card (Tufte:
direct labeling, and less redundant ink). Cells in one band are grid siblings, so they stretch
to the tallest and stay aligned — which is what makes the comparison an eyespan rather than a
scroll. A missing option shows up as visibly empty space in the matrix; a dominated option
shows up as a column that pays a cost in every band and closes no question.

Paste this style block alongside the §1 core only when rendering an options comparison:

```html
<style>
  /* options-comparison primitives (§11) — same tokens, no new palette */
  /* Narrow viewports cannot hold N columns in one eyespan, and stacking the grid would
     group cells by attribute — detaching every cell from its option header. Pan instead:
     the matrix keeps its alignment and its option→cell association, and costs a scroll. */
  .oc-scroll{overflow-x:auto}
  .oc-matrix{display:grid;gap:0;min-width:680px;border:1px solid var(--border);
    border-radius:var(--r3);background:var(--bg-elev);box-shadow:var(--shadow);overflow:hidden}
  .oc-cell{padding:var(--s3) var(--s4);border-top:1px solid var(--border);
    border-left:1px solid var(--border);font-size:13px;color:var(--fg)}
  .oc-cell.is-head{border-top:none;background:var(--bg-subtle);display:flex;flex-direction:column;gap:var(--s2)}
  .oc-rowlabel{padding:var(--s3) var(--s4);border-top:1px solid var(--border);
    font-size:10px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;
    color:var(--fg-faint);font-family:var(--sans)}
  .oc-rowlabel.is-head{border-top:none;background:var(--bg-subtle)}
  .oc-name{font-family:var(--mono);font-size:13px;font-weight:600;color:var(--fg)}
  .oc-split{font-family:var(--mono);font-size:10.5px;color:var(--fg-muted)}
  .oc-chip{display:inline-block;align-self:flex-start;border-radius:999px;padding:2px 9px;
    font-family:var(--sans);font-size:10px;font-weight:600}
  .oc-chip.is-asserted{border:1px solid var(--risk);color:var(--risk);
    background:color-mix(in srgb,var(--risk) 12%,transparent)}
  .oc-chip.is-dominated{border:1px solid var(--del);color:var(--del);
    background:color-mix(in srgb,var(--del) 12%,transparent)}
  /* the support asymmetry, made visual: cited reads normally on a solid neutral spine;
     asserted is muted, italic, and on a dashed --risk spine. Emphasis marks what is NOT
     evidenced, which is what the reader needs to notice. Diff hues stay out of it. */
  .oc-cited{border-left:2px solid var(--fg-faint);padding-left:var(--s3);color:var(--fg)}
  .oc-asserted{border-left:2px dashed var(--risk);padding-left:var(--s3);
    color:var(--fg-muted);font-style:italic}
  .oc-src{display:block;margin-top:var(--s1);font-family:var(--mono);font-size:10.5px;
    color:var(--fg-faint);font-style:normal}
  /* Per-option note. Without a [data-feedback-note] descendant the §4 serializer skips the
     unit outright, so the opt- handles would be inert and the round-trip below fictional. */
  .oc-note{display:block;width:100%;margin-top:auto;padding:4px 7px;border-radius:var(--r1);
    border:1px solid var(--border);background:var(--bg);color:var(--fg);font-family:var(--sans);
    font-size:11.5px;outline:none}
</style>
```

**Worked example (N = 4)** — the real fork this block was written for: PR #239 changed one line
of `pre-merge/review-checklist.md`, review found its principle paragraph (line 182) and its
violation bullet (line 193) disagreeing, and four mutually exclusive dispositions were on the
table. Five attribute bands (resulting 182, resulting 193, buys, costs, take it if) × four
options is the ~20 items that overran the reader in prose. Two of the five are shown here — one
cited-heavy, one wholly asserted; render all five.

```html
<section id="sec-options" style="margin-top:var(--s8);scroll-margin-top:var(--s7)">
  <div style="font-size:11px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin-bottom:var(--s4)"><span style="font-family:var(--mono);color:var(--accent)">01</span> &nbsp;Four ways to dispose of the 182/193 mismatch</div>

  <div class="oc-scroll">
    <div class="oc-matrix" style="grid-template-columns:132px repeat(4,minmax(0,1fr))">
      <!-- header band: one cell per option, each with its cited/asserted split -->
      <div class="oc-rowlabel is-head"></div>
      <div class="oc-cell is-head" data-feedback-id="opt-reconcile-182-now" data-feedback-kind="option"><div class="oc-name">A · Reconcile 182 now</div><div class="oc-split">2 cited · 3 asserted</div><input data-feedback-note class="oc-note" placeholder="note…"></div>
      <div class="oc-cell is-head" data-feedback-id="opt-merge-file-followup" data-feedback-kind="option"><div class="oc-name">B · Merge, file follow-up</div><div class="oc-split">2 cited · 3 asserted</div><input data-feedback-note class="oc-note" placeholder="note…"></div>
      <div class="oc-cell is-head" data-feedback-id="opt-soften-193" data-feedback-kind="option"><div class="oc-name">C · Soften 193 to echo 182</div><div class="oc-split">2 cited · 3 asserted</div><span class="oc-chip is-dominated">dominated — closes neither question</span><input data-feedback-note class="oc-note" placeholder="note…"></div>
      <div class="oc-cell is-head" data-feedback-id="opt-revert-wontfix" data-feedback-kind="option"><div class="oc-name">D · Revert, close #238 wontfix</div><div class="oc-split">1 cited · 4 asserted</div><span class="oc-chip is-asserted">mostly asserted</span><input data-feedback-note class="oc-note" placeholder="note…"></div>

      <!-- attribute band: CITED cells — verbatim current text, each showing its source -->
      <div class="oc-rowlabel">Resulting line 182</div>
      <div class="oc-cell"><div class="oc-asserted">…proposed rewrite, drafted for this option…<span class="oc-src">asserted — draft, not yet written</span></div></div>
      <div class="oc-cell"><div class="oc-cited">"…if something breaks you can no longer attribute the cause"<span class="oc-src">pre-merge/review-checklist.md:182 — unchanged</span></div></div>
      <div class="oc-cell"><div class="oc-cited">"…if something breaks you can no longer attribute the cause"<span class="oc-src">pre-merge/review-checklist.md:182 — unchanged</span></div></div>
      <div class="oc-cell"><div class="oc-cited">"…if something breaks you can no longer attribute the cause"<span class="oc-src">pre-merge/review-checklist.md:182 — unchanged</span></div></div>

      <!-- attribute band: ASSERTED cells — judgments about states that do not exist yet -->
      <div class="oc-rowlabel">Costs</div>
      <div class="oc-cell"><div class="oc-asserted">Widens the PR past #238's declared non-goal.<span class="oc-src">asserted</span></div></div>
      <div class="oc-cell"><div class="oc-asserted">Leaves the mismatch live until the follow-up lands.<span class="oc-src">asserted</span></div></div>
      <div class="oc-cell"><div class="oc-asserted">Reinstates the reason #239 just demoted.<span class="oc-src">asserted</span></div></div>
      <div class="oc-cell"><div class="oc-asserted">Discards a change two reviews found correct.<span class="oc-src">asserted</span></div></div>

      <!-- …remaining bands: Resulting line 193, Buys, Take it if… -->
    </div>
  </div>

  <p style="margin:var(--s3) 0 0;font-size:12px;color:var(--fg-faint)">Same attributes, same order, every column — only the option differs. Solid spine = cited, dashed = asserted.</p>
</section>
```

**Choosing is not this block's job.** The comparison ends at understanding; the choice is taken
by the skill's `AskUserQuestion` menu immediately after (`next-step-menu.md`). The
`data-feedback-id="opt-<slug>"` handles exist so a reviewer can attach a *note* to a specific
option and have it serialize with everything else via the §4 `recap-feedback v1` blob. The
`.oc-note` input inside each option header is what makes that true rather than aspirational:
the §4 serializer looks for a `[data-feedback-note]` **descendant of the unit** and returns
early when a unit has neither a verdict nor a note, so a header cell without one is skipped
unconditionally and the handle is inert. Untouched options still cost nothing — an empty input
serializes to nothing.
Do not add per-option "select" buttons; that would put the commit mechanism in a transient
file instead of the menu.

**A markdown table is a legitimate render of this block.** The epistemic work is done by
constancy of design and one eyespan, not by HTML — a table with attributes as rows, options as
columns, and each cell marked cited (with its source) or `asserted` delivers both, costs
nothing, and needs none of this skeleton. Reach for the HTML when the cells carry code, long
resulting text, or enough bands that a chat table stops being scannable. Either way the
artifact stays transient (`visual-rendering-core.md` §8) — gitignored `.context/` or `mktemp`,
never committed.

---

## Do's and Don'ts

- **Do** copy the §1 token core verbatim and keep the variable names — that fixed system is
  what makes two recaps look like the same surface. Deviate in *content*, not in *tokens*.
- **Do** use the violet `--accent` only for interaction and the active state — one signal,
  used sparingly.
- **Don't** color syntax tokens with `--add` / `--del`; reserve those hues for diff
  semantics so meaning never blurs.
- **Do** annotate only the changes that matter — 3–8 *key files/hunks*, each with a one-line
  intent summary and a few high-signal callouts, focused excerpts of ~150 lines max (the
  core's reading budget: a ceiling *and* a floor).
- **Don't** add decorative drop shadows or gradients beyond `--shadow`; separate with
  whitespace, a hairline, or a tonal step (Tufte: subtract weight).
- **Do** keep both themes equal — every semantic color is already WCAG-AA-tuned in §1;
  verify any color you add against its surface in light *and* dark.
- **Don't** let the container compete with the code: no heavy borders or card chrome around
  the diff.
- **Don't** introduce a third font family or a web font — two native system stacks only, so
  the file reads identically offline.
- **Don't** render an options comparison (§11) whose columns all read the same weight when
  their support doesn't — an all-asserted column beside a mostly-cited one, drawn identically,
  is the Lie Factor the block exists to prevent. Mark every cell cited or asserted, show each
  option's split, and drop any option with nothing citable.
- **Don't** turn this skeleton into a shipped/versioned/imported component library — it is a
  copyable reference, exactly like the §4 serializer. If you reach for an npm package, a
  build step, or a CDN runtime, pull it back.

---

# Part II — the walkthrough deck (narrative mode)

Everything above renders a change the reviewer will **audit**: parallel hunks, contract cards,
line-anchored callouts, a topology to check against. This part specifies the second canonical
mode — a **paged walkthrough deck** for a change the reviewer has to be **argued through**: one
causal arc, one idea per screen, the before/after pair inside the screen.

It is here because the field built it twice without being asked to. On PR #299 an agent produced
a paged deck unprompted; on PR #297 an agent rendered the canonical scroll first, was shown
#299's deck, and rebuilt to match. Two independent sessions, no coordination, the same override.
A format arrived at twice that the canon does not describe is a gap in the canon, not an
authoring lapse — so the deck is specified rather than re-derived per run, which is the argument
that produced this document in the first place (#126/#127).

The deck **inherits everything and changes two things.** It inherits the §1 token core verbatim,
the Grounding Rule, secret-redaction, the reading budget, and the transient-artifact rule. It
changes the **shell** and the **reading order**. It introduces no new palette, no new block
semantics, and no runtime dependency.

---

## §D1. Mode selection (answer this before rendering anything)

**Is there one story the screens advance? → deck. Is the reviewer auditing parallel hunks? →
scroll.**

| Take the **deck** when | Take the **scroll** when |
|---|---|
| The change has a causal arc — a premise, a sequence of moves that depend on each other, a mechanism that pins them, an aftermath | The reviewer's job is to check a topology — which files moved, which contracts changed, which hunks are load-bearing |
| A reviewer needs the *why* before any hunk means anything | A reviewer already holds the why and needs the *where* |
| The change is a sweep with one thesis, or a review's own story | The change is a set of independent edits with no single thesis |
| The prose is doing the work and the code excerpts are evidence for it | The code is doing the work and the prose is a label on it |

When both fit, take the scroll — it is the cheaper artifact and the reviewer can always be
walked through it in chat. When neither fits because the diff is small or obvious, render
nothing; the skip gate outranks both modes.

**The deck does not replace the scroll for narrative-shaped code audits.** A deck screen still
carries the scroll's blocks — the same panes, the same cards, the same callouts. What differs is
that they arrive one argument at a time instead of all at once.

---

## §D2. The two rules that bound paging

Paging buys sequence and costs simultaneity, and Tufte names the cost by name: *"The viewer
cannot compare what they cannot see at the same time. Memory is not vision."* Both rules below
exist to keep the deck from spending what it cannot afford. They are not style preferences —
a deck that breaks either one is worse than the scroll it replaced.

**Rule 1 — no comparison may span screens.** Any before/after pair, any A-vs-B, any
option-comparison shares a single screen. Paging separates **topics**; it never separates the
halves of a comparison. This is why `.panes` (§D5) is a side-by-side grid rather than a toggle:
the comparison is the payload, and the payload is never the thing you page away from.

**Rule 2 — never page a population.** When N sites are near-identical instances of one cause,
the population *is* the finding, and N screens turn "five fixed, one deliberately exempt, two
found late" into a memory test the reviewer cannot pass. A population belongs in one screen as a
co-visible series or matrix, with per-unit before/afters inside it. Page *between* topics; never
page *within* a set the reader is being asked to compare across.

Together the two rules say the same thing from opposite ends: **the deck pages arguments, not
evidence.**

---

## §D3. The shell (rail + stage), and paging without a router

The deck shell is a grouped sticky rail beside a single stage. The rail carries brand, one
`.navitem` per screen with a subtitle, and the key hints; the stage carries a progress bar,
prev/next, a counter, and the current screen.

**Every screen is a real `<section>` in the document, present in the markup from the start.**
Paging shows one and hides the rest by toggling `hidden`. There is no template array, no
`innerHTML` assignment, and no render function that rebuilds the stage — a store plus routing is
the app this whole surface exists to avoid (`visual-rendering-core.md` §4), and it is what §12
refuses. The single integer `cur` is a *view* index over a document that is entirely there.

That distinction is load-bearing for four separate reasons, and every one of them is a thing a
reviewer will actually do:

- **Show-all is one keystroke.** `A` unhides every screen into one scrolling column — the deck
  collapses into the scroll. The reviewer who wants simultaneity is never trapped in sequence,
  which is the honest answer to Rule 1's residual.
- **Browser find works.** `⌘F` searches the whole change, not the current screen. With an
  `innerHTML` router, eight-ninths of the artifact is not in the DOM to find.
- **Print and PDF work**, because `@media print` can unhide everything.
- **The §4 serializer sees every unit.** `querySelectorAll('[data-feedback-id]')` returns
  elements on hidden screens too, so feedback written on screen 2 still serializes from screen 9.
  A router loses it the moment you page away.

```html
<style>
  /* deck shell (§D3) — same §1 tokens, no new palette */
  .dk{display:grid;grid-template-columns:290px minmax(0,1fr);align-items:start;max-width:1500px;margin:0 auto}
  @media (max-width:960px){.dk{grid-template-columns:1fr} .dk aside{position:static;height:auto}}
  .dk aside{position:sticky;top:0;height:100vh;overflow-y:auto;border-right:1px solid var(--border);background:var(--bg-subtle);padding:var(--s5) var(--s4)}
  .dk main{padding:var(--s7) var(--s7) var(--s8);min-width:0}
  .dk-grp{font-size:10px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:var(--fg-faint);margin:var(--s5) 0 var(--s2);padding-left:var(--s2)}
  .dk-grp:first-of-type{margin-top:0}
  .navitem{display:block;width:100%;text-align:left;border:1px solid transparent;background:none;color:var(--fg-muted);font-family:var(--sans);font-size:13px;padding:var(--s2) var(--s3);border-radius:var(--r2);cursor:pointer;margin-bottom:2px;line-height:1.35}
  .navitem:hover{background:var(--bg-inset);color:var(--fg)}
  .navitem.on{background:var(--accent-dim);border-color:var(--accent);color:var(--fg)}
  .navitem .nm{font-family:var(--mono);font-size:12.5px;font-weight:600;display:block}
  .navitem .sb{font-size:11px;color:var(--fg-faint);display:block;margin-top:2px}
  .keyhint{margin-top:var(--s6);font-size:11px;color:var(--fg-faint);line-height:1.7;border-top:1px solid var(--border);padding-top:var(--s4)}
  kbd{font-family:var(--mono);font-size:10px;border:1px solid var(--border-strong);border-bottom-width:2px;border-radius:4px;padding:1px 5px;background:var(--bg-inset);color:var(--fg-muted)}
  .topbar{display:flex;align-items:center;gap:var(--s3);margin-bottom:var(--s6);flex-wrap:wrap}
  .prog{flex:1;height:3px;background:var(--bg-inset);border-radius:999px;overflow:hidden;min-width:120px}
  .prog i{display:block;height:100%;background:var(--accent);transition:width .25s ease}
  .pgbtn{border:1px solid var(--border-strong);background:var(--bg-elev);color:var(--fg-muted);border-radius:var(--r2);padding:var(--s2) var(--s3);font-size:12px;cursor:pointer;font-family:var(--sans)}
  .pgbtn:hover:not(:disabled){color:var(--fg);border-color:var(--accent)}
  .pgbtn:disabled{opacity:.35;cursor:default}
  .count{font-family:var(--mono);font-size:11px;color:var(--fg-faint);letter-spacing:.06em}
  /* show-all: the deck collapsing back into the scroll */
  .dk.all .screen[hidden]{display:block}
  .dk.all .screen{margin-bottom:var(--s8);border-bottom:1px solid var(--border);padding-bottom:var(--s8)}
  @media print{.dk aside,.topbar{display:none} .screen[hidden]{display:block}}
</style>

<div class="dk" id="dk">
  <aside>
    <div class="brand"><span class="mk">297</span><span class="tx">Change-by-change</span></div>
    <div class="brand-sub">PR #297 · closes #293 · 8 commits</div>
    <nav id="dk-nav">
      <div class="dk-grp">Start here</div>
      <button class="navitem" data-to="premise"><span class="nm">The premise</span><span class="sb">one disease, five instances</span></button>
      <!-- …one .navitem per screen, in render order; a .dk-grp heads each new group -->
    </nav>
    <div class="keyhint">
      <kbd>J</kbd>/<kbd>&darr;</kbd> next &nbsp; <kbd>K</kbd>/<kbd>&uarr;</kbd> prev<br>
      <kbd>1</kbd>&ndash;<kbd>9</kbd> jump &nbsp; <kbd>A</kbd> show all<br><kbd>T</kbd> light / dark
    </div>
  </aside>

  <main>
    <div class="topbar">
      <button class="pgbtn" id="dk-prev">&larr; Prev</button>
      <button class="pgbtn" id="dk-next">Next &rarr;</button>
      <div class="prog"><i id="dk-bar"></i></div>
      <span class="count" id="dk-cnt"></span>
      <button class="pgbtn" id="dk-all">Show all</button>
    </div>

    <!-- every screen is here from the start; paging only toggles [hidden] -->
    <section class="screen" id="premise"> … </section>
    <section class="screen" id="picture" hidden> … </section>
    <!-- … -->

    <footer id="dk-foot"></footer>
  </main>
</div>
```

---

## §D4. The screen model

One screen is one idea. Its slots are fixed so two decks read the same way; render only the
slots the screen needs, in this order.

| Slot | Markup | What it carries | Grounded or authored |
|---|---|---|---|
| `id` | `<section id>` | stable, kebab-case, the paging and deep-link handle | authored (stable across regenerations) |
| group | `.dk-grp` in the rail | the arc stage this screen belongs to (§D5) | authored |
| nav label + subtitle | `.navitem .nm` / `.sb` | the rail's two-line entry; the subtitle is what puts "where am I in this argument" in the artifact rather than the reader's head (Norman, *knowledge in the world*) | authored |
| `kind` | `.ovl` overline | the screen's register — `CONTEXT · ISSUE #293`, `CHANGE 3 OF 6`, `MECHANISM` | mixed: the number is derived, the label authored |
| headline | `<h1>` | one sentence, the claim this screen proves | authored |
| lede | `.lede` | 1–3 sentences; **every domain term glossed on first use** (§D6) | authored |
| chips | `.chip` | 2–4 status pills — `fix` / `op` / `keep` / `miss` | authored flags over derived facts |
| panes | `.panes` | the before/after pair, side by side, in this screen (Rule 1) | hunk text derived; pane headers authored |
| blocks | `.mmd-wrap` / `.term` / `.defs` / any §3–§12 block | diagram, terminal transcript, definition table, contract card, per-unit series | per the block's own rule |
| notes | `.note` + `.good`/`.warn`/`.bad` | a typed aside — what to notice, what nearly went wrong | authored |
| keyline | `.keyline` | **one sentence**, the lesson this screen leaves behind. At most one per screen, and not on every screen | authored |
| stats | `.stat` | 3–5 tabular figures — files, net diff, commits, checks | derived (`git diff --stat`, CI) |

**The keyline is rationed on purpose.** It is the accent-bordered box, and a deck where every
screen has one has no emphasis at all — the same subtraction-of-weight rule the scroll applies to
borders (`visual-rendering-core.md` §5). Use it where the screen genuinely leaves a portable
lesson.

```html
<style>
  /* screen primitives (§D4) — see §1 for every color used here */
  .ovl{font-size:11px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:var(--accent);margin:0 0 var(--s2)}
  .screen h1{font-size:31px;font-weight:600;letter-spacing:-0.022em;margin:0 0 var(--s3);line-height:1.15}
  .lede{color:var(--fg-muted);font-size:15.5px;line-height:1.65;margin:0 0 var(--s5);max-width:74ch;text-wrap:pretty}
  .lede b{color:var(--fg)}
  .chips{display:flex;gap:var(--s2);flex-wrap:wrap;margin-bottom:var(--s4)}
  .chip{font-size:10.5px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;padding:3px 9px;border-radius:999px;border:1px solid var(--border-strong);color:var(--fg-muted);background:var(--bg-elev)}
  .chip.fix{color:var(--add);border-color:var(--add);background:var(--add-bg)}
  .chip.op{color:var(--risk);border-color:var(--risk);background:color-mix(in srgb,var(--risk) 12%,transparent)}
  .chip.keep{color:var(--accent);border-color:var(--accent);background:var(--accent-dim)}
  .chip.miss{color:var(--del);border-color:var(--del);background:var(--del-bg)}
  .panes{display:grid;grid-template-columns:1fr 1fr;gap:var(--s4)}
  @media (max-width:1180px){.panes{grid-template-columns:1fr}}
  .pane{border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);overflow:hidden;box-shadow:var(--shadow);min-width:0}
  .pane-hd{display:flex;align-items:center;gap:var(--s2);padding:var(--s3) var(--s4);border-bottom:1px solid var(--border);font-size:11px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;background:var(--bg-subtle)}
  .pane.b .pane-hd{color:var(--del)} .pane.a .pane-hd{color:var(--add)}
  .pane-path{margin-left:auto;font-family:var(--mono);font-size:10.5px;font-weight:400;letter-spacing:0;text-transform:none;color:var(--fg-faint)}
  .note{border-left:3px solid var(--accent);background:var(--bg-subtle);padding:var(--s3) var(--s4);border-radius:0 var(--r2) var(--r2) 0;font-size:13.5px;line-height:1.65;color:var(--fg-muted);margin-top:var(--s4);text-wrap:pretty}
  .note.warn{border-left-color:var(--risk)} .note.bad{border-left-color:var(--del)} .note.good{border-left-color:var(--add)}
  .note .lbl{display:block;font-size:10.5px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--accent);margin-bottom:var(--s1)}
  .note.warn .lbl{color:var(--risk)} .note.bad .lbl{color:var(--del)} .note.good .lbl{color:var(--add)}
  .keyline{font-size:15px;line-height:1.6;color:var(--fg);border:1px solid var(--accent);background:var(--accent-dim);border-radius:var(--r3);padding:var(--s4) var(--s5);margin-top:var(--s5);text-wrap:pretty}
  .keyline .lbl{display:block;font-size:10.5px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--accent);margin-bottom:var(--s2)}
  .stats{display:flex;gap:var(--s3);flex-wrap:wrap;margin-top:var(--s4)}
  .stat{flex:1 1 130px;border:1px solid var(--border);border-radius:var(--r2);background:var(--bg-elev);padding:var(--s3) var(--s4)}
  .stat .v{font-size:20px;font-weight:680;font-variant-numeric:tabular-nums;letter-spacing:-0.01em}
  .stat .k{font-size:11px;color:var(--fg-muted);margin-top:2px}
  .stat.bad .v{color:var(--del)} .stat.good .v{color:var(--add)}
  .term{border:1px solid var(--border);border-radius:var(--r3);background:var(--bg-elev);overflow:hidden;box-shadow:var(--shadow);margin:var(--s4) 0}
  .term-hd{display:flex;align-items:center;gap:var(--s2);padding:var(--s2) var(--s4);border-bottom:1px solid var(--border);background:var(--bg-subtle);font-size:11px;font-weight:700;letter-spacing:.14em;text-transform:uppercase;color:var(--fg-muted)}
  .term pre{margin:0;font-family:var(--mono);font-size:12.5px;line-height:1.9;padding:var(--s3) 0;overflow-x:auto}
  .term .tl{display:block;padding:0 var(--s4);white-space:pre;color:var(--fg-muted)}
  .term .tl.cmd{color:var(--fg);font-weight:500}
  .term .tl.cmd::before{content:"$ ";color:var(--accent);font-weight:700}
  .term .tl.ok{background:var(--add-bg)} .term .tl.no{background:var(--del-bg)}
  .term .tl.ok .an{color:var(--add);font-weight:600;padding-left:var(--s2)}
  .term .tl.no .an{color:var(--del);font-weight:600;padding-left:var(--s2)}
</style>
```

One screen, whole:

```html
<section class="screen" id="contract" hidden>
  <p class="ovl">CHANGE 1 OF 6 · THE CONTEXT CONTRACT</p>
  <h1>&ldquo;Nothing else&rdquo; was false for five of eleven lenses.</h1>
  <div class="chips"><span class="chip fix">fixed</span><span class="chip keep">gate kept</span></div>
  <p class="lede">A <b>lens</b> is one of the eleven review dimensions&hellip; 1&ndash;3 sentences, every
     domain term glossed the first time it appears.</p>

  <div class="panes">
    <div class="pane b"><div class="pane-hd"><span class="dot" style="background:var(--del)"></span>Before<span class="pane-path">pre-merge/SKILL.md:118</span></div>
      <pre class="code"><span class="ln d">Hand the sub-agent these four items. Nothing else.</span></pre></div>
    <div class="pane a"><div class="pane-hd"><span class="dot" style="background:var(--add)"></span>After<span class="pane-path">pre-merge/SKILL.md:118</span></div>
      <pre class="code"><span class="ln a">Hand the sub-agent these four items, plus whatever</span><span class="ln a">its dimension's row in the checklist declares.</span></pre></div>
  </div>

  <div class="note good"><span class="lbl">Why it matters</span>Five dimensions needed the repo, the
    issue bodies, or npm &mdash; and the contract forbade all three.</div>
  <div class="keyline"><span class="lbl">The lesson</span>A contract that is cheaper to violate than to
    honor is not a contract.</div>
</section>
```

---

## §D5. The arc

Four groups, in this order. The rail's `.dk-grp` headings are these names (or the change's own
words for them); the reader is told the arc up front on the first screen.

1. **Premise** — *why any of this matters*, before a single hunk. One or two screens: the
   situation, and optionally the same story as a picture (§D7). Nothing here is a change; this is
   the ground the changes stand on. This screen is the one most likely to be authored badly, so
   §D6 gives it a rule set.
2. **The changes** — one screen per move, in the order the moves depend on each other, **not** the
   order the commits landed. Each screen: what was true, what is true now, why the second is
   better. This is where `.panes` earns the deck.
3. **The mechanism** — what pins the changes so they cannot silently regress: the contract test,
   the hook, the schema constraint. If a change has no mechanism, this group is where you say so
   in as many words, rather than leaving its absence to be inferred.
4. **Aftermath** — what was fixed versus filed, what is deliberately still open, what the reviewer
   is being asked to decide, and the lesson that rode along.

A deck missing group 3 or group 4 is usually a deck that should have been the scroll: without a
mechanism and an aftermath there is no arc, only a list.

---

## §D6. The premise screen, and its `/re-pitch` pairing

The premise screen is a **retelling for a reader who does not hold the context** — which is the
job `/re-pitch` does in chat. The two are the same move in two media, and the field evidence for
this is direct: on PR #297 a `/re-pitch` was run mid-session and its framing became the deck's
opening screen.

Write the premise screen under `/re-pitch`'s rule set:

- **One anchor sentence first** — the whole change in a sentence a reader can carry.
- **Every domain term glossed on first use**, in the sentence that uses it. Not a glossary block
  the reader has to cross-reference; that is the legend the callout rule already forbids.
- **Sentences capped.** A premise screen that runs long has become the thing it exists to
  replace.
- **No forward references.** Nothing on the premise screen may depend on a screen the reader has
  not reached.

`SKILL.md` may **recommend** `/re-pitch` when the audience signals the change feels abstract. It
never invokes it — same rule as every other cross-skill seam in the pack.

---

## §D7. Diagrams in a deck

Deck diagrams are usually the picture of *the whole mechanism before and after* — labeled edges,
fan-outs, styled failure and guard nodes, two graphs the reader compares. That is the
multi-stage/behavioral case, so the default is **Mermaid via CDN with the visible degrade note**
(`visual-rendering-core.md` §5, §6; markup and label-safety in §5 above). The `.fc-*` primitive
stays the right answer for a trivial spine, and is the *recommended* answer when the review
context is known to be offline.

Under Rule 1 a before/after diagram pair is a comparison, so both graphs live on one screen —
`.mmd-wrap` twice inside the same `<section>`, each with its own caption.

Two deck-specific consequences of the CDN opt-in:

- **The degrade note is per figure and on its face**, not once in a footer. A reader who pages
  straight to screen 6 must see it there.
- **Re-run Mermaid when a screen becomes visible**, because a diagram inside a `hidden` section
  has no layout box and renders at zero size. Initialize with `startOnLoad:false` and call
  `run({nodes})` for the screen you just revealed — see §D8.

---

## §D8. The interactions (the whole script)

Prev/next, rail jump, number keys, show-all, theme, and the Mermaid re-run. That is all of it. If
this grows a store, a router, or an `innerHTML` assignment, it has become the app this surface
exists to avoid (`visual-rendering-core.md` §4) — pull it back. The §4 `copyFeedback()`
serializer is separate and unchanged.

```html
<script>
  const dk = document.getElementById('dk');
  const screens = [...dk.querySelectorAll('.screen')];
  const items = [...dk.querySelectorAll('.navitem')];
  let cur = 0;

  function show(i){
    cur = Math.max(0, Math.min(screens.length - 1, i));
    dk.classList.remove('all');
    screens.forEach((s, j) => { s.hidden = j !== cur; });
    items.forEach((b, j) => b.classList.toggle('on', j === cur));
    document.getElementById('dk-bar').style.width = ((cur + 1) / screens.length * 100) + '%';
    document.getElementById('dk-cnt').textContent = (cur + 1) + ' / ' + screens.length;
    document.getElementById('dk-prev').disabled = cur === 0;
    document.getElementById('dk-next').disabled = cur === screens.length - 1;
    // a diagram inside a hidden section has no layout box, so lay it out on reveal
    if (window.__mmd) { try { window.__mmd.run({ nodes: screens[cur].querySelectorAll('.mermaid') }); } catch (e) {} }
    window.scrollTo({ top: 0, behavior: 'instant' });
  }
  function showAll(){
    dk.classList.add('all');
    if (window.__mmd) { try { window.__mmd.run({ nodes: dk.querySelectorAll('.mermaid') }); } catch (e) {} }
  }
  items.forEach((b, j) => b.addEventListener('click', () => show(j)));
  document.getElementById('dk-prev').addEventListener('click', () => show(cur - 1));
  document.getElementById('dk-next').addEventListener('click', () => show(cur + 1));
  document.getElementById('dk-all').addEventListener('click', showAll);
  addEventListener('keydown', e => {
    if (e.metaKey || e.ctrlKey || e.altKey || /^(INPUT|TEXTAREA)$/.test(e.target.tagName)) return;
    const k = e.key.toLowerCase();
    if (k === 'j' || e.key === 'ArrowDown' || e.key === 'ArrowRight') { e.preventDefault(); show(cur + 1); }
    else if (k === 'k' || e.key === 'ArrowUp' || e.key === 'ArrowLeft') { e.preventDefault(); show(cur - 1); }
    else if (k === 'a') showAll();
    else if (k === 't') dk.dataset.theme = dk.dataset.theme === 'light' ? 'dark' : 'light';
    else if (/^[1-9]$/.test(k) && +k - 1 < screens.length) show(+k - 1);
  });
  show(0);
</script>
```

The `INPUT|TEXTAREA` guard is not optional: without it, typing the letter `a` into a
`[data-feedback-note]` field pages the deck out from under the reviewer mid-sentence.

---

## §D9. Deck Do's and Don'ts

- **Do** put the whole arc in the rail before the reader starts — group headings and per-item
  subtitles. A deck whose rail is a flat list of nine identical labels has spent the paging cost
  and bought nothing.
- **Don't** page a comparison or a population (§D2). If you catch yourself writing "screen 4 vs
  screen 5," you have written the anti-pattern.
- **Do** keep every screen in the DOM and page by `hidden`. Show-all, browser find, print, and
  the feedback serializer all depend on it.
- **Don't** give every screen a keyline; the box means nothing when everything wears it.
- **Do** order the change screens by dependency, not by commit date — the deck is an argument,
  and an argument has an order the history does not.
- **Don't** let the deck outgrow the reading budget (`visual-rendering-core.md` §5). More screens
  is not more coverage; ~8–12 screens is a walkthrough, 30 is a document nobody finishes.
