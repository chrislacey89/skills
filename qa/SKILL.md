---
name: qa
description: "Side-route skill and single entry point for bug conversations. Use when the user is reporting observed failures and wants durable GitHub issues filed in project language. Delegates per-issue to /triage-issue for bugs that need root-cause diagnosis, then returns to the loop. Not for already-scoped implementation work (use /execute)."
---

# QA Session

Run an interactive QA session. The user describes problems they're encountering. You clarify, explore the codebase for context, and file GitHub issues that are durable, user-focused, and use the project's domain language. For any one bug that needs deeper diagnosis before it can be filed lightweight, you delegate to `/triage-issue` for that issue and then return to the loop for the next observation.

## Invocation Position

This is a side-route skill, not a default shaping or implementation step. It is the **single entry point for bug conversations** — `/triage-issue` is no longer a direct entry point and is instead invoked from here on a per-issue basis when depth is needed.

Use `/qa` when the user is testing behavior, reporting bugs conversationally, or wants help turning observed failures into durable GitHub issues.

Do not use it when the task is already a concrete, well-scoped implementation task ready for `/execute`.

## For each issue the user raises

### 1. Listen and lightly clarify

Let the user describe the problem in their own words. Ask **at most 2-3 short clarifying questions** focused on:

- What they expected vs what actually happened
- Steps to reproduce (if not obvious)
- Whether it's consistent or intermittent

Do NOT over-interview. If the description is clear enough to file, move on.

### 2. Explore the codebase in the background

While talking to the user, kick off an Agent (subagent_type=Explore) in the background to understand the relevant area. The goal is NOT to find a fix — it's to:

- Start with a lightweight hypothesis about what class of failure might explain the behavior so your exploration is guided rather than wandering. Revise the hypothesis as you gather evidence.
- Learn the domain language used in that area (check UBIQUITOUS_LANGUAGE.md)
- Understand what the feature is supposed to do
- Identify the user-facing behavior boundary

This context helps you write a better issue — but the issue itself should NOT reference specific files, line numbers, or internal implementation details.

### 3. Assess scope: single issue or breakdown?

Before filing, decide whether this is a **single issue** or needs to be **broken down** into multiple issues.

Break down when:

- The fix spans multiple independent areas (e.g. "the form validation is wrong AND the success message is missing AND the redirect is broken")
- There are clearly separable concerns that different people could work on in parallel
- The user describes something that has multiple distinct failure modes or symptoms

Keep as a single issue when:

- It's one behavior that's wrong in one place
- The symptoms are all caused by the same root behavior

### 3.5. Decide depth: lightweight file or delegate to /triage-issue

For each issue identified in Step 3, decide whether it can be filed lightweight or needs deeper diagnosis. Apply this decision **per issue**, not per session — most QA sessions mix both kinds.

**Delegate to `/triage-issue` when at least one of these holds:**

- The user explicitly asks for diagnosis, root cause, or "why" this is happening
- The bug is a regression — it worked before and broke recently
- Your lightweight Step 2 exploration could not form a confident hypothesis about the cause
- Reproduction is intermittent or unreliable
- Multiple symptoms might share an upstream cause and the user wants that confirmed

**Stay lightweight (continue to Step 4) when:**

- Reproduction steps are clear and the cause is obvious in class (missing validation, cosmetic issue, clear null case)
- The user just wants the bug on the backlog, not debugged
- The behavior is wrong in one place and the fix is uncontroversial

**When delegating to `/triage-issue`:**

1. State the decision and the reason to the user in one sentence — e.g. "This one looks like a regression and I can't form a hypothesis without reproducing it, so I'll switch to deep diagnosis for this issue."
2. Run `/triage-issue` Steps 2–5 (reproduce, explore + diagnose, optional structural diagnosis, fix approach, TDD fix plan, issue creation) on this single bug.
3. The issue created by `/triage-issue` **replaces** the lightweight issue Step 4 would otherwise have filed for this bug — do not file both.
4. Once the triage issue is created, return to the `/qa` loop and continue with the next observation in Step 5.

If Step 3 produced a breakdown, apply this depth decision to each sub-issue independently. A single QA report can produce a mix of lightweight `/qa` issues and deep `/triage-issue` issues.

### 4. File the GitHub issue(s)

This step runs only for issues that stayed lightweight in Step 3.5. Issues that delegated to `/triage-issue` are already filed by that skill and skip this step.

Create issues with `gh issue create`. Do NOT ask the user to review first — just file and share URLs.

Issues must be **durable** — they should still make sense after major refactors. Write from the user's perspective.

#### For a single issue

Use this template:

```
## What happened

[Describe the actual behavior the user experienced, in plain language]

## What I expected

[Describe the expected behavior]

## Steps to reproduce

1. [Concrete, numbered steps a developer can follow]
2. [Use domain terms from the codebase, not internal module names]
3. [Include relevant inputs, flags, or configuration]

## Additional context

[Any extra observations from the user or from codebase exploration that help frame the issue — e.g. "this only happens when using the Docker layer, not the filesystem layer" — use domain language but don't cite files]
```

#### For a breakdown (multiple issues)

Create issues in dependency order (blockers first) so you can reference real issue numbers.

Use this template for each sub-issue:

```
## Parent issue

#<parent-issue-number> (if you created a tracking issue) or "Reported during QA session"

## What's wrong

[Describe this specific behavior problem — just this slice, not the whole report]

## What I expected

[Expected behavior for this specific slice]

## Steps to reproduce

1. [Steps specific to THIS issue]

## Blocked by

- #<issue-number> (if this issue can't be fixed until another is resolved)

Or "None — can start immediately" if no blockers.

## Additional context

[Any extra observations relevant to this slice]
```

When creating a breakdown:

- **Prefer many thin issues over few thick ones** — each should be independently fixable and verifiable
- **Mark blocking relationships honestly** — if issue B genuinely can't be tested until issue A is fixed, say so. If they're independent, mark both as "None — can start immediately"
- **Create issues in dependency order** so you can reference real issue numbers in "Blocked by"
- **Maximize parallelism** — the goal is that multiple people (or agents) can grab different issues simultaneously

#### Rules for all issue bodies

- **No file paths or line numbers** — these go stale
- **Use the project's domain language** (check UBIQUITOUS_LANGUAGE.md if it exists)
- **Describe behaviors, not code** — "the sync service fails to apply the patch" not "applyPatch() throws on line 42"
- **Reproduction steps are mandatory** — if you can't determine them, ask the user
- **Keep it concise** — a developer should be able to read the issue in 30 seconds

After filing, print all issue URLs (with blocking relationships summarized) and ask: "Next issue, or are we done?"

### 5. Continue the session

Keep going until the user says they're done. Each issue is independent — don't batch them.

## Handoff

- **Expected input:** observed user-facing failures, regressions, or QA findings — `/qa` is the single entry point for bug conversations
- **Produces:** durable GitHub issues written in domain language, plus per-issue triage issues from `/triage-issue` when depth was needed
- **Delegates per-issue to:** `/triage-issue` for bugs that fail the Step 3.5 depth check; control returns to the `/qa` loop after each delegation
- **Feeds back into:** `/execute` once the filed bug work is ready to implement
