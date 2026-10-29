---
date: 2026-10-29
category: patterns
problem_type: a SHA recorded at one moment is later used as the left end of a range, and "still an ancestor of HEAD" is taken to mean "the commits after it are this branch's", but a rebase onto an advanced base or a merge from the base keeps it an ancestor while the range fills with other people's commits
components: [init-pipeline/scripts/sidecar.sh, pre-merge/SKILL.md, fix-findings/SKILL.md, execute/SKILL.md]
technologies: [bash, git]
severity: medium
volatility: stable
---

# A recorded start that is still an ancestor of HEAD can still bound the wrong commits

## Problem

`sidecar.sh range <W-n>` (#599) returns `<start_sha>..HEAD` whenever the slice's recorded start is an ancestor of `HEAD`. It falls back to the base range only when the start is no longer an ancestor. That test is necessary but not sufficient. On an ordinary rebase onto an advanced base, the old start is still an ancestor, and the range then covers commits that other PRs landed on the base.

## Context

`/execute` records `start_sha` when a slice starts, so that `/pre-merge`'s first review and `/fix-findings`' round count cover one slice on a branch that carries several. The fallback was written for the case the PRD named, a fold that rewrites the start. The reverse case was not named: history moves underneath the start, and the start itself survives.

## Symptoms

- After `git rebase origin/<base>`, `range W-n` prints the old base tip with no notice. The review diff (`<left>...HEAD`) lists another PR's file next to the slice's own, while `<base>...HEAD` lists only the slice's.
- `ROUNDS` counts `Fix-Findings-Run:` lines from squash-merged PRs on the base. That is #586's over-count again, coming from the base this time instead of from earlier slices.
- Restarting a slice on a fresh branch from a newer base gives the same result. `/execute` keeps a recorded start, and the old one is still an ancestor.

## Root Cause

Ancestry answers "is this commit in HEAD's history?". The range needs a different answer: "is every commit after it this branch's own?". These agree only while nothing from the base has entered the branch since the start was recorded. Recording a SHA freezes a moment, and the ancestor test checks the SHA, not the moment. The pack already had the right rule in another module: `/pre-merge` Phase 1 step 4 refuses the post-stamp delta when a merge follows the stamp, because "the post-stamp diff would carry the base branch's own changes". `range` was written as a new verb and did not inherit that rule, because the rule lived inline in one caller instead of in the module that owns "which commits are this slice's".

Both independent `/pre-merge` reviewers found this on the first review and reproduced it in scratch repositories. The author's own fixtures never advanced the base after recording a start, so the primary path and the fallback agreed on every case the suite ran.

## Learning Level

- **Level:** Pattern. The same check already existed for the review stamp, and this is the second recorded SHA in the pack used as a range endpoint.
- **Feedback loop or delay:** none at authoring time. The defect shows only after a base has moved, which no fixture simulated, and the result is a wider review. That reads as safe even though it is not this branch's work.

## Rule Scope

- **Applies when:** a SHA recorded earlier (a slice start, a review stamp, any "since" marker) becomes the left end of `<sha>..HEAD` or `<sha>...HEAD` on a branch that can be rebased onto, or merged with, a base that has moved since.
- **Inverts or does not apply when:** the range is meant to include the base's commits, or the branch can never take base commits (for example, a pinned release branch). If the base is the left end itself (`<base>..HEAD`), git's own set subtraction already excludes the base's commits, and no extra check applies.
- **Sibling docs:** `docs/solutions/architecture-decisions/compat-default-is-every-failures-answer-2026-10-24.md` (why `range`'s could-not-look exit stays separate from its fallback); `docs/solutions/testing-patterns/a-preset-variable-tests-a-path-no-run-takes-2026-10-26.md` (a fixture where two paths give the same answer).

## Solution

Status at capture: unfixed. This is Concern 1 on PR #622. The guard belongs inside `range`, the module both callers read, and not in either caller. `/pre-merge` takes only the left end, so it cannot subtract the base afterward.

Use the recorded start only when it **contains** the branch's fork point and nothing from the base follows it. Otherwise fall back to the base range, with the same named notice the fold case prints:

```bash
fork=$(git merge-base "$base" HEAD)
if git merge-base --is-ancestor "$fork" "$start" \
   && [ -z "$(git log --merges --format=%H "$start..HEAD")" ]; then
  echo "$start..HEAD"           # every commit after the start is this branch's
else
  echo "$base..HEAD"            # the base moved under the start; say so on stderr
fi
```

## Prevention

**Code-level:** a fixture that records a start, lands a commit on the base, rebases the branch onto it, and asserts that `range` answers the base range with a notice. Add a second fixture that merges the base in instead. Both should carry a `Fix-Findings-Run:` line on the base commit, so that the round count goes wrong visibly if the guard regresses.

**Process-level:** when a new verb takes over a decision that a caller used to make inline, read the caller's fallback list and move each condition into the verb. `/pre-merge` step 4's "merge after the stamp" condition was in view and was not carried over.

## Related

- PR #622, slice #599, PRD #596, issue #586
- `pre-merge/SKILL.md` Phase 1 step 4 (the same rule, for the review stamp)

## Shelf Life

When `range` checks containment and the rebase and merge fixtures are in `scripts/test-sidecar-resolution.sh`, this entry is a record of why they are there. The rule itself is evergreen for any recorded-SHA range endpoint.
