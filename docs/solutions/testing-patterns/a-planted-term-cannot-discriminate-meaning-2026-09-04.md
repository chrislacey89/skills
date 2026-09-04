---
date: 2026-09-04
category: testing-patterns
problem_type: a contract test written to guard a prose contract asserts what the prose means via substring matching, making the test itself a hand-maintained restatement of the prose's semantics — second recording, with the measurement that shows why a planted self-test does not close it
components: [scripts/test-*.sh, contract-test suites, fix-findings, pre-merge, CLAUDE.md]
technologies: [bash, grep, awk, contract-tests, mutation-testing, llm-skills]
severity: high
volatility: evergreen
---

# A planted term cannot discriminate meaning

## Problem

Fourteen independent breaker sub-agents each applied one corpus-drawn mutation
to a branch whose contract suite grepped skill prose for what it *meant*.
Fourteen of fourteen returned `survived`. Four did it by restoring the exact
defect a fix had just removed, with the suite reporting 127 passed, 0 failed.

## Context

This is the **second recording** of
`prose-contract-tests-are-restated-claims-2026-08-27.md`. That entry's
Prevention section already says: *if one surface is "the reader will
understand," assign the property to review — do not write the grep.* It was
eight days old when this branch started. The author ran `/execute` Step 1's
`docs/solutions/` grep with the keywords the task suggested and did not land on
it; `CLAUDE.md` rule (b) then said *pin the claim*, and the author pinned it.

The branch was PR #338, which adds `/fix-findings`. Its suite,
`scripts/test-post-review-edit-lock.sh`, grew to 1,525 lines. Sections 1–10
executed things: they ran the hook body, drove the five documented commands, ran
`/execute` Step 0's gate against real installs. Sections 12–14 mostly grepped
prose: that `/init-pipeline` § 2 "routes Path C past the sections that ask a
human," that "every site states both halves of the auto-invoke condition,"
that a surgery span "starts at" a named anchor. The two buckets are not clean
— section 11's required non-match and digest, section 12's clause counts, and
section 14c's string-absence check executed or compared by identity and were
deleted with the rest; the suite header names each. The line this entry draws
is about the comparison relation, not the section number.

## Symptoms

- A breaker changes `skip § 4, § 5` to `run § 4, § 5 in full` — the inverse
  instruction, the one that deadlocks an unattended run — and the suite stays
  green. The assertion looked for the token `§ 4` inside Path C's clause and
  found it either way.
- A breaker moves a paragraph from above the path labels to below them, same
  words, and the suite stays green. The detector was a prefix scan that set
  `labeled = 1` at the first label and never cleared it.
- A breaker changes `predates the lock` to `already carries the lock` — the
  inverse population — and the suite stays green. The detector recognized the
  second condition by four vocabulary terms, and the mutated sentence still
  contained one.
- **Section 14 carried planted-positive self-tests** (a whole § 14a: three
  planted positives, four near-misses) **and fell anyway.** A planted term
  proves the detector can see the term. It cannot prove the detector can tell
  two meanings of the sentence containing it apart, because a grep has no
  such faculty to test.
- Meanwhile an 18-mutation sweep against sections 1–10 killed every one, and
  across five review rounds no defect on the branch was first found by a suite.
  Every one came from a fresh independent reader.

## Root Cause

A grep decides whether a **term** is present. A meaning-claim is about what the
sentence **says** of that term. "skip § 4" and "run § 4 in full" contain the
same term, so under the grep's comparison relation they are the same input — an
equivalent mutant (Ammann & Offutt, Def. 5.49), and a *decidably* equivalent
one, not the undecidable code-level kind. No amount of planting more terms
changes that: the self-test plants a term, and the defect is a meaning.

The first recording named the class. What it did not have was the measurement
showing that its sibling remedy — *make the narrowness declared and self-tested*
(`mechanism-generality-lags-the-pattern-2026-08-23.md` § Rule Scope) — has a
floor. Declared-and-self-tested closes the gap between a detector's matcher and
its stated reach. It cannot close the gap between a matcher and a *meaning*,
because a self-test for that would itself need to read meaning.

## Learning Level

- **Level:** Structure.
- **Feedback loop or delay:** `CLAUDE.md` rule (b) routes every checkable claim
  to a suite and says "careful reading is not the mechanism." For a claim about
  tool behavior that is correct (#243). For a claim about what a sentence means
  it is exactly backwards, and nothing on the author path distinguished the
  two. The lesson was recorded eight days earlier and the router did not point
  at it — a missing information flow, not a missing fact (Meadows).

## Rule Scope

- **Applies when:** the subject of an assertion is prose that an agent reads
  and acts on, and the property is what the prose *instructs* — routes, skips,
  conditions, ordering, which of two things a sentence says to do.
- **Inverts or does not apply when:** the subject can be **executed** (extract
  the fenced block and run it) or **compared by exact string against a value
  derived from the tree** (`grep -qxF "$x" <<<"$allowed"` where `$allowed` is
  read out of another real file). Both of those held under every mutation on
  this branch; `scripts/test-review-currency-marker.sh`'s closed-vocabulary
  detector killed five. The line is *what the comparison relation can see*,
  not *whether the file is markdown*.
- **Sibling docs:**
  - `prose-contract-tests-are-restated-claims-2026-08-27.md` — the first
    recording. Its Prevention holds the rule; this entry holds the
    measurement and the floor under "self-tested."
  - `mechanism-generality-lags-the-pattern-2026-08-23.md` — "declared and
    self-tested." Correct for matcher-vs-reach; this entry is where it stops.
  - `battery-that-only-perturbs-what-is-present-2026-08-28.md` and
    `authored-mutations-inherit-the-authors-blind-spot-2026-08-28.md` — why the
    author's own 18-mutation sweep reported "killed every one" while an
    independent 24-mutation sweep found four survivors it missed.
  - `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md`
    — the round-2 fix for a vacuous routing assertion checked a token instead
    of a sentence: the corrective hunk did not satisfy the rule it enforced.

## Solution

Delete, do not patch. Commit `8f260dc` removed sections 12–14 and section 11's
two theatrical assertions (a required non-match that could only ever fire for
one term, and a body digest that fired on a comment typo with the same message
as a real change), kept everything that executes, and declared the resulting
gap in the suite header so a reader does not mistake silence for coverage.
Suite: 1,525 → 1,085 lines, 127 → 89 assertions, and every survivor of the
independent sweep is gone.

The property those sections guarded is still true. It is guarded by review.

## Prevention

**Code-level:** none, and that is the finding. The class has no code-level
guard because the guard would have to read meaning. What *is* pinned is the
boundary: `scripts/test-post-review-edit-lock.sh`'s header names each deleted
property and says review holds it.

**Process-level — two mechanisms, both shipped:**

1. **`fix-findings/SKILL.md` Step 1, instruction 2** (commit `153138b`): a
   fixer must grep `docs/solutions/` for the class of thing it is about to
   write *before* writing it — the same move `/execute` Step 1 makes. On this
   branch four fixers wrote the grep the first recording had already said not
   to write. Permitted-to-read was not enough; required-to-read is the change.
2. **chrislacey89/skills#340** (pack-level, filed): scope `CLAUDE.md` rule (b)
   to subjects that can be executed or compared by derived string, and point
   at the first recording as the canonical statement. That puts the lesson on
   the author path at the moment the decision is made, rather than one keyword
   guess away. Verdict: proceed narrowly; no reply round — both checkable
   contradictions between Advocate and Skeptic resolved by reading the tree.

**Defect clustering:** this is the second recording of the 2026-08-27 entry's
pattern. Prose was the deliverable the first time and the pattern recurred
anyway — under an author who had read the pack's rules and followed them. The
two mechanisms above are what makes a third recording not a valid outcome.

## Planning / Calibration Notes

- **What widened the work:** five review rounds and fourteen breaker passes
  spent confirming one fact. The first recording already held it.
- **What tightened the work:** the deletion. Round 5's review found four false
  sentences the deletion left behind and one real gap (the trigger surface
  pinned one extension deep) — all cheap, because the boundary was already
  drawn.
- **Future planning adjustment:** when a slice's verification plan says "pin
  the prose," stop and name the comparison relation. If it is a grep for a
  term, the plan is asking a reader's question of a matcher.

## Actuals Worth Reusing

- **Comparable future work:** any change to a skill's operative prose that
  ships with a contract suite.
- **Reusable baseline:** on a prose artifact, independent readers found every
  defect and suites found none. Budget review rounds, not assertion counts.
  The mechanism that held five rounds running was a fresh sub-agent with no
  session context — 3 auditors, 5 reviewers, 14 breakers — and the thing that
  did not hold was 1,000 lines of grep.

## Related

- PR #338 — the branch; its body records all fourteen verdicts and the four
  inverse mutations
- chrislacey89/skills#327 — the skill whose breaker produced the measurement
- chrislacey89/skills#340 — the rule (b) proposal this entry's second mechanism
- chrislacey89/skills#225, #312 — prior verdicts in the same family; this is
  the case where "self-tested" hit its floor
- `docs/mutation-at-consumption.md` — the breaker's procedure, and the four
  verdicts (`killed` / `survived` / `not-run` / `not-applicable`) every one of
  the fourteen was reported under

## Shelf Life

Evergreen — no expiration condition. A grep will not learn to read.
