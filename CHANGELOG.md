# Changelog

## v1.7.0 — Research archive, PRD-shape gate, plateau detection, Coverage Matrix

Seven improve-pipeline issues shipped in one batch after real-world friction from Fulcra and civic-mirror engagements, plus two worktree fixes. The through-line: close feedback loops the pack was missing (forward-failure routing, progress signals, requirement traceability), and move one load-bearing artifact (`research.md`) out of the path of destructive git operations. Every change was scoped via the `/improve-pipeline` advocate/skeptic/mediator workflow before landing; each closed the original GitHub issue.

### Changes

- **`/research` writes to a per-user archive outside the repo (#2)** — output is now `~/.claude/research/<repo-slug>/<feature-slug>-<YYYY-MM-DD>.md` with frontmatter (`date`, `repo`, `feature`, `installed_versions_snapshot`). Worktree- and branch-resilient; cannot be destroyed by ordinary git hygiene. Synchronized removal of the "delete after ship" clause across `SYSTEM-OVERVIEW.md`, `CLAUDE.md`, `/research`, `/write-a-prd`, `/compound`, `/help`, `/correct-course`, `/pre-merge` checklist, and `docs/using-this-pack.md`. Step 9 of the pipeline renamed Cleanup; archive entries persist as durable per-user planning context. Tier 2 (auto-consult the archive during `/research` Phase 0) explicitly deferred.
- **`/execute` PRD-shape detection gate (#4)** — new Step 0 gate halts and routes to `/prd-to-issues` when an issue has shaped-pitch markers (Appetite, Rabbit Holes, User Stories, Implementation Decisions) and no `Decomposed into: #…` comment. `/prd-to-issues` now posts that comment as the detectable signal. `/write-a-prd` appends a `**Next step:** run /prd-to-issues …` footer inside the pitch template so the handoff is visible on the rendered GitHub issue. `SYSTEM-OVERVIEW.md` gains a Forward-failure subsection in Pipeline Recovery.
- **Plateau detection as a second AFK circuit breaker (#5)** — Ralph already stopped on repeated failure; a matching stop rule now trips on repeated non-progress. Two consecutive iterations on the same slice with no unmet acceptance criterion, failing check, or unresolved unknown transitioning to resolved = stationary dot, escalate. One recovering iteration resets the counter (hysteresis). Uses Shape Up's Hill Chart vocabulary (uphill / downhill / stationary dot) and Nygard's Circuit Breaker framing — no new subsystem. Lands in `SYSTEM-OVERVIEW.md`, `/execute`, `/setup-ralph-loop`, and `README.md`.
- **Coverage Matrix as derived view (#6)** — `/prd-to-issues` Step 5 derives a requirement-to-slice coverage view from PRD user stories (Must / Want / ~Tilde), surfaces unmapped Musts as backpressure before slice creation, and reports matrix-generation difficulty as a PRD-quality signal rather than forcing PRD restructuring. `/pre-merge` gains Dimension 5 "Coverage Matrix Reconciliation" as a reconciliation test — block on unmapped Musts, warn on Wants, accept ~Tildes silently. `/execute` verification reads mapped commitments when present. Size-gated: single-slice PRDs skip. Regenerated on demand from GitHub-native state — no stored matrix file. `/write-a-prd` intentionally unchanged (Shape Up PRD roughness).
- **`/execute` worktree post-creation setup (#8)** — new two-tiered block under the `wt switch --create` recommendation. Preferred path configures worktrunk's `[pre-start]` hooks once per project (`copy = "wt step copy-ignored"`, `install = "pnpm install"`). Fallback path documents manual `cp .env.local` + `pnpm install` for plain `git worktree add` users. Always-applies block covers the Claude Code harness's cwd-reset behavior (prefix each Bash call with `cd <worktree>`). Uses `pre-start` (blocking) not `post-start` (background) to avoid the race against subsequent commands that need `.env.local`.
- **`/execute` cross-file type-refactor bullet (#7)** — Step 3 logical-unit examples list gains one entry: "A cross-file type or interface refactor whose intermediate per-file steps would leave typecheck broken — the whole ripple is one logical unit." The rule itself was already correct; the examples list just skewed too small.
- **`/init-pipeline` ↔ `/setup-ralph-loop` boundary closed (#1)** — Step 6 gitignore block now names `/setup-ralph-loop` as the owner of `.claude/.ralph-checked`, with the auto-invocation trigger and manual path. Handoff "Supports downstream" entry reworded so it no longer implies `/init-pipeline` creates the marker. Closes an information-leakage incident surfaced during manual `/init-pipeline` invocation.

### Motivation

Each issue came from real downstream friction during active work (Fulcra Follow-Up Suggestions, civic-mirror OCR fallback, fulcrum_ai worktree setup), and each was triaged through `/improve-pipeline`'s dialectic before landing. Five of the seven fixes share the same structural pattern: the pack was missing a feedback loop that should have existed. Forward-failure routing for PRD-shaped issues (`/execute` → `/prd-to-issues`), progress signals for AFK execution (plateau as a second circuit breaker), requirement traceability alongside interface traceability (Coverage Matrix derived view), and durable storage for research artifacts (archive outside the repo) are all instances of adding missing feedback to prevent recurring breakdowns. The two worktree fixes and the information-leakage fix are smaller-surface closures of the same kind of gap at skill boundaries. The deferred proposal — Local Mode backend + "pipeline" → "skill pack" rename (#3) — remains open until brownfield pressure becomes explicit and sustained; it was not shipped in this batch because its blast radius (~15 files, new shim skill, breaking change for installed users) warrants its own dedicated evaluation.

## v1.6.3 — Improve-pipeline meta-skill + pack-feedback loop

Four changes add a new feedback path for improving the skills pack itself. The through-line is turning real-world friction discovered while using the pipeline in another repo into durable improvements for `chrislacey89/skills`, without overfitting to one incident or mutating the pack before review. This patch introduces a proposal-first meta-skill, anchors it to a fixed GitHub repo, requires canonical pack context before filing issues, and teaches the end-of-loop skills when to recommend it.

### Changes

- **New skill: `/improve-pipeline`** — optional side-route skill for pipeline-pack feedback. It captures pipeline-level lessons from real-world usage, runs an advocate / skeptic / mediator analysis, searches for overlapping issues, and files a GitHub issue in `chrislacey89/skills` instead of writing a local proposal file.
- **Fixed target-repo and context-loading guardrails** — `/improve-pipeline` now always targets `chrislacey89/skills`, never the downstream project's remote. Before filing, it must load canonical pack context from `README.md`, `SYSTEM-OVERVIEW.md`, `CLAUDE.md`, and `docs/skill-anatomy.md`, then review the nearest affected skill plus adjacent overlapping skills.
- **`/compound` and `/pre-merge` recommendation hooks** — both skills now explicitly note that when the main lesson is about the pipeline pack rather than the downstream project, they may recommend `/improve-pipeline` if it is present. The recommendation is advisory only; neither skill invokes it.
- **Repo-level docs updated** — `CLAUDE.md` and `SYSTEM-OVERVIEW.md` now include `/improve-pipeline` in the side-route taxonomy, handoff model, directory tree, and quick-reference guidance so the new skill is discoverable and consistent with the rest of the pack.

### Motivation

The pack already had a strong compounding loop for project knowledge (`docs/solutions/`), but it lacked a matching loop for improving the pack itself. Real-world usage in downstream repositories revealed a recurring meta-problem: sometimes the right lesson is not "how should this app change?" but "how should the pipeline prompt, handoff, checklist, or skill boundary change?" Without a named path for that feedback, those lessons stayed trapped in chat history or got mixed into downstream project docs where they did not belong. This patch gives the pack a deliberate self-improvement path while preserving the pack's existing principles: GitHub-native durable state, explicit handoffs, and review before mutation.

## v1.6.2 — Boundary-map drift checks + non-dry path sanity

Four changes tighten the contract between planning, execution, testing, and review. The through-line is the same failure mode seen from different angles: upstream slice artifacts that drift from reality, dry-run paths that hide production defaults, and tests whose timing behavior quietly degrades after retry or backoff logic is introduced. This patch adds checks at planning time, execution time, review time, and TDD time, then trims the new wording so the guidance stays scoped to issue-based slice work instead of reading like a universal preflight.

### Changes

- **`/execute` new Consumes verification gate** — Step 0 now adds a scoped check for issue-based slice work created by `/prd-to-issues`: when a slice's `## Boundary Map` / `### Consumes` section references an already-closed upstream slice, verify the declared symbols still exist at the declared path and shape before implementation starts. If not, stop and either expand scope explicitly, backtrack via `/correct-course`, or create a new blocker slice.
- **`/prd-to-issues` new Consumes plausibility check** — boundary-map drafting now verifies `Consumes` entries that reference already-closed upstream slices before finalizing the new slice, and requires a post-hoc correction comment on the upstream issue when drift is found.
- **`/pre-merge` review checklist hardening** — Boundary Map Contracts now explicitly checks upstream-produced symbols consumed by the current PR, and Runtime Initialization now covers CLI/orchestration dry-run paths, silent env-var fallbacks, and placeholder production defaults that would silently degrade non-dry execution.
- **`/tdd` timing-coupled primitives guidance** — `/tdd` now calls out `sleep` / `delay` / `retry` / `timeout` / `interval` as injectable policies rather than hardcoded behavior, and `/execute` Tier 2 command verification now tells reviewers to treat sudden test-runtime jumps as a design smell rather than a reason to bump `testTimeout`.

### Motivation

The pack already treated boundary maps as contracts and verification as a first-class stage, but the failure mode where a closed upstream slice claimed outputs it did not actually ship was still under-specified. The same was true for dry-run CLI paths that can mask placeholder defaults and for tests that quietly become wall-clock-coupled after retries or sleeps are introduced. This patch closes those gaps without changing the pipeline shape: the new guidance is strongest where the repo is already opinionated — explicit handoffs, GitHub-native truth, and verification over assumption — and the follow-up cleanup keeps the language narrow enough that normal one-off execution work does not inherit unnecessary ceremony.

## v1.6.1 — /help base-branch detection + parallel tool-use gotcha note

One fix to `/help`'s Phase 1 state gather. The prior version hardcoded `git log main..HEAD || git log master..HEAD` to count commits ahead of base, which exit-128'd in any repo whose default branch is not `main`/`master` (this pack's own repo uses `prod`; others use `develop`, `trunk`, or team-specific names). Because `/help` dispatches its snapshot commands as a parallel tool-use batch in Claude Code, and because Claude Code cancels the in-flight siblings of any bash call that errors, a single bad ref killed the entire snapshot and forced a full retry.

### Changes

- **`/help` Step 1 split into Phase 1a and Phase 1b** — Phase 1a detects the base branch sequentially using `git symbolic-ref refs/remotes/origin/HEAD` with fallback through `main`, `master`, `prod`, `trunk`. Phase 1b dispatches the six read-only snapshot commands in parallel, each referencing the detected `$BASE_BRANCH`. If `origin/HEAD` is unset and no fallback candidate exists, the skill asks the user for the base branch name before continuing.
- **New "parallel tool-use gotcha" note in `/help`** — explicitly documents that one failing bash call in a Claude Code parallel batch cancels its siblings, and that this is why base-branch detection must run first and alone. Discourages the shortcut of chaining `&&`/`||` against a guessed branch inside a parallel batch.

### Motivation

Caught while running `/help` in the Civic Mirror repo (default branch `prod`). The initial state gather exited 128 on `git log main..HEAD`, which cancelled the other six commands in the same parallel batch, and the recovery round had to retry everything with the correct ref. Two compounding problems: (1) the hardcoded branch name was wrong for the repo, and (2) the parallel dispatch amplified one failure into seven. Fix (1) addresses the immediate bug; fix (2) is a durable note so future skill authors know not to trust `&&`-chains inside parallel batches.

## v1.6.0 — BMAD Audit Adopts + /execute Auto-Flow + QA/Triage Restructure

Seven changes: five derived from the audit in `docs/bmad-comparison.md` against [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD), a flow improvement that folds `/pre-merge` invocation into `/execute`'s existing manual verification checklist, and a restructuring of the bug path so `/qa` is the single entry point for bug conversations and delegates per-issue to `/triage-issue` when depth is needed. None of the seven changes the pipeline's core shape. Together they harden review, lower the friction of trivial changes, add the orientation and recovery affordances the pack was missing, remove the manual handoff step when the user is already at the PR-ready moment, and collapse two overlapping bug entry points into one.

### Changes

- **New skill: `/help`** — side-route orientation skill that reads current repo state (branch, open PRs, open issues, `research.md` presence, milestones) and recommends one next pipeline step with a one-line reason and the specific state signals that triggered it. Advisory only — never runs the recommended skill itself. Twelve-rule priority table covers the common pipeline states from "open PR on current branch" down to "clean slate, start with `/shape`."
- **New skill: `/correct-course`** — side-route recovery skill that turns the `SYSTEM-OVERVIEW.md` Pipeline Recovery prose into an invocable workflow. Captures the trigger, diagnoses which upstream skill's output is now untrustworthy, lists every stale artifact (`research.md`, PRD issue, slice issues, open PR, planning milestone), walks the cleanup one decision at a time, and hands off to the earliest affected skill with scoped re-run instructions.
- **`/pre-merge` minimum-findings guard** — Phase 4 now counts findings across all three tiers before presenting. If fewer than 4 surfaced on a non-trivial diff (>50 changed lines or >2 files), the skill does one more focused pass for common miss categories (scope drift, silent assumption changes, shallow modules, happy-path-only tests, new state files). Borrowed from BMAD's `bmad-review-adversarial-general` "at least ten issues" rule and tuned to our context — explicit anti-sycophancy guard that stops the review from closing too early.
- **`/execute` trivial-task exception** — Step 0 TDD classification gate now allows skipping classification via direct `.claude/.tdd-skipped` creation for single-commit cleanups (typo fixes, dead code removal, comment-only changes, formatting-only changes, dependency bumps without API changes). Guarded by four conjunctive conditions: not tied to a GitHub issue, not on an active feature branch, single commit, no behavior change. When any condition fails, use the normal gate.
- **`SYSTEM-OVERVIEW.md` handoff table** — new one-row-per-skill table added before the existing Default Handoff Map bullets. Covers all 23 skills with `Expects | Produces | Next` in ≤15 words per cell. Scannable orientation for readers who do not want to read the narrative bullets. Borrowed from BMAD's `module-help.csv` declarative flow model, adapted to markdown.
- **`/execute` → `/pre-merge` auto-flow** — Step 5's manual verification checklist now has a final "Ready for PR Review" item. When the user confirms it, Step 6 cleanup runs and `/execute` automatically invokes `/pre-merge`, passing the PRD issue number forward so slice lineage and boundary map contracts can be verified without re-asking. When the user answers "no" to the PR review item — batching with more work, waiting on external input, sitting on the branch — Step 6 runs cleanup and `/execute` exits cleanly for manual `/pre-merge` invocation later. AFK Ralph iterations and trivial-task flows that never reached Step 5 keep the prior clean-exit behavior. This is not from the BMAD audit — it came from observing that HITL users already run `/execute` → `/pre-merge` sequentially every time, so folding the transition into Step 5's existing user gate removes a redundant manual step without loosening the consent checkpoint.
- **`/qa` ↔ `/triage-issue` restructure** — `/qa` is now the single entry point for bug conversations and gains a new **Step 3.5 "Decide depth"** gate applied per issue. Lightweight issues (clear repro, obvious cause, uncontroversial fix) continue through the normal filing flow. Issues that fail the depth check — user explicitly asks for diagnosis, regression from working behavior, no confident hypothesis after Step 2 exploration, intermittent repro, or multiple symptoms possibly sharing an upstream cause — delegate to `/triage-issue` for that one bug. The triage issue replaces the lightweight issue `/qa` would otherwise have filed, and control returns to the `/qa` loop for the next observation. `/triage-issue` is recategorized from side-route to invoked helper and should no longer be called as a direct entry point. A single QA session can produce a mix of lightweight `/qa` issues and deep `/triage-issue` issues without the user having to pre-classify the whole batch.

### Documentation updates

- `README.md` — skill count 21 → 23, new "Orientation & Recovery" section with `/help` and `/correct-course`; `/triage-issue` description in the Development table rewritten to reflect per-issue invocation from `/qa`; `/qa` description in the Workflow table rewritten as the single entry point for bug conversations
- `SYSTEM-OVERVIEW.md` — side-route list, handoff map bullets, directory tree, and quick reference table all include the two new skills; new handoff table section above the existing bullets; `/execute` row in the handoff table and the `/execute → /pre-merge` handoff map bullet both note the auto-invocation; `/qa` and `/triage-issue` rows rewritten to describe the per-issue delegation and return-to-loop behavior; `/triage-issue` moved from side-route to invoked-helper list and from the SIDE ROUTES tree section up into the invoked-helper group; quick reference table collapses the prior two bug-path rows into "Run a QA session or report bugs" and "Investigate a specific bug deeply"
- `CLAUDE.md` — side-route list updated; `/correct-course` noted as the invocable front door for Pipeline Recovery; `/help` described as advisory orientation; new `/execute` key-interactions bullet describes the `/pre-merge` auto-invocation and which flows skip it; `/triage-issue` moved from side-route to invoked-helper category in Invocation Roles
- `docs/using-this-pack.md` — side-route list updated with descriptions; new "Start with `/help`" and "Start with `/correct-course`" entry points added; prior "Start with `/qa` or `/triage-issue`" entry rewritten as a single `/qa` entry with an explicit note that bug sessions should not start with `/triage-issue` directly
- `correct-course/SKILL.md` — "What This Skill is NOT" and "Do not use it for" sections updated so the bug-path redirect points at `/qa` only, noting that `/qa`'s per-issue depth check delegates to `/triage-issue` when root cause is needed

### Motivation

The audit against BMAD-METHOD (`docs/bmad-comparison.md`) surfaced twelve dimensions of comparison and cut the adopt list to the five highest-value items:

1. `/help` — BMAD's strongest idea this pack lacked. A router that reads state and tells you the next step makes every other pipeline investment more discoverable.
2. `/correct-course` — the Pipeline Recovery section of `SYSTEM-OVERVIEW.md` already documented backtracking, but it was prose. Turning it into a named skill gives it a front door.
3. Minimum-findings guard — `/pre-merge` was sometimes closing with two or three findings on large diffs because the agent found nothing obvious and stopped. A re-pass threshold hardens this cheaply.
4. Trivial-task exception — the TDD classification gate is load-bearing but creates friction on single-line cleanups. An explicit, guarded opt-out reduces the "pipeline is all-or-nothing" feeling without loosening the gate for real work.
5. Handoff table — BMAD's declarative `module-help.csv` is more scannable than narrative handoff prose for orientation. A markdown table gives most of that benefit without adding a CSV.

The audit also named five things deliberately not adopted (agent personas, filesystem-first state, story-level cadence, separate market/domain/technical research skills, post-hoc test generation) and five distinctive values to defend (mandatory research with Phase 0 version check, GitHub-native state discipline, compounding `docs/solutions/`, TDD classification gate, boundary maps before implementation). Those trade-offs are now durable in `docs/bmad-comparison.md`.

The sixth change — the `/execute` → `/pre-merge` auto-flow — is not from the audit. It came from observing the actual HITL workflow: the user was already running `/execute` followed by `/pre-merge` every time, so the explicit handoff was friction. Three options were considered: (A) auto-invoke with no prompt, (B) a separate Step 7 with its own confirmation, (C) fold the transition into Step 5's existing manual verification checklist as a final item. Option C won because it reuses the existing user-consent checkpoint instead of adding a new one, preserves the "the user decides when the PR happens" property, and naturally skips AFK Ralph and trivial-task flows where Step 5 does not run.

The seventh change — the `/qa` ↔ `/triage-issue` restructure — came from the same observation pattern. The prior model treated `/qa` and `/triage-issue` as two separate direct entry points for bug work, forcing the user to pre-decide whether a bug session was "lightweight intake" or "deep diagnosis" before starting. In practice most QA sessions mix both: three cosmetic bugs that just need filing, one regression that needs root cause, one intermittent failure that needs reproduction. Making the user re-enter a different skill mid-conversation was friction, and more importantly it meant `/triage-issue`'s depth was often skipped for bugs that silently needed it. Per-issue delegation from inside `/qa` lets a single conversation handle the mixed case without renegotiating scope. `/triage-issue` is still a distinct skill with its own rigor — it just stops being the thing the user reaches for directly.

## v1.5.2 — Branch Isolation + Runtime Startup Verification

Two fixes from Civic Mirror issue #5: (1) `/execute` started work on a stale feature branch instead of branching from the base branch, and (2) the verification ladder had no step between "it compiles" and "it behaves correctly" — the app crashed at runtime because database migrations hadn't been applied, but all tests passed using in-memory SQLite.

### Changes

- `/execute` Step 0 adds **Branch isolation gate** — first prerequisite, runs before Ralph/hooks/TDD gates. Checks that the current branch is appropriate for the task (not a stale feature branch from previous work). Prefers `wt switch --create` (worktrunk) for full worktree isolation; falls back to `git checkout -b` from the base branch. References `/worktrunk` skill for guidance.
- `/execute` Step 4 adds **Tier 2.5: Runtime Startup Verification** — between Command Verification (Tier 2) and Behavioral Verification (Tier 3). Mandatory when the slice touches schema, migrations, env config, server initialization, or new routes. Checks: database migrations applied, dev server boots from cold, new routes return 200, env vars present, no console errors at startup.
- `/pre-merge` review checklist adds **Dimension 7: Runtime Initialization** — conditional review dimension (only for schema/config PRs) that catches missing migrations, untested cold boots, in-memory test divergence, and missing environment variables. Review dimension count updated from 7 to 8.
- `/pre-merge` SKILL.md updated: dimension count references (seven → eight), Sub-agent B assignment includes Runtime Initialization, conditional trigger note added for Dimension 7
- `SYSTEM-OVERVIEW.md` updated: verification ladder description mentions runtime startup checks; new key enhancement note for branch isolation gate with worktrunk preference

### Motivation

During Civic Mirror issue #5 (Landing Page), `/execute` was invoked while still on the `finalsite-scraper` branch from issue #4. All landing page commits went onto that stale branch. Separately, all 67 tests passed using in-memory SQLite with auto-migrations, the build succeeded, and typecheck was clean — but the app crashed at runtime with "no such table: governing_bodies" because `db:push` had never been run against the real `dev.db`.

## v1.5.1 — Manual Verification Checklist in /execute

Adds a new Step 5 to `/execute` — a manual verification checklist presented to the user before handing off to `/pre-merge`. Covers behavior review, code quality, and acceptance criteria confirmation so the user has a structured gate to catch issues automated checks miss.

### Changes

- `/execute` new Step 5: **Manual Verification Checklist** — summarizes commits and key files, presents checklist covering behavior, code quality, and acceptance criteria, waits for user confirmation before proceeding
- `/execute` Step 5 Acceptance Criteria: generates concrete walkthrough-style verification steps derived from the GitHub issue/PRD AC rather than generic checkboxes
- `/execute` Step 5 (Cleanup) renumbered to Step 6
- Cross-references updated: `execute/SKILL.md` Step 0, `CLAUDE.md`, `tdd/SKILL.md` all point to Step 6 for TDD marker cleanup

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
