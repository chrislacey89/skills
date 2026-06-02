---
name: closeout
description: "Primary pipeline tail step after /pre-merge, when a reviewed PR is ready to land and you want the workspace back to a clean base. Use to merge, switch off the worktree before removing it, prune the merged branch, pull base, and verify a clean end state. Triggers on 'close out', 'merge and clean up', 'get back to a clean main/base', 'tear down the worktree'. Not for capturing lessons (that's /compound) or closing PRD/slice issues and research-artifact hygiene (that's the cleanup prose in SYSTEM-OVERVIEW Step 9)."
sources:
  primary:
    - "Thinking in Systems — Donella H. Meadows"
    - "The Design of Everyday Things — Donald A. Norman"
  secondary:
    - "The Checklist Manifesto — Atul Gawande"
    - "Continuous Delivery — Jez Humble, David Farley"
---

# Closeout

Take a reviewed PR and return the workspace to a clean base — merge, switch the shell off the worktree before removing it, prune the merged branch, pull base, and verify the end state. This is the pipeline's tail: the most-repeated motion ("I'm done, merge it and get me back to a clean main") moved out of the user's head and into a skill.

## Why This Exists

`/execute` Step 0 *creates* a worktree for every slice; until this skill existed, nothing *removed* one. Worktrees are a stock with an inflow and no outflow, so the stock rises without bound (Meadows, *Thinking in Systems* — the structural escape for an inflow-without-outflow stock is to *add the missing feedback loop*, not to exhort harder). The merge → teardown → pull sequence lived only in the user's memory, and "prospective memory fails silently" (Norman, *The Design of Everyday Things* — move the knowledge from the head into the world). The ordering is genuinely error-prone: removing a worktree while the shell's cwd is still *inside* it strands the shell on a trashed directory, and a `node_modules`-dependent Stop hook firing from there emits a wall of false `MODULE_NOT_FOUND` "lint/type errors" that read like a real regression. The cd-to-base-before-remove ordering in Step 4 is the load-bearing fix for exactly that slip.

This skill *orchestrates existing tools* (`gh pr merge`, `wt remove` / `git worktree remove`, `commit-commands:clean_gone`). It introduces no filesystem state. It verifies the **outcome** — clean tree, on a fresh base, PR merged — not merely that cleanup *ran* (Meadows' "seeking the wrong goal": a closeout measured by "did it run" optimizes the proxy and produces brittle ceremony).

## Invocation Position

This is a primary pipeline skill that owns the `merge → cleanup` tail of the default delivery path:

```
… → /pre-merge → [merge + worktree teardown — THIS SKILL] → /compound → [issue-closing — Step 9 prose]
```

Use `/closeout` when:

- `/pre-merge` has created a PR and the review is done (or the change is trivial enough not to need one)
- the PR is approved and mergeable, and you want it merged and the workspace returned to a clean base
- the user asks to "close out," "merge and clean up," "tear down the worktree," or "get back to a clean main/base"

Do not use `/closeout` when:

- the PR is not yet created or still under review — run `/pre-merge` first
- you want to capture a durable lesson — that is `/compound` (which, per the PR-attachable model, may already have ridden the PR before merge); `/closeout` does not capture lessons
- you want to close the PRD and slice issues or reconcile the research artifact's frontmatter — that is the cleanup prose in `SYSTEM-OVERVIEW.md` Step 9; `/closeout` performs the *git-hygiene* half and defers the *issue-closing and research-artifact-supersession* half to Step 9 rather than duplicating it
- the change is not on a feature branch at all (you are on the base branch with nothing to merge) — there is nothing to close out

It is HITL-confirmed and non-blocking: it operationalizes an already-optional tail. It never auto-merges — merge is outward-facing and hard to reverse, so it always confirms first.

## Process

Run this as a do-confirm checklist (Gawande): perform each step, then verify its outcome before the next. The destructive steps (4–6) are self-guarded — confirm the safety preconditions in Step 2 hold before running them.

### 1. Confirm intent and gather state

Never auto-merge. State what you are about to do and get an explicit go-ahead.

Gather the facts first (these are read-only):

```bash
git branch --show-current                                   # the feature branch
git rev-parse --show-toplevel                               # the current working tree (may be a worktree)
git worktree list --porcelain | awk '/^worktree /{print $2; exit}'   # the BASE checkout (main working tree)
gh pr view --json number,title,url,state,mergeable,mergeStateStatus,reviewDecision 2>/dev/null
```

Determine the base branch the PR targets — the repo's declared default, not an assumption:

```bash
git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null   # e.g. origin/main → main; origin/prod → prod
```

Tell the user, in one short block: which PR will merge, which worktree (if any) and branch will be torn down, and which base branch you will return to and pull. Wait for confirmation. If there is no PR on this branch, stop and route to `/pre-merge`.

### 2. Verify safety preconditions before any destructive step

The teardown is destructive; verify it is safe first (self-guard). All of these must hold:

- [ ] The feature branch is fully pushed — `git status` shows no unpushed commits, and `git log @{u}..` is empty.
- [ ] A PR exists for this branch and is mergeable (`mergeable` is `MERGEABLE`; `mergeStateStatus` is not `BLOCKED`/`DIRTY`).
- [ ] Required checks are green and review is approved (`reviewDecision` is `APPROVED`, or the repo does not require review and the user has explicitly accepted).

If any precondition fails, stop and report which one — do not merge or remove anything. A failed precondition is a signal to return to review, not to force through.

### 3. Merge the PR

Merge with the repo's convention (squash is the common default; confirm if unsure). Let the merge delete the remote branch where the platform supports it:

```bash
gh pr merge <number> --squash --delete-branch   # or --merge / --rebase per repo convention
```

Confirm the PR now reports `MERGED` before touching the worktree:

```bash
gh pr view <number> --json state -q .state       # expect: MERGED
```

### 4. Re-anchor the shell to the base checkout — BEFORE removing the worktree

**This is the load-bearing step.** If the current working tree is a linked worktree, move the shell to the base checkout *now*, while the worktree still exists, so nothing is removed out from under the running shell. Pick the re-anchor mechanism that matches how the session got into the worktree:

**If this same session entered the worktree via `EnterWorktree`** — the inflow `/execute` now uses (`pwd` reports a path under `.claude/worktrees/` and `EnterWorktree` was called earlier in *this* session) — re-anchor with the matching harness tool, not a bare `cd`:

`ExitWorktree { action: "keep" }` restores the shell to the base checkout (the directory the session was in before `EnterWorktree`) and, per the tool's contract, will *not* remove a worktree entered via `path`. Use `keep`, never `remove`: the worktree's branch is what just merged, and Step 5/6 own its teardown and pruning. Removal stays in Step 5.

**Otherwise** — a fresh `/closeout` session that did not itself call `EnterWorktree`, or a plain `git checkout -b` checkout with no worktree — re-anchor with a bare `cd` (`ExitWorktree` only operates on worktrees its own session entered, so it is a no-op here):

```bash
cd "$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
git rev-parse --show-toplevel    # confirm cwd is now the base checkout, not the worktree
```

If Step 1 showed the current tree *is* the base checkout (you were on a plain `git checkout -b` branch, not a worktree), there is no worktree to remove — skip to switching branches:

```bash
git switch <base-branch>
```

Either way, confirm the shell is no longer inside the feature worktree before proceeding.

### 5. Remove the worktree (only if one was created)

Now that the shell is anchored to the base checkout, removing the worktree is safe:

```bash
wt remove <worktree-or-branch>          # if worktrunk is available
# or
git worktree remove <worktree-path>     # plain git
```

If the worktree has uncommitted or untracked changes you have not accounted for, `git worktree remove` will refuse — investigate rather than forcing `--force`. (Everything reviewed in the PR is already merged; anything left behind is unexpected.)

### 6. Prune the merged branch

The local feature branch (and its now-`[gone]` remote-tracking ref) is dead weight after merge. Prune it:

```bash
git fetch --prune                       # drop the [gone] remote-tracking ref
git branch -d <feature-branch>           # safe delete; fails if not merged — investigate if it does
```

`commit-commands:clean_gone` removes all `[gone]` branches and their worktrees in one pass — prefer it when several stale worktrees have accumulated (the recurring symptom this skill exists to stop). Do not reimplement what it already does.

### 7. Pull the base branch

Bring the local base up to date so it reflects the merge you just made:

```bash
git pull --ff-only       # fast-forward; resolves the merge into local base
```

### 8. Verify the clean end state (outcome, not activity)

Confirm the *outcome*, not that the steps ran. All must be true:

- [ ] On the base branch — `git branch --show-current` reports the base.
- [ ] Working tree clean — `git status --short` is empty.
- [ ] PR merged — `gh pr view <number> --json state -q .state` reports `MERGED`.
- [ ] Worktree gone — the feature worktree no longer appears in `git worktree list`.
- [ ] Branch pruned — the feature branch no longer appears in `git branch`.

Report the end state in one short block. If any check fails, say which and stop — a half-clean state is exactly the failure mode this skill exists to prevent.

### 9. Hand off

- If a durable lesson emerged from this work and was **not** already captured on the PR (per the PR-attachable `/compound` model), invoke `/compound` now. If the lesson already rode the PR, say so and skip it. `/closeout` never captures lessons itself.
- Closing the PRD and any remaining slice issues, and confirming the research artifact's frontmatter still reflects what shipped (superseding with a new dated artifact if a version bumped), is the cleanup prose in `SYSTEM-OVERVIEW.md` Step 9 — name it as the remaining tail work; do not perform research-artifact supersession from here.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The PR looks fine, I'll just merge it without asking." | Merge is outward-facing and hard to reverse. `/closeout` always confirms intent first (Step 1). Auto-merge is an explicit non-goal. |
| "I'll `wt remove` first, then `cd` out of the trashed directory." | That is the exact slip this skill exists to prevent — it strands the shell inside a removed worktree and makes a `node_modules`-dependent Stop hook emit false `MODULE_NOT_FOUND` errors. Re-anchor to base *before* removing (Step 4). |
| "Verifying the steps ran is the same as verifying it worked." | Meadows' "seeking the wrong goal" — measuring activity, not outcome. Step 8 checks the actual end state: on base, clean tree, PR merged, worktree gone, branch pruned. |
| "I'll force the worktree removal — there's just some leftover state." | Everything reviewed is already merged; leftover state is unexpected. Investigate it rather than `--force`-ing it away. |
| "I'll close the PRD issue and refresh the research artifact while I'm here." | That is Step 9's job, not closeout's. Performing research-artifact supersession from here duplicates and risks contradicting the canonical cleanup prose. Name it as remaining work and hand off. |
| "I'll capture the lesson in `docs/solutions/` as part of closing out." | That is `/compound`. Under the PR-attachable model the lesson may already be on the PR; if it isn't, hand to `/compound` — don't fold knowledge capture into closeout. |

## Red Flags

- About to run `wt remove` / `git worktree remove` while the shell's cwd is still inside that worktree.
- Merging before confirming the PR is pushed, mergeable, and approved (skipping Step 2).
- A Stop hook or feedback loop suddenly reporting `MODULE_NOT_FOUND` / "cannot find module" for `biome`, `tsc`, or `vitest` right after a teardown — almost always a stranded cwd, not a real failure.
- Reporting "cleanup done" without the Step 8 outcome checks actually passing.
- `git worktree list` showing several stale feature worktrees — evidence the outflow loop is being skipped; this is the symptom closeout removes.
- Closeout performing issue-closing or research-artifact supersession itself instead of deferring to Step 9.

## Verification

A run of `/closeout` is not complete until:

- the user explicitly confirmed the merge before it ran
- the PR reports `MERGED`
- the shell was re-anchored to the base checkout *before* the worktree was removed
- the feature worktree (if one existed) is gone from `git worktree list` and the merged branch is pruned
- the base branch was pulled and the working tree is clean on the base branch
- the end state was reported, and remaining tail work (`/compound` if a lesson is uncaptured, Step 9 issue-closing) was named in the handoff

## Handoff

- **Expected input:** a reviewed, mergeable PR created by `/pre-merge`, on a feature branch (in a worktree or a plain checkout)
- **Produces:** the PR merged, the worktree torn down, the merged branch pruned, the base branch pulled, and a verified clean end state — no filesystem state introduced
- **May invoke:** `/compound` when a durable lesson emerged and was not already captured on the PR
- **Comes next by default:** `/compound` (only when an uncaptured lesson is worth recording) and the `SYSTEM-OVERVIEW.md` Step 9 cleanup prose (close the PRD and slice issues, confirm research-artifact frontmatter). After that, the loop is closed — `/help` when you return to the repo.
