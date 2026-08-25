---
date: 2026-08-19
category: testing-patterns
problem_type: a contract test that ran, passed, and verified nothing, because its mutation battery exercised the subject under test and never the fixture's oracle
components: [triage-issue, tdd, pre-merge, scripts, lefthook, validate-skills]
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

- **Applies when:** *either* the test's outcome is decided by a predicate the fixture supplies to the system under test, rather than asserted directly on the system's output by the test body; *or* the property being claimed has more than one failure direction that is **independently observable and independently breakable** — a two-ended relation (does the pointer resolve / does the target stay pointed-at), a round trip (encoder / decoder), a guard with an over-claim and an under-claim direction. The observable-and-breakable test is what keeps this arm from matching everything: almost any property can be *described* as having two directions, but `assert_eq 3 "$(add 1 2)"` has no second thing you can break on its own. The tell is an inversion of control — the test hands over a callback, script, comparator, or marker, and the system decides using it. Also applies whenever a test's pass condition is **non-zero / not-equal / non-empty**, because negative conditions are satisfied by every kind of failure, including the failure of the test's own setup.
- **Inverts or does not apply when:** the test asserts directly on a value it computed itself with no intermediary **and** the property has a single failure direction (`assert_eq 3 "$(add 1 2)"`). Both halves are required — a direct assertion with no oracle can still carry two directions, which is what the second instance below is. With both, there is no oracle to mutate and no second direction to cover, so a "mutate the oracle" step is ceremony. It also does not apply to tests whose only meaningful failure mode genuinely *is* a crash — a smoke test that asserts a binary starts.
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

## Second instance (2026-08-24) — a battery that exercised one end of a two-ended relation

**This one falls outside the Rule Scope above and the root cause fired anyway**, which is why it is recorded here rather than as a fifth entry in this cluster.

`scripts/test-widened-domain-tell.sh` guards every `§` cross-reference in `tdd/`: it discovers references by scanning and asserts each resolves to a heading that exists. PR #276 added `tdd/tests.md` § *A test name is a claim the assertion must be able to falsify* plus a pointer to it from `tdd/SKILL.md`'s `Checklist Per Cycle`, and mutation-tested the pointer before claiming it was covered:

```
baseline                                 22 passed, 0 failed
rename the heading in tests.md           21 passed, 1 failed   <- caught
delete the pointer clause in SKILL.md    21 passed, 0 failed   <- GREEN
```

Only the first mutation was run. The PR body then reported *"the pointer is machine-checked."* One mutation, one red, and a claim about the reference as a whole.

**A reference has two ends and two independent failure directions.** *Resolution* — does the pointer still name a heading that exists — is what the mutation tested. *Reachability* — does anything still point at the heading — is what it did not, and with the pointer deleted the checklist row reads `[ ] Test name claims only what the assertion can falsify` with no method attached anywhere. That is the exhortation the change existed to avoid. `MIN_TO_RULE` floors inbound references to exactly one heading (the type-level rule from #268) and nothing floors the next one, which is `partial-oracle-selfcheck-2026-08-22.md`'s shape in the guard rather than in the suite.

**Why it is a scope-boundary instance.** The Applies-when above requires a fixture-supplied oracle — an inversion of control where the test hands over a predicate and the system decides using it. There is none here: the suite extracts headings and compares them directly, the shape this entry's Inverts-when explicitly exempts. What recurred was not the oracle blind spot but the layer under it: **the battery's coverage bounds the claim, and the claim was made at the width of the artifact rather than the width of the battery.** That generalizes the same way the 2026-08-19 instance generalized `sweep-commits`, and it is the second such boundary test — evidence the root cause is about *batteries*, not about *oracles*.

**And the corrective change carried the defect, for the third recorded time.** The PR was adding a rule that says a test name is a claim the assertion must be able to falsify. The PR-body claim was the name; the single mutation was the assertion; the name was wider. Same author, same PR, same hour — `../architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` again, now with an instance where the defect and the *rule against the defect* were written into one diff.

**Found by:** a `/pre-merge` review sub-agent, which re-ran the battery and added the mutation the author had not. Not by the author re-reading it. The battery is chosen by the person holding the theory of what could go wrong (§ Root Cause), and that is as true of the second mutation as of the first.

## Prevention

**Code-level.**

1. **Bind the identifier to the conclusion in a single assertion.** `assert output contains "<id> <conclusion-phrase>"`, never those two facts separately. Two assertions that are each true of the output do not compose into the claim you meant.
2. **Prove the oracle discriminates before trusting it.** Run it at a known-positive and a known-negative input and assert *different* results. An oracle that answers identically at both ends still lets the system under test terminate and report a confident answer.
3. **Never let an assertion's pass condition be bare non-zero.** Assert the specific expected range or value, and assert the setup's status separately. A negative pass condition is satisfied by every failure mode including the test's own.
4. **Make fixture sentinels non-overlapping.** No marker may be a substring of another marker in the same fixture. This is what turns a substring/whole-line mix-up from a silent wrong answer into a loud one.

**Process-level.** The repo already requires mutation-testing a new contract suite before wiring it in (`by-construction-claims-need-a-mechanism-2026-08-11.md` § Solution). That requirement stands and is not sufficient. Extend it with a **coverage rule for the battery itself**:

> A mutation battery must contain at least one mutation of the **fixture** and at least one of the **oracle**, not only of the artifact under test. If every mutation in the battery fails the same way — all crashes, or all fatals — the battery has demonstrated one failure mode and left the others untested.

**Amended 2026-08-24 — component coverage is not direction coverage.** The rule above enumerates *parts* (subject, fixture, oracle), and the second instance above had no fixture and no oracle to enumerate. Add the orthogonal half:

> **Where the property has more than one independent failure direction, mutate each direction.** A reference has two ends: mutate the target *and* delete the pointer. A round trip has two halves: break the encoder *and* the decoder. A guard has two directions: feed it something it must reject *and* something it must accept. One red establishes one direction, and the claim you may write from it is that direction — not the artifact.

The checkable trigger, stated so it can be applied to a single assertion without re-deriving the diagnosis:

> **"If this assertion passed, what else could have made it pass?"**

And its mirror, for the battery rather than the assertion — the question the second instance above needed and nobody asked:

> **"What am I about to claim from this red, and is that the claim the mutation tested?"**

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
- PR #276 / issue #185 — the second instance (2026-08-24); **issue #277** is the mechanism it needs, a reachability floor in `scripts/test-widened-domain-tell.sh` beside the existing `MIN_TO_RULE`
- PR #246 / issue #245 — landed on `prod` while this PR was open; its `sweep-commits` entry is why the safety-net observation above is framed as a scope-boundary instance of a known pattern rather than as a new finding

## Shelf Life

Evergreen — no expiration condition. The specific instance is git-bisect-shaped, but the rule is about the relationship between a test, its oracle, and its mutation battery, and does not depend on any tool. Retire it only if it is absorbed into the consolidated entry the parent doc calls for.

**Sibling (2026-08-23).** [validate-the-instrument-not-only-the-subject-2026-08-23.md](validate-the-instrument-not-only-the-subject-2026-08-23.md) carries this one level out: that entry mutates the *oracle inside a committed suite*; this one is about the reviewer's own uncommitted harness, which no suite here can reach.

**Second instance (2026-08-24).** Recorded in-place under `/compound` Phase 4's *same problem → update the existing file* branch, not under its prose-only rule — that rule governs whether an entry ships a **mechanism**, and says nothing about file-vs-in-place. The judgment the branch needs is that this is the same root cause as the 2026-08-19 instance (a battery narrower than the claim drawn from it) rather than a distinct one; § Second instance argues that at length, and the widened Rule Scope is the result. A reader who thinks the boundary makes it *distinct* rather than *the same pattern generalized* should split it out — that is the arguable call here, and it is deliberately left visible.

Two prior entries in this category name a guard that under-covers what it claims — `partial-oracle-selfcheck-2026-08-22.md` and `mechanism-generality-lags-the-pattern-2026-08-23.md`. (`validate-the-instrument-not-only-the-subject-2026-08-23.md` is a different shape: an instrument that *fails* while reporting normally, not one that under-covers.)

**Which of Phase 4's five came closest: a stronger test** — a reachability floor in `scripts/test-widened-domain-tell.sh` beside the existing `MIN_TO_RULE`, roughly ten lines, sketched in **#277**. What blocked it is *not* difficulty, and the scope/difficulty exit is closed on purpose: it is buildable in this codebase and someone should build it. It was filed rather than written into PR #276 because that PR touches the suite's *subject* and not the suite, and a floor added in the same diff as the reference it floors is a guard authored by the party it guards. That is a defensible reason and a weak one — this instance ships a mechanism-in-waiting, not a mechanism, and if #277 is still open when a third instance arrives, the deferral was wrong.

**Third instance (2026-08-24, PR #278) — and it is the one that bounds this entry's own rule.** A contract test typed each work in a derived canon `book` or `paper`, and its comment claimed it asserted *"the property, not the rule."* It did not. The generator typed a work `paper` when the author field matched `et al.` or a trailing `(YYYY)`; the check asserted `paper` iff the author field matched `et al.` or a trailing `(YYYY)` — **the same predicate, over the same input, in two files.** Two readings of one rule cannot disagree, so it passed by construction, and a research paper cited without a venue year shipped typed `book` with the check green.

The battery satisfied this entry as written. The oracle *was* mutated: emptying the expected set went red, inverting the predicate went red. Every mutation established that the recomputation was correctly wired, and none could establish that the recomputation was *right*, because subject and oracle were the same function. **A mutation battery over an oracle that recomputes the subject measures the wiring, not the claim.**

So the rule this entry states — mutate the oracle, not only the subject — is necessary and, on its own, satisfiable by an oracle that cannot fail. The missing precondition: **the oracle must be capable of disagreeing with the subject in the first place, which requires it to be derived from a different source.** Recomputation from the subject's own input is the disqualifying shape, and it is attractive precisely because it looks rigorous and never needs maintaining.

The fix was to replace the recomputed predicate with a hand-written list of the works known to be papers, checked against the derivation in both directions — and the reasoning is worth stating because it inverts the surrounding change. That same PR rejected a hand-maintained list twice: an alias table for author spellings, and a table of paper titles inside the generator. Both were correctly rejected: **in the subject, a list is a maintenance burden that drifts.** In the oracle, a list is the only thing that *can* disagree. The rejection reasoning does not carry across the subject/oracle boundary, and carrying it across is what produced the defect.

Two limits recorded honestly. The replacement is a *regression pin, not a gate*: it catches a listed work being retyped and a marker being removed, and does not catch a newly added paper carrying no citation tell — that work is absent from both sides of the comparison and passes. Closing that needs an expected-type row for every work, which reintroduces the per-source maintenance the change existed to remove. And the first version shipped with no floor, so both sides empty reported `ok` — the one state a set comparison cannot distinguish from agreement, and the shape `partial-oracle-selfcheck-2026-08-22.md` already names.

**Which of Phase 4's five came closest: a stronger test, and it was built** — `EXPECTED_PAPERS` plus a `MIN_PAPERS` floor plus fixtures driving the comparison in both directions, in `scripts/test-canon-coverage.sh`. Unlike the second instance, nothing was deferred here.
