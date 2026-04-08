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

**Ralph auto-detection gate.** Evaluate all three conditions:

- [ ] The task comes from a GitHub issue (not a one-off verbal request)
- [ ] The issue has multi-slice scope (PRD, big-batch appetite, or multiple user stories)
- [ ] No `ralph-once.sh` or `ralph.sh` exists in the repo root

If all three are true, invoke `/setup-ralph-loop` now. Do not proceed to Step 1 until Ralph setup is complete or the conditions are not met.

**Pipeline hooks gate.** If `.claude/hooks/enforce-classification.sh` does not exist in this project, invoke `/init-pipeline` now to scaffold enforcement hooks.

**TDD classification gate.** Step 3 requires classifying the work before writing any code. `/tdd` automatically creates `.claude/.tdd-active` via harness preprocessing when loaded (not LLM-dependent); visual frontend creates `.claude/.tdd-skipped`. A PreToolUse hook blocks all `.ts` file writes unless one of these markers exists. Step 5 removes both markers after commit.

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

### 4. Verify

**"All steps done" is NOT verification. Check the actual outcomes.**

Run the feedback loops first:

```
pnpm run typecheck
pnpm run test
```

Fix any issues. Repeat until both pass cleanly.

Then apply the verification ladder — use the strongest tier you can reach:

#### Tier 1: Static Verification
- Files that should exist actually exist
- Exports are present (not just declared but actually exported)
- Imports between modules are wired correctly (not importing from a path that doesn't resolve)
- Implementation is substantive (not stubs, not console.log placeholders, not TODO comments where real code should be)

#### Tier 2: Command Verification
- Tests pass (not just "no test failures" — confirm tests actually exist and ran)
- Build succeeds
- Lint is clean
- Any CLI commands the feature exposes actually work when invoked

#### Tier 3: Behavioral Verification
- API endpoints return the expected responses (use curl or httpie to verify)
- Browser flows work end-to-end (if applicable and you can verify)
- Data flows correctly from input to storage to output

#### Tier 4: Human Verification
- Ask the user only when you genuinely cannot verify yourself
- Be specific about what you need them to check: "Can you verify that the presence indicator shows your name when you open lesson 3 in a second browser tab?"
- Never use human verification as a substitute for Tiers 1-3

**If verification reveals gaps**, fix them before committing. Do not commit code that fails verification and leave a "TODO: fix this" comment.

#### Bug-Fix Verification (when the task is a fix, not a feature)

If this unit of work is fixing a bug, apply these additional checks before committing:

1. **Classify the fix**: Is this a correction (removes the defect — the code error that caused the problem) or a workaround (suppresses the failure while the defect remains)? If a workaround is the pragmatic choice, note it in the commit message and leave the issue open or create a follow-up for the correction.
2. **Structural sibling search**: Search the codebase for the same pattern that caused the defect. If found in other locations, fix all instances or file issues for them. A defect fixed in one location but present in three others is 75% unfixed.
3. **Two-condition confirmation**: Confirm both that (a) the corrupted state is no longer produced, AND (b) the original failure no longer occurs. If only the failure is suppressed but the underlying state is still wrong, the fix is a workaround, not a correction.

### 5. Commit

Once typecheck, tests, and verification pass, commit the work. Write a commit message that includes:

- What was built (the feature or fix, not "implemented changes")
- Key decisions made during implementation (if any)
- Files changed (summary, not exhaustive list)

**Cleanup:** After a successful commit, remove the classification markers:

```bash
rm -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-active" "$CLAUDE_PROJECT_DIR/.claude/.tdd-skipped"
```

If you cannot complete the task in this context window, leave a comment on the GitHub issue with:

- What was done
- What remains
- Any gotchas or tricky parts for the next iteration
- If the failure was caused by an error (build failure, test failure, unexpected API behavior), include the exact error output — the next iteration benefits from the real error, not a summary

If the error suggests the approach from `research.md` or the PRD is wrong, say so in the comment — this is a signal to backtrack, not to keep retrying the same approach.

## Handoff

- **Expected input:** a concrete task, issue, or slice with enough scope clarity to implement safely, plus durable upstream artifacts if this is being run AFK
- **Produces:** verified code changes, commit-ready work, and implementation context for the next reviewer or iteration
- **May invoke:** `/tdd` for backend work and behavior-heavy frontend logic, plus stack-specific reference skills when the project stack warrants them
- **Auto-invokes:** `/init-pipeline` when enforcement hooks are missing, `/setup-ralph-loop` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist in the repo
- **Comes next by default:** `/pre-merge`
