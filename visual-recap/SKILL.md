---
name: visual-recap
description: "Side-route skill that renders a finished diff, PR, or branch as a single self-contained interactive HTML recap — file-tree + change flags, annotated split diffs with line-anchored callouts, before/after panels, reused Mermaid diagrams, and a copy-text feedback loop. Use when a reviewer who didn't author the change needs to grasp its shape before reading lines. Optional and never auto-invoked; skip for small or obvious diffs. Not a defect finder (that's /pre-merge), not free-form diagramming (that's /excalidraw-diagram), not a committed artifact (the HTML is transient)."
sources:
  primary:
    - "Best Kept Secrets of Peer Code Review — Jason Cohen"
    - "The Design of Everyday Things — Don Norman"
  secondary:
    - "Thinking in Systems — Donella Meadows"
    - "The Visual Display of Quantitative Information — Edward Tufte"
    - "Envisioning Information — Edward Tufte"
---

# Visual Recap

Render a finished change as a single self-contained interactive HTML file that shows a reviewer the *shape* of the diff before they read the lines: which surfaces moved, which hunks are load-bearing, what's risky — with callouts anchored to the exact lines, then a drop into the literal code. The output is **reviewer comprehension as a portable artifact**, not a defect list.

This skill exists because Cohen's strongest empirical finding is *author preparation*: an annotated walkthrough prepared by someone who understands the change correlates with near-zero defect variance. The pipeline produces that annotation as terminal prose (`/pre-merge`, `/walk-commits`) but never as a highlightable, shape-first surface — so the reviewer rebuilds the change's topology in their own head before judging any line. `/visual-recap` produces the missing surface (Meadows: a missing high-bandwidth feedback flow in the review loop) **without any lock-in** — the agent authors the HTML directly; there is no renderer package, no build system, no server, no MCP connector, and no hosted database. GitHub PR review comments stay the durable channel.

It is the *reverse* direction of the planning bookend: `/visual-recap` builds a reviewable artifact *from* a finished diff, the same data model a forward planning recap would build *toward* a change.

## Invocation Position

This is a **side-route skill**. It does not block merge and is **never auto-invoked**.

It reconnects to the main pipeline at the `/pre-merge` → merge boundary, exactly like `/walk-commits`: run it when you want shape-first comprehension before approving, then proceed to merge (and `/compound` if a durable lesson emerged). `/pre-merge` Phase 4 may *recommend* it — without invoking it — when the person merging didn't author the diff, the same way it recommends `/walk-commits`.

Use `/visual-recap` when:

- A reviewer who did **not** author the change needs to grasp its shape across multiple files before reading lines.
- The change's topology (what moved where, which hunks are load-bearing) is hard to hold in your head from flat terminal output.
- You want a portable, line-anchored artifact you can open in a browser and feed answers back from.

**Do not** use `/visual-recap`:

- **For small or obvious diffs.** This is the load-bearing gate. A one-file, few-line change reads faster as plain text; generating ceremony HTML for it is filler bait (Norman, *featuritis*; Meadows, *policy resistance*). If `/pre-merge` or `/walk-commits` terminal output already makes the change legible, do not render a recap. When unsure, skip.
- **To find defects** across the diff — that is `/pre-merge`'s adversarial, dimension-based review. The recap renders *comprehension*, not findings.
- **To draw free-form architecture arguments** — that is `/excalidraw-diagram`. The recap stays clean and structured.
- **To produce a committed artifact** — the HTML is transient (see the transient-artifact rule). Never commit it.

The line that keeps this distinct from `/pre-merge`: **comprehension surface, not defect-finding.** If you catch yourself enumerating bugs, you are running the wrong skill.

## The shared rendering core

All of the HTML vocabulary, the copy-text serializer, the Grounding Rule, secret-redaction, and the Tufte quality bar live in **`references/visual-rendering-core.md`** — the single bar this skill and `/walk-commits` both author against. Read it before rendering. The points below are the skill-level discipline; the core is the rendering contract.

Two rules from the core are load-bearing and worth restating here:

- **The Grounding Rule.** Every structured value — paths, line numbers, hunk text, ±counts, commit hashes — is mechanically derived from the real diff (`git show`, `git diff`, `git diff --stat`), copied not retyped. The model writes **prose only** (callout notes, hunk intent summaries, change flags). A confidently-wrong recap is more dangerous than plain text because a reviewer who trusts the summary skips the line it got wrong. Visual emphasis must not exceed the real change (Tufte, Lie Factor ≤ 1).
- **Secret-redaction runs before any HTML is written.** Mask values for `*_KEY` / `*_SECRET` / `*_TOKEN` / credentialed URIs / PEM blocks — keep the key, mask the value — and note once in the overview if anything was masked. The artifact is portable; a leaked secret in a copied file is unrecoverable.

## Process

### 1. Resolve the change and apply the skip gate

Resolve what to recap — a branch range, a PR, or a working diff:

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')
[ -z "$BASE_BRANCH" ] && for c in main master prod trunk; do git rev-parse --verify "$c" >/dev/null 2>&1 && BASE_BRANCH=$c && break; done
git diff --stat "$BASE_BRANCH..HEAD"
git log --oneline --no-merges "$BASE_BRANCH..HEAD"
```

Do not hardcode `main` — detect the base (this repo itself uses `prod`). For a PR, resolve its head/base with `gh pr view <n>`.

**Apply the skip gate now.** Look at the `--stat`. If the change is small or obvious — a single file, a handful of lines, a mechanical rename — say so and **recommend skipping the recap**; the terminal output from `/pre-merge` or `/walk-commits` is faster. Only proceed when the topology genuinely warrants a shape-first surface. This gate is the skill's main defense against becoming filler.

### 2. Derive the grounded skeleton (tooling, not prose)

Build the structural inputs mechanically, before writing a single sentence:

- **Topology:** the file list and per-file ±LOC from `git diff --stat`.
- **Hunks:** the actual before/after text and line numbers from `git diff`/`git show` — copied verbatim into the annotated-diff blocks.
- **Commits:** hashes and touched files from `git log`/`git show`.

Run secret-redaction over every hunk at this step (per the core), before any of it reaches the HTML.

### 3. Author the prose layer (judgment only)

Now write the parts the model owns — and only these:

- The **overview**: 1–3 sentences of "what this change is," the scale, and the reading mode (evolution vs. maintenance), so the reviewer reads *intent first*.
- A **change flag** per file (`new` / `moved` / `load-bearing` / `mechanical` / `risky`).
- A one-line **intent summary** above each annotated hunk.
- **3–8 callouts** total, each anchored to a real line range, each a single note — respecting the reading budget (Cohen/Rigby: ~100–300 LOC, 30–60 min). A recap that callouts every hunk has rebuilt the diff the reviewer was going to scroll anyway.

When the change needs an architecture, data-flow, or sequence picture, **reuse `/mermaid`** and embed the result — do not hand-roll graph layout (issue #83 already chose embedded Mermaid as the pipeline's diagram answer).

### 4. Render the self-contained HTML

Author one `.html` file against the core's vocabulary:

- Inline, themeable CSS is load-bearing (CSS variables flipped on `[data-theme]` for light + GitHub-dark); CDN libraries are enhancement-only and always have a no-CDN fallback. The file must read identically with the network off.
- Line-anchored callouts are **direct labels** rendered at the line, not a separate legend (Tufte; Norman, *natural mapping*). Clicking a marker highlights the exact line — scope the highlight to the code cell, not the whole row.
- Maximize data-ink: no chartjunk, no decorative shadows; small multiples + constancy of design for before/after panels (identical scale and frame on both sides).
- Include the **Copy feedback** button and its layered-clipboard serializer with stable `data-feedback-id`s, exactly per the core's `recap-feedback v1` format.

Write the file to a **transient** path — gitignored `.context/` or `mktemp` — never the tracked tree.

### 5. Open, review, and round-trip the feedback

Emit both open paths so the reviewer can choose:

```
open <artifact>.html                # file:// is a secure context
python3 -m http.server 8000         # fallback for sandboxes that block file://
```

The reviewer reads the recap, writes notes/verdicts in-page, clicks **Copy feedback**, and pastes the `recap-feedback v1` block back. Parse it by stable id and either (a) patch the HTML, (b) drive changes into code, or (c) **promote durable items to GitHub PR review comments** — the line-anchored channel that outlives the session. The clipboard is the working transport; GitHub is the system of record.

### 6. Tear down

Delete the HTML (and any screenshots) when the review round is done. What persists is the *decision* — sign-offs and any items promoted to PR comments — not the file. If you want to keep the HTML "for reference," that is the signal to promote its content to a PR comment or `docs/solutions/` entry instead.

## What This Skill is NOT

- **Not a defect review.** It does not sweep the diff for bugs — `/pre-merge` does that and emits advisory findings. Recap renders comprehension.
- **Not free-form diagramming.** It stays clean and structured; exploratory "diagrams that argue" are `/excalidraw-diagram`.
- **Not a diagram engine.** Architecture/data-flow pictures come from `/mermaid`; the core owns callouts and diffs, not graph layout.
- **Not a renderer we ship.** The core is a vocabulary the agent hand-authors against — no package, no build, no server, no committed app. If "self-contained HTML with CDN imports" starts growing state, routing, or a component library, pull it back.
- **Not a mandatory stage, and not auto-invoked.** It is optional, gated by the skip-for-small-diffs rule. If a later PR sample shows it is rarely invoked or only fires on diffs `/pre-merge` already covers, fold it into `/pre-merge` as an optional phase (mirrors `/walk-commits`'s own self-deprecation clause).
- **Not a committed artifact.** The HTML is transient — gitignored or `mktemp`, deleted after the round. Per SYSTEM-OVERVIEW §Philosophy.

## Handoff

- **Expected input:** a finished change to comprehend — a branch range, a PR number, or a working diff — plus the base branch to diff against. No upstream artifact is required, though a linked PRD or slice issue helps frame intent.
- **Produces:** a transient, self-contained interactive HTML recap (file-tree + change flags, annotated split diffs with line-anchored callouts, before/after panels, reused Mermaid diagrams) and the reviewer's copied-back feedback, with durable items promoted to GitHub PR review comments. A comprehension surface and a decision, not a committed file.
- **Reconnects at:** the `/pre-merge` → merge boundary. Run it before approving; proceed to merge once the change is understood, then `/compound` if a durable lesson emerged.
- **What comes next:** the user merges (or pauses on unresolved items). `/visual-recap` does not invoke anything.
