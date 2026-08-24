---
date: 2026-08-19
category: testing-patterns
problem_type: a contract test that ran, passed, and verified nothing, because its mutation battery exercised the subject under test and never the fixture's oracle
components: [triage-issue, scripts, lefthook, validate-skills]
technologies: [bash, git-bisect, contract-tests, mutation-testing, ci]
severity: high
volatility: evergreen
---

# Mutate the oracle, not only the subject

## Problem

A contract test written specifically to stop wrong git-command claims from shipping passed 12/12 while proving nothing about the command it existed to pin. It was mutation-tested before it was wired into CI, and every mutation went red — which is what made a test that verified nothing look verified.

## Context

`CLAUDE.md` § "Commands a skill documents" rule (b) requires that a checkable claim about tool behavior be pinned by an executable `scripts/test-*.sh`. The rule exists because of #243, where six successive drafts of one passage each shipped a wrong claim about a git subcommand; every wrong draft was caught by a human or a review sub-agent, and none by a check.

PR #255 added two runnable git commands to `triage-issue/SKILL.md` and, under that rule, `scripts/test-documented-git-commands.sh` to pin them. The suite extracts each invocation verbatim from the skill and runs it against a synthetic repository with a planted regression, so that `git bisect` has exactly one correct answer.

Expected: the suite fails if the documented block stops being a valid invocation, or if bisect stops returning the planted commit. Actual: the bisect half could not fail for the second reason at all.

## Symptoms

Recognizable without knowing anything about git:

- A test whose verdict depends on a **fixture-supplied oracle** — a predicate the fixture hands to the system under test, which then decides the outcome from it. Bisect scripts, property-test generators, retry/backoff predicates, search-ranking relevance functions, and "does this record match" callbacks all have this shape.
- A mutation battery whose entries all name the **subject** (`swap the argument order`, `rename the command`) and none name the **fixture** or the **oracle**.
- Two assertions that are individually true of the output but are never related to each other — `assert output contains <expected-id>` next to `assert output contains "<success phrase>"`.
- A test that has only ever been observed passing, or whose failures have only ever been *crashes* rather than *wrong answers*.

## Root Cause

Three independent defects, each insufficient alone, jointly fatal:

1. **The oracle was a substring match on a marker that contained its own negation.** The oracle was `grep -q ok value.txt`; the fixture wrote `broken` to mark bad revisions. `broken` contains `ok` (br-**ok**-en), so the oracle answered "good" on every revision. Bisect never received a `bad` verdict and walked to HEAD.

2. **The assertions were never bound to each other.** One checked that the planted SHA appeared *anywhere* in bisect's output; it did — in git's intermediate `Bisecting: … [<sha>]` checkout line, which reports a revision being *tested*, not concluded. The other checked that the phrase `is the first bad commit` appeared *anywhere*; it did — attached to a different SHA. Each assertion was individually true. Their conjunction was not what either implied.

3. **The mutation battery only mutated the subject.** Four mutations were run before wiring the suite in — swapped bad/good argument order, dropped a flag, unescaped an alternation, renamed a command. All four went red, and all four went red *for the same reason*: they made bisect **abort**. So the battery established that the suite detects a crash, and never that it detects a wrong answer. The battery is what converted an unverified mechanism into a confidently-reported verified one.

The deeper condition is that **the oracle is part of the mechanism but does not look like part of the mechanism.** It lives in the fixture, which reads as setup — and setup is the code nobody thinks to attack. Mutation testing has a natural gravity toward the artifact named in the test's title, which is precisely the half most likely to already be correct, because it is the half under review.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from **the test's verdict** back to **the test's own validity**. A passing test emits the same signal whether it verified everything or nothing, so there is no error signal to learn from — the only channel that would report the difference is a deliberate mutation, and the mutation set is chosen by the same person who wrote the fixture, holding the same belief about what could go wrong. The delay is what hides it: the cost surfaces only when the pinned artifact actually drifts, which may be never, and if it is never, the suite is indistinguishable from a working one for its whole life.

## Rule Scope

- **Applies when:** the test's outcome is decided by a predicate the fixture supplies to the system under test, rather than asserted directly on the system's output by the test body. The tell is an inversion of control — the test hands over a callback, script, comparator, or marker, and the system decides using it. Also applies whenever a test's pass condition is **non-zero / not-equal / non-empty**, because negative conditions are satisfied by every kind of failure, including the failure of the test's own setup.
- **Inverts or does not apply when:** the test asserts directly on a value it computed itself with no intermediary (`assert_eq 3 "$(add 1 2)"`). There is no oracle to mutate, and adding a "mutate the oracle" step is ceremony. It also does not apply to tests whose only meaningful failure mode genuinely *is* a crash — a smoke test that asserts a binary starts.
- **Sibling docs:**
  - `partial-oracle-selfcheck-2026-08-22.md` — the child, and the failure one step past *this* entry's remedy. Its rule was followed there: the oracle was mutated, twice, and both mutations were caught. They landed on the four labels the oracle's self-check covered, out of nine. **A battery samples**, so against a guard whose own coverage is partial, sampling is what decides whether the hole is found — and the intuition that picks mutations is the same one that picked the self-check's entries, so the two samples are not independent. That entry adds the adversarial-selection rule this one's Prevention was missing.
  - `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — the parent family, and the entry this one refines. That entry's class is *a property asserted with no mechanism behind it*, and its remedy is to build the extract-and-compare test. This is the failure one step past that remedy: the mechanism exists, runs, and is green, and still establishes nothing. Its line *"a contract suite that has only ever been observed passing is itself an unverified claim"* is correct and was followed here — the suite was mutation-tested — and it was still not enough, because the battery is itself an artifact that can be incomplete.
  - `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — names the pattern behind this entry's most striking symptom: a corrective change written in the idiom that produced the defect reintroduces it. This entry is a fourth instance falling **outside** that entry's three stated preconditions (single-site not multi-site, executable bash not restated prose, found by reasoning not by a grep sweep), which is why it is filed here rather than as another row there — and why it is evidence for promoting that entry from Pattern to Structure. See Solution.
  - `../architecture-decisions/self-review-blind-to-composition-2026-08-13.md` — supplies a second instance of its narrower Prevention rule: *"confirm the counter that test reads can distinguish the mechanism not firing from the mechanism being unable to fire. Those are different facts and only one of them is evidence."* The polarity check added as this defect's own safety net violated exactly that (see Solution), which is strong evidence the rule should be promoted from prose into a checklist item.

## Solution

Three fixes, each closing one of the three root causes, and none sufficient alone.

**Before:**
```bash
# fixture: bad revisions marked with a word that contains the good marker
echo broken > value.txt

# oracle: substring match
run_cmd="${bisect_run//<the-loop-command>/grep -q ok value.txt}"

# assertions: individually true, never related
assert_contains "$bisect_out" "$expected_bad"            # matches an intermediate checkout line
assert_contains "$bisect_out" 'is the first bad commit'  # matches, attached to a different SHA
```

**After:**
```bash
# fixture: marker cannot be a substring of the good marker
echo spoiled > value.txt

# oracle: whole-line match
run_cmd="${bisect_run//<the-loop-command>/grep -qx ok value.txt}"

# pre-flight: prove the oracle discriminates before trusting any verdict from it.
# setup and oracle run as SEPARATE statements — chained with && they share one
# exit status, and the bad-end assertion passes on non-zero, so a failed setup
# would satisfy it exactly as well as a working oracle.
oracle_setup "$good_ref"; good_setup=$?
oracle_run;               good_end=$?
oracle_setup HEAD;        bad_setup=$?
oracle_run;               bad_end=$?
assert_eq 0 "$good_setup" "the probe is really running"
assert_eq 0 "$bad_setup"  "the probe is really running"
assert_eq 0 "$good_end"   "oracle says good at the known-good end"
# range, not merely non-zero: git bisect treats 1-127 except 125 as "bad"
[[ "$bad_end" -ge 1 && "$bad_end" -le 127 && "$bad_end" -ne 125 ]] || fail

# assertion: binds the identifier to the conclusion in one needle
assert_contains "$bisect_out" "$expected_bad is the first bad commit"
```

**The safety net needed the same treatment.** The polarity pre-flight above was added to catch this defect class and shipped containing it: the first draft chained `git checkout … && grep -qx ok value.txt` into one status, on an assertion that passes when the status is non-zero. Pointing the checkout at a nonexistent ref left the suite fully green with that assertion measuring nothing. The same author, in the same hour, writing the check *for* this defect, reproduced it.

**That is a named pattern, not a novelty**, and the entry that names it landed the day before this one: `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md`, whose sharpest recorded instance is *"the artifact written specifically to prevent this defect class contained the defect class."* Its first root cause is the operative one here — *"the sweeper edits in the idiom that produced the defect … the correction and the defect are drawn from the same well."*

What this instance adds is a **boundary test of that entry's Rule Scope**, which currently requires all three of: the defect is textual and multi-site, the sweep is enumerated by search, and the correction is written in the same medium as the defect. This instance satisfies none of them. It is a single-site defect in executable bash rather than restated prose, found by reasoning about an oracle rather than by a grep sweep. The mechanism still fired. That is evidence the root cause generalizes past the stated preconditions to *any* corrective change, which bears directly on that entry's own note that it is **"Level: Pattern … not yet Structure."** A fourth instance outside its declared scope is the kind of evidence that would promote it.

## Prevention

**Code-level.**

1. **Bind the identifier to the conclusion in a single assertion.** `assert output contains "<id> <conclusion-phrase>"`, never those two facts separately. Two assertions that are each true of the output do not compose into the claim you meant.
2. **Prove the oracle discriminates before trusting it.** Run it at a known-positive and a known-negative input and assert *different* results. An oracle that answers identically at both ends still lets the system under test terminate and report a confident answer.
3. **Never let an assertion's pass condition be bare non-zero.** Assert the specific expected range or value, and assert the setup's status separately. A negative pass condition is satisfied by every failure mode including the test's own.
4. **Make fixture sentinels non-overlapping.** No marker may be a substring of another marker in the same fixture. This is what turns a substring/whole-line mix-up from a silent wrong answer into a loud one.

**Process-level.** The repo already requires mutation-testing a new contract suite before wiring it in (`by-construction-claims-need-a-mechanism-2026-08-11.md` § Solution). That requirement stands and is not sufficient. Extend it with a **coverage rule for the battery itself**:

> A mutation battery must contain at least one mutation of the **fixture** and at least one of the **oracle**, not only of the artifact under test. If every mutation in the battery fails the same way — all crashes, or all fatals — the battery has demonstrated one failure mode and left the others untested.

The checkable trigger, stated so it can be applied to a single assertion without re-deriving the diagnosis:

> **"If this assertion passed, what else could have made it pass?"**

If the answer includes anything other than "the behavior I am claiming," the assertion is not yet pinned. This is deliberately shaped as a question you can ask of one line, because the parent entry's Shelf Life records that its own consolidation would fail if written as more prose.

## Planning / Calibration Notes

- **What widened the work:** the review, correctly. The implementation matched the approved issue in about 33 lines of skill text; the contract test, its repair, and the repair of the repair came to roughly 380 lines and two extra review rounds. Every one of those rounds found something real, and the second found a defect inside the fix produced by the first.
- **What tightened the work:** applying rule (a) — *reference, don't re-author* — before rule (b). Pointing at `git bisect --help` § "Bisect run" instead of restating exit-code semantics meant the **prose** claims survived two adversarial reviews untouched. Every defect found was in the **mechanism**, none in the referenced material. That is a strong signal for the ordering the repo already prescribes.
- **Future planning adjustment:** when a change's deliverable is *a mechanism that verifies something*, budget verification of the mechanism as its own reviewable unit rather than as a step inside implementation. Here it was larger than the feature and needed independent eyes twice.

## Actuals Worth Reusing

- **Comparable future work:** any change that adds a `scripts/test-*.sh` contract suite, especially one whose fixture supplies a predicate to the thing being tested. The highest-value next target is `/closeout`, which documents 13 runnable git invocations including `git worktree remove`, `git branch -d`, and `git pull --ff-only` — destructive, and run unsupervised at merge time.
- **Reusable baseline:** for a suite of this shape, expect the mutation battery to roughly double the suite's development cost, and expect the first battery to be incomplete. Budget an independent verification pass on the suite itself; in this instance it found seven further defects after six had already been fixed.

## Defect Classification

**Origin phase:** Design error — the fixture and its oracle were designed together by one author holding one theory of what could go wrong, and the mutation battery inherited that theory.
**Fix type:** Correction. The oracle now discriminates, the assertion binds identity to conclusion, the polarity probe distinguishes setup failure from a negative verdict, and eight mutations — including two of the oracle and one of the fixture setup — each turn the suite red.

## Key Decision

**Decision:** File this as a new `testing-patterns` entry rather than folding it into `by-construction-claims-need-a-mechanism-2026-08-11.md`.

**Rationale:** that entry's Shelf Life warns that its siblings are overdue for consolidation and that adding another retelling of the same diagnosis would produce a further instance. This is not the same diagnosis. Its class is *a claim with no mechanism*; this is *a mechanism that returns a false green*, which sits one step past its remedy and would be invisible to every check it prescribes. Folding a refutation-shaped lesson into the entry it refines would bury the part that is new.

**Alternatives considered:** fold in as a sixth instance — rejected above. Capture as a code comment only — rejected: the comment exists in the suite header, but the transferable rule is about how mutation batteries are chosen, which no single file owns.

**Revisable:** Yes. If the consolidation the parent entry calls for is ever written as a trigger-shaped entry, this should fold into it as one of its worked examples.

## Related

- PR #255 / issue #236 — the change that produced this entry
- Issue #243 — the incident behind `CLAUDE.md` rule (b), which required the suite this entry is about
- `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md`, `../architecture-decisions/self-review-blind-to-composition-2026-08-13.md`, and `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — see Rule Scope
- PR #246 / issue #245 — landed on `prod` while this PR was open; its `sweep-commits` entry is why the safety-net observation above is framed as a scope-boundary instance of a known pattern rather than as a new finding

## Shelf Life

Evergreen — no expiration condition. The specific instance is git-bisect-shaped, but the rule is about the relationship between a test, its oracle, and its mutation battery, and does not depend on any tool. Retire it only if it is absorbed into the consolidated entry the parent doc calls for.

**Sibling (2026-08-23).** [validate-the-instrument-not-only-the-subject-2026-08-23.md](validate-the-instrument-not-only-the-subject-2026-08-23.md) carries this one level out: that entry mutates the *oracle inside a committed suite*; this one is about the reviewer's own uncommitted harness, which no suite here can reach.
