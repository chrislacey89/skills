---
date: 2026-10-13
category: patterns
problem_type: a skill's fenced command blocks share variables as if one shell ran them all, but the agent harness opens a fresh shell per tool call and the contract test concatenates the blocks into one process, so neither the author nor the suite sees the loss
components: [excavate/SKILL.md, scripts/test-documented-git-commands.sh]
technologies: [bash, claude-code]
severity: high
volatility: stable
---

# A skill's command blocks run one shell per tool call; shared state must be written to a file

## Problem

`/excavate` set its working variables once in a Step 0 block, declared them "set once and reused", and had every later block read them. In a downstream agent session each block runs in a fresh shell, so `$WORK` was empty, an `EXIT` trap deleted the work directory when the first call ended, and sub-agents dispatched with only a path lost `SINCE`, `BOTS`, and `NONDOMAIN` entirely. `git log --since=""` returns zero commits and `grep -Ev ""` prints nothing, so a miner would have reported "no reverts" and an empty map, which the skill reads as valid answers.

## Context

The skill's blocks are executable prose: a downstream agent copies each fenced block out and runs it. The repo's own contract suite extracts every block and runs it against a planted fixture, which is the right check for whether a block is a valid invocation. But the harness evaluates the setup block and every later block in one process so they can share `$WORK`, and that one decision made the suite blind to exactly the property the skill's prose claimed. Two review rounds found it: the first caught `$WORK` and the trap, the fix closed only `$WORK`, and the second round caught the rest at the sub-agent boundary.

## Symptoms

- A later block's output is empty or refers to a path under an unset variable; the skill's prose treats empty output as a legitimate answer.
- The repository suite is green, because it never runs two blocks in two processes.

## Root Cause

"Set once in Step 0 and reused" was a claim with nothing constructing it: no file carried the values between shells, and the only executable reader of the blocks (the suite) was shaped to make the claim true by accident. This is the shape `by-construction-claims-need-a-mechanism-2026-08-11.md` names, in a skill's command blocks rather than a contract test's prose.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** missing feedback. The author's mental model (one terminal), the harness (one process), and the field (one shell per call) disagree, and only the field reports the difference, after install.

## Rule Scope

- **Applies when:** a skill documents more than one fenced command block and a later block reads a variable, function, trap, or working directory an earlier block set.
- **Inverts or does not apply when:** every block is self-contained, or the skill explicitly instructs the agent to run a named setup block at the top of each shell and that block is idempotent and cheap. Even then, a user override made after the setup block is lost on re-run unless persisted.
- **Sibling docs:** `by-construction-claims-need-a-mechanism-2026-08-11.md`; `mechanism-generality-lags-the-pattern-2026-08-23.md` (the mechanism below covers one skill).

## Solution

Persist resolved state to a file under a deterministic path, and make every later shell source it.

**Before:** a Step 0 block with `WORK=$(mktemp -d)`, `trap 'rm -rf "$WORK"' EXIT`, and prose saying the variables are set once.

**After:** `WORK` derived from the repository path (`${TMPDIR:-/tmp}/excavate-<cksum of toplevel>`), no trap, a block that writes `declare -p` output and the `GIT_CONFIG_*` exports to `$WORK/vars.sh` after overrides are applied, prose saying every later shell and both sub-agent briefs source that file, and cleanup as an explicit last step. See `excavate/SKILL.md` Step 0 and the Process intro.

## Prevention

**Code-level:** `scripts/test-documented-git-commands.sh` now runs one pass in a second `bash` process that only sources `vars.sh` and rebuilds the shared log, asserting the same line count as the main pass; mutant M7 re-runs the setup block instead of sourcing and shows that assertion failing. This is the mechanism for this skill. Generalizing it to every skill is blocked by the harness running only `/excavate`'s blocks; the next skill with shared blocks needs the same pass added when its blocks are registered.

**Process-level:** when a skill's prose says variables are "reused" across blocks, the review question is "by what file?"; and a contract test that concatenates blocks into one process should say so in its header as a known blind spot.

## Related

- PR #403, commits `dea082a` (deterministic path, no trap) and `ea37cb7` (`vars.sh`)
- #402
- Defect clustering: this is the second recording of the pattern `by-construction-claims-need-a-mechanism-2026-08-11.md` names, across categories (that entry is `architecture-decisions`). The mechanism is the second-process pass above.

## Shelf Life

Until the agent harness keeps shell state across tool calls, or until the contract suite runs every block of every skill in its own process, at which point the pattern is caught at authorship.
