---
date: 2026-08-22
category: testing-patterns
problem_type: an oracle self-check that covers part of its lookup table states a property it does not have, leaving the uncovered arms able to launder a value from the subject
components: [scripts, compound, lefthook, validate-skills]
technologies: [bash, contract-tests, mutation-testing, ci]
severity: high
volatility: evergreen
---

# A self-check that covers part of its table states a property it does not have

## Problem

A contract suite's oracle — the one value it does not read out of the subject — was protected by a self-check that exercised four of the table's nine entries. Rewriting one of the five untested entries to return a value derived from the subject turned a genuine failure into a full green, and the comment directly above the loop asserted the property the loop did not have.

## Context

PR #267 added `scripts/test-q4-mechanism-names.sh` to pin a countable cross-reference in `/compound`: Phase 4 says *"one of the five Q4 names"* about a list declared in Phase 1, so the count is a claim about another passage maintained by hand.

The suite compares a spelled number-word against a parsed count, which means it needs a word→integer table. That table is the only thing in the file not extracted from the subject, so it is the only thing capable of *disagreeing* with the subject — and the suite guarded it exactly as `mutate-the-oracle-not-only-the-subject-2026-08-19` requires, with a self-check running the table against literals before any parse:

```bash
for expect in two:2 four:4 five:5 ten:10; do
    if [ "$(word_to_int "${expect%%:*}")" != "${expect##*:}" ]; then
        fatal "word_to_int(\"${expect%%:*}\") is not ${expect##*:} …"
    fi
done
```

The self-check was also placed deliberately — *above* every read of the subject, so no parsed count is in scope for a mutated arm to launder. That placement was correct and was itself the fix for an earlier defect in the same file.

Expected: the table cannot silently agree with whatever the subject says. Actual: it could, on five of its nine labels.

## Symptoms

Recognizable without knowing anything about the domain:

- A test holds a **fixed lookup table** — a `case`, a dict, a map, a switch — whose values are the test's independent source of truth.
- A **self-check** runs that table against literals, and the literal list is **shorter than the table**.
- A comment above the self-check states an unqualified property (*"there is no parsed count in scope for it to launder"*), where the code establishes it only for the entries enumerated.
- The mutation battery mutated the oracle — and every oracle mutation happened to land on a covered entry.
- The uncovered entries are unreachable *today* and become reachable on an ordinary future edit (the list grows by one, a new register is added).

## Root Cause

A self-check is itself an artifact that can be incomplete, and a partial one is indistinguishable from a total one at a glance. Three things compound:

1. **Sampling and proving look identical in this shape.** `for expect in two:2 four:4 five:5 ten:10` reads as thoroughness. Nothing in the line says the table has nine entries.
2. **The prose overclaims for free.** The comment was written describing the *design intent* (place the check above the parse) and silently inherited a scope the *implementation* did not have. No mechanism relates a claim about "the table" to the table's actual size.
3. **The mutation battery samples too.** It found the covered entries because those are the ones a person writing mutations thinks of first — the same cognitive shortlist that produced the self-check's four entries. Two samples drawn from one intuition are not independent.

The general shape: **a guard whose own coverage is a hand-maintained subset of the thing it guards.** The guard runs, passes, and is trusted in proportion to its appearance rather than its extent.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** a missing feedback loop with a *latency* that hides it. The uncovered arms are unreachable at the moment they are written, so no test, review, or run can distinguish the partial guard from the total one. The gap only becomes reachable on a later, unrelated edit — by which point the guard has been green for months and reads as established. Confidence in the guard grows monotonically while its actual coverage stays fixed.

## Rule Scope

- **Applies when:** a test holds a **finite, enumerable set of constants** as its independent source of truth — a lookup table, an allow-list, a fixture registry, a set of sentinel values, a schema of expected keys — *and* a self-check or setup assertion exercises that set by listing members literally. The tell is that the set and the list of members exercised are written in two places and agree only because someone made them agree.
- **Inverts or does not apply when:** the set is not enumerable from the test (values generated at runtime, read from the environment, or supplied by a property-test generator) — there is no total coverage to demand, and the right instrument is a generator invariant, not an enumeration. It also does not apply when the "table" has one entry, where partial and total coincide. And it does not reach a self-check that is deliberately a **smoke** check of a large table (thousands of entries) where the cost of totality is real — but that case needs the sampling *declared*, because the failure here was not sampling, it was sampling silently while the prose claimed totality.
- **Sibling docs:**
  - `mutate-the-oracle-not-only-the-subject-2026-08-19.md` — the direct parent, and the entry this one refines. Its rule (*mutate the oracle, not only the subject*) was **followed** in #267: the oracle was mutated twice and both mutations were caught. They landed on covered labels. This entry is the failure one step past that remedy — a battery samples, and against a partially-covered guard, sampling is what decides whether the hole is found.
  - `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — the grandparent family. Its class is *a property asserted with nothing constructing it*; here the property was asserted in a comment over a loop that constructed four-ninths of it.
  - `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — the mechanism written for *this* entry reproduced this entry's own defect on its first draft. See Solution.

## Solution

**Make the coverage total, and make totality checkable from outside.**

**Before** — four of nine labels, and a comment claiming the whole table:

```bash
# Up here there is no parsed count in scope for it to launder.
for expect in two:2 four:4 five:5 ten:10; do
```

**After** — every label, in every table:

```bash
for expect in two:2 three:3 four:4 five:5 six:6 seven:7 eight:8 nine:9 ten:10; do
```

Fixing the one file is the instance. The mechanism is `scripts/test-oracle-table-coverage.sh`, which scans every `scripts/test-*.sh`, finds each `case "$1" in` lookup function, extracts its labels and the literal keys of the self-check loop that calls it, and requires set equality. A lookup table with **no** self-check fails too. It is wired into `lefthook.yml` and `.github/workflows/validate-skills.yml`.

**The mechanism shipped this entry's own defect on its first draft, and the oracle mutation caught it.** The scanner treated "found zero tables" as a legitimate pass — defensible in the abstract, since a repo need not contain any. But mutating the case-detection regex made the scan find nothing and the suite reported **full green**: the vacuous pass this entire family exists to abolish, reproduced inside the file written to abolish it. The fix is a declared floor (`MIN_TABLES`) that turns a detector regression into a `FATAL`. Lowering it is still possible and is deliberately a *visible edit to a named constant* rather than a silent condition — verified: lowering the floor **and** breaking detection does pass, which is the intended escape.

This is a fourth instance of `sweep-commits-reintroduce-their-own-defect-class`, and like the third it falls outside that entry's stated preconditions — it is a fresh artifact rather than a corrective sweep. Filed here for that reason; noted there as evidence for promoting it from Pattern to Structure.

## Prevention

**Code-level.**

1. **A self-check over an enumerable set must enumerate all of it.** Not a representative sample — the whole set. If that is genuinely impractical, the sampling is declared in the code, not implied by the absence of a statement.
2. **Derive the coverage instead of restating it, where the language allows.** Iterating the table's own keys removes the two-places problem entirely. `test-q4-mechanism-names.sh` still lists literals, because the literals *are* the independent values — deriving them from the table would make the check tautological. That tension is real and is why the external scanner exists: when you cannot derive, check from outside.
3. **Read every comment above a guard as a claim, and check its scope against the code beneath it.** The comment here was true of the design and false of the implementation. That gap is invisible unless you deliberately compare the two.

**Process-level.** Extend the mutation-battery coverage rule that `mutate-the-oracle-not-only-the-subject` established. That rule requires at least one oracle mutation. Add:

> **Oracle mutations must be chosen adversarially against the guard's coverage, not from intuition.** Before writing them, ask which parts of the oracle the self-check does *not* exercise, and mutate there first. A battery drawn from the same intuition that wrote the guard tests the same region twice.

The checkable trigger, shaped to be asked of one line — the form the parent family requires, because its Shelf Life records that consolidation written as more prose produces another instance:

> **"This guard protects N things. How many does its own check touch?"**

If the answer is not "all N," or you cannot say what N is, the guard is not yet established.

## Planning / Calibration Notes

- **What widened the work:** two review rounds, each finding a defect *inside* the mechanism rather than in the change it guarded. The mechanism, not the feature, carried the risk — the skill-prose edits were correct in the first draft.
- **What tightened the work:** the adversarial mutation habit already required by the sibling entry. Every defect here was found by mutation, not by reading. Two independent review agents reading the same file did not find the partial-coverage gap; running a mutation against an uncovered arm did, immediately.
- **Future planning adjustment:** when a slice's deliverable is *a contract test*, budget the review for the test as the primary artifact. Three of the four defects in PR #267 were in the mechanism.

## Actuals Worth Reusing

- **Comparable future work:** any `scripts/test-*.sh` added under `CLAUDE.md` rule (b).
- **Reusable baseline:** a contract suite pinning a cross-reference costs roughly its own length again in mutation work, and the mutation battery finds defects the reading passes do not. Budget ~20 mutations split subject/oracle for a suite of this size; expect one or two to land on the suite itself.

## Defect Classification

**Origin phase:** Design error — the self-check's placement was reasoned about carefully and its extent was not.
**Fix type:** Correction. The instance is fixed by full enumeration; the class is fixed by an external scanner that cannot be satisfied by a partial self-check.

## Related

- PR #267 — `/compound`'s pack-level filing mechanism, where this surfaced
- Issue #266 — the driving proposal
- `mutate-the-oracle-not-only-the-subject-2026-08-19.md` — parent entry
- `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — grandparent family

## Shelf Life

Evergreen — no expiration condition. The rule is about the relationship between a guard and its own coverage, not about bash, `case` statements, or this repo's suites. `scripts/test-oracle-table-coverage.sh` is bash-and-`case`-specific and *will* need extending if a suite adds a lookup table in another shape; that is a gap in the mechanism, not in the lesson. If this entry is ever superseded, it should be by a consolidation with its parent and grandparent — the family now has three rungs describing one thing: **an artifact that establishes less than it appears to.**
