# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Use this file when editing Skill Kit itself. For a quick overview of the repository, read `README.md`. For the deeper workflow philosophy and detailed delivery model, read `SYSTEM-OVERVIEW.md`.

## What This Repository Is

Skill Kit is a personal directory of Claude Code skills — composable workflow steps that form a feature development pipeline. Skills are installed globally for Claude Code via `npx skills@latest add chrislacey89/skills --skill '*' --agent claude-code --global -y`.

This repo is not an application — there is no build system, test runner, or deployment target. Each subdirectory contains a `SKILL.md` (with YAML frontmatter for `name` and `description`) and optional reference files.

## The Pipeline

Skills compose into an ordered pipeline for taking a feature from idea to shipped:

```
/shape → /research → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → /compound (in-PR) → /closeout (merge + teardown) → cleanup
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
- `/execute` delegates to `/tdd` for backend code and consults `docs/solutions/` and the research archive entry (from `~/.claude/research/<repo-slug>/…`) before implementation
- `/execute` auto-invokes `/pre-merge` at the end of Step 6 when Step 5's manual verification checklist ran and the user confirmed the "Ready for PR Review" item — this is the default HITL flow. AFK Ralph iterations skip Step 5 (no user to ask) and exit cleanly for the user to invoke `/pre-merge` manually after the batch. Trivial-task flows that took the `.claude/.tdd-skipped` exception also skip Step 5.
- `/init-pipeline` is auto-invoked by `/execute` Step 0 when `.claude/hooks/enforce-classification.sh` is missing — scaffolds Claude Code hooks (TDD classification gate, git guardrails), pre-commit hooks, and package manager enforcement into the target project
- `/setup-ralph-loop` is auto-invoked by `/execute` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist — prepares `ralph-once.sh` and bounded `ralph.sh` for HITL-to-AFK execution
- `/tdd` automatically creates `.claude/.tdd-active` via harness preprocessing when loaded (deterministic, not LLM-dependent); `/execute` Step 6 removes it after commit — a PreToolUse hook blocks `.ts` file writes unless the classification gate was passed
- `/prd-to-issues` produces boundary maps (Produces/Consumes) that `/execute` reads to understand interfaces, plus a `Context` subsection on AFK slices that `/execute` Step 1 is required to read before its `docs/solutions/` grep (the subsection's slots are defined once, in `/prd-to-issues` §4, and pinned to the issue template by `scripts/test-context-block-contract.sh`)
- `/pre-merge` creates the PR with PRD lineage and verifies boundary map contracts from `/prd-to-issues` against actual code
- `/closeout` owns the `merge`/`cleanup` git-hygiene tail after `/pre-merge`: confirm → merge the reviewed PR → re-anchor the shell to the base checkout *before* removing the worktree → prune the merged branch → pull base → verify a clean end state. It is HITL-confirmed (never auto-merges), orchestrates existing tools (`gh pr merge`, `wt remove`/`git worktree remove`, `commit-commands:clean_gone`), introduces no filesystem state, and defers lesson capture to `/compound` and issue-closing + research-artifact hygiene to SYSTEM-OVERVIEW Step 9. When isolation is host-owned (`worktree.provisioning: host`, or a host env var like `CONDUCTOR_WORKSPACE_PATH`/`CODESPACES`), `/closeout` still merges but cedes worktree teardown and branch pruning to the host; symmetrically, `/execute` Step 0 stands down rather than provisioning a worktree the host already created
- `/compound` captures lessons into `docs/solutions/` — by default onto the open PR before `/closeout` merges (so the lesson is reviewed and merged with the code that taught it), or post-merge as the fallback for lessons that surface at/after merge; this is the compounding loop, and it may also capture tranche-level lessons when a milestone closes
- `/compound` and `/pre-merge` may recommend `/improve-pipeline` when the main lesson is about Skill Kit itself rather than the downstream project; `/improve-pipeline` files a GitHub issue in `chrislacey89/skills` and is advisory until the user approves follow-on implementation. Separately, `/compound` Phase 4 may file a proposal stub in `chrislacey89/skills` itself, as the fifth of its permitted mechanisms — available only when the preventing change belongs to the pack rather than to the downstream repo, and not as a substitute for a downstream mechanism that is merely hard to build
- When backtracking to an earlier skill, stale artifacts (research archive entries, PRD issues, slice issues) must be explicitly updated or superseded before proceeding forward — `/correct-course` is the invocable front door for this, and the canonical rules live in SYSTEM-OVERVIEW.md "Pipeline Recovery". Archive entries are superseded by a new dated file, not deleted.
- `/visual-recap` is an optional side-route at the `/pre-merge` → merge boundary (like `/walk-commits`): it renders a finished diff/PR/branch as a transient, self-contained interactive HTML recap so a reviewer who didn't author the change can grasp its shape before reading lines. It is never auto-invoked, skips small/obvious diffs, defaults to a CSS diagram primitive for simple flow/sequence pictures and uses `/mermaid` only for complex graphs that need auto-layout, and produces a transient artifact (gitignored `.context/` or `mktemp`, never committed). Defect-finding stays in `/pre-merge`; free-form diagramming stays in `/excalidraw-diagram`. It shares `docs/visual-rendering-core.md` (rendering vocabulary, copy-text feedback serializer, Grounding Rule, secret-redaction, Tufte quality bar) with `/walk-commits` — bundled into both via `scripts/skill-references.manifest`
- `/re-pitch` is the comprehension-repair side-route: it fires when an explanation did not land, diagnoses whether the reader is missing a term, missing the situation, or was given too much at once, and re-states the same content under a checkable rule set with every domain term glossed on first use. It rewrites an existing answer rather than producing new work, never runs against a wrong answer (correct that instead), writes nothing to disk, and returns control to whatever was in flight. It reads `UBIQUITOUS_LANGUAGE.md` when present and may recommend `/ubiquitous-language` when the same terms keep needing glosses — but never invokes it
- `/tdd`, `/pre-merge`, and `/execute` share `docs/restated-claims.md` — the single statement of the restated-claim-in-unchecked-prose class (what a prose contract and an operative site are, the census move, the limit of the literal-count assertion, and the fallback when interpolation is unavailable). `/tdd` § 4 Refactor points at it for the author-time move; `/pre-merge` Dimension 1 points at it for the review-time detector; `/execute` Step 4 points at it for the scope check on set-claims, the author-path rung that keeps an existential measurement from being written up as a universal claim. None restates it — bundled into all three via `scripts/skill-references.manifest`, and `scripts/test-bundled-pointer-resolution.sh` pins that the pointers resolve
- `/help` is the orientation skill — it reads repo state (branch, PRs, issues, research archive, milestones) and recommends the next pipeline skill with a one-line reason. It is advisory only and never invokes the recommended skill itself.

## Invocation Roles

Use these categories consistently across the repo:

- **Primary pipeline skills** — direct-entry steps in the default delivery path, plus the milestone-planning branch for oversized work: `/shape`, `/create-milestone`, `/research`, `/write-a-prd`, `/prd-to-issues`, `/execute`, `/pre-merge`, `/closeout`, `/compound`
- **Invoked helper skills** — usually not top-level entry points for a feature, but delegated when a narrower decision is unresolved: `/api-design-review`, `/design-an-interface`, `/tdd`, `/triage-issue`
- **Side-route skills** — valid alternate or supporting paths beside the main pipeline: `/qa`, `/request-refactor-plan`, `/improve-codebase-architecture`, `/improve-pipeline`, `/ubiquitous-language`, `/ts-audit`, `/walk-commits`, `/visual-recap`, `/help`, `/correct-course`, `/handoff`, `/re-pitch`
- **Infrastructure skills** — project setup or safety tooling, not normal delivery steps: `/init-pipeline`, `/setup-pre-commit`, `/setup-ralph-loop`, `/git-guardrails-claude-code`

Each skill should make its role obvious.

- **Direct-entry skills** should say when to start with them and whether they are on the default feature path or the milestone-planning branch.
- **Invoked helpers** should say who calls them and when not to call them directly.
- **Side-route skills** should say how they reconnect to the main workflow.
- **Infrastructure skills** should say they are setup tasks, not feature-delivery stages.

### Invocation mechanics — a cost axis orthogonal to role

The roles above say *where a skill sits in the workflow*. They say nothing about *how it is invoked*, which is a separate axis with its own cost:

- **Model-invoked** skills can self-trigger, so their `description` sits in the context window on every turn of every session — in every downstream repo the pack is installed into. The cost is *context load*, paid whether or not the skill ever fires there.
- **User-invoked** skills fire only when a human types `/name` (`disable-model-invocation: true` in Claude Code). The cost is *cognitive load*: zero context, but the human must remember the skill exists.

The two axes are independent — a side-route or an infrastructure skill can be either. Naming the axis gives the vocabulary to ask, per skill, "can this ever usefully self-trigger in a downstream session?" For a side-route that is always typed in practice the answer is plausibly no, and its always-on description is an unpriced cost that grows monotonically as the set grows.

## Handoff Contract

Each pipeline skill should end with a clear transition statement:

- **Expected input** — the artifact, decision, or context it needs
- **What it produces** — the artifact, decision, or verified outcome it leaves behind
- **What comes next** — the default next skill or branch

If a skill can branch, the branch condition should be explicit. Example: `/shape` normally hands off to `/research`, but branches to `/create-milestone` when the work requires multiple independent PRDs. Example: `/write-a-prd` creates a container milestone for big-batch appetite before creating the PRD issue. If a skill advances an issue through maturity states, name them explicitly (`roadmap bet` → `research-ready` → `prd`) so downstream skills do not guess what artifact they are consuming.

At branch-point handoffs (and high-frequency control-yield seams like `/execute` → `/pre-merge`), offer the next step as an `AskUserQuestion` menu rather than leaving the user to retype a command — see `docs/next-step-menu.md` for when this applies and how to shape the options. The menu *renders* the `What comes next` line and *composes with* existing auto-invokes; it does not replace them, and it never appears on linear single-successor handoffs or AFK runs. The same doc carries the threshold above which a fork's options must be *compared* — as a table or panel matrix, cells cited or marked asserted — before the menu takes the choice.

## Conversational Principles

**One question per turn.** When a skill needs to ask the user multiple questions, ask one question at a time and wait for the answer before asking the next. Never present a numbered list of questions, a bulleted set of questions, or multiple questions in a single message. This applies to every phase of every skill — discovery, constraint confirmation, review, and closing. The goal is a genuine back-and-forth conversation, not a form to fill out.

## Architectural Principles

**Deep modules over shallow modules.** Skills like `/tdd`, `/improve-codebase-architecture`, and `/write-a-prd` all reference John Ousterhout's "A Philosophy of Software Design" — small interfaces hiding deep implementations. This shapes how interfaces are designed and refactored.

**Vertical slices, not horizontal layers.** `/tdd` enforces one-test-one-implementation cycles (not "write all tests then all code"). `/prd-to-issues` decomposes into tracer-bullet vertical slices that cut through all layers end-to-end.

**State lives in GitHub, not the filesystem.** PRDs, milestones, work items, and bugs are GitHub issues or GitHub milestones. Milestones serve two procedural roles: container milestones (from `/write-a-prd` for single-PRD big-batch work) and planning milestones (from `/create-milestone` for multi-PRD tranches) — both are the same GitHub object. No `.gsd/` directories, no `STATE.md`, no `PLAN.md` per slice. The only persistent filesystem artifacts are skills themselves and `docs/solutions/`.

**Research lives in a per-user archive, not the repo.** `/research` writes to `~/.claude/research/<repo-slug>/<feature-slug>-<YYYY-MM-DD>.md`, outside the working tree. It is referenced by the PRD and by `/execute` executions including Ralph's AFK loop, and persists after ship — branch switches, worktree cleanup, and `/compound` closeout do not touch it. Stale research still harms agent performance; the file's frontmatter (`date`, `installed_versions_snapshot`) exists so future readers can judge freshness before relying on it.

## Writing Conventions

**American English spelling, repo-wide.** This applies to every file authored in this repo — `SKILL.md` bodies and frontmatter, `README.md`, `SYSTEM-OVERVIEW.md`, `CHANGELOG.md`, `CLAUDE.md`, everything under `docs/` and `site/`, and comments in `scripts/`. It is not a skill-editing rule; it is a repo rule, and treating it as skill-only is how British forms drift into the prose files that skills are generated from.

*behavior* not *behaviour*, *color* not *colour*, *initialize* not *initialise*, *center* not *centre*, *optimize* not *optimise*, *neighbor* not *neighbour*, *canceled* not *cancelled*, *labeled* not *labelled*, *modeling* not *modelling*, *artifact* not *artefact*, *judgment* not *judgement*, *skeptic* not *sceptic*, *analyze* not *analyse*, *gray* not *grey*, *defense* not *defence*, *toward* not *towards*, *while* not *whilst*, *among* not *amongst*.

When forking an upstream skill that uses British spelling, convert it in the same change (this is what the `/mermaid` `SKILL.md` fork did).

Exceptions — leave the original spelling:
- **Words that only look British.** The always-`-ise` verbs (*supervise*, *exercise*, *promise*, *compromise*, *advertise*, *improvise*, *otherwise*) and the words already correct in both dialects (*analysis*, *characteristics*, *mechanism*, *fulfillment*, *forwards* as a verb) are American English as written. Do not "correct" them.
- Proper nouns, book titles, author names, and quoted material
- Identifiers that must match an external contract: package names (`@img/colour`), CSS keywords and API values (`stroke: grey`, `$bgColor="grey"`), config keys
- **Verbatim vendored files.** `mermaid/references/*.md` are autogenerated copies of upstream Mermaid docs, carry a `THIS IS AN AUTOGENERATED FILE. DO NOT EDIT.` header, and are the syntax source of truth for `/mermaid`. Their British spellings (`recognise`, `modelling`, `summarises`, `centred`, `capitalised`, `Popularisation`) are correct as-is — rewriting them breaks fidelity against upstream for no reader benefit.

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
  papers:
    - "Paper Title — Author"      # optional type marker; see docs/skill-anatomy.md
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
- `papers` is an optional type marker, not a third tier — every entry must also appear under `primary` or `secondary`, and `scripts/test-canon-coverage.sh` fails if it does not. Use it only for a work that is a paper rather than a book *and* whose author field carries no citation convention to read (no `et al.`, no trailing `(Venue Year)`); papers cited the normal way are typed without it. It exists because the landing page's canon section is derived from these blocks and renders papers as a different object than books
- Do not put provenance into `description`; keep it optimized for triggering
- Only claim a source if the skill body clearly operationalizes it
- Prefer short source lists over comprehensive ones
- Keep skills self-contained — each should work without requiring the user to read SYSTEM-OVERVIEW.md
- Cross-skill references (like `/execute` delegating to `/tdd`) should use the `/skill-name` convention
- Add a short invocation-position or handoff section when a skill participates in a larger workflow
- If a skill reconnects to the main pipeline, say exactly where it reconnects
- If a skill advances an issue through lifecycle states, define those states and the minimum content required to move between them
- If a skill can run HITL or AFK, say which mode is expected by default and what durable artifacts must exist before AFK execution is safe
- Follow the repo-wide American-spelling rule in § Writing Conventions

**Inventory-sync rule (a router that lies is worse than no router).** Adding, renaming, removing, or re-roling a skill must update every inventory surface *in the same change*, never in a follow-up. The surfaces are:

- the skill tables in `README.md`
- the Handoff Table and the role lists in `SYSTEM-OVERVIEW.md`
- the role lists in this file (`CLAUDE.md` § Invocation Roles)
- the classification ladder in `help/SKILL.md` Step 2 (state-driven rows only — a skill with no repo-state signal, like `/re-pitch`, correctly has no row)
- the `catalog` array in `site/src/lib/data.ts`, which the landing page's collection section renders and both spelled-out skill counts are now derived from

A stale surface routes agents and users to a skill that no longer exists, or under a role it no longer holds — the drift #143 reconciled once by hand. Keeping the surfaces in lockstep with the change that causes the drift makes that reconciliation standing rather than after-the-fact, and puts the inventory knowledge in the world instead of the maintainer's head.

### Commands a skill documents

Skills ship executable prose: a downstream agent copies a fenced block out of a `SKILL.md` and runs it unsupervised in someone else's repo. A wrong command does not fail here — it fails later, quietly, somewhere the author will never see. Two rules govern it, and they apply in this order.

**(a) Reference, don't re-author.** When a skill's prose needs a third-party tool's exit codes, flag behavior, or defaults, link or quote that tool's own documentation instead of paraphrasing it from memory. A paraphrase is a permanent drift liability this repo then owns and has to maintain, and it is usually unforced: #243 records six successive drafts of one passage each shipping a wrong claim about a git subcommand that the triggering issue had never asked anyone to document. Before writing the claim, ask whether the skill needs it at all — the cheapest command claim to keep accurate is the one you did not make.

**(b) Route to the mechanism.** When a skill's prose *does* make a checkable claim about tool behavior, pin it with an executable contract test under `scripts/test-*.sh` and wire it into both `.github/workflows/validate-skills.yml` and `lefthook.yml`. That glob is the inventory — do not restate the list here, it drifts. `test-review-currency-marker.sh` and `test-context-block-contract.sh` are the readable entry points into the shape: a header naming the drift class and the incident behind it, then assertions that extract the real text from the real files rather than restating it. Careful reading is not the mechanism — in #243, every wrong draft was caught by a human or a review sub-agent, and none by a check.

Rule (a) runs before rule (b): the subtraction shrinks the set of claims that need pinning, and pinning a claim that should never have been written is the more expensive order.

## Shared reference files

The `skills` npm CLI installs each skill as a self-contained directory under `~/.claude/skills/<skill>/`. It does **not** copy repo-root files (`SYSTEM-OVERVIEW.md`) or sibling top-level directories (`docs/`). Any skill that needs to read those at runtime must bundle its own copy inside `<skill>/references/`.

When editing a skill:
- If you add a reference to `SYSTEM-OVERVIEW.md` or anything in `docs/` (other than `docs/solutions/`, which is a downstream-project artifact), add a `source  consuming-skill` line to `scripts/skill-references.manifest` and run `bash scripts/sync-skill-references.sh`.
- Point the skill body at the bundled path (`references/<file>.md`), not the repo-root path, so the instruction is valid post-install.
- Canonical content lives at the repo root / in `docs/`. Never edit a `<skill>/references/*.md` copy directly — it will be overwritten by the next sync.
- The `check-skill-references` CI job runs `scripts/sync-skill-references.sh --check` on every PR and fails if a bundled copy has drifted.

## Local dev setup

Install Lefthook (`brew install lefthook` or see <https://github.com/evilmartians/lefthook>) and ShellCheck (`brew install shellcheck`), then run `lefthook install` once per clone. This wires:

- **Pre-commit** — runs `sync-skill-references.sh --check` and `shellcheck` on any staged shell script. Cheap (<1s), catches drift and shell gotchas before CI does.
- **Pre-push** — runs every `scripts/test-*.sh` suite plus `shellcheck` across all scripts. The list is not repeated here; `lefthook.yml` and `.github/workflows/validate-skills.yml` are the two places a new suite must be registered.

Both suites also run in CI (`.github/workflows/validate-skills.yml`), so local hooks are an early-warning layer, not a gate. The repo intentionally has no `package.json` — no JS/TS to tend — so Biome and other Node-ecosystem linters are out of scope until that changes.

### Reading a prose diff

Paragraphs here are single physical lines, routinely past 400 characters — `SYSTEM-OVERVIEW.md:207` is 1,051 and `pre-merge/review-checklist.md` tops out near 2,800. Git's unit is the line, so a paragraph edit renders as the whole paragraph deleted and a near-identical paragraph re-added, with nothing marking where the two diverge, and a large share of what the reviewer re-reads never changed. (#295 quantified that share; the figure is not restated here, because a count over "the last 60 markdown commits" is a sliding window that moves with every commit and nothing checks it. The two line lengths above are fixed and greppable.)

**Use `git diff --word-diff`.** It renders the same change as `[-old-]{+new+}` word-runs instead of two walls of text. It is a display flag on git's own diff ([git-diff docs](https://git-scm.com/docs/git-diff)) and needs no repo configuration. Worth an alias once per machine:

```
git config --global alias.wd 'diff --word-diff'
```

**`.gitattributes` does a different job — do not confuse the two.** `*.md diff=markdown` selects git's built-in `markdown` userdiff driver, which supplies an `xfuncname`: hunk headers become `@@ -4,3 +4,3 @@ ## Pre-merge` rather than a bare line range, so a reviewer can see which section a hunk lands in. It supplies **no** `wordRegex`, and `--word-diff` output is byte-identical with and without it. That negative is easy to get backwards and was gotten backwards in #295's own proposal, so it is pinned by `scripts/test-markdown-diff-attribute.sh` against the installed git rather than trusted here.

## Post-merge install verification

After a change to the manifest or any shared reference file lands on `prod`, run a one-shot install check to confirm the install CLI still delivers what we expect:

```
npx skills@latest add chrislacey89/skills --skill '*' --agent claude-code --global -y
scripts/verify-install.sh ~/.claude/skills
```

`verify-install.sh` exits 0 only if every manifest entry has a corresponding file under `<install-dir>/<skill>/references/`. This step is manual-only — it depends on live GitHub state and a published branch, so it's not part of per-PR CI.
