---
date: 2026-11-18
category: devops
problem_type: a declared test command that selects its jobs from changed files exits 0 when the selection is empty, and the exit status is reported as a passing test run
components: [lefthook, fix-findings, execute, sidecar profile]
technologies: [lefthook, git-hooks, bash]
severity: medium
volatility: stable
paths: [lefthook.yml, fix-findings/SKILL.md, execute/SKILL.md]
replaces: []
related: [local-gates-absent-in-a-fresh-worktree-2026-08-24.md, validate-the-instrument-not-only-the-subject-2026-08-23.md]
---

# A declared test command exits 0 having run nothing

## Problem

This repo declared `lefthook run pre-push` as its test command. On a branch whose upstream already holds every commit, lefthook skips every job and exits 0 in about a second. A `/fix-findings` fixer ran it, got exit 0, and reported that as its test result. No suite had run.

## Context

PR #790 went through a `/fix-findings` round after its first review. Each fixer is told to "Run the test command the profile names and report the exit status verbatim" (`fix-findings/SKILL.md`, Step 1, item 4). The profile's `test` line was `lefthook run pre-push`. The branch had been pushed when the PR opened, and a fixer runs the command before it commits, so there was nothing to push at the moment the command ran.

Earlier, in `/execute`, the same command had run all 67 pre-push jobs. The branch had no upstream then.

## Symptoms

- The run finishes in about a second. A real run of this repo's pre-push suites takes about three minutes.
- Every job line reads `(skip) no matching push files`.
- The log has no job-passed lines. A real run has one per job, 67 at the time of writing.
- The exit status is 0, and the report that quotes it looks like every other green report.

Reproduce it on any branch with an upstream and no unpushed commits:

```bash
lefthook run pre-push; echo "exit=$?"
```

## Root Cause

The pipeline reads a test command's exit status as "the tests passed". A hook manager answers a narrower question: did the jobs selected for this push pass? With nothing to push, nothing is selected, and "none of zero jobs failed" is still exit 0.

The exit status is the only thing the fixer's instruction asks for, so nothing in the report shows that the selection was empty. The controller caught this run only because it noticed the duration.

## Learning Level

- **Level:** Pattern.
- **Feedback loop or delay:** the missing feedback is a count. A report that carries an exit status and no count of what ran cannot tell a pass from a run that did nothing. The gap also opens late: the command behaves until the branch is first pushed, so a check made at the start of the work does not see it.

This is the second recording of one pattern. `local-gates-absent-in-a-fresh-worktree-2026-08-24.md` is the first: there the hooks were never installed, so every commit succeeded and no gate ran. Here the command was invoked on purpose and selected nothing. In both, a gate is read as passed when it did not run.

## Rule Scope

- **Applies when:** the declared test command is a hook manager, or any runner that picks its work from changed, staged, or pushed files, and it is run by hand outside the git event it was written for.
- **Inverts or does not apply when:** the runner always runs its whole suite. Then exit 0 does mean the suite passed, and adding a count is harmless but not needed.
- **Sibling docs:** `local-gates-absent-in-a-fresh-worktree-2026-08-24.md` (gates wired and never installed), `validate-the-instrument-not-only-the-subject-2026-08-23.md` (a measuring instrument that fails while reporting normally).

## Solution

Declare the form of the command that cannot select nothing. `lefthook run --help` lists two flags that do this: `--all-files` ("replace files templates with {all_files}") and `--force, -f` ("do not skip if no files changed").

**Before** (the sidecar profile's `verify.test`):

```
lefthook run pre-push
```

**After:**

```
lefthook run pre-push --all-files
```

The `--all-files` form was run four times on PR #790's branch after the first push: exit 0 each time, 67 jobs passed, none skipped.

## Prevention

**Code-level:** the command that runs this repo's whole local suite is stated in the header of `scripts/run-changed-suites.sh`.

**Process-level:** chrislacey89/skills#793 proposes that `/fix-findings` Step 1 ask for evidence that checks ran (a count of tests or jobs) beside the exit status, the way `/execute` Step 4, Tier 2 already does ("confirm tests actually exist and ran"), and that the controller treat a count of zero as not run. Until that lands, a controller should check a fixer's test claim against the run's duration or its job count before repeating it.

When declaring a test command for any repo, run it once on a branch with nothing staged and nothing to push. If it finishes at once, it is selecting from changed files.

## Planning / Calibration Notes

- **What widened the work:** one extra full run of the suite by the controller, and a changed brief for the three fixers that followed.
- **Future planning adjustment:** when a slice's verification leans on a declared command, the Review Notes should give the number of jobs or tests that ran, not the exit status alone.

## Related

- PR #790, where it happened.
- chrislacey89/skills#793, the pack-level proposal.
- `docs/solutions/devops/local-gates-absent-in-a-fresh-worktree-2026-08-24.md`
- `docs/solutions/testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md`

## Shelf Life

The lefthook detail expires if lefthook stops skipping pre-push jobs when there are no push files, or if this repo moves its suites off a hook manager. The rule that an exit status needs a count beside it is evergreen.
