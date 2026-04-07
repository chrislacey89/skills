# Using This Pack

This guide explains how to use this repository as a pipeline-first skills pack.

If you want a quick repo overview, read `../README.md`. If you want the deeper rationale for why the workflow is shaped this way, read `../SYSTEM-OVERVIEW.md`. If you want concrete examples of good slice sequences, boundary maps, and handoffs, read `example-pipeline-artifacts.md`. If you want to edit or author skills, read `skill-anatomy.md` and `../CLAUDE.md`.

## What this pack is for

This pack is built for feature delivery where:
- planning state should live in GitHub issues and PRs
- research should be verified before shaping
- implementation should follow explicit handoffs
- shipped work should improve future planning through `docs/solutions/`

It is not a generic collection of interchangeable prompts. The skills are designed to compose into a specific workflow.

## Default entrypoints

Start with the first skill that matches the state of the work.

### Start with `/shape`

Use when:
- the problem is still fuzzy
- scope is still emerging
- stakeholder goals or assumptions are unclear

If the shaped outcome is too large for a single PRD, `/shape` can branch to `/create-milestone` instead of handing off directly to `/research`.

### Start with `/create-milestone`

Use when:
- `/shape` already clarified a blank-project or major-tranche outcome
- the work is too large for a single PRD
- you need a GitHub milestone plus sequenced feature bets before feature-level research begins

### Start with `/research`

Use when:
- the problem is already clarified
- you need current docs, version checks, repo patterns, or technical validation before shaping
- a milestone feature has already been promoted to `research-ready`

### Start with `/write-a-prd`

Use when:
- discovery and research are already in place
- the work is ready to become a bounded PRD issue

### Start with `/prd-to-issues`

Use when:
- a PRD already exists
- the next need is implementation-ready slices and boundary maps

### Start with `/execute`

Use when:
- there is already a concrete slice, issue, or clearly scoped implementation task
- the work is ready to build and verify
`Ralph` is the AFK execution mode/persona for this stage, not a separate skill or pipeline step. Use HITL `/execute` when the slice still needs active user decisions, review, or supervision. Use AFK `/execute` only when the slice is already durable in GitHub, unblocked, and clear enough to execute without renegotiating scope.

### Start with `/qa` or `/triage-issue`

Use when:
- behavior is failing and you need bug intake or diagnosis rather than normal feature flow

## Default pipeline

```text
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → merge → /compound → cleanup
```

Treat this as the default route, not a prison. For blank-project or major-tranche work that is too large for a single PRD, `/shape` can branch to `/create-milestone`, which creates a GitHub milestone plus feature issues that mature from `roadmap bet` to `research-ready` to `prd` before re-entering the default route at `/research`. The workflow supports branch points and deliberate backtracking.

## Operating modes

The pipeline stays the same, but the way you run a stage can change.

### Planning mode

- Use for shaping, research, decomposition, review, or critique
- Typical stages: `/shape`, `/research`, `/write-a-prd`, `/prd-to-issues`, `/pre-merge`
- Goal: produce better artifacts and better decisions, not code throughput

### HITL execution mode

- Use when implementation still needs active user judgment
- Good fits: design-sensitive work, contract decisions, ambiguous bugs, risky migrations, or any slice where acceptance still depends on conversation
- Typical stage: `/execute`

### AFK execution mode

- Use when the next slice is already unblocked and legible from durable artifacts
- The minimum preconditions are: a clear GitHub issue, correct dependencies, enough boundary-map detail to avoid interface invention, and any needed `research.md` or `docs/solutions/` context already linked or available
- `Ralph` is the AFK execution mode for `/execute`, not a separate pipeline branch
- If the repo does not already have Ralph runner scripts, use `/setup-ralph-loop` before expecting repeatable AFK execution

A good default is: plan in public, execute from durable artifacts, and fall back to HITL the moment the work needs new shaping rather than implementation.

## Skill roles

### Primary pipeline skills

These are the direct-entry stages in the main delivery path:
- `/shape`
- `/create-milestone`
- `/research`
- `/write-a-prd`
- `/prd-to-issues`
- `/execute`
- `/pre-merge`
- `/compound`

`/execute` is the execution stage in this list, but it may run either HITL or AFK depending on how complete the upstream artifacts are.

### Invoked helper skills

These are usually called from another skill when a narrower question needs focused rigor:
- `/api-design-review`
- `/design-an-interface`
- `/tdd`

### Side-route skills

These support or re-enter the main flow:
- `/qa`
- `/triage-issue`
- `/request-refactor-plan`
- `/improve-codebase-architecture`
- `/ubiquitous-language`

### Infrastructure skills

These are setup or safety tasks, not normal delivery stages:
- `/setup-pre-commit`
- `/setup-ralph-loop`
- `/git-guardrails-claude-code`

## Artifacts and where state lives

This pack prefers durable state in GitHub and temporary state only when it serves a narrow purpose.

### Durable state

- PRDs live in GitHub issues
- milestone roadmaps live in GitHub milestones plus feature issues
- slices live in GitHub issues with dependency relationships
- QA findings live in GitHub issues
- PR lineage lives in GitHub PRs
- compounded lessons live in `docs/solutions/`

### Temporary or local artifacts

- `research.md` exists only long enough to support shaping and implementation
- skill-local reference files live next to the skill when they are specific to that skill

### What this pack avoids

- large local planning forests like `.gsd/`
- per-task state files that drift out of sync
- long-lived local summaries that duplicate issue and PR state

## Backtracking rules

Backtracking is expected when the current artifact is no longer truthful.

Examples:
- `/research` can send work back to `/shape` when the underlying assumptions are wrong
- `/write-a-prd` can send work back to `/research` when shaping exposes missing technical truth
- `/prd-to-issues` can send work back to `/write-a-prd` when decomposition reveals scope beyond the appetite
- `/pre-merge` can send work back to `/execute` when review reveals deeper rework
- if a bug, refactor, or review finding changes problem framing, stakeholder goals, scope boundaries, or contract assumptions, backtrack to `/shape` or `/research` instead of continuing as if the work were still implementation-ready

Rule:
- when you backtrack, update or delete stale artifacts instead of leaving them behind for later skills to trust

## What each major stage should leave behind

### `/shape`

- clarified choices
- assumptions with confidence tags
- impositions
- structural signals

Treat this closing summary as the compressed handoff artifact for the next stage. If `/research` or `/create-milestone` starts in a fresh session, carry these four categories forward explicitly rather than relying on the full conversation transcript.

For blank-project or major-tranche work, `/shape` can hand that closing summary to `/create-milestone` instead of directly to `/research`.

### `/create-milestone`

- a GitHub milestone with a limited set of sequenced feature issues
- feature issues that start as `roadmap bet`
- a selected feature promoted to `research-ready` before it re-enters at `/research`

### `/research`

- `research.md` with verified docs, version checks, and recommended approach

For milestone-planned work, `/research` should consume the selected feature issue only after it has been expanded into a `research-ready` brief.

### `/write-a-prd`

- a shaped PRD issue with appetite, solution, rabbit holes, no-gos, and implementation decisions

### `/prd-to-issues`

- implementation-ready slice issues with boundary maps and dependency order

### `/execute`

- verified implementation work ready for review or for the next AFK iteration to pick up cleanly

### `/pre-merge`

- a PR with lineage and an architectural review readout

### `/compound`

- durable project knowledge in `docs/solutions/`

## Operating tips

- Use the written artifact from the previous step instead of relying on full conversation history.
- Keep `research.md` temporary. If it no longer supports active work, delete it.
- Treat `docs/solutions/` as a compounding loop, not a dumping ground.
- For milestone-planned work, do not run `/research` against a raw `roadmap bet`; promote the chosen feature issue to `research-ready` first.
- Use helper skills only when their narrower rigor is actually needed.
- Use `/setup-ralph-loop` when a repo wants repeatable HITL-to-AFK execution around `/execute` rather than hand-rolling Ralph scripts ad hoc.
- Keep side-route skills tied back to the main flow so work does not drift.

## If you are editing the pack itself

Read these in order:
- `../README.md`
- `../CLAUDE.md`
- `skill-anatomy.md`
- the specific `SKILL.md` you are changing

When editing a skill, preserve the repo's two strongest conventions:
- the skill should make its invocation role obvious
- the skill should end with a clear handoff
