---
date: 2026-08-18
updated: 2026-09-04
category: architecture-decisions
problem_type: corrective commit re-introduces the defect class it was written to remove
components: [pre-merge, execute, compound, tdd, fix-findings, docs, skill-references, scripts]
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

## Third observation (2026-08-28, PR #309 / issue #305) — the medium was executable, not prose

The first two observations were prose fixing prose. This one is **a contract test fixing a contract test**, which is why it is recorded here rather than filed separately: it is the same structure in a medium the Rule Scope did not yet cover, and it widens that scope (below).

Issue #305 removed a CSS token, `--sx-t`, from a palette two skills copy verbatim. The palette had a defect: it measured that a token was *named*, never that it *covered the language being rendered* — so an agent hit a gap, invented a token, and repurposed another, which is the incident #305 exists for.

| Round | Artifact | What its mechanism actually measured | What its label claimed |
|---|---|---|---|
| 1 | the palette itself | a token was *named* | a working vocabulary |
| 2 | `test-syntax-palette-contract.sh`, written to pin round 1 | a token was *named and present* | *shown, distinct, counted* |
| 3 | the checks written to fix round 2 | tokens it could *parse*; a claim it could *read* | all tokens, all claims |

Round 2 shipped four assertions that could not fail, each confirmed by mutation: a straggler detector that stayed green with an unmatchable pattern **and** when run outside a git work tree (a trailing `|| true` turned a dead instrument into a clean bill of health); a "demonstration" assertion — the one the suite's own header called load-bearing — satisfied by prose that merely *named* a token rather than a span that colored something; a contract pinning the deleted token's *name* rather than the two properties that condemned it, so re-adding it under another name passed at 26/0; and a `$` matcher met by `costs US$5`.

Round 3, written in the same session by the author who had just diagnosed round 2, shipped three more:

- The first draft of the guard closing "the detector cannot fire" **put its `exit` inside `$( … )`**, where it kills only the subshell. The FATAL printed to stderr, the assignment yielded empty, the assertion compared that emptiness and passed, and the run reported **27 passed, 0 failed, exit 0**.
- The fixture builder for that guard was written as `( cd … ) || fatal` — the unfireable-guard shape `scripts/test-guards-can-fire.sh` already existed to detect. **The repo's own mechanism caught it**, which is the first time in three observations that anything but a human or a fresh-context sub-agent did.
- A token whose value was not `hsl()`/`hsla()` was silently dropped by the new color parser, exempting it from the distinctness floor entirely — five tokens measured where six were declared, with no line saying one had gone missing. Separately, the new AA-claim parser **died silently** on a sentence it could not read: section header, then nothing, no summary, exit 1, because `grep -oE` matching nothing returns 1 and `pipefail` inside `$( … )` trips `set -e`.

And then the mechanism written for *this* observation did it once more. Detector C (below) shipped a first draft matching the word `exit` anywhere in a helper body — which flagged **nine** correct helpers whose `exit` was an awk statement inside an embedded awk program. A detector that reddens on correct code is worse than none, because the fix is to delete it. Its own self-test caught two further defects in it before it ran clean: an extractor blind to one-liner function definitions (and `fatal() { …; exit 2; }` is a one-liner in most suites here, so it would have missed every real case), and a call-site regex requiring a boundary character that `\$\(` had already consumed, so it silently matched nothing.

**Four rounds, four fresh instances, in executable code rather than prose.** The count is the same as observation one; the medium is not.

## Fourth observation (2026-09-04, PR #342 / issue #341) — three independent authors, one clause

The first three observations all had the same author writing each correction, and the Root Cause below leans on that: *"the author's just-falsified model is the one authoring the fix."* This observation removes that condition. Every round was written by a **different fresh sub-agent** under `/fix-findings`, none of which had seen the others' work, the authoring session's reasoning, or any prior round. The structure held anyway.

The subject was one paragraph of `fix-findings/SKILL.md` — the rule governing what a breaker may read.

| Round | What it correctly fixed | What it introduced | Caught by |
|---|---|---|---|
| `a2efa0e` | — (introduced the rule) an absolute ban: *"never reads the original tree — not `git status`, not the working files, not for orientation"* | Contradicted a standing instruction 48 lines below telling the breaker to copy `.env.local` and symlink a dependency tree — every project with a lockfile loses its breaker pass | review 1 |
| `8565487` | Scoped the head clause to *"for evidence about the fix"*, un-blocking the dependency carry | Left the enumerated tail standing. "Not for orientation" no longer followed from the clause it hung off, and the new carve-out's own stated test cleared `git status` for orientation — reopening the exact incident the rule exists to close | review 2 |
| `3ac8980` | Re-derived the rule from the hazard — mutability, not purpose. The ban's tail now follows: *"never reads the original working tree and never resolves a moving ref — not `git status`, not the working files, not `HEAD`"* | A **new** two-item tail in the permission paragraph: *"rather than inferring the diff from the working files or from the fixer's report."* The report cannot move, so under the rewrite's own rule it is permitted — a purpose-scoped ban left inside a mutability-scoped rule | the breaker for round 3 |

**The unit was a clause, not a site.** Rule Scope's second bullet describes a sweep "enumerated by search," and observation 3 already loosened the conjunction. This loosens it further: there was no enumeration, no query, no second site. One sentence, edited at the head, with the tail left behind. The structure does not need multiplicity — it needs an *unchecked relation between two parts of one statement*, and a head clause and its enumerated tail are two parts.

**Round 3's fixer was briefed on the exact failure mode and reproduced it anyway.** It was handed `git show` of the commit that caused the defect, told that narrowing a head clause while leaving its tail standing was what went wrong, and given four named cases to check its output against. It checked all four correctly — and wrote the fifth instance into a sentence explaining the fix. This is the sharpest evidence yet that the existing Solution's move 2 (*"does the text I just wrote satisfy the rule I am applying?"*) is necessary but not sufficient: the fixer applied it to the four cases it was given and not to the prose it authored around them.

**No mechanism could have caught any round, and this is the correct outcome rather than a gap.** A breaker verified it by reversion rather than inspection: reverting each fix in turn produced zero change in suite outcome, and deleting the entire 1,464-character rule left all 28 suites green. The defect is the semantic relation between a clause and its tail, which is exactly the meaning-claim `#340` rules out sending to a grep — and which `prose-contract-tests-are-restated-claims-2026-08-27.md` says becomes a second restatement if you try. The mitigation here is procedural, not mechanical.

## Symptoms

- A commit message credibly says "swept every instance," and a later reviewer finds one it missed **in the file that references the ones it fixed**.
- The missed instance is in a different *kind* of file from the fixed ones — a `SKILL.md` when the sweep was over `docs/`, a test when the sweep was over prose.
- The fix for defect X is written in the idiom that produced X. A path-prefix fix uses the wrong path prefix. A "state the rule numerically" fix states a second rule in prose.
- Consecutive commits on one branch each carry a `Refs #N` and each fix the previous one.
- A rule's **head clause is re-scoped and its enumerated tail is not**, so one item in the list no longer follows from the clause it hangs off. The tail still reads as true, because it was true under the old scope.

## Root Cause

Not carelessness, and not insufficient rigor — each sweep enumerated deliberately and each was checked. Two structural causes:

**The sweeper edits in the idiom that produced the defect.** Fixing a wrong path prefix means *writing path prefixes*, at the moment the author's model of "which prefix is right" is the model that was just shown to be wrong. The correction and the defect are drawn from the same well.

**The author condition is not necessary (2026-09-04).** Observation 4's three corrections were written by three fresh sub-agents with no shared context, and reproduced the structure regardless. So the first cause above describes a *sufficient* aggravator, not the mechanism. What survives is the artifact: a statement with two parts and nothing relating them holds its defect open for whoever edits it next, however clean their context. Read the first cause as raising the rate, not as the cause.

**Grep finds the shape you already understand.** A sweep is scoped by the query that found the known instances. `rg 'docs/next-step-menu.md'` cannot find `references/visual-recap-design.md`, and `rg 'the one model-authored'` over `docs/` cannot find the `SKILL.md` that points at `docs/`. The instances that escape are the ones in a *different* shape or a *different file class* — precisely the ones the enumeration was blind to.

## Learning Level

- **Level:** **Structure**, as of the second observation. Promoted from Pattern (three instances, one branch) on 2026-08-26: PR #282 reproduced it across a second, unrelated branch, and did so *while the branch's own subject was this defect class*. Three prose statements of the rule were in the author's context and did not prevent it. The recurring condition is not a habit — it is that prose is the medium an author reaches for when the artifact in front of them is prose, even when a generating mechanism already exists in the repo. See Rule Scope for the shapes where it does not hold.
- **Feedback loop or delay:** the detection loop worked and the *prevention* loop did not. Every instance was caught, by review, one pass late. That is a balancing loop with a delay equal to one review cycle — self-correcting but not convergent, since each correction is a new opportunity to inject. Convergence came from a mechanism (`scripts/test-options-comparison-contract.sh`), not from more care.

## Rule Scope

- **Applies when** the first and third hold; the second is typical but not necessary. Observation 3 is why the conjunction was loosened: its search-scoped instances (a color parser blind to a value shape, a claim parser blind to a rewording) fit bullet 2, but its two inert-guard instances — an `exit` inside `$( … )`, a `( cd … ) || fatal` fixture — are not sweeps enumerated by any query, and the structure held for them anyway.
  - The defect is **not caught by a compiler, type system, or schema** — so nothing mechanically relates the correction to the property it is supposed to establish. Observations 1 and 2 read this as *textual and multi-site* (the same claim restated across files); observation 3 widened it, because a contract test is a single site with no restatement and reproduced the structure anyway. The general condition is the absence of a checking relation, not the presence of duplicated text.
  - The sweep is **enumerated by search** rather than by a structural list, so its completeness is bounded by the query's shape. In the executable case the query is the check's own matcher, and its blind spots are invisible in its output: a check reports on the population it could parse, never on the population it was pointed at.
  - The correction is written in **the same medium** as the defect (prose fixing prose, a path fixing a path, a check fixing a check), so the author's just-falsified model is the one authoring the fix.
  - **Multiplicity is not required (2026-09-04).** Observations 1–3 all had N sites; observation 4 had one sentence. The operative condition is an *unchecked relation between two parts of a statement* — head clause and enumerated tail, rule and carve-out, claim and citation — not a count of files. A single-site correction is in scope.

- **Inverts or does not apply when:**
  - A compiler, type checker, or schema relates the sites. Renaming a symbol across a typed codebase is not this shape — the tool enumerates, and a miss fails the build rather than shipping.
  - The sweep is over a **generated or synced** surface. The ten `<skill>/references/` mirrors in this PR were never at risk; `sync-skill-references.sh --check` makes a partial sweep impossible by construction. **This is the exemption to engineer into, not merely to note.** PR #282 spent three corrections restating a rule across two skills that could both have taken a synced copy — the exemption was one manifest row away and was reached for only on the fourth attempt. Before sweeping a textual multi-site defect, ask first whether every consumer can accept a generated copy; if so, the sweep is the wrong move entirely.
  - The instances are genuinely independent — three unrelated typos are three events, and treating them as a class manufactures a pattern.
  - **The generate-instead-of-restate exemption does not reach the executable case.** Observation 3's defects were in a single file with nothing to sync, so "let the manifest carry it" had no purchase. Where the corrective artifact is a check rather than a restatement, the only cure available is a detector for the specific shape *plus* a self-test proving that detector can fire — which is why observation 3's mechanism is a third detector in an existing suite rather than a new generated surface.
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

**Code-level, third observation.** `scripts/test-guards-can-fire.sh` gains **detector C**: a helper that can abort the run (reaches `fatal`) called inside `$( … )`, where its `exit` kills only the subshell and the run continues to a passing summary. It is a third detector rather than a widened first one because detector A keys on `)` followed by `||` at line start — syntax entirely absent from this shape — which is the failure `mechanism-generality-lags-the-pattern-2026-08-23.md` names. Both self-tests are mandatory and both caught real defects in the detector before it shipped. Its narrowing is stated in the code and is the load-bearing part: it keys on a `fatal` call, **not** the word `exit`, because nine helpers here embed awk programs whose own `exit` is correct — and it says plainly what that gives up (a bare shell `exit` outside `fatal()` is not caught).

**Process-level, third observation — the reviewable unit is the correction, not the branch.** Observation 2's Prevention already proposed the question *"does the corrective hunk itself satisfy the rule it enforces?"* Observation 3 is the case for making it unconditional after **every** corrective commit, not once per branch: three consecutive corrections each carried a fresh instance, and each was found only because something re-examined the correction specifically. Note what did the finding, in order: a fresh-context sub-agent (round 2), the repo's existing `test-guards-can-fire.sh` (round 3's fixture), and the new detector's own self-tests (round 3's detector). The trend is the point — mechanisms caught what review caught in observations 1 and 2, and they caught it at authoring time rather than one pass late. That is the delay this entry's feedback-loop note says review cannot remove.

**Process-level, fourth observation — count corrective rounds against the seam, not against the session.** Observation 4's mitigation cannot be a mechanism (see above), and it cannot be the existing per-branch or per-commit question either, because each of its three sessions made exactly one fix attempt and succeeded at what it was asked. The thrashing was visible only one level up, across sessions, at the seam. `chrislacey89/skills#202` proposes a fix-shape circuit breaker and scopes its trigger to a session; this observation is filed there as its first incurred field incident, arguing the trigger belongs on the **seam** instead, persisted where it survives a session — the `/pre-merge` ledger row or the PR body already hold that state. A fresh agent per round is what `/fix-findings` sells, and it does **not** reset this risk; it hides it, because each session's local view is one clean success. The operator's stop after round 3 was the "rely on someone to notice" path, which is the path that failed in observations 1–3.

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
- PR #309, issue #305 — the third observation, and the first in executable rather than prose medium
- `scripts/test-guards-can-fire.sh` detector C — the mechanism for the third observation: pins that a run-aborting helper is not called inside `$( … )`, where its exit cannot stop the run
- `scripts/test-syntax-palette-contract.sh` — the artifact of rounds 2 and 3; its header records the palette defect, and its straggler self-test and token-coverage floor are the round-3 repairs
- `docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md` — why detector C is a third detector and not a widened first one. **Its Shelf Life clause was considered and declined here:** it asks whether a third recording in a new shape means the family should be consolidated. Declined for now because the four rungs still have genuinely different matchers and different self-tests, and merging them would produce one detector whose narrowings are harder to state than four whose narrowings are each one paragraph — the readability of the disclosed boundary is the thing this family is about. Revisit if a fifth rung appears.
- `docs/solutions/testing-patterns/dead-guards-report-coverage-they-do-not-have-2026-08-27.md` — the nearest neighbor in `testing-patterns/`, and deliberately not the home for this: it names one artifact class (a guard that cannot fire), where the structure recorded here is that the *correction* reliably carries the defect, whatever the artifact
- `docs/solutions/architecture-decisions/self-review-blind-to-composition-2026-08-13.md` — why a fresh context caught every instance
- PR #342, issue #341 — the fourth observation, and the first where each correction had a different author
- `chrislacey89/skills#202` — the mechanism for the fourth observation: the fix-shape circuit breaker, carrying this run's field incident and the argument for a seam-scoped rather than session-scoped trigger. **Not a test**, and the entry says why: the defect is a semantic relation between a clause and its tail, which `#340` rules out sending to a grep and which `prose-contract-tests-are-restated-claims-2026-08-27.md` shows becomes a second restatement if you try. Of the five Q4 names, a contract test came closest and was rejected on that ground; a planning-checklist item was rejected as the discipline-shaped fix the Key Decision below already retires
- `docs/solutions/testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md` — why observation 4 ships no pin

## Shelf Life

Stable, and now evidenced across three branches and two media (prose, executable checks) — the promotion condition below is met, so it is no longer pending. Supersede if the repo adopts generation for cross-file restatements (which would make the enumeration structural rather than search-scoped), or if a later sample shows sweeps landing clean without a pinning test. (A clause here reading "this is one branch and one author, which is why Rule Scope calls it Pattern and not Structure" was stale from the 2026-08-26 promotion and survived the observation-3 rewrite that contradicted it two clauses earlier — this entry, committing this entry's defect class, for the third time. Caught by the review sub-agent, not by the sweep.) The 2026-08-26 note asked for two or three more branches before the claim could be about how corrections are authored generally rather than about this repo's prose surfaces. Observation 3 supplies the third branch and, more usefully, the second medium: the structure held where there was no prose, no second site, and nothing to sync. Treat the claim as general. What would still falsify it: a branch whose corrective commits land clean under the same review intensity, or a mechanism class that reliably catches these at authoring time — detector C and the round-3 self-tests are the first evidence that the second is possible.

Observation 4 (2026-09-04) removes the last author-shaped reading: three corrections, three independent fresh contexts, same structure. It also narrows what would falsify the claim — a branch landing clean is no longer enough if its corrections were authored by one context, since that is the condition observation 4 shows is not load-bearing. The falsifier is now a *seam* that survives several independent corrective rounds clean.
