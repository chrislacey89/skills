---
date: 2026-08-23
category: testing-patterns
problem_type: a mechanism built to catch a pattern is written against the syntax of the instance that produced it, so the pattern recurs in a different shape and the mechanism stays silent
components: [scripts, tdd, execute, lefthook, validate-skills]
technologies: [bash, contract-tests, mutation-testing, ci]
severity: high
volatility: evergreen
---

# A mechanism inherits the shape of the instance that produced it, and the pattern does not

## Problem

`scripts/test-oracle-table-coverage.sh` was built to abolish "a guard whose own coverage is a hand-maintained subset of the thing it guards." It detects `case "$1" in` lookup tables, because that is the shape the incident behind it had. The very next contract suite added to this repo reproduced the same pattern in a different syntax — a hand-listed set of *files* rather than a partial lookup table — and the mechanism was silent throughout.

## Context

`partial-oracle-selfcheck-2026-08-22.md` shipped three days before this. It is `volatility: evergreen`, it names the general shape explicitly, its Prevention #2 is *"derive the coverage instead of restating it, where the language allows,"* and it closes with a one-line trigger question meant to be asked of any guard: **"This guard protects N things. How many does its own check touch?"**

PR #271 (issue #268) then added `scripts/test-widened-domain-tell.sh`, the first `scripts/test-*.sh` in this repo since that entry landed. Its job is to pin § cross-references — claims one file makes about another file's headings — against exactly the drift class `CLAUDE.md` rule (b) exists for.

It held its population as two files named in one string:

```bash
citers="$refac $skill"
```

A review sub-agent appended a **third** citing site carrying a stale heading. The suite reported `17 passed, 0 failed`. A `citer_seen -eq 2` counter guarded the list *shrinking*; nothing guarded the repo *growing* a citer the list did not know about.

The same suite had a second instance in a third syntax — `for label in Discipline Candidates` over `sed` ranges that overran their sections, so both per-section checks passed while pointing at text outside the section they named.

Expected: the entry, the mechanism, and the trigger question would have stopped this. Actual: none of the three fired.

## Symptoms

- A `docs/solutions/` entry names a pattern in general terms and ships a mechanism written against the **syntax** of one instance.
- The mechanism's detector keys on a language construct (`case`, a decorator, an annotation, a specific call) rather than on the property.
- A new artifact reproduces the pattern using a different construct, and the mechanism's scan reports zero — indistinguishable from a clean repo.
- The entry's own Shelf Life or Rule Scope **already predicted this**, in a sentence read as a caveat rather than as a work item.
- The recurrence is caught by human or sub-agent review, not by the mechanism. (Here: two review sub-agents found it; the mechanism did not.)

## Root Cause

Three things compound, and only the third is about this repo:

1. **A mechanism is written at the moment of maximum instance-specificity.** You have just fixed one concrete defect, and its syntax is the most available handle. Detecting `case "$1" in` is easy and precise; detecting "an enumerable set whose members are restated" is neither. The easy detector gets written and the general one is deferred to a "will need extending" note.
2. **Zero hits is the mechanism's healthy state, so its silence carries no signal.** A `case`-shaped detector finding no violations looks exactly like a `case`-shaped detector that has stopped covering the repo's real shapes. Nothing in a green run distinguishes "no instances" from "no longer looking where the instances are."
3. **`docs/solutions/` retrieval is keyed to the feature domain, not to the deliverable's form.** `/execute` Step 1 greps `docs/solutions/` for keywords about the problem being solved. The #268 slice was about type-level invariants, so the grep was for *illegal state*, *branded type*, *smart constructor* — and returned nothing. `partial-oracle-selfcheck` is filed under `testing-patterns` and is about **writing a contract suite**, which is what the slice actually *produced*. The relevant entry was three days old, evergreen, and unreachable by the search that was run.

(3) is the structural one. The lesson was captured, findable, and correct, and the retrieval path could not connect it to the work — because nothing routes by *what the slice ships*, only by *what the slice is about*.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** a balancing loop that stops balancing without announcing it. The mechanism's coverage is fixed at authorship; the population of shapes it must cover grows with every artifact added. Confidence in the mechanism grows monotonically with each green run while its *actual* fraction of the population falls. There is no signal at the crossover, because the observable — a green scan — is identical on both sides of it.

## Rule Scope

- **Applies when:** a `docs/solutions/` entry (or any post-incident rule) ships an **automated detector**, *and* the detector keys on a syntactic construct while the entry's prose states the rule as a **property**. The tell is a gap between the entry's Rule Scope, which is written generally, and the mechanism's matcher, which is written concretely. It applies with extra force when the entry's own Shelf Life contains a sentence of the form *"the mechanism is X-specific and will need extending if…"* — that sentence is a filed prediction, and predictions in Shelf Life sections are not tracked by anything.
- **Inverts or does not apply when:** the property genuinely *is* the syntax — a rule about `git checkout --`, about a specific API's calling convention, or about one file's format has no more general form to reach for, and generalizing it manufactures false positives. It also does not apply where the general detector's false-positive rate would exceed its catch rate; a detector that reddens correct code gets deleted, which is worse than a narrow one that survives. The escape is to make the narrowness **declared and self-tested**, not to widen the matcher past what it can do accurately.
- **Sibling docs:**
  - `partial-oracle-selfcheck-2026-08-22.md` — the direct parent. This entry is its second recording: same pattern, different syntax, and its mechanism did not fire. Its Prevention #2 (*derive, don't restate*) is the correct fix and was applied here.
  - `authored-mutations-inherit-the-authors-blind-spot-2026-08-28.md` — this entry's second recording, five days later, and the explanation for *why the mutation battery did not catch it*: the battery was drawn from the same model as the detector, so it could only plant shapes the detector already covered.
  - `mutate-the-oracle-not-only-the-subject-2026-08-19.md` — grandparent. Its rule found both defects here, once the battery was aimed at the set-membership region rather than the assertion region.
  - `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — the family's root: *a property asserted with nothing constructing it*.
  - `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — a fifth instance of that entry's shape, and a strong one: the suite reproduced the defect class it was written to abolish, in the same file, in the same commit.

## Solution

**Two moves. The instance is fixed by deriving; the class is fixed by widening the mechanism to the property and self-testing the detector.**

**Before** — the population restated, and a counter that only catches it shrinking:

```bash
citers="$refac $skill"
citer_seen=0
for f in $citers; do
    citer_seen=$((citer_seen + 1))
    # …assert $f cites the heading exactly…
done
[ "$citer_seen" -eq 2 ] || bad "expected to check 2 citing files"
```

**After** — the population *discovered*, under a floor that turns a broken extractor into a `FATAL` rather than a clean run:

```bash
# Scan tdd/ for every § cross-reference and resolve each against the headings
# of the file it names. The § idiom survives a heading rename, so the SET is
# discoverable while the heading TEXT stays the extracted value being compared.
while IFS= read -r line; do
    # …extract target + heading, assert it resolves…
done <<EOF
$(grep -n -- '\.md) § \*' tdd/*.md | sed 's|^\(tdd/[A-Za-z0-9.-]*\):[0-9]*:|\1:|' || true)
EOF

# One floor PER SHAPE, not one for the sum. Each extractor is its own point of
# vacuous green, and a shared floor cannot tell "this shape found nothing" from
# "the other shape found plenty."
for shape in "1:$shape1_total:$MIN_SHAPE1" "2:$shape2_total:$MIN_SHAPE2"; do
    n="${shape#*:}"; found="${n%%:*}"; floor="${n##*:}"
    [ "$found" -ge "$floor" ] || fatal "extractor for reference shape ${shape%%:*} found $found reference(s), expected at least $floor — that regex no longer matches the idiom."
done
```

**The per-shape floor is the corrected version, and the aggregate one is the instructive mistake.** The first draft floored `ref_total` at 4 for both extractors together. Breaking shape 2 alone then left shape 1's five references clearing the bar, and a genuinely stale shape-2 reference passed `21/0` — verified. An earlier revision of *this entry* shipped that aggregate floor as the worked example, which is the entry's own thesis applied to itself: a mechanism's prose and its matcher must be read together, and here the prose was the mechanism.

Deriving raised coverage from 2 hand-picked files to every § reference in `tdd/` — picking up two **pre-existing** references the hand-list never covered, and one this branch itself created that it had missed.

**The class fix** is a second detector in `scripts/test-oracle-table-coverage.sh`, the file the parent entry shipped. It finds a hand-listed *population of subject files* and requires the suite to declare how the population was obtained. Scope note, because the Context above records **two** instances: the detector reaches the file-population one only. The second — `for label in Discipline Candidates` over overrunning `sed` ranges — is a population of *sections*, was fixed by bounding those ranges rather than by the detector, and is pinned as a required non-match so the detector's name stays true — `coverage:` on any line satisfies it. The escape is deliberately one that must be **written down**: enumeration is allowed (the parent entry's Rule Scope permits it), silence is not.

Two properties worth stating, because they are where this mechanism differs from its sibling:

- **It has no floor, and that is disclosed rather than an oversight.** The table check floors at `MIN_TABLES=2` because the repo demonstrably has tables, so a zero scan is a detector regression. Hand-listed populations are different: zero is a *permissible* state, so a floor could redden a legitimately clean repo. Note what this does **not** claim — the repo's actual count is not zero, and the scan reports several declared populations. The design argument is about what a floor would forbid, not about the current tree.
- **So the guard is a self-test instead.** The suite plants the exact pre-fix shape and requires the detector to find it, plus the inverse — a single named subject (`compound_skill="compound/SKILL.md"`, how every suite here opens) must **not** trip it. A floor asserts the repo still has the defect; a self-test asserts the detector still sees it. The second is what was actually wanted, and it closes the "zero hits carries no signal" root cause directly.

Verified against the real artifact: restoring `test-widened-domain-tell.sh` to its pre-fix commit makes the scan report that suite as carrying undeclared populations; adding `coverage:` notes makes it pass; breaking the detector's regex makes the self-test fail.

**Do not re-narrow this to a single line or a single shape.** It said "the exact line (`125:…`)" once and a later commit in the same PR silently falsified it. It then said "the `citers=` assignment" — and at that revision the detector could not match that shape at all, so the claim was true only because a *different* population in the same file failed. Both times the sentence named a coordinate that something else owned. Name what the scan reports about the artifact, and let the artifact be the thing that is checked.

**This paragraph originally cited the failing line by number, and that citation is why it is worth reading twice.** It was accurate when written. Two commits later — in the same PR — the detector was widened, so the scan began reporting a *different* line first, and the claim became false with nothing to notice. A line number in an evergreen entry is a hand-maintained cross-reference to a file that moves: the same class this entry is about, in the entry itself. Cite the *shape* that fails, not its coordinates.

## Prevention

**Code-level.**

1. **A mechanism's detector and its entry's prose must be read together, once, at authorship.** If the prose says *property* and the matcher says *construct*, either narrow the prose to what is enforced or widen the matcher. Both are honest; the gap is not.
2. **A detector whose healthy state is zero hits needs a self-test, not a floor.** Plant the shape it exists to find and require a hit, and plant a near-miss and require silence. Without this, the only observable is a green run, which is the same on both sides of a detector going blind.
3. **Aim the mutation battery at the *set-membership* region, not only the assertion region.** Both defects here were set-membership (which files, which sections), and both survived a battery that mutated assertions thoroughly. This extends `mutate-the-oracle-not-only-the-subject`'s rule with a second target class.
4. **A "will need extending if…" sentence in a Shelf Life section is a filed prediction with no owner.** When writing one, either build the extension or file an issue. Here the prediction came true on the next artifact, three days later.

**Process-level.** The retrieval gap is the structural half, and it is the one worth changing.

> **`/execute` Step 1's `docs/solutions/` consult should be keyed to the slice's *deliverable type* as well as its feature keywords.** When the slice ships a contract test, `docs/solutions/testing-patterns/` is mandatory reading regardless of what the test is about. When it ships a migration, `devops/`. The current grep is keyed to the problem domain, which is exactly the axis along which the relevant entry was invisible.

The checkable trigger, in the one-line form this family requires:

> **"What shape does this mechanism match, and is that the same as the property it is named for?"**

## Planning / Calibration Notes

- **What widened the work:** a full second review round. Five Concerns, two of them false-pass mutations inside the new suite. The prose the slice was nominally about needed three small corrections; the *mechanism* carried every structural defect — the second consecutive PR where that was true.
- **What tightened the work:** delegating review to sub-agents that held none of the authoring context, and instructing them to **re-derive** the mutation claim rather than trust the PR body. The authoring session had run 22 mutations and found four defects; the independent pass found two more that the battery had not been aimed at.
- **Future planning adjustment:** when a slice's deliverable is a contract test, treat the test as the primary review artifact and budget a mutation battery aimed specifically at set membership. Also: three "survivors" in this branch's battery were `git checkout --` on a file whose fix was still *uncommitted*, which reverts to the last **commit** and silently runs every later mutation against the old file. Copy the tree per mutation and assert the mutation landed.

## Actuals Worth Reusing

- **Comparable future work:** any `scripts/test-*.sh` added under `CLAUDE.md` rule (b), and any post-incident mechanism whose entry states a rule more generally than its matcher enforces it.
- **Reusable baseline:** the parent entry budgeted ~20 mutations for a suite of this size and expected one or two to land on the suite itself. Actual here: ~30 across two rounds, with **four** landing on the suite. The mechanism, not the feature, is where the defects live — for the second PR running. Budget review accordingly.

## Defect Classification

**Origin phase:** Design error — the mechanism's scope was chosen from the instance's syntax, and the entry's own Shelf Life recorded that choice as a known limitation without treating it as work.
**Fix type:** Correction. The instance is fixed by deriving the set; the class is fixed by a second detector that matches the property in either syntax, guarded by a self-test rather than a floor.

## Related

- `guard-and-subject-must-be-one-artifact-2026-08-25.md` — this entry's thesis restated a third time: `scripts/test-oracle-table-coverage.sh` could not fire on a suite with no `case` table, so a third mechanism was written for a third syntax.

- PR #271 — where this surfaced; issue #268 the driving proposal
- `partial-oracle-selfcheck-2026-08-22.md` — parent entry, second recording
- `mutate-the-oracle-not-only-the-subject-2026-08-19.md` — grandparent
- `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — family root

## Shelf Life

Evergreen. The rule is about the relationship between a mechanism's matcher and the property it is named for, not about bash or this repo's suites.

One condition would supersede it: if `/execute` Step 1 gains deliverable-type routing for its `docs/solutions/` consult, root cause (3) is closed at the source and this entry should be trimmed to its first two causes. **If a third recording of the parent's pattern appears in yet another shape, that is evidence the family should be consolidated** — it now has four rungs describing one thing, *an artifact that establishes less than it appears to*, and a fifth rung would be the pattern the family is about, applied to the family itself.
