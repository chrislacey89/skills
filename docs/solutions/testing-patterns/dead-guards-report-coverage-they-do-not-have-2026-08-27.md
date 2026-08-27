---
date: 2026-08-27
category: testing-patterns
problem_type: a guard written to prove a check is non-vacuous is itself unable to fire, so it reports coverage while providing none — and the comment above it asserts a verification that was never run
components: [scripts/test-*.sh, contract-test suites]
technologies: [bash, awk, grep, shellcheck]
severity: high
volatility: evergreen
---

# A guard that cannot fire reports coverage it does not have

## Problem

A change that hardened three contract-test extractors shipped four instances of the defect class it was written to remove. Two of the four were **guards that could not fire** — non-vacuity checks whose conditions were unreachable — and one of those carried a comment claiming it had been verified.

## Context

`scripts/test-*.sh` in this repo assert prose claims against real files. Several extractors reached for a *paragraph* and grabbed a *physical line*, which reads as correct only because a paragraph here is usually one line. PR #296 fixed three of them and added floors to prove the fixed extractors had not narrowed.

The floors are the part that failed. Each one printed nothing, which is what a healthy floor does, and each one would have printed nothing no matter what the code did.

## Symptoms

- A suite reports its normal `N passed, 0 failed` while the property it names is violated.
- Deleting the operation a guard protects does not change the output.
- A comment above a guard says "Verified: …" and the guard has no such behavior.
- A corrective commit's own hunks match the pattern the commit message describes removing.

## Root Cause

Three distinct mechanisms, one shared shape — **the unit a check operates on is not the unit its claim is about**:

1. **`set -e` is suppressed in the left operand of `||`.** `( cd …; git commit … ) || fatal "could not build the repo"` runs past a failed commit and exits with the status of the subshell's *last* command. Reproduced under a global `core.hooksPath` whose `pre-commit` rejects: the commit failed, the guard stayed silent, the suite passed because `git diff` fell back to index-vs-worktree and happened to agree.

2. **A comparison whose operands had both been through the same transformation.** A non-vacuity check compared a value against another value after both had had the same prefix stripped, so they always differed and the condition was unreachable. Deleting the operation it guarded left the suite at `13 passed, 0 failed`.

3. **`grep -c` counts lines, not occurrences.** Where a paragraph is a line, `grep -c` for "declared exactly once" returns 1 for a paragraph containing two declarations — so the "declare it once" failure arm was unreachable for precisely the duplicates most likely to occur. Two "sentence count" floors had the same bug: on a single logical line they could only ever return 0 or 1, presence tests wearing a count's name.

The deeper cause is why **none of this was caught by the audit the same PR ran.** That audit enumerated six *syntactic extractor shapes* — assignments from `grep`/`sed`/`awk`, range extractors, `while read` loops, chunk-returning functions, parameter expansion, `cut`/`tr` pipelines. The property is "the extraction unit does not match the claim's unit." A **counter** has that property in a syntax none of the six passes name, so `grep -c` was invisible to a sweep looking for extractors.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** A missing feedback loop with a sign error. A dead guard's output is indistinguishable from a healthy guard's output — both print nothing — so the signal that would prompt investigation is *identical* to the signal that says all is well. The absence of an alarm reads as the absence of a problem, and the longer a dead guard sits, the more confidently it is cited as coverage.

## Rule Scope

- **Applies when:** a check's healthy state is *silence* — floors, non-vacuity guards, `fatal` on a precondition, "no offenders found" detectors. These are the checks whose failure to fire is unobservable from their output.
- **Inverts or does not apply when:** the check's healthy state is a positive assertion that names what it found (`ok "23 cross-references discovered and resolved"`). Those self-report their own reach; a floor under them is belt-and-braces, not the load-bearing guard. Also does not apply to a check whose subject changes every run — there, a stale guard shows up as a flake rather than as silence.
- **Sibling docs:**
  - `validate-the-instrument-not-only-the-subject-2026-08-23.md` — the family: the failing thing is the reviewer's own instrument, and it fails while reporting normally.
  - `partial-oracle-selfcheck-2026-08-22.md` — the adjacent shape, where the comment above a loop asserts a property the loop does not have. Same author-time move, third recording.
  - `mechanism-generality-lags-the-pattern-2026-08-23.md` — why the audit missed instance 3: the mechanism (and the sweep) inherited the syntax of the instance that produced it.
  - `sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — the containing pattern; see Defect Clustering below.

## Solution

**Before** — a guard that cannot fire:

```bash
( cd "$scratch"; git init -q .; git commit -qm base ) \
    || fatal "could not build the scratch repo"
```

**After** — check the result, not the subshell's exit status:

```bash
( cd "$scratch"; git init -q .; git commit -qm base )
git -C "$scratch" rev-parse --verify HEAD >/dev/null 2>&1 \
    || fatal "no commit exists in $scratch, so every diff below would be measuring an unborn branch."
```

**Before** — a comparison that is always false:

```bash
judge_prose="records the reviewer${judge_line#*records the reviewer}"
judge_prose="${judge_prose%%. *}"
[[ "$judge_prose" == "$judge_line" ]] && fatal "the sentence did not narrow"
```

**After** — compare against the value the operation actually consumed:

```bash
judge_from_anchor="records the reviewer${judge_line#*records the reviewer}"
judge_prose="${judge_from_anchor%%. *}"
[[ "$judge_prose" == "$judge_from_anchor" ]] && fatal "the sentence did not narrow"
```

**Before / After** — count occurrences, not lines:

```bash
guard_hits="$(grep -c -F -- "$marker" "$file")"                        # counts LINES
guard_hits="$(grep -o -F -- "$marker" "$file" | wc -l | tr -d ' ')"    # counts OCCURRENCES
```

**The operational test, and it is cheap.** Before writing "this guard catches X," delete X and run the suite. If the output does not change, the guard is decoration. Every one of these was found that way in under a minute — by a reviewer, after merge-readiness, not by the author who wrote the claim.

## Prevention

**Code-level:** `scripts/test-guards-can-fire.sh` (added with this entry). Two decidable detectors over every contract suite:

- a subshell used as the left operand of `||`
- an `awk` paragraph reader (`RS=""`) matching its anchor against `$0` rather than an unwrapped record

Each detector has a **self-test** rather than a floor — it is run against a fixture it must flag and a corrected fixture it must not — because a detector whose healthy state is zero hits is exactly the one that rots silently (`mechanism-generality-lags-the-pattern` Prevention #2). The suite excludes itself from its own file scan, since its fixtures are executable examples of what it forbids; that cost is stated in its header, and the self-tests are what make the exclusion survivable.

It does **not** close the class, and says so: a guard can be dead for reasons no grep can see — a comparison whose operands are always equal, a `case` arm no value reaches.

**Process-level:** `/pre-merge`'s delegated review is what caught all four here, and that is the finding worth carrying. The authoring session held every rationalization it had made while writing the guards; two independent sub-agents on the same diff found the same defects within one pass each. The relevant `/pre-merge` rule — delegation is unconditional because the reviewer must not be the author — did its job. **What is missing upstream is the author-time counterpart:** `/execute` Step 4 has a "mutate at the point of consumption" rung that applies to the *test*, but nothing that applies to a *guard on a test*. A guard is a claim like any other and should be mutation-checked before its comment is written.

## Defect Clustering

**This is a second recording of `sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md`**, whose Prevention § Process-level already prescribes the exact question this PR failed:

> "does the corrective hunk itself satisfy the rule it enforces? … the highest-yield place to look is the correction, not the code around it."

That entry predicted "roughly one escaped instance per sweep until a mechanism exists." This sweep produced four. Prose was the deliverable the first time and the pattern recurred anyway, so per `/compound` Phase 4 this entry ships a mechanism rather than a third prose-only recording — `scripts/test-guards-can-fire.sh`, registered in `lefthook.yml` and `.github/workflows/validate-skills.yml`.

The mechanism is narrower than the pattern, deliberately. It catches two syntactic shapes out of a class that is not decidable in general. That is the honest reach, and naming it is what stops the next reader citing this suite as coverage it does not provide.

## Planning / Calibration Notes

- **What widened the work:** the review, correctly. Four escapes plus eight smaller findings turned a "fix two extractors" slice into a second commit roughly the size of the first. Budget for a real fix pass after `/pre-merge` on any change whose subject *is* the checking layer.
- **What tightened the work:** mutation testing as the red bar. Every extractor fix was proved by planting the defect and watching a named assertion fail. The guards were the parts *not* proved that way — which is the whole entry in one line.
- **Future planning adjustment:** when a slice's subject is the mechanism layer itself, treat "the corrective hunk carries the defect" as the expected case rather than the tail risk, and schedule the review before believing the diff.

## Related

- PR #296, issue #295
- `docs/solutions/architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md`
- `docs/solutions/testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md`
- `docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md`
- `docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md`

## Shelf Life

Evergreen — no expiration condition. The specific detectors are tied to bash and awk idioms and would go stale if the suites were rewritten in another language, but the shape (a check whose healthy state is silence cannot distinguish "nothing wrong" from "not looking") outlives any implementation.
