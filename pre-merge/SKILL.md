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

This is a primary pipeline skill used after implementation has been verified and before merging to main, *or* when picking up someone else's PR for review.

Use `/pre-merge` when the branch is ready for PR creation, architectural review, and final plan-to-code reconciliation. Use `/pre-merge --pr <number>` when you are reviewing a PR you did not author.

Do not use it as a substitute for implementation verification, QA intake, or refactor planning. It assumes the work is already built and ready to review.

## Modes

`/pre-merge` runs in one of two modes. Both reuse Phase 3's 11 architectural review dimensions (`review-checklist.md`); they differ in what they consume and what they produce.

- **Author-mode (default)** — invoked on your own branch with no `--pr` argument. The skill creates the PR (Phase 2) and prints findings to the terminal as advisories (Phase 4). This is the mode auto-invoked by `/execute` Step 6.
- **Reviewer-mode** — invoked as `/pre-merge --pr <number>` against a PR you did not author. The skill skips PR creation (the PR already exists) and produces *draft comment text* (Phase 4) for you to review and post, structured per `references/comment-craft.md` (5P gate, Triple-R, Comment Signals, MMG Exchange).

If you are running on a branch other than the user's working branch and `--pr` was not provided, ask once whether the user means reviewer-mode against a specific PR number rather than guessing — auto-detection saves a keystroke but misclassifying mode produces draft comments that would have been local advisories or vice versa.

## When to Use

- **Author-mode:** after QA passes and before merging a feature branch to main; after Ralph finishes AFK execution and you've verified behavior; or for any branch you want reviewed before merge, even without a full pipeline run.
- **Reviewer-mode:** when a teammate or external contributor opens a PR and you want to apply the 10-dimension architectural review to their diff and produce constructive comment text.

## Execution Flow

### Phase 1: Gather Context

**Author-mode:**

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

**Reviewer-mode (`--pr <number>`):**

1. **Fetch the PR and its diff:**
   ```bash
   gh pr view <pr-number> --json number,title,headRefName,baseRefName,body,author,url,state
   gh pr diff <pr-number>
   ```
   If the PR is already merged or closed, tell the user and stop — review comments on a closed PR are surfaced separately and rarely useful.

2. **Identify the PRD issue from the PR body.** Look for `Closes #<n>`, `Refs #<n>`, or a `## PRD` section pointing at an issue. If found, run the same `gh issue view` + slice-issue search as author-mode step 2 to load PRD context and boundary maps. If the PR has no PRD lineage, treat it as the "no PRD" branch — Phase 3's PRD-gated dimensions (Boundary Map Contracts, Coverage Matrix Reconciliation) skip themselves.

3. **Note the diff size and base branch from the PR JSON.** No local branch math — `gh pr diff` returns the merged-base-to-head diff directly. Do not try to check the PR out locally; you are reviewing the diff, not running it.

### Phase 2: Create the PR

**Skip this phase entirely in reviewer-mode** — the PR already exists, you did not author it, and rewriting someone else's PR body is out of scope. Proceed to Phase 3.

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

Consult `review-checklist.md` for the review dimensions and their violation patterns. The 11 dimensions run identically in both modes — the `diff` they read is the local `git diff "$BASE_BRANCH...HEAD"` in author-mode and the `gh pr diff <pr-number>` output in reviewer-mode.

**Small diff** (< 200 changed lines, < 10 files): run all dimensions sequentially in the main agent.

**Larger diff**: spawn two sub-agents in parallel:
- **Sub-agent A (structural & scope):** Deep Modules, Vertical Slice Integrity, State Discipline, Surgical Scope, Review-friendly Size
- **Sub-agent B (contracts & quality):** Boundary Map Contracts, Test Quality, docs/solutions/ Adherence, Runtime Initialization, Fix Completeness

Each sub-agent reads the full diff and its assigned dimensions from `review-checklist.md`, then returns findings in the three-tier severity format.

**Dimension 4 (Boundary Map Contracts) only runs if a PRD with slice issues was provided.** Without boundary maps, there are no contracts to verify.

**Dimension 7 (Runtime Initialization) only runs if the diff includes schema files, migration files, environment config, or server startup code.** Without infrastructure changes, there is nothing to verify.

**Surgical Scope runs on every diff.** Where Dimensions 4 and 5 check plan-vs-actual between slices (PRD-gated), Surgical Scope checks scope drift inside a single diff — drive-by reformatting, speculative additions, adjacent fixes — and applies whether or not the work went through `/prd-to-issues`. Findings under this dimension must cite the file path and hunk start line; "looks scope-creepy" is not a finding.

**Dimension 11 (Review-friendly Size) runs on every diff.** It checks whether the diff stays within the convergent engagement bands documented in `review-checklist.md` (>300 LOC Observation, >500 LOC or >20 files Suggestion, >800 LOC + multi-domain Concern). Tracer-bullet slices are exempt — note the suppression in the findings rather than silently skipping. The signal is about *reviewer load*, not scope drift, so it is distinct from Dimension 10 even when both fire on the same diff.

**Dimension 6 (docs/solutions/ Adherence):** Search `docs/solutions/` for files whose `components` or `technologies` frontmatter overlaps with the changed code areas. If relevant solutions exist, check whether the implementation follows or consciously diverges from documented patterns.

**TypeScript projects:** For branches with significant `.ts` or `.tsx` changes, mention that `/ts-audit` can be run on the changed files for type-safety analysis that complements the architectural review. Do not invoke it automatically — note it as an option. Example: "For deeper TypeScript analysis, consider running `/ts-audit` on the changed files."

**Verify, don't suspect — library callback semantics.** When a finding turns on how a library treats a value the application hands it (return from a callback, object passed to a hook, systemMessages/tools/middleware collection semantics), the sub-agent must cite the installed type definition — `node_modules/<library>/**/*.d.ts` file path and line — in the finding. If a research archive entry exists for this feature, prefer its `callback_contracts_snapshot` (see `research/SKILL.md` Phase 1.25). Hedged language ("if the library replaces X rather than merges", "if this field is accepted") without a source citation is not acceptable for this class of finding — the proof is one grep away and the failure mode is runtime-invisible. Either cite the source and classify as Observation/Suggestion/Concern per the severity rules, or downgrade to a named follow-up with an explicit "verify before merge" action.

### Phase 4: Present Findings

Combine findings from all dimensions (or sub-agents).

**Minimum-findings guard.** Before presenting, count the total findings across all three tiers. If the total is fewer than 4 on a diff of any meaningful size (more than ~50 changed lines or more than 2 files), do one more focused pass explicitly looking for what you might be missing — scope drift, silent assumption changes, shallow modules, tests that only cover the happy path, or new state files that slipped past dimension 3. A count of zero or one on a non-trivial diff is a signal that the review stopped too early, not that the code is flawless. If after the second pass the count is still low, present what you have — do not fabricate findings to hit a quota.

**Author-mode** prints terminal advisories (below). **Reviewer-mode** transforms those same findings into draft PR comment text (see "Reviewer-mode comment drafts" below) — same dimensions, same severity classification, different output shape.

Present in the terminal using three tiers (author-mode):

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

**At the very end of Phase 4 output, print the runtime handoff line if — and only if — a durable lesson emerged from this work that future `/research` or `/write-a-prd` would benefit from:**

```
**Next session:** /compound
**Input:** PR #<pr-number>
```

Substitute `<pr-number>` with the PR created in Phase 2. Skip the line when the work was a clean execution of a pre-shaped plan with no surprises, rework, or non-obvious decisions — the issue body and PR description already carry that record, and a `docs/solutions/` entry with no reusable lesson trains future readers to skim. When in doubt, skip. Signals that a lesson is worth capturing: a tricky bug whose root cause was non-obvious, a Rabbit Hole from the PRD that actually bit, an architectural decision with significant tradeoffs, or a pattern that should be reused. See `/compound`'s "When NOT to Use" for the full skip list.

### Reviewer-mode comment drafts

In reviewer-mode, transform the dimension findings into PR comment text per `references/comment-craft.md`. Output drafts to the terminal (clearly grouped) for the user to review and post — do **not** post comments directly via `gh pr comment` or `gh api` from this skill. The user is the editor of last resort; auto-posting comments on someone else's PR is hard-to-reverse and skips the human empathy pass that comment-craft is built around.

For each finding, draft the comment using these rules. The full methodology is in `references/comment-craft.md`; this is the application:

1. **Run the 5P gate per finding.** If the concern is unjustifiable, *Pass* (drop it from the draft set). If it is valid but out of scope for this PR, *Postpone* (surface as a "Suggested follow-up issue" line, not a PR comment). Only Propose-class findings become PR comments.

2. **Map severity → Comment Signal.** Use `review-checklist.md`'s severity classification to pick the prefix:
   - `Concern` → `needs change:` (small fix), `needs rework:` (major refactor), or `align:` (convention violation)
   - `Suggestion` → `levelup:` (non-blocking improvement)
   - `Observation` → either drop entirely (no action implied) or post as `nitpick:` if it warrants noting

3. **Use Triple-R for action-requiring comments** (any blocking signal, plus most `levelup:`s). Request (transformation verb), Rationale (objective justification — cite the principle from `review-checklist.md`, the `.d.ts` line, the prior PR), Result (measurable end state).

4. **Apply tone discipline.** Replace sentence-initial "you" with "we." Ask, don't command. Target the artifact, not the author.

5. **Anchor each comment to a file path and line.** A PR comment without a code anchor is harder to act on than a terminal advisory; reuse the file/line citations the dimension findings already require (especially Surgical Scope's "cited hunks, not yes/no" rule).

Output shape in the terminal:

```
## Reviewer-Mode Draft Comments — PR #<pr-number>

### Per-line comments (paste at the cited code position)

#### `path/to/file.ts:42`
**`needs change:` Move helper into existing utility module**

**Rationale** — the new `formatBillDate` in `src/pipeline/format.ts:42` duplicates `lib/dates/format.ts`'s shape. `pre-merge/review-checklist.md` Dim 1 (Deep Modules) flags this as information leakage between two modules holding the same protocol detail.

**Result** — `formatBillDate` lives in `lib/dates/format.ts` and `src/pipeline/format.ts:42` imports it.

---

[next per-line comment]

### Top-level review summary (paste as PR-level comment)

[2-3 sentence summary of the review posture, naming the dimensions that ran and the highest-severity finding. Frame as collaborative, not adversarial — Rigby's "shippable code, not a defect tally."]

### Suggested follow-up issues (5P-Postpone — do not post in this PR)

- [Title] — out of scope for this PR; file as `<repo>/issues/new` if the team wants to track it
- [Title] — same

### Held back at 5P-Pass (no comments posted)

- [One-line note per dropped concern with the reason — kept for the user's audit, not for the PR]
```

If after the 5P gate the per-line comment count is zero, the review may still produce a top-level approval comment — phrase it as collaborative ("ready to ship from a structural standpoint" rather than "LGTM"). Tacke notes that LGTM-only approvals are a code-review failure mode; if you ran the 10 dimensions and have nothing concrete to say, that result is meaningful and should at least name which dimensions were checked.

If a disagreement is anticipated (e.g., the finding overturns a deliberate choice the author made), draft a single comment opening the MMG Exchange offline ("Can we sync briefly on the X tradeoff before I leave detailed comments?") rather than posting an objection thread on the PR.

## What This Skill is NOT

- **Not a test runner.** Pre-commit hooks run tests, typecheck, and lint on every commit.
- **Not a bug finder.** `/qa` files behavioral bugs as GitHub issues.
- **Not a refactoring planner.** `/request-refactor-plan` produces RFC-style refactor proposals.
- **Not a CI gate.** Findings are advisory. The user decides what to address before merging.
- **Not an auto-poster.** Reviewer-mode produces draft comment text for the user to review and post; the skill does not call `gh pr comment` or `gh pr review` itself.

## Handoff

- **Expected input:** verified implementation work that is ready for review and PR creation (author-mode), or an existing PR number you want reviewed (reviewer-mode)
- **Produces:** a PR with lineage plus an architectural review readout (author-mode), or draft PR comment text following `references/comment-craft.md` (reviewer-mode)
- **May redirect:** to `/qa` when a finding looks behavioral, or to `/request-refactor-plan` when deeper structural cleanup is warranted
- **Comes next by default:** merge. Then `/compound` only when a durable lesson emerged worth capturing in `docs/solutions/` — skip it when the work was a clean execution of a pre-shaped plan. In reviewer-mode, the user reviews and posts the draft comments; the next step is the author's response, not `/compound`
