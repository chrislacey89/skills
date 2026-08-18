---
date: 2026-08-11
category: architecture-decisions
problem_type: a claim asserted as holding "by construction" is maintained by hand in N files, with nothing constructing it
components: [prd-to-issues, execute, help, setup-ralph-loop, qa, pre-merge, SYSTEM-OVERVIEW]
technologies: [pipeline-design, gh-cli, github-api, cross-file-contracts]
severity: medium
volatility: stable
---

# A claim asserted as "by construction" that nothing constructs

## Problem

A pipeline change verifies an external fact once, writes the resulting rule into several skills, and asserts in prose that the copies agree "by construction." Nothing constructs the agreement — it is maintained by hand across every copy, and nothing re-checks the underlying fact. Both halves decay silently, and the assertion is what stops anyone from looking.

## Context

Issue #168 (PR #170, 2026-08-04) made the slice dependency graph queryable. While writing it, someone tried `gh issue list --json isBlocked`, got `Unknown JSON field`, and correctly concluded that field did not exist. The conclusion recorded was broader: *"`gh issue list --json` cannot see dependency data — dependency reads must use `gh api`."*

That was false when written. `gh` v2.94.0 shipped `--json blockedBy,blocking,parent,subIssues` on **2026-06-10**, nearly two months earlier, along with `gh issue edit --add-blocked-by`. The one field tested was the one field that does not exist.

The false claim was then copied verbatim into `/prd-to-issues` §7, `execute/SKILL.md`, `help/SKILL.md`, `setup-ralph-loop/SKILL.md`, and `SYSTEM-OVERVIEW.md` — which `scripts/skill-references.manifest` bundles into four more `references/` copies. Nine sites, one unverified generalization.

Alongside it, #168 wrote a second claim into two of those files: that the selection sites *"agree by construction rather than by coincidence."* They did not. The selection idiom lives in five hand-maintained files with no test relating them. `sync-skill-references.sh` pins `SYSTEM-OVERVIEW.md` to its four bundled copies and says nothing about the five sources.

The false claim survived from 2026-08-04 to 2026-08-11 and was found only because a `/research` pass happened to read `gh --help` — one command that nothing in the pipeline required.

## Symptoms

- A skill states a capability limit about an external tool (*"X cannot do Y"*) with no version qualifier and no citation.
- The same command, comment, or `jq` idiom appears in three or more files, none of which reference the others as canonical.
- Prose asserts a consistency property — "agree by construction," "cannot drift," "by definition" — that no test, script, or generator enforces.
- A negative claim was generalized from a single probe (*one field errored* → *the whole family is unavailable*).
- The pinning that does exist covers the easy axis (one canonical file → its copies) and not the hard one (several peer files that must agree).
- A cross-reference **enumerates** the thing it refers to — "the same A → B → C → D shape X uses" — and the enumeration is missing a step that X actually has. This reads as referring and behaves as restating; see the 2026-08-17 instance below.

## Root Cause

Two decays with one shared cause.

**Verification has no provenance and no expiry.** The pipeline records what verification *concluded* and not what it *ran against*. Once written, `"gh issue list --json cannot see dependency data"` is indistinguishable from a fact. There is no version it was true at, no command that would re-check it, and nothing that ages it. `/research` has exactly this machinery — `installed_versions_snapshot` frontmatter, "cite the docs URL at the verified version," a Sources section graded by confidence — but that discipline governs *research artifacts about downstream projects*, not claims Skill Kit writes about its own toolchain.

**Asserting a property is cheaper than enforcing it, and reads the same.** "Agree by construction" is one clause. A test that extracts the idiom from five files and compares them is real work. The prose form provides the reassurance of the mechanism at none of the cost, and it actively suppresses the check — a reader who sees "by construction" has been told not to verify.

The two compound. A claim believed to be verified, asserted to be consistent, and copied nine times is maximally protected from the thing that would correct it.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from **external tool state** back to **the claims the pipeline makes about it**. Skill Kit has a strong loop for downstream-project facts (`/research` Phase 0 re-checks installed versions every run) and none for its own toolchain — `gh` is a dependency nothing declares, snapshots, or re-verifies. The delay is what hides it: a false capability claim causes no error. It causes a clunkier implementation, which reads as necessary because the claim explains why. The cost surfaces only when someone reads the tool's own docs for an unrelated reason.

## Rule Scope

- **Applies when** both hold:
  - a rule is derived from probing an external tool's behavior — a CLI flag, an API field, a version limit, an error message — rather than from reading its documented contract at a pinned version; **and**
  - the derived rule is written into more than one file, or is asserted to be consistent across files.
- **Inverts or does not apply when:**
  - **The claim is about the repo's own code**, where a test can assert it directly and the codebase is the source of truth. Write the test; no snapshot needed.
  - **A single file owns the rule and others reference it by name.** Cross-skill references (`see /prd-to-issues §7`) are the correct shape and need no pinning — the point of failure is *restating*, not *referring*.

    **Amended 2026-08-17 — referring and restating are not a clean binary, and this clause as originally written would have cleared the defect it was meant to catch.** A reference that *enumerates* its target ("the same `mktemp` → read body → edit → `gh pr edit --body-file` shape Phase 4's stamp uses") is a restatement wearing a reference's clothes: the reader reconstructs the procedure from the enumeration, not from the target, so any step the list omits is omitted in practice no matter what an adjacent sentence claims. The test is not "does this name its source" but **"could a reader build the thing from this sentence alone, and if they did, would they get it right?"** Reference by *name* or by *section* is safe because it cannot be built from — it forces the reader to the source. Reference by *partial enumeration* is the dangerous middle, and it is the shape most likely to be written, because enumerating feels more helpful than pointing.
  - **The tool genuinely has no versioned contract** (an undocumented search qualifier, an unreleased endpoint). Then the honest record is the probe plus its date, marked as such — which is what this PR did for GitHub's broken `parent-issue:` qualifier, and correctly so.
  - **The copies are generated.** `scripts/sync-skill-references.sh` already makes canonical→bundled copies safe; this lesson is about peer files that must agree, which no generator covers.
- **Sibling docs:**
  - `staleness-gate-intermediate-writers-2026-08-06.md` — closest sibling, and the inverted axis: that one is a contract between **two** skills over a mutable interval, this one is a claim copied to **N** peers with no interval at all. Its prescription (enumerate the writers mechanically rather than from memory) is the same move applied to a different asymmetry.
  - `secondhand-source-proposal-specificity-2026-08-11.md` — the upstream cause in this instance. #205 was drafted from `/prd-to-issues` §7 rather than from `gh --help`, because §7 read as verified.
  - `advisory-to-executed-rule-promotion-2026-08-07.md` — the family's shared shape: *a recorded limitation that gates nothing is a footnote.* This entry adds the mirror case — **a recorded *verification* that expires nothing is also a footnote.**
  - `sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — the empirical case for this entry's *timing* clause. It records three consecutive sweeps on one branch that each introduced a fresh instance of the class they were correcting, including the sweep that finally added the pinning test. That is why "the assertion and the test should be added in the same change" is load-bearing rather than tidy: the change that defers the test is the change most likely to need it.

## Solution

**What this PR fixed (the instance).** Removed the false claim from all five sources and the four bundled copies; swapped the hand-rolled REST mechanism for `gh issue edit --add-blocked-by`; stated a `gh >= 2.94.0` floor in `README.md` — the repo's first declared tool-version floor, which is the closest thing to a snapshot the claim ever had.

**What this PR then fixed (the mechanism).** `scripts/test-selection-idiom-consistency.sh` now constructs the agreement the prose asserts, wired into lefthook pre-push and CI. Four checks, each extracting the real text from the real files:

1. The three FRONTIER copies (`/setup-ralph-loop` ×2, `SYSTEM-OVERVIEW.md`) normalize to one value.
2. No file compares `.state == "open"` against a `blockedBy` read — the uppercase/lowercase split that matches nothing silently.
3. `isBlocked` does not resurface as a capability claim in any skill.
4. Every adjacent `` `/skill` Step N `` reference resolves to a heading that exists.

**What it deliberately does not assert:** that all nine occurrences are byte-identical. They are not, and should not be — §9 tests for an empty set, `/execute` projects `{number, title}`, `/help` projects `.number`. Pinning them to one string would force a false uniformity and the suite would be deleted the first time someone legitimately needed a different projection. Only the parts that *must* agree are pinned.

The suite was mutation-tested before commit: drifting one FRONTIER copy's `--limit`, lowercasing one state predicate, appending an `isBlocked` claim, and adding a dangling `Step 9` reference each produced exactly one failure, and the tree was restored clean. A contract suite that has only ever been observed passing is itself an unverified claim — which is the error this entry is about.

Check 4 earned its place immediately: the `/triage-issue` fix made earlier in this same PR referenced `/qa` **Step 4b**, a number created by renumbering in that same PR. It is now referenced by name instead.

## Prevention

**Code-level.** The repo already has the pattern, in `scripts/test-review-currency-marker.sh`: it **extracts** the real regex from `closeout/SKILL.md` and the real template from `pre-merge/SKILL.md` and round-trips one through the other, rather than restating either. A hand-copied assertion in a test drifts alongside the thing it tests; a test that reads both halves fails precisely when they stop agreeing. The same shape applies to any idiom asserted to be shared — extract each occurrence, normalize whitespace, assert one distinct value. **Adopt this whenever prose claims cross-file agreement.** The assertion and the test should be added in the same change; an "agree by construction" clause with no accompanying test is the detectable form of this defect.

**Which mechanism — and specifically, why not a Claude Code hook.** This is the first question a reader asks here, because Skill Kit ships hook-based enforcement (`/init-pipeline`'s TDD classification gate) and reaching for the same tool looks natural. It is the wrong tool for this class, and the dividing line is worth stating once:

| What is being checked | Right mechanism |
|---|---|
| Session state that does not survive to commit time — *"was this work classified **before** code was written?"* | **Hook.** `.claude/.tdd-active` exists only during the session; nothing in the tree can answer this afterward. |
| Any property verifiable from the tree — cross-file agreement, a reference resolving, a marker's format | **Test**, wired into CI. |

Cross-file consistency is entirely tree-verifiable, so a hook would *narrow* who the check protects rather than widen it. Three concrete reasons:

1. **Coverage holes, and they are not hypothetical.** A `PostToolUse` hook fires on `Edit`/`Write`. The session that produced this entry edited `SKILL.md` files four ways — `Write`, `Edit`, `python3` heredocs through `Bash` (three separate files), and `gh pr edit`. A hook would have missed every `python3` edit, and those were the multi-site mechanical rewrites *most* likely to introduce the drift being guarded against.
2. **It only protects one editor.** A hook never fires for a human in an IDE, a contributor who does not use Claude Code, or CI. The tree is read by all three.
3. **Skill Kit deliberately has no `.claude/` directory.** Its enforcement is lefthook (pre-commit cheap, pre-push full) with CI as the gate — `lefthook.yml` states outright that local hooks are "an early-warning layer, not a gate." The hooks `/init-pipeline` installs are for *downstream projects*, not for this repo.

If edit-time latency ever becomes the actual pain, the right place is **lefthook pre-commit**, not a Claude hook — it catches every edit path rather than one agent's.

### Fifth instance, 2026-08-17 (PR #254, issue #253) — and what it says about this entry

PR #254 added two guards to `/pre-merge`'s stamp write, then wrote, one bullet below them: *"Phase 5's ledger write is the same read-modify-write against the same API and reuses this shape, guards included."* The reference site in Phase 5 read: *"Write the block with the same `mktemp` → read body → edit the block → `gh pr edit --body-file` shape Phase 4's stamp uses."* Four steps, none of them the guards. An agent building the ledger write from that sentence — which is the sentence it is given — writes unguarded, in the mode that rewrites the PR body most often. The commit message asserted the inheritance too.

Three things make this instance worth more than a tally mark:

1. **The entry was in hand and did not fire.** The same PR body cites this file, by path, for an unrelated decision. Reading a diagnostic entry at citation time does not make its rule fire at authoring time. That is a property of the entry, not of the author — a lesson that only fires when you are already thinking about it is not a mechanism, which is the thing this entry exists to say about *other* claims.
2. **Its Rule Scope cleared the defect.** The "reference by name is the correct shape" carve-out reads as covering any sentence that names its source, and this one did. The amendment above narrows it.
3. **A reviewer caught it, the author did not** — the same asymmetry `self-review-blind-to-composition-2026-08-13.md` records. The author reads the assertion as true because they know it is true; the reviewer reads only what the sentence would produce.

The instance fix was to name the guards in the enumeration. The mechanism fix is unbuilt and is the same one named below: extract both fences and assert the guard lines appear in each. Recorded, not built — which is exactly what this entry's own Key Decision did in August, and the reason there is now a fifth instance to write up.

**Process-level.** Two changes, neither yet made:

1. **A capability claim about an external tool needs a version and a re-check command**, the same way `/research` requires a docs URL at the verified version. `"gh issue list --json cannot see dependency data"` should never have been writable without a `gh` version beside it. A claim with a version attached is falsifiable by inspection; without one it is folklore on its first read.
2. **Negative claims need a wider probe than positive ones.** *"This field works"* is proven by one call. *"This family is unavailable"* is not disproven by one call — and the failed probe here (`isBlocked`) was of a field that never existed, which is the weakest possible evidence for the conclusion drawn. Generalizing from a single negative probe is the specific error; the fix is to enumerate the family (`gh issue list --json` with no argument prints every accepted field) before concluding anything about it.

## Planning / Calibration Notes

- **What widened the work:** the sweep. The mechanism swap was small and mostly subtractive (net −9 lines across four skills). Finding every site of the false claim — including `SYSTEM-OVERVIEW.md`, which was outside the proposal's scope and bundled into four more copies — was most of the work, and it was entirely `rg` sweeps rather than reasoning.
- **What tightened the work:** one throwaway edge. Wiring `gh issue edit --add-blocked-by 168` on a live issue and removing it resolved in seconds what prose could not settle at all: the `--json blockedBy` node shape, `state` being the uppercase GraphQL enum where REST returns lowercase, and `totalCount` counting all states. Two of those would have shipped as guesses.
- **Future planning adjustment:** when a proposal's substance is *how to call a tool*, budget the tool's own `--help` and release notes as a **filing precondition**, not as implementation-time discovery. Cost here: two commands. It changed the verdict from "proceed narrowly, propagate the mechanism" to "proceed broadly, delete the mechanism."

## Actuals Worth Reusing

- **Comparable future work:** any change that writes a rule about an external CLI or API into more than one skill — and any change whose diff is mostly `rg` sweeps for a repeated string.
- **Reusable baseline:** a false claim in this repo propagates to roughly 5 hand-maintained sites plus whatever `skill-references.manifest` bundles. Budget the sweep, not the edit. The ratio held twice now — this entry and `secondhand-source-proposal-specificity-2026-08-11.md` both had trivial diffs and non-trivial verification.

## Defect Classification

**Origin phase:** Specification error — the claim was written into the spec (the skills) from an under-powered probe, and every downstream copy faithfully implemented a false premise.
**Fix type:** Correction for the claims (the false statements are gone and the floor is declared); **Workaround for the consistency property** — "agree by construction" now describes a true rule, but still nothing enforces the copies agreeing. The real fix is the extract-and-compare test named under Prevention.

## Key Decision

**Decision:** Fix the claims in this PR; record the missing enforcement mechanism as a finding rather than building it here.

**Rationale:** the claims were actively wrong and cheap to correct. The harness is a different change with a different blast radius, and #205's Mediator verdict scoped this PR to the claims. Building it mid-PR would have widened an already cross-cutting diff.

**Alternatives considered:** build the extract-and-compare test in this PR — rejected as scope creep on a diff already touching 13 files across five skills. Consolidate the five copies into one canonical file that the others reference — attractive, and the right long-term shape, but it changes how four skills read at runtime and deserves its own proposal.

**Revisable:** Yes. If the idiom drifts again before the test exists, that is the evidence to stop deferring and build it.

## Related

- PR #206 — this implementation
- PR #254 / issue #253 — the fifth instance (2026-08-17): a guard asserted as inherited "by reference" whose reference site enumerated four steps and named neither guard. Source of the Rule Scope amendment above
- Issue #205 — the proposal; its first draft recommended propagating the mechanism this PR deletes, corrected in a comment on the issue
- Issue #168 / PR #170 — where both claims were introduced
- [cli/cli v2.94.0](https://github.com/cli/cli/releases/tag/v2.94.0) — the release that made the claim false, two months before it was written
- [cli/cli#13899](https://github.com/cli/cli/pull/13899) — open, unmerged; the `gh issue create` deferred-failure mode that shapes the create-bare-then-wire rule
- `staleness-gate-intermediate-writers-2026-08-06.md`, `secondhand-source-proposal-specificity-2026-08-11.md`, `advisory-to-executed-rule-promotion-2026-08-07.md` — see Rule Scope
- `self-review-blind-to-composition-2026-08-13.md` — same family, and the reason a *second reader* is the mechanism where a snapshot is not: a claim maintained by hand across peers fails silently, and the author is the one reader who cannot see it

## Shelf Life

The *instance* closed in the PR that opened it — `scripts/test-selection-idiom-consistency.sh` now constructs what the prose asserts. Retire this entry's instance half when that suite is deleted or the "agree by construction" claim is removed; the suite's own check 5 fails if the claim disappears without it, so the two retire together by design.

The *general* rule outlives it and is now the fourth entry in a chain saying one thing four ways: **a limitation, a source gap, a stamped interval, or a verification that constrains nothing downstream is a footnote, not a mechanism.** Four instances is past the point where the siblings should be consolidated into one entry; that consolidation is the real successor to all four, and this entry should be folded into it rather than deleted.

**Updated 2026-08-17.** A fifth instance landed (above), and it was deliberately folded in here rather than filed as a fifth sibling file — adding one would have been the exact move this section warns against. But folding in is a holding action, not the fix. The consolidation is now overdue by one instance, and the fifth instance is itself evidence for why: the entry did not fire at authoring time for an author who had it open. A consolidated entry is only worth writing if it is shaped as a **trigger** — a named shape you can check a sentence against ("could a reader build this from the sentence alone?") — rather than as a fourth retelling of the diagnosis. If the consolidation gets written as more prose, expect a sixth instance.
