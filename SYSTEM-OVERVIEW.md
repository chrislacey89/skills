# The Hybrid Workflow

This document is the deep rationale for the workflow: why the pipeline is shaped this way, where state lives, how handoffs compress context, and how the system recovers when forward progress breaks. For a quick orientation, read `README.md`. For repository-editing conventions, read `CLAUDE.md`.

## Philosophy

**Cognitive debt is the enemy.** If you can't glance at your project and know where things stand, the system is failing. Every artifact must either live in GitHub (traceable, visible, searchable) or be temporary (deleted after the feature ships). Nothing persists in the filesystem that isn't code, skills, or the compounding knowledge base.

This system cherry-picks the best ideas from three frameworks:

- **Composable skills** — The backbone. GitHub-native planning, composable skill steps, and distinct AFK/HITL execution modes.
- **GSD's structured research** — The rigor. Structured research template, verification ladder, boundary maps, calibrated depth.
- **Compound Engineering's knowledge capture** — The compounding. `docs/solutions/` knowledge base that makes each unit of work easier than the last.

What we explicitly reject:

- GSD's `.gsd/` filesystem (40+ markdown files per milestone that go stale)
- Compound Engineering's 36K-token monolithic plugin (51% context consumed before typing)
- Any system where the developer loses track of where state lives

## The Pipeline

```
/shape → /research (always, depth-calibrated) → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → merge → /compound → cleanup
```

The pipeline order is the default path, not a prison. `Ralph` is the AFK execution mode/persona for the `/execute` stage, not a separate pipeline step. For work that requires multiple independent PRDs — where the shaped outcome decomposes into several features each needing their own research-PRD cycle — `/shape` can branch to `/create-milestone`, which creates a planning milestone plus feature issues that move from `roadmap bet` to `research-ready` to `prd` before re-entering the default path at `/research`. For big-batch work (6 weeks) that fits a single PRD, `/write-a-prd` creates a lightweight container milestone to organize the PRD and its downstream slice issues. If `/research` invalidates assumptions from `/shape`, return to `/shape`. If `/research` invalidates assumptions from a milestone feature, backtrack to `/create-milestone` or `/shape` depending on the blast radius. If `/write-a-prd` reveals the problem was misunderstood, return to `/research`. If `/prd-to-issues` reveals materially more work than the appetite supports, return to `/write-a-prd` and reshape. Backtrack deliberately rather than patching forward with stale assumptions.

### Context Engineering

**Artifact precedence.** When a skill consults multiple artifacts, resolve conflicts using this priority order:

1. Working code in the repository (ground truth)
2. `research.md` (verified against installed versions, most recently produced)
3. `docs/solutions/` (compounded knowledge, possibly stale)
4. Framework reference skills (general best practices)
5. Model training data (least reliable for version-specific details)

When `research.md` and `docs/solutions/` disagree, `research.md` wins because it was produced more recently and verified against installed versions. Flag the conflict to the user rather than silently choosing. Load `docs/solutions/` on demand — grep for relevant keywords first, read only matching files — rather than loading everything upfront.

**Planning-chain compression.** Each pipeline handoff has a compression artifact: the closing summary (`/shape`), `research.md` (`/research`), the PRD issue (`/write-a-prd`). The downstream skill should work from the written artifact, not from the full prior conversation. If a session is running long after multiple planning skills, start the next pipeline step in a fresh session using the written artifact as its entry point.

### Step 1: /shape (Matt's, enhanced)

**What it does:** Interviews you relentlessly about the feature or tranche until every branch of the decision tree is resolved.

**Why it goes first:** You need to know WHAT you're building before you can research HOW to build it. Researching Ably vs Pusher before deciding you need real-time presence is unfocused waste.

**Output:** A shared understanding of the feature or tranche. No file is produced — the understanding lives in your conversation and informs everything that follows.

**Time:** 15-30 min active, 0 min AFK.

**Skill:** Enhanced `/shape`.

When the shaped work requires multiple independent PRDs — where the outcome decomposes into several features each needing their own research-PRD cycle — `/shape` should branch after its closing summary instead of handing off directly to `/research`. The closing summary becomes the input to `/create-milestone`. A blank project or large-scope effort that is one cohesive product stays on the default path; `/write-a-prd` will create a container milestone for big-batch work.

### Step 1.5: /create-milestone (new — only for oversized work)

**What it does:** Turns a tranche-sized outcome into a GitHub milestone plus a small set of sequenced feature issues. Each feature issue starts as a `roadmap bet`, can be promoted to a `research-ready` brief when selected, and later becomes the full PRD issue.

**Why it exists:** `/shape` can clarify an entire application or product area, but `/research` needs a narrower, feature-level question. `/create-milestone` creates that bridge without forcing a giant PRD for the whole tranche.

**Output:** One GitHub milestone, a limited set of feature issues ordered by dependency and architectural risk, and one clearly marked tracer-bullet feature. Selected features are promoted to `research-ready` before entering `/research`.

**Time:** 10-20 min active.

**Skill:** Custom `/create-milestone` skill.

### Step 2: /research (new — always runs, depth-calibrated)

For milestone-planned work, `/research` does not consume a raw `roadmap bet`. It consumes the selected feature issue after that issue has been expanded into a `research-ready` brief containing the problem, user or stakeholder, success signal, why now, appetite, constraints or impositions, assumptions to verify, what the feature proves, and what is out of scope for now.

**This is mandatory, not optional.** You don't know what you don't know. The most expensive research failures happen when you confidently skip research because "middleware is well-understood" — and the API was renamed under you.

**Phase 0 (always runs, 30-60 seconds):** Reads your package.json / lockfile, identifies which dependencies this feature touches, checks for breaking changes between installed versions and latest, flags any stale API patterns. This alone catches the middleware→proxy class of errors.

**Auto-calibration based on Phase 0:**
- **TARGETED (2-5 min):** No version surprises, extending familiar patterns. Output is a 20-line research.md confirming the approach is valid.
- **STANDARD (10-20 min):** One dependency has a version mismatch, or a single technical decision needs evaluation.
- **DEEP (20-30 min):** Significant version mismatches, unfamiliar external services, multiple valid approaches.

**Critical rules:**
- Every API reference must include a direct link to official docs (`[proxy.ts](URL) 🔗`) so the developer can click through and audit.
- Every API reference must be verified against documentation for the **installed** version, not the latest. Never trust training data.
- When the approach depends on behavior that changed between versions, flag it with a `🔄 VERSION CHANGE` callout showing old pattern, new pattern, version that introduced the change, and a link to the migration guide.

**Emoji system for scanning:** Research docs use consistent emoji anchors — 🔒 locked decisions, ✅ verified APIs, ⚠️ warnings, 🔄 version changes, 🚫 don't hand-roll, 🪤 pitfalls, 🔗 doc links, 💡 recommendations, 📦 dependencies.

**Staleness check:** When consulting `docs/solutions/`, `/research` checks the `volatility` field and date. Volatile solutions older than 90 days, or solutions whose Shelf Life condition appears met, are flagged as potentially stale before being incorporated.

**Output:** One `research.md` file in the repo root. Referenced in the PRD. **Deleted after the feature ships.**

**Time:** 2-30 min active depending on calibrated depth.

**Skill:** Custom `/research` skill (new).

### Step 3: /write-a-prd (Matt's, enhanced with Shape Up)

**What it does:** Turns the shape conversation + research findings into a shaped pitch filed as a GitHub issue. Uses Shape Up's shaping discipline: sets appetite (time budget) before solution design, names rabbit holes with pre-decided resolutions, declares explicit no-gos, and classifies user stories as must-haves vs. nice-to-haves (~). Interviews you about modules, interfaces, and test boundaries.

**Enhancement:** Now consults `docs/solutions/` for relevant past solutions and incorporates `research.md` recommendations. Surfaces relevant pitfalls during the interview. Validates the pitch is rough (room for builder judgment), solved (rabbit holes patched), bounded (appetite set, no-gos declared), and complete (omitted activities scan — checks for commonly missed work like error handling, auth changes, migrations, monitoring, and surfaces any that apply as Rabbit Holes) before writing. Includes a conditional Flow Sketch for multi-step UI features. Auto-invokes `/design-an-interface` when a module interface is uncertain. For big-batch appetite (6 weeks), creates a lightweight container milestone and attaches the PRD issue to it — distinct from the planning milestone created by `/create-milestone` for multi-PRD tranches.

**Output:** A GitHub issue containing the pitch (optionally attached to a container milestone for big-batch work) — problem story, appetite, solution, rabbit holes, no-gos, flow sketch (conditional), user stories (must-haves + nice-to-haves), implementation decisions, research reference, lessons from past solutions.

**Time:** 10-15 min active.

**Skill:** Enhanced `/write-a-prd`.

### Step 4: /prd-to-issues (Matt's, enhanced)

**What it does:** Breaks the PRD into independently-grabbable GitHub issues using vertical slices (tracer bullets). Each issue is a thin end-to-end slice, not a horizontal layer.

**Enhancement:** Now includes boundary maps in each issue body — what each slice produces (exported functions, types, endpoints), what it consumes from upstream slices, and the contract notes that matter to downstream work (error shape, compatibility posture, versioning readiness when relevant). This forces interface thinking before implementation and prevents slices from making incompatible assumptions. Runs a scope completeness check per slice (verifying Produces covers error paths, loading states, and Rabbit Hole edge cases — not just the happy path) and an appetite proportionality check (flagging when decomposition is disproportionate to the stated appetite). When the parent PRD belongs to a milestone, all slice issues are attached to the same milestone for progress tracking.

**Output:** GitHub issues with blocking relationships, acceptance criteria, and boundary maps.

**Time:** 5-10 min active.

**Skill:** Enhanced `/prd-to-issues`.

### Step 5: /execute (HITL or AFK via Ralph)

**What it does:** Executes the next concrete slice. In HITL mode, you run `/execute` directly on a specific issue. In AFK mode, Ralph acts as the runner/persona that repeatedly picks the next unblocked issue, invokes `/execute` + `/tdd`, commits, and iterates. Each AFK iteration is a fresh context window that reads the last commits and open issues.

**Default progression:** Start with HITL Ralph, not AFK Ralph. Use HITL to refine the execution prompt, confirm the repo's quality bar is actually encoded in the workflow, and prove that slice boundaries and feedback loops are working. Go AFK only once the runner is reliably choosing the right next slice and producing reviewable commits without needing frequent rescue.

**Risk-first execution:** Ralph should not blindly take the first issue in the list or optimize for easy wins. Prefer the highest-risk unblocked slice that will reveal architectural, contract, or integration truth earliest. The tracer bullet exists to burn down uncertainty first; AFK execution should preserve that behavior rather than smoothing over it.

**Key enhancement to /execute:** GSD's verification ladder. After tests pass, Ralph checks the actual outcomes — files exist, exports are real (not stubs), imports resolve, API endpoints respond, behavioral flows work. "All steps done" is NOT verification. For bug fixes, an additional gate classifies the fix as correction (removes the defect) or workaround (suppresses the failure), searches for structural siblings of the defect pattern, and confirms the corrupted state is no longer produced.

**Key enhancement to /execute:** Now consults `docs/solutions/` and `research.md` before implementation, so past lessons and technical decisions don't need re-discovery each iteration.

**Key enhancement to /execute:** When a project uses Next.js or React, Ralph loads `/vercel-react-best-practices`, `/vercel-composition-patterns`, `/next-best-practices`, and `/next-cache-components` before implementation so framework guidance is present in every iteration.

**Quality must be explicit:** Ralph does not infer whether a repo is a throwaway prototype or a long-lived codebase. The quality bar must be stated in the repo and reinforced in the execution skill: small steps, passing feedback loops, reviewable commits, and no silent downgrade from production standards to demo-code shortcuts just because the loop is running AFK.

**Error forwarding between iterations:** If a Ralph iteration fails (build breaks, tests fail, verification fails), the GitHub issue comment should include the exact error output so the next iteration can diagnose rather than repeat. If two consecutive iterations fail on the same issue with the same error class, Ralph should stop and flag the issue for human review rather than continuing to retry.

**Output:** Commits on the feature branch. GitHub issues closed as completed.

**Time:** 5-15 min active (launching + reviewing), 30-120 min AFK.

**Skills:** Enhanced `/execute` (bug-fix verification gate), enhanced `/tdd` (Khorikov code classification + managed/unmanaged mocking discipline + assertion hardening step), pre-commit hooks via `/setup-pre-commit`.

### Step 6: QA (manual)

**What it does:** You test the feature manually. Feedback creates new GitHub issues. Ralph fixes them in subsequent iterations.

**Output:** New issues for bugs, then fixes committed by Ralph.

**Time:** 10-20 min active.

### Step 7: /pre-merge (new)

**What it does:** Creates a GitHub PR with full lineage (links PRD issue, lists closed/open slice issues) and runs an architectural review of the full diff against project principles. Checks seven dimensions: deep modules, vertical slice integrity, state discipline, boundary map contracts, test quality, docs/solutions/ adherence, and fix completeness (bug-fix PRs only — catches workarounds disguised as corrections, missing regression tests, and lone instance fixes). Findings are advisory — presented in the terminal as Observations, Suggestions, or Concerns. When a PRD with slice issues was provided, also notes scope drift: work that appeared in the diff but wasn't in any slice's Boundary Map, and declared Produces that weren't implemented.

**Output:** A GitHub PR with structured body. Advisory findings in terminal.

**Time:** 5-10 min active.

**Skill:** Custom `/pre-merge` skill.

### Step 8: /compound (new)

**What it does:** After the feature ships, captures what was learned into `docs/solutions/`. Reviews the git log, issue thread, and diff to identify the most important lessons — root causes, prevention strategies, patterns, key decisions. Applies a 4-question pre-filter before capturing: is this novel, will it last, could it live closer to the source, and (for bug fixes) was the process fixed? Reviews the PRD's Rabbit Holes against actual outcomes — ones that bit are high-value compound targets. For bug fixes, classifies the defect origin phase (specification/design/coding error) and splits prevention into code-level (tests, assertions) vs. process-level (pipeline step changes). Flags systemic defect patterns when 3+ solutions share the same root cause. Also checks for scope accuracy lessons and captures patterns so future planning improves. When a milestone's feature issues are all complete, close the GitHub milestone and optionally capture tranche-level lessons if they add reusable knowledge.

**Output:** One file in `docs/solutions/<category>/` with YAML frontmatter including a `volatility` classification (evergreen/stable/volatile) that drives review cadence. Each solution includes a Shelf Life section declaring what change would make it unnecessary.

**Time:** 5-10 min active.

**Skill:** Custom `/compound` skill (enhanced with Living Documentation principles).

### Step 9: Delete research.md

**What it does:** Removes the temporary research file now that the feature has shipped. Stale research is worse than no research.

**Output:** Clean repo.

### Pipeline Recovery

The pipeline described above is the forward path. This section covers what happens when forward progress stops — either a planned backtrack or an unplanned failure.

**When backtracking to an earlier skill:**

- State which skill you are returning to and why.
- If the backtrack invalidates a written artifact: delete it (`research.md`), update in place (PRD issue body), or close with a comment explaining the backtrack (slice issues). Do not leave stale artifacts for downstream skills to consume.
- Scope the re-run to what changed — do not restart the skill from scratch. Example: "We shaped X, but Y was wrong, so we are re-researching Z."
- After the re-run, proceed forward through the pipeline again from that point.

**When a skill cannot complete:**

- Leave a comment on the relevant GitHub issue with: what was done, what remains, and the exact error output (not a summary). The next agent or user benefits from seeing the real error.
- If the error suggests the approach from `research.md` or the PRD is wrong, say so explicitly — this is a signal to backtrack, not to keep retrying the same approach.
- If `/research` reveals that `/shape` assumptions are fundamentally wrong, backtrack to `/shape`.
- If `/pre-merge` reveals architectural concerns serious enough to warrant rework, backtrack to `/execute`.
- Do not silently swallow errors or continue forward when the underlying approach is broken.

---

## Where State Lives

| State | Location | Why |
|-------|----------|-----|
| Feature plans (PRDs) | GitHub issues | Traceable, visible, survives context resets |
| Milestone roadmaps | GitHub milestones + feature issues | Sequence large work without introducing local roadmap files. Two roles: container milestones (from `/write-a-prd` for big-batch single-PRD work) and planning milestones (from `/create-milestone` for multi-PRD tranches) |
| Work items (slices) | GitHub issues with blocking relationships | Native kanban, Ralph reads them |
| QA bugs | GitHub issues | Created during manual QA, closed by Ralph |
| Decisions register | Ubiquitous language doc (decisions section) | Co-located with terminology, single source of truth |
| Technical research | Temporary `research.md` in repo | Claude Code reads it easily; deleted after ship |
| Institutional knowledge | `docs/solutions/` in repo | Compounds over time, consulted during planning |
| Workflow definitions | `.claude/skills/` in repo | Composable, load-on-demand, version-controlled |

### What is NOT in the filesystem

- No `.gsd/` directory
- No `STATE.md`, `ROADMAP.md`, `CONTEXT.md`, `PLAN.md` per slice
- No `progress.txt` as durable task state
- No `docs/brainstorms/`, `docs/plans/`, `docs/specs/`
- No monolithic AGENTS.md consuming 36K tokens

---

## Skill Installation

Everything lives in `.claude/skills/`. No external dependencies. You own all copies.

### Invocation Roles

Use this taxonomy consistently:

- **Primary pipeline skills** — the default feature-delivery path plus the milestone-planning branch for oversized work: `/shape`, `/create-milestone`, `/research`, `/write-a-prd`, `/prd-to-issues`, `/execute`, `/pre-merge`, `/compound`
- **Invoked helper skills** — delegated from another skill when a narrower question needs focused rigor: `/api-design-review`, `/design-an-interface`, `/tdd`
- **Side-route skills** — alternate entry points or supporting paths that reconnect to the main workflow: `/qa`, `/triage-issue`, `/request-refactor-plan`, `/improve-codebase-architecture`, `/ubiquitous-language`
- **Infrastructure skills** — repo setup and safety tooling, not feature-delivery stages: `/init-pipeline`, `/setup-pre-commit`, `/setup-ralph-loop`, `/git-guardrails-claude-code`

### Default Handoff Map

- `/shape` → `/research` for work that fits a single PRD, or `/create-milestone` for work that requires multiple independent PRDs
- `/create-milestone` → selected feature issue promoted from `roadmap bet` to `research-ready`, then `/research`
- `/research` → `/write-a-prd` and conditionally `/api-design-review`
- `/write-a-prd` → `/prd-to-issues` (with optional container milestone for big-batch work) and conditionally `/design-an-interface` or `/api-design-review`
- `/init-pipeline` is auto-invoked by `/execute` Step 0 when `.claude/hooks/enforce-classification.sh` is missing — scaffolds Claude Code hooks (TDD classification gate, git guardrails), pre-commit hooks, and package manager enforcement
- `/setup-ralph-loop` is auto-invoked by `/execute` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist — prepares `ralph-once.sh` and bounded `ralph.sh` for HITL-to-AFK execution
- `/prd-to-issues` → `/execute`, with Ralph optionally running the AFK execution loop for unblocked slices, then QA and `/pre-merge`
- `/execute` → `/pre-merge` after verification, delegating to `/tdd` when backend work benefits from strict red-green-refactor
- `/pre-merge` → merge → `/compound`
- `/qa` and `/triage-issue` feed bug work back into `/execute`
- `/request-refactor-plan` and `/improve-codebase-architecture` produce refactor work that can re-enter at `/execute`

```
.claude/skills/
│
│  ── PRIMARY PIPELINE (direct-entry) ───────────────────────────────────
│
├── shape/SKILL.md               # Requirements discovery (enhanced — workflow stories, hidden-function stability probes)
├── create-milestone/SKILL.md    # GitHub milestone planning for multi-PRD tranche work before feature research
├── research/SKILL.md               # Technical research with version checking (new — GSD-structured)
├── write-a-prd/SKILL.md            # Shaped pitch (enhanced — Shape Up discipline, consults solutions + research, auto-invokes /design-an-interface)
├── prd-to-issues/SKILL.md          # Issue decomposition (enhanced — boundary maps in each issue)
├── execute/SKILL.md                # Execution (enhanced — verification ladder, solutions lookup, React/Next.js references, delegates to /tdd)
├── pre-merge/SKILL.md              # PR creation + architectural review before merge (new)
├── compound/SKILL.md               # Knowledge capture after ship (new — CE-inspired)
│
│  ── INFRASTRUCTURE ────────────────────────────────────────────────────
│
├── init-pipeline/SKILL.md          # Scaffold all enforcement: Claude Code hooks, git guardrails, pre-commit, pnpm (auto-invoked by /execute)
├── setup-pre-commit/SKILL.md       # Lefthook + detected formatter/linter, supports ESLint/Prettier/Biome (enhanced)
├── setup-ralph-loop/SKILL.md       # Generates ralph-once.sh and bounded ralph.sh for HITL-to-AFK /execute execution
├── git-guardrails-claude-code/     # Block dangerous git commands (from Matt, unmodified)
│   ├── SKILL.md
│   └── scripts/block-dangerous-git.sh
│
│  ── INVOKED BY OTHER SKILLS (not called directly) ─────────────────────
│
├── api-design-review/SKILL.md      # Spec-first API contract review for higher-risk API work (invoked by /research and /write-a-prd)
├── design-an-interface/SKILL.md    # Parallel sub-agent interface designs (auto-invoked by /write-a-prd)
├── tdd/                            # Test-driven development delegated primarily from /execute for backend work
│   ├── SKILL.md
│   ├── code-classification.md
│   ├── deep-modules.md
│   ├── interface-design.md
│   ├── mocking.md
│   ├── tests.md
│   └── refactoring.md
│
│  ── SIDE ROUTES AND SUPPORTING PATHS ──────────────────────────────────
│
├── qa/SKILL.md                     # Interactive QA session that files bug issues and feeds fix work back into the pipeline
├── triage-issue/                    # Bug investigation + structural diagnosis + TDD fix plan that produces implementation-ready fix work
│   ├── SKILL.md
│   └── systems-reference.md
├── improve-codebase-architecture/  # Find deepening opportunities and spin them into refactor work
│   ├── SKILL.md
│   └── REFERENCE.md
├── request-refactor-plan/SKILL.md  # Refactor RFC with tiny commits that can re-enter execution through /execute
└── ubiquitous-language/SKILL.md    # Domain glossary support that can sharpen shaping, QA, and refactor conversations
```

### Ralph setup:

`/execute` auto-invokes `/setup-ralph-loop` when it detects multi-slice GitHub-issue work (PRD, big-batch appetite, or multiple user stories) and no `ralph-once.sh` or `ralph.sh` exists in the repo root. The skill generates `ralph-once.sh` for supervised use and bounded `ralph.sh` for AFK use, adapted to the repo's real task source and feedback loops. You can also invoke `/setup-ralph-loop` directly if you want to set up Ralph before reaching `/execute`.

A generated `ralph.sh` should follow Matt's pattern:

```bash
#!/bin/bash
# Ralph — AFK execution loop
# Picks the next unblocked issue, implements one slice, commits, and iterates

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

for ((i=1; i<=$1; i++)); do
  claude --message "Look at the open GitHub issues. Pick the highest-risk unblocked issue that still needs implementation, respecting blocking relationships. Use /execute to implement exactly one reviewable slice. Run the repo's feedback loops. If all issue work is complete, say DONE and stop."
  # ... (rest of the script remains the same)
```

Run in a sandboxed environment (Docker or separate terminal). Each iteration is a fresh context window.

Do **not** introduce a committed `progress.txt` file in this repo. Ralph's durable progress substrate here is GitHub-native state plus commits: PRD issues, slice issues with dependencies, QA issues, issue comments with exact errors, and the commit history itself. That keeps the repo aligned with its "state lives in GitHub, not the filesystem" rule.

### Pre-commit hooks:

`/init-pipeline` handles this automatically — it detects existing tools (formatter, linter, hook manager, package manager), confirms with the user, and invokes `/setup-pre-commit` with the confirmed tools. Defaults to Lefthook + Biome + pnpm if nothing is detected. You can also invoke `/setup-pre-commit` directly if you only want pre-commit hooks without the full pipeline enforcement setup.

---

## Quick Reference

| I want to... | Do this |
|---------------|---------|
| Start a new feature | `/shape` to establish what to build, then hand off to `/research` |
| Plan a blank project or major tranche | `/shape`, then `/create-milestone` if the work requires multiple independent PRDs. If it fits one PRD (even if big-batch), stay on the default path — `/write-a-prd` creates a container milestone |
| Research the technical approach | `/research` (always runs, depth auto-calibrated, invokes `/api-design-review` for higher-risk API contract work, then hands off to `/write-a-prd`) |
| Promote a milestone feature into the pipeline | Expand the selected feature issue from `roadmap bet` to `research-ready`, then run `/research` |
| Write a shaped pitch | `/write-a-prd` → shaped pitch filed as GitHub issue (appetite → solution → rabbit holes → no-gos, includes API contract sketch when relevant, auto-invokes `/design-an-interface` or `/api-design-review` when needed, then hands off to `/prd-to-issues`) |
| Break into work items | `/prd-to-issues` → GitHub issues with boundary maps that feed `/execute`; Ralph can run the AFK loop over unblocked issues |
| Set up pipeline enforcement | `/init-pipeline` — scaffold Claude Code hooks, git guardrails, pre-commit hooks, pnpm enforcement (auto-invoked by `/execute`) |
| Set up Ralph for a repo | `/setup-ralph-loop` — generate `ralph-once.sh` and bounded `ralph.sh` adapted to the repo's task source and feedback loops |
| Execute AFK | Start with HITL Ralph first, then run a bounded Ralph loop over the highest-risk unblocked issues once the prompt and quality bar are proven |
| Execute HITL | Run `/execute` directly on a specific issue, then `/pre-merge` after verification |
| Write tests first | `/tdd` for strict red-green-refactor, usually delegated from `/execute` |
| Run a QA session | `/qa` — report bugs conversationally, agent files GitHub issues that feed fix work back into the pipeline |
| Review and create PR before merge | `/pre-merge` — creates PR with PRD lineage, runs architectural review |
| Investigate a bug | `/triage-issue` — explores codebase, finds root cause, diagnoses structural condition (archetype + leverage), creates TDD fix plan that can flow into `/execute` |
| Plan a refactor | `/request-refactor-plan` — tiny commits RFC as GitHub issue, then implement via `/execute` |
| Find architecture improvements | `/improve-codebase-architecture` — surface deepening opportunities that can become refactor work |
| Capture lessons learned | `/compound` after feature ships or after a high-value bug fix |
| Define domain terms | `/ubiquitous-language` to build or update the glossary + decisions register, then reuse that language in shaping, QA, and issue writing |
| Record a decision | Add a row to the decisions register in ubiquitous language doc |
| Clean up after ship | Delete `research.md`, close the PRD issue |
| Audit knowledge base | Review `docs/solutions/` quarterly |
