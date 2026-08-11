---
date: 2026-08-07
category: architecture-decisions
problem_type: a rule promoted from advisory-to-human to executed-by-machine keeps evidence and precision that were only adequate for advice
components: [pre-merge, execute, prototype, research]
technologies: [pipeline-design, ai-judges, feasibility-spikes]
severity: medium
volatility: stable
---

# Promoting a rule from advisory to executed changes what evidence and precision it needs

## Problem

A rule that a human reads as a suggestion and a rule that an agent executes are different artifacts, even when the sentence is identical. Promoting one to the other silently raises the bar on two things — how precisely the trigger is defined, and how strong the evidence behind the rule must be — and nothing in the change itself announces that the bar moved.

## Context

Issue #182 proposed a bounded review-response loop for `/pre-merge`: delegate review to a fresh context, disposition each finding as FIX or ESCALATE, apply the fixes, re-review the delta. The proposal was unusually well-supported — four books consulted, an Advocate/Skeptic/Mediator analysis, twelve numbered safety rules, and a FEASIBILITY spike over a real 14-finding corpus.

Two rules inside it were promotions from advisory to executed, and both carried their advisory-era properties across unchanged.

## Symptoms

- A qualifier that reads fine in a sentence addressed to a person (*"for branches with significant `.ts` changes…"*) becomes an undefined threshold the moment an automated caller has to evaluate it.
- A spike's stated limitation sits in writing, is not disputed, and does not narrow the design it was cited to support.
- The design's own supporting evidence, read closely, answers a *different question* than the one the design decision turns on.
- The gap is invisible while the rule is advisory, because a human reader silently supplies the missing precision and the missing judgment.

## Root Cause

**Instance 1 — trigger precision.** `/pre-merge` Phase 3 said: for branches with *significant* `.ts`/`.tsx` changes, mention that `/ts-audit` can be run. Promoting that to "loop-mode auto-invokes it" kept the word *significant*. For a human deciding whether to **mention** a tool, a soft qualifier is correct — the cost of misjudging is one unnecessary sentence. For a loop deciding whether to **run** a tool, it is unevaluable. Every other conditional in the same file names a concrete test (`< 200 changed lines, < 10 files`; `>300/>500/>800 LOC`); this one did not, and nobody noticed because it had never needed to be decidable before.

**Instance 2 — evidence scope, and the more serious one.** The FEASIBILITY spike asked: *can independent fresh-context agents apply this rubric and reach the same classification?* It answered well — 93% unanimous across three classifiers over 42 judgments, zero scattered. That result licenses a claim about **reliability**: the rubric is applied consistently.

The design decision it was cited to support was different: *may the loop act on those classifications?* That turns on **validity**: are the classifications correct? A reliable instrument can be consistently wrong, and this one demonstrably was — the same corpus contained a finding all three classifiers rated high-confidence actionable that was a false positive against an established repo convention. Three independent agents agreeing on a wrong answer is a perfectly reliable, invalid measurement.

**The structural part is what happened next.** The gap was *noticed*. A comment on #182 states it plainly: *"The spike measured whether classifiers agree. It did not measure whether the findings they classify are true — and at least 1 of 14 was not. Finding validity is a separate eval, currently unbuilt."* That sentence was written, published, and never disputed — and the Mediator verdict still specified a loop that acts on findings. The knowledge existed and changed nothing, because nothing connected *"the eval that would justify this is unbuilt"* to *"therefore do not ship the half that depends on it."*

An acknowledged limitation that gates nothing is not a constraint. It is a footnote.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback is between a spike's **stated scope** and the **scope of the design it licenses**. `/prototype`'s FEASIBILITY branch defines a spike as giving "a binary verdict on whether a single technical assumption holds" and says the verdict folds back into the calling artifact — but nothing requires the spike to name *which decision* the verdict authorizes, so a verdict about one question is free to travel to an adjacent question that needs a different one. The delay compounds it: the mismatch surfaces only when the built thing runs, long after the design discussion where citing the spike felt like diligence.

## Rule Scope

- **Applies when** a rule changes from *a human reads it and decides* to *an agent evaluates it and acts*. Both halves matter and both are checkable at review time:
  - the rule contains a qualifier only a human can resolve (*significant*, *large*, *where appropriate*, *when it makes sense*, *if the diff warrants it*); **or**
  - the evidence cited for the rule measures **agreement, consistency, or reproducibility** among judges, raters, or runs, while the decision authorizes an actor to **act** on those judgments.
- **Inverts or does not apply when:**
  - The rule stays advisory. A soft qualifier is the *right* bar for a mention-rule; replacing it with a threshold there is false precision that will misfire at the edges for no benefit.
  - The evidence measures the outcome directly — did the change work, did the test pass, did the deploy hold — rather than measuring whether raters concur about it. Reliability evidence is sufficient when the decision it supports is itself only about *observing* or *recording*.
  - The action is cheap to reverse and immediately visible. The asymmetry that makes this bite is that a wrong automated action is silent and compounds; a wrong suggestion is read and discarded.
- **Sibling docs:** `staleness-gate-intermediate-writers-2026-08-06.md` — the adjacent shape. That entry is about a gate whose correctness depends on actors nobody enumerated; this one is about a rule whose correctness depends on evidence nobody scoped. Both are cases where careful design work aimed one question to the left of the one that mattered.

## Solution

**Instance 1 — give the trigger a decidable test, and keep the soft bar where it belongs.**

Before:

> **TypeScript projects:** For branches with significant `.ts` or `.tsx` changes, mention that `/ts-audit` can be run… Do not invoke it automatically.

After — the mention-rule keeps *significant*; the invoke-rule gets a threshold and a visible skip:

> - **Author-mode and reviewer-mode: mention it, do not invoke it.** … A soft "significant" is the right bar here, because the cost of misjudging it is one unnecessary sentence.
> - **Loop-mode: auto-invoke it** … **Trigger — more than 50 changed `.ts`/`.tsx` lines, or more than 2 changed `.ts`/`.tsx` files.** Below that, skip the audit and record the skip … rather than passing over it silently.

**Instance 2 — split the design along the line the evidence actually supports.**

The loop had two separable halves fused together: *drive the cycle* (re-run the review, remember `/ts-audit`, keep findings from evaporating between sittings) and *decide what to do about each finding*. The first carries no risk of wrong action and was the actual friction. The second carries all the risk and had only reliability evidence behind it.

So loop-mode ships as a recorder: it reviews, attaches the grep or type definition that supports or refutes each finding, writes every finding into a durable ledger on the PR, and hands back. It writes one state, `open`; the operator writes `fixed`, `filed`, `accepted`, or `dropped`.

The deferred half became issue #190 with **entry conditions stated as data the ledger will produce** — finding validity rate, mechanical share, operator disposition mix — and with "close it unimplemented" named as an acceptable outcome. That converts the footnote into a gate: the work cannot start on argument alone.

Three complications dissolved rather than needing answers, which is the usual sign the split was along a real seam. The loop makes no commits, so the review-currency stamp needs no loop-specific rules — a Concern-level defect found in review became moot rather than fixed. There is no autonomous cycle, so there is no pass bound to enforce. Two of the four STPA inadequate-control-action categories collapse, because a controller that never acts cannot act unsafely or report on a half-applied state.

## Prevention

**Code-level:** where a promoted rule has a threshold, pin it against the prose that depends on it. `scripts/test-loop-ledger-markers.sh` does this for the ledger markers, and it earned itself on its first run by catching a template that used `<placeholder>` syntax inside an HTML comment — a `>` there truncates the extraction and silently drops every field after it. A rename-detector would not have caught that; a contract test did.

**Process-level — two changes, both `/improve-pipeline` candidates:**

1. **`/prototype` FEASIBILITY should require the spike to name the decision its verdict licenses**, not only the assumption it tests. A spike that measures inter-rater agreement licenses claims about *consistency*; if the decision turns on *correctness*, the spike has not been run yet. One sentence in the spike's verdict — "this verdict supports X; it does not support Y" — would have caught this at design time rather than at implementation time.
2. **`/improve-pipeline`'s Mediator phase should treat an acknowledged-but-unbuilt eval as a scope constraint**, not a caveat. The rule: if a proposal's own text says the evidence for some part is missing, that part is out of scope for the proposal until the evidence exists. #182 contained the sentence and shipped the design anyway.

## Planning / Calibration Notes

- **What widened the work:** running `/pre-merge` on the change itself. It produced 11 findings, and re-reading them — rather than the findings alone — is what exposed the scope problem. The finding distribution was the evidence: of 7 actioned findings, 3 were mechanical, 2 medium, 2 needed judgment, and one judgment finding changed a cross-skill contract that the proposed rubric would have escalated anyway. So the deferred half would have made ~4 mechanical fixes and then stopped and asked.
- **What tightened the work:** the design work in #182 was not wasted. The rubric, the escalate list, the judge pinning, and the ledger mechanics all survived — they moved to #190 or shipped as-is. Narrowing scope did not mean re-deriving the design.
- **Future planning adjustment:** for any proposal that automates a loop a human currently runs, decompose it into *observe* and *act* before estimating, and ask what evidence exists for each half separately. The two halves usually have very different risk and very different support, and fusing them hides that.

## Actuals Worth Reusing

- **Comparable future work:** any `/improve-pipeline` proposal that moves a step from HITL to automated — the deferred `ralph.sh` review phase is the nearest example, and it defers on identical grounds.
- **Reusable baseline:** on a real review corpus from this repo, roughly **40% of findings were mechanical** (findable by text search), ~30% medium, ~30% required judgment. Treat ~40% as the realistic ceiling on what an auto-fixer could safely take on a markdown-and-prose codebase, before accounting for validity. Compound error at ~40 decisions and 95% per-decision accuracy lands near 13% all-correct, so the ceiling is lower still in practice.

## Key Decision

**Decision:** Ship the observing half of an automation and defer the acting half behind stated evidence conditions, rather than shipping both because the design work for both was complete.

**Rationale:** The two halves have asymmetric risk and asymmetric support. Driving a cycle cannot take a wrong action; deciding can. The available evidence measured agreement, which licenses recording and not acting. The reversal is also asymmetric — adding action to a recorder is easy, removing it after it has silently acted is not.

**Alternatives considered:** Ship both as designed (rejected — the acting half's evidence answers a different question); drop the proposal entirely (rejected — the closed-loop argument is sound and independently valuable, and findings really were evaporating); ship both behind a feature flag (rejected — a flag defaults to on eventually and defers the same decision without producing evidence to settle it).

**Revisable:** Yes — that is the point. #190 states what data would justify the acting half, and the ledger this change ships is the instrument that produces it.

## Related

- PR #188 — implements loop-mode's recording half; its own `/pre-merge` review is the evidence behind the split
- Issue #182 — the original proposal, including the FEASIBILITY spike and the comment that names the validity gap
- Issue #190 — the deferred acting half, with entry conditions and an explicit unimplemented-is-acceptable outcome
- `staleness-gate-intermediate-writers-2026-08-06.md` — sibling shape; see Rule Scope
- `secondhand-source-proposal-specificity-2026-08-11.md` — the same missing edge ("an acknowledged limitation that gates nothing") at the source-gap → proposal-specificity seam

## Shelf Life

Retire the *instances* when they stop being live: instance 1 when `/ts-audit`'s trigger is set from data rather than by analogy, and instance 2 when #190 is either implemented on evidence or closed unimplemented. The general rule — a promotion from advisory to executed raises the bar on trigger precision and evidence scope — outlives both and should migrate rather than be deleted.
