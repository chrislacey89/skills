---
date: 2026-08-28
category: testing-patterns
problem_type: a mutation battery perturbs only values that exist, so it certifies that each assertion reads its value and never that the assertion fails when the value is gone — five assertions passed with their subject deleted, under an author who had run a battery and believed the claim
components: [scripts/test-*.sh, contract-test suites, docs/visual-recap-design.md]
technologies: [bash, grep, awk, contract-tests, mutation-testing, ci]
severity: high
volatility: evergreen
---

# A battery that only perturbs what is present certifies the wrong half

## Problem

A contract test shipped with 28 assertions and a CHANGELOG line reading "Every assertion was mutation-checked." An independent review found **five** of them passed when the exact thing they named was deleted from the tree. The battery behind the claim was real and had been run; it was aimed in one direction only.

## Context

`CLAUDE.md` rule (b) requires an executable contract test for every checkable claim a skill makes, so this repo manufactures prose-pinning suites continuously. `scripts/test-per-unit-series-contract.sh` was written to pin §12 of `docs/visual-recap-design.md` — a block whose load-bearing constraints (real `<section>`s, a required matrix, a retained serializer, no router) are invisible in the rendered output and therefore have nothing but the suite holding them.

Before wiring it in, five mutations were run: drop the matrix, plant a `stage.innerHTML` router, strip a note input, reinstate the deleted `setSide` handler, weaken the site threshold. All five went red. The battery looked convincing enough to write "every assertion was mutation-checked" in the changelog.

## Symptoms

- Every mutation in the battery goes red, and each goes red *for the reason you expected*.
- The suite's assertion labels read as strong claims about the subject.
- Deleting the subject outright — rather than corrupting it — leaves the suite green.
- A guard's floor never appears in the output, in either the passing or the failing case.

## Root Cause

**Perturbing a value that exists tests whether an assertion *reads* that value. It does not test whether the assertion can be satisfied by something *other* than that value, nor whether it degenerates to vacuous truth once the value is gone.** Those are different questions, and only the second finds this defect class. Every one of the five hid under absence:

1. **Vacuous-loop counter.** `bad_ids=0`, incremented only for a *malformed* id. Deleting every id left an empty stream, so the counter stayed `0` and `assert_eq "0" "$bad_ids"` passed. A counter with no floor against the population it should equal proves nothing about an empty population.
2. **Prose satisfies a markup assertion.** `assert_found "oc-matrix" "$span"`, where the span held §12's markup *and* the prose describing it. Deleting the matrix markup passed, because the sentence requiring the matrix contains the string.
3. **Frontmatter satisfies a body assertion.** Two gate assertions grepped all of `visual-recap/SKILL.md`. Both phrases also live in the YAML `description:` — a trigger string, not an instruction — so deleting the operative Step 3 instruction passed.
4. **A needle too generic to die with its sentence.** `assert_found "population" "$CORE"`. The bare word survives elsewhere in the file, so deleting the bullet the issue actually asked for passed.
5. **A literal-name census standing in for a behavioral property.** The toggle census grepped `setSide`, `ba-thumb`, `toggle variant`. Reinstating a working hide-one-side toggle under the handler name `showSide` passed. The anti-pattern is *one comparison state is hidden*; the census asserted *a function with this name does not exist*.

Two further shapes the battery had no mutation aimed at:

6. **The region boundary.** The §12 span terminated on `/^## 1[3-9]\./`, but §12 is the *last* numbered section, so the span ran to end-of-file and swept in `## Do's and Don'ts` — letting an assertion about §12 be satisfied from outside §12, the precise failure the span existed to prevent, inverted. Extraction boundaries are part of the mechanism and need their own mutation; renaming the section heading is the cheapest one.
7. **The guard that cannot fire.** Under `set -o pipefail`, a legitimately zero-match `grep` in a counting pipeline returns 1 and aborts the script *before* the floor on the next line can report the count. Three instances shipped in one file. None was visible by reading; all three surfaced only by running the suite against a tree where the counted thing was absent.

The deeper condition is a gravity in how batteries get designed. **A mutation is easiest to write against something you can see**, so the author reaches for the artifact in front of them and corrupts it. Absence has no line to edit and no obvious place to put the cursor — which is exactly why the assertions that fail under absence are the ones that survive review.

There is a second-order version worth naming, because it bit during the *fix*: replacing the literal-name census with a behavioral detector produced two false positives, both found only by running it. An unqualified `\.hidden *=` flagged the rendering core's `ta.hidden = false`, which *reveals* the clipboard fallback textarea — the opposite behavior. Broadening to `hidden.*after` then flagged ordinary prose in `shape/SKILL.md`: *"Probe hidden functions … only surface after rollout."* **In a repo whose product is English, a detector built from English words is a detector built from noise.** A behavioral detector over prose has to be anchored to markup shapes.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** Missing feedback with a long delay. A green suite is indistinguishable from a suite that reads nothing, and the signal that would separate them — the guard's own floor message — is by construction never printed while the tree is healthy. The author's confidence therefore rises with each passing run, and the only event that can correct it is an independent reviewer choosing a mutation the author did not. That happened here; it is not a mechanism.

## Rule Scope

- **Applies when:** a mechanism's assertion is a *match* over a text region — `grep`, `assert_found`, a substring test — and the region is extracted from a larger file. This is the whole prose-contract-test family under `CLAUDE.md` rule (b), plus any suite matching against markup, config, or generated output.
- **Applies when:** the healthy state of a check is *zero hits*, or a counter's healthy value is `0`. Both are satisfied by an empty input, so both need a floor against a separately-derived population.
- **Inverts or does not apply when:** the assertion is a *computed comparison* between two independently derived values (`assert_eq "$declared" "$rows"`), which cannot pass vacuously — deleting either side changes one and not the other. Reach for that shape in preference to a match whenever the subject admits a count. It also does not apply to subject-corrupting batteries over executable code, where the classical mutation operators already cover the direction this entry is about.
- **Sibling docs:** [`mutate-the-oracle-not-only-the-subject`](mutate-the-oracle-not-only-the-subject-2026-08-19.md) is the closest neighbor and the same underlying pattern — *a battery certifies a property it does not establish*. It asks **which artifact** to aim at (the oracle, not just the subject); this one asks **which direction** to aim, within either. [`dead-guards-report-coverage-they-do-not-have`](dead-guards-report-coverage-they-do-not-have-2026-08-27.md) covers root cause 7's family. [`prose-contract-tests-are-restated-claims`](prose-contract-tests-are-restated-claims-2026-08-27.md) covers root causes 2–4, and this entry supplies the battery that would have found them. [`mechanism-generality-lags-the-pattern`](mechanism-generality-lags-the-pattern-2026-08-23.md) covers root cause 5.

## Solution

The prescription is a **battery recipe**, because "mutation-check your assertions" is what the author of this incident believed they had done. Perturb-present is necessary and not sufficient. Add four directions:

| Direction | The mutation | Catches |
|---|---|---|
| **Perturb-present** | corrupt the value the assertion names | the assertion does not read its value |
| **Delete-the-subject** | remove the value entirely | vacuous counters, empty-stream loops, zero-hit checks with no floor |
| **Satisfy-from-elsewhere** | delete the *operative* instance, leave a decorative one (a prose mention, a frontmatter copy, a sibling section) | a needle too generic, or a region too wide, to distinguish them |
| **Move-the-boundary** | rename the section heading, change the fence, shift the extraction anchor | extraction that silently reads too much or too little |
| **Rename-the-mechanism** | keep the forbidden *behavior*, change every identifier it uses | a census keyed to literal names rather than the property |

Two structural rules follow, and both were applied to the suite that produced this incident:

**(a) An assertion about markup reads the extracted markup, never the region that also holds the prose describing it.** §12's fenced blocks and the SKILL body with frontmatter stripped became separate extracts, each with its own non-vacuity floor.

**Before:**
```bash
awk '/^## 12\./ { inside = 1 } inside && /^## 1[3-9]\./ { inside = 0 } inside' "$DESIGN" > "$span"
assert_found "oc-matrix" "$span"   # satisfied by §12's prose; and $span ran to EOF
```

**After:**
```bash
# Terminates on the NEXT `## ` heading of any kind: §12 is the last numbered
# section, so a numbered terminator ran to end-of-file.
awk '/^## 12\./ { inside = 1; print; next } inside && /^## / { exit } inside' "$DESIGN" > "$span"
# Markup only — the fenced blocks, prose removed.
awk '/^```html$/ { f = 1; next } /^```$/ { f = 0; next } f' "$span" > "$markup"
assert_found "oc-matrix" "$markup"
# And a regression guard for the boundary itself:
grep -qF "Do's and Don'ts" "$span" && fatal "the span swept in the closing section"
```

**(b) A detector whose healthy state is zero hits gets a self-test, not a floor** — plant the shape and require a hit, plant a near-miss and require silence. Both false positives from the fix are pinned this way, so a future widening of the regex cannot silently re-acquire them.

Counters get a floor against a separately-derived population rather than an equality against a constant:

**Before:** `assert_eq "0" "$bad_ids"` — passes on an empty stream.
**After:** `assert_eq "$unit_headers" "$unit_ids"` — cannot pass unless both are derived and agree.

The suite went from 28 assertions to 49. Twelve mutations, one per named row.

## Prevention

**Code-level:** `scripts/test-guards-can-fire.sh` gains **Detector C** — a `grep` feeding a counter (`wc`, or another `grep -c`) without `|| true`, or a bare `grep -c`, inside a command substitution in a suite running `set -o pipefail`. That is root cause 7 made mechanical, and it is narrow on purpose: counting is the operation whose *zero* result is meaningful, so those are exactly the greps that must survive matching nothing.

Its first version was narrower than that principle: it required `$(`, `grep`, `|`, and `wc` on one physical line, which caught **one** of the four counting sites in the file that motivated it and none elsewhere in the tree — the syntax of the instance standing in for the class, which is the failure [`mechanism-generality-lags-the-pattern`](mechanism-generality-lags-the-pattern-2026-08-23.md) names. Review caught it. It now joins continuation lines, allows intermediate pipeline stages, and covers bare `grep -c`; reverting the three fixes in `test-per-unit-series-contract.sh` names all three, and it found a live unguarded instance in `test-options-comparison-contract.sh` that the first version reported clean.

**What Detector C still does not catch,** stated so its coverage is not over-read: a counting command outside the `wc`/`grep -c` set, a non-`grep` command that exits non-zero in the same position, and a count assembled across two statements. Narrowed, not closed. It carries the suite's self-test convention — four hazardous fixtures that must be flagged, three safe ones that must not, and a no-`pipefail` near-miss.

**A second review round found the repair had reproduced the class one level up**, at four more sites: two stop-rule self-tests that *re-typed* their needle instead of calling the detector (so typo-ing the operative regex left them green while a planted router shipped); a "behavioral" toggle detector that a rename to `old`/`new` plus `display:none` walked through; a census loop that redirected from a tracked-but-deleted path and so aborted 40 lines before the guard written to report it; and the sibling suite `test-options-comparison-contract.sh`, which carried root cause 1 verbatim and a live unguarded `grep -c` — because the structural-sibling search of Q4/Dimension 9 was never run. That round is the strongest evidence for the recipe below: the author had *just written this entry* and still aimed the second battery the same way.

Root causes 1–6 are **not** mechanized, and the reason is worth stating rather than leaving as an omission: each is a property of what an assertion *means*, and deciding whether a needle is "too generic to die with its sentence" requires reading the sentence. Detector C exists because root cause 7 is the one shape in the set that is decidable by grep. The rest are carried by the battery recipe above and by review.

**Process-level:** `/pre-merge`'s delegated review is what caught all five here, and it caught them because a sub-agent chose mutations the author had not. That is the argument for the delegation being unconditional rather than size-gated — the author's battery was not lazy, it was *systematically* aimed at one half, and only a different reader breaks that. When a PR's own diff contains a `scripts/test-*.sh`, the reviewer should run the delete-the-subject direction explicitly rather than reading the assertions.

## Planning / Calibration Notes

- **What widened the work:** the contract test was budgeted as one commit and took three — write, repair after review, then extend to the surfaces review found restated-but-unpinned. Assume a prose-pinning suite is not done when it first goes green.
- **What tightened the work:** the existing `testing-patterns` entries gave the fix its shape immediately; the two structural rules are generalizations of moves those entries already prescribe.
- **Future planning adjustment:** when `/prd-to-issues` slices work that ships a contract test, treat "write the suite" and "mutation-check the suite in all five directions" as separate acceptance criteria. Folding them into one criterion is what let a green suite read as a finished one.

## Actuals Worth Reusing

- **Comparable future work:** any slice satisfying `CLAUDE.md` rule (b) by adding a `scripts/test-*.sh` over prose.
- **Reusable baseline:** a suite pinning one doc section landed at 28 assertions; making *that same coverage* honest took it to 40 — **1.43×**, and those 12 really are floors, self-tests, and separated extracts. A further 9 arrived with the drift sweep (gate surfaces, chip mapping, routing) and are new subject coverage, not hardening. Budget the two separately: a planner who reads one 1.75× figure will over-budget the hardening by the cost of a sweep that is a different job. A second review round then added 4 more, so the suite as merged is 53.

## Defect Classification

**Origin phase:** Design error — the battery's design, not its execution. Every mutation in it ran and reported correctly.
**Fix type:** Correction for root cause 7 (Detector C removes the defect class mechanically) and for the six specific assertions. Mitigation for root causes 1–6 as a class: the battery recipe is a procedure, and a procedure is weaker than a check.

## Related

- PR #306 / issue #304 — the branch this was found on; the suite is `scripts/test-per-unit-series-contract.sh` and the mechanism is Detector C in `scripts/test-guards-can-fire.sh`
- [`mutate-the-oracle-not-only-the-subject`](mutate-the-oracle-not-only-the-subject-2026-08-19.md) — same pattern, different axis; read both
- [`dead-guards-report-coverage-they-do-not-have`](dead-guards-report-coverage-they-do-not-have-2026-08-27.md)
- [`prose-contract-tests-are-restated-claims`](prose-contract-tests-are-restated-claims-2026-08-27.md)
- [`mechanism-generality-lags-the-pattern`](mechanism-generality-lags-the-pattern-2026-08-23.md)

## Shelf Life

Evergreen — no expiration condition. The gravity it describes is a property of how humans and agents design mutations, not of any tool. Detector C expires only if these suites stop running under `set -o pipefail`.
