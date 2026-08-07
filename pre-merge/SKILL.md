---
name: pre-merge
description: "Primary pipeline review step after verified implementation. Use to create a PR with lineage and run architectural review before merge. Not for QA intake, planning, or implementation work."
sources:
  secondary:
    - "Software Requirements — Karl Wiegers & Joy Beatty"
    - "The Checklist Manifesto — Atul Gawande"
    - "Continuous Delivery — Jez Humble & David Farley"
    - "The Twelve-Factor App — Adam Wiggins"
    - "Release It! — Michael Nygard"
    - "Growing Object-Oriented Software, Guided by Tests — Freeman & Pryce"
---

# Pre-Merge

Create a GitHub PR linking back to the PRD and slice issues, then review the full diff against the project's architectural principles. Produces advisory findings — does not block merge, auto-fix code, or file issues.

## Invocation Position

This is a primary pipeline skill used after implementation has been verified and before merging to main, *or* when picking up someone else's PR for review.

Use `/pre-merge` when the branch is ready for PR creation, architectural review, and final plan-to-code reconciliation. Use `/pre-merge --pr <number>` when you are reviewing a PR you did not author.

Do not use it as a substitute for implementation verification, QA intake, or refactor planning. It assumes the work is already built and ready to review.

## Modes

`/pre-merge` runs in one of three modes. All three reuse Phase 3's 11 architectural review dimensions (`review-checklist.md`); they differ in what they consume and what they produce.

- **Author-mode (default)** — invoked on your own branch with no `--pr` argument. The skill creates the PR (Phase 2) and prints findings to the terminal as advisories (Phase 4). This is the mode auto-invoked by `/execute` Step 6 on the HITL path.
- **Reviewer-mode** — invoked as `/pre-merge --pr <number>` against a PR you did not author. The skill skips PR creation (the PR already exists) and produces *draft comment text* (Phase 4) for you to review and post, structured per `references/comment-craft.md` (5P gate, Triple-R, Comment Signals, MMG Exchange).
- **Loop-mode** — invoked as `/pre-merge --loop`, or entered automatically when `/execute` hands off on an AFK run. Runs Phases 1–4 as author-mode does, then continues into **Phase 5**: it gives every finding a disposition (fix it here, or escalate and stop), applies the fixes through `/execute`'s normal path, re-stamps, and re-reviews the delta — bounded at three passes. Findings stop being advisories in this mode; they become work with owners.

**Loop-mode's exit condition is that every finding has a disposition — never that the review came back clean.** "Zero findings" is a *forbidden* termination signal, consistent with Phase 4's existing minimum-findings guard, which was written because a near-empty review on a non-trivial diff means the review stopped early rather than that the code is flawless. A loop that terminates on clean reviews will reliably produce clean reviews and nothing else (Meadows, *Seeking the Wrong Goal*; Leveson: never reward low incident counts — reward reporting itself).

If you are running on a branch other than the user's working branch and `--pr` was not provided, ask once whether the user means reviewer-mode against a specific PR number rather than guessing — auto-detection saves a keystroke but misclassifying mode produces draft comments that would have been local advisories or vice versa.

## When to Use

- **Author-mode:** after QA passes and before merging a feature branch to main; after Ralph finishes AFK execution and you've verified behavior; or for any branch you want reviewed before merge, even without a full pipeline run.
- **Reviewer-mode:** when a teammate or external contributor opens a PR and you want to apply the 10-dimension architectural review to their diff and produce constructive comment text.
- **Loop-mode:** when a branch should reach *reviewed, with every finding dispositioned* without an operator sitting through each pass — the AFK handoff from `/execute`, or a HITL run where you want the mechanical fix-and-re-review cycle driven for you and only the genuinely hard calls handed back.

## Execution Flow

### Phase 1: Gather Context

**Author-mode:**

1. **Ask for the PRD issue number.** Accept "none" if this change didn't go through the full pipeline. **In loop-mode entered from an AFK `/execute` handoff, do not ask** — take the issue number from the handoff (`/execute` Step 6 passes it) and treat its absence as "none". There is nobody to answer, so an unconditional question here would hang the run at its first step.

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

3. **Write the `## Review Notes` block, when `/execute` handed one over.** Both the author-mode and loop-mode handoffs pass a block of re-runnable verification claims — which commands ran and their exit status, which tiers were skipped and why, scope absorbed under the Consumes gate, assumptions that shifted, known-weak spots. Emit it verbatim after `## Summary`; do not summarize or re-word it. Its whole value is that the reviewer can re-run the claims, and every summarization hop is a lossy transformation authored by the agent under review. See `/execute` Step 6 for the block's shape.

4. Print the PR URL.

5. **Note that the body gains one more section later.** Phase 4 appends a `## Review Currency` block recording the head SHA the review actually covered. It is written *after* Phase 3 runs, not here — a stamp written at PR-creation time would certify a review that had not happened yet.

### Phase 3: Architectural Review

Consult `review-checklist.md` for the review dimensions and their violation patterns. The 11 dimensions run identically in both modes — the `diff` they read is the local `git diff "$BASE_BRANCH...HEAD"` in author-mode and the `gh pr diff <pr-number>` output in reviewer-mode.

**Delegation exists for reviewer independence; parallelism on large diffs is a sub-case of it.** When `/pre-merge` is auto-invoked by `/execute` Step 6 it runs in the session that just wrote the code, holding every rationalization the implementing agent made while writing it. The dimensions are sound; the reviewer is not independent. Cohen's finding is that the author's job is to *annotate for* a reviewer, not to be one — so the sub-agent split below is first a way to put a clean context in front of the diff, and only second a way to halve wall-clock on a big one.

- **Loop-mode: delegation is unconditional, regardless of diff size.** Each dimension pass runs in a fresh sub-agent whose entire context is the diff, `review-checklist.md`, and the PR body's `## Review Notes` block — *not* the implementing session's context. See Phase 5 for what the sub-agent may and may not be told between passes.
- **Author-mode and reviewer-mode: delegate by size.** **Small diff** (< 200 changed lines, < 10 files): run all dimensions sequentially in the main agent. **Larger diff**: spawn the two sub-agents below in parallel.

The split, when sub-agents are used:

- **Sub-agent A (structural & scope):** Deep Modules, Vertical Slice Integrity, State Discipline, Surgical Scope, Review-friendly Size
- **Sub-agent B (contracts & quality):** Boundary Map Contracts, Test Quality, docs/solutions/ Adherence, Runtime Initialization, Fix Completeness

Each sub-agent reads the full diff and its assigned dimensions from `review-checklist.md`, then returns findings in the three-tier severity format.

**The reviewer always reads the actual diff, never a summary of it.** A summary is a lossy transformation authored by the controller under review; a fresh context buys independence from *rationalization* and buys nothing against *misreporting* (Leveson: no control system performs better than its measuring channel).

**Dimension 4 (Boundary Map Contracts) only runs if a PRD with slice issues was provided.** Without boundary maps, there are no contracts to verify.

**Dimension 8 (Runtime Initialization & Production-Runtime Parity) only runs if the diff includes schema files, migration files, environment config, server startup code, a CLI/orchestration entrypoint with a dry-run mode, OR code whose deploy runtime differs from its test runtime / static assets resolved at deploy time / behavior bounded by a platform limit the test runtime does not enforce.** Without infrastructure or deploy-runtime changes, there is nothing to verify.

**Surgical Scope runs on every diff.** Where Dimensions 4 and 5 check plan-vs-actual between slices (PRD-gated), Surgical Scope checks scope drift inside a single diff — drive-by reformatting, speculative additions, adjacent fixes — and applies whether or not the work went through `/prd-to-issues`. Findings under this dimension must cite the file path and hunk start line; "looks scope-creepy" is not a finding.

**Dimension 11 (Review-friendly Size) runs on every diff.** It checks whether the diff stays within the convergent engagement bands documented in `review-checklist.md` (>300 LOC Observation, >500 LOC or >20 files Suggestion, >800 LOC + multi-domain Concern). Tracer-bullet slices are exempt — note the suppression in the findings rather than silently skipping. The signal is about *reviewer load*, not scope drift, so it is distinct from Dimension 10 even when both fire on the same diff.

**Dimension 7 (docs/solutions/ Adherence):** Search `docs/solutions/` for files whose `components` or `technologies` frontmatter overlaps with the changed code areas. If relevant solutions exist, check whether the implementation follows or consciously diverges from documented patterns.

**TypeScript projects:** For branches with significant `.ts` or `.tsx` changes, `/ts-audit` complements the architectural review with type-safety analysis. Whether it runs depends on the mode:

- **Author-mode and reviewer-mode: mention it, do not invoke it.** Note it as an option — "For deeper TypeScript analysis, consider running `/ts-audit` on the changed files" — and leave the decision with the user. This is the deliberate HITL boundary; the scoping below does not move it.
- **Loop-mode: auto-invoke it** on the changed `.ts`/`.tsx` files and feed its findings through Phase 5's disposition rubric alongside the dimension findings. It is already the recommended next action at exactly this point for exactly these files; the only reason it was ever manual is that nothing drove the loop.

**Verify, don't suspect — library callback semantics, subpath swaps, and provider schema constraints.** When a finding turns on how a library treats a value the application hands it (return from a callback, object passed to a hook, systemMessages/tools/middleware collection semantics), the sub-agent must cite the installed type definition — `node_modules/<library>/**/*.d.ts` file path and line — in the finding. If a research archive entry exists for this feature, prefer its `callback_contracts_snapshot` (see `research/SKILL.md` Phase 1.25). For findings that turn on which subpath of a package an import resolves through — runtime-affecting swaps disguised as type-only diffs across sibling subpaths of multi-runtime packages — prefer the `installed_versions_snapshot` (see `research/SKILL.md` Phase 5b); Dimension 4's spec-reality check item 2 is the gate that consumes it. For findings that turn on **provider schema constraints when an SDK wraps a provider** — the SDK's type signature accepts a shape (JSON Schema, Zod, tool definitions) that the underlying provider's actual contract rejects (e.g. Gemini's `response_schema` rejecting numeric enums, Anthropic's `tool.input_schema` honoring only a subset of JSON Schema, OpenAI Structured Outputs' schema-subset divergence from JSON Schema 2020-12) — the citation must include the provider's contract docs at the installed SDK version, not only the SDK's permissive `.d.ts`. Hedged language ("if the library replaces X rather than merges", "if this field is accepted", "the SDK lets you pass any schema") without a source citation is not acceptable for this class of finding — the proof is one grep or one provider-docs page away and the failure mode is runtime-invisible. Either cite the source and classify as Observation/Suggestion/Concern per the severity rules, or downgrade to a named follow-up with an explicit "verify before merge" action.

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

**Acceptance-criteria checkbox reconciliation (reporting only).** While the slice issues are loaded, compare each slice's `## Acceptance Criteria` checkbox state against what the merged diff and verification actually establish. Flag any mismatch as a factual note — a criterion that reads as met but whose box is still unchecked, or a checked box the diff doesn't support. Report it; do not edit the issue. `/execute` is the single writer for these boxes (see its Step 5/6 writeback); `/pre-merge` stays advisory and never writes, so this is a merge-gate backstop that surfaces drift without creating a second editor.

**Closing-issue comment-thread reconciliation (reporting only).** Phase 1 loads slice issues without their comment threads, so a requirement living only in a comment is invisible to every check above. For each issue named in the PR body's `Closes #N` lines — those issues only, not every slice loaded in Phase 1 — fetch the thread and compare it against the body:

```bash
gh issue view <closing-issue-number> --comments
```

Report as a factual note any comment naming a concrete capability the body's acceptance criteria do not cover **and whose consumer you can name** (an issue, slice, PRD, or shipped code that would use it). Apply the same discriminator `/execute` Step 1 uses: an exploratory comment with no identified consumer does not qualify. Merging is what closes the issue, so this is the last moment the thread is still attached to open work. Report it; do not edit the issue and do not file the follow-up yourself — `/execute` remains the single writer, and this backstops the case where `/execute` never ran on the issue at all (hand-authored PRs, external contributions).

If the review reveals that the main lesson is about Skill Kit itself — for example unclear stage boundaries, missing handoff guidance, or a review checklist gap in `chrislacey89/skills` rather than a problem in the downstream codebase — note: "Consider running `/improve-pipeline` if that skill is present." Do not invoke it.

If a concern warrants deeper work, note: "Consider running `/request-refactor-plan` for this area." Do not invoke it.

If a finding looks like a behavioral bug, note: "Consider running `/qa` to verify." Do not file an issue.

If the person about to merge did not author the diff — or hasn't internalized it commit-by-commit — note: "Consider running `/walk-commits` for an interactive per-commit comprehension walkthrough before merge." Do not invoke it. This is a comprehension/sign-off pass, distinct from the defect review above; it does not replace these findings.

Omit any tier that has zero findings.

**Stamp the reviewed head SHA into the PR (author-mode and loop-mode).** The review above covers one specific commit. Record which one in the PR body, so a later — possibly fresh-session — `/closeout` can tell whether the diff it is about to merge is still the diff that was reviewed. Prospective memory fails silently (Norman), so the marker goes into durable GitHub state rather than into the operator's head; `/closeout` Step 2's review-currency precondition is its only reader.

Write it only after the findings above have been presented — the stamp asserts "a review completed at this SHA," so writing it earlier would certify a review that had not run.

```bash
REVIEWED_SHA=$(git rev-parse HEAD)
BODY_FILE=$(mktemp)   # unique per run — parallel worktrees must not share a temp path
gh pr view <pr-number> --json body -q .body > "$BODY_FILE"
# In "$BODY_FILE": replace the existing "## Review Currency" section if one is
# present; otherwise append this block, substituting the real SHAs:
#
#   ## Review Currency
#
#   <!-- reviewed-at: <full-sha> -->
#   Reviewed by `/pre-merge` at `<short-sha>`. Commits pushed after this SHA have
#   not been through the review dimensions — `/closeout` surfaces the delta before merge.
#
gh pr edit <pr-number> --body-file "$BODY_FILE"
rm -f "$BODY_FILE"
```

- **The HTML comment carries the full 40-character SHA — never the short form.** The two placeholders sit on adjacent lines and are not interchangeable: `<full-sha>` is the untruncated `git rev-parse HEAD` output, `<short-sha>` is the abbreviated form and belongs *only* in the visible prose line. `/closeout` compares the extracted marker against `headRefOid`, which is always 40 characters, so a short SHA in the comment can never compare equal — the gate would then report divergence on a PR whose head never moved, and a gate that cries wolf is one that gets clicked through. `/closeout`'s parser requires exactly 40 hex characters, so a swapped placeholder does not degrade quietly into a prefix match; it fails to parse. In the Skill Kit repo, `scripts/test-review-currency-marker.sh` pins this contract by round-tripping this template through `/closeout`'s own extraction, so the two skills cannot drift apart silently.
- **Exactly one stamp per PR.** Re-running `/pre-merge` replaces the existing block rather than appending a second one. `/closeout` reads the stamp as a single value, and two stamps make "which SHA was reviewed" ambiguous — with the stale one being the more dangerous answer.
- **Keep both halves.** The HTML comment is what `/closeout` greps for; the visible line is what tells a human skimming the PR why an unfamiliar SHA is sitting in the body.
- **Reviewer-mode does not stamp.** It never creates or rewrites the PR body (Phase 2 is skipped for the same reason), and its findings are drafts the user has not yet posted — nothing has been reviewed *into* that PR to certify.
- **Fixes made in response to these findings will move the head past the stamp.** That is the mechanism working, not a false alarm: those commits genuinely have not been reviewed. Re-running `/pre-merge` after the fixes re-stamps and clears the divergence.
- **Loop-mode re-stamps on every exit path**, including the escalation and bound-exhaustion paths. See Phase 5 — the loop authors fix commits inside the interval this stamp guards, so an exit that skips the re-stamp makes `/closeout` report divergence on work the loop itself reviewed.

**At the very end of Phase 4 output, if — and only if — a durable lesson emerged from this work that future `/research` or `/write-a-prd` would benefit from, recommend capturing it in this PR before merge.** `/compound`'s default is to commit the `docs/solutions/` entry onto this still-open PR branch, so the lesson is reviewed in the same pass as the code and merged atomically with it — capture it now, before `/closeout`, rather than as a separate post-merge session. Print the runtime handoff line:

```
**Next session:** /compound
**Input:** PR #<pr-number>  (capture the lesson onto this PR branch, before /closeout merges)
```

Substitute `<pr-number>` with the PR created in Phase 2. Skip the line when the work was a clean execution of a pre-shaped plan with no surprises, rework, or non-obvious decisions — the issue body and PR description already carry that record, and a `docs/solutions/` entry with no reusable lesson trains future readers to skim. When in doubt, skip. Signals that a lesson is worth capturing: a tricky bug whose root cause was non-obvious, a Rabbit Hole from the PRD that actually bit, an architectural decision with significant tradeoffs, or a pattern that should be reused. See `/compound`'s "When NOT to Use" for the full skip list.

### Phase 5: Loop-Mode — Dispose of Every Finding

**Loop-mode only.** Author-mode and reviewer-mode end at Phase 4; their findings stay advisory by design.

Phases 1–4 are a sensor. Without something that acknowledges, investigates, and resolves what the sensor reports, the reporting channel is functionally equivalent to having no sensor at all (Leveson, Ch. 12) — and Phase 4's own closing line is "No action is required. These are advisory." Phase 5 is the closing arc: it turns each finding into a disposition, applies what it may safely apply, and hands back what it may not.

**Bounds.** At most **three** passes. A pass is: Phases 1–4 (Phase 2 skipped after the first — the PR exists) → plan → execute → re-stamp → ledger write.

#### Step 1 — Triage every finding into a plan, before fixing anything

Do not triage and fix in one motion. Produce the *complete* disposition plan for the pass first, validate it, and only then execute (Huyen, Ch. 6 — planner / evaluator / executor: "to avoid fruitless execution, planning should be decoupled from execution"). Catching a bad plan costs one check; catching it mid-execution costs commits to unwind.

**Verify each finding against the tree before it may be dispositioned FIX.** A finding is a *claim about* the code, not the code. On the corpus that validated this rubric, one finding of fourteen asserted that a block "no-ops because the mutating step is a bash comment" — and all three independent classifiers dispositioned it FIX with high confidence. It was a false positive: the comment-carries-the-judgment-step shape is an established convention in this repo, used identically in `/execute` Step 5's acceptance-criteria writeback. A loop running that plan would have confidently "fixed" a convention it did not recognize. So: **a FIX disposition requires the finding to be confirmed against the tree first, and a finding that fails verification is dropped, not fixed.** Phase 3's "Verify, don't suspect" rule already says this for library-callback semantics; loop-mode generalizes it to every finding it intends to act on. Record dropped findings in the ledger as `dropped` with the verification that refuted them — a dropped finding is still a dispositioned finding.

**The disposition rubric — two branches, FIX or ESCALATE.**

- **FIX in-loop** — the finding is local to files already in the diff, **and** confirmable by an existing feedback loop you can name: typecheck, test, lint, or a specific verification-ladder tier from `/execute` Step 4. Both halves are required. "I can see how to fix this" is not a feedback loop.
- **ESCALATE and stop — no judgment call.** Any one of these, and the loop stops:
  - the fix changes a public interface, an exported type, a boundary-map `Produces`, or an API contract;
  - it adds, removes, or upgrades a dependency;
  - **the minimal and the thorough fix would leave different public contracts behind** (nearly every finding admits a minimal and a thorough fix, so "two designs with different long-term costs" is too wide a test to be useful — the discriminator is the contract each one leaves, not the effort each one takes);
  - it contradicts the PRD, the research artifact, or a `docs/solutions/` entry;
  - the same finding survives two passes;
  - `/execute`'s repeated-failure or plateau rule trips.

**Filing is not a third branch.** It is the output of the structural-sibling search that a FIX already runs (see Step 2). `/pre-merge` findings are by construction *about the diff*, so a branch defined over out-of-diff work has no input to match: given this rubric with FILE as a peer option, three independent classifiers selected it zero times across 42 judgments. Siblings are a different input type, produced as a side effect of fixing.

**Validate the plan before executing it.** Four cheap checks that pay for themselves:

1. Does every finding matching the escalate list above actually carry an ESCALATE disposition?
2. Is any single bucket at 100%? All-FIX means the escalate list was not consulted; all-ESCALATE means the loop is a rubber stamp that saves nothing.
3. Does any FIX name a file outside the diff? That is an escalate or a file, not a fix.
4. Does any FIX lack a named feedback loop that would confirm it?

**Errors must fall toward ESCALATE.** Three passes over a normal finding set is on the order of 40 disposition decisions; even at 95% accuracy each, the probability that all are correct is around 13% (Huyen's compound-error arithmetic — `0.95^10 ≈ 0.60` for a ten-step agent). The design response is not "be more accurate," it is that the two branches have **asymmetric cost**: a wrong ESCALATE wastes the operator's time, while a wrong FIX ships unsupervised bad code. When a disposition is genuinely borderline, escalate.

#### Step 2 — Execute the plan

**Fixes route through `/execute`'s normal path.** Classification gate, `/tdd` where it applies, commit per logical unit, the Step 4 verification ladder. There is no bypass lane for fixes just because a reviewer asked for them.

**Every FIX runs `/execute`'s structural-sibling search** (Step 4, Bug-Fix Verification item 2): search the codebase for the same pattern that produced the finding. Siblings inside the diff are fixed in the same pass. **Siblings outside the diff are filed as issues in `/qa`'s shape and linked to the PR** — do not hand-roll issue bodies, and do not widen the diff to reach them. This is Leveson's learning orientation applied at the finding level: a defect fixed in one location and left in three others is 75% unfixed.

**Fixes apply in a defined order, and the next pass may not start until this pass's fix commits have landed.** A pass that reads a half-applied fix set produces findings about a state that never existed (STPA: *wrong timing or sequence*). Order the fixes so the tree typechecks between commits, apply them, and confirm every commit is in before Step 3.

#### Step 3 — Close the pass, then decide whether another is warranted

1. **Re-stamp.** Run Phase 4's stamp block against the new head — same single-block, replace-not-append mechanics.
2. **Write the ledger** (below) into the PR body.
3. **Decide.** If every finding from this pass has a disposition and no ESCALATE fired, run one more pass over the delta. If nothing new surfaces and everything is dispositioned, exit clean.

**Re-review the delta, not the whole diff again.** Pass N > 1 reviews `git diff <previously-stamped-sha>...HEAD` — the commits this loop just authored — with the full `$BASE_BRANCH...HEAD` diff available as context so a fix's interaction with unchanged code is still visible. Re-running all 11 dimensions over an unchanged diff produces the same findings and burns a pass.

#### The disposition ledger

Each pass runs in a fresh sub-agent, so without a durable artifact it re-derives the previous pass's findings (Cohen: N passes by a self-similar reviewer are not N independent reviews). The ledger is that artifact, and it is simultaneously the acknowledged / investigated / resolved record Leveson's closed-loop rule requires — one artifact, both jobs, GitHub-native.

It follows the `## Review Currency` conventions exactly: a marked block in the PR body, **exactly one per PR**, replaced rather than appended, with a machine-readable marker and a visible human line.

```markdown
## Review Disposition Ledger

<!-- loop-pass: 2 of 3 -->
<!-- loop-judge: model=<model-id> checklist=<sha of review-checklist.md> prompt=loop-mode-v1 -->

Dispositioned by `/pre-merge` loop-mode. Every finding below has an owner: a commit, an issue, or an escalation waiting on you.

| Finding | Dimension | Disposition | Where it landed |
|---|---|---|---|
| Duplicate date formatter in pipeline | 1 — Deep Modules | fixed | `abc1234` |
| Same pattern in `lib/export/` | 1 — Deep Modules (sibling) | filed | #199 |
| Presence helper claimed as Effect Layer | 4 — Boundary Map | escalated | pass 2 — changes an exported type |
| Stamp block "no-ops" | 6 — docs/solutions | dropped | repo convention; `/execute` Step 5 uses the same shape |
```

Write it with the same `mktemp` → read body → edit the block → `gh pr edit --body-file` shape Phase 4's stamp uses. `gh pr edit` creates no commits, so ledger and review-notes writes do not move the head and are **benign** writers in the review-currency interval — stated explicitly because "writes to the PR" reads as invalidating when left unclassified, and an unclassified writer is how a gate acquires its first false positive on the happy path. A staleness gate's correctness is a property of the *interval* it spans, not of the two steps at its ends, so every actor that can write the guarded artifact in that interval needs an explicit benign-or-invalidating call.

**What passes forward to the next pass, and what is withheld.** Independence and efficiency pull opposite ways here, and the split resolves them:

- **Forward: the dispositions** — what was fixed and where, what was filed, what was dropped and why. These are facts about the code's *current* state. Without them the next pass re-reports resolved findings.
- **Withheld: the previous pass's un-actioned findings and its severity judgments.** That is the anchoring surface. A fresh reviewer independently re-raising something an earlier pass dismissed is *signal* — and under the escalate list, a finding surviving two passes is already a stop trigger. Forwarding the earlier judgment would suppress exactly the evidence that trigger depends on.

This is deliberately **not** `/handoff`. That skill summarizes into a transient `mktemp` doc, and both properties are wrong here: the fix Leveson's rule demands is "hand over checkable claims," not "summarize better," and every summarization hop is a lossy transformation authored by the upstream controller. `/handoff`'s own Red Flags already forbid producing a doc at a pipeline-skill boundary; that fence stays where it is.

#### Pin the judge, or cross-pass comparison is meaningless

The delegated reviewer is an AI judge, and **a judge is a system — model + prompt + sampling parameters — not a model** (Huyen, Ch. 3). The escalate rule "the same finding survives two passes" silently assumes pass 1 and pass 3 measured the same way. Nothing enforces that on its own, so loop-mode records the reviewer's model, the `review-checklist.md` revision, and the prompt shape in the ledger's `loop-judge` marker. **A change to any of the three starts a new loop rather than continuing the current one** — pass counts and survive-two-passes comparisons do not carry across a judge change.

#### Exit paths

All three re-stamp. All three write the ledger. All three print what the operator is inheriting.

| Exit | When | What it means |
|---|---|---|
| **Clean** | every finding dispositioned, no escalate fired, a delta pass surfaced nothing new | The branch is reviewed and every finding has an owner. Hand off to `/compound` or `/closeout` as Phase 4 describes. |
| **Escalation** | any escalate-list condition fired | Stop immediately. Name the finding, the condition it tripped, and what you did *not* do. The remaining findings still get dispositions in the plan — escalating one finding does not leave the others unowned. |
| **Bound exhausted** | three passes with findings still undispositioned | **This is an escalation, not a clean exit.** Say so plainly. A bound that quietly reports success when it runs out of passes is the "stopped too soon" hazard wearing a green badge. |

**Re-stamp on every one of them — including escalation and bound exhaustion.** Loop-mode's fix commits are invalidating writers in the interval between Phase 4's stamp and `/closeout`'s check. A loop that fixes code and then escalates without re-stamping leaves its own commits sitting past the stamp, and `/closeout` reports divergence on work the loop authored and reviewed itself — training the reflexive click-through the review-currency gate exists to avoid, on code rather than on a single markdown file.

#### Health signals

**The loop's health signal is findings surfaced and dispositioned — never findings remaining.** Watch two rates together, not either alone (Huyen, Ch. 4 — violation rate paired with false-refusal rate): the **bad-fix rate** (fixed what it should have escalated) and the **over-escalation rate** (escalated what was plainly local and checkable). Optimizing either alone yields a useless loop — reckless in one direction, a rubber stamp that escalates everything and saves nothing in the other. The ledger is the raw data for both.

If *findings surfaced per pass* trends down across runs over time, the loop is suppressing reports rather than improving code — re-anchor the bar or return review to HITL.

#### Circuit breakers

Loop-mode introduces none of its own. It trips on `/execute`'s existing repeated-failure and plateau rules, which already have the right shape: two consecutive passes on the same finding set with nothing transitioning from unresolved to resolved is a plateau, and it escalates.

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
- **Not a CI gate.** In author-mode and reviewer-mode, findings are advisory and the user decides what to address before merging. Loop-mode acts on findings but is still not a gate — it ends at "every finding has a disposition," never at "safe to merge," and `/closeout` remains HITL-confirmed.
- **Not an auto-poster.** Reviewer-mode produces draft comment text for the user to review and post; the skill does not call `gh pr comment` or `gh pr review` itself.
- **Not a learning organ.** Loop-mode is a *fixing* orientation by design — it disposes of findings. Diagnosing the process defect that let a flaw through is `/compound`'s job, and loop-mode's escalations and filed issues are its input.

## Handoff

- **Expected input:** verified implementation work that is ready for review and PR creation (author-mode), an existing PR number you want reviewed (reviewer-mode), or an AFK handoff from `/execute` — branch plus the `## Review Notes` it wrote into the PR body (loop-mode)
- **Produces:** a PR with lineage, stamped with the head SHA the review covered, plus an architectural review readout (author-mode); draft PR comment text following `references/comment-craft.md` (reviewer-mode); or a branch where every finding carries a disposition — fix commits, filed issues, and a `## Review Disposition Ledger` in the PR body, re-stamped on whichever exit path was taken (loop-mode)
- **May redirect:** to `/qa` when a finding looks behavioral, or to `/request-refactor-plan` when deeper structural cleanup is warranted
- **May invoke:** `/ts-audit` on changed `.ts`/`.tsx` — in loop-mode only; author-mode and reviewer-mode mention it without invoking
- **Comes next by default:** when a durable lesson emerged, `/compound` first — captured onto this open PR so it is reviewed and merged with the code it explains (skip when the work was a clean execution of a pre-shaped plan); then `/closeout` — confirm, merge the reviewed PR, re-anchor off the worktree before removing it, prune the merged branch, pull base, and verify a clean end state. When no lesson is worth capturing, go straight to `/closeout`. Lessons that only surface during or after merge can still be compounded post-merge as the fallback. In reviewer-mode, the user reviews and posts the draft comments; the next step is the author's response, not `/closeout`. In loop-mode, a clean exit joins the author-mode path above; an escalation or bound-exhaustion exit hands back to the operator with the ledger naming what is unowned, and nothing proceeds until they decide

**Next-step menu.** This is a genuine branch point, so offer the next step as a menu rather than leaving the user to retype a command (see `references/next-step-menu.md`). It does not apply on AFK loop-mode runs — there is no user to ask, so print the exit readout and the handoff line instead. Present a single `AskUserQuestion` with the recommended step first. In author-mode, when a durable lesson emerged: **→ `/compound` in this PR (recommended)**, **`/closeout` (no lesson to capture)**, **Address a finding first**. When no lesson emerged, lead with **→ `/closeout` (recommended)**, **Address a finding first**, **File follow-up issues / redirect to `/qa` or `/request-refactor-plan`**. In reviewer-mode the options differ — **Post the draft comments**, **Open the MMG exchange offline first**, **Revise a draft comment** — because the next move is the author's response, not `/closeout`. The platform's free-text "Other" option is the escape hatch — don't add one.
