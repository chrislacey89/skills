---
date: 2026-09-09
category: testing-patterns
problem_type: a mutation reported as a prose description rather than as the literal edit is not re-runnable, so independent parties mutate different things, get different numbers, and each uses their own number to judge another's verdict
components: [scripts/test-documented-git-commands.sh, pre-merge/review-checklist.md, docs/mutation-at-consumption.md, fix-findings/SKILL.md]
technologies: [bash, git, parameter-expansion]
severity: high
volatility: evergreen
---

# A mutation described in prose is not re-runnable, and its verdict is unfalsifiable

## Problem

A mutation is run, its result is recorded, and the record names the mutation in
prose — *"weakening `:?` to `:-origin/prod`"* — rather than quoting the line that
was actually edited. Every later party re-runs *their* reading of that phrase,
gets a different number, and concludes the original was wrong. Nobody is
careless and nobody can be shown to be right.

## Context

PR #355 (issue #354) added set-but-empty runs to two `${VAR:?}` fail-fast
guards. A `/fix-findings` round then produced `827612e`, whose message justified
the scope of a declared-gap note with a measurement:

> the default-value mutant (`:?` weakened to `:-origin/prod`) still goes red
> (175 passed, 6 failed) under the existing assertions

Four parties measured that mutant. The mutation site was unambiguous —
`pre-merge/review-checklist.md:114` holds the only `${BASE_REF:?}` in the repo —
and the suite is deterministic. They still disagreed:

| Party | Reported |
|---|---|
| the fixer (`827612e`) | 175 passed, 6 failed |
| the breaker | 178 passed, 3 failed |
| the controller | 175 passed, 6 failed |
| the delta reviewer | 179 passed, 2 failed |

Re-measured afterwards, holding the *edit* fixed rather than the phrase:

| The literal edit | Result |
|---|---|
| guard line → `: "${BASE_REF:-origin/prod}"` | 179 passed, 2 failed |
| guard line deleted **and** the range changed to `"${BASE_REF:-origin/prod}...HEAD"` | 175 passed, 6 failed |
| guard line → `: "${BASE_REF:=origin/prod}"` | 177 passed, 4 failed |

All three are faithful readings of "weakening `:?` to `:-origin/prod`." One of
them is a two-line edit the phrase does not mention. Together they account for
three of the four reported counts — the fixer's and the controller's `175/6`
are the same two-line edit, and the delta reviewer's `179/2` is the first row.

The breaker's `178/3` is not a fourth reading: it is the first row's edit
re-run in a `git archive` copy with no `.git`, where a ref-lookup test that
cannot resolve there fails on its own, one failure short of what the guard
mutation adds. The breaker and the delta reviewer ran the identical edit and
reported different counts — there the counts were the conflict, not the
mutants.

## Symptoms

- Two parties report different counts for a mutation they both name the same way,
  against a deterministic suite in a clean tree.
- A verdict is overturned by a re-measurement, and the re-measurement is itself
  overturned later.
- A dispute about a mutation's *result* cannot be settled by re-running it,
  because re-running it requires re-deciding what it was.
- The mutation record contains a verb — *weakening*, *relocating*, *deleting* —
  where the edit's two versions should be.

## Root Cause

`docs/mutation-at-consumption.md` governs which mutation to choose (draw it from
the corpus) and when a verdict may be stated (validate the apparatus first). It
says nothing about how the mutation is **recorded**, so the record defaulted to
prose — and a prose description of an edit is a specification with more than one
implementation.

The mutation's whole epistemic value is that a second party can reproduce it. A
description that does not determine the edit converts a reproducible measurement
into an assertion, which is the thing mutation testing exists to replace.

The failure then compounds, because each party's number *feels* like independent
confirmation:

- The controller re-measured, got `175/6`, matched the fixer's number, and
  overturned the breaker's `survived` verdict on that basis. The controller had
  mutated two lines; the phrase named one. The agreement was coincidence.
- The breaker got `178/3` in a `git archive` copy with no `.git`, and diagnosed
  the discrepancy against the delta reviewer's `179/2` as `origin/prod` failing
  to resolve there. That diagnosis was incomplete, not wrong: the `.git`-less
  copy fails exactly one ref-lookup test before the mutation runs, which is the
  whole delta between `178/3` and `179/2`. It does not reach why the guard
  mutation survives at all — that `:-` substitutes without assigning, so
  `$BASE_REF` is still empty on the next line and the `^[DR]` assertions keep
  passing.

One of the four judgments in that chain was unsound — the controller's, which
overturned a correct verdict on a coincidental number match — and it was made
confidently by a party that had genuinely run a suite. The breaker's verdict
was right, and its diagnosis, while incomplete, was not unsound.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** Missing feedback. A mutation record is written once
  and read by parties who cannot query its author. Nothing in the loop compares a
  re-run against the original edit, so a divergence surfaces as a disagreement
  about the *code* rather than about the *record* — and the parties then spend
  their effort re-measuring instead of re-reading.

## Rule Scope

- **Applies when:** a mutation's result is recorded for a reader who was not
  present when it ran — a commit message, a code comment, a breaker verdict, a
  review finding, a `docs/solutions/` entry — **and** the mutation is an edit to
  a text file rather than a named, already-versioned artifact.
- **Inverts or does not apply when:** the mutation is applied by a committed
  script or fixture that the reader can run by name (`scripts/test-*.sh`'s own
  self-test hunks, a checked-in mutant file). There the artifact *is* the record
  and quoting it inline would be a second operative site — see
  `docs/restated-claims.md`. It also does not apply to a `not-applicable`
  verdict, where no edit was made. And it does not reach an instrument
  divergence: the breaker and the delta reviewer quoted the identical hunk and
  still got different counts, because the breaker's copy lacked something the
  check silently depends on and the delta reviewer's did not. Closing that gap
  is `validate-the-instrument-not-only-the-subject-2026-08-23.md`'s job, not
  this one's — recording the edit tells a reader what ran, not whether their
  environment will reproduce the number.
- **Sibling docs:**
  - `authored-mutations-inherit-the-authors-blind-spot-2026-08-28.md` — where the
    mutation's *content* comes from. Distinct: that entry is about a battery
    whose shapes are all imagined by one mind. This one is about a single
    mutation that was drawn correctly and reported irreproducibly.
  - `validate-the-instrument-not-only-the-subject-2026-08-23.md` — the breaker's
    `.git`-less copy is an instance of that entry, and the two co-occurred here
    rather than one masquerading as the other: the instrument fault accounts
    for the one-test gap between the breaker's `178/3` and the delta reviewer's
    `179/2` on the identical edit; the ambiguous record accounts for the rest —
    why three parties ran three different edits for one phrase in the first
    place.
  - `dead-guards-report-coverage-they-do-not-have-2026-08-27.md` — a comment
    asserting a verification that was never run. Here the verification *was* run.

## Solution

Record the mutation as the **literal before and after text of the edited line**,
with its file and line, beside the verdict. The verb goes in the prose; the two
versions go in the record.

**Before:**

```
the default-value mutant (`:?` weakened to `:-origin/prod`) still goes red
(175 passed, 6 failed)
```

**After:**

```
pre-merge/review-checklist.md:114
- : "${BASE_REF:?resolve it with the Phase 1 detection block before running this}"
+ : "${BASE_REF:-origin/prod}"
→ scripts/test-documented-git-commands.sh: 179 passed, 2 failed
```

Nothing about the second form requires more work — the edit was in the editor's
buffer either way. It requires only that the record be a copy rather than a
paraphrase.

Two consequences worth naming. A multi-line mutation is now visibly multi-line,
so the controller's two-line edit could not have been mistaken for the fixer's
one-line one. And a party who disagrees can apply the recorded hunk instead of
re-deriving it, which turns "you measured wrong" into a diff.

## Prevention

**Code-level: none, and the reason is the finding one level up.** The rule is
"the record must determine the edit," which is a claim about meaning — a
substring check for a `-`/`+` pair would pass on any record that happens to be
formatted that way and fail on a correct one that is not, which is the
restated-claim shape `prose-contract-tests-are-restated-claims-2026-08-27.md`
names and `chrislacey89/skills#340` is open to scope out of `CLAUDE.md` rule (b).
Of the five Q4 names, a contract test came closest and was rejected on that
ground; writing it would have made this the fifth instance of the very defect
class the PR it sits on exists to fix.

**Process-level:** `docs/mutation-at-consumption.md` § *Record the mutation as
the edit, not as a description of it* — added in the same commit as this entry.
It is the canonical statement, bundled into `/execute` and `/fix-findings` via
`scripts/skill-references.manifest`, so both the author-time rung and the
breaker's procedure reach it without a second operative site.

The honest accounting: this is prose, and this repo's own corpus records that
prose was the deliverable for a related class and the pattern recurred anyway.
The claim here is narrower than "a warning will hold" — it is that the canonical
doc previously had no statement at all on this axis, so the failure mode was not
a rule being ignored but a rule not existing.

## Planning / Calibration Notes

- **What widened the work:** one `/fix-findings` round and one delta review spent
  disputing a number, when most of the disagreement was about which edit had
  run, not the arithmetic. Four measurements: one judgment built on them — the
  controller's — was unsound, and one diagnosis of them — the breaker's — was
  correct but incomplete.
- **What tightened the work:** holding the *edit* fixed and re-running all three
  readings side by side settled it in a single command. That move — enumerate the
  readings, run each — is the general one when two parties disagree about a
  deterministic measurement.
- **Future planning adjustment:** when a review round turns on a measured count,
  the first question is "what exactly was edited," not "who measured wrong."

## Defect Classification

**Origin phase:** Specification error — `docs/mutation-at-consumption.md`
specifies choosing and validating a mutation, and never specifies recording it.
**Fix type:** Correction. The missing specification is added at the canonical
site rather than at any of the places that suffered from its absence.

## Related

- PR #355 / issue #354 (chrislacey89/skills) — the branch this surfaced on
- `docs/mutation-at-consumption.md` — the canonical rung this entry adds a
  section to
- `docs/restated-claims.md` — why the section is added once rather than in both
  consuming skills
- `chrislacey89/skills#340` — the open proposal to scope `CLAUDE.md` rule (b)
  away from meaning-claims, which is what makes the Prevention above "none"
  rather than a contract test

## Shelf Life

Evergreen — the boundary is categorical. A description of an edit admits more
than one edit for as long as descriptions are prose.
