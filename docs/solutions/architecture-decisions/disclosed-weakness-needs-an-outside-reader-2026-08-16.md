---
date: 2026-08-16
category: architecture-decisions
problem_type: a weakness the author disclosed in their own review notes, failed anyway, and could only be caught by a reader holding the disclosure
components: [pre-merge, execute, next-step-menu]
technologies: [pipeline-design, code-review, multi-agent-review]
severity: medium
volatility: stable
---

# A disclosed weakness is a lead for an outside reader and a mute for the author

## Problem

An author names a weak spot in their own review notes, ships the change anyway, and the change fails on exactly that spot. The disclosure did not function as a control. It functioned as a receipt.

## Context

PR #241 added a per-option rule to `docs/next-step-menu.md` — Krug's Second Law and his three sources of menu ambiguity — and, in a second commit, audited the five menus already shipped across `/shape`, `/execute`, `/pre-merge`, and `/closeout` against it.

The author's `## Review Notes` block named the risk precisely, under *known-weak spots*:

> The rule's third sub-bullet ("a set with no option for the state the user is actually in") is the one an author can satisfy by assertion rather than by checking. Less mechanically checkable than the other two.

The audit then passed all five menus on that clause. Two of them violated it, and the violations were not subtle:

- `pre-merge/SKILL.md` — the author-mode lesson-emerged menu offered no *merge now, file the finding later* branch, while its sibling menu one sentence later treated that branch as important enough to warrant its own slot and stated the discriminator out loud.
- `closeout/SKILL.md` — the tail menu offered no *close the PRD and slice issues* branch, while the same file's exit criteria nine lines earlier named Step 9 issue-closing as remaining tail work.

Both menus had a free fourth slot, so the convention's own ≤4 cap was not the constraint. The evidence sat in the same file, above the edited line, in both cases.

The independent `/pre-merge` sub-agent returned both as its top Concern in one pass, and said where it got the thread:

> The author's Review Notes flag this sub-rule as "the one an author could satisfy by assertion rather than by checking." That is what happened.

## Symptoms

- A commit both **authors a rule** and **applies it**, so the author is grader of their own homework on a clause only they can interpret.
- The author's review notes pre-concede a weakness, and no subsequent artifact by that author rates the weakness any higher than the note did.
- The clause that fails is the one the author already identified as the least mechanically checkable.
- The disconfirming evidence is in the same file as the change, above the edited line.

## Root Cause

Disclosure and control are different acts, and disclosure is the one that feels like rigor.

Writing "this clause is satisfiable by assertion" converts an open question into a filed item. The cost is paid immediately in felt diligence; the check it names is never scheduled. For the author, the note is *terminal* — it closes the loop it opens. Nothing downstream of the author reads it as a task.

For a reader who did not write the change, the same sentence is *generative*. It names a specific place to push, backed by the author's own admission that they could not verify it. The sub-agent above did not discover the weak clause independently; it was handed a map to it and followed the map.

So the asymmetry is not that disclosure is worthless. It is that **the value of a disclosure is realized entirely by someone other than its author** — which means a disclosure with no outside reader in the loop buys nothing at all.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from *a self-declared weak spot* back to *anything that acts on it*. `/execute` composes the Review Notes; nothing between composing them and merge is obliged to treat a `known-weak spots` line as a work item. The disclosure is a signal emitted into a channel with no subscriber on the author's side of the handoff. The delay hides it: prose has no compiler, so a clause satisfied by assertion produces no error until a human hits the menu months later and has no option to pick.

## Rule Scope

- **Applies when** both hold:
  - the diff **authors a rule, convention, or criterion and applies it in the same change** — the author sets the bar and grades against it, with no external oracle for the grading; **and**
  - at least one clause of that rule is qualitative enough that satisfying it is a judgment rather than a mechanical check.
- **Inverts or does not apply when:**
  - **The rule is mechanically checkable and a check ships with it.** A convention pinned by `scripts/test-*.sh` or a linter is graded by the mechanism, not the author. This entry is about the clauses that resist that treatment, which is why it does not contradict `by-construction-claims-need-a-mechanism-2026-08-11.md` — that entry says build the mechanism where you can; this one covers the residue where you cannot.
  - **The rule and its application ship in separate changes** with a different reader on the second. The separation supplies the outside reader structurally.
  - **The disclosure names a scoping decision rather than an unverified claim.** "Did not add `sources:` frontmatter, here is why" is a decision offered for disagreement and is complete as written. "This clause is satisfiable by assertion" is an admission that a check did not happen. Only the second is a mute.
- **Sibling docs:**
  - `self-review-blind-to-composition-2026-08-13.md` — **the parent, and the closest sibling.** It names this suppression effect (§ Root Cause, second half) from a single instance and folds it into a broader claim about composition defects. This entry is a second instance, isolates the disclosure mechanism from the composition mechanism, and supplies the missing half: what the disclosure does *for the outside reader*. Read that entry for why self-review cannot see the set; read this one for why writing down what you cannot see does not help you see it.
  - `advisory-to-executed-rule-promotion-2026-08-07.md` — *"an acknowledged limitation that gates nothing is not a constraint. It is a footnote."* Same shape, one level up: that entry is about a rule that gates nothing, this one about a **confession** that gates nothing.
  - `by-construction-claims-need-a-mechanism-2026-08-11.md` — see *Inverts* above.

## Solution

There is no author-side fix, and looking for one is the trap — a stronger note is still a note.

**Route every `known-weak spots` line to a reader who did not write it, and let that reader treat it as a work item rather than a disclosure.** The pipeline already does this: `/execute` Step 6 composes the block, `/pre-merge` Phase 2 emits it verbatim into the PR body, and Phase 3 hands it to a sub-agent spawned with none of the authoring context. On this PR that path worked end to end and cost one round trip.

Two properties of the handoff mattered, and both are worth protecting:

1. **The notes were forwarded verbatim, not summarized.** The sub-agent quoted the author's sentence back. A summarization hop authored by the party under review would have been the first thing to drop it.
2. **The reader was independent, not merely second.** A re-read in the authoring session inherits the same filed-and-handled status for the same sentence.

## Prevention

**Code-level:** none for the general case — the artifact is prose and the check is a judgment. One narrower check is available and would have caught this instance: **when a change authors a rule and applies it in the same commit, apply each clause of the rule to each site by hand and record the verdict per clause, not per site.** The audit here recorded per-site verdicts ("this menu passes"), which lets a clause be skipped silently across every site at once. A per-clause × per-site grid makes an unevaluated clause visible as an empty column.

**Process-level: none needed — this is confirming evidence, not a gap report.** Naming a pipeline fix here would be manufacturing one. `/pre-merge`'s unconditional delegation, shipped in #222, is what caught this, on a 48-line diff that the deleted size gate would have routed to the authoring session. The mechanism worked as designed on its intended failure class.

## Planning / Calibration Notes

- **What widened the work:** one review round trip and one follow-up commit (`1d8bf91`), adding two options and re-ordering a third. Small, because the fix was in the same lines already under review.
- **What tightened the work:** the audit had a bounded, enumerable target — five menus, roughly a dozen options — so the reviewer could apply the rule exhaustively rather than sampling. Rules applied against an enumerable set are much cheaper to review than rules applied against open-ended code.
- **Future planning adjustment:** when `/write-a-prd` or `/improve-pipeline` shapes work that *authors a criterion and applies it*, treat the application as a separate reviewable unit from the criterion. They fail independently and the author cannot grade the second.

## Actuals Worth Reusing

- **Comparable future work:** any Skill Kit change that introduces a convention and audits existing call sites against it in the same PR — option-label rules, frontmatter conventions, template slots, naming bars.
- **Reusable baseline:** on this single observation, the blind pass cost roughly 109k sub-agent tokens and under six minutes, and produced the only findings that changed the diff. That is in the same order of magnitude as the 82k/three-minute figure in the parent entry, which is mild evidence the cost is stable across this change class rather than incidental. Token and duration figures come from the sub-agent's usage report and are not reconstructible from the repo; the commit is (`git log`).

## Key Decision

**Decision:** Record this as a distinct entry rather than as a second instance appended to `self-review-blind-to-composition-2026-08-13.md`.

**Rationale:** the parent's claim is about **composition** — parts that each pass and disagree as a set. The disclosure effect appears there as a supporting observation in one paragraph, sourced from one instance. Here the composition framing is available but not load-bearing: the failure is legible as a single unchecked clause, and what generalizes is the disclosure asymmetry, which the parent states only from the author's side.

**Alternatives considered:** append to the parent (rejected — it would bury a falsifiable claim inside an entry already carrying three postscripts, and the parent is long enough that a reader searching for the disclosure effect would not find it); write nothing, since the pipeline caught the defect (rejected — the parent's Shelf Life explicitly flags the Review-Notes-forwarding question as unresolved, and this run is evidence on it).

**Revisable:** Yes. If a later instance shows a forwarded disclosure *muting* an independent reader rather than aiming one, the § Solution claim inverts and this entry should be merged back into the parent as a two-sided observation.

## Related

- PR #241 — the change, the review that caught it, and commit `1d8bf91` — the fix
- Issue #240 — the `/improve-pipeline` proposal this implements
- Issue #199 / PR #222 — unconditional fresh-context delegation; this PR is confirming evidence for it
- `self-review-blind-to-composition-2026-08-13.md` — the parent; see Rule Scope

## Shelf Life

**Evergreen on the general claim** — the value of a self-disclosed weakness is realized by someone other than its author. That outlives any particular skill.

**Revisit the § Solution claim** if `/pre-merge` ever stops forwarding `## Review Notes` verbatim to its sub-agents, or starts summarizing them. Both properties in § Solution are load-bearing, and the parent entry's § Solution argues the opposite case — that forwarding the notes *reintroduces* the mute. This run is one data point against that concern and does not settle it; two entries now disagree, deliberately, and the disagreement is the useful part until more instances land.
