---
date: 2026-08-24
category: devops
problem_type: a repo's commit-time gates are wired, correct, and absent at runtime because the hook manager was never installed in this worktree
components: [lefthook, execute, pre-merge, scripts/check-shellcheck-version.sh]
technologies: [git-worktrees, git-hooks, lefthook, shellcheck, conductor, codespaces]
severity: medium
volatility: evergreen
---

# A mechanism that was built, wired, and never ran

## Problem

A repo documents pre-commit and pre-push checks and wires them into a hook manager. From then on everyone reasons as though they run. They run only where the manager is installed — and git hooks live in `.git/hooks`, which is **per-worktree and untracked**. A fresh worktree inherits none of them, nothing reports the absence, and every commit succeeds.

## Context

PR #278 derived a landing page's canon from `sources:` frontmatter. Eight commits, in a Conductor workspace. `lefthook.yml` declares four pre-commit commands and fifteen pre-push suites; `lefthook` was not on `PATH` and `.git/worktrees/cape-town/hooks/` was empty. **Not one of those checks ran, once, across the whole branch.**

The one that mattered was `scripts/check-shellcheck-version.sh` — a warner written for PR #271 to stop exactly this session's mistake. Run by hand it is unambiguous:

```
shellcheck-version: local 0.11.0, CI gates on 0.9.0.
  A local pass does NOT mean the merge gate passes.
  Read the PR check, not this run, before reporting "shellcheck clean".
```

The session reported `shellcheck scripts/*.sh | 0` into the PR body's review notes as a merge signal. Local was 0.11.0. CI pins 0.9.0, which flagged SC2015 on a line the branch had just added and would have failed the required check.

## Symptoms

- Every documented commit-time guarantee is cited in reasoning and none of them has produced output all session.
- `git commit` never prints hook output — no timings, no check names, nothing — and this reads as "the hooks passed quietly."
- A tool the repo pins is reported by version-free name ("lint clean", "tests pass").
- `ls "$(git rev-parse --git-dir)/hooks/" | grep -v '\.sample$'` is empty; the declared manager is not on `PATH`.
- The environment is a host-provisioned workspace (Conductor, Codespaces, devcontainer) or any freshly created worktree.

## Root Cause

Two independent facts that compose badly.

**Git hooks are per-worktree and untracked.** `.git/hooks` is not in the tree, and for a linked worktree it resolves under `.git/worktrees/<name>/hooks/`. Cloning, `git worktree add`, and a host workspace provisioner all produce a checkout with the repo's *files* and none of its *hooks*. Installing them is a separate, manual, per-clone act — `lefthook.yml` says so in its own header ("run `lefthook install` once per clone"), and that sentence is addressed to a human reading the repo, not to a session that arrives inside an already-provisioned workspace.

**The absence is unreportable by anything local.** The natural place to detect "local checks did not run" is a local check — which has the same absence. So the failure has no local signal at all, in either direction: hooks firing and hooks not existing both look like a clean `git commit`.

`/execute` Step 0's worktree setup checklist confirms `.env.local`, dependencies, session cwd, `$CLAUDE_PROJECT_DIR`, and TDD markers. It said nothing about hooks. Worse, its host-provisioned stand-down actively reassured past the gap: *"The host has already seeded git-ignored config and dependencies, so the 'Worktree setup checklist' is informational only."* True about config and dependencies, and the host-provisioned path is precisely where hooks are most likely to be missing.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback runs from *whether a gate executed* back to *the confidence placed in it*. Gate-passed and gate-absent are the same observation. The delay is what makes it expensive: the defect is still caught, by CI, but one push and one review round later — and in the interval the session writes a verification claim the reviewer may act on. The cost is not escape, it is **a false claim entering the artifact the reviewer trusts**.

## Rule Scope

- **Applies when:** the repo delegates checks to a hook manager requiring per-clone installation (`lefthook install`, `husky install`, `pre-commit install`); **and** the working copy was not set up by the person who installed those hooks — a fresh clone, a `git worktree add`, or a host-provisioned workspace (Conductor, Codespaces, devcontainer, cloud IDE).
- **Inverts or does not apply when:**
  - **`core.hooksPath` points at a tracked directory.** Then hooks *are* tracked and every checkout has them; the failure cannot occur, and adding a checklist item is noise.
  - **CI runs the same checks and nothing is claimed before CI reports.** The gap is latency only. It becomes real the moment a local run is *reported as* a merge signal — which is the failure mode, not the missing hook.
  - **The checks are slow enough that hooks were deliberately skipped.** Then the absence is a decision, and the fix is to record it in the review notes rather than to install anything.
- **Sibling docs:**
  - `../testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md` — the closest sibling and the **inverted axis**. Its five instances are *the instrument disagreed with the gate*: two reviewers ran shellcheck 0.11.0 against a 0.9.0 gate and reported clean three times. This is *the instrument was correct and never ran*. Same family — a measurement channel that reads normally while measuring nothing — approached from opposite sides, which is why it is a separate entry rather than a sixth instance folded into that one.
  - `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — the mirror. There, a claim is asserted and nothing constructs it. Here, something *is* constructed, correctly, and is not present where it is relied on. Its central line — *"a limitation, a source gap, a stamped interval, or a verification that constrains nothing downstream is a footnote, not a mechanism"* — extends cleanly: **a mechanism that is not installed is also a footnote.**

## Solution

Two tells in `/execute`, because nothing local can gate this.

**Step 0 — the worktree setup checklist gains an item** naming the fact that makes the absence invisible:

```markdown
- [ ] **Local git hooks are installed and their manager is on `PATH`** —
      `ls "$(git rev-parse --git-dir)/hooks/" | grep -v '\.sample$'` lists something,
      and the manager the repo declares resolves. Hooks live in `.git/hooks`, which
      is **per-worktree and untracked**, so a fresh worktree inherits none of them.
```

The clause about *why* is load-bearing. An item reading only "install hooks" is setup advice a session skips; the reason is what makes it a warning.

**Step 0 — the host-provisioned stand-down carves the item out** instead of dismissing the checklist wholesale. Hosts provision tracked files plus dependencies, not hooks, so the stand-down path is where the gap is likeliest.

**Step 6 — a verification claim names its instrument.** A pinned tool's row carries the version it ran, and the notes state once whether local gates were active:

**Before**

| Command | Exit | Tier |
|---|---|---|
| `shellcheck scripts/*.sh` | 0 | 2 |

**After**

| Command | Exit | Tier |
|---|---|---|
| `shellcheck --version` → `0.9.0` (matches `.shellcheck-version`); `shellcheck scripts/*.sh` | 0 | 2 |

A branch whose hooks never ran is not disqualified — it is *differently evidenced*, and the reviewer has to be able to tell which they are reading.

## Prevention

**Code-level.** `scripts/test-absent-local-gate-tells.sh`, wired into `lefthook.yml` and `.github/workflows/validate-skills.yml`. It extracts the Step 0 checklist by range (so a `hook` mention elsewhere in a 900-line file cannot launder the item), requires the per-worktree/untracked clause, requires the stand-down to name the exception, and requires Step 6 to demand both the version and the gates-ran statement. Every live check concludes from an absent result, which is the shape that reports green when the reader breaks — so both readers are fixture-tested in both directions, per `../testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md`.

Considered and rejected: a check that fails when `.git/hooks` is empty. It cannot live in CI (runners have no hooks, so it would be permanently red) and cannot live in a hook (that is the absence). The detector would need the property it is detecting.

**Process-level.** When a repo pins a tool version, a claim about that tool without the version is not a verification claim. `/pre-merge` already refuses hedged findings that turn on library semantics without a `.d.ts` citation; this is the same rule pointed at the reviewer's own instruments.

## Planning / Calibration Notes

- **What widened the work:** the review rounds this caused. Two of the four first-round Concerns — the CI-red shellcheck line and a silent `set -euo pipefail` abort — are precisely what pre-commit and pre-push would have caught at the moment they were written, for free. Instead they cost a full delegated review round plus a fix round.
- **What tightened the work:** delegating review to a fresh context. The absence was invisible from inside the session that had it; a sub-agent ran CI's pinned shellcheck in Docker and got a different answer in one step.
- **Future planning adjustment:** when `/execute` Step 0 stands down on a host-provisioned workspace, budget one command to confirm hooks. When it does not, treat "the repo has pre-commit checks" as unverified until observed producing output.

## Actuals Worth Reusing

- **Comparable future work:** any first branch in a new workspace on a repo with a hook manager — which, for an agent, is most branches.
- **Reusable baseline:** the check is one command and the failure costs a review round. `ls "$(git rev-parse --git-dir)/hooks/"` before the first commit.

## Defect Classification

**Origin phase:** Specification error — `/execute` Step 0 specified worktree setup and omitted the one component that is per-worktree and untracked by construction.
**Fix type:** Correction for the tells (the checklist item and the version rule are in place and pinned). **Workaround for the underlying condition** — hooks still require manual installation, and a session that ignores the checklist item is in exactly the old position. No local mechanism can close that; see Prevention.

## Key Decision

**Decision:** Two tells in `/execute` plus a contract test, rather than a check that detects missing hooks.

**Rationale:** the detector would need to run in the place it is detecting the absence of. CI cannot see local hooks and a hook cannot report that hooks are absent, so the only surfaces that work are the agent's procedure and the artifact the reviewer reads.

**Alternatives considered:** committing hooks via `core.hooksPath` to a tracked directory — genuinely closes it, and rejected here because it changes how every contributor's git behaves and deserves its own proposal rather than riding a landing-page PR. Recorded as the real fix if this recurs.

**Revisable:** Yes. If it recurs with the checklist item in place, the item is not the mechanism and `core.hooksPath` is next.

## Related

- PR #278 — the branch that produced this, and whose review notes carried the false claim
- PR #271 / `scripts/check-shellcheck-version.sh` — the warner this incident bypassed by not running it
- `../testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md` — inverted axis; see Rule Scope
- `../architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md` — mirror shape; see Rule Scope

## Shelf Life

Retire when `core.hooksPath` points at a tracked directory in this repo, or when the hook manager stops requiring per-clone installation. Until then the condition is a property of git, not of any version — **evergreen**.
