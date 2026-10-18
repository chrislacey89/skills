---
date: 2026-10-17
category: testing-patterns
problem_type: content-addressed fixtures built from identical inputs collide, so a test keyed on git object identity sees two fixtures as one
components: [scripts/test-sidecar-resolution.sh, init-pipeline/scripts/sidecar.sh, scratch-repo fixtures]
technologies: [git, bash, GitHub Actions]
severity: medium
volatility: evergreen
---

# Identical scratch commits share a root SHA

## Problem

A test suite that builds several scratch git repos with the same helper gets the same commit SHAs in different repos whenever they are created within the same second. Any code under test that uses a commit SHA as an identity treats those repos as one, and the suite fails or passes for the wrong reason depending on how fast the machine is.

## Context

`sidecar.sh` (#410) identifies a project by its root commit, the first commit in its history, so every clone and worktree of one repo resolves to one sidecar. Its contract test builds fixture repos with a `mkrepo` helper that made two empty commits with fixed messages. Locally the suite was green with an occasional unexplained failure in the init-cleanup sections. In CI it failed every run: `a retry after removing the hook succeeds` and `a retry after the jq failure succeeds`, with `fatal: cannot change to '.../sidecars/hostile'`.

## Symptoms

- A test passes locally and fails consistently on CI, or fails roughly one run in five locally and never reproduces when you look.
- The code under test refuses or merges things the fixture author meant to be distinct. Here: `init refused: root:<sha> already belongs to sidecar proj`.
- Earlier assertions in the same section pass for the wrong reason. A check that "init exits 1 when the hook fails" passed because init exited 1 on the alias refusal before it ever reached the hook.
- Pinning `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` to one value turns the intermittent failure into a deterministic one (89 passed, 9 failed here).

## Root Cause

A git commit's SHA is a hash of its tree, parents, author, committer, timestamps, and message. An empty commit with a fixed message, made by a fixed test identity, has no input that differs between fixtures except the timestamp, and git timestamps have one-second resolution. Two fixtures made in the same second therefore produce byte-identical root commits. A fast CI runner builds many fixtures per second; a laptop under load builds fewer, so it collides only sometimes.

This was not predictable from the code under test. `sidecar.sh` was correct to treat identical roots as one project, which is the behavior its PRD asks for. The defect was in the fixture, and it only surfaced because the code under test keys on exactly the property the fixture failed to vary.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** The local feedback loop hid the defect. Slow, variable fixture creation made the collision rare, and each rare failure looked like flakiness rather than a signal. The CI runner, being faster, was the first environment where the loop was tight enough to fail every time.

## Rule Scope

- **Applies when:** a test builds two or more git repos (or any content-addressed objects: blobs, container layers, hashed cache keys) from the same helper with identical inputs, *and* the code under test uses the resulting hash as an identity or a lookup key.
- **Inverts or does not apply when:** the test needs two checkouts to share identity on purpose. Build those from the original repo with `git clone`, `git worktree add`, or a shallow clone, not from the helper; they share history by construction and must keep doing so. Also does not apply when the code under test never reads the hash.
- **Sibling docs:** `scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md` covers a different scratch-repo hazard: the fixture's git commands landing in the *real* repo through an inherited `GIT_DIR`. Both are fixtures that look isolated and are not, but the mechanisms differ (environment leak vs content collision) and so do the fixes.

## Solution

Put something unique per fixture into an input of the root commit. The fixture's own path is free and always distinct:

**Before:**
```bash
mkrepo() {
    git init -q "$1"
    git -C "$1" commit -q --allow-empty -m "root"
    git -C "$1" commit -q --allow-empty -m "second"
}
```

**After:**
```bash
mkrepo() {
    git init -q "$1"
    git -C "$1" commit -q --allow-empty -m "root $1"
    git -C "$1" commit -q --allow-empty -m "second"
}
```

Then make the failure-path assertions state their reason, so a collision cannot satisfy them by accident: the hostile-hook section now also checks that the output names the hook (`the failure is the hostile hook, not an alias refusal`).

## Prevention

**Code-level:** To prove a fixture fix, run the suite with `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` exported to one fixed value. That forces the worst case on any machine. A constant-message helper under fixed dates fails 10 assertions, and the fixed helper passes all 99. For a failure-path test, assert the reason as well as the exit status: an exit status alone is satisfied by any earlier refusal.

**Process-level:** When a test is intermittent locally and steady in CI, suspect a timing-dependent input before suspecting the code under test. Rerunning the test until it passes throws the evidence away.

## Related

- #410, PR #417: the slice that introduced root-commit identity and this suite.
- `scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md`

## Shelf Life

Evergreen. It holds for as long as git uses one-second timestamps and tests key on object identity.
