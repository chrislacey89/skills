---
date: 2026-08-13
category: architecture-decisions
problem_type: a defect formed by parts of one commit that are each individually correct, invisible to the author's own review
components: [pre-merge, execute, improve-pipeline]
technologies: [pipeline-design, code-review, multi-agent-review]
severity: medium
volatility: stable
---

# Self-review is structurally blind to composition defects

## Problem

A commit adds several parts. Each one matches the intent that produced it, so each one passes review. The defect exists only in how they compose — and composition was never a unit of intent, so nothing in the author's review is aimed at it.

## Context

PR #220 added a reply round to `/improve-pipeline` Phase 4. Commit `bfc71ab` introduced three things at once:

1. A **discard rule** — a reply that concedes without quoting a claim is thrown out and the verdict written from the opening pair. This creates a new terminal state.
2. A **Verification bullet** admitting two values: the replies appear, or the verdict says "no reply round."
3. A **falsification test**, written into the CHANGELOG: *"If ten runs pass with no trigger, delete the round."*

Each is defensible alone. Together they do not work. The round has four terminal states, not two — the gate did not fire, the round ran and replies were kept, the round ran and a reply was discarded, and degraded mode where the round cannot run at all. States three and four had to be recorded as "no reply round," which loses the state the discard rule exists to catch and inflates the counter the falsification test reads. **The audit built to detect dead ceremony could not read its own most important signal.**

The author's `/pre-merge` pass produced eight findings across three tiers, and this was not among them. It ran the seven dimensions a prose diff can reach — Dimensions 4 and 5 need a PRD, 8 needs a schema or deploy-runtime change, 9 needs a bug fix, so four of the eleven gated themselves off. A reviewer spawned with a clean context — explicitly denied the PR body and the author's findings — returned it as its top Concern in one pass, and the fix was one line.

## Symptoms

- One commit both introduces a state, case, or branch **and** edits the record, counter, or check meant to observe it.
- Every finding in the author's own review is *"this part is wrong."* None is *"these parts disagree."*
- A retirement or falsification test ships in the same commit as the mechanism it is supposed to be able to retire.
- The author's review notes pre-concede a weakness, and the author's own subsequent review rates that weakness no higher than the note already did.

## Root Cause

**Self-review is a comparison against remembered intent.** The author reads each hunk with the reason it was written still in context, so each hunk passes the only test being applied to it. A composition defect has no hunk to point at — it is a property of the set, and the set was never a unit of intent, so no comparison is ever run against it.

A reviewer with no memory of the intents cannot do that comparison at all. Having nothing to check each part against individually, it reads the relations between parts first. The blindness and the sight are the same mechanism seen from two sides.

The second half is a **suppression effect**, and it is the more uncomfortable one. Naming a weakness in author-facing review notes converts it from an open question into a handled item. Here the author flagged one sentence as "a soft instruction" under *known-weak spots*. The blind reviewer promoted the same sentence to a Concern and connected it to two sentences the same PR **deleted for failing the very same test** — a connection the author could not make, having already filed the sentence as disclosed. Disclosure felt like rigor and functioned as a mute.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from *the composition of a commit* back to *the review that reads it*. Each of `/pre-merge`'s eleven dimensions is scoped to one property — deep modules, scope, size, contracts. None asks whether the parts of the diff agree with each other. The delay is what hides it: a composition defect produces no error, because prose has no compiler and the record is only read later, by a future run that has no way to know what it lost.

## Rule Scope

- **Applies when** both hold:
  - a single commit adds two or more parts that interact only through a **third artifact** — a record, a counter, a state enumeration, a retirement condition — rather than through a call a compiler or test would check; **and**
  - the reviewer is the author, or shares the authoring session's context.
- **Inverts or does not apply when:**
  - **The parts interact through a typed interface or a test.** Composition failures surface mechanically, and a second reader buys little. This is a prose-artifact and cross-file-contract problem.
  - **The diff has one part.** There is nothing to compose.
  - **The review is already intent-blind.** The active ingredient is the blindness, not the second reader — a second pass carrying the authoring context reproduces the first (Cohen: N passes by a self-similar reviewer are not N independent reviews).
  - **The commit is large and heterogeneous.** Then the ordinary dimensions fire first and this is not the marginal finding. The effect is sharpest on small, tight, single-purpose diffs, which is the inversion worth remembering: *diff size is the wrong trigger for a blind pass.*
- **Sibling docs:**
  - `deletion-unit-is-function-not-syntax-2026-08-15.md` — **the inverted axis, and the closest sibling.** This entry is about parts *added* whose defect lives in how they compose; that one is about one part *removed* that served more than one purpose. Same blindness, same detection mechanism, opposite direction of change. The shared structure is that the author's unit of attention is the unit of intent, and defects live at the seams that unit does not name.
  - `advisory-to-executed-rule-promotion-2026-08-07.md` — *"an acknowledged limitation that gates nothing is not a constraint. It is a footnote."* This entry is that shape one layer down: not a rule that gates nothing, but a **record that cannot hold the state it exists to observe**.
  - `by-construction-claims-need-a-mechanism-2026-08-11.md` — same family; a claim maintained by hand with nothing constructing it.
  - `secondhand-source-proposal-specificity-2026-08-11.md` — the other half of PR #220's story, and the reason the proposal needed re-adjudicating at all.

## Solution

Spawn a reviewer with a genuinely clean context and **deny it the author's framing**, not just the author's findings:

- Give it: the diff, the review checklist, the repo, and the task statement taken from commit messages.
- Withhold: the author's findings, **and the PR body**. The body carries the summary narrative and the pre-conceded weak spots, and forwarding it reintroduces exactly the suppression described above.
- Ask it directly what an author would be motivated not to see.

Then **reconcile rather than merge the lists**. The blind pass here promoted one finding the author had demoted, demoted two the author had led with, and found three the author had missed entirely. The disagreements were more informative than the overlap.

Do not take the blind pass at face value either. Its Suggestion 5 claimed the two source papers were unreachable because `/library` is book-based; both were in fact installed as library books, and the real gap was narrower — the skill's `sources:` frontmatter. Verify a blind finding before acting on it, the same as any other.

## Prevention

**Code-level:** none available for the general case — the artifact is prose and the check is a judgment. But one specific, cheap check does exist and would have caught this instance: **when a commit both introduces a state and edits the record that observes it, enumerate the states and confirm the record admits each one.** A second, narrower form: when a commit ships a retirement test for the mechanism it also introduces (*"delete this if it never fires in ten runs"*), confirm the counter that test reads can distinguish *the mechanism not firing* from *the mechanism being unable to fire*. Those are different facts and only one of them is evidence.

**Process-level:** issue #199 proposes this fix for `/pre-merge` — an intent-blind lens, with fresh-context review made unconditional rather than size-gated. **This entry is posted as evidence on #199 rather than merely asserting the connection here.** An entry that names a consumer and leaves no trace where the consumer would read it is the footnote `advisory-to-executed-rule-promotion-2026-08-07.md` warns about — and this entry cites that warning, so reproducing it would be self-refuting. The sibling converted its own footnote into a gate by writing entry conditions into #190; this is the same move.

What #199 lacked at the time of writing was a **trigger predicate**, and this instance supplied a candidate: *delegate when the diff introduces a state, case, or branch and also edits the record, counter, or check that observes it — at any size.* That predicate was not adopted. #199's re-adjudication went the other way — delete the trigger rather than sharpen it — on the ground that the party judging *"does this diff touch an observing record?"* is the party whose judgment is under review, and a default is knowledge in the world where any predicate is knowledge in the head (Norman). What shipped is unconditional delegation with a four-class content exemption; see § Shelf Life.

## Planning / Calibration Notes

- **What widened the work:** nothing at implementation time. The widening was entirely in review — the blind pass produced **two** follow-up commits: three edits correcting the state-collapse defect, and a `sources:` frontmatter addition from a second finding. Neither had surfaced under any amount of re-reading by the author.
- **What tightened the work:** the dimensions were sound and needed no change. The variable was the reviewer, not the checklist. This is worth stating because the instinct on a missed finding is to add a dimension.
- **Future planning adjustment:** trigger a blind review pass on **what the diff changes**, not on how large it is. A diff that touches a state machine, a record, a counter, or a retirement condition earns one at any size.

## Actuals Worth Reusing

- **Comparable future work:** any Skill Kit change that introduces a state and edits the artifact meant to observe it — verification bullets, ledger schemas, marker contracts, issue-template slots.
- **Reusable baseline:** on a single observation — treat it as an order of magnitude, not a figure — one blind pass cost roughly 82k sub-agent tokens and under three minutes, and produced both findings that changed the diff. Against a self-review that read the same 34 lines and missed both, that is cheap. Budget it as a default line item for state-touching changes rather than an exceptional measure. The token and duration figures come from the sub-agent's own usage report and are not reconstructible from the repo; the commit counts are (`git log`).

## Key Decision

**Decision:** Spawn a blind reviewer rather than re-running `/pre-merge` in the authoring session.

**Rationale:** `/pre-merge`'s small-diff rule — deleted since, see § Shelf Life — routed a diff under 200 changed lines *and* under 10 files to the main agent, and at 34 lines across 2 files this one qualified on both counts. The skill is explicit that delegation is "first a way to put a clean context in front of the diff, and only second a way to halve wall-clock" — so the rule's *intent* was already independence, and only its *trigger* was a size proxy. That proxy is what failed: it was calibrated to reviewer load, and composition defects do not scale with reviewer load.

**Alternatives considered:** re-run the dimensions in the same session (rejected — a self-similar second pass reproduces the first); ship and rely on `/closeout` (rejected — `/closeout` merges, it does not review); add a twelfth "internal consistency" dimension (rejected — the dimensions were not the failing part, and a dimension read by the author would inherit the same blindness).

**Revisable:** Yes. If a reasonable sample of blind passes stops producing findings the author missed, the independence is no longer buying anything and the size gate can stand.

## Related

- PR #220 — the change and the first two review passes; merged before the third pass's corrections landed
- Issue #217 — the proposal this implements
- Issue #199 — the pipeline fix this entry is posted as evidence on; see Prevention for the trigger predicate it still needs
- `advisory-to-executed-rule-promotion-2026-08-07.md`, `by-construction-claims-need-a-mechanism-2026-08-11.md`, `secondhand-source-proposal-specificity-2026-08-11.md` — see Rule Scope; all three now link back

## Postscript — the third pass

A third blind pass, run on the commit that added this entry, found **six** further defects in it: an inflated dimension count ("all eleven" where four gate themselves off on a prose diff), an undercount of the blind pass's own output (one follow-up commit where there were two — a claim this entry contradicted three paragraphs earlier), a Prevention section that gated nothing while quoting a sibling entry against exactly that, a `sources:` entry claiming a paper the skill body never cited, six restatements of one argument, and two misreadings of the delegation rule this entry criticizes.

That is worth recording plainly rather than quietly fixing: **the entry describing composition blindness contained a composition defect, written by an author who had just finished describing the mechanism.** Knowing the failure mode, naming it, and writing it down did not confer the ability to see it in one's own text. The corrections came from the third reader, not from the author's third reading. If any single fact in this entry deserves to survive, it is that one.

## Shelf Life

**The instance is retired.** PR #222 (2026-08-13) deleted the size gate: `/pre-merge` now delegates review to a fresh sub-agent in all three modes, exempting only four trivial content classes. The gap this entry documented is closed, and the present-tense claims above have been marked accordingly. Read the § Context and § Root Cause as a record of what the gap cost, not as a live description of the skill.

**One prescription did not ship, deliberately.** § Solution says to withhold *the PR body* from the blind reviewer, not just the author's findings, because pre-conceded weak spots function as a mute. #222 forwards the `## Review Notes` block to every sub-agent, which is the opposite. That divergence is adjudicated rather than accidental: Cohen's author-preparation finding and Leveson's measuring-channel rule both argue for keeping re-runnable claims in front of the reviewer, and #199's re-adjudication lists Review Notes explicitly under *what remains unchanged*. The reconciliation is that Cohen's value is captured when the author **writes** the notes, so withholding them from **one** lens among sighted ones costs nothing measured — which is the intent-blind lens, still open on #199 and not shipped by #222. Until that lands, § Solution describes a manual move, not the skill's behavior.

**First evidence on that divergence, and it runs against § Solution.** PR #241 (2026-08-16) added a per-option rule to `docs/next-step-menu.md` and audited five existing menus against it in the same change — author as both rule-maker and grader. Its `## Review Notes` conceded, under *known-weak spots*, that one clause of the new rule was "the one an author can satisfy by assertion rather than by checking." The audit then passed all five menu sites — seven option sets, since `/pre-merge`'s single paragraph carries three — on exactly that clause; two violated it.

Under #222's shipped behavior the notes were forwarded **verbatim** to the blind reviewer, and the disclosure did not mute it — it **aimed** it. The sub-agent quoted the sentence back, went to that clause first, and returned both violations as its top Concern.

**The contrast with the #220 instance above is the whole finding.** There the reviewer was *denied* the PR body and reached the disclosed sentence anyway. Here it was *handed* the disclosure and followed it. Both reached the same place, so on the evidence available the forwarding neither supplied the finding nor suppressed it — which is the narrower claim, and the one two instances can carry. The mute in § Root Cause looks like an author-side effect that does not survive the handoff to a reader with no memory of having filed the item. One instance either way; not settled.

Two details from #241 sharpen § Symptoms rather than adding to them:

- **The disconfirming evidence was not merely nearby — for one menu it was inside the edited line.** `/closeout`'s exit criteria sat nine lines above the menu, which is the ordinary case. `/pre-merge`'s two menus live in a single prose paragraph, so the sibling menu that treated the missing branch as slot-worthy was in the same line being rewritten. Proximity is not the protective factor it feels like.
- **A cheap check that would have caught it:** when a commit authors a rule and applies it, record verdicts **per clause × per site**, not per site. The #241 audit recorded per-site verdicts ("this menu passes"), which lets one clause go unevaluated across every site at once. A grid makes that an empty column.

Round 2 of the same PR's review found the fix for this had itself opened a new defect, and round 3 found the `docs/solutions/` entry written about it was a near-restatement of this one — which is why that entry does not exist and this paragraph carries the lesson instead.

The **general rule** — self-review compares each part against remembered intent and therefore cannot see the set — outlives the fix and should migrate into whatever consolidated form the sibling entries eventually take.

**Postscript to the postscript.** #222 — the PR that closed this gap — shipped its own composition defect, caught by the same mechanism. Its new Phase 4 rule said a refuted finding is not presented; loop-mode runs Phase 4 and its ledger says every Phase 3 finding gets a row with no filtering. A new terminal state, and the record that observes it did not admit it. Third instance in this lineage, in the change that fixes the lineage.
