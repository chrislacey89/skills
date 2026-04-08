---
name: init-pipeline
description: "Infrastructure skill for scaffolding pipeline enforcement into a project. Sets up Claude Code hooks (TDD classification gate, git guardrails) and pre-commit hooks (detects existing tools, defaults to Lefthook + Biome + pnpm if none found). Run once per project, auto-invoked by /execute if hooks are missing."
---

# Init Pipeline

Scaffold pipeline enforcement infrastructure into the current project: Claude Code hooks for skill compliance, git guardrails for safety, and pre-commit hooks for code quality. Detects existing tools before suggesting defaults.

## When to use

- Automatically invoked by `/execute` Step 0 if `.claude/hooks/enforce-classification.sh` is missing
- Manually by the user when setting up a new project for pipeline work

## What it sets up

All files are created in the **target project**, not in the skills repo.

### 1. Git guardrails (Claude Code hook)

Invoke `/git-guardrails-claude-code` with project scope.

This blocks dangerous git commands (`git push`, `git reset --hard`, `git clean -f`, `git branch -D`, `git checkout .`, `git restore .`) via a PreToolUse hook on Bash.

### 2. TDD classification gate (Claude Code hook)

Create `.claude/hooks/enforce-classification.sh` and make it executable. This blocks Write/Edit to `.ts`/`.tsx` implementation files unless the `/execute` Step 3 classification gate has been passed.

The hook checks for either `.claude/.tdd-active` (TDD invoked) or `.claude/.tdd-skipped` (visual frontend, explicitly opted out). No path checking — it enforces "did you go through the gate?"

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only enforce for TypeScript files (not test files, not type declarations, not config)
if [[ "$FILE_PATH" == *.ts || "$FILE_PATH" == *.tsx ]]; then
  # Skip test files and type declarations
  if [[ "$FILE_PATH" == *test* || "$FILE_PATH" == *spec* || "$FILE_PATH" == *.d.ts ]]; then
    exit 0
  fi
  # Skip config files (drizzle.config, vite.config, etc.)
  if [[ "$FILE_PATH" == *.config.* ]]; then
    exit 0
  fi
  # Check for classification markers
  if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-active" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-skipped" ]; then
    echo '{"decision":"block","reason":"BLOCKED: classify work in /execute Step 3 before writing implementation files. Either invoke /tdd (backend/behavior-heavy) or create .claude/.tdd-skipped (visual frontend)."}' >&2
    exit 2
  fi
fi
exit 0
```

After writing, run: `chmod +x .claude/hooks/enforce-classification.sh`

### 3. Claude Code settings

Create or merge `.claude/settings.json` with both hooks:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/enforce-classification.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If `.claude/settings.json` already exists, merge the `hooks.PreToolUse` entries — do not overwrite existing settings.

### 4. Pre-commit hooks and package manager enforcement

**Detect before suggesting.** Before invoking any setup, check what the project already uses:

```bash
# Package manager — check lockfiles
ls pnpm-lock.yaml package-lock.json yarn.lock bun.lockb 2>/dev/null

# Formatter/linter — check deps and configs
grep -E "biome|prettier|eslint|oxlint|dprint" package.json 2>/dev/null
ls biome.json biome.jsonc .prettierrc .prettierrc.* prettier.config.* .eslintrc* eslint.config.* 2>/dev/null

# Hook manager — check for existing setup
ls lefthook.yml .husky 2>/dev/null
```

**Present findings to the user and ask for confirmation:**

- If a formatter/linter is detected → "Found [tool]. I'll use it for pre-commit hooks."
- If none detected → "No formatter/linter found. I'd suggest Biome (handles both formatting and linting, fast, zero-config). Want Biome, or something else?"
- If a hook manager is detected → "Found [Lefthook/Husky]. I'll use it." (Suggest migrating Husky to Lefthook if Husky is found.)
- If none detected → "No hook manager found. I'd suggest Lefthook. OK?"
- If a package manager lockfile is detected → use that package manager
- If none detected → "No lockfile found. I'd suggest pnpm. OK?"

**After user confirms**, invoke `/setup-pre-commit` with the confirmed tools.

**Package manager enforcement:** If the confirmed package manager is pnpm (detected or chosen), add the `only-allow` guard:

```json
{
  "scripts": {
    "preinstall": "npx only-allow pnpm"
  }
}
```

For npm or yarn, skip this step — `only-allow` is only needed when enforcing pnpm specifically.

### 5. `.gitignore` additions

Append these lines if not already present:

```
.claude/.tdd-active
.claude/.tdd-skipped
.claude/.ralph-checked
```

## Verification

Before considering setup complete, check:

- [ ] `.claude/hooks/enforce-classification.sh` exists and is executable
- [ ] `.claude/hooks/block-dangerous-git.sh` exists and is executable
- [ ] `.claude/settings.json` has both PreToolUse hooks configured
- [ ] Hook manager config exists (e.g. `lefthook.yml`)
- [ ] Pre-commit hooks run successfully
- [ ] `.gitignore` has marker entries
- [ ] No existing project settings were overwritten

## Handoff

- **Expected input:** any project that will use `/execute`
- **Produces:** complete enforcement infrastructure — Claude Code hooks, git guardrails, pre-commit hooks using detected or user-confirmed tools
- **Auto-invoked by:** `/execute` Step 0 when `.claude/hooks/enforce-classification.sh` is missing
- **Invokes:** `/git-guardrails-claude-code` (project scope), `/setup-pre-commit`
- **Supports downstream:** `/tdd` (marker creation), `/execute` (marker cleanup), `/setup-ralph-loop` (marker creation)
