# Changelog

## v1.5.0 — TypeScript Audit Skill

Adds `/ts-audit` as a side-route skill for auditing TypeScript and React code against 9 Total TypeScript library references. Produces structured markdown reports with findings grouped by category (Type Safety, Generics, Discriminated Unions, Advanced Patterns, Type Transformations, React Patterns, Testing Patterns).

### Changes

- New skill: `/ts-audit` — audit TypeScript code quality against Total TypeScript best practices (user-invoked, side-route)
- `/ts-audit` SKILL.md: added Invocation Position and Handoff sections for pipeline integration
- `/pre-merge` Phase 3: added note about `/ts-audit` as optional companion for TypeScript projects
- `README.md` updated: skill count 20→21, `/ts-audit` added to Development table
- `CLAUDE.md` updated: side-route skills list
- `SYSTEM-OVERVIEW.md` updated: side-route skills list, directory tree, handoff map, quick reference table
- `docs/using-this-pack.md` updated: side-route skills list

## v1.4.2 — Compartmentalized Commits in /execute

`/execute` now commits after each logical unit of progress instead of accumulating all changes into a single commit at the end. This produces a clean, reviewable commit history where each commit is the smallest change that leaves the codebase working.

### Changes

- `/execute` Step 3 adds **"Commit after each logical unit"** section — defines what a logical unit is (TDD cycle, new module, wiring change, refactor, migration) and requires typecheck + test pass before each commit
- `/execute` Step 4 reframed as a full-slice integration verification pass — individual units are already committed, so this step confirms the whole feature works end-to-end; fixes discovered here become their own commits
- `/execute` Step 5 renamed from "Commit" to "Cleanup" — all commits are already done, this step only removes classification markers
- Handoff section updated: produces "compartmentalized commits (one per logical unit)" instead of "commit-ready work"

## v1.4.1 — Init Pipeline: Quality Gate, Better Lefthook Config, CLAUDE_PROJECT_DIR Paths

Improves `/init-pipeline` based on real-world usage. Adds optional quality gate hook for real-time feedback during editing, fixes hook command paths, and improves the Lefthook + Biome config template.

### Changes

- New optional Step 5: **Quality gate** — PostToolUse hook on Write|Edit that runs biome check, tsc, and vitest --changed after each file edit, catching issues while Claude works instead of only at commit time. Supports project-specific extensions (e.g., RAG smoke tests). Asks user before adding.
- `/init-pipeline` settings.json template now uses `"$CLAUDE_PROJECT_DIR"` prefix for hook command paths — fixes resolution issues when Claude's working directory differs from the project root
- Added recommended Lefthook + Biome config template with `--no-errors-on-unmatched`, `--files-ignore-unknown=true`, and `--colors=off` flags
- Lefthook config uses `commands` format (single Biome check) instead of `jobs` with parallel typecheck — typecheck is too slow for pre-commit and should be a pre-push hook
- Broader glob pattern: adds `cjs`, `mjs`, `d.cts`, `d.mts` to file matching

## v1.4.0 — Pipeline Enforcement via Init Pipeline + Claude Code Hooks

Adds deterministic enforcement for mandatory `/execute` steps (TDD classification, Ralph setup) that were previously prose-only and had a 50-85% compliance ceiling. A new `/init-pipeline` skill scaffolds Claude Code PreToolUse hooks into any project at runtime, and `/execute` auto-invokes it when hooks are missing.

### Changes

- New skill: `/init-pipeline` — scaffolds enforcement hooks, git guardrails, pre-commit hooks, and package manager enforcement into target projects at runtime (detects existing tools first, defaults to Lefthook + Biome + pnpm)
- `/execute` Step 0 restructured with three explicit gates: Ralph auto-detection (checklist format), pipeline hooks check (auto-invokes `/init-pipeline`), and TDD classification gate
- `/execute` Step 3 restructured with STOP classification gate — must classify work as backend/behavior-heavy/visual before writing any code
- `/execute` Step 5 now removes `.tdd-active` and `.tdd-skipped` markers after commit
- `/tdd` creates `.claude/.tdd-active` marker on entry; handoff documents marker cleanup
- `/setup-ralph-loop` creates `.claude/.ralph-checked` marker on completion
- `README.md` updated: skill count 19→20, `/init-pipeline` added to Tooling & Setup table
- `CLAUDE.md` updated: infrastructure skills list, key interactions (init-pipeline auto-invocation, TDD marker lifecycle)
- `SYSTEM-OVERVIEW.md` updated: file tree, handoff map, skill taxonomy, quick reference table, pre-commit hooks section
- `docs/using-this-pack.md` updated: infrastructure skills list, operating tips

### Infrastructure

- TDD classification enforcement via PreToolUse hook — blocks `.ts` writes without `.tdd-active` or `.tdd-skipped` marker
- Git guardrails integrated into `/init-pipeline` orchestration via `/git-guardrails-claude-code`
- Pre-commit hooks integrated into `/init-pipeline` orchestration via `/setup-pre-commit` (project-independent detection)
- `/tdd` marker creation is now deterministic via `!` command (harness preprocessing on skill load) — zero LLM compliance dependency for marker creation

## v1.3.0 — Auto-invoke Ralph Setup from /execute

`/execute` now automatically invokes `/setup-ralph-loop` when it detects multi-slice GitHub-issue work and no Ralph scripts exist in the repo. Previously, the language was passive ("if a repo wants"), which required the agent to infer intent and was easy to miss.

### Changes

- `/execute` Invocation Position section now has a **mandatory auto-detection check** with three explicit conditions: (1) task comes from a GitHub issue, (2) issue has multi-slice scope, (3) no `ralph-once.sh` or `ralph.sh` in repo root
- `/setup-ralph-loop` Invocation Position section now documents auto-invocation from `/execute`
- `SYSTEM-OVERVIEW.md` handoff map and Ralph setup section updated to reflect auto-detection as the primary trigger
- `CLAUDE.md` interaction note updated for `/setup-ralph-loop`
- `docs/using-this-pack.md` AFK execution section and operating tips updated

### Infrastructure

- `/setup-ralph-loop` is now listed as an infrastructure skill that can be auto-invoked, not just manually called

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
