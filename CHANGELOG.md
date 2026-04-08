# Changelog

## v1.2.0 — Container Milestones for Big-Batch Work

Fills a gap in the pipeline where big-batch (6-week) work that fits a single PRD had no organizational container. Also fixes the `/shape` branching condition so "blank-project" no longer auto-triggers `/create-milestone`.

### Changes

- `/write-a-prd` now creates a lightweight GitHub milestone for big-batch work and attaches the PRD issue to it
- `/prd-to-issues` detects the milestone on the parent PRD and propagates it to all slice issues
- `/shape` branching condition corrected: route to `/create-milestone` only when work requires multiple independent PRDs, not for all blank projects
- `/create-milestone` description updated for consistency with the corrected condition
- `SYSTEM-OVERVIEW.md` updated: pipeline description, handoff map, state table, file tree, and quick reference

### Pipeline

Two types of milestones now exist (same GitHub object, different procedural origin):
- **Container milestone** — created by `/write-a-prd` for single-PRD big-batch work (one PRD + its slices)
- **Planning milestone** — created by `/create-milestone` for multi-PRD tranches (multiple feature bets)

## v1.1.0 — One Question Per Turn

Enforces a strict one-question-at-a-time conversational pattern across all pipeline skills. Skills now maintain a genuine back-and-forth instead of batching multiple questions into a single message.

### Changes

- Added `## Conversational Principles` section to `CLAUDE.md` as a global default for all skills
- Added per-skill `> **One question per turn.**` blockquote to `/shape`, `/research`, `/write-a-prd`, `/create-milestone`
- Rewrote batched-question sites in `/research` (Phase 2 constraints, Phase 6 review), `/write-a-prd` (structural checks, timeline framing), `/create-milestone` (branch confirmation), and `/design-an-interface` (synthesis) to ask sequentially

## v1.0.0 — Initial Public Release

### Skills (19)

**Primary Pipeline (8):**
- `/shape` — structured requirements discovery
- `/create-milestone` — GitHub milestone planning for multi-PRD tranche work
- `/research` — mandatory pre-PRD research with auto-calibrated depth
- `/write-a-prd` — PRD creation via Shape Up discipline, filed as GitHub issue
- `/prd-to-issues` — decompose PRD into vertical slices with boundary maps
- `/execute` — end-to-end implementation with verification (HITL or AFK)
- `/pre-merge` — create the PR and run architectural review before merge
- `/compound` — capture lessons learned into `docs/solutions/`

**Invoked Helpers (3):**
- `/design-an-interface` — generate multiple radically different interface designs
- `/api-design-review` — focused contract review for higher-risk API decisions
- `/tdd` — test-driven development with red-green-refactor loop

**Side-Route (5):**
- `/qa` — interactive QA session, files GitHub issues
- `/triage-issue` — investigate bugs, find root cause, create TDD fix plan
- `/improve-codebase-architecture` — surface deepening opportunities for shallow modules
- `/request-refactor-plan` — plan refactors with tiny commits
- `/ubiquitous-language` — DDD glossary with decisions register

**Infrastructure (2):**
- `/setup-pre-commit` — Lefthook + Biome pre-commit hooks
- `/git-guardrails-claude-code` — block dangerous git commands

### Pipeline

```
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → merge → /compound → cleanup
```

Branch: `/shape` → `/create-milestone` for oversized work before re-entering at `/research`.
