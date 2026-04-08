# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Use this file when editing the skills pack itself. For a quick overview of the repository, read `README.md`. For the deeper workflow philosophy and detailed delivery model, read `SYSTEM-OVERVIEW.md`.

## What This Repository Is

A personal directory of Claude Code skills — composable workflow steps that form a feature development pipeline. Skills are installed globally for Claude Code via `npx skills@latest add chrislacey89/skills --skill '*' --agent claude-code --global -y`.

This repo is not an application — there is no build system, test runner, or deployment target. Each subdirectory contains a `SKILL.md` (with YAML frontmatter for `name` and `description`) and optional reference files.

## The Pipeline

Skills compose into an ordered pipeline for taking a feature from idea to shipped:

```
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → merge → /compound → delete research.md
```

This summary is here so skill authors can keep handoffs consistent. For work that requires multiple independent PRDs, `/shape` may branch to `/create-milestone`, which creates a planning milestone plus feature issues that mature from `roadmap bet` to `research-ready` to `prd` before re-entering the default path at `/research`. For big-batch work (6 weeks) that fits a single PRD, `/write-a-prd` creates a lightweight container milestone and attaches the PRD issue to it; `/prd-to-issues` then propagates the milestone to all slice issues. `Ralph` is the AFK execution mode/persona for the `/execute` stage, not a separate pipeline step. The canonical rationale, state model, and recovery rules live in `SYSTEM-OVERVIEW.md`.

## Operating Modes

The pipeline steps stay the same, but skill authors should be explicit about which operating mode a stage assumes:

- **Planning mode** — shaping, research, decomposition, and review. The output is a better artifact or better decision, not code throughput.
- **HITL execution mode** — implementation or verification that still depends on active user judgment.
- **AFK execution mode** — implementation from durable artifacts when the next slice is already unblocked and sufficiently legible.

When a skill participates in execution, say whether it is normally HITL, AFK, or both. If AFK execution is allowed, say what artifacts must already exist before it is safe to proceed.

Key interactions between skills:
- `/research` is mandatory between `/shape` and `/write-a-prd` — never skip it
- `/shape` branches to `/create-milestone` only when the shaped work requires multiple independent PRDs — not for all blank projects or large-scope efforts that fit one PRD
- `/create-milestone` creates a planning milestone plus sequenced feature issues and promotes the next chosen feature from `roadmap bet` to `research-ready` before it re-enters the main flow at `/research`
- `/write-a-prd` creates a container milestone for big-batch (6-week) work that fits a single PRD; `/prd-to-issues` propagates the milestone to all slice issues
- `/research` invokes `/api-design-review` for higher-risk API contract work (new external APIs, contract changes, OAuth/webhook security, or unresolved paradigm choices)
- `/write-a-prd` uses Shape Up's shaping discipline (appetite → solution → rabbit holes → no-gos), requires a lightweight API contract sketch for API-shaped work, and auto-invokes `/design-an-interface` or `/api-design-review` when the interface or contract is still uncertain; when the input issue came from `/create-milestone`, it expands the existing `research-ready` feature issue into the full PRD rather than creating a duplicate issue
- `/execute` delegates to `/tdd` for backend code and consults `docs/solutions/` + `research.md` before implementation
- `/setup-ralph-loop` is auto-invoked by `/execute` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist — prepares `ralph-once.sh` and bounded `ralph.sh` for HITL-to-AFK execution
- `/prd-to-issues` produces boundary maps (Produces/Consumes) that `/execute` reads to understand interfaces
- `/pre-merge` creates the PR with PRD lineage and verifies boundary map contracts from `/prd-to-issues` against actual code
- `/compound` runs after ship to capture lessons into `docs/solutions/` — this is the compounding loop, and it may also capture tranche-level lessons when a milestone closes
- When backtracking to an earlier skill, stale artifacts (`research.md`, PRD issues, slice issues) must be explicitly updated or removed before proceeding forward — see SYSTEM-OVERVIEW.md "Pipeline Recovery"

## Invocation Roles

Use these categories consistently across the repo:

- **Primary pipeline skills** — direct-entry steps in the default delivery path, plus the milestone-planning branch for oversized work: `/shape`, `/create-milestone`, `/research`, `/write-a-prd`, `/prd-to-issues`, `/execute`, `/pre-merge`, `/compound`
- **Invoked helper skills** — usually not top-level entry points for a feature, but delegated when a narrower decision is unresolved: `/api-design-review`, `/design-an-interface`, `/tdd`
- **Side-route skills** — valid alternate or supporting paths beside the main pipeline: `/qa`, `/triage-issue`, `/request-refactor-plan`, `/improve-codebase-architecture`, `/ubiquitous-language`
- **Infrastructure skills** — project setup or safety tooling, not normal delivery steps: `/setup-pre-commit`, `/setup-ralph-loop`, `/git-guardrails-claude-code`

Each skill should make its role obvious.

- **Direct-entry skills** should say when to start with them and whether they are on the default feature path or the milestone-planning branch.
- **Invoked helpers** should say who calls them and when not to call them directly.
- **Side-route skills** should say how they reconnect to the main workflow.
- **Infrastructure skills** should say they are setup tasks, not feature-delivery stages.

## Handoff Contract

Each pipeline skill should end with a clear transition statement:

- **Expected input** — the artifact, decision, or context it needs
- **What it produces** — the artifact, decision, or verified outcome it leaves behind
- **What comes next** — the default next skill or branch

If a skill can branch, the branch condition should be explicit. Example: `/shape` normally hands off to `/research`, but branches to `/create-milestone` when the work requires multiple independent PRDs. Example: `/write-a-prd` creates a container milestone for big-batch appetite before creating the PRD issue. If a skill advances an issue through maturity states, name them explicitly (`roadmap bet` → `research-ready` → `prd`) so downstream skills do not guess what artifact they are consuming.

## Conversational Principles

**One question per turn.** When a skill needs to ask the user multiple questions, ask one question at a time and wait for the answer before asking the next. Never present a numbered list of questions, a bulleted set of questions, or multiple questions in a single message. This applies to every phase of every skill — discovery, constraint confirmation, review, and closing. The goal is a genuine back-and-forth conversation, not a form to fill out.

## Architectural Principles

**Deep modules over shallow modules.** Skills like `/tdd`, `/improve-codebase-architecture`, and `/write-a-prd` all reference John Ousterhout's "A Philosophy of Software Design" — small interfaces hiding deep implementations. This shapes how interfaces are designed and refactored.

**Vertical slices, not horizontal layers.** `/tdd` enforces one-test-one-implementation cycles (not "write all tests then all code"). `/prd-to-issues` decomposes into tracer-bullet vertical slices that cut through all layers end-to-end.

**State lives in GitHub, not the filesystem.** PRDs, milestones, work items, and bugs are GitHub issues or GitHub milestones. Milestones serve two procedural roles: container milestones (from `/write-a-prd` for single-PRD big-batch work) and planning milestones (from `/create-milestone` for multi-PRD tranches) — both are the same GitHub object. No `.gsd/` directories, no `STATE.md`, no `PLAN.md` per slice. The only persistent filesystem artifacts are skills themselves and `docs/solutions/`.

**`research.md` is temporary.** Created by `/research`, referenced by the PRD and by `/execute` executions including Ralph's AFK loop, then deleted after the feature ships. Stale research actively harms agent performance.

## Skill Structure

Every skill has a `SKILL.md` with:
```yaml
---
name: skill-name
description: "When to invoke this skill"
sources:
  primary:
    - "Book Title — Author"
  secondary:
    - "Book Title — Author"
---
```

Some skills have supporting reference files (e.g., `tdd/` has `deep-modules.md`, `interface-design.md`, `mocking.md`, `tests.md`, `refactoring.md`). The `improve-codebase-architecture/` skill has a `REFERENCE.md` with dependency categories and the RFC issue template. `git-guardrails-claude-code/` bundles a shell script at `scripts/block-dangerous-git.sh`.

## Editing Skills

When modifying a skill:
- Preserve YAML frontmatter (`name` and `description`) — these are used for skill discovery and invocation
- The `description` field determines when the skill triggers; write it as a usage hint, not a summary
- Make the `description` immediately answer three questions when possible: when to invoke, when not to invoke, and whether the skill is direct-entry, delegated, or conditional
- `sources` is an optional repo-local field, but expected for skills making substantive methodological claims
- `primary` means core lineage — the skill is fundamentally built on this work
- `secondary` means a supporting influence — a specific technique or check drawn from this work
- Do not put provenance into `description`; keep it optimized for triggering
- Only claim a source if the skill body clearly operationalizes it
- Prefer short source lists over comprehensive ones
- Keep skills self-contained — each should work without requiring the user to read SYSTEM-OVERVIEW.md
- Cross-skill references (like `/execute` delegating to `/tdd`) should use the `/skill-name` convention
- Add a short invocation-position or handoff section when a skill participates in a larger workflow
- If a skill reconnects to the main pipeline, say exactly where it reconnects
- If a skill advances an issue through lifecycle states, define those states and the minimum content required to move between them
- If a skill can run HITL or AFK, say which mode is expected by default and what durable artifacts must exist before AFK execution is safe
