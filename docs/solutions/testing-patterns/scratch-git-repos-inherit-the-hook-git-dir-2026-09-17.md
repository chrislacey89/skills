---
date: 2026-09-17
category: testing-patterns
problem_type: a contract suite builds a scratch git repo, but run from a git hook it inherits GIT_DIR, so its fixture git commands rewrite the real repository's shared config while the suite reports green
components: [scripts/test-*.sh, lefthook pre-push, git worktrees, shared .git/config]
technologies: [git, git-hooks, git-worktrees, lefthook, bash]
severity: high
volatility: evergreen
---

# Scratch git repos inherit the hook's GIT_DIR and rewrite the real repo

## Problem

A contract suite that builds a scratch repo with `git init <dir>` and configures it with `git config` does not clear the git environment it inherits. When git runs that suite as a hook from a linked worktree, `GIT_DIR` is already set, and the suite's fixture commands land on the real repository instead of the scratch one. It writes `core.bare=true` into the shared config, and sometimes the fixture's identity and `core.hooksPath` too. Fixtures that commit move the pushing worktree's branch to fixture commits and can leave stray fixture branches in the shared refs. The suite still passes.

## Context

This came up during the delta review of PR #373. That PR added a classification-marker suite whose fix for an earlier finding made it `git init` a scratch repo. The reviewer checked what happens under the environment a pre-push hook provides. The repo's `lefthook.yml` runs every `scripts/test-*.sh` on pre-push, and pushing from a worktree is the normal workflow here: Conductor workspaces are linked worktrees of one checkout.

## Symptoms

- **Every worktree breaks at once.** `git status` and `git diff` fail with "must be run in a work tree", because the shared config now reads `core.bare=true`.
- **The shared config carries a fixture identity.** Here that was `user.name=t` / `user.email=t@example.com`, so a session's git-status banner reports the user as `t`.
- **The pushing worktree's branch points at a fixture commit**, and a stray `feature` branch can appear in the shared refs. A full sandbox pre-push with this damage went red with 14 unrelated suites failing as it spread, so in practice it can also look like a blocked push with many unrelated failures.
- **`core.hooksPath` points at a temp directory that no longer exists** (`…/tmp.XXXX/no-hooks`). That silently disables lefthook in every worktree.
- **The triggering run reports green.** The compound re-stamp handoff suite printed **17 passed, 0 failed** while doing all of the above. Nothing points at the suite that did it, and the damage surfaces sessions later as "hooks don't run" or "git user is t".

## Root Cause

Git exports `GIT_DIR` into the environment of hooks it runs from a linked worktree. A child process that runs `git init <scratch>` or `git config …` inherits it. Git uses an explicit `GIT_DIR` in preference to discovering a repository from the target directory. So `git init` re-initializes whatever `GIT_DIR` names, which is the real repository's gitdir, and `git config` writes to that repository's config. A linked worktree's config is the shared `.git/config` of the main checkout, so every worktree inherits the result.

Measured in a sandbox clone with a linked worktree, one suite per run, `GIT_DIR` set the way a hook sets it:

| Suite | Shared config afterward | Suite output |
|---|---|---|
| post-review edit lock | `core.bare=true` | 106 passed, 4 failed |
| delta review scope | `core.bare=true`, `user.name=t` | FATAL (fixture) |
| compound re-stamp handoff | `core.bare=true`, `core.hooksPath=<deleted temp>/no-hooks` | 17 passed, 0 failed |
| population covers untracked | `core.bare=true`, `user.name=t` | FATAL (fixture) |
| classification marker, before the fix | `core.bare=true` | 20 passed, 0 failed |

That table was the first count. A follow-up measurement on chrislacey89/skills#374 found three more suites with the same defect (documented git commands, markdown diff attribute, syntax palette contract). Each wrote a fixture identity into the shared config and moved the worktree's branch to a fixture commit, and two of them still passed.

A real `git push` from a sandbox worktree, whose pre-push hook dumped its environment, carried `GIT_DIR`, `GIT_EDITOR`, `GIT_EXEC_PATH` and `GIT_PREFIX`. A push made with `git -c` also carries `GIT_CONFIG_PARAMETERS`. Pre-commit hooks add `GIT_INDEX_FILE`. A push from the main checkout carries no `GIT_DIR`, which is why the hazard is specific to worktrees.

## Learning Level

- **Level:** Structure.
- **Feedback loop or delay:** a delayed effect that looks like its own cause. The hook run that corrupts the config also writes a dead `core.hooksPath`, which stops the next hook from running. So after the first corruption the hazard can't recur, and it can't be seen either: the visible symptom becomes "local gates don't run" (see the sibling entry below), not "a suite broke the config". Removing the dead `hooksPath` as a cleanup brings back exactly the conditions that produced it. PR #373's first Review Notes attributed that `hooksPath` to Conductor. That wrong explanation is what the delay produces.

## Rule Scope

- **Applies when:** a script runs git commands meant for a directory other than the repository it was launched from (`git init <dir>`, `git config` inside a scratch repo, `git -C <scratch> …`), and anything could run the script as, or from, a git hook. In this repo that means every `scripts/test-*.sh`, because `lefthook.yml` runs them on pre-push. Outside the suites, a sidecar `git -C <dir> commit` is one example (`scripts/test-sidecar-resolution.sh` pins that case).
- **Inverts or does not apply when:** the script is supposed to act on its caller's repository through the inherited variables. A hook body that reads `GIT_DIR` to find the repo it serves is correct, and unsetting would break it. The unset belongs only in code that builds or targets its own repository. It also doesn't apply to git commands that act on the repo the suite lives in (`git ls-files`, `git check-ignore` against `$repo_root`). Those resolve correctly from the working directory once the variables are gone, and resolved correctly with them set as long as they pointed at the same repo.
- **Sibling docs:** `../devops/local-gates-absent-in-a-fresh-worktree-2026-08-24.md` covers the state this defect leaves behind (hooks not running). It is a different pattern with a shared symptom. `dead-guards-report-coverage-they-do-not-have-2026-08-27.md` is a different pattern: its scratch repo sits under a hostile `core.hooksPath` rather than an inherited `GIT_DIR`.

## Solution

Clear the variables git uses to choose a repository, before the script's first git call:

**Before:**
```bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
# … later …
git init -q "$reserved_repo"   # under a hook, re-initializes the real repo
```

**After** (`scripts/test-lfg-marker.sh`, commit 1527e43):
```bash
set -euo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

A breaker confirmed this against a real pre-push hook fired by a real `git push` from a worktree. With the line, `core.bare` stayed `false` and the suite passed. With the line deleted, `core.bare` flipped to `true` and the suite still passed.

To recover a repository that is already damaged, fix the suites first. Then remove `core.bare=true`, the fixture identity, and the dead `core.hooksPath` from the shared config, reset any branch moved to a fixture commit, and delete stray fixture branches. Doing it in the other order means the next worktree push re-corrupts it.

## Prevention

**Code-level:** every `scripts/test-*.sh` that builds scratch git state now unsets `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` before its first git call (#427, #433, #403). The mechanism that catches the next instance is `scripts/test-fixture-git-isolation.sh`. It runs every suite pre-push runs, read from `lefthook.yml`, from a linked worktree of a throwaway clone with a hook-style `GIT_DIR`, and it fails naming any suite that changed the shared config, any ref, or the worktree's HEAD. It checks behavior rather than grepping for the `unset` line, because a grep proves the line exists, not that the suite stays out of the real repo. It first runs against planted leaks of each shape (init, config, ref, HEAD, and a commit that also deletes a file) and a planted guarded suite, and must tell them apart. After any leak it rebuilds the scratch worktree, so one leak cannot make a later suite exit early and hide a second. It fails unless the suites it reads from `lefthook.yml` are exactly `scripts/test-*.sh` minus itself. It runs in CI only, not on pre-push (#442). Its stated blind spots are writes to hooks, objects, the index, or worktree files that move no config or ref, and leaks on code paths the scratch run never reaches.

**Process-level:** never reproduce this against a real checkout. A reviewer on #373 did, to confirm the finding, and flipped the maintainer's shared config to bare; it was restored by hand. Any sub-agent brief that tests hook-environment behavior should require a throwaway clone with its own worktree, and should end by checking `core.bare` on the real shared config.

## Defect Classification

**Origin phase:** Coding error in test fixtures. The fixtures were written to run from an interactive shell, where `GIT_DIR` is unset, and the pre-push wiring put them in an environment nobody modeled.
**Fix type:** Correction in `scripts/test-lfg-marker.sh`, then in the six other suites (#427, #433, #403), plus a detector across all suites, `scripts/test-fixture-git-isolation.sh` (#438, extended to refs under chrislacey89/skills#374).

## Clustering check

This is the first recording of this pattern. The nearest entry is `devops/local-gates-absent-in-a-fresh-worktree-2026-08-24.md`. That entry is about a hook manager never installed in a worktree, and this one is about fixtures that corrupt the shared config and leave a dead `hooksPath` behind. They share the symptom "local gates don't run" but not the mechanism, so this is a different pattern. Its mechanism is `scripts/test-fixture-git-isolation.sh` (PR #438).

## Related

- PR #373: the delta review that found it, and commit 1527e43, the fix and its breaker verdict
- chrislacey89/skills#374: the seven-suite scope, the ref damage, and the cross-suite check
- `scripts/test-fixture-git-isolation.sh`: the detector
- `../devops/local-gates-absent-in-a-fresh-worktree-2026-08-24.md`: the downstream symptom

## Shelf Life

The fix and its detector have landed, so the entry no longer tracks open work. Keep it while `scripts/test-fixture-git-isolation.sh` exists: it records why that suite exists and what its planted leaks stand for. Retire it if pre-push stops running suites from linked worktrees. The git behavior itself is stable, so **evergreen** until then.
