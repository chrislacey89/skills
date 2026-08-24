# Skill Kit

[![License: MIT](https://img.shields.io/github/license/chrislacey89/skills)](LICENSE)
![Skills](https://img.shields.io/badge/skills-30-blue)
![CLI](https://img.shields.io/badge/npx%20skills-compatible-green)

Skill Kit is a pipeline-first Claude Code skills pack for structured feature delivery. 30 composable skills that take a feature from idea to shipped — with explicit handoffs, verified research, and a compounding knowledge loop.

Built around structured research, GitHub-native state, and a compounding knowledge loop in `docs/solutions/`. Compatible with Claude Code, Cursor, Windsurf, and any agent that can consume SKILL.md files.

## Installation

Global install (all skills, Claude Code):

```bash
npx skills@latest add chrislacey89/skills --skill '*' --agent claude-code --global -y
```

### Requirements

Most skills need only an agent that reads `SKILL.md` files. The pipeline's GitHub-native state has one version floor:

| Requirement | Needed for | Notes |
|---|---|---|
| [`gh`](https://cli.github.com) **≥ 2.94.0** | issue dependencies and sub-issue relationships in `/prd-to-issues`, `/qa`, `/execute`, `/help`, `/setup-ralph-loop` | Released 2026-06-10. Earlier versions lack `gh issue edit --add-blocked-by` and the `blockedBy` / `blocking` `--json` fields. Check with `gh --version`. |

On GitHub Enterprise Server, issue **types** and **sub-issues** need GHES 3.17+, and issue **dependencies** need GHES 3.19+. Where dependencies are unavailable, the filing skills degrade to the prose `## Blocked by` section and say so rather than failing.

## Keeping skills updated

The skills CLI tracks content hashes. When this repo updates, your installed copies know about it:

```bash
npx skills@latest check    # see what changed upstream
npx skills@latest update   # pull latest versions
```

## What Skill Kit optimizes for

- **GitHub-native state** — PRDs, slices, QA bugs, and lineage live in GitHub issues and PRs, not a sprawling local planning filesystem.
- **Explicit handoffs** — skills declare what they expect, what they produce, and what comes next.
- **Verified research before PRD writing** — `/research` is a first-class step, not an optional extra.
- **Compounded knowledge** — shipped lessons feed future work through `docs/solutions/`.

## Canonical pipeline

```
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → /compound (in-PR) → /closeout (merge + teardown) → cleanup
```

The pipeline is the default path, not a prison. Skills can backtrack when assumptions fail or branch to helper and side-route skills when the work demands it. For blank-project or major-tranche work that is too large for a single PRD, `/shape` can branch to `/create-milestone`, which creates a GitHub milestone plus feature issues that mature from `roadmap bet` to `research-ready` to `prd` before re-entering the normal pipeline at `/research`. `Ralph` is the AFK execution mode/persona for the `/execute` stage, not a separate pipeline step — it stops on repeated failure *or* repeated non-progress, whichever trips first.

## Skills

### Planning & Design

| Skill | Description |
|-------|-------------|
| [shape](shape/) | Structured requirements discovery — shared understanding before research |
| [create-milestone](create-milestone/) | Turn a shaped app-sized or tranche-sized idea into a GitHub milestone with sequenced feature bets |
| [research](research/) | Mandatory pre-PRD research with auto-calibrated depth |
| [write-a-prd](write-a-prd/) | PRD creation via interview, filed as GitHub issue |
| [prd-to-issues](prd-to-issues/) | Break PRD into vertical slices with boundary maps |
| [design-an-interface](design-an-interface/) | Generate multiple radically different interface designs |
| [api-design-review](api-design-review/) | Focused contract review for higher-risk API design decisions |
| [prototype](prototype/) | Throwaway code that answers a question — LOGIC (state model), UI (layout variants), or FEASIBILITY (spike-solution discharge for `Uncertain` research assumptions) |
| [mermaid](mermaid/) | Generate Mermaid diagram source (flowcharts, sequence, ER, state, C4, Gantt, and 18 more) for embedding in PRDs, research notes, and issues |

### Development

| Skill | Description |
|-------|-------------|
| [execute](execute/) | Execute a unit of work end-to-end with verification |
| [tdd](tdd/) | Test-driven development with red-green-refactor loop (invoked from `/execute`) |
| [triage-issue](triage-issue/) | Deep bug diagnosis + root cause + TDD fix plan (invoked from `/qa` per issue) |
| [improve-codebase-architecture](improve-codebase-architecture/) | Surface deepening opportunities for shallow modules |
| [request-refactor-plan](request-refactor-plan/) | Plan refactors with tiny commits |
| [ts-audit](ts-audit/) | Audit TypeScript code against 9 bundled TypeScript library references |

### Tooling & Setup

| Skill | Description |
|-------|-------------|
| [init-pipeline](init-pipeline/) | Scaffold pipeline enforcement — Claude Code hooks, git guardrails, pre-commit setup (auto-invoked by `/execute`) |
| [setup-pre-commit](setup-pre-commit/) | Lefthook + Biome pre-commit hooks (detects existing tools) |
| [git-guardrails-claude-code](git-guardrails-claude-code/) | Block dangerous git commands |

### Knowledge & QA

| Skill | Description |
|-------|-------------|
| [qa](qa/) | Single entry point for bug conversations; files lightweight issues and delegates per-issue to `/triage-issue` for deep diagnosis |
| [pre-merge](pre-merge/) | Author-mode: create the PR and run an architectural review before merge. Reviewer-mode (`--pr <n>`): review someone else's PR and draft comment text. Loop-mode (`--loop`, or auto-entered on an AFK `/execute` handoff): records every finding in a durable ledger on the PR with the evidence for or against it, so findings survive the session — makes no commits and no decisions; the operator settles each row |
| [walk-commits](walk-commits/) | Interactive commit-by-commit comprehension walkthrough before merge — intent, riskiest line, deliberate oddities, what's absent by design, per-commit sign-off (optional, recommended by `/pre-merge`; can render per-commit callouts via the shared visual-rendering core) |
| [visual-recap](visual-recap/) | Render a finished diff/PR/branch as a self-contained interactive HTML recap — file-tree + change flags, annotated split diffs with line-anchored callouts, schema/API contract cards, UI wireframes, before/after columns, CSS-first diagrams (Mermaid opt-in), copy-text feedback loop (optional, never auto-invoked, transient artifact) |
| [closeout](closeout/) | Merge the reviewed PR, tear down the worktree, prune the branch, and return to a clean base |
| [compound](compound/) | Capture lessons learned into docs/solutions/ — onto the open PR before `/closeout` merges (default), or post-merge as the fallback |
| [ubiquitous-language](ubiquitous-language/) | DDD glossary with decisions register |

### Orientation & Recovery

| Skill | Description |
|-------|-------------|
| [help](help/) | Read repo state and recommend the next pipeline step |
| [correct-course](correct-course/) | Diagnose stale artifacts and walk the cleanup before backtracking |
| [handoff](handoff/) | Compact the current session into a transient handoff doc when no pipeline artifact fits |

## Repo guide

- **[docs/using-this-pack.md](docs/using-this-pack.md)** — how to operate Skill Kit end-to-end
- **[SYSTEM-OVERVIEW.md](SYSTEM-OVERVIEW.md)** — workflow philosophy, state model, and detailed pipeline rationale
- **[CLAUDE.md](CLAUDE.md)** — editing conventions for agents working on this repository itself
- **[docs/skill-anatomy.md](docs/skill-anatomy.md)** — structure and quality bar for `SKILL.md` files

## License

MIT
