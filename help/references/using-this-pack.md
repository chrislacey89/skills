# Using Skill Kit

This guide explains how to use Skill Kit as a pipeline-first skills pack.

If you want a quick repo overview, read `../README.md`. If you want the deeper rationale for why the workflow is shaped this way, read `../SYSTEM-OVERVIEW.md`. If you want concrete examples of good slice sequences, boundary maps, and handoffs, read `example-pipeline-artifacts.md`. If you want to edit or author skills, read `skill-anatomy.md` and `../CLAUDE.md`.

## What Skill Kit is for

Skill Kit is built for feature delivery where:
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

### Start with `/qa`

Use when:
- behavior is failing and you need bug intake rather than normal feature flow

`/qa` is the single entry point for bug conversations. Within its per-issue loop, it delegates to `/triage-issue` for any specific bug that needs root-cause diagnosis before it can be filed lightweight, then returns to the loop. Do not start a bug session with `/triage-issue` directly — start with `/qa` and let the depth check decide.

### Start with `/help`

Use when:
- you are returning to a repo mid-pipeline and are not sure which skill to run next
- a new team member is onboarding and wants a recommendation grounded in actual repo state
- you just want confirmation that your mental model of the next step matches what is actually durable in GitHub

`/help` is advisory — it reads state (branch, PRs, issues, research archive, milestones) and recommends one next step. It does not run the recommended skill itself.

### Start with `/correct-course`

Use when:
- an upstream artifact (research, PRD, slice decomposition) has been invalidated by new information
- you need to clean up stale issues, supersede a stale research archive entry, or handle an in-flight PR before re-running an earlier pipeline skill
- `/research` or `/pre-merge` surfaced a concern that warrants deliberate backtracking rather than patching forward

`/correct-course` diagnoses the blast radius, walks artifact cleanup one decision at a time, and hands off to the earliest affected skill.

## Default pipeline

```text
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → /closeout (merge + teardown) → /compound → cleanup
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
- The minimum preconditions are: a clear GitHub issue, correct dependencies, enough boundary-map detail to avoid interface invention, and any needed research archive entry or `docs/solutions/` context already linked or available
- `Ralph` is the AFK execution mode for `/execute`, not a separate pipeline branch
- `/execute` auto-invokes `/setup-ralph-loop` when it detects multi-slice GitHub-issue work and no Ralph scripts exist — no manual setup needed

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
- `/closeout`
- `/compound`

`/execute` is the execution stage in this list, but it may run either HITL or AFK depending on how complete the upstream artifacts are.

### Invoked helper skills

These are usually called from another skill when a narrower question needs focused rigor:
- `/api-design-review`
- `/design-an-interface`
- `/tdd`
- `/triage-issue` — invoked from `/qa` per issue when a specific bug needs root-cause diagnosis

### Side-route skills

These support or re-enter the main flow:
- `/qa`
- `/request-refactor-plan`
- `/improve-codebase-architecture`
- `/ubiquitous-language`
- `/ts-audit`
- `/help` — orientation skill that reads repo state and recommends the next pipeline skill
- `/correct-course` — invocable backtracking skill for when an upstream artifact has gone stale
- `/handoff` — invocable session-compaction skill for when no inter-skill compression artifact fits (mid-skill, exploratory, or cross-agent handoff); writes a transient doc at a `mktemp` path rather than inside the repo

### Infrastructure skills

These are setup or safety tasks, not normal delivery stages:
- `/init-pipeline` (orchestrates the others — auto-invoked by `/execute` when hooks are missing)
- `/setup-pre-commit`
- `/setup-ralph-loop`
- `/git-guardrails-claude-code`

## Artifacts and where state lives

Skill Kit prefers durable state in GitHub and temporary state only when it serves a narrow purpose.

### Durable state

- PRDs live in GitHub issues
- milestone roadmaps live in GitHub milestones plus feature issues
- slices live in GitHub issues with dependency relationships
- QA findings live in GitHub issues
- PR lineage lives in GitHub PRs
- compounded lessons live in `docs/solutions/`

### Durable per-user artifacts outside the repo

- Research files live in `~/.claude/research/<repo-slug>/<feature>-<date>.md` — worktree- and branch-resilient, not committed to the repo, freshness judged via frontmatter `date` and `installed_versions_snapshot`
- Skill-local reference files live next to the skill when they are specific to that skill

### What Skill Kit avoids

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

- An archived research file with verified docs, version checks, and recommended approach

For milestone-planned work, `/research` should consume the selected feature issue only after it has been expanded into a `research-ready` brief.

### `/write-a-prd`

- a shaped PRD issue with appetite, solution, rabbit holes, no-gos, and implementation decisions

### `/prd-to-issues`

- implementation-ready slice issues with boundary maps and dependency order

### `/execute`

- verified implementation work ready for review or for the next AFK iteration to pick up cleanly

### `/pre-merge`

- a PR with lineage and an architectural review readout

### `/closeout`

- a merged PR and a clean base: worktree torn down, branch pruned, base pulled, end state verified

### `/compound`

- durable project knowledge in `docs/solutions/`

## Operating tips

- Use the written artifact from the previous step instead of relying on full conversation history.
- Research files live in `~/.claude/research/<repo>/…` outside the repo. They persist across features — let stale entries age naturally; the frontmatter `date` and `installed_versions_snapshot` are how future readers judge freshness.
- Treat `docs/solutions/` as a compounding loop, not a dumping ground.
- For milestone-planned work, do not run `/research` against a raw `roadmap bet`; promote the chosen feature issue to `research-ready` first.
- Use helper skills only when their narrower rigor is actually needed.
- `/execute` handles Ralph setup automatically for multi-slice GitHub-issue work. You can also invoke `/setup-ralph-loop` directly if you want to set up Ralph before reaching `/execute`.
- `/execute` handles pipeline enforcement setup automatically via `/init-pipeline` when Claude Code hooks are missing. This scaffolds TDD classification gates, git guardrails, and pre-commit hooks (detecting existing tools first). You can also invoke `/init-pipeline` directly.
- Keep side-route skills tied back to the main flow so work does not drift.

## If you are editing Skill Kit itself

Read these in order:
- `../README.md`
- `../CLAUDE.md`
- `skill-anatomy.md`
- the specific `SKILL.md` you are changing

When editing a skill, preserve the repo's two strongest conventions:
- the skill should make its invocation role obvious
- the skill should end with a clear handoff
