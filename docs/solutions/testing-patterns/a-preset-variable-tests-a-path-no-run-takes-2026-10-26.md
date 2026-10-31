---
date: 2026-10-26
category: testing-patterns
problem_type: a test feeds a skill block its input through a channel a real run never has (a preset environment variable), or through a fixture where two code paths give the same answer, so it passes on a path no run takes
components: [pre-merge/SKILL.md, init-pipeline/scripts/sidecar.sh, scripts/test-guest-footprint.sh, scripts/test-sidecar-resolution.sh, scripts/test-block-default-reads.sh, scripts/test-documented-git-commands.sh]
technologies: [bash, claude-code]
severity: high
volatility: stable
---

# A preset variable tests a path no run takes

## Problem

Two tests on PR #604 passed for a reason unrelated to the behavior they claimed to check.

- `scripts/test-guest-footprint.sh` ran `/pre-merge` Phase 2's sidecar block with `BASE_BRANCH=slice-1-branch` in the environment and asserted `gh pr create --base slice-1-branch`. The block reads `[ -n "${BASE_BRANCH:-}" ] || BASE_BRANCH=$(bash "$SC" base-ref --name)`. An agent runs that block in a fresh shell, where the stacked-PR override set in Phase 1 never arrives, so the override the test proves is kept is one that cannot reach the block.
- `scripts/test-sidecar-resolution.sh` checked that `base-ref` follows `origin/HEAD` in a clone whose `origin/HEAD` was `main`, also the first name in the fallback list. A version that skipped `origin/HEAD` entirely still passed all 424 checks.

## Context

The slice added `sidecar.sh base-ref`, so skills read a declared base branch instead of each guessing from `origin/HEAD`. The same review cycle fixed `/pre-merge` Phase 4's sidecar stamp, which passed `--base-ref "${BASE_REF:-}"` from a block that never set `BASE_REF`, so every sidecar stamp recorded an empty base. The fix for that finding and the fix for the stacked-PR finding landed one commit apart, and the second reintroduced the first's shape in a form the test could not see.

## Symptoms

- A block reads `${VAR:-}` for a variable only another block sets, and its test passes because the harness exports `VAR` before running it.
- A mutation that removes the code path under test leaves the suite green, because the fixture's expected value is also what the fallback produces.
- A test extracts one line from a skill's block and runs it with the variable the rest of the block computes already set, so a block broken before that line still passes.

## Root Cause

The test supplied the precondition the code was supposed to establish. In the first case the channel (an environment variable) does not exist in a real run: `docs/solutions/patterns/skill-command-blocks-run-one-shell-per-call-2026-10-13.md` records that each block runs in its own shell. In the second, the fixture made the primary path and the fallback indistinguishable. Both are the same failure seen from two sides: the test's input does not separate the behavior under test from the behavior it replaces.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** missing feedback. The suite runs blocks in a process where the harness can set anything, and only a downstream run in a fresh shell reports the difference, after install. Review caught each instance; nothing checked.

## Rule Scope

- **Applies when:** a test runs a skill's fenced block, or one line extracted from it, and sets, in its environment, a variable the block reads or computes; or a test asserts a lookup's result in a fixture where the lookup's fallback would return the same value.
- **Inverts or does not apply when:** the variable is one the harness or user genuinely provides (`HOME`, `CLAUDE_PROJECT_DIR`, a documented override like `CLAUDE_LIBRARY_DIR`), or the block substitutes a placeholder (`W="W-<n>"`) that the test fills by the same substitution an agent would make.
- **Sibling docs:** `patterns/skill-command-blocks-run-one-shell-per-call-2026-10-13.md` (the runtime fact); `testing-patterns/a-planted-term-cannot-discriminate-meaning-2026-09-04.md` (a fixture that cannot discriminate, on prose); `architecture-decisions/compat-default-is-every-failures-answer-2026-10-24.md` (the same PR family; it recorded the stamp block's empty `BASE_REF` as a recurrence).

## Solution

- **Fixture that discriminates.** The `base-ref` fixture now runs `git remote set-head origin develop`, so following `origin/HEAD` gives `develop` and the first fallback candidate gives `main` (commit `44dd3e5`). A breaker reversed the lookup order and the suite failed four checks.
- **Inputs through the agent's channel.** A value a block needs from an earlier step goes in a placeholder line beside `W=` and `TITLE=`, which the test fills by substitution, or the block computes it with the verb in its own shell (the stamp block, commit `395eb83`).

## Prevention

**Code-level:** run the whole block a skill documents, with placeholders substituted, rather than a line extracted from it under a preset. `scripts/test-block-default-reads.sh` scans every fenced shell block in `*/SKILL.md` and `docs/*.md` and fails on a `${VAR:-...}` read of a variable the block has not assigned earlier, except harness variables and a named `KNOWN` list whose entries must still match. It does not catch a plain `$VAR` read across blocks, a fixture whose paths coincide, or a harness that runs a fragment of a block with the rest of the block's output preset. `scripts/test-documented-git-commands.sh` covers the first and last of those for `$BASE_REF` only.

**Process-level:** when a test sets a variable the block under test reads, ask whether an agent running that block could have it set. When a test asserts a fallback-capable lookup, check that the fixture makes the primary path and the fallback disagree.

## Defect clustering

This is the fourth recording of the one-shell-per-call pattern: `/excavate` (#403), PR #529 finding 6 (noted in `compat-default-is-every-failures-answer-2026-10-24.md`), and PR #604's S5 and its sibling concern 1. Prose was the deliverable each time and the pattern recurred, so this entry ships `scripts/test-block-default-reads.sh` as the mechanism.

The fifth recording came two days later, on the next slice of the same PRD (#598, PR #615). The base-ref sweep rewrote `scripts/test-documented-git-commands.sh` so that `run_in_fixture` sets `BASE_REF` and `BASE_BRANCH` from one run of the verb, then runs each skill's range lines. No skill's own `SC=` and `BASE_REF=` lines run. A review breaker pointed `/walk-commits`' `SC` at a path that does not exist after install, and moved `/visual-recap`'s `BASE_REF=` below the lines that read it. Both left every suite green. `test-block-default-reads.sh` did not fire, because no block reads `${BASE_REF:-}`: the harness ran a fragment and supplied what the omitted lines compute. The mechanism for this shape shipped under chrislacey89/skills#616: that suite now runs each block whole with its placeholder substituted and nothing preset, the way its `/closeout` section already did. It found the plain `$BASE_REF` read across blocks live at `/compound`, `/help`, and `/execute`'s removed-guard sweep.

## Related

- PR #604, slice #597, PRD #596
- PR #615, slice #598: the fifth recording; mechanism filed as #616
- `/fix-findings` breaker verdicts on `6043a8e` and `395eb83`: the `|| true` mutants survived because no test runs the block with the variable unset

## Shelf Life

Until the agent harness keeps shell state across tool calls, or the contract suites run each skill block in its own process with only placeholder substitution.
