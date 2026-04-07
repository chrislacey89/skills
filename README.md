# Skills

[![License: MIT](https://img.shields.io/github/license/chrislacey89/skills)](LICENSE)
![Skills](https://img.shields.io/badge/skills-19-blue)
![CLI](https://img.shields.io/badge/npx%20skills-compatible-green)

A pipeline-first Claude Code skills pack for structured feature delivery. 19 composable skills that take a feature from idea to shipped — with explicit handoffs, verified research, and a compounding knowledge loop.

Built around structured research, GitHub-native state, and a compounding knowledge loop in `docs/solutions/`. Compatible with Claude Code, Cursor, Windsurf, and any agent that can consume SKILL.md files.

## Installation

Install individual skills:

```bash
npx skills@latest add chrislacey89/skills/shape
npx skills@latest add chrislacey89/skills/research
npx skills@latest add chrislacey89/skills/execute
```

Or install the full pack:

```bash
npx skills@latest add chrislacey89/skills --all
```

## Keeping skills updated

The skills CLI tracks content hashes. When this repo updates, your installed copies know about it:

```bash
npx skills@latest check    # see what changed upstream
npx skills@latest update   # pull latest versions
```

## What this pack optimizes for

- **GitHub-native state** — PRDs, slices, QA bugs, and lineage live in GitHub issues and PRs, not a sprawling local planning filesystem.
- **Explicit handoffs** — skills declare what they expect, what they produce, and what comes next.
- **Verified research before PRD writing** — `/research` is a first-class step, not an optional extra.
- **Compounded knowledge** — shipped lessons feed future work through `docs/solutions/`.

## Canonical pipeline

```
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → merge → /compound → cleanup
```

The pipeline is the default path, not a prison. Skills can backtrack when assumptions fail or branch to helper and side-route skills when the work demands it. For blank-project or major-tranche work that is too large for a single PRD, `/shape` can branch to `/create-milestone`, which creates a GitHub milestone plus feature issues that mature from `roadmap bet` to `research-ready` to `prd` before re-entering the normal pipeline at `/research`. `Ralph` is the AFK execution mode/persona for the `/execute` stage, not a separate pipeline step.

## Skills

### Planning & Design

| Skill | Description | Install |
|-------|-------------|---------|
| [shape](shape/) | Structured requirements discovery — shared understanding before research | `npx skills@latest add chrislacey89/skills/shape` |
| [create-milestone](create-milestone/) | Turn a shaped app-sized or tranche-sized idea into a GitHub milestone with sequenced feature bets | `npx skills@latest add chrislacey89/skills/create-milestone` |
| [research](research/) | Mandatory pre-PRD research with auto-calibrated depth | `npx skills@latest add chrislacey89/skills/research` |
| [write-a-prd](write-a-prd/) | PRD creation via interview, filed as GitHub issue | `npx skills@latest add chrislacey89/skills/write-a-prd` |
| [prd-to-issues](prd-to-issues/) | Break PRD into vertical slices with boundary maps | `npx skills@latest add chrislacey89/skills/prd-to-issues` |
| [design-an-interface](design-an-interface/) | Generate multiple radically different interface designs | `npx skills@latest add chrislacey89/skills/design-an-interface` |
| [api-design-review](api-design-review/) | Focused contract review for higher-risk API design decisions | `npx skills@latest add chrislacey89/skills/api-design-review` |

### Development

| Skill | Description | Install |
|-------|-------------|---------|
| [execute](execute/) | Execute a unit of work end-to-end with verification | `npx skills@latest add chrislacey89/skills/execute` |
| [tdd](tdd/) | Test-driven development with red-green-refactor loop | `npx skills@latest add chrislacey89/skills/tdd` |
| [triage-issue](triage-issue/) | Investigate bugs, find root cause, create TDD fix plan | `npx skills@latest add chrislacey89/skills/triage-issue` |
| [improve-codebase-architecture](improve-codebase-architecture/) | Surface deepening opportunities for shallow modules | `npx skills@latest add chrislacey89/skills/improve-codebase-architecture` |
| [request-refactor-plan](request-refactor-plan/) | Plan refactors with tiny commits | `npx skills@latest add chrislacey89/skills/request-refactor-plan` |

### Tooling & Setup

| Skill | Description | Install |
|-------|-------------|---------|
| [setup-pre-commit](setup-pre-commit/) | Lefthook + Biome pre-commit hooks | `npx skills@latest add chrislacey89/skills/setup-pre-commit` |
| [git-guardrails-claude-code](git-guardrails-claude-code/) | Block dangerous git commands | `npx skills@latest add chrislacey89/skills/git-guardrails-claude-code` |

### Knowledge & QA

| Skill | Description | Install |
|-------|-------------|---------|
| [qa](qa/) | Interactive QA session, files GitHub issues | `npx skills@latest add chrislacey89/skills/qa` |
| [pre-merge](pre-merge/) | Create the PR and run an architectural review before merge | `npx skills@latest add chrislacey89/skills/pre-merge` |
| [compound](compound/) | Capture lessons learned into docs/solutions/ | `npx skills@latest add chrislacey89/skills/compound` |
| [ubiquitous-language](ubiquitous-language/) | DDD glossary with decisions register | `npx skills@latest add chrislacey89/skills/ubiquitous-language` |

## Repo guide

- **[docs/using-this-pack.md](docs/using-this-pack.md)** — how to operate the pack end-to-end
- **[SYSTEM-OVERVIEW.md](SYSTEM-OVERVIEW.md)** — workflow philosophy, state model, and detailed pipeline rationale
- **[CLAUDE.md](CLAUDE.md)** — editing conventions for agents working on this repository itself
- **[docs/skill-anatomy.md](docs/skill-anatomy.md)** — structure and quality bar for `SKILL.md` files

## License

MIT
