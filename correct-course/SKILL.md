---
name: correct-course
description: "Side-route skill for explicit backtracking when an upstream artifact becomes untrustworthy. Use when research, PRD, or slice decomposition has been invalidated by new information and you need to clean up stale artifacts before re-running an earlier pipeline step. Not for forward progress, fresh shaping, or routine bug fixes."
sources:
  primary:
    - "Thinking in Systems — Donella Meadows"
  secondary:
    - "A Philosophy of Software Design — John Ousterhout"
---

# Correct Course

Run this skill when something has changed — new information, a failed assumption, a reshaped scope — and the current pipeline artifact can no longer be trusted. `/correct-course` diagnoses the blast radius, names the earliest skill that needs to re-run, and walks you through cleaning up stale artifacts before forward motion resumes.

This is the named, invocable form of the Pipeline Recovery rules in `SYSTEM-OVERVIEW.md`. Those rules still apply — this skill just gives them a front door.

> **One question per turn.** Throughout this skill, ask one question at a time and wait for the user's answer before asking the next. Backtracking is a conversation, not a form.

## Invocation Position

This is a side-route skill that reconnects to the main pipeline at whichever earlier skill the diagnosis points to.

Use `/correct-course` when any of the following is true:

- `/research` surfaced version changes or constraints that invalidate the `/shape` closing summary
- `/write-a-prd` reveals the problem was misframed during shaping
- `/prd-to-issues` reveals that the total work materially exceeds the stated appetite
- `/execute` hits an error whose root cause is that `research.md` or the PRD is wrong
- `/pre-merge` surfaces an architectural concern that warrants rework, not advisory findings
- A GitHub issue has gone stale because the work it described has been reshaped or superseded

Do not use it for:

- Forward progress that is still on track (use the normal pipeline)
- Bugs that just need triage (use `/qa` or `/triage-issue`)
- Refactor opportunities unrelated to stale artifacts (use `/request-refactor-plan`)
- Fresh shaping when no prior artifact exists (use `/shape`)

## Process

### 1. Capture the trigger

Ask one question: **"What changed that made the current artifact untrustworthy?"**

Let the user describe it in their own words. Do not ask follow-up questions yet. You are trying to understand the class of invalidation, not the full history:

- **New information** — a version check, a benchmark, a stakeholder comment, a failed demo
- **Failed assumption** — something the `/shape` summary marked `Likely` or `Uncertain` turned out to be wrong
- **Reshaped scope** — the appetite, no-gos, or must-haves need to change
- **Wrong problem framing** — the user realized they were solving the visible symptom, not the underlying problem
- **External force** — a dependency was deprecated, a pricing tier changed, a partner API was removed

Write down the class you think this is, in one sentence. You will use it in Step 2.

### 2. Diagnose the blast radius

Based on the trigger, determine the **earliest skill whose output is now untrustworthy**. The rule of thumb:

| Trigger | Earliest affected skill |
|---|---|
| `/shape` assumption is wrong | `/shape` |
| Version or API reality diverges from `research.md` | `/research` |
| Problem was misframed — solving symptom, not cause | `/shape` |
| Appetite or no-gos need to change | `/write-a-prd` |
| Solution direction is wrong but the problem and appetite still hold | `/write-a-prd` |
| Slice decomposition reveals work exceeds appetite | `/write-a-prd` (reshape), not `/prd-to-issues` (re-decompose) |
| Boundary map contract was wrong, slices are still valid | `/prd-to-issues` |
| Slice is correct but execution approach hit a wall | `/execute` (not a backtrack — try a different approach) |
| Architectural concern from `/pre-merge` warrants rework | `/execute`, possibly `/request-refactor-plan` first |

Explore the repo to confirm. Read the PRD issue, any slice issues, `research.md`, and the relevant parts of `docs/solutions/`. The goal is to be specific: not "shaping is stale" but "the Ably-vs-Pusher decision in `research.md` is wrong because Ably raised its free-tier limits and Pusher dropped theirs."

State the diagnosis to the user in one or two sentences and ask one question: **"Does that match what changed?"** If no, refine. If yes, proceed.

### 3. List stale artifacts

Now list every durable artifact that needs to be dealt with before forward progress can resume. Be specific — name the exact issue number, the exact file path. Common stale artifacts:

- **`research.md`** — delete it if the earliest affected skill is `/shape` or `/research`; update it in place only if the research findings are still mostly correct and a small section needs revision
- **PRD GitHub issue** — update in place if the problem and appetite still hold; comment and close if the entire PRD is being reshaped
- **Slice GitHub issues** — comment on each and close as superseded if the PRD is being reshaped; comment and leave open only if the specific slice is still valid
- **Planning or container milestone** — usually leave open; the milestone's feature issues or slice issues are the real artifacts
- **`docs/solutions/` entries** — flag as stale if this situation reveals the documented lesson is wrong, but do not delete without the user's confirmation
- **Open PR** — close with a comment explaining the backtrack if the PR is built on the stale artifact; leave open if the code is still correct but the framing is wrong
- **Active feature branch** — usually preserve; the branch is just code history, not a durable planning artifact

For each artifact, name it, name what should happen to it (delete, update in place, close with comment), and note the one-line reason. Present the full list to the user as a numbered plan.

### 4. Walk the cleanup

Walk the cleanup one artifact at a time. For each:

1. State what you are about to do and why.
2. Ask the user to confirm (one question: **"Proceed with this one?"**).
3. Do the action. Use `gh issue close`, `gh issue comment`, or direct file deletion as appropriate.
4. Move to the next.

Do not batch the cleanup into a single confirmation. Each artifact is a small, reversible decision, and batching increases the chance that a subtle mistake slips through. The cost of confirming each is small; the cost of closing the wrong issue is real.

If the user hesitates on any artifact, skip it and flag it as "needs review" in the final summary. Do not press.

### 5. Hand off

After the cleanup is complete, state explicitly:

- Which skill the user should run next (the earliest affected skill from Step 2)
- What context to bring into that skill (the trigger, the diagnosis, any artifacts preserved for reference)
- Whether the re-run should be scoped to a specific piece (most backtracks are scoped — "re-research the real-time provider decision" — not full re-runs)

Suggest starting the next skill in a fresh session if the conversation has been long. The closing summary is the compressed handoff.

## What This Skill is NOT

- **Not a bug triage tool.** If the trigger is a failing test or a runtime error, use `/qa` or `/triage-issue` first to diagnose whether it is a bug or a stale-artifact problem.
- **Not a refactor planner.** If the trigger is architectural pain with no stale upstream artifact, use `/improve-codebase-architecture` or `/request-refactor-plan`.
- **Not a full re-run.** A good correction scopes the re-run to what changed, not to everything. "We shaped X, but Y was wrong, so we are re-researching Z" is the target.
- **Not a replacement for reading `SYSTEM-OVERVIEW.md`.** The Pipeline Recovery section is still the canonical reference for what backtracking means in this pack. This skill makes that reference invocable.

## Handoff

- **Expected input:** a trigger that invalidated an upstream artifact, plus enough context to diagnose the blast radius
- **Produces:** a cleaned-up repo state with stale artifacts deleted, updated, or closed, and a named re-entry point into the main pipeline
- **Re-enters the main pipeline at:** `/shape`, `/research`, `/write-a-prd`, `/prd-to-issues`, or `/execute` depending on the diagnosis
- **What comes next:** the user runs the recommended earlier skill, scoped to the change, in a fresh session if the correction was large
