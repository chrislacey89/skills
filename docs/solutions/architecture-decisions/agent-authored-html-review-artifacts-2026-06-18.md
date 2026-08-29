---
date: 2026-06-18
category: architecture-decisions
problem_type: portable interactive artifact without a renderer/backend
components: [visual-recap, walk-commits, visual-rendering-core]
technologies: [html, vanilla-js, clipboard-api, css-variables]
severity: medium
volatility: stable
---

# Agent-authored self-contained HTML for review artifacts (no renderer, no backend)

## Problem

Skill Kit's review bookend (`/pre-merge`, `/walk-commits`) produced no portable, highlightable artifact showing a reviewer the *shape* of a change before they read the lines. The best off-the-shelf surface (Builder.io's `visual-recap`) had the right ergonomics but required a proprietary renderer package, a hosted MCP connector, and a hosted database — none of which fit the kit's no-renderer, GitHub-native-state constraints.

## Context

Implementing issue #117 (the review bookend, "A of 2"). The goal was to capture the line-anchored-callout review ergonomics *without* the lock-in. A FEASIBILITY spike (recorded on #117) had already verified that a single self-contained HTML file can deliver the full UX — line-anchored callouts, annotated split diff, before/after, and a clipboard feedback round-trip — with zero proprietary dependencies.

## Root Cause

The ergonomics people attribute to a "renderer product" are actually three separable things: (1) a small HTML/CSS vocabulary, (2) line-anchored callouts as direct labels, and (3) a feedback transport. A hosted renderer bundles all three and sells them as one. Only the third *seems* to need a backend — and it doesn't, because the clipboard is a transport and a human is a willing courier.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The review loop was missing a high-bandwidth comprehension *information flow* (Meadows LP 6). The pipeline's output format is defined by the skills, so the gap could only be closed by changing the skills — not any downstream repo. The same structural move `/closeout` made for the merge/teardown tail.

## Rule Scope

**Applies when** an agent needs to produce a *portable, interactive* artifact for a human to read and respond to, and:

- the artifact must survive with no network (offline, sandbox, `file://`), and
- the feedback must round-trip *without* a server or database, and
- a durable channel already exists for anything that must outlive the session (here: GitHub PR review comments).

Under those conditions, author **self-contained HTML directly** and treat any "renderer" as a *vocabulary + quality bar the agent writes against*, never as shipped/versioned JavaScript. The clipboard is the feedback transport; stable, content-derived element ids are the parse anchors on the way back.

**Inverts or does not apply when:**

- A real backend/persistence is available and the feedback must be queryable, multi-user, or durable beyond a paste — then a hosted surface earns its keep and this round-trip is a downgrade.
- The artifact is non-interactive (a static report) — then Markdown/terminal output is lighter and this is over-engineering.
- The change is small or obvious — a few lines read faster as plain text; rendering HTML is filler (Norman *featuritis*). Both `/visual-recap` and the `/walk-commits` enhancement gate on this explicitly.

- **Sibling docs:** none yet. This entry was written expecting a sibling `/visual-plan` skill to inherit it. That skill was never built — #317 ruled that the planning bookend ships as forward-looking *blocks* in `docs/visual-recap-design.md` rather than as a second command, so what inherits this entry is `/visual-recap`'s forward-looking mode, not a new skill.

## Solution

Three artifacts, one shared quality bar (`docs/visual-rendering-core.md`, bundled into both consuming skills via `scripts/skill-references.manifest`):

1. **The "renderer" is documentation, not a package.** A component vocabulary (callout, annotated-diff, before/after, file-tree) the agent hand-authors HTML against each time. No npm dependency, no build, no server, no committed app. This is the explicit defense against both the lock-in *and* renderer-creep.
2. **Inline CSS is load-bearing; CDN libraries are enhancement-only with a no-CDN fallback.** The spike proved a real recap used *zero* utility classes — 100% inline CSS, degrading to an identical file offline. Test: open with the network off; if it still reads, it was built right.
3. **The copy-text feedback loop is the backend-free `get-plan-feedback`.** A layered-clipboard serializer (`navigator.clipboard` → `execCommand` → an always-visible pre-selected `<textarea>` as the guarantee) emits a compact, agent-parseable `recap-feedback v1` blob keyed by **stable, diff-derived element ids** (`c-<file-slug>-L<line>`, `q-<n>`, `signoff-<short-hash>`). The agent parses it back by id; durable items get promoted to GitHub PR review comments.
4. **The Grounding Rule keeps it honest.** Every structured value (paths, line numbers, hunk text, ±counts, hashes) is mechanically derived from the real diff and copied, never retyped; the model writes prose only. A confidently-wrong recap is *more* dangerous than plain text. Visual emphasis must not exceed the real change (Tufte, Lie Factor ≤ 1).

## Prevention

**Code-level:** When documenting a machine-parseable format alongside a reference implementation, the implementation must reproduce *every* documented example — including the edge cases (here: a verdict-less open question). They drift silently otherwise.

- This bit during this very PR's review: the serializer prepended the verdict→note em-dash whenever a note existed, so a verdict-less unit serialized as `question#q-1:  — "…"` instead of the documented `question#q-1: "…"`. The fix joins verdict + quoted note with the em-dash only when both are present.
- Cheapest guard: paste each documented example's inputs through the reference serializer in your head (or a scratch eval) at authoring time. The format *is* the parse contract — a divergence is a silent round-trip failure, not a cosmetic one.

**Process-level:** Recurring capability gaps whose output format is defined by the *skills* (not any downstream repo) are pipeline-structural — close them by changing the skills, and keep the fix a *feedback fix, not a feature* (optional, side-route, never auto-invoked, hard skip-for-small-diffs gate). When a shared quality bar is consumed by ≥2 skills, make it one bundled reference (manifest + `sync-skill-references.sh`), not per-skill prose that drifts.

## Key Decision

**Decision:** Capture Builder.io's review-recap ergonomics as agent-authored self-contained HTML governed by a shared `docs/` vocabulary, with a clipboard feedback round-trip — not as a renderer package, MCP connector, or hosted DB.
**Rationale:** Delivers the comprehension surface with zero lock-in and zero new persistent filesystem state; the LLM is the renderer and GitHub is the durable channel.
**Alternatives considered:** Adopt Builder.io's `@agent-native/core` + hosted Plan DB (rejected — lock-in, violates GitHub-native-state); ship a small committed renderer app (rejected — renderer-creep, violates the transient-artifact rule); leave the bookend as terminal prose (the status quo — leaves Cohen's author-preparation ergonomics on the table).
**Revisable:** Yes — if a later PR sample shows `/visual-recap` is rarely invoked or only fires on diffs `/pre-merge` already covers, fold it into `/pre-merge` as an optional phase (mirrors `/walk-commits`'s self-deprecation clause).

## Related

- Issue #117 — the `/improve-pipeline` proposal and the FEASIBILITY spike verdict that grounds this decision
- PR #123 — the implementation this entry rides
- Issue #317 — the planning bookend, filed as sibling issue B and **resolved against a new skill**. The blocks land in `docs/visual-recap-design.md`; `/visual-recap` selects them. Read it before assuming this entry is waiting on a `/visual-plan` that never arrived
- `docs/visual-rendering-core.md` — the shared vocabulary + quality bar this decision produced

## Shelf Life

Stable. Supersede if Skill Kit ever adopts a sanctioned renderer/persistence layer (which would relax the no-backend constraint), or if the clipboard round-trip is replaced by a richer durable channel. Until then the constraints that forced this design (no renderer package, GitHub-native state, transient filesystem) still hold.
