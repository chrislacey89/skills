---
date: 2026-11-16
category: devops
problem_type: an inherited path variable trusted as naming the current checkout, guarded only against being unset
components: [pre-merge, execute, closeout, fix-findings, lfg, hackathon, setup-ralph-loop]
technologies: [bash, claude-code]
severity: medium
volatility: stable
paths: [pre-merge/SKILL.md, execute/SKILL.md, closeout/SKILL.md, fix-findings/SKILL.md, lfg/SKILL.md, hackathon/SKILL.md, setup-ralph-loop/SKILL.md]
replaces: []
related: [a-preset-variable-tests-a-path-no-run-takes-2026-10-26.md]
---

# `$CLAUDE_PROJECT_DIR` in a skill block can name another checkout

## Problem

`/pre-merge` Phase 4 writes the post-review lock to `"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.claude/.review-stamped"`. In a session where the shell's `CLAUDE_PROJECT_DIR` named a different repository, the lock went there, and the worktree under review was left unlocked. Nothing failed: the block exited 0, and nothing it printed names where the lock went.

## Context

The session was launched from this repo's main checkout and moved into a worktree with `EnterWorktree`. Its Bash environment carried `CLAUDE_PROJECT_DIR` set to a third checkout, a different project on the same machine. No shell startup file and no `settings.json` sets it, so the process inherited it. Where from is unverified. The stamp block's `touch` landed on that project's own `.review-stamped`, which already existed from a real review there, so the only change was its modified time. A file that had not existed would have been created, locking a branch in a project this session never touched.

## Symptoms

- The stamp block exits 0, nothing it prints names the lock path, and `ls .claude/` in the worktree shows no `.review-stamped` afterward.
- `echo "$CLAUDE_PROJECT_DIR"` and `git rev-parse --show-toplevel` disagree.

## Root Cause

`${VAR:-fallback}` covers an unset or empty variable. It does not cover a variable that is set to the wrong place. The skill blocks treat `CLAUDE_PROJECT_DIR` as a statement about the current tree. In a Bash-tool shell it is only an environment variable, and any parent process can have set it. The harness sets it for hooks it runs, but a skill's fenced block runs in the agent's shell, which inherits it.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** the misdirected write succeeds and the block exits cleanly, so the only feedback is a missing lock in the right place, and a missing lock looks exactly like a branch nobody edited after review.

## Rule Scope

- **Applies when:** a fenced skill block, run through the Bash tool, reads a path from an inherited environment variable and writes under it.
- **Inverts or does not apply when:** the harness itself sets the variable for the process reading it, as for a hook command in `settings.json`. There it is the harness's statement about the session's project.
- **Sibling docs:** the host-signal block in `/execute` Step 0 is the same pattern, already fixed for `CONDUCTOR_WORKSPACE_PATH`: it counts only when it contains the current toplevel (#378, pinned by `scripts/test-host-signal-containment.sh`).

## Solution

Here the lock was written by hand in the worktree, and the other project's file was left alone because it was older than this session.

The fix for the blocks is the containment rule #378 applied to `CONDUCTOR_WORKSPACE_PATH`: a path variable counts only when it describes the current tree. One thing has to be settled before the blocks change. The lock is read by the classification hook, which takes `CLAUDE_PROJECT_DIR` from the harness, not from the agent's shell, and what the harness sets it to in a worktree session is unverified. The writer and the reader have to name the same directory, so the fix starts by measuring that.

**Before:**
```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
```

The fallback guards only the unset case, and the wrong-value case is the one that happened.

## Prevention

**Code-level:** a contract test that fails on a skill block reading `CLAUDE_PROJECT_DIR` without that containment.

**Process-level:** recorded on chrislacey89/skills#693, which already asks for a measurement of `$CLAUDE_PROJECT_DIR` under `EnterWorktree` before the marker path changes. This is one such measurement, and a third value #693 does not list: set, and naming another project.

## Related

- PR #757, where this surfaced during `/pre-merge`
- #693, the marker path under `EnterWorktree` isolation
- #378, the same containment rule for `CONDUCTOR_WORKSPACE_PATH`
- `a-preset-variable-tests-a-path-no-run-takes-2026-10-26.md`, the lesson on preset variables, which this one qualifies for `CLAUDE_PROJECT_DIR`

## Shelf Life

When no skill block reads `CLAUDE_PROJECT_DIR`, or every one checks containment.
