---
date: 2026-08-15
category: architecture-decisions
problem_type: the diff that answers review findings is the least-reviewed code in the pipeline
components: [pre-merge, execute, closeout]
technologies: [pipeline-design, code-review, ai-judges]
severity: medium
volatility: stable
---

# The fix for a review finding is the one diff nobody reviews

## Problem

`/pre-merge` puts a blind reader in front of the diff, hands its findings to the author, and stops. The author's *response* to those findings — the fix commit — gets no reader at all. That commit is written under the finding's framing and under pressure to comply, which makes it more likely to carry a defect than the diff that triggered it, not less.

## Context

PR #226 (issue #224) added one violation-pattern bullet to `/pre-merge`'s own review checklist. Author-mode delegated the review to a fresh sub-agent, which returned three Concerns. All three were real and all three were confirmed by execution against the tree.

The fix commit (`da0e1ff`) addressed all three. A second review round — run by choice, not by any rule — found that the fix commit had introduced **two new defects**, both absent from the original diff:

1. Round 1 flagged the bullet's falsification clause for carrying two criteria and only one number. The fix **deleted the unquantified criterion**. That was the wrong half: `<10%` tests for *dead ceremony*, and the deleted clause tested for *noise* — which #224's own Mediator verdict names as the bullet's top repo-wide risk, with that note as its stated mitigation. The fix removed the mitigation for the risk the issue was most worried about, and the CHANGELOG then described the removal as an improvement ("one criterion instead of two").
2. The same commit pointed the remaining count at *"the Phase 5 ledger's per-dimension tallies."* That instrument does not exist for this purpose: `pre-merge/SKILL.md:303` scopes the ledger to loop-mode, its `Dimension` column is dimension-level rather than per-bullet, and the author-mode run that produced these very findings wrote no ledger at all. A mechanism was asserted to close the gap the finding had named.

Neither defect was in `914fb66`. Both entered while fixing it.

## Symptoms

- A review finding of the form *"X is underspecified / unquantified / ambiguous"* is answered by **deleting X** rather than sharpening it. The finding is technically satisfied and the function X performed is gone.
- A fix commit closes a "this claims something unverified" finding by **naming a mechanism** — a counter, a ledger, an existing test, a downstream skill — without checking that the mechanism produces what the claim needs.
- The PR's review-currency stamp is older than `HEAD`, and nothing in the session treats that as a reason to re-review.
- A `docs/solutions/` entry exists that names the exact defect, is cited elsewhere in the same change, and still does not prevent it.
- The fix commit's message reads as a list of compliance items ("addressed finding 1, 2, 3") rather than as a change with its own rationale.

## Root Cause

**The pipeline's independent-reader mechanism is scoped to one diff, and the fix is a different diff.**

`/pre-merge` Phase 3 makes delegation unconditional precisely because the authoring session cannot review its own work — *"a fresh context buys independence from rationalization."* But Phase 4 ends at presenting findings, and the skill's closing line is *"No action is required. These are advisory."* Everything after that point — the author reading the findings, deciding what each one means, and writing the commit that answers them — happens in the authoring session with no blind reader anywhere.

The gap is not that the machinery is missing. **It already exists and already detects this.** Phase 4 stamps `<!-- reviewed-at: <sha> -->` into the PR body and says outright: *"Fixes made in response to these findings will move the head past the stamp. That is the mechanism working, not a false alarm: those commits genuinely have not been reviewed."* The stamp fires correctly. It just reports to `/closeout`, whose job is to surface the delta before merge — a *disclosure* at the merge gate, not a *re-review*. Re-running `/pre-merge` after fixes is described as what clears the divergence; nothing requires it.

**Why the fix commit is higher-risk than the diff it fixes**, which is the part that makes this worth a mechanism rather than diligence:

- The author is no longer solving the original problem. They are solving *"make this finding go away,"* and those have different cheapest solutions. Deletion is almost always the cheapest, and it reads as compliance.
- A finding supplies its own frame, and the frame is narrow. Round 1's finding was *"two criteria, one number."* Both repairs satisfy it; only one preserves the function. Nothing in the finding says which, because the reviewer was describing a defect, not specifying a fix.
- Momentum: findings arrive as a list, and lists get worked through. The care spent deciding *whether* each fix is right is a fraction of what was spent writing the original change.

**And the failure is silent in the specific way that defeats a `docs/solutions/` entry.** `self-review-blind-to-composition-2026-08-13.md` was already in the tree. Its Rule Scope names commits whose parts interact through *"a record, a counter, a state enumeration, a **retirement condition**"* — the falsification clause is a retirement condition — and its Solution prescribes the exact check: *"confirm the counter that test reads can distinguish the mechanism not firing from the mechanism being unable to fire."* The round-2 reviewer quoted that line back. The entry could not fire on its own, because the artifact that reads `docs/solutions/` is `/pre-merge` Dimension 7, and Dimension 7 had already run — on the diff before the fix.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing loop runs from **the fix** back to **the review that demanded it**. `/pre-merge` is a single-pass sensor with a manual re-arm: it reads a diff, emits findings, and the operator decides whether it ever reads again. Every safeguard in the pipeline — the blind reader, the eleven dimensions, Dimension 7's `docs/solutions/` consultation, the evidence check — is spent on the pre-finding diff and none is spent on the post-finding one. The delay hides it: a defect introduced while fixing looks like a fix, ships inside a commit whose message is a list of corrections, and the stamp that noticed the head moved reports to a skill two steps downstream whose remit is disclosure rather than review.

## Rule Scope

- **Applies when** all three hold:
  - a review produced findings that the author will act on **in the same session**, holding the reviewer's framing; **and**
  - at least one finding is of the *underspecified / unverified / ambiguous* shape, where deletion and sharpening both satisfy it; **and**
  - the artifact is prose, config, or a cross-file contract — something no compiler or test will re-check after the edit.
- **Inverts or does not apply when:**
  - **The fix is mechanical and its correctness is checkable by the suite.** A rename, a type fix, a corrected import — CI is the second reader and is a better one. Re-review buys nothing.
  - **The finding names the repair, not just the defect.** *"Add `push -f` to `DANGEROUS_PATTERNS`"* has one implementation; *"the falsification clause has two criteria and one number"* has two, and they are opposites. The risk lives entirely in the second shape. A reviewer who can cheaply name the repair should, and that is the cheaper fix than a second round.
  - **The fix is a pure subtraction the finding explicitly requested** — *"delete this bullet"* is not the subtraction trap; *"quantify this bullet"* answered by deletion is.
  - **A blind reader is already in the loop by construction** — loop-mode, where the operator settles ledger rows between passes and the next pass re-reads with fresh eyes. This entry is about author-mode, which is the default and the auto-invoked path from `/execute` Step 6.
- **Sibling docs:**
  - `self-review-blind-to-composition-2026-08-13.md` — the direct parent, and the sharpest evidence for this entry, twice over. That one says a composition defect needs a *blind reader*; this one says the pipeline supplies that reader for exactly one diff. Its prescribed counter-check is what round 2 used, quoting it verbatim — an entry cannot fire on the commit written after the pass that would have read it. Its **Postscript** is the prior instance of this entry's own thesis (six defects in the commit that answered two earlier passes), filed as a footnote to a lesson about readers rather than as a lesson about targets.
  - `by-construction-claims-need-a-mechanism-2026-08-11.md` — defect 2 is a textbook instance, committed while citing that entry's family two bullets away in the same CHANGELOG. Knowing the rule is not the binding constraint; being read at the right moment is.
  - `advisory-to-executed-rule-promotion-2026-08-07.md` — *"an acknowledged limitation that gates nothing is not a constraint. It is a footnote."* The review-currency stamp is the mirror image: a *detection* that routes nowhere actionable is also a footnote. The stamp is correct, timely, and inert.

## Solution

**What this PR did (the instance).** Ran a second `/pre-merge` round scoped to the fix commit, with a fresh sub-agent given the delta and an explicit instruction to check whether each claimed fix held. It returned `DOES NOT HOLD` on the mechanism claim and a Concern on the deleted criterion. Both were repaired in `fb48b8b`: both criteria restored and quantified, *"fires"* defined as a violation so the acceptance notes the bullet itself mandates cannot inflate the numerator, and the honor system named as an honor system rather than dressed as an instrument.

**The generalizable move — review the fix, not just the finding.** A second pass is cheap and the prompt is different from the first. It is not *"review this diff"* but:

> Here is a commit claiming to address findings A, B, C. For each: does the claimed fix hold? Verify by execution where execution is possible. Then — did the fix introduce anything new? Report `HOLDS` / `PARTIAL` / `DOES NOT HOLD` per claim.

The verdict-per-claim shape is what does the work. *"Review this commit"* would likely have passed both defects: the deletion looks like a tightening and the ledger reference looks like a citation. Asking *"does this claimed fix hold"* forces the reviewer to go read the ledger and find it is loop-mode only.

**Before** — Phase 4 ends:

> No action is required. These are advisory. When ready, merge the PR at `<PR-URL>`.
>
> *(author fixes findings; head moves past the stamp; `/closeout` discloses the delta at merge)*

**After** — the loop re-arms on the condition that already exists:

> *(author fixes findings; head moves past the stamp)*
>
> The stamp is stale ⇒ the fix commit is unreviewed ⇒ re-run scoped to the delta, with per-claim verdicts ⇒ re-stamp.

## Prevention

**Code-level.** The trigger needs no new state — it is already in the PR body and already machine-readable. `/closeout` extracts `<!-- reviewed-at: <sha> -->` and compares it against `headRefOid`; that same comparison run at the *end of `/pre-merge`* answers "is there an unreviewed delta?" A contract test in the shape of `scripts/test-review-currency-marker.sh` — which already round-trips the marker between `/pre-merge`'s template and `/closeout`'s parser — could pin that a third reader exists for the stamp, so the detection has somewhere to go.

**Process-level.** Two changes, neither yet made, both `/improve-pipeline` candidates:

1. **`/pre-merge` should re-arm on a stale stamp rather than leaving it to the operator.** The condition is already computed and already disclosed; only the routing is missing. Scope the second pass to the delta and require per-claim `HOLDS` / `PARTIAL` / `DOES NOT HOLD` verdicts rather than an open-ended re-review — the verdict shape is what caught both defects here, and an open-ended pass plausibly catches neither. Note the honest cost: this makes every findings-bearing PR at least two sub-agent passes, and the falsification test should be whether round two ever finds anything on a reasonable sample.
2. **A reviewer who can cheaply name the repair should name it.** The whole subtraction trap opens in the gap between *"X is underspecified"* and *"here is what X should say."* This is a smaller, cheaper change than (1) and attacks the same seam from the other end: `comment-craft.md`'s Triple-R already requires a **Result** (measurable end state) on action-requiring comments. Extending that requirement to author-mode terminal findings — not just reviewer-mode PR comments — would have made round 1's finding read *"quantify the second criterion"* instead of *"there are two criteria and one number."*

## Planning / Calibration Notes

- **What widened the work:** the second review round, and it more than paid for itself. The change was two rows from a Mediator verdict, expected as a single small commit. It shipped as three, and commits two and three exist entirely because review found things — one round on the original diff, one on the fix. Budget review-and-repair as its own phase on any change to a shared rule, not as a tail on implementation.
- **What tightened the work:** verifying by execution rather than by reading. Every confirmed finding across both rounds came from running something — `echo '{"tool_input":…}' | bash block-dangerous-git.sh`, `git ls-files .claude`, `gh pr view --json body`. The findings that came from reading prose alone were the ones that needed the most re-checking. Where a claim is executable, execute it.
- **Future planning adjustment:** for a change that edits a rule other work is judged by, plan for N+1 review passes and treat the fix commit as reviewable work rather than as cleanup. The first pass reads the change; the second reads the response to the first.

## Actuals Worth Reusing

- **Comparable future work:** any change to `pre-merge/review-checklist.md`, a scaffolded hook, or a cross-skill contract — anywhere the artifact under change is the thing that judges other changes.
- **Reusable baseline:** a 19-line, 3-file diff produced 3 Concerns in round 1 and 2 more in round 2, both introduced by the fix. On this repo, **assume the fix commit carries roughly one new defect per two findings addressed** when the findings are prose-shaped.

  **This is n=2, and the prior instance is worse.** `self-review-blind-to-composition-2026-08-13.md`'s own Postscript records a third pass, run on the commit that added that entry, finding **six** further defects in it — including "an undercount of the blind pass's own output (one follow-up commit where there were two — a claim this entry contradicted three paragraphs earlier)" and "a Prevention section that gated nothing while quoting a sibling entry against exactly that." Every one of those is a defect in a commit written to answer prior review. It was recorded as a postscript to an entry about *blind readers* rather than as a lesson about *which diff the reader is pointed at*, which is why the shape had to be rediscovered here. Two observations, both on prose diffs, both non-trivial: treat the fix commit as reviewable work by default rather than waiting for n=3.

## Defect Classification

**Origin phase:** Design error — the review loop was designed as a single pass with manual re-arm. Each part is correct in isolation (the blind reader, the stamp, `/closeout`'s disclosure); the seam between detection and re-review is where nothing lives.
**Fix type:** **Workaround.** The instance was corrected by choosing to run a second round. Nothing yet requires it, so the next findings-bearing PR reproduces the gap exactly. The correction is Prevention item 1.

## Key Decision

**Decision:** Capture this as a Structure lesson and file the routing change as an `/improve-pipeline` candidate, rather than editing `/pre-merge` in this PR.

**Rationale:** The change under review *is* `/pre-merge`'s checklist, and #224's Non-Goals scope this PR to two rows. Adding a re-arm rule to Phase 4 mid-PR would be the same scope drift Dimension 10 exists to catch — inside the PR that adds a dimension bullet about not doing exactly that. The evidence is durable in the entry either way.

**Alternatives considered:** add the re-arm to `/pre-merge` Phase 4 here (rejected — scope, and it deserves its own falsification clause); rely on `/closeout`'s existing delta disclosure (rejected — it discloses at the merge gate, which is where the operator is least likely to reopen review, and it routes to a human rather than to a reader); require it only in loop-mode (rejected — loop-mode already has the property; author-mode is the default and the gap).

**Revisable:** Yes. If a reasonable sample of second rounds finds nothing, the cost is not worth it and Prevention item 2 — requiring findings to name the repair — is the cheaper half to keep.

## Related

- PR #226 — this change; three commits, two of them review-driven
- Issue #224 — the `/improve-pipeline` proposal, whose Mediator verdict scoped the work to two rows
- Issue #227 — filed from round 1's Dim 9 finding; round 2 then found the gap it describes is five commands wide, not one, and that the guard also has false positives. A second instance of the same shape, in a GitHub issue instead of a commit
- `self-review-blind-to-composition-2026-08-13.md`, `by-construction-claims-need-a-mechanism-2026-08-11.md`, `advisory-to-executed-rule-promotion-2026-08-07.md` — see Rule Scope

## Shelf Life

Retire the *instance* half when `/pre-merge` Phase 4 re-arms on a stale review-currency stamp — at that point the gap is closed by mechanism and this entry's evidence has moved into the skill.

The *general* rule outlives it: **a safeguard scoped to one artifact does not cover the artifact written in response to it.** That shape is not specific to code review, and it is the fifth entry in a chain the `by-construction` entry already flagged for consolidation — *a limitation, a source gap, a stamped interval, a verification, or a detection that routes nowhere is a footnote, not a mechanism.* Fold this into that consolidation when it happens rather than deleting it.
