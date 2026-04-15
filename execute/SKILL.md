---
name: execute
description: "Primary pipeline execution step after /prd-to-issues or for clearly scoped implementation work. Use to build, verify, and commit a concrete slice, delegating to /tdd for backend work and behavior-heavy frontend logic when red-green-refactor will reduce risk. Not for shaping or pre-merge review."
---

# Execute

Execute a complete unit of work: plan it, build it, verify the actual outcomes, commit it.

## Invocation Position

This is a primary pipeline skill used after `/prd-to-issues` has produced a concrete slice, or when the user already has a clearly scoped implementation task.

Use `/execute` when the work is ready to build, verify, and commit.

Use HITL `/execute` when the slice still needs active user judgment, supervision, or acceptance decisions during implementation. Use AFK `/execute` only when the next slice is already durable in GitHub, unblocked, and legible from its issue, boundary map, and any linked `research.md` or `docs/solutions/` context.

See **Step 0: Prerequisites** below for the mandatory Ralph auto-detection and TDD marker gates.

Do not use it to replace `/shape`, `/research`, or `/write-a-prd` when the problem or shape is still unresolved. Do not use it as a substitute for `/pre-merge` once implementation is complete and ready for review.

## Workflow

### 0. Prerequisites

**Branch isolation gate.** Before any implementation work, ensure you are working on a clean branch created for this specific task — not a leftover feature branch from previous work.

1. Check the current branch: `git branch --show-current`
2. If the current branch is the base branch (e.g., `main`, `prod`, `master`), create a new feature branch for this task.
3. If the current branch is a **different feature branch** (not the base branch and not a branch named for this task), you are on a stale branch from previous work. Do not commit new work here.

**To create an isolated branch**, use one of these approaches (in order of preference):

- **Worktrunk** (if `wt` is available): `wt switch --create <branch-name>` — creates a new worktree + branch from the base branch and switches to it, giving full filesystem isolation. Use the `/worktrunk` skill for guidance.
- **Plain git**: `git checkout <base-branch> && git checkout -b <branch-name>` — creates a new branch from the base branch in the current working directory.

Derive the branch name from the task: e.g., `issue-5-landing-page`, `landing-page`, or the issue slug. Do not reuse branch names from previous work.

**After creating the worktree, set it up.** A new worktree inherits tracked files but not git-ignored ones (`.env.local`, per-worktree deps, build caches). Two paths:

**Preferred — configure once via worktrunk hooks** (`.config/wt.toml` in the project):

```toml
[pre-start]
copy = "wt step copy-ignored"
install = "pnpm install"
```

`pre-start` hooks are blocking — the worktree is not reported ready until they finish. Use `pre-start` (not `post-start`) for both, because `post-start` runs in the background and subsequent commands that need `.env.local` or `node_modules` will race the hook. See `/worktrunk` for the full recipe. One-time per project.

**Fallback — manual setup for plain `git worktree add`** (no worktrunk):

- `cp <source-repo>/.env.local <worktree>/.env.local` (and any other git-ignored config the project uses).
- Run the project's install command (`pnpm install`, `npm ci`, `pip install -r requirements.txt`, etc.) from the worktree.

**Always — per-session harness reminder:** shell cwd resets to the session's project root after every Bash command. Prefix each Bash call with `cd <worktree-path> && …` or set the command's working directory explicitly. This applies regardless of how the worktree was created.

**Issue-shape detection gate.** If the task is a GitHub issue, verify it is a slice (implementation-ready), not an undecomposed PRD. Run `gh issue view <n> --comments` and check for a comment matching `^Decomposed into: #\d+`.

- If such a comment exists: proceed. The PRD has been decomposed; the operator is presumably working on one of its child slices (and should have supplied that slice's number, not the PRD's).
- If no such comment exists AND the issue body contains shaped-pitch markers (sections named `Appetite`, `Rabbit Holes`, `No-gos`, `User Stories`, or `Implementation Decisions`): halt. This is an undecomposed PRD. Invoke `/prd-to-issues <this-issue-number>` to produce implementation-ready slices, then restart `/execute` against one of the child slice issues.
- If multiple `Decomposed into:` comments exist, read the most recent; `/prd-to-issues` is responsible for ensuring only one is authoritative.

Skip this gate for one-off tasks not tied to a GitHub issue.

**Ralph auto-detection gate.** Evaluate all three conditions:

- [ ] The task comes from a GitHub issue (not a one-off verbal request)
- [ ] The issue has multi-slice scope (PRD, big-batch appetite, or multiple user stories)
- [ ] No `ralph-once.sh` or `ralph.sh` exists in the repo root

If all three are true, invoke `/setup-ralph-loop` now. Do not proceed to Step 1 until Ralph setup is complete or the conditions are not met.

**Pipeline hooks gate.** If `.claude/hooks/enforce-classification.sh` does not exist in this project, invoke `/init-pipeline` now to scaffold enforcement hooks.

**TDD classification gate.** Step 3 requires classifying the work before writing any code. `/tdd` automatically creates `.claude/.tdd-active` via harness preprocessing when loaded (not LLM-dependent); visual frontend creates `.claude/.tdd-skipped`. A PreToolUse hook blocks all `.ts` file writes unless one of these markers exists. Step 6 removes both markers after commit.

**Trivial-task exception.** For single-commit cleanups unrelated to active feature work — typo fixes, dead code removal, comment-only changes, formatting-only changes, dependency version bumps without API surface changes — you may skip classification by creating `.claude/.tdd-skipped` directly. This exception applies only when **all** of the following are true:

- The task is not tied to an open GitHub issue, PRD, slice issue, or QA bug
- The task is not part of an active feature branch created for multi-slice work
- The change is expected to be a single commit (not a sequence of logical units)
- The change does not touch behavior — no new conditionals, no new state, no new exported symbols, no schema or migration changes

If any of these is false, go through the normal classification gate. When in doubt, use the gate — the cost of one extra `/tdd` invocation is lower than the cost of an unverified behavior change slipping through as "trivial."

**Assumptions validation gate.** If the task is a GitHub issue with an "Assumptions from Parent PRD" section, spend 60 seconds checking each listed assumption against current reality before proceeding. For each:

- Is the external service still available at the expected API and pricing tier?
- Does the parent PRD's approach still hold given what you now know?
- Are the packages this slice depends on still at compatible versions?

If all assumptions still hold, proceed to Step 1. If any assumption has changed, stop and flag it to the user — this slice needs a targeted `/research` + mini-PRD cycle before execution, not a patch during implementation. Do not proceed with stale assumptions and attempt to work around them mid-execution.

Skip this gate entirely for one-off tasks without an "Assumptions from Parent PRD" section.

**Consumes verification gate.** Only for issue-based slice work. If the task comes from a GitHub issue created by `/prd-to-issues`, and its `## Boundary Map` / `### Consumes` section references an already-closed upstream slice, spend 60 seconds verifying each listed symbol exists at the declared path in the current tree. This catches upstream boundary-map drift before implementation starts.

For each Consumes entry:

1. If it names a file path — check the file exists.
2. If it names a function, type, or exported symbol — grep for the export.
3. If it names a shape (e.g. "Effect Layer", "Zod schema", "React component", "Context provider") — confirm the *shape* matches, not just the name. A pure helper function does not satisfy a claim of "Effect Layer." A plain object does not satisfy a claim of "Zod schema."

If any Consumes symbol is missing or wrong-shaped, **stop**. The upstream boundary map is stale. Choose one of:

1. **Expand scope in this slice** to fill the gap. Note the expansion in the first commit's message, in the PR description, and file a post-hoc correction comment on the upstream closed issue so future slices don't trust the stale claim.
2. **Backtrack via `/correct-course`** to update the upstream boundary map and reshape the affected slices.
3. **File a new slice** for the missing work and block this one on it.

Do not silently absorb the gap — leave a breadcrumb for the next slice.

Skip this gate for one-off tasks, sibling slices still being planned, or issues without upstream `Consumes` entries.

This gate is scoped to intra-repo symbols (paths, exports, shapes). The mirror check for *externally-resolvable* declarations — package names, public API symbols, and pinned versions against the research snapshot — runs at `/pre-merge` Dimension 4 under "Spec-reality check." Step 0 sees the registry at slice-start; `/pre-merge` sees it at merge time. Both windows are intentional; do not widen this gate to duplicate the review-time check.

### 1. Understand the Task

Read any referenced plan, PRD, or GitHub issue. Explore the codebase to understand the relevant files, patterns, and conventions. If the task is ambiguous, ask the user to clarify scope before proceeding.

If a `research.md` exists in the repo root or `plans/` directory, read it — it contains cached technical research that should inform your approach. Do not re-research what has already been decided.

Consult `docs/solutions/` for relevant past solutions before starting implementation:

```bash
grep -rl "relevant-keyword" docs/solutions/ 2>/dev/null
```

If past solutions exist for this problem domain, incorporate their lessons and avoid their documented pitfalls.

**Artifact precedence:** When `research.md` and `docs/solutions/` give conflicting guidance, follow `research.md` — it was verified against the current installed versions. If the conflict is significant enough that you are uncertain, flag it to the user before proceeding. Load `docs/solutions/` selectively: grep for relevant keywords first, then read only matching files.

### 2. Plan the Implementation (optional)

If the task has not already been planned, create a plan for it. If the GitHub issue includes boundary maps (Produces/Consumes sections), use them to understand the interfaces you need to implement or code against.

### Stack-Specific References

Before implementing, check the project's stack and load relevant best practices.

- **Next.js / React projects**: If `package.json` includes `next` or `react`, load these skills before writing code:
  - `/vercel-react-best-practices` — performance optimization and React Server Component guidance
  - `/vercel-composition-patterns` — component composition patterns that scale without prop sprawl
  - `/next-best-practices` — file conventions, data patterns, metadata, and error handling
  - `/next-cache-components` — cache components, `use cache`, `cacheLife`, and `cacheTag`

### 3. Implement

**STOP — classify before writing any code:**

- [ ] **Backend code** → invoke `/tdd` now (creates `.claude/.tdd-active`)
- [ ] **Behavior-heavy frontend** (reducers, state machines, validation, accessibility, interaction regressions) → invoke `/tdd` now (creates `.claude/.tdd-active`)
- [ ] **Visual/layout/styling/copy frontend** → run: `mkdir -p .claude && touch .claude/.tdd-skipped`

A PreToolUse hook blocks all `.ts` file writes unless one of these markers exists. Do not write implementation code until you have classified the work.

If `/tdd` is not available, follow this minimum discipline:

1. Write a single failing test for the smallest vertical slice of behavior
2. Run the test — confirm it fails (red)
3. Write the minimum code to make it pass (green)
4. Repeat from step 1 for the next slice of behavior
5. Refactor if needed while keeping tests green

Do not write all tests upfront — write one, make it pass, then move to the next.

#### Commit after each logical unit

Do not accumulate all changes into one commit. Commit after each self-contained unit of progress. A logical unit is the smallest change that leaves the codebase in a working state — typecheck passes, tests pass, nothing is half-wired. Examples:

- One red-green-refactor TDD cycle (test + implementation for one behavior)
- A new module, type, or schema with its tests
- A wiring change (route registration, dependency injection, config)
- A refactor that improves structure without changing behavior
- A migration or seed file
- A cross-file type or interface refactor whose intermediate per-file steps would leave typecheck broken — the whole ripple is one logical unit

After completing each logical unit:

1. Run `pnpm run typecheck` and `pnpm run test` (or the project's equivalent). Fix any failures before committing.
2. Stage only the files for that unit — do not stage unrelated changes.
3. Commit with a message that says what this unit accomplished, not "WIP" or "progress".

If a unit touches both a test and its implementation, they belong in the same commit. If a refactor was triggered by the unit but is conceptually separate, commit the refactor separately.

### 4. Verify

**"All steps done" is NOT verification. Check the actual outcomes.**

By this point, each logical unit has already been committed with passing typecheck and tests. Step 4 is the full-slice verification pass — confirming the whole feature works end-to-end, not just that individual units pass.

Run the full feedback loops one final time:

```
pnpm run typecheck
pnpm run test
```

Fix any issues. If fixes are needed, commit them as a separate commit (e.g., "fix integration between X and Y").

Then apply the verification ladder — use the strongest tier you can reach:

#### Tier 1: Static Verification
- Files that should exist actually exist
- Exports are present (not just declared but actually exported)
- Imports between modules are wired correctly (not importing from a path that doesn't resolve)
- Implementation is substantive (not stubs, not console.log placeholders, not TODO comments where real code should be)

**Deletion Completeness (only when the slice body contains a `### Deletes` section).** For each deleted module, enumerate its external consumer surfaces — the symbolic names callers were taught to emit for it to consume, beyond its exports. Typical surfaces:

- DOM data-attributes the module read (`data-*`)
- CSS class names and selectors the module applied or queried
- Global or custom event names (`addEventListener('foo-bar')`, `dispatchEvent(new CustomEvent('foo-bar'))`)
- `window`, `localStorage`, or `sessionStorage` keys
- Route names, config keys, or feature-flag names the module owned

Infer surfaces from the module body as it existed before deletion (git show, or the `Deletes` bullet's accompanying notes). Grep the merged tree for each surface across every source-text file type the project uses — templates, source code, styles, config, docs. Do not restrict to a fixed extension list; the relevant surfaces depend on the stack (`.py`/`.rb`/`.go`/`.rs` for imports, `.vue`/`.svelte`/`.astro`/`.tsx` for templates, `.css`/`.scss`/`.sass`/`.less`/`.styl` for styles, `.yml`/`.toml`/`.json` for config, `.md`/`.mdx` for docs that ship). Zero matches required to pass. Non-zero matches: restore the module, migrate the consumers, or declare them as intentionally inert and track the cleanup as a follow-up slice. Imports alone are the narrowest possible definition of "consumer"; the surface may be wider.

#### Tier 2: Command Verification
- Tests pass (not just "no test failures" — confirm tests actually exist and ran)
- Test wall-clock duration didn't unexpectedly jump. A sudden multi-second increase in a previously fast test, especially after adding retry, sleep, backoff, or interval code, signals a real-time primitive was introduced without being injected. See `/tdd` § Timing-coupled primitives. Fix via injection, not `testTimeout` bumps.
- Build succeeds
- Lint is clean
- Any CLI commands the feature exposes actually work when invoked

#### Tier 2.5: Runtime Startup Verification
**Mandatory when the slice touches schema, migrations, environment config, server initialization, or new routes. Skip only for pure-logic changes to existing modules where nothing about app startup changed.**

- Database is ready: run pending migrations or `db:push` — do not assume the dev database has the latest schema just because tests passed (tests often use in-memory databases that run their own migrations)
- Dev server starts from cold without errors: `pnpm run dev` (or equivalent) boots and responds, not just builds
- The new or changed routes load without 500 errors: `curl -s -o /dev/null -w '%{http_code}' http://localhost:<port>/` returns 200
- Required environment variables are present and valid (check `.env.local` or equivalent)
- No unhandled errors in the server console output during startup

If you cannot start the dev server (e.g., missing external services), note which checks you skipped and why in the Step 5 checklist so the user can verify them.

#### Tier 2.6: Non-Dry Path Sanity Check (CLI + orchestration slices only)

**Mandatory when the slice ships a CLI, scheduled job, cron worker, or orchestration entrypoint that has a dry-run or preview mode.**

Dry-run success does not imply real-run success. A dry-run can short-circuit before storage or side-effects and hide placeholder functions wired into the production path.

For each function wired as a default in the production code path (layer construction, DI container, config object, CLI flag handler), check:

1. Is the function named, documented, or commented as a placeholder, stub, TODO, or follow-up?
2. If yes, is it either (a) guarded by a fail-fast check that throws in non-dry mode, or (b) bound only to the dry-run code path?

If any placeholder is wired as the default for a non-dry path without a fail-fast guard, **flag it now**. Options:

- Add a runtime guard: `if (!process.env.ALLOW_PLACEHOLDER) throw new Error(...)` or equivalent
- Bind the stub only when `dryRun === true` and require a real implementation for the non-dry path
- Gate the slice on the real implementation (larger scope but eliminates the silent-degradation window entirely)

This is a silent-degradation check: if an operator ran this without `--dry-run`, would the output be real, or would placeholder data flow through the production path?

#### Tier 3: Behavioral Verification
- API endpoints return the expected responses (use curl or httpie to verify)
- Browser flows work end-to-end (if applicable and you can verify)
- Data flows correctly from input to storage to output

#### Tier 4: Human Verification
- Ask the user only when you genuinely cannot verify yourself
- Be specific about what you need them to check: "Can you verify that the presence indicator shows your name when you open lesson 3 in a second browser tab?"
- Never use human verification as a substitute for Tiers 1-3

**If verification reveals gaps**, fix them and commit the fix as its own commit. Do not amend a prior commit — the history should show what was built and what was corrected.

#### Bug-Fix Verification (when the task is a fix, not a feature)

If this unit of work is fixing a bug, apply these additional checks before committing:

1. **Classify the fix**: Is this a correction (removes the defect — the code error that caused the problem) or a workaround (suppresses the failure while the defect remains)? If a workaround is the pragmatic choice, note it in the commit message and leave the issue open or create a follow-up for the correction.
2. **Structural sibling search**: Search the codebase for the same pattern that caused the defect. If found in other locations, fix all instances or file issues for them. A defect fixed in one location but present in three others is 75% unfixed.
3. **Two-condition confirmation**: Confirm both that (a) the corrupted state is no longer produced, AND (b) the original failure no longer occurs. If only the failure is suppressed but the underlying state is still wrong, the fix is a workaround, not a correction.

### 5. Manual Verification Checklist

Before handing off to `/pre-merge`, present the user with a verification checklist so they can confirm the work is ready.

**Preparation:** Summarize what was built — list the commits made and key files changed. If the task originated from a GitHub issue with acceptance criteria, pull those criteria into the checklist so the user doesn't have to cross-reference.

Present the checklist:

#### Behavior Review
- [ ] Feature works as expected when manually exercised (browser, terminal, API)
- [ ] Edge cases and error states behave correctly
- [ ] No regressions in adjacent functionality

#### Code Quality
- [ ] Diff reviewed — no debug code, console.logs, or commented-out blocks left behind
- [ ] No TODOs that should be resolved before merge
- [ ] No hardcoded values that should be config or env vars

#### Acceptance Criteria

If the task originated from a GitHub issue or PRD with acceptance criteria, read them and generate a concrete verification step for each one. Each step should tell the user exactly what to do and what to expect — not just restate the criterion.

If the slice issue has a `User Stories Addressed` section referencing the parent PRD, read the parent PRD user stories the slice claims to cover. Derived matrix entries (from `/prd-to-issues` Step 5) surface here as verification targets — each mapped commitment needs a concrete step the user can check. Unmapped commitments from the slice are not in scope for this checklist; they belong to other slices or to the post-merge `/pre-merge` reconciliation.

Example — if the AC says "user can reset their password via email":
- [ ] Go to /login → click "Forgot password" → enter test email → confirm reset email arrives → follow link → set new password → log in with new password

After the generated steps, always include:
- [ ] Scope matches what was asked — no unasked-for additions, no missing pieces

#### Ready for PR Review

- [ ] Ready to create the PR and run architectural review now (flows directly into `/pre-merge`)?

Wait for the user to review and confirm. If they flag items that need fixing, address them, commit the fixes, and re-present the checklist. Only proceed to Step 6 after user confirmation.

**How the "Ready for PR Review" item drives the handoff:** If the user confirms this final item, Step 6 runs cleanup and then automatically invokes `/pre-merge` with the PRD issue number (if the task originated from one). If the user confirms the behavior, code quality, and acceptance criteria items but answers "no" to the PR review item — because they want to batch with more work, are waiting on external input, or plan to sit on the branch — Step 6 runs cleanup and `/execute` exits cleanly. The user invokes `/pre-merge` manually when ready.

### 6. Cleanup and Handoff

All commits should already be done by this point. This step handles post-implementation cleanup and the transition to `/pre-merge`.

Remove the classification markers:

```bash
rm -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-active" "$CLAUDE_PROJECT_DIR/.claude/.tdd-skipped"
```

**Auto-invoke `/pre-merge`.** If Step 5 ran and the user confirmed the "Ready for PR Review" item, invoke `/pre-merge` now. If the task originated from a PRD issue, pass the issue number so `/pre-merge` can gather slice lineage and verify boundary map contracts without asking the user for it again. If the user answered "no" to the PR review item, or Step 5 was skipped entirely (AFK Ralph iterations, trivial-task flows that never reached a user checklist), `/execute` exits here and the user invokes `/pre-merge` manually when ready.

If you cannot complete the task in this context window, leave a comment on the GitHub issue with:

- What was done
- What remains
- Any gotchas or tricky parts for the next iteration
- If the failure was caused by an error (build failure, test failure, unexpected API behavior), include the exact error output — the next iteration benefits from the real error, not a summary

If the error suggests the approach from `research.md` or the PRD is wrong, say so in the comment — this is a signal to backtrack, not to keep retrying the same approach.

**AFK progress and plateau detection.** When running under Ralph, progress is *epistemic state advancement*, not activity. An iteration counts as progress only if at least one of these transitions from unresolved to resolved:

- an unmet acceptance criterion on the active slice
- a failing check (typecheck, test, or verification gate) becoming a passing check
- a named unknown or rabbit hole from `research.md` or the PRD being closed

Code churn without such a transition is a stationary dot. Red flags: the same slice staying active across multiple iterations, tests still failing but "in different ways," recurring error classes with superficial code rewrites, no acceptance checkbox or gate advancing.

**Plateau stop rule.** If two consecutive iterations on the same slice produce stationary dots, stop and leave an issue comment (same shape as the repeated-failure comment above) naming what did *not* advance. Do not start a third iteration. Hysteresis: a single recovering iteration — at least one of the transitions above — resets the stationary counter. This rule complements the existing repeated-failure rule; it is *not* a replacement.

This applies to AFK Ralph iterations only. HITL `/execute` runs are paced by user judgment and do not need the heuristic.

## Handoff

- **Expected input:** a concrete task, issue, or slice with enough scope clarity to implement safely, plus durable upstream artifacts if this is being run AFK
- **Produces:** verified code changes as compartmentalized commits (one per logical unit), and implementation context for the next reviewer or iteration
- **May invoke:** `/tdd` for backend work and behavior-heavy frontend logic, plus stack-specific reference skills when the project stack warrants them
- **Auto-invokes:** `/init-pipeline` when enforcement hooks are missing, `/setup-ralph-loop` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist in the repo, and `/pre-merge` at the end of Step 6 when Step 5 ran and the user confirmed the "Ready for PR Review" checklist item
- **Comes next by default:** `/pre-merge` — auto-invoked after Step 5 user confirmation in HITL mode; user invokes it manually after AFK Ralph iterations or when they answered "no" to the PR review item
