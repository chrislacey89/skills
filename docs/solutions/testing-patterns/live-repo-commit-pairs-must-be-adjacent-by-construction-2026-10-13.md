---
date: 2026-10-13
category: testing-patterns
problem_type: a suite that resolves commits from the live repository assumes the local checkout's shape (HEAD and HEAD~1 adjacent), which a CI pull-request checkout does not provide
components: [scripts/test-git-guardrails.sh, .github/workflows/validate-skills.yml, scripts/test-documented-git-commands.sh]
technologies: [git, github-actions, bash]
severity: medium
volatility: stable
---

# A suite that reads commits from the live repo must pick an adjacent pair by construction

## Problem

A contract suite that needs two real commits to disagree about took `HEAD` and `HEAD~1`, asserted a one-commit delta between them, and passed on every developer machine while failing on every multi-commit pull request in CI. The failure was invisible for weeks because an earlier step in the same job aborted first.

## Context

`scripts/test-git-guardrails.sh` drives the stale-stamp refusal through a stubbed `gh` and needs a reviewed SHA and a head SHA that both exist in the repository, so the guard's delta measurement runs its measurable branch. It resolved them as `HEAD~1` and `HEAD` and asserted the refusal text `delta: 1 commit(s) past the stamp`. On a developer's branch those two commits are adjacent. In GitHub Actions a pull request checks out `refs/pull/N/merge`: a merge commit whose first parent is the base branch and whose second parent is the PR head. There `HEAD~1` is the base branch, and `HEAD~1..HEAD` is every commit on the PR plus the merge.

Nobody saw it because the same CI job had been stopping one step earlier since #349: the default depth-1 checkout made the suite's own "two distinct 40-character commits" precondition fail with `FATAL`, and a fatal exit at that step hid every later step. Repairing the checkout (`fetch-depth: 0`) let the suite run far enough to expose the second assumption. PR #403 carried both repairs.

## Symptoms

- `FAIL the refusal lost a SHA or its delta` with a measured delta of 3 or more commits, only in CI, only on PRs with more than one commit.
- Before that, `FATAL: could not resolve two distinct 40-character commits … (shallow clone?)` at the same step on every prod run, masking everything after it.

## Root Cause

The oracle (`1 commit(s)`) encoded a fact about the checkout shape rather than about the pair it chose. `HEAD` and `HEAD~1` are adjacent only when `HEAD` is not a merge commit, and a PR checkout always is one. The earlier shallow-clone fatal was a guard that reported coverage the job did not have: a green-looking precondition that stopped the job before the assertion it protected ever ran, so the assertion's own flaw never surfaced (`dead-guards-report-coverage-they-do-not-have-2026-08-27.md`).

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** none. A suite that resolves live commits gets no signal when the checkout shape differs from the author's, and a fatal at an earlier step removes the one place the signal would have appeared.

## Rule Scope

- **Applies when:** a test resolves commits from the repository it lives in (rather than from a fixture it built) and asserts anything about the distance between them, or about which commit is "the previous one".
- **Inverts or does not apply when:** the suite builds its own scratch repository, where it controls the shape; or when the assertion is on the *existence* of two distinct commits and nothing about their adjacency.
- **Sibling docs:** `scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md` (the same pattern one layer down: a suite assumes the local git state where it runs), `dead-guards-report-coverage-they-do-not-have-2026-08-27.md` (why the first flaw hid the second).

## Solution

Choose the pair so adjacency holds in every checkout shape: the newest non-merge commit on the first-parent chain, and its single parent.

**Before:**
```bash
stamp_sha="$(git -C "$repo_root" rev-parse HEAD~1)"
head_oid="$(git -C "$repo_root" rev-parse HEAD)"
```

**After:**
```bash
head_oid="$(git -C "$repo_root" rev-list --first-parent --no-merges -1 HEAD)"
stamp_sha="$(git -C "$repo_root" rev-parse "${head_oid}~1")"
```

A non-merge commit has exactly one parent, so `stamp_sha..head_oid` is exactly that commit, in a plain checkout, a PR merge checkout, or a branch with merges in its history.

## Prevention

**Code-level:** the mechanism is the CI environment itself, now that `script-tests` checks out full history (`.github/workflows/validate-skills.yml`): every pull request runs every suite against a merge-commit `HEAD`, so the next suite that assumes `HEAD~1` is adjacent fails on its first multi-commit PR instead of passing for weeks. The repaired suite's comment names the shape (`scripts/test-git-guardrails.sh`, the "Two commits that exist in THIS repository" block).

**Process-level:** when a CI job has been red at one step for a while, treat the steps after it as unrun, not as passing. Repair the blocking step first and expect the next failure to be new.

## Defect Classification

**Origin phase:** Design error (the oracle was chosen from the author's checkout, not from the contract)
**Fix type:** Correction

## Related

- PR #403, commits `4aee9ee` (checkout depth) and `7e38d1b` (adjacent pair)
- #349 (the first red prod run), #402 (the feature whose verification exposed it)
- Defect clustering: this is the second recording of the pattern `scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md` names in the same category. That entry's mechanism is a per-suite `unset`; this one's is the CI checkout shape, which catches the adjacency form for every suite at once.

## Shelf Life

Until the `script-tests` job stops checking out pull requests as merge commits or returns to a shallow checkout; either change re-opens the gap.
