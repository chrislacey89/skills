---
date: 2026-08-06
category: architecture-decisions
problem_type: staleness gate invalidated by an unenumerated intermediate writer
components: [pre-merge, closeout, compound, SYSTEM-OVERVIEW]
technologies: [github-pr, gh-cli, pipeline-design]
severity: medium
volatility: stable
---

# A staleness gate is defined by the interval it spans, not by the two steps at its ends

## Problem

Issue #163 added a review-currency gate: `/pre-merge` stamps the head SHA it reviewed into the PR body, and `/closeout` compares that stamp against the current head before merging, so a diff that grew after review is not merged unreviewed. The gate is correct for the seam it was designed against. It is also tripped, on the pipeline's own documented happy path, by `/compound` — the step that runs *between* the two.

## Context

`/compound`'s default is in-PR: it commits a `docs/solutions/` entry onto the open PR branch and pushes, so the lesson is reviewed and merged with the code that taught it (`compound/SKILL.md:274-279`). That push moves the PR head past the stamp `/pre-merge` just wrote. So on every PR carrying a lesson — which is to say, every PR that runs the full documented flow — `/closeout` reports a divergence and interrupts with a `git diff --stat` and a three-option question.

The delta it interrupts on is a single markdown file that the pipeline itself just authored. That is the most predictable and least risky post-review addition possible, which makes it the worst possible thing to interrupt on: it trains the exact reflexive click-through that #163's Skeptic Case warned about, on the path users travel most.

Worth noting where the design effort actually went. #163's Mediator verdict took the noise problem seriously and tuned hard against it — show `git diff --stat` so the response scales to the delta's *magnitude*, never hard-block, pass silently when the SHAs match. Every one of those mitigations assumes the noise source is a *human* committing something small after review. None of them consider that the pipeline itself is a writer in that interval. The care was real; it was aimed one actor to the left of the problem.

## Symptoms

- A gate that "works" in isolation fires on the pipeline's normal flow rather than on the anomaly it was built to catch.
- The false positive is intermittent and delayed — it appears only at merge time, and only on runs that happened to produce the intermediate write — so it reads as "this gate is noisy" rather than "this gate has an unenumerated writer."
- Design discussion for the gate names exactly two skills, matching the two endpoints of the interval.

## Root Cause

A stamp-then-compare staleness gate asserts that a guarded artifact is unchanged between time T1 (stamp) and T2 (check). Its correctness therefore depends on the **complete set of actors that can write to that artifact during the interval** — not on the two skills sitting at the endpoints.

The structural reason that set went unenumerated: `SYSTEM-OVERVIEW.md` presents the pipeline as a linear chain, and for most of its life the canonical chain read `/pre-merge → /closeout`. In-PR `/compound` was a later change that inserted a writer between them. A designer reading the chain to find "which step comes after `/pre-merge`" gets a *sequencing* answer, and sequencing is not the question a staleness gate asks. The gate's question is "who can write in this interval," and the linear rendering makes any out-of-order or interstitial writer structurally invisible at design time.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback is between *gate design* and *the set of writers on the guarded artifact*. Nothing in the design process forces that enumeration, and the pipeline's canonical documentation actively biases toward adjacent-pair reasoning. The delay compounds it — a false positive surfaces only at merge time on a subset of runs, long after the design decision, and arrives labeled as noise rather than as a design defect. That mislabeling is what makes the loop self-defeating: the natural response to a noisy gate is to relax or ignore it, which removes the signal without ever finding the unenumerated writer.

## Rule Scope

**Applies when** adding a gate that stamps state at one pipeline step and compares it at a later one — review currency, freshness checks, "has the artifact changed since," cache or snapshot invalidation, approval-still-valid checks — **and** the guarded artifact is mutable by more than one actor.

Under those conditions, treat the **interval** as the unit of analysis rather than the pair of steps at its ends. Before shipping, enumerate every actor that can write the guarded artifact between stamp and check, mechanically rather than from memory:

```bash
# The guarded artifact here is "commits on the open PR branch."
# Ask which pipeline actors write it, rather than recalling which ones ought to.
grep -ln "git push" */SKILL.md
```

Then classify each intermediate writer explicitly as **benign** (auto-acknowledge with a stated reason, do not prompt) or **invalidating** (prompt, or have that writer re-stamp). A writer left unclassified defaults to invalidating, which is how a gate acquires its first false positive on the happy path.

**Inverts or does not apply when:**

- The guarded artifact is written *only* by the stamping actor — then the pair genuinely is the interval, and this enumeration is ceremony.
- The stamp and the check are synchronous (same session, no yield to other steps) — there is no interval for another writer to occupy.
- Every write during the interval is genuinely unreviewed scope. Then interrupting on all of them is the correct behavior and classifying would only weaken the gate. The discriminator is not "is this write small" but "does this write come from an actor whose output was already subject to the guarantee the gate protects." A `/compound` entry rides the PR precisely so it *will* be reviewed; a hand-added feature commit does not.

**Sibling docs:** `advisory-to-executed-rule-promotion-2026-08-07.md` — the adjacent shape. This entry is about a gate whose correctness depends on actors nobody enumerated; that one is about a rule whose correctness depends on evidence nobody scoped. Both are cases where thorough design work aimed one question to the left of the one that mattered, which suggests the shared defect is *not* insufficient rigor but an unasked question. Adjacent shape still worth watching: gates that compare against a *research* artifact rather than a PR, where `/correct-course` is the interstitial writer.

## Solution

**Before** — the gate treats any head movement as divergence:

```
stamped SHA != current head  ->  print git diff --stat, prompt (re-review / acknowledge / stop)
```

Correct for hand-added scope. Fires on `/compound`'s documented in-PR commit.

**After** — classify the known intermediate writer, keep everything else interrupting:

```
stamped SHA != current head
  -> if the delta's files are confined to docs/solutions/:
       note in one line ("post-review delta is a /compound entry — rides this PR for review"), continue
  -> otherwise:
       print git diff --stat, prompt (re-review / acknowledge / stop)
```

The alternative shape — have `/compound` re-stamp the PR after pushing — also works and is arguably more principled, since `/compound`'s entry genuinely was reviewed by riding the PR. It was not chosen because it adds a second writer to the stamp, and a single-writer invariant is what makes "which SHA was reviewed" unambiguous.

**Status:** the heuristic above is the durable lesson and stands on its own. The specific remediation was identified during `/pre-merge` review of PR #183 and is **not applied as of this entry** — it is carried as a named Concern on that PR.

## Prevention

**Code-level:** when a gate's contract spans two skills via a marker string, add a consistency check to the repo's existing test harness (`scripts/test-*.sh`) so the writer's emitted format and the reader's parser cannot drift apart silently. Absent that, a broken contract is indistinguishable from a legitimately un-stamped artifact — both take the "no stamp found" branch.

**Process-level:** add an enumeration step to `/improve-pipeline`'s Mediator phase. When a proposal adds a gate comparing state across two pipeline steps, require the proposal to list every skill that writes the guarded artifact in the interval and classify each as benign or invalidating. #163's Advocate, Skeptic, and Mediator sections all did real work on the noise question and still shipped this, because none of them was prompted to ask "who else writes here."

## Planning / Calibration Notes

- **What widened the work:** nothing at implementation time — the two file edits landed clean. The widening is latent: the gate needs a third edit before it behaves correctly on the default path, and that edit was discoverable only by reading a *third* skill the issue never named.
- **What tightened the work:** the issue's Mediator verdict was specific enough to implement almost directly, and the marker contract was cheap to verify end-to-end against a real PR.
- **Future planning adjustment:** for pipeline-gate proposals, `/research` and `/improve-pipeline` should treat "enumerate the writers in the interval" as a required scan, on par with the existing omitted-activities scan. Reading the canonical chain for sequencing is not the same as reading it for concurrency.

## Key Decision

**Decision:** Analyze staleness gates over the interval they span, enumerating intermediate writers mechanically, rather than over the pair of steps at the interval's endpoints.
**Rationale:** The gate's correctness is a property of the interval. Adjacent-pair reasoning is what the linear pipeline documentation invites, and it is structurally incapable of seeing an interstitial writer.
**Alternatives considered:** Relying on reviewer judgment to notice the collision (fails silently — three review sections in #163 missed it); tuning the gate's noise threshold harder (treats the symptom and degrades the real signal).
**Revisable:** Yes — if the pipeline ever gains a registry of which skills write which shared artifacts, the enumeration becomes a lookup instead of a discipline, and this entry reduces to a pointer at that registry.

## Related

- PR #183 — implements #163's review-currency gate; carries the unremediated Concern
- Issue #163 — the `/improve-pipeline` proposal, including the Advocate/Skeptic/Mediator analysis that missed the intermediate writer
- Issue #182 — bounded review-response loop; treats the reviewed-SHA stamp as a hard prerequisite

## Shelf Life

Retire this entry when the pipeline gains an explicit artifact-writer registry that makes intermediate-writer enumeration mechanical, or when in-PR `/compound` stops committing to the PR branch. The general heuristic — a staleness gate is defined by its interval, not its endpoints — outlives both and should migrate rather than be deleted.
