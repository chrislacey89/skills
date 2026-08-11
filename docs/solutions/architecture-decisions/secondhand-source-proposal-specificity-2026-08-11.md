---
date: 2026-08-11
category: architecture-decisions
problem_type: a proposal specifies an artifact's details from a secondhand rendering of a primary source it recorded as unavailable
components: [improve-pipeline, prd-to-issues, tdd, pre-merge]
technologies: [pipeline-design, requirements-notation, library-consultation]
severity: medium
volatility: stable
---

# A recorded library gap does not narrow the proposal built without the book

## Problem

`/improve-pipeline` proposals import mechanisms from outside the pipeline. When the mechanism arrives through a *secondhand rendering* — a tool's adaptation of a notation, a blog summary, another framework's implementation — and the primary source is missing from `/library`, the proposal records the absence and then specifies the change at full detail anyway. The renderer's distortions travel into the Recommended Changes table as if they were the source's.

## Context

Issue #197 proposed an opt-in EARS form for slice acceptance criteria. EARS surfaced in a 2026-08-10 competitive audit of 16 frameworks, via AWS Kiro's spec-driven workflow. The proposal did the library consultation honestly: it loaded Wiegers, Shape Up, and Ammann & Offutt, ran the dialectic, and its "Suggested Further Reading" section named the gap outright — *"Easy Approach to Requirements Syntax (EARS) — Mavin, Wilkinson, Harwood, Novak (IEEE RE'09) — the primary source for the notation and its five patterns; the audit relied on Kiro's secondhand rendering of it."* The `library-gap` label was applied. Everything the skill asks for happened.

The Recommended Changes table was then written at full specificity: an exact sentence shape, an exact keyword set, an exact claim about what `/pre-merge` gains. All three came from Kiro.

The book was acquired the next day, 2026-08-11 — one command, one day. Reading it before implementing changed three of the proposal's specifics and one omission:

1. **Syntax.** The proposal's form was `WHEN <condition> THE SYSTEM SHALL <behavior>`. Mavin's is `<preconditions> <trigger> the <system name> shall <system response>` — lowercase `shall`, and the actual system named in the slot. The proposal's own Skeptic Case objected that *"'THE SYSTEM SHALL' fails the repo's own Bar/Beach Test"* — a valid objection aimed at Kiro's all-caps rendering and mistaken for an objection to EARS. Written the paper's way, the objection largely dissolves.
2. **Template set.** The proposal offered two forms, `WHEN` and `IF…THEN`. The paper has five, and the one the proposal's own trigger list needed — it named "state transitions" — is the missing `WHILE`. The paper's most-repeated rule of thumb is that using `When` for sustained behavior is the canonical misuse. Shipping the two-keyword version would have taught the exact error the notation exists to prevent.
3. **Verification claim.** The proposal offered `/pre-merge` a "mechanical hook." The paper explicitly excludes traceability links from scope, and its nearest claim — that explicit triggers make contradictions visible — is flagged in the source as an untested hypothesis, since the case-study corpus contained no conflicting requirements.

Reading it also supplied two things for free that the proposal's Mediator had deferred to a follow-up: a ceremony cap (combine at most two keywords; three means the criterion is two criteria) and the Ubiquitous template, which is the principled reason plain prose stays the default rather than a concession to brevity.

## Symptoms

- A proposal's "Gap in the library" subsection names the primary source *for the mechanism the proposal is adopting*, not merely for background.
- The advocacy leans on a tool's adoption of the mechanism as evidence, where the mechanism's own evidence base is the thing in question.
- A Skeptic objection targets a surface property (verbosity, capitalization, ceremony) that belongs to the renderer's presentation rather than to the mechanism.
- The proposal places the mechanism at a decomposition level the primary source declines to claim — discoverable only by reading the source's scope statement.
- Specifics that came through the renderer are indistinguishable in the table from specifics that came from a read source; nothing marks the provenance of a row.

## Root Cause

`/improve-pipeline` Phase 3.5 step 5 says: *"Graceful degradation. If `/library` is not installed or the index is empty, record 'Library consultation: unavailable' and continue. Do not block filing."* The issue template carries a matching "Gap in the library (not yet available; worth acquiring)" subsection, and Phase 5 applies a `library-gap` label so gaps "accumulate as a visible backlog."

Every one of those mechanisms treats the missing book as a **reading suggestion for a future session**. None of them treats it as a **constraint on the current proposal's specificity**. The Recommended Changes table is written to the same level of detail whether the source was read or paraphrased by a third party, and no field records which.

The graceful-degradation rule is correct for the case it was written for — the library is absent entirely, or the incident has no obvious book, and blocking would kill the proposal for nothing. It silently generalizes to a different case: the library is present and working, and the one book that determines the proposal's specifics is a named, cheap acquisition away.

**This is the second entry in five days with the same abstract shape.** `advisory-to-executed-rule-promotion-2026-08-07.md` closes on: *"An acknowledged limitation that gates nothing is not a constraint. It is a footnote."* That was a spike's stated scope failing to narrow the design it licensed. This is a source gap failing to narrow the proposal it grounds. Same missing edge — from *recorded limitation* to *scope of what may be specified* — at two different seams. Two instances is a pattern worth naming, not yet a systemic claim.

> **Update 2026-08-11 (same day) — a third instance, and it recurred on this entry's own subject matter.** Issue #205 was drafted from `/prd-to-issues` §7's description of the GitHub dependency API rather than from `gh --help`, and its Recommended Changes table specified that `/qa` should copy §7's database-id lookup verbatim. `gh` had shipped a first-class flag for it two months earlier. Both halves of this entry's Rule Scope held: the mechanism arrived through a secondhand rendering (a stale handoff doc, plus §7 as an intermediate rendering of the API), and the proposal specified artifact-level detail the primary source determines. The primary source was a **one-command** gap — the same "one command, one day" cost profile recorded above.
>
> Two details make this instance worse than the two above. The rendering was **internal** — a skill in this repo, which reads as authoritative in a way an external tool's docs do not, so nothing prompted a check. And the near-miss was narrow: the handoff's *line numbers* were verified against the current checkout, which caught that it was stale about **what had shipped** — that finding was simply not generalized one step further, to whether §7 was stale about **how to do it**.
>
> Three instances moves this from "a pattern worth naming" to a systemic claim about `/improve-pipeline` Phase 3.5. The Prevention below is still unimplemented, and the third instance happened while implementing a fix for the second. See `by-construction-claims-need-a-mechanism-2026-08-11.md`, which covers why §7 read as verified in the first place.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from **source availability** to **proposal specificity**. `/improve-pipeline` has a well-built loop from incident → library → dialectic → proposal, and the library step reports its own gaps — into a backlog, not back into the step that consumes it. The delay is what hides it: a proposal filed on a secondhand rendering reads as complete and well-cited, and the mismatch surfaces only at implementation, when someone types the specifics into a file and has reason to check them. If the implementation had followed the proposal directly (a plausible outcome for a table this concrete), the distortions would have shipped and the review that caught them would never have run.

## Rule Scope

- **Applies when** both halves hold:
  - the mechanism the proposal adopts arrives through a **secondhand rendering** — a tool's implementation of a notation or method (Kiro's EARS, a framework's take on an established practice), a summary, or another project's adaptation; **and**
  - the proposal specifies artifact-level details the source determines: exact syntax, the member set of a template/keyword family, thresholds, or a claim about what the mechanism guarantees.
- **Inverts or does not apply when:**
  - **The rendering is the target.** Adopting Kiro's workflow *because you are integrating with Kiro* makes Kiro the primary source. The distortion only matters when the proposal claims the underlying method's authority.
  - **The proposal names a direction without artifact-level specifics.** "Acceptance criteria should carry a condition shape" needs no source read to file; `WHEN <x> THE SYSTEM SHALL <y>` does.
  - **The source is genuinely unavailable** — out of print, paywalled beyond reason, no library entry obtainable. Graceful degradation is then correct and the proposal proceeds; the fix is to mark the dependent rows provisional, not to block.
  - **The mechanism is folklore with no primary source** (a widely-held convention, a community practice). There is nothing to be secondhand *to*.
- **Sibling docs:**
  - `advisory-to-executed-rule-promotion-2026-08-07.md` — same missing edge (a recorded limitation that gates nothing), at the spike-scope → design-scope seam
  - `staleness-gate-intermediate-writers-2026-08-06.md` — the third entry in this chain; a contract spanning two skills with nothing reconciling the halves

## Solution

The proposal was reviewed against the primary source *before* implementing, rather than implemented as written. The review was posted as a comment on #197 naming each deviation and its evidence, so the closed issue and the merged diff can be reconciled by a later reader.

Implementation then followed the corrected set, not the table:

- `prd-to-issues/SKILL.md` — Mavin's syntax (`<condition>, the <module> shall <response>`), three keywords including `While`, the two-keyword cap, and Ubiquitous named as the reason plain prose is the default
- `tdd/SKILL.md` — an EARS criterion arrives pre-partitioned; each keyword clause names a *characteristic*, and a compound criterion names several rather than one block (a correction the source forced — the proposal said the clause "names a block")
- `pre-merge/SKILL.md` — the clause is a search key, described as a reader aid; "mechanical" dropped, because the source does not support it

One further correction was recorded rather than acted on: the proposal deliberately inverts the paper's own scope. EARS scopes itself to *high-level stakeholder requirements* and declines to claim all decomposition levels; the proposal keeps it out of the PRD (that level) and puts it in slice issues (a level the paper does not claim). The inversion is right — Shape Up's roughness constraint governs the PRD and Mavin et al. never faced it — but it is now stated in the PR rather than implied, so a future reader who checks the source does not conclude the proposal misread it.

## Prevention

**Code-level:** none available, and worth saying plainly rather than inventing one — the artifact is prose and the check is a judgment about provenance. The nearest mechanical hook already exists: the `library-gap` label. A proposal carrying that label *and* a Recommended Changes table with syntax, threshold, or template-member specifics is the detectable form of this shape, if it ever recurs often enough to be worth automating.

**Process-level:** in `/improve-pipeline` Phase 3.5, when the mechanism being adopted comes from a secondhand rendering and the primary source is a *named, obtainable* gap, acquire it before filing. This one cost one command and one day against a proposal whose entire substance was the notation's details. When acquisition genuinely is not possible, keep graceful degradation and mark the dependent Recommended Changes rows provisional, so the implementer knows which specifics were never checked against the source. The general form: extend the existing "Gap in the library" subsection from *what to read later* to *what this proposal could not verify*.

## Planning / Calibration Notes

- **What widened the work:** nothing at implementation time — the diff is 10 lines across 3 files. The widening was entirely in *review*: reading the source produced three corrections, one omission fixed, two free additions, and a scope inversion that needed stating. Substantively, the review pass carried more of this change than the implementation did.
- **What tightened the work:** the Mediator verdict was specific enough to implement almost directly — the same note `staleness-gate-intermediate-writers-2026-08-06.md` made, and the property that makes this failure mode dangerous rather than merely untidy. A vague proposal would have forced the source read; a precise one invites being followed.
- **Future planning adjustment:** for `/improve-pipeline` proposals whose mechanism is imported from outside the pipeline, treat "is the primary source in the library?" as a filing precondition on par with the existing repo-context load, not as a reading note appended at the end.

## Actuals Worth Reusing

- **Comparable future work:** any `/improve-pipeline` proposal adopting an external notation, method, or convention — particularly ones surfaced by competitive audit, where the framework being audited is by construction a secondhand rendering of whatever it implements.
- **Reusable baseline:** proposal-to-implementation ratio is inverted for notation adoptions. Expect the diff to be small (10 lines here) and the correctness work to sit almost entirely in the source read. Budget the review, not the edit.

## Key Decision

**Decision:** Review the filed proposal against the newly-available primary source before implementing, and implement the corrected set rather than the table as written.

**Rationale:** the proposal's specifics were the part most likely to be wrong and the part an implementer would copy most literally. One of the four corrections (`WHILE`) would have shipped guidance teaching the misuse the notation exists to prevent.

**Alternatives considered:** implement the table as approved and file a follow-up issue for the corrections — rejected because it would have shipped the `WHILE` omission into the template every downstream slice inherits, and a correction issue competes with all other backlog. Re-run `/improve-pipeline` from scratch on the primary source — rejected as disproportionate; the verdict, the placement, and the dialectic all held, and only the artifact-level specifics moved.

**Revisable:** Yes — if a later `/improve-pipeline` run shows the acquire-before-filing rule blocking proposals on books that turn out to be unobtainable, fall back to marking dependent rows provisional.

## Related

- PR #203 — the implementation, including the three corrections and the scope-inversion note
- Issue #197 — the proposal; its Recommended Changes table still carries the uncorrected syntax, with the review comment naming each deviation
- Issue #81 — the SMART quality-attribute precedent this extends from nonfunctional to behavioral criteria
- `advisory-to-executed-rule-promotion-2026-08-07.md` — sibling shape; see Rule Scope
- `staleness-gate-intermediate-writers-2026-08-06.md` — third entry in the same chain
- `by-construction-claims-need-a-mechanism-2026-08-11.md` — fourth entry; the third instance of *this* entry's shape (issue #205, PR #206) and the reason the internal rendering read as verified

## Shelf Life

Retire the *instance* when `/improve-pipeline` Phase 3.5 gains the acquire-or-mark-provisional rule — at that point this entry documents a closed gap. The general rule (a recorded limitation that constrains nothing is a footnote, not a constraint) is the one this shares with its two siblings and should migrate into whatever consolidated form those three eventually take, rather than being deleted.
