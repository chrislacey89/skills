---
name: git-guardrails-claude-code
description: "Infrastructure safety skill for blocking dangerous git commands in Claude-driven workflows. Use when the repo or user environment needs guardrails against destructive git operations. Not a delivery-pipeline step; it makes later work safer."
---

# Setup Git Guardrails

Sets up a PreToolUse hook that intercepts and blocks dangerous git commands before Claude executes them.

## Invocation Position

This is an infrastructure safety skill, not a feature-delivery step.

Use `/git-guardrails-claude-code` when the project or user wants stronger protection against destructive git operations in Claude-driven workflows.

Do not treat it as part of the normal feature pipeline. It is a repo or user setup action that makes later work safer.

## What Gets Blocked

- `git push --force` / `git push -f` / `git push --force-with-lease`
- `git reset --hard`
- `git clean -f` / `git clean -fd` / `git clean -df` / `git clean -d -f`
- `git branch -D` / `git branch --delete --force` / `git branch -f -d`
- `git checkout .` / `git restore .` / `git checkout -- .` / `git restore -- .`

## What Stays Allowed

- `git push origin feature/my-branch`
- `git reset --soft HEAD~1`
- `git clean -n`
- `git branch -d merged-branch`
- `git checkout main`
- `git checkout .github/workflows/ci.yml`
- `git restore .gitignore`

Both lists are executable, not decorative. `scripts/test-git-guardrails.sh` extracts every command in them and runs it through the real script, asserting exit 2 for the first list and exit 0 for the second. Adding a line to either list without making the script agree fails CI.

That test exists because this section was wrong for an unknown period: it claimed `git push -f` was blocked when the matcher only ever saw the `--force` long form (#227). A guard's own documentation is the thing a user reads when deciding whether to install it, so an unchecked claim here is worse than no claim.

### How matching works

The script parses the command into arguments rather than searching it for substrings, so it sees past the surface forms a substring search misses:

- **Flag order and bundling** — `-fd`, `-df`, and `-d -f` are the same command.
- **Long and short forms** — `-D`, `--delete --force`, and `-f -d` are all force-deletes of a branch.
- **The `--` separator** — `git checkout -- .` is `git checkout .`.
- **Leading global options** — `git -C /some/path push -f` is still a force push.
- **A path is not a pathspec of `.`** — `git checkout .github/workflows/ci.yml` merely *starts* with a dot and is left alone.

Matching stays deliberately conservative in two ways. A `git` token is inspected wherever it appears in a segment, so wrappers like `sudo git push -f` and `bash -c "git push -f"` are still caught. And `--force-with-lease` is blocked alongside `--force`: it is the safer force push, but it still rewrites published history.

When blocked, Claude sees a message telling it that it does not have authority to access these commands.

## Steps

### 1. Ask scope

Ask the user: install for **this project only** (`.claude/settings.json`) or **all projects** (`~/.claude/settings.json`)?

### 2. Copy the hook script

The bundled script is at: [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh)

Copy it to the target location based on scope:

- **Project**: `.claude/hooks/block-dangerous-git.sh`
- **Global**: `~/.claude/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

### 3. Add hook to settings

Add to the appropriate settings file:

**Project** (`.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

**Global** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If the settings file already exists, merge the hook into existing `hooks.PreToolUse` array — don't overwrite other settings.

### 4. Ask about customization

Ask if user wants to add or remove any patterns from the blocked list. Edit the copied script accordingly.

### 5. Verify

Run a quick test:

```bash
# Should be BLOCKED (exit 2):
echo '{"tool_input":{"command":"git push --force origin main"}}' | <path-to-script>

# Should be ALLOWED (exit 0):
echo '{"tool_input":{"command":"git push origin feature/my-branch"}}' | <path-to-script>
```

The force-push command should exit with code 2 and print a BLOCKED message to stderr. The regular push should exit with code 0.

## Handoff

- **Expected input:** a project or user environment that needs stronger git safety controls
- **Produces:** installed guardrail hooks and safer Claude git behavior
- **Supports downstream:** all implementation and review work by reducing destructive-command risk
- **What comes next:** return to normal workflow with the guardrails in place
