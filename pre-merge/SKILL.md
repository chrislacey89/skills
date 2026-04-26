---
name: pre-merge
description: "Primary pipeline review step after verified implementation. Use to create a PR with lineage and run architectural review before merge. Not for QA intake, planning, or implementation work."
sources:
  secondary:
    - "The Checklist Manifesto — Atul Gawande"
---

# Pre-Merge

Create a GitHub PR linking back to the PRD and slice issues, then review the full diff against the project's architectural principles. Produces advisory findings — does not block merge, auto-fix code, or file issues.

## Invocation Position

This is a primary pipeline skill used after implementation has been verified and before merging to main.

Use `/pre-merge` when the branch is ready for PR creation, architectural review, and final plan-to-code reconciliation.

Do not use it as a substitute for implementation verification, QA intake, or refactor planning. It assumes the work is already built and ready to review.

## When to Use

- After QA passes and before merging a feature branch to main
- After Ralph finishes AFK execution and you've verified behavior
- For any branch you want reviewed before merge, even without a full pipeline run

## Execution Flow

### Phase 1: Gather Context

1. **Ask for the PRD issue number.** Accept "none" if this change didn't go through the full pipeline.

2. **If a PRD was given:**
   ```bash
   gh issue view <number>
   gh issue list --search "in:body #<prd-number>" --state all --json number,title,state,body --limit 100
   ```
   Parse boundary maps (Produces/Consumes sections) from each slice issue body.

3. **Detect the base branch and assess the diff:**
   ```bash
   BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')
   if [ -z "$BASE_BRANCH" ]; then
     for candidate in main master prod develop trunk; do
       if git rev-parse --verify "$candidate" >/dev/null 2>&1; then BASE_BRANCH=$candidate; break; fi
     done
   fi
   git diff "$BASE_BRANCH...HEAD" --stat
   git log --oneline "$BASE_BRANCH..HEAD"
   ```
   For a stacked-PR slice, override `$BASE_BRANCH` with the sibling slice's branch name (the upstream the PR will target). If no diff from the base, tell the user there's nothing to review and stop. Do not hardcode `main` — Skill Kit's own repo uses `prod`, and many others use `develop`, `trunk`, or a team-specific name.

### Phase 2: Create the PR

1. **Check for an existing PR:**
   ```bash
   gh pr list --head $(git branch --show-current) --json number,url
   ```

2. **Create or update the PR.** Use `gh pr create --base "$BASE_BRANCH"` (override `--base` for stacked-PR slices to the sibling slice's branch) or `gh pr edit`.

**PR body template (when PRD exists):**

```markdown
## Summary

[For trivial PRs — typo fixes, dep bumps, formatting-only, single-line reverts — 1–2 sentences derived from the PRD's Problem and Solution sections.

For non-trivial PRs — behavior changes, new surface area, bug fixes with non-obvious root causes, refactors crossing module boundaries — write a plain-language walkthrough: one paragraph of domain setup, what changed and why each piece was the right move, and why it matters. Aim for a reader who doesn't have the codebase in their head. See `references/writing-for-humans.md` for the shape and revision bar.]

## PRD

Closes #<prd-issue-number>

## Slices

- [x] #N — Title (for closed slices)
- [ ] #N — Title (for still-open slices)

## Key Decisions

[Bullet list of notable implementation decisions that refined or diverged from the PRD. Derived from commit messages and slice issue comments. Omit this section if nothing diverged.]
```

**PR body template (no PRD):**

```markdown
## Summary

[For trivial PRs — typo fixes, dep bumps, formatting-only, single-line reverts — 1–2 sentences derived from the diff and commit messages.

For non-trivial PRs, write a plain-language walkthrough: one paragraph of domain setup, what changed and why each piece was the right move, and why it matters. See `references/writing-for-humans.md`.]
```

3. Print the PR URL.

### Phase 3: Architectural Review

Consult `review-checklist.md` for the review dimensions and their violation patterns.

**Small diff** (< 200 changed lines, < 10 files): run all dimensions sequentially in the main agent.

**Larger diff**: spawn two sub-agents in parallel:
- **Sub-agent A (structural & scope):** Deep Modules, Vertical Slice Integrity, State Discipline, Surgical Scope
- **Sub-agent B (contracts & quality):** Boundary Map Contracts, Test Quality, docs/solutions/ Adherence, Runtime Initialization, Fix Completeness

Each sub-agent reads the full diff and its assigned dimensions from `review-checklist.md`, then returns findings in the three-tier severity format.

**Dimension 4 (Boundary Map Contracts) only runs if a PRD with slice issues was provided.** Without boundary maps, there are no contracts to verify.

**Dimension 7 (Runtime Initialization) only runs if the diff includes schema files, migration files, environment config, or server startup code.** Without infrastructure changes, there is nothing to verify.

**Surgical Scope runs on every diff.** Where Dimensions 4 and 5 check plan-vs-actual between slices (PRD-gated), Surgical Scope checks scope drift inside a single diff — drive-by reformatting, speculative additions, adjacent fixes — and applies whether or not the work went through `/prd-to-issues`. Findings under this dimension must cite the file path and hunk start line; "looks scope-creepy" is not a finding.

**Dimension 6 (docs/solutions/ Adherence):** Search `docs/solutions/` for files whose `components` or `technologies` frontmatter overlaps with the changed code areas. If relevant solutions exist, check whether the implementation follows or consciously diverges from documented patterns.

**TypeScript projects:** For branches with significant `.ts` or `.tsx` changes, mention that `/ts-audit` can be run on the changed files for type-safety analysis that complements the architectural review. Do not invoke it automatically — note it as an option. Example: "For deeper TypeScript analysis, consider running `/ts-audit` on the changed files."

**Verify, don't suspect — library callback semantics.** When a finding turns on how a library treats a value the application hands it (return from a callback, object passed to a hook, systemMessages/tools/middleware collection semantics), the sub-agent must cite the installed type definition — `node_modules/<library>/**/*.d.ts` file path and line — in the finding. If a research archive entry exists for this feature, prefer its `callback_contracts_snapshot` (see `research/SKILL.md` Phase 1.25). Hedged language ("if the library replaces X rather than merges", "if this field is accepted") without a source citation is not acceptable for this class of finding — the proof is one grep away and the failure mode is runtime-invisible. Either cite the source and classify as Observation/Suggestion/Concern per the severity rules, or downgrade to a named follow-up with an explicit "verify before merge" action.

### Phase 4: Present Findings

Combine findings from all dimensions (or sub-agents).

**Minimum-findings guard.** Before presenting, count the total findings across all three tiers. If the total is fewer than 4 on a diff of any meaningful size (more than ~50 changed lines or more than 2 files), do one more focused pass explicitly looking for what you might be missing — scope drift, silent assumption changes, shallow modules, tests that only cover the happy path, or new state files that slipped past dimension 3. A count of zero or one on a non-trivial diff is a signal that the review stopped too early, not that the code is flawless. If after the second pass the count is still low, present what you have — do not fabricate findings to hit a quota.

Present in the terminal using three tiers:

```
## Architectural Review

### Observations (for awareness — no action needed)

[Patterns noticed that aren't violations. Example: "The presence module
exports 6 functions — reasonable, but worth watching if it grows."]

### Suggestions (action optional — would improve quality)

[Grouped by dimension. Things that aren't violations but would make
the code better.]

### Concerns (action recommended — potential principle violation)

[Grouped by dimension. Each concern cites the principle, shows the
specific code, and explains why it matters.]

---
No action is required. These are advisory.
When ready, merge the PR at <PR-URL>.
```

**Scope Notes (only when a PRD with slice issues was provided):**

After the three-tier findings, note any significant scope drift between the planned decomposition and the actual diff:

- Work that appears in the diff but wasn't in any slice's Boundary Map (omitted scope discovered during implementation)
- Declared Produces that don't appear in the diff (planned work that was cut or deferred)
- Slices where the actual diff footprint was dramatically different from the boundary map's declared scope

These are factual notes, not review findings. They don't produce Observations, Suggestions, or Concerns — they record plan-vs-actual divergence so the user and `/compound` can decide whether a pattern is worth capturing. Omit this section entirely if the diff aligns closely with the planned boundary maps.

If the review reveals that the main lesson is about Skill Kit itself — for example unclear stage boundaries, missing handoff guidance, or a review checklist gap in `chrislacey89/skills` rather than a problem in the downstream codebase — note: "Consider running `/improve-pipeline` if that skill is present." Do not invoke it.

If a concern warrants deeper work, note: "Consider running `/request-refactor-plan` for this area." Do not invoke it.

If a finding looks like a behavioral bug, note: "Consider running `/qa` to verify." Do not file an issue.

Omit any tier that has zero findings.

## What This Skill is NOT

- **Not a test runner.** Pre-commit hooks run tests, typecheck, and lint on every commit.
- **Not a bug finder.** `/qa` files behavioral bugs as GitHub issues.
- **Not a refactoring planner.** `/request-refactor-plan` produces RFC-style refactor proposals.
- **Not a CI gate.** Findings are advisory. The user decides what to address before merging.

## Handoff

- **Expected input:** verified implementation work that is ready for review and PR creation
- **Produces:** a PR with lineage plus an architectural review readout
- **May redirect:** to `/qa` when a finding looks behavioral, or to `/request-refactor-plan` when deeper structural cleanup is warranted
- **Comes next by default:** merge, then `/compound`
