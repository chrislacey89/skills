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

- `git push --force` (regular pushes are allowed; the `-f` short form is **not** matched — see the note below)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

When blocked, Claude sees a message telling it that it does not have authority to access these commands.

**Known gap — `git push -f` passes.** `DANGEROUS_PATTERNS` matches the literal string `push --force`, which the `-f` short form does not contain, so `git push -f origin main` exits 0. This is a real hole in the guard, not a documentation nuance; it is tracked separately rather than patched here so the fix lands with a test. Verified by execution, not by reading.

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
