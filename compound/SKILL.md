---
name: compound
description: "Primary pipeline knowledge-capture step that closes the compounding loop. Capture a durable lesson in docs/solutions/ onto the open PR before /closeout merges (the default), or post-merge when the lesson only surfaces during/after merge. Use so future /research and /write-a-prd runs improve. Not for trivial edits with no reusable project-level learning, and not for the merge/teardown itself (that's /closeout)."
sources:
  primary:
    - "Living Documentation — Cyrille Martraire"
  secondary:
    - "Thinking in Systems — Donella Meadows"
    - "Software Estimation — Steve McConnell"
    - "Thinking in Bets — Annie Duke"
    - "The Fifth Discipline — Peter Senge"
---

# Compound

Document a recently solved problem or shipped feature to compound your project's knowledge. Each documented solution makes future planning and implementation faster — the agent consults `docs/solutions/` during `/research` and `/write-a-prd`, so lessons learned today prevent mistakes tomorrow.

When the work surfaced planning or estimation surprises, capture those too. McConnell-style calibration only happens if actual work feeds back into future shaping.

## Invocation Position

This is a primary pipeline skill that closes the compounding loop. It runs near the tail of the default delivery path, after `/pre-merge` has created the PR.

**Default — capture the lesson in the PR, before merge.** When a durable lesson is already known at PR time, run `/compound` on the open PR branch so the `docs/solutions/` entry rides the same PR as the code that taught it — reviewed in the same pass and merged atomically with it. This places `/compound` between `/pre-merge` and `/closeout`:

```
… → /pre-merge → /compound (in-PR, when a lesson exists) → /closeout (merge + teardown) → cleanup
```

**Fallback — capture post-merge.** Some lessons only surface during or after the merge: integration surprises, QA findings, behavior seen once it ships. For those, run `/compound` after `/closeout` has merged. This is the fallback path, not the default.

Either way, `/compound` never performs the merge or worktree teardown itself — that is `/closeout`. Capturing in-PR means committing onto the open PR branch so the lesson is reviewed like any other change; it does not mean merging.

Do not use it for trivial edits or for lessons that belong entirely in a higher-fidelity artifact like a test, linter rule, or code comment without any durable project-level learning. Whether in-PR or post-merge, the "When NOT to Use" guard below still applies — most PRs carry no durable lesson, and there is no standing per-PR `docs/solutions/` slot to fill.

## Why This Exists

Without this step, you've done traditional engineering with AI assistance. The first three steps of the workflow (plan, work, review) produce a feature. This fourth step produces a system that builds features better each time.

## When to Use

- When a feature's PR is ready and it taught a durable lesson — capture it onto the PR before merge (the happy path)
- After shipping, when a lesson only became clear during or after the merge (the post-merge fallback)
- After fixing a tricky bug where the root cause was non-obvious
- After a QA cycle revealed issues that could have been caught earlier
- After making an architectural decision with significant tradeoffs
- When you've discovered a pattern that should be reused

## When NOT to Use

- For trivial fixes (typo corrections, simple config changes)
- When the solution is already well-documented in official library docs
- When the lesson is project-specific but you're about to deprecate that code
- When the work was a clean execution of a pre-shaped plan — no surprises, no rework, no non-obvious decisions. The issue body and PR description already carry that record; a `docs/solutions/` entry with no reusable lesson trains future readers to skim
- When in doubt — skipping costs nothing because the issue and PR persist in GitHub. Capturing a low-value lesson costs future planners' attention every time they consult `docs/solutions/`

## Execution Flow

### Phase 1: Identify What to Capture

On the in-PR default path the work under review is the open PR branch, so the commands below read it directly (`git log` and `git diff main...HEAD` against the still-unmerged branch). On the post-merge fallback path, run them in a session that can still see the merged feature's history — once `/closeout` has pruned the branch and pulled base, `git diff main...HEAD` is empty and you must read the PR diff via `gh pr diff <n>` instead. Either way, review the recent work. Look at:

1. **Git log** — What commits were made? What changed?
   ```bash
   git log --oneline -20
   ```

2. **Issue thread** — What was the original problem? What was discussed?

3. **The diff** — What files changed? What patterns emerged?
   ```bash
   git diff main...HEAD --stat
   ```

Ask the user: "What was the most important thing you learned or the trickiest part of this feature?" Their answer often reveals the highest-value lesson to capture.

Before writing, classify the lesson at the right level:

- **Event** — a one-off incident or visible failure
- **Pattern** — something that has happened repeatedly across features, bugs, or handoffs
- **Structure** — a recurring condition in the codebase, workflow, incentives, or decision process that keeps producing the pattern

Prefer capturing the highest level you can support with evidence. If the lesson is structural, name the feedback loop, missing feedback, or delayed effect that made the outcome likely.

**Before proceeding, consider three questions** (guidance, not a gate — if the answer is unclear, proceed and let the writing process clarify):

1. **Is this genuinely novel?** Check official library docs and existing `docs/solutions/` files. If the lesson is already well-documented elsewhere, skip it or link to the existing source.
2. **Will this still be accurate in 3 months?** If the lesson is tightly coupled to a dependency version or a temporary workaround, note that — it affects the `volatility` classification below.
3. **Could this be captured closer to the source?** A behavioral invariant is better as a test. A convention is better as a linter rule. A "why" explanation is better as a code comment co-located with the decision. If the lesson can be fully captured in a higher-fidelity artifact, do that instead of (or in addition to) writing prose.
4. **Was the process fixed?** (Bug-fix compounds only.) Was the fix a correction (removed the defect) or a workaround (suppressed the failure)? Were structurally similar patterns elsewhere in the codebase found and addressed? What process change would prevent this defect class from entering the codebase again — a stronger test, a linter rule, an assertion, a planning checklist item? If the answer is "nothing," the mechanism that produced this defect is still active.

**Rabbit Hole review.** If a PRD issue exists for this feature, read its Rabbit Holes section. For each one, check: did the pre-decided resolution hold, or did it need to be revised during implementation? Rabbit Holes that bit — required a different resolution than planned, or surfaced late despite being named — are high-value compound targets. Capture the risk pattern and the *actual* resolution in `docs/solutions/` so future `/write-a-prd` sessions surface them during the completeness scan. Rabbit Holes that held as planned are less valuable to document unless the risk pattern is likely to recur in unrelated features.

**Scope accuracy check.** Also check: did this feature reveal a *scope* lesson worth capturing?

- Were significant activities omitted from the original decomposition that had to be discovered during implementation?
- Did a specific type of work (auth integration, data migration, UI state management) consistently appear as unplanned scope additions?

If a scope pattern emerges (e.g., "auth changes in this codebase consistently require updating three additional systems"), capture it in the appropriate existing `docs/solutions/` category — `integration-issues/`, `patterns/`, etc. The lesson compounds: `/write-a-prd`'s omitted activities scan and `/prd-to-issues`'s scope completeness check both consult `docs/solutions/`, so a documented pattern directly improves the next feature's planning.

If the main lesson is not about the downstream project but about Skill Kit itself — for example unclear skill boundaries, missing handoff guidance, or weak process guardrails in `chrislacey89/skills` — recommend `/improve-pipeline` if that skill is present. Do not invoke it. `/compound` still captures project knowledge; `/improve-pipeline` is for improving Skill Kit.

**Calibration check.** Also ask:

- Which unknowns actually drove variance between the shaped work and the implemented work?
- Did the team confuse a target, estimate, or commitment at any point?
- Did the first tracer bullet materially tighten confidence or reveal hidden work?
- Are there concrete actuals from this feature that should become a baseline for similar future work?

You do not need formal project accounting. A few truthful lines about what actually widened or narrowed the work are enough to improve future planning.

### Phase 2: Classify the Problem

Determine the category for filing. Use the most specific category that fits:

| Category | When to Use |
|----------|-------------|
| `integration-issues` | External API, third-party service, library integration |
| `architecture-decisions` | Structural choices with significant tradeoffs |
| `performance-issues` | Optimization, N+1 queries, caching strategies |
| `runtime-errors` | Bugs that were hard to diagnose |
| `logic-errors` | Business logic that was subtly wrong |
| `testing-patterns` | Testing approaches that worked well (or didn't) |
| `ui-patterns` | Frontend patterns, component architecture |
| `devops` | Build, deploy, CI/CD, environment issues |
| `security-issues` | Auth, permissions, data handling |
| `patterns` | Reusable patterns that emerged from implementation |

### Phase 3: Write the Solution Document

Create the document in `docs/solutions/<category>/`. Use the template below.

**Before writing the Root Cause section**, apply two tests. First: was the outcome a predictable consequence of the decision, or did it depend on conditions that weren't available to reason about at decision time? If unpredictable from the decision, the lesson belongs in Context (what you now know about the environment), not Prevention (what to do differently next time). Second: under what conditions would this lesson mislead a future agent? If you can't name a condition that would make the lesson wrong, tighten it until it's falsifiable or drop it. For Pattern and Structure lessons, record the answer in the Rule Scope section of the template so future `/research` consumers can pattern-match their own work's shape against the preconditions without re-deriving them from prose.

**Ensure the directory exists:**
```bash
mkdir -p docs/solutions/<category>
```

**Filename convention:** `<kebab-case-problem-slug>-<YYYY-MM-DD>.md`

Example: `docs/solutions/integration-issues/ably-presence-channel-auth-2026-03-28.md`

```markdown
---
date: YYYY-MM-DD
category: <category>
problem_type: <specific type within category>
components: [list, of, affected, components]
technologies: [list, of, relevant, technologies]
severity: low | medium | high | critical
volatility: evergreen | stable | volatile
---

# [Problem Title]

## Problem

[1-2 sentence description of the issue. Be specific enough that someone searching for this problem would find it.]

## Context

[What were you building when this came up? What was the expected behavior vs actual behavior?]

## Symptoms

[Observable symptoms that would help someone recognize they're hitting the same issue.]

- [Symptom 1 — error message, behavior, timing]
- [Symptom 2]

## Root Cause

[Why this happened. Be precise — not "the API was wrong" but "Ably's presence channel requires explicit auth via a server-side token request endpoint, not client-side API key auth."]

## Learning Level

- **Level:** Event / Pattern / Structure
- **Feedback loop or delay:** [If applicable, what reinforcing loop, balancing loop, missing feedback, or delayed effect made this likely?]

## Rule Scope

*Required for Pattern and Structure lessons. Optional for Event lessons — include only when the event's Solution embeds a transferable rule.*

[State the structural conditions under which the Solution's recommendation is correct, so a future `/research` consumer can pattern-match against their own work's shape without re-deriving the preconditions from prose. Be specific about shape, not just keywords — a 2-step agent loop with a terminal forced tool is a different shape from a 3-step loop where the same tool is non-terminal, even though both mention the same tool name. Note where the rule inverts if the conditions differ, and cross-reference sibling docs that cover the inverted or adjacent shape.]

- **Applies when:** [Structural preconditions — e.g., "the forced tool is terminal in the agent loop", "the callback replaces rather than merges the collection", "the component is a client component rendered inside an RSC boundary"]
- **Inverts or does not apply when:** [The shapes where following this recommendation would produce the opposite of the intended outcome, or simply not help — e.g., "for N+1-step loops where the tool is non-terminal, the `stopWhen` list must exclude it; see `<sibling-doc>`"]
- **Sibling docs:** [Links to `docs/solutions/` entries covering adjacent or inverted shapes, if any exist]

[Diagram suggestion: if Rule Scope describes conditional applicability with ≥3 distinguishable branches (multiple Applies-when shapes, or several Inverts-or-does-not-apply shapes that diverge in different directions), consider invoking `/mermaid` for a decision diagram showing which conditions route to which recommendation. Skip when the rule is binary (one Applies-when, one Inverts-when) — prose is already the cleanest rendering at that size.]

## Solution

[The actual fix. Include before/after code when it helps.]

**Before:**
```typescript
// What didn't work and why
```

**After:**
```typescript
// What works and why
```

## Prevention

[How to avoid this in the future. Separate code-level and process-level strategies.]

**Code-level:** [Tests, assertions, checks, linter rules that would catch this defect or its siblings.]

**Process-level:** [Pipeline step changes — e.g., "add auth token refresh to /write-a-prd's omitted activities scan" or "this defect class is a specification error; invest more in /shape for this domain."]

## Planning / Calibration Notes

[Include when the lesson should change future shaping, decomposition, or commitment language.]

- **What widened the work:** [Unknowns, omitted activities, or integration surprises]
- **What tightened the work:** [Tracer bullet, research answer, reused pattern, or existing baseline]
- **Future planning adjustment:** [What `/research`, `/write-a-prd`, or `/prd-to-issues` should do differently next time]

## Actuals Worth Reusing

[Include when this feature produced a reusable baseline for future work. Keep it lightweight and qualitative if hard numbers are unavailable.]

- **Comparable future work:** [What kind of feature this should inform]
- **Reusable baseline:** [Size, effort shape, scope pattern, or dependency pattern to remember]

## Defect Classification (bug-fix compounds only)

**Origin phase:** Specification error / Design error / Coding error
**Fix type:** Correction (addresses root cause) / Workaround (suppresses symptom — note what the real fix would require)

## Key Decision

[If an architectural or library choice was made, document it here.]

**Decision:** [What was chosen]
**Rationale:** [Why]
**Alternatives considered:** [What else was evaluated]
**Revisable:** [Yes/No — and under what conditions]

## Related

- [Link to GitHub issue or PR if applicable]
- [Link to related docs/solutions/ files if they exist]
- [Link to the research spike issue when one exists for this feature — `Refs #<spike-issue-number>`. This preserves the causal chain from research → PRD → slices → PR → compound, citable from any machine. If the project uses archive-mode research instead, omit this link — archive paths are openable only by the originating user, so they add no value to a `docs/solutions/` entry that may be read by others.]

## Shelf Life

[What change would make this solution unnecessary? E.g., "When Ably SDK v3 ships built-in auth" or "When we refactor the auth module per RFC #42". If this is an enduring principle, write "Evergreen — no expiration condition."]
```

**Adjust the template to fit the content.** Not every solution needs every section. A simple bug fix might just need Problem, Root Cause, Solution, and Prevention. An architectural decision might skip Symptoms and emphasize Key Decision. Don't pad sections that have nothing to say.

### Phase 4: Check for Overlaps

Before committing, search for existing solutions that might overlap:

```bash
grep -rl "relevant-keyword" docs/solutions/ 2>/dev/null
```

If a related solution already exists:
- **If it's the same problem solved again:** Update the existing file instead of creating a duplicate. Add new context, note if the solution changed.
- **If it's a related but distinct problem:** Create the new file and add cross-references in both documents.
- **If the existing solution is now outdated:** Update or supersede it. Never silently let stale solutions persist.

**Defect clustering check.** When compounding a bug fix, search for not just overlapping solutions but overlapping defect patterns. If `docs/solutions/` has 3+ entries in the same category with the same root-cause pattern, that pattern is a systemic issue worth noting in the solution (e.g., "all three auth integration bugs were specification errors — the PRD never addresses token refresh"). This feeds back into `/write-a-prd`'s omitted activities scan and `/shape`'s probing.

### Phase 5: Commit

**In-PR (the default):** commit the solution document onto the open PR branch and push, so the entry joins the PR and is reviewed and merged with the code that taught it:

```bash
git add docs/solutions/<category>/<filename>.md
git commit -m "docs: compound — <brief description of what was learned>"
git push        # in-PR path: push so the entry joins the open PR for review
```

**Post-merge (fallback):** the same commit lands on the base branch. If the repo requires review for the base branch, open a small PR for the doc rather than pushing it unreviewed — the whole point of the in-PR default is to keep `docs/solutions/` entries reviewed, so don't bypass that on the fallback path.

### Phase 6: Report

Tell the user what was captured, then print the closing block that matches the path you took.

**In-PR path (default)** — the lesson now rides the open PR; the loop closes when `/closeout` merges it. Hand off to the merge step:

```
Compounded onto PR #<n>: docs/solutions/<category>/<filename>.md

Key lesson: [One sentence summary of the most important takeaway]

This rides the PR — reviewed and merged with the code that taught it — and will be consulted automatically during future /research and /write-a-prd sessions.

**Next session:** /closeout
**Input:** PR #<n>
```

**Post-merge path (fallback)** — the work already shipped; this is the end of the loop:

```
Compounded: docs/solutions/<category>/<filename>.md

Key lesson: [One sentence summary of the most important takeaway]

This will be consulted automatically during future /research and /write-a-prd sessions.

**Loop closed.** Next: /help when you return to this repo.
```

On the in-PR path `/closeout` still follows — it performs the merge — so `/compound` hands to it with a `**Next session:**` line. On the post-merge path `/compound` is the end of the loop, so it prints the loop-closed line instead. `/help` is only a suggested re-entry point; the user may also re-enter via `/shape`, `/qa`, or any other appropriate skill.

## Maintenance

The `docs/solutions/` directory needs periodic maintenance. Solutions go stale when:

- The library/service updates with breaking changes
- You refactor away from the documented approach
- The codebase evolves past the documented pattern
- The context that made the solution correct changes, so the old advice would now mislead future work

When you notice a stale solution during research or planning, either update it or delete it. Stale solutions are worse than no solutions — they actively mislead the agent.

Use the `volatility` field to drive review cadence instead of a blanket schedule:

- **`volatile`** (dependency/API-specific) — review when those dependencies change, or at most every 90 days
- **`stable`** (architectural patterns) — review quarterly
- **`evergreen`** (fundamental principles) — review annually

During review, check each document's **Shelf Life** section. If the expiration condition has been met, delete the document. If the document describes a workaround for a design problem that has since been fixed, delete it — stale workarounds are worse than no documentation.

## Handoff

- **Expected input:** a durable lesson worth reusing — known at PR time (the in-PR default) or surfacing during/after merge (the post-merge fallback), plus solved bugs or meaningful lessons from implementation, QA, or review
- **Produces:** durable `docs/solutions/` knowledge that feeds future `/research` and `/write-a-prd` sessions — riding the PR on the in-PR path, committed to base (or a small doc PR) on the post-merge path
- **Comes after:** `/pre-merge` on the in-PR default path (capture onto the PR branch, then `/closeout` merges code + lesson together); `/closeout` on the post-merge fallback path. `/compound` captures the lesson — it never merges
- **Closes the loop on:** `/pre-merge`, `/closeout`, and shipped implementation work
- **What comes next:** in-PR, `/closeout` merges the PR carrying the lesson; post-merge, the loop is closed. Either way, future features consult the compounded knowledge during discovery, research, and shaping
