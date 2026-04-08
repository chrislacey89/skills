---
name: setup-ralph-loop
description: "Infrastructure skill for setting up Ralph loop scripts for Claude-driven AFK execution. Use when a repo wants a HITL-to-AFK runner around /execute with bounded iterations, GitHub-native durable state, and explicit feedback loops. Not a normal feature-delivery stage; it prepares the repo for safer autonomous execution."
---

# Setup Ralph Loop

Create the local scripts and repo conventions needed to run Ralph safely.

## Invocation Position

This is an infrastructure skill, not a normal feature-delivery stage.

Use `/setup-ralph-loop` when a project wants to run `/execute` in a repeatable HITL-to-AFK loop.

**Auto-invocation:** `/execute` automatically invokes this skill when it detects multi-slice GitHub-issue work (PRD, big-batch appetite, or multiple user stories) and no `ralph-once.sh` or `ralph.sh` exists in the repo root. This means the skill may be entered without the user explicitly calling it — the detection and invocation happen as a prerequisite step inside `/execute`.

Do not use it as part of the default feature pipeline. It prepares the repo so later `/execute` execution can run under Ralph with bounded iterations, explicit feedback loops, and durable GitHub-backed state.

## What This Sets Up

- **`ralph-once.sh`** for one-iteration HITL Ralph
- **`ralph.sh`** for bounded AFK Ralph runs
- **Optional package.json scripts** for convenient invocation
- **Repo-local loop prompts** that tell Ralph to prefer the highest-risk unblocked slice, run feedback loops, and stop when work is done

## Rules Before Setup

- Ralph is an execution mode for `/execute`, not a separate workflow.
- Start with HITL Ralph first. Only go AFK after the prompt, feedback loops, and quality bar are behaving well.
- Ralph's durable progress state in this workflow lives in GitHub issues, issue comments, and commits — not in `progress.txt` or other local task-state files.
- Each iteration should implement exactly one reviewable slice.
- Every AFK loop must be bounded. Do not generate an infinite loop.

## Steps

### 1. Confirm task source and state model

Ask where Ralph should read work from.

Prefer this order:

1. GitHub issues with dependency relationships
2. Another durable backlog system the repo actually uses
3. A temporary fallback file only if the user explicitly wants it

If the repo uses GitHub issues, keep Ralph GitHub-native:

- open PRD issues define the end state
- slice issues define the current work queue
- issue comments carry exact errors or partial-progress context
- commits are the execution log

Do not introduce `progress.txt` as durable state unless the user explicitly chooses to deviate from the repo's GitHub-first model.

### 2. Detect feedback loops

Inspect the target repo before generating scripts.

Check for available commands in `package.json` or equivalent tooling:

- `typecheck`
- `test`
- `lint`
- `build`

Also note whether the repo already has:

- `/setup-pre-commit`
- container or sandbox tooling
- GitHub CLI configured

The generated Ralph prompt should only name feedback loops that actually exist.

### 3. Detect execution environment

Ask whether Ralph should run:

- in the current repo shell
- in a sandboxed shell or container
- through an existing task runner such as `pnpm`

Default recommendation:

- HITL first in the current repo
- AFK in a sandboxed or isolated environment when possible

### 4. Generate `ralph-once.sh`

Create a one-iteration script for supervised use first.

The script should:

- run exactly one Ralph iteration
- point Ralph at the task source
- tell Ralph to pick the highest-risk unblocked slice, not just the first issue
- tell Ralph to use `/execute`
- tell Ralph to run the repo's real feedback loops
- tell Ralph to stop after one reviewable slice

Suggested shape:

```bash
#!/bin/bash
set -e

claude --message "Look at the open GitHub issues. Pick the highest-risk unblocked issue that still needs implementation, respecting blocking relationships. Use /execute to implement exactly one reviewable slice. Run the repo's feedback loops. If all issue work is complete, say DONE and stop."
```

Adapt the prompt to the actual task source and available commands.

### 5. Generate `ralph.sh`

Create a bounded AFK loop.

The script must:

- require an iteration count argument
- fail fast if no argument is given
- run one iteration per loop
- avoid `while true`
- keep the same task-picking logic as `ralph-once.sh`

Suggested shape:

```bash
#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

for ((iteration=1; iteration<=$1; iteration++)); do
  claude --message "Look at the open GitHub issues. Pick the highest-risk unblocked issue that still needs implementation, respecting blocking relationships. Use /execute to implement exactly one reviewable slice. Run the repo's feedback loops. If all issue work is complete, say DONE and stop."

  echo "Ralph iteration $iteration complete."
done
```

If the user wants, also add convenience scripts to `package.json`, for example:

```json
{
  "scripts": {
    "ralph:once": "./ralph-once.sh",
    "ralph": "./ralph.sh 5"
  }
}
```

Use a small default iteration count if adding a package script.

### 6. Encode the quality bar explicitly

Make sure the generated loop prompt states the repo's quality expectations clearly.

The prompt should say Ralph must:

- implement one reviewable slice at a time
- run feedback loops each iteration
- avoid silent scope changes
- prefer risky slices early when unblocked
- leave exact error output in issue comments when blocked
- stop and escalate after repeated failure instead of retrying forever

If the repo is clearly long-lived production code, say so explicitly in the prompt.

### 7. Verify the generated setup

Check:

- `ralph-once.sh` exists and is executable
- `ralph.sh` exists and is executable
- package.json scripts were added correctly, if requested
- the generated prompt references the real task source
- the generated prompt references only real feedback loops
- no `progress.txt` was introduced unless the user explicitly asked for it

**On completion:** Create the Ralph marker so enforcement hooks know setup was done.

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude" && touch "$CLAUDE_PROJECT_DIR/.claude/.ralph-checked"
```

### 8. Recommend first usage

Instruct the user to:

1. run `./ralph-once.sh` first
2. review the result
3. refine the prompt if task selection or quality is off
4. only then run bounded AFK Ralph such as `./ralph.sh 5`

## Verification

Before considering setup complete, check:

- [ ] Ralph has a HITL entrypoint
- [ ] Ralph has a bounded AFK entrypoint
- [ ] The AFK loop does not run infinitely
- [ ] Task selection is risk-first, not just list-order-first
- [ ] The prompt uses `/execute`
- [ ] The prompt names real feedback loops from the repo
- [ ] Durable state remains GitHub-native unless the user explicitly chose otherwise

## Handoff

- **Expected input:** a repo that wants repeatable Ralph execution around `/execute`
- **Produces:** working Ralph loop scripts and repo-local conventions for HITL-first, bounded AFK execution
- **Supports downstream:** `/execute`, `/pre-merge`, and GitHub-issue-based execution by making AFK work safer and more repeatable
- **What comes next:** return to normal feature work, first by trying `ralph-once.sh`, then by using bounded AFK Ralph when the setup proves reliable
