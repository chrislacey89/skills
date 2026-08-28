---
date: 2026-08-27
category: devops
problem_type: a known local/gate instrument divergence was disclosed instead of verified — the warning fired, was quoted into the PR body, and the branch still went red at the gate
components: [scripts, lefthook, validate-skills, pre-merge, execute]
technologies: [shellcheck, bash, git, ci]
severity: medium
volatility: stable
---

# A disclosed risk with a runnable check is a to-do, not a disclosure

## Problem

PR #299 shipped three commits carrying the note "local shellcheck is 0.11.0, CI gates on 0.9.0 — read the PR check, not my run" — written into the PR body twice — and then failed CI's shellcheck job on SC2015, which 0.11.0 special-cases (`|| true` in `A && B || C`) and 0.9.0 reports. The pinned binary was downloadable the whole time; nobody ran it, and nobody read the PR check either.

## Context

The repo already had a mechanism for this exact divergence: `scripts/check-shellcheck-version.sh`, built after PR #271 (2026-08-23), where local 0.11.0 said clean and CI's 0.9.0 said SC2317 through four review rounds. On #299 the warner **fired correctly** and the failure recurred anyway.

## Root Cause

Two layers.

1. **The warner prescribes reading, not running.** Its message ended "Read the PR check, not this run" — a post-push action, easy to defer and easy to forget (prospective memory fails silently). The actionable *pre-push* verification — download the ~1.4MB pinned binary, cached forever, and lint with it — existed but nothing named it, so the divergence was treated as a fact to disclose rather than a check to run.
2. **Disclosure was mistaken for diligence.** Writing the risk into the PR's Review Notes felt like handling it. A named risk that nothing verifies is a prediction; the proof is that running the real 0.9.0 binary during the fix immediately caught a *residual* instance in the first attempt at the fix itself — predicted lint behavior was wrong twice in one hour, and the instrument was right both times.

## Learning Level

- **Level:** Pattern — second occurrence of "local green read as gate green" (PR #271, PR #299), and the recurrence happened *with the first occurrence's mechanism active*.
- **Missing feedback:** the warner announced the divergence but created no path from the announcement to a verification, so the loop stayed open between push and CI.

## Rule Scope

- **Applies when:** a merge gate runs a pinned tool version, the local version differs, and the pinned artifact is obtainable locally (released binary, container image, lockfile-installable package). Then the divergence warning must *route to running the pinned instrument*, not to reading the gate's output later.
- **Inverts or does not apply when:** the pinned instrument genuinely cannot run locally (license, platform, gate-only hardware). Then "read the PR check" is the only verification there is — the disclosure *is* the mechanism, and the right upgrade is making the gate's result block, not shaming the disclosure.
- **Sibling docs:** `../testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md` (instrument fails while reporting normally — this entry is the case where the instrument is *known* to differ and the knowledge changes nothing); `local-gates-absent-in-a-fresh-worktree-2026-08-24.md` (gates absent rather than wrong-versioned — both produce a local green that is not the merge gate's green).

## Solution

`scripts/shellcheck-pinned.sh`: resolves the pin from `.shellcheck-version` (derived, never restated — the parity suite pins that), uses the PATH binary when it already matches, otherwise downloads the pinned release once into `~/.cache/skill-kit/` and lints with that. Offline or unknown platform, it falls back to the local binary and says loudly that the run is not the gate's instrument. `lefthook.yml` pre-push `shellcheck-all` now runs it, and the warner's message routes to it instead of to "read the PR check".

## Prevention

**Code-level:** the script + pre-push wiring above — the pre-push lint now *is* the merge gate's instrument on any machine that has fetched it once.

**Process-level:** in `/execute`'s Review Notes and any "known-weak spots" list, a named risk must carry either its verification (command + exit status) or one line on why it cannot be run locally. "Read the PR check" appearing in author-written notes is the tell — it defers to a gate the author has already demonstrated they are not reading.

## Related

- PR #299, issue #298 (the branch this recurred on); PR #271 (the first occurrence, recorded in the warner's header)
- The same branch was also the first recurrence of `../testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md`'s census discipline (three rounds of enumeration-by-wording); its mechanism upgrade — a census by behavior with per-file floors and run-the-block assertions — shipped in `scripts/test-documented-git-commands.sh` on the same PR, so that pattern is not re-recorded here.

## Shelf Life

Obsolete if the repo ever pins local tooling by construction (devcontainer/nix providing the exact shellcheck), which would make local/gate divergence unrepresentable. Until then, stable.
