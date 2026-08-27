---
date: 2026-08-25
category: testing-patterns
problem_type: a self-test that is total over the reader it checks still establishes nothing, because the behavior that decides the property lives outside the reader — in a caller's argument, or in a second copy of the reader
components: [scripts, execute, pre-merge, compound, lefthook, validate-skills]
technologies: [bash, awk, contract-tests, mutation-testing, ci]
severity: high
volatility: evergreen
---

# A guard proves nothing about behavior that lives outside the thing it guards

## Problem

A contract suite's offprint check — the only mechanical evidence that the landing page renders a conference paper as a different object than a bound book — could be defeated by inverting two characters. Two successive fixes each looked sufficient, shipped, and left the hole open: the first pinned the reader's semantics with a fixture that enumerated *every* combination of its parameters, and the second removed the parameter but gave the self-test its own copy of the replacement.

## Context

PR #279 gave the landing page's canon section the form issue #274 asked for, including the requirement that books and papers render as different objects. Everything about the offprint except its height is CSS the suite deliberately does not grade, so the entire property rests on one comparison: is every paper shorter than every book?

That comparison read two extremes off a min/max helper:

```bash
tallest_paper="$(extreme "$records" paper 1)"
shortest_book="$(extreme "$records" book 0)"
```

Expected: a paper drawn at bound-volume height turns the suite red. Actual: swapping the two flags — `paper 1`→`paper 0`, `book 0`→`book 1` — compares every paper against the *tallest* book instead of the shortest, and a page with a paper at 300px against a 214px shortest book reported:

```
ok   all 3 paper(s) render as offprints, shorter than every one of the 42 book(s) (122px vs 356px)
64 passed, 0 failed
```

The assertion named the property while agreeing with a page that violated it.

## Symptoms

Recognizable without knowing the domain:

- A guard's **direction, threshold, or mode is a parameter**, and the call sites pass it as a bare literal — `1`/`0`, `min`/`max`, `true`/`false`, an index, a comparator name.
- The guard **has a self-test, and the self-test looks thorough** — it may even be total over the guard's own parameter space.
- The property the suite claims is a statement about **the composition** of guard and call site, but nothing exercises the composition.
- Or: the self-test **defines its own copy** of the reader — same logic, different indentation — so mutating the real one leaves the self-test green.
- The live data cannot distinguish a correct reader from a lucky one. Here all three papers rendered at the same height, so a min/max swap on the paper side was invisible against the real page.

## Root Cause

A self-test's scope is the artifact it names, and the property under test is rarely a property of that artifact alone.

1. **A test on a function cannot reach its callers' arguments.** The first fix enumerated all four `(type, direction)` combinations of `extreme()` and every one passed — correctly, because `extreme()` was never broken. The defect was in *which* combination the two call sites asked for, which is a fact about the call sites.
2. **A test on a copy cannot reach the original.** The second fix replaced the parameter with a pairwise scan — the right move — but inlined that scan in the live check and pasted a duplicate into the self-test. Mutating the live scan produced `68 passed, 0 failed`, because the self-test was still exercising its duplicate.
3. **Both failures present as coverage.** Four green fixture assertions and a named self-test read as a validated instrument. Nothing in either shape says "the thing I check and the thing that runs are not the same thing."

The general shape: **the guard and the subject must be one artifact.** When the behavior that decides the property lives outside the artifact the guard names — one call frame up, or in a second copy — the guard is measuring something adjacent to the claim and reporting it as the claim.

## Learning Level

- **Level:** Pattern — third recording. See Rule Scope § Sibling docs.
- **Feedback loop or delay:** a missing feedback loop that *strengthens* with each fix attempt. Every round added a green assertion, so measured confidence rose while actual coverage stayed at zero. The two intermediate fixes were not neutral: each one made the suite look more thoroughly tested than it had been, which is why neither was questioned until the property was mutated end to end.

## Rule Scope

- **Applies when:** a guard's behavior is selected by an argument its callers pass, *or* the self-test and the live check hold separate copies of the same logic. The tell is that you can state the property only as a sentence about two things — "the reader, called this way" — while the test names one of them.
- **Inverts or does not apply when:** the guard is a pure predicate with no mode parameter and exactly one definition, where the self-test's scope and the property's scope already coincide. It also does not apply to a parameter that is *data* rather than *direction* — passing the records to scan is not the defect; passing which end to scan is.
- **The durable fix is subtraction, not more testing.** Removing the parameter made the invertible thing not exist. A test for the flag combination would have worked too and would have been the weaker fix — one more artifact to keep in step, where the pairwise scan simply has no direction to get backwards. Reach for the test only when the parameter cannot be removed.
- **Sibling docs:**
  - `partial-oracle-selfcheck-2026-08-22.md` — the direct parent. Its class is *a guard whose own coverage is a hand-maintained subset of the thing it guards*; this entry is the case where coverage of the named thing is **total** and still establishes nothing, because the property was never confined to it. Its Prevention rule (*choose oracle mutations adversarially against the guard's coverage*) was followed here and was not sufficient: `extreme()`'s fixture *was* the adversarial choice, and the adversary was in the wrong file.
  - `mechanism-generality-lags-the-pattern-2026-08-23.md` — the second recording. `scripts/test-oracle-table-coverage.sh`, the mechanism written for the parent, could not fire here: it keys on `case "$1" in` and this suite holds no case table. A third mechanism was needed for a third syntax, which is that entry's thesis restated.
  - `mutate-the-oracle-not-only-the-subject-2026-08-19.md` — the grandparent. Its rule was followed; see Prevention for why following it was compatible with shipping this.
  - `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — the family root: a property asserted with nothing constructing it.

## Solution

**Remove the invertible parameter, and give the live check and the self-test one definition to share.**

**Before** — direction in a caller's argument, self-test total over the wrong scope:

```bash
tallest_paper="$(extreme "$records" paper 1)"
shortest_book="$(extreme "$records" book 0)"
[ "$tp_h" -ge "$sb_h" ] && bad "a paper renders at least as tall as a book"
```

**After** — one `offprint_scan`, called by both the live check and its self-test, asking the property directly:

```bash
offprint_scan() {
    printf '%s\n' "$1" | awk -F"$(printf '\t')" '
        $2 == "paper" { pw[++np] = $1; ph[np] = $3 + 0 }
        $2 == "book"  { bw[++nb] = $1; bh[nb] = $3 + 0 }
        END {
            for (i = 1; i <= np; i++)
                for (j = 1; j <= nb; j++)
                    if (ph[i] >= bh[j]) { printf "%s\t%d\t%s\t%d\n", pw[i], ph[i], bw[j], bh[j]; exit }
        }'
}
```

The self-test fixture hides its violation behind a compliant paper — one paper clears the shortest book, another does not — which is precisely the case an extremes-based comparison gets wrong.

**The mechanism is `scripts/test-duplicate-guard-programs.sh`**, wired into `lefthook.yml` and `.github/workflows/validate-skills.yml`. It scans every `scripts/test-*.sh` for multi-line `awk`/`sed` readers written more than once in the same file, normalizing indentation first, because the two copies that matter are never byte-identical. Heredoc bodies are skipped as fixture data. Verified against the real defect: reconstructing the inlined-scan shape in `test-canon-coverage.sh` reports `writes the same reader 2 times (lines 653 1179)`.

**It carries a declared floor and its own self-tests, and both earned their place during construction.** The scanner shipped four defects before it worked, three of which are this family's own classes:

- Raw newlines in a tab-delimited record stream, so one program became many records and every field read landed on the wrong program.
- A heredoc-tag character class covering only double quotes, so every `<<'QUOTED'` fixture leaked back into the scan.
- A comment *inside* the awk program containing single quotes, which broke the program — and `2>/dev/null` on the invocation swallowed the parse error, so the scanner reported reading zero programs as a clean pass. The redirect is gone; silencing an instrument's error channel is how a broken instrument reports as a working one.
- Fixture programs one line below `MIN_PROGRAM_LINES`, so two of the scanner's four self-tests were passing vacuously — the parent entry's defect, reproduced inside the mechanism written to extend it. There is now a `fatal` pinning the fixture's program count against that threshold.

## Prevention

**Code-level.**

1. **A guard whose direction is a parameter is not pinned by a test on the guard.** Either remove the parameter so there is nothing to invert, or test the composition — the call site and the guard together. Prefer removal.
2. **One definition, called by both.** If the live check and the self-test need the same logic, it is a function. A pasted copy makes the self-test a test of the paste.
3. **Never redirect a reader's stderr to `/dev/null`.** A parse error and an empty result are the same output once you do, and the empty result reads as clean.
4. **A fixture must clear the threshold the detector applies to real input.** A fixture the detector is designed to ignore makes its assertion pass whether the detector works or not; pin the fixture's size against the threshold rather than assuming it.

**Process-level.** Extend the parent's adversarial-mutation rule, which this incident satisfied and survived. That rule asks which parts of the oracle the self-check does not exercise. Add the scope question in front of it:

> **Mutate the property end to end before mutating any part of it.** Break the thing the suite claims — at the subject, in the real data — and confirm red. Only then mutate the oracle. A battery aimed at the reader answers "does the reader work," and the claim is never that.

The checkable trigger, in the one-line form this family requires:

> **"If I break the claim in the real input, does this suite go red?"**

If you have not run that, the guard's green is a statement about the guard.

## Planning / Calibration Notes

- **What widened the work:** two rounds of fixes that were each correct-looking and insufficient, then a mechanism that took four iterations. The review itself was cheap; the response to it was not.
- **What tightened the work:** delegated review with a clean context. The authoring session had already declared this suite mutation-tested in both axes and believed it. Two independent sub-agents, given the diff and no history, found the hole in one pass — and the sharper of the two framings (plant a *real* page defect, then invert the flags) is what made the failure undeniable rather than theoretical.
- **Future planning adjustment:** when a slice's deliverable includes a contract test, treat the test as the primary artifact for both review and mutation budget. Three of the four defects in the parent's PR were in its mechanism; four of the defects here were in this one's.

## Actuals Worth Reusing

- **Comparable future work:** any `scripts/test-*.sh` added under `CLAUDE.md` rule (b), especially one whose live check and self-test share logic.
- **Reusable baseline:** a scanner over source text costs roughly three to four iterations before its extractor is right, and most of that cost is in quoting — heredoc tags, quotes inside embedded programs, quotes inside comments inside embedded programs. Budget for the extractor, not the assertions. Expect at least one defect in the mechanism to be an instance of the class the mechanism exists to catch.

## Defect Classification

**Origin phase:** Design error — the guard's scope was reasoned about carefully at each step, and the property's scope never was.
**Fix type:** Correction. The instance is fixed by removing the parameter; the class is fixed by a scanner that cannot be satisfied by a self-test exercising a copy. The composition half — a reader whose direction is a caller's literal — remains unmechanized, and the entry says so rather than implying full coverage.

## Related

- PR #279 — the canon section's bookcase form, where this surfaced
- Issue #274 — the driving issue
- `partial-oracle-selfcheck-2026-08-22.md` — parent
- `mechanism-generality-lags-the-pattern-2026-08-23.md` — second recording of the same pattern

## Shelf Life

Evergreen. The rule is about the relationship between a guard's scope and a property's scope, not about bash, awk, or contract suites.

`scripts/test-duplicate-guard-programs.sh` is bash-and-awk-specific and will need extending when a suite grows a reader in another shape — that is a gap in the mechanism, not the lesson, and it is the same gap `mechanism-generality-lags-the-pattern` predicted for its predecessor.

This family now has four rungs describing one thing: **an artifact that establishes less than it appears to.** The parent's Shelf Life asked for a consolidation rather than a fourth entry, and this one is filed separately anyway because its distinguishing move is a *design* rule the others do not carry — remove the invertible parameter rather than test it. If a consolidation is written, that rule is the part that must survive it.
