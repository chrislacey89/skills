---
date: 2026-08-18
updated: 2026-08-26
category: architecture-decisions
problem_type: corrective commit re-introduces the defect class it was written to remove
components: [pre-merge, execute, compound, tdd, docs, skill-references]
technologies: [markdown, bash, git]
severity: medium
volatility: stable
---

# A sweep commit tends to add the N+1th instance of the class it is sweeping

## Problem

A commit written to fix every instance of a defect introduced a fresh instance of the same defect, three times in a row on one branch. Each corrective commit was itself correct about the instances it had found, and each one was wrong in the same idiom that produced them.

## Context

PR #246 (issue #245) added an `options-comparison` block across three shared docs. Four review passes ran under `/pre-merge --loop`. Three of the four found a defect **created by the previous pass's fix**:

| Sweep | What it correctly fixed | What it introduced | Caught by |
|---|---|---|---|
| `84e347e` | Two of three sites saying the wireframe was "the one model-authored block"; the manifest rows making §11's pointers resolve | Missed `visual-recap/SKILL.md:106` — the file that *points at* both docs and loads before either. Wrote `references/visual-recap-design.md` into a file that is itself bundled into `references/`, so it would resolve to `references/references/` | pass 2, pass 3 |
| `ebe716a` | All five pointers, to the bare-sibling form that resolves in-repo and post-install | — (clean) | — |
| `4afdba3` | Eleven open ledger rows, including a contract test to stop exactly this drift | A `/pre-merge` Phase 4 paragraph telling the phase to "take the choice with `AskUserQuestion`" — a choice Phase 4 does not own, in a phase whose own output says "No action is required" | pass 4 |
| `4afdba3` | (the contract test) | The test passed with an option set to `0 cited · 5 asserted`; its note check was line-scoped where the serializer is descendant-scoped | pass 4 mutation test |

The last row is the sharpest instance: the artifact written specifically to prevent this defect class contained the defect class.

**And then this entry did it too.** The first draft cited `visual-recap/SKILL.md:104` — a line number made stale two commits earlier by a paragraph *this same PR* inserted above it — and attributed "discipline-shaped fix" to `docs/skill-anatomy.md`, which does not contain the phrase; it is `/improve-pipeline`'s classifier. Both were caught by running this entry's own Solution against the entry. The verification grep had a bug of its own (`rg -r` is `--replace`, not recursive), which briefly made a real phrase look fabricated. Four sweeps, four fresh instances. Treat the pattern as robust.

## Second observation (2026-08-26, PR #282 / issue #280)

The pattern recurred on a branch whose **entire subject was this defect class**, which
makes it the strongest instance recorded so far. The branch added guidance telling
authors to consolidate a claim restated across several sites in prose no compiler checks.

| Commit | What it correctly fixed | What it introduced | Caught by |
|---|---|---|---|
| `6933de8` | — (the initial rule) | Gave the remedy with no census move, and prescribed an assertion that counts the *new* literal and so cannot see a reworded restatement | review 1 |
| `1f8c000` | The census, the assertion's limit, and the missing reviewer-time detector | Stated the rule at **two** sites that disagreed three ways on arrival — "error-message contract" vs "template", "every verdict" vs "each verdict", and a library gloss attributed to a page number | review 2 |
| `8e967f6` | Made the two sites one site via `scripts/skill-references.manifest` | Left the census procedure written out in the checklist, two sentences before the line saying the reference carries it — the exact sentence its own commit message claimed to have fixed | review 3 |
| `8e967f6` | (the consolidation) | Both consumers glossed the canonical definition as "no compiler" where canonical reads "no compiler, type checker, or schema" — a divergence on day one | review 3 |

Two further details worth keeping:

**The detector could not fire on the commits that carried the defect.** Its trigger read
"the same claim is stated at other operative sites *the diff leaves untouched*." Both
offending commits wrote all their sites in one change, so a reviewer working the bullet
checks its precondition, finds nothing untouched, and moves on. A trigger written from the
*previous* incident's shape — stale sites left behind — missed the shape in front of it.

**The census grep returned a false clean.** The first verification ran `rg` line-scoped
against a phrase the file had wrapped across two lines, and reported zero matches in a file
that contained it. Every census since normalizes whitespace first (`tr '\n' ' '`). This is
the same genre as this entry's original `rg -r` bug: the sweep's *instrument* is drawn from
the same well as the sweep.

## Symptoms

- A commit message credibly says "swept every instance," and a later reviewer finds one it missed **in the file that references the ones it fixed**.
- The missed instance is in a different *kind* of file from the fixed ones — a `SKILL.md` when the sweep was over `docs/`, a test when the sweep was over prose.
- The fix for defect X is written in the idiom that produced X. A path-prefix fix uses the wrong path prefix. A "state the rule numerically" fix states a second rule in prose.
- Consecutive commits on one branch each carry a `Refs #N` and each fix the previous one.

## Root Cause

Not carelessness, and not insufficient rigor — each sweep enumerated deliberately and each was checked. Two structural causes:

**The sweeper edits in the idiom that produced the defect.** Fixing a wrong path prefix means *writing path prefixes*, at the moment the author's model of "which prefix is right" is the model that was just shown to be wrong. The correction and the defect are drawn from the same well.

**Grep finds the shape you already understand.** A sweep is scoped by the query that found the known instances. `rg 'docs/next-step-menu.md'` cannot find `references/visual-recap-design.md`, and `rg 'the one model-authored'` over `docs/` cannot find the `SKILL.md` that points at `docs/`. The instances that escape are the ones in a *different* shape or a *different file class* — precisely the ones the enumeration was blind to.

## Learning Level

- **Level:** **Structure**, as of the second observation. Promoted from Pattern (three instances, one branch) on 2026-08-26: PR #282 reproduced it across a second, unrelated branch, and did so *while the branch's own subject was this defect class*. Three prose statements of the rule were in the author's context and did not prevent it. The recurring condition is not a habit — it is that prose is the medium an author reaches for when the artifact in front of them is prose, even when a generating mechanism already exists in the repo. See Rule Scope for the shapes where it does not hold.
- **Feedback loop or delay:** the detection loop worked and the *prevention* loop did not. Every instance was caught, by review, one pass late. That is a balancing loop with a delay equal to one review cycle — self-correcting but not convergent, since each correction is a new opportunity to inject. Convergence came from a mechanism (`scripts/test-options-comparison-contract.sh`), not from more care.

## Rule Scope

- **Applies when** all three hold:
  - The defect is **textual and multi-site** — the same claim, path, or count restated in several files, with no compiler or type system relating them.
  - The sweep is **enumerated by search** rather than by a structural list, so its completeness is bounded by the query's shape.
  - The correction is written in **the same medium** as the defect (prose fixing prose, a path fixing a path), so the author's just-falsified model is the one authoring the fix.
- **Inverts or does not apply when:**
  - A compiler, type checker, or schema relates the sites. Renaming a symbol across a typed codebase is not this shape — the tool enumerates, and a miss fails the build rather than shipping.
  - The sweep is over a **generated or synced** surface. The ten `<skill>/references/` mirrors in this PR were never at risk; `sync-skill-references.sh --check` makes a partial sweep impossible by construction. **This is the exemption to engineer into, not merely to note.** PR #282 spent three corrections restating a rule across two skills that could both have taken a synced copy — the exemption was one manifest row away and was reached for only on the fourth attempt. Before sweeping a textual multi-site defect, ask first whether every consumer can accept a generated copy; if so, the sweep is the wrong move entirely.
  - The instances are genuinely independent — three unrelated typos are three events, and treating them as a class manufactures a pattern.
- **Sibling docs:**
  - `by-construction-claims-need-a-mechanism-2026-08-11.md` — the adjacent shape and the prescribed cure. That entry says a cross-file agreement asserted in prose needs a test shipped *in the same change*. This entry is the empirical case for **why that timing clause is load-bearing**: the sweep that would have added the test late is the same sweep that adds the next instance.
  - `deletion-unit-is-function-not-syntax-2026-08-15.md` — the same completeness failure in the deletion direction, where the unit of removal was drawn too narrowly.
  - `self-review-blind-to-composition-2026-08-13.md` — why the catching party has to be a fresh context. Every instance here was found by a sub-agent that had not written the sweep.

## Solution

**Do not trust a sweep that was scoped by the query that found the defect.** Three moves, in increasing order of cost:

1. **Widen the enumeration past the file class you started in.** After sweeping `docs/`, grep the files that *point at* `docs/` — `*/SKILL.md`, `CLAUDE.md`, `SYSTEM-OVERVIEW.md`, `CHANGELOG.md`. The instance that escapes is usually one indirection out.

   ```bash
   # not this, which only sees where you already looked
   rg 'the one model-authored' docs/
   # this — every file class, minus generated mirrors and frozen history
   rg 'the one model-authored' . -g '!**/references/**' -g '!CHANGELOG.md'
   ```

2. **Re-read the correction against the rule it enforces.** The `references/references/` bug survived because the author checked that the *old* pointer was wrong, not that the *new* one was right. One question closes it: does the text I just wrote satisfy the rule I am applying?

3. **Ship a mechanism, and break it before trusting it.** A contract test converts the class from "caught next pass" to "cannot land." But a test that has only ever seen a clean tree pins its own assumptions — this one passed on a `0 cited · 5 asserted` column, the exact violation it existed to prevent.

**Before:**

```bash
# a test that has only run green
bash scripts/test-options-comparison-contract.sh   # 27 passed — proves nothing yet
```

**After:**

```bash
# break each rule once, confirm the suite fails, revert
cp docs/visual-recap-design.md /tmp/bak
#   set an option to "0 cited · 5 asserted"
bash scripts/test-options-comparison-contract.sh   # FAIL: floor is at least 1  ✓
cp /tmp/bak docs/visual-recap-design.md
bash scripts/test-options-comparison-contract.sh   # 28 passed  ✓
```

Mutation-testing found two holes in a 27-assertion suite written by an author who believed it was thorough.

## Prevention

**Code-level — check for the generated route before writing the pin.** If every consumer can accept a synced copy, put the text in one file and let `scripts/skill-references.manifest` carry it; the class is then gone rather than detected. Only when some consumer must hold the text inline does the pin become the right instrument. Ship the pinning test in the same change as the restatement — `by-construction-claims-need-a-mechanism-2026-08-11.md`'s existing rule, and this entry is its cost of deferral. Then mutation-test it in both directions: fail on a broken tree, pass on a clean one. An assertion that has never failed is a hypothesis. Where the surface can be generated instead of restated, generate it — the mirrors in this PR were structurally exempt from the whole class.

**Code-level, second observation.** `scripts/test-bundled-pointer-resolution.sh` closes the sub-class the manifest route opens: a pointer at a bundled reference that does not resolve, the `references/references/` prefix bug this entry's first observation recorded, and a hand copy of an upstream file sitting without a manifest row. Mutation-tested in four directions including an oracle mutation on the link extractor itself.

**Process-level.** `/pre-merge` Dimension 1 now carries a *Restated claim in unchecked prose* detector, added in PR #282, which routes to `docs/restated-claims.md` rather than restating the remedy. Note the trigger's own history: as first written it fired only on sites *the diff leaves untouched*, and so could not fire on either commit in that branch that carried the defect — both wrote all their sites at once. A trigger drawn from the previous incident's shape misses the next one. Separately, `/pre-merge` Dimension 9 (Fix Completeness) already asks whether structural siblings were found; the gap is that it reads the diff as a *fix* and not as *new text that can carry the same defect*. The cheap addition is one question at the point of review: **does the corrective hunk itself satisfy the rule it enforces?** Reviewing a sweep is not the same job as reviewing a feature — the highest-yield place to look is the correction, not the code around it.

The loop-mode ledger is what made this visible at all. Four passes with durable rows showed *findings introduced by the previous fix* as a countable series (8 → 5 → 3 → 3); in a single advisory pass each would have read as an unrelated miss.

## Planning / Calibration Notes

- **What widened the work:** the fix cycle, not the feature. Original scope was three doc edits and a manifest decision; shipped scope was six commits, four review passes, and a new test suite. Four of the six commits are corrections, and three of those correct a correction.
- **What tightened the work:** the contract test. After it landed, the remaining findings were about the test rather than the docs — the drift class was closed and the frontier moved.
- **Future planning adjustment:** when `/write-a-prd` or `/prd-to-issues` scopes work whose deliverable is *a rule restated across N files*, budget the pinning test as part of the slice rather than as a follow-up. It is not polish; it is what stops the fix cycle from being longer than the feature.

## Actuals Worth Reusing

- **Comparable future work:** any change adding a shared convention to `docs/` that skills restate — a new block in the rendering core, a new threshold, a new id shape.
- **Reusable baseline:** three doc edits produced six commits. Expect the correction tail to exceed the original change when the deliverable is multi-site prose with no compiler relating the sites, and expect roughly one escaped instance per sweep until a mechanism exists.

## Defect Classification

**Origin phase:** Design error — the sweep's *enumeration strategy* was wrong, not its execution. Each commit correctly fixed what it had found.
**Fix type:** Correction. `scripts/test-options-comparison-contract.sh` removes the class for these specific claims (threshold numbers, the cited/asserted floor, the chip bar, the `opt-` id, block counts, the carve-out count) rather than suppressing a symptom. The general pattern is unfixed and probably unfixable by tooling — the process-level question above is the mitigation.

## Key Decision

**Decision:** Close the class with a contract test plus a mutation check, rather than with a checklist item asking authors to sweep more carefully.
**Rationale:** Every instance here was produced by an author who was already sweeping carefully and enumerating deliberately. A rule that asks for more of what already failed is what `/improve-pipeline` classifies as a *discipline-shaped fix in disguise* (`improve-pipeline/SKILL.md:130`): a remedy that "requires the user to remember, notice, or do something," to be reclassified and replaced with a knowledge-in-the-world equivalent. The test is knowledge in the world.
**Alternatives considered:** A `/pre-merge` checklist item alone (rejected — advisory, and the advisory version is what missed three times); generating the restatements from a single source (rejected in 2026-08 for the *rendering-core* case, on the ground that the four skills which cannot read the core genuinely need the text inline).

**Revised 2026-08-26 — the rejection was scoped too widely, and its revision trigger named the wrong variable.** PR #282's restatement crossed exactly two skills, *both* of which could accept a bundled copy. `scripts/skill-references.manifest` plus `sync-skill-references.sh --check` therefore applied and made the class impossible — one canonical file in `docs/`, synced copies under each `<skill>/references/`, CI failing on drift. That mechanism existed the whole time and was not reached for, across three consecutive corrections, because the artifact in front of the author was prose and prose is what an author reaches for.

Split the decision by consumer, not by count:

- **Every consumer can bundle the doc** → put it in `docs/`, add manifest rows, and let the consumers reference it by name. The class is gone by construction. `docs/restated-claims.md` is the worked example.
- **Some consumer must carry the text inline** → the original rejection stands; pin with a contract test and mutation-check it.

**Revisable:** The old trigger — "if the restatement count grows past a handful of docs" — is wrong and is retired. Count was never the variable; **whether every consumer can accept a bundled copy** is. A two-site restatement across two bundling skills already warrants generation, and a twenty-site one across skills that cannot bundle still does not.

## Related

- PR #246, issue #245 — the branch this pattern was observed on
- `scripts/test-options-comparison-contract.sh` — the mechanism for the first observation
- PR #282, issue #280 — the second observation
- `docs/restated-claims.md` — the canonical statement of this class, and the worked example of the bundled-copy remedy
- `scripts/test-bundled-pointer-resolution.sh` — the mechanism for the second observation: pins that every bundled-reference pointer resolves, that no file inside `references/` writes the `references/` prefix, and that a copy of an upstream file has a manifest row
- `docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — the rule this entry supplies evidence for
- `docs/solutions/architecture-decisions/deletion-unit-is-function-not-syntax-2026-08-15.md` — the same completeness failure, deletion direction
- `docs/solutions/architecture-decisions/self-review-blind-to-composition-2026-08-13.md` — why a fresh context caught every instance

## Shelf Life

Stable. Supersede if the repo adopts generation for cross-file restatements (which would make the enumeration structural rather than search-scoped), or if a later sample shows sweeps landing clean without a pinning test — this is one branch and one author, which is why Rule Scope calls it Pattern and not Structure. If two or three more branches show the same series, promote it: the claim would then be about how corrections are authored generally, not about this repo's prose surfaces.
