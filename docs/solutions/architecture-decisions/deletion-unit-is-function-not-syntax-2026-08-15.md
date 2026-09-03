---
date: 2026-08-15
category: architecture-decisions
problem_type: a subtractive change reviewed at the granularity of the deleted syntax rather than the functions that syntax served
components: [execute, pre-merge, improve-pipeline]
technologies: [pipeline-design, prose-artifacts, code-review, subtractive-change]
severity: medium
volatility: stable
---

# A deletion's unit of review is function, not syntax

## Problem

A subtractive change removes a sentence, paragraph, or section that a reader naturally treats as one thing. It was one thing syntactically and two things functionally. The rationale retires one function, the diff removes both, and nothing signals the difference — because a deletion produces no error.

## Context

Issue #231 audited Skill Kit against Ford's *Building Evolutionary Architectures* and returned three deletions of dead prose. Cut A targeted this sentence in `CLAUDE.md` § Writing Conventions:

> To audit, sweep for the `-our`/`-ise`/`-isation` families and the doubled-`l` forms, **then subtract the always-`-ise` verbs** (*supervise*, *exercise*, *promise*, *compromise*, *advertise*, *improvise*, *otherwise*) **and the words that are already correct in both dialects** (*analysis*, *characteristics*, *mechanism*, *fulfillment*, *forwards* as a verb).

The stated rationale was sound and survives intact: the sentence specified a sweep procedure for a runner nobody built, and the rule it served has held for four months with zero automation, so Ford's Rule of Three says the procedure had not earned a script. That reasoning covers the first clause.

It does not cover the second. The bolded half is not procedure — it is a **stop-list**, and it was the only text in `CLAUDE.md` declaring that those seventeen words are already correct American English.

The issue's own change table said *"Delete the 'To audit, sweep for…' paragraph. **Keep the rule, the word list, and the exceptions.**"* The PR body restated that as *"the rule itself, the word list, and the three exception classes all stay."* Both statements were accurate about the three bulleted exceptions at `CLAUDE.md:113–116`, and both missed that the deleted sentence carried a **fourth, unbulleted exception class**. The audit's Mediator had separately flagged Cut A for Chesterton's-fence exposure and accepted the risk — but the risk it priced was *"the method for auditing goes."* Nobody, at any stage, priced the guard.

The author's `/execute` verification swept the tree for dangling references to the deleted text and found one (a pointer in `docs/skill-anatomy.md`), which it fixed. That sweep asked *"does anything still point at this text?"* — the right question for Cut B and Cut C, and the wrong question here. Nothing pointed at the stop-list. Things **relied** on it. A blind reviewer at `/pre-merge`, holding none of the authoring context, returned it as its top Concern in one pass.

## Symptoms

- The diff is net-subtractive and touches prose or config — an artifact with no compiler and no test.
- The deleted unit is one sentence, bullet, or paragraph that reads as atomic, and the authorizing artifact quotes it whole.
- The deletion rationale is a single argument (*"this is dead because X"*) applied to a unit that does more than one job.
- The deleted text contains a seam word — **then**, **and**, **unless**, **except**, **but** — or a parenthetical list. In this instance the seam is literal: *"To audit, sweep for … **then subtract** …"*.
- A term, word list, or exemption declared only in the deleted text still appears throughout the tree afterward.
- Verification asks *"does anything point at this?"* and gets zero, which reads as clean. Reliance is not reference.

## Root Cause

**Deletions are reasoned about at the granularity the text presents, and text presents syntax.** An author deciding whether to cut a sentence asks "is this sentence obsolete?" That question has one answer, so it silently assumes the sentence has one job. Nothing in the sentence's shape announces that it has two.

Additions do not have this failure mode in the same way, because writing text requires enumerating what it should do. Deleting it requires only a reason to stop wanting it — and one reason is enough to license removing everything inside the boundary.

The second half is that **the authorizing artifact inherits the same mistake and then launders it.** #231 was produced by a two-role dialectic with a Mediator, and all three converged on Cut A. That convergence is real evidence — it is why the change was approved — but it is evidence about the *decomposition the proposal offered*, not about whether that decomposition was complete. The Mediator quoted the sentence whole and reasoned about it whole. By the time it reached `/execute`, the quoted text *was* the scope, and the scope gates in Step 0 verify that upstream symbols still exist, never that an upstream deletion list is complete. An approved change set is not a scope oracle for subtractions.

Why it stayed invisible: a removed guard emits nothing. The cost lands arbitrarily far in the future, in a different session, when some agent following `CLAUDE.md:153` (*"Follow the repo-wide American-spelling rule"*) sweeps a file, hits `exercise` or `forwards`, and "corrects" it — with no trace leading back to the PR that removed the warning.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from *a deleted text's functions* back to *the review that authorized the deletion*. Both existing checks are reference-shaped: `/execute`'s dangling-pointer sweep asks who **points at** the deleted text, and its Deletion Completeness rung asks who **emits symbols for** a deleted module. Neither asks who **relies on a declaration** the deleted text was the sole site of. The delay is what hides it — prose has no compiler, so the deletion is silent at merge and the loss surfaces only when a future agent acts on the now-unguarded rule.

## Rule Scope

- **Applies when** all three hold:
  - the change is **subtractive**, and the deleted artifact is prose or config — no type checker, no test, no import graph to enumerate consumers mechanically; **and**
  - the deleted unit is a **syntactic** unit a reader treats as atomic (a sentence, bullet, paragraph, table row, section); **and**
  - the authorizing artifact — issue, RFC, audit verdict, plan — enumerated the deletion by **quoting that unit whole**, so its scope statement and the syntax boundary are the same object.
- **Inverts or does not apply when:**
  - **The deletion is code with a working type checker or test suite.** The compiler enumerates consumers for you and a removed function's callers fail loudly. This is a prose-and-config problem; reaching for it on a typed deletion is ceremony.
  - **The deleted unit genuinely has one job.** Most deletions do. Cut B and Cut C in this same PR each removed exactly one function and needed nothing beyond the ordinary dangling-reference sweep — which is the useful calibration: two of three cuts were fine, so the check must be cheap enough to run on all three.
  - **The change is additive.** There is no prior function set to price.
  - **The deleted text declares nothing that outlives it.** A pure procedure, a pure to-do, a pure pointer — delete freely. The trigger is *declaration or exemption*, not *length*.
- **Sibling docs:**
  - `self-review-blind-to-composition-2026-08-13.md` — **closest sibling, and the inverted axis.** That entry is about parts *added* whose defect lives in how they compose; this one is about one part *removed* that served more than one purpose. Both are invisible to an author reading against remembered intent, both were caught by the same blind-review mechanism, and neither is reachable by a dimension scoped to a single property. Read them as one family: *the author's unit of attention is the unit of intent, and defects live at the seams that unit does not name.*
  - `sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — the same completeness failure in the corrective direction. That entry is about a *sweep* whose enumeration was scoped by the query that found the defect; this one is about a *deletion* whose unit was scoped by syntax rather than function. Both are cases where the boundary the author drew around the work was narrower than the boundary the defect actually occupied.
  - `by-construction-claims-need-a-mechanism-2026-08-11.md` — its Rule Scope inversion (*"the claim is about the repo's own code … write the test; no snapshot needed"*) is the argument for making the Prevention check below mechanical rather than a prose reminder.
  - `advisory-to-executed-rule-promotion-2026-08-07.md` — the family's shared shape, *"a recorded limitation that gates nothing is a footnote,"* and its process-level rule that a proposal's own admitted evidence gap bounds its scope. #231's Chesterton's-fence note is exactly such an admitted gap; it bounded nothing.

## Solution

**The instance.** Restore the stop-list as a fourth bullet under Exceptions — as a *declaration*, not as procedure — so Cut A's goal survives whole: the dead algorithm still goes, the live guard stays.

**Before** (what the deletion left):

```markdown
Exceptions — leave the original spelling:
- Proper nouns, book titles, author names, and quoted material
- Identifiers that must match an external contract: ...
- **Verbatim vendored files.** ...
```

**After:**

```markdown
Exceptions — leave the original spelling:
- **Words that only look British.** The always-`-ise` verbs (*supervise*, *exercise*,
  *promise*, *compromise*, *advertise*, *improvise*, *otherwise*) and the words already
  correct in both dialects (*analysis*, *characteristics*, *mechanism*, *fulfillment*,
  *forwards* as a verb) are American English as written. Do not "correct" them.
- Proper nouns, book titles, author names, and quoted material
- ...
```

**The general move.** Before deleting prose, enumerate what the text *does* — function by function — and check each function against the deletion rationale. If the rationale retires some functions and not others, the deletion is partial and the survivors need a new home. Do this even when an approved change set quotes the text verbatim, because the quote is where the mispricing gets inherited.

Two cheap tells that make this affordable enough to run every time:

1. **Seam words.** A deleted sentence containing *then*, *and*, *unless*, *except*, *but*, or a parenthetical list is a candidate multi-function unit. Split it at the seam and price each half separately.
2. **Sole-site declarations.** If the deleted text is the only place a term, word list, exemption, or threshold is declared, and instances of that thing still exist in the tree, the deletion is partial by definition.

## Prevention

**Code-level.** One mechanical check would have caught this, and it is the prose analogue of `/execute`'s existing consumer-surface sweep rather than a new idea: **for any net-subtractive prose diff, grep the tree for every term, word, or identifier the deleted text declared or exempted. Non-zero matches outside the deleted text mean the declaration outlived its declaration site.** Run here, it is decisive — `exercis*` appears in 11 files, `supervis*` in 9, `otherwise` in 20, `improvis*` in 4, `pre-merge/review-checklist.md:236` uses `forwards` as a verb, and `ubiquitous-language/SKILL.md:91` uses `fulfillment`. Seventeen words still in active use; their only "these are fine" declaration deleted.

Note the direction, because it is what the existing sweep gets backward for this defect class: the author's dangling-reference sweep searched for **the deleted text's name** and found nothing. The right search is for **the things the deleted text talked about**.

**Process-level — filed as #326, half shipped.** `/execute` § Verify has a Deletion Completeness rung, and it did not reach this case on two counts:

1. It fired **only when the slice body contained a `### Deletes` section**. `[improve-pipeline]` issues never carry one — #231 did not — so the rung was structurally unreachable for this entire class of change. **Fixed by #326:** the rung now reads the trigger off the diff (`git diff --diff-filter=DR --name-status "$BASE_REF...HEAD"`), and the header survives only as an optional hint. #326 measured the same unreachability independently at 0 of 274 fulcrum issues.
2. Its five listed surfaces are all *code* surfaces: DOM data-attributes, CSS class names, event names, storage keys, route/config/feature-flag names. All answer *"what symbols did callers emit at this module?"* None answers *"what did this text declare that other text relies on?"* **Still open.** #326's Mediator bounded its change set to the trigger and declined to widen the surface list, so this half is unshipped and the Prevention section below still carries it.

What remains of the proposal: add **sole-site declarations and exemptions** to the surface list, so a net-subtractive *prose* diff is swept for what the deleted text declared and not only for the modules it deleted. A second, smaller one for `/improve-pipeline` itself: its Mediator should treat a quoted deletion as *the proposer's decomposition*, not as a scope oracle — the same move `advisory-to-executed-rule-promotion-2026-08-07.md` already prescribes for admitted evidence gaps.

## Planning / Calibration Notes

- **What widened the work:** the blind review pass at `/pre-merge`, producing one Concern and one follow-up commit. Nothing widened at implementation time — the three cuts landed exactly as specified, all six contract suites stayed green throughout, and the mispricing was invisible to every check that ran before review.
- **What tightened the work:** the issue's precision. #231 quoted all three target passages with locations, and all three matched byte-for-byte. That precision is also what made the error inheritable: an exactly-quoted wrong decomposition reads as an exactly-specified scope.
- **Future planning adjustment:** for subtractive issues, `/execute` Step 1 should enumerate the deleted text's *functions* before editing, not just locate it. Ten seconds per deletion, and it is the only step that would have caught this before review.

## Actuals Worth Reusing

- **Comparable future work:** any Skill Kit change that removes prose from `CLAUDE.md`, `SYSTEM-OVERVIEW.md`, `docs/`, or a `SKILL.md` — which is most `[improve-pipeline]` audit outcomes, since audits characteristically return subtractions.
- **Reusable baseline:** a 13-line, 8-file, net-subtractive diff — three cuts, of which **one in three** carried a second function. Treat "obviously dead prose" as roughly a two-thirds hit rate, not a certainty.
- **Calibration on blind review, worth recording deliberately.** `self-review-blind-to-composition-2026-08-13.md` § Key Decision marks its recommendation *Revisable*: *"If a reasonable sample of blind passes stops producing findings the author missed, the independence is no longer buying anything."* This is the second consecutive instance, on an unrelated defect class, of a blind pass producing a finding the author missed on a small diff. Two is not a sample, but it runs the other way, and the sample only exists if instances are recorded as they occur.

## Key Decision

**Decision:** Restore the stop-list as an exception bullet within the same PR, rather than reverting Cut A or filing a follow-up.

**Rationale:** the deletion had exceeded the scope its own issue approved (*"keep … the exceptions"*), so restoring is a return to the sanctioned change set, not new scope. Rephrasing it as a declaration rather than as procedure preserves Ford's Rule-of-Three argument in full — no script, no sweep, no runner — while returning the guard.

**Alternatives considered:** revert Cut A entirely (rejected — the audit procedure really is dead, and the repo's compliance record supports that half); file a follow-up issue (rejected — it would ship `prod` in a state where a general rule invites a sweep with no stop-list, which is precisely the window in which an agent does the damage); restore the sentence verbatim (rejected — reinstates the dead algorithm the audit correctly retired).

**Revisable:** Yes. If `/execute`'s Deletion Completeness rung is generalized as proposed above, the bullet stays but this entry's Prevention becomes redundant with the pipeline.

## Related

- PR #232 — the three subtractions, the dangling-pointer fix, and the restoration commit
- Issue #231 — the audit; see its "Recommended Changes" row 3 and the Mediator's Chesterton's-fence note
- Issue #157 — tracks the standing audit Cut B removed from `CLAUDE.md`; `docs/skill-anatomy.md` now routes there
- Issue #195 — `docs/solutions/` Shelf Life has no runner; adjacent to Cut C
- `self-review-blind-to-composition-2026-08-13.md`, `by-construction-claims-need-a-mechanism-2026-08-11.md`, `advisory-to-executed-rule-promotion-2026-08-07.md` — see Rule Scope

## Shelf Life

**The instance retires** when `/execute`'s Deletion Completeness rung fires on any net-subtractive diff and lists sole-site declarations among its consumer surfaces. At that point the Prevention section here is superseded by the pipeline and should be cut to a pointer. **Status after #326: first half met, second half not.** The rung now fires on a diff that deletes or renames a module — which is narrower than *net-subtractive*, so a prose diff that removes a declaration without removing a file still does not trigger it — and the surface list is unchanged. The entry stays.

**The general rule outlives that fix and should migrate rather than be deleted:** a deletion's unit of review is function, not syntax — and an approved change set that quotes a syntactic unit has priced the proposer's decomposition of it, not necessarily a complete one. That rule and its sibling in `self-review-blind-to-composition-2026-08-13.md` are two faces of one structure and belong together in whatever consolidated form these entries eventually take.
