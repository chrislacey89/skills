---
name: init-pipeline
description: "Infrastructure skill for scaffolding pipeline enforcement into a project. Sets up Claude Code hooks (TDD classification gate, git guardrails, optional quality gate), pre-commit hooks (detects existing tools, defaults to Lefthook + Biome + pnpm if none found). Run once per project, auto-invoked by /execute if hooks are missing."
---

# Init Pipeline

Scaffold pipeline enforcement infrastructure into the current project: Claude Code hooks for skill compliance, git guardrails for safety, and pre-commit hooks for code quality. Detects existing tools before suggesting defaults.

## When to use

- Automatically invoked by `/execute` Step 0 if `.claude/hooks/enforce-classification.sh` is missing
- Manually by the user when setting up a new project for pipeline work

## What it sets up

All files are created in the **target project**, not in the Skill Kit repo.

### 1. Git guardrails (Claude Code hook)

Invoke `/git-guardrails-claude-code` with project scope.

This installs a PreToolUse hook on Bash that blocks destructive git commands — force pushes, hard resets, forced cleans, force branch deletes, and whole-tree checkout/restore. The authoritative list lives in `/git-guardrails-claude-code`'s "What Gets Blocked" and "What Stays Allowed" sections; read it there rather than here.

The list is deliberately not restated in this file. It was, and the copy was wrong: it claimed plain `git push` was blocked, which it never has been. That is the same defect as #227 — documentation asserting coverage the matcher does not have — and a second copy is a second thing to keep true, in the file more downstream projects actually read.

### 2. TDD classification gate (Claude Code hook)

Create `.claude/hooks/enforce-classification.sh` and make it executable. This blocks Write/Edit to implementation files unless the `/execute` Step 3 classification gate has been passed.

The hook checks for either `.claude/.tdd-active` (TDD invoked) or `.claude/.tdd-skipped` (visual frontend, explicitly opted out). No path checking beyond the trigger surface — it enforces "did you go through the gate?"

It carries a second clause on the same trigger surface: the **post-review edit lock**, which refuses an implementation write while `.claude/.review-stamped` exists and `.claude/.fix-findings-active` does not. The first clause asks "was this work classified?"; the second asks "is this edit landing after a review, authored by the session the review went around?" Both are one script because both key off the same file-pattern decision.

**The two clauses are ordered, not independent — read the `.review-stamped` term in the first one before editing either.** The classification clause stands down on a stamped branch, so the post-review clause is the only one that decides there. This is not a stylistic preference: `/execute` Step 6 removes `.claude/.tdd-active` and `.claude/.tdd-skipped` *before* it hands off to `/pre-merge`, so a stamped branch never carries a classification marker. Two independent clauses in this order therefore never reach the second one — the `/fix-findings` fixer is refused despite holding the flag written for it, and the authoring session is refused by the wrong clause, told to invoke `/tdd` and never told that `/fix-findings` is the route. A lock whose designed affordance never prints is a lock nobody can use, and it was described here as "independent" while behaving this way. `scripts/test-post-review-edit-lock.sh` now drives `/execute` Step 6's removal as part of the round trip, so the ordering is measured rather than asserted.

**Install-time: ask which file patterns constitute implementation code.** Before scaffolding the hook, present the user with the default include list and ask:

> "The TDD classification gate fires on Write/Edit of files matching a pattern list. Default: `*.ts, *.tsx, *.astro, *.py, *.go, *.rb, *.java, *.rs, *.js, *.jsx, *.vue, *.svelte`. Over-gating is acceptable — classification is a quick decision at the top of /execute, though backend/behavior-heavy matches will trigger a full /tdd cycle. Accept the default, or customize for this project?"

Use the confirmed list (default or customized) to populate the `IMPL_PATTERNS` array in the hook body below. Over-gating is acceptable — the cost of an extra classification prompt is lower than the cost of silent under-fire on a polyglot project. If `/init-pipeline` is running non-interactively (auto-invoked by `/execute` Step 0), accept the default list and record that fact in the hook body via a leading comment.

**Skip logic stays extension-agnostic.** Tests, type declarations, and config files are detected by path substring (`*test*`, `*spec*`, `.d.ts`, `.config.*`) rather than per-language expansion.

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Implementation patterns — populated at install time from the user's answer to
# the /init-pipeline trigger-surface question. Over-gating is intended.
IMPL_PATTERNS=("*.ts" "*.tsx" "*.astro" "*.py" "*.go" "*.rb" "*.java" "*.rs" "*.js" "*.jsx" "*.vue" "*.svelte")

MATCHED=0
for pattern in "${IMPL_PATTERNS[@]}"; do
  if [[ "$FILE_PATH" == $pattern ]]; then MATCHED=1; break; fi
done
if [ $MATCHED -eq 0 ]; then exit 0; fi

# Skip test files and type declarations (extension-agnostic)
if [[ "$FILE_PATH" == *test* || "$FILE_PATH" == *spec* || "$FILE_PATH" == *.d.ts ]]; then
  exit 0
fi
# Skip config files (drizzle.config, vite.config, etc.)
if [[ "$FILE_PATH" == *.config.* ]]; then
  exit 0
fi
# Check for classification markers — but stand down on a stamped branch, so the
# post-review clause below is the one that decides there. /execute Step 6 removes
# BOTH classification markers before it hands off to /pre-merge, so by the time
# .review-stamped exists there is never a marker left for this test to find.
# Without the .review-stamped term, this clause short-circuits every post-review
# write: the /fix-findings fixer is refused outright, and the authoring session is
# refused by the wrong clause, under a message that names /tdd and never names the
# route the lock was built to offer.
if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.review-stamped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-active" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-skipped" ]; then
  echo '{"decision":"block","reason":"BLOCKED: classify work in /execute Step 3 before writing implementation files. Either invoke /tdd (backend/behavior-heavy) or create .claude/.tdd-skipped (visual frontend)."}' >&2
  exit 2
fi
# Post-review edit lock. /pre-merge Phase 4 touches .review-stamped beside the
# review-currency stamp; /fix-findings touches .fix-findings-active when it
# loads and removes it when it reports. Between those two, an implementation
# edit is a post-review fix authored by the session the review just went around.
if [ -f "$CLAUDE_PROJECT_DIR/.claude/.review-stamped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.fix-findings-active" ]; then
  echo '{"decision":"block","reason":"BLOCKED: this branch has been reviewed and stamped. A post-review fix needs an independent author. Either invoke /fix-findings <numbers>, or delete .claude/.review-stamped to take the edit yourself."}' >&2
  exit 2
fi
exit 0
```

**The lock's two exits are both deliberate acts.** Invoking `/fix-findings`
routes the edit to a sub-agent that did not write the code; deleting
`.claude/.review-stamped` by hand takes the edit anyway. Today that second choice
is made silently and invisibly — this clause does not remove it, it makes it
visible.

**What the clause deliberately does not cover.** It reuses the `IMPL_PATTERNS`
list and the `*test*` / `*spec*` / `*.d.ts` / `*.config.*` skip logic above,
unchanged, so a post-review edit to a test file, a type declaration, a config
file, or anything outside the pattern list is **not** refused. That is the same
trigger surface the classification gate already uses, and giving the two clauses
different definitions of "implementation file" would make the hook's behavior
unreadable from its own source. A re-run of `/pre-merge`, not this hook, covers
a post-review edit to a test.

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
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/enforce-classification.sh"
          }
        ]
      },
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

**Recommended Lefthook + Biome config** (when both are confirmed):

```yaml
# Pre-push hook for vitest run should be added after test suite stabilizes.
pre-commit:
  commands:
    check:
      glob: "*.{js,ts,cjs,mjs,d.cts,d.mts,jsx,tsx,json,jsonc}"
      run: pnpm biome check --write --no-errors-on-unmatched --files-ignore-unknown=true --colors=off {staged_files}
      stage_fixed: true
```

Key flags: `--no-errors-on-unmatched` prevents false failures when no staged files match, `--files-ignore-unknown=true` avoids Biome choking on unsupported files, `--colors=off` gives cleaner hook output. Skip typecheck in pre-commit (too slow) — add it as a pre-push hook later.

**Package manager enforcement:** If the confirmed package manager is pnpm (detected or chosen), add the `only-allow` guard:

```json
{
  "scripts": {
    "preinstall": "npx only-allow pnpm"
  }
}
```

For npm or yarn, skip this step — `only-allow` is only needed when enforcing pnpm specifically.

### 5. Quality gate (Claude Code hook — optional)

Ask the user: "Do you want a quality gate hook that runs feedback loops during editing? This catches issues while Claude works, not just at commit time."

If yes, create `.claude/hooks/quality-gate.sh` and make it executable. This runs as a **PostToolUse** hook on `Write|Edit`, providing immediate feedback after each file change. The first thing it does is anchor to `$CLAUDE_PROJECT_DIR` and no-op if that directory is gone — a hook firing from a worktree that was just torn down (e.g. during `/closeout`) must not emit false `MODULE_NOT_FOUND` errors from a vanished `node_modules`.

**Detect available feedback loops first.** Check `package.json` scripts for `check`/`lint`, `tsc`/`typecheck`, and `test`/`vitest`. Only include loops that actually exist.

```bash
#!/bin/bash
# Quality gate — runs after each Write/Edit to catch issues early.
# Only runs on TypeScript/JavaScript files. Skips test/config files.

# Anchor to the project root before running any feedback loop. If the
# directory is gone — e.g. a worktree was removed out from under the
# shell during /closeout teardown — no-op instead of emitting false
# MODULE_NOT_FOUND errors from a vanished node_modules. A stranded cwd
# must never masquerade as a lint/type failure.
if [ -z "$CLAUDE_PROJECT_DIR" ] || [ ! -d "$CLAUDE_PROJECT_DIR" ]; then
  exit 0
fi
cd "$CLAUDE_PROJECT_DIR" || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only gate TypeScript/JavaScript implementation files
if [[ ! "$FILE_PATH" == *.ts && ! "$FILE_PATH" == *.tsx && ! "$FILE_PATH" == *.js && ! "$FILE_PATH" == *.jsx ]]; then
  exit 0
fi
# Skip test files, type declarations, config files
if [[ "$FILE_PATH" == *test* || "$FILE_PATH" == *spec* || "$FILE_PATH" == *.d.ts || "$FILE_PATH" == *.config.* ]]; then
  exit 0
fi

# 1. Biome check (fast — format + lint)
BIOME_OUTPUT=$(pnpm biome check src/ 2>&1)
BIOME_EXIT=$?

# 2. TypeScript type check
TSC_OUTPUT=$(pnpm tsc --noEmit 2>&1)
TSC_EXIT=$?

if [ $BIOME_EXIT -ne 0 ] || [ $TSC_EXIT -ne 0 ]; then
  if [ $BIOME_EXIT -ne 0 ]; then
    echo "Biome errors found:" >&2
    echo "$BIOME_OUTPUT" >&2
    echo "" >&2
  fi
  if [ $TSC_EXIT -ne 0 ]; then
    echo "TypeScript errors found:" >&2
    echo "$TSC_OUTPUT" >&2
  fi
  exit 2
fi

# 3. Run tests for changed files only (vitest import graph analysis)
VITEST_OUTPUT=$(pnpm vitest run --changed 2>&1)
VITEST_EXIT=$?

if [ $VITEST_EXIT -ne 0 ]; then
  echo "Tests failed for changed files:" >&2
  echo "$VITEST_OUTPUT" >&2
  exit 2
fi

exit 0
```

**Project-specific extensions:** If the project has domain-specific smoke tests (e.g., RAG agent tests, API health checks), append them after the generic checks. Use `git diff --name-only HEAD` to scope them to relevant directories.

After writing, run: `chmod +x .claude/hooks/quality-gate.sh`

Add the PostToolUse hook to `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/quality-gate.sh"
          }
        ]
      }
    ]
  }
}
```

Merge into existing settings — do not overwrite.

### 6. `.gitignore` additions

Append these lines if not already present:

```
.claude/.tdd-active
.claude/.tdd-skipped
.claude/.ralph-checked
.claude/.review-stamped
.claude/.fix-findings-active
```

`.claude/.ralph-checked` is reserved here but created by `/setup-ralph-loop`, which is auto-invoked by `/execute` when a multi-slice task needs AFK bounds or may be run manually. `/init-pipeline` does not create the marker itself.

`.claude/.review-stamped` and `.claude/.fix-findings-active` are the post-review edit lock's two flags, also reserved here rather than created: `/pre-merge` Phase 4 writes the first beside the review-currency stamp and `/closeout` removes it at merge; `/fix-findings` writes the second when it loads and removes it when it reports. Both are transient, and a committed one would hold the lock open or shut across every future branch.

### 7. Worktree provisioning mode (optional)

`/execute` Step 0 and `/closeout` consult an optional `.claude/settings.json` key, `worktree.provisioning`, to decide whether the *pipeline* owns worktree provisioning and teardown or whether the *host* environment does. It mirrors the existing `research.storage` precedent — a single, in-repo, authoritative representation of an environment fact (Hunt/Thomas, DRY) rather than env-sniffing scattered across skills.

- `"auto"` (default when the key is absent) — `/execute` stands down if a host env var is present (`CONDUCTOR_WORKSPACE_PATH`, `CODESPACES`, `REMOTE_CONTAINERS`) or the current tree is not the repo's primary working tree; otherwise it provisions via worktrunk or plain git.
- `"host"` — isolation is always host-owned. `/execute` works in place; `/closeout` merges but cedes worktree teardown and branch pruning to the host.
- `"pipeline"` — the pipeline always provisions and tears down (the pre-host behavior).

```json
{
  "worktree": {
    "provisioning": "host"
  }
}
```

**Scaffold `host` when running inside a host environment.** If `/init-pipeline` runs while a host env var is set, write `worktree.provisioning: "host"` explicitly — the env var that disambiguates is available at scaffold time, and an explicit setting is more robust than re-deriving it on every `/execute`:

```bash
if [ -n "$CONDUCTOR_WORKSPACE_PATH" ] || [ -n "$CODESPACES" ] || [ -n "$REMOTE_CONTAINERS" ]; then
  : # merge {"worktree":{"provisioning":"host"}} into .claude/settings.json
fi
```

Merge into existing settings — do not overwrite. When no host env var is present, leave the key unset (`auto` is the safe default for un-hosted repos, where the pipeline should provision).

## Verification

Before considering setup complete, check:

- [ ] `.claude/hooks/enforce-classification.sh` exists and is executable
- [ ] Hook's `IMPL_PATTERNS` array matches the project's implementation surface as confirmed during install (default list or customized answer)
- [ ] `.claude/hooks/block-dangerous-git.sh` exists and is executable
- [ ] `.claude/settings.json` has both PreToolUse hooks configured
- [ ] If quality gate accepted: `.claude/hooks/quality-gate.sh` exists, is executable, and PostToolUse hook is in settings
- [ ] Hook manager config exists (e.g. `lefthook.yml`)
- [ ] Pre-commit hooks run successfully
- [ ] `.gitignore` has marker entries
- [ ] If running inside a host environment (Conductor/Codespaces/devcontainer), `.claude/settings.json` has `worktree.provisioning: "host"`; otherwise the key is left unset (`auto`)
- [ ] No existing project settings were overwritten

## Handoff

- **Expected input:** any project that will use `/execute`
- **Produces:** complete enforcement infrastructure — Claude Code hooks, git guardrails, pre-commit hooks using detected or user-confirmed tools
- **Auto-invoked by:** `/execute` Step 0 when `.claude/hooks/enforce-classification.sh` is missing
- **Invokes:** `/git-guardrails-claude-code` (project scope), `/setup-pre-commit`
- **Supports downstream:** `/tdd` (marker creation), `/execute` (marker cleanup); reserves `.claude/.ralph-checked` for `/setup-ralph-loop`, which creates the marker itself (auto-invoked by `/execute` for multi-slice work, or run manually); reserves `.claude/.review-stamped` and `.claude/.fix-findings-active` for the post-review edit lock, written by `/pre-merge` Phase 4 and `/fix-findings` respectively
