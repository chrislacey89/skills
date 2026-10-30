---
name: init-pipeline
description: "Infrastructure skill for scaffolding pipeline enforcement into a project. Sets up Claude Code hooks (TDD classification gate, git guardrails, optional quality gate), pre-commit hooks (detects existing tools, defaults to Lefthook + Biome + pnpm if none found). Run when setting up a project for pipeline work, and again to re-scaffold a hook that predates the post-review edit lock or a classification marker; /execute Step 0 auto-invokes it when the hook is missing or stale."
---

# Init Pipeline

Scaffold pipeline enforcement infrastructure into the current project: Claude Code hooks for skill compliance, git guardrails for safety, and pre-commit hooks for code quality. Detects existing tools before suggesting defaults.

## When to use

- Automatically invoked by `/execute` Step 0 if `.claude/hooks/enforce-classification.sh` is missing, or if the installed hook does not read every path its own classification clause tests — the lock's stamp flag, or a marker such as `.claude/.lfg-active` (see § 2's re-scaffold note)
- Manually by the user when setting up a new project for pipeline work
- Manually by the user on a project that is already set up, to create its sidecar (§ 8), bring a hook body that reads every marker path up to the current text, or be offered the quality gate a Path B install never asked about — § 2's Path D

## What it sets up

All files are created in the **target project**, not in the Skill Kit repo — except § 8's sidecar, which lives outside both.

### 1. Git guardrails (Claude Code hook)

Invoke `/git-guardrails-claude-code` with project scope.

This installs a PreToolUse hook on Bash that blocks destructive git commands — force pushes, hard resets, forced cleans, force branch deletes, and whole-tree checkout/restore. The authoritative list lives in `/git-guardrails-claude-code`'s "What Gets Blocked" and "What Stays Allowed" sections; read it there rather than here.

The list is deliberately not restated in this file. It was, and the copy was wrong: it claimed plain `git push` was blocked, which it never has been. That is the same defect as chrislacey89/skills#227 — documentation asserting coverage the matcher does not have — and a second copy is a second thing to keep true, in the file more downstream projects actually read.

### 2. TDD classification gate (Claude Code hook)

Create `.claude/hooks/enforce-classification.sh` and make it executable. This blocks Write/Edit to implementation files unless the `/execute` Step 3 classification gate has been passed.

The hook checks for any of `.claude/.tdd-active` (TDD invoked), `.claude/.tdd-skipped` (visual frontend, explicitly opted out), or `.claude/.lfg-active` (`/lfg` proof-of-concept mode). No path checking beyond the trigger surface — it enforces "did you go through the gate?"

It carries a second clause on the same trigger surface: the **post-review edit lock**, which refuses an implementation write while `.claude/.review-stamped` exists and `.claude/.fix-findings-active` does not. The first clause asks "was this work classified?"; the second asks "is this edit landing after a review, authored by the session the review went around?" Both are one script because both key off the same file-pattern decision.

**The two clauses are ordered, not independent — read the `.review-stamped` term in the first one before editing either.** The classification clause stands down on a stamped branch, so the post-review clause is the only one that decides there. This is not a stylistic preference: `/execute` Step 6 removes `.claude/.tdd-active`, `.claude/.tdd-skipped`, and `.claude/.lfg-active` *before* it hands off to `/pre-merge`, so a stamped branch never carries a classification marker. Two independent clauses in this order therefore never reach the second one — the `/fix-findings` fixer is refused despite holding the flag written for it, and the authoring session is refused by the wrong clause, told to invoke `/tdd` and never told that `/fix-findings` is the route. A lock whose designed affordance never prints is a lock nobody can use, and it was described here as "independent" while behaving this way. `scripts/test-post-review-edit-lock.sh` now drives `/execute` Step 6's removal as part of the round trip, so the ordering is measured rather than asserted.

**Install-time: the run takes one of four paths, and at most one of them applies at a time.** Read `.claude/hooks/enforce-classification.sh` in the target project before writing anything. What is already installed there decides the path — not how this skill was invoked, because `/execute` Step 0 routes both of its verdicts (`hooks-absent` and `hooks-stale`) to the same auto-invocation. Two things the per-path rules below do key on: on a fresh install (Path A or B), whether a user is present to answer, which an HITL `/execute` session supplies and an AFK run does not; and on a hook that is already installed (Path C, Path D, and § 8's skip), whether a user typed `/init-pipeline` by hand or another skill auto-invoked it, because a user being present in the calling session does not turn an auto-invocation into a hand-run. Take no instruction from a path you are not on. The one handover between paths is Path C's, below: a hand-run that rewrites a stale hook has, by the end of that rewrite, the hook Path D is for.

**Path A — no hook installed, and a user is present** (a user ran `/init-pipeline` by hand, or is in the session that auto-invoked it, as in an HITL `/execute`). Present the default include list and ask:

> "The TDD classification gate fires on Write/Edit of files matching a pattern list. Default: `*.ts, *.tsx, *.astro, *.py, *.go, *.rb, *.java, *.rs, *.js, *.jsx, *.vue, *.svelte`. Over-gating is acceptable — classification is a quick decision at the top of /execute, though backend/behavior-heavy matches will trigger a full /tdd cycle. Accept the default, or customize for this project?"

Use the confirmed list (default or customized) to populate the `IMPL_PATTERNS` array in the hook body below. Over-gating is acceptable — the cost of an extra classification prompt is lower than the cost of silent under-fire on a polyglot project.

**Path B — no hook installed, and `/init-pipeline` is running non-interactively** (auto-invoked by `/execute` Step 0 on a project whose hooks gate reported `hooks-absent`, with nobody present to answer, as in an AFK Ralph iteration; or auto-invoked by `/lfg` Step 4, whose invocation declares nobody present to answer even though a user is in the session, and which puts the run here rather than on Path A). Do not ask. Populate `IMPL_PATTERNS` with the default list from Path A's question and record that fact in the hook body by putting this exact line directly above the `IMPL_PATTERNS` array: `# Path B: IMPL_PATTERNS is the default list; no user was present at install.` Path C carries it over with the array, and Path D reads it to learn that § 5 was never offered here.

**Path C — a hook is installed but does not read every path clause 1 tests, or lacks a `# gate:` sentinel** (`hooks-stale`: a project initialized before one of those paths or sentinels shipped — before the post-review edit lock, before `.claude/.lfg-active`, or before the project-scope clause). `/execute` Step 0 prints the terms it found missing on a `missing:` line on stderr, beside the verdict it prints on stdout; every one of them is a boundary this project's install predates, and this path's job is to bring the hook up to all of them at once rather than one boundary per run. The trigger-surface question was answered at that project's own install, so neither Path A's question nor Path B's default applies here — both belong to the fresh-install case, and reaching for either on this path is the one harm this path exists to prevent. Do not ask again, and do not silently re-default: carry the installed hook's `IMPL_PATTERNS` array — with the provenance comment above it — and its skip clauses over verbatim, because the project may have customized them at its own install time, and changing them changes the classification gate's behavior for work that has nothing to do with the lock. Replace everything from the installed hook's `# Check for classification markers` comment through its final `exit 0` with the marker-check clauses at the foot of the block below. On a pre-lock hook that is one clause replaced and one added, not two replaced, because such a hook carries the classification clause alone and the post-review clause is what the upgrade brings; on a hook that already has both, it is both replaced with current text. Either way the span is the same and the replacement is wholesale, so this path never has to know which boundary it is crossing — which is what lets one run fix a hook that is behind on several. Every `# gate: <name>` sentinel line in the block below sits inside that span, beside the clause it names, so the replacement installs the clause and its sentinel together and the next Step 0 run reports the hook current; `scripts/test-lfg-marker.sh` section 10 pins that placement.

**Path D — a hook that reads every path clause 1 tests and carries every `# gate:` sentinel is installed, and a user ran `/init-pipeline` by hand.** This is the hook `/execute` Step 0's gate reports `hooks-lock-present` for, so that gate never auto-invokes this skill here. The verdict is named for the terms it found, not for currency: a hook can read every path and still carry an older marker-check body, from a change that added no new path. So do not assume the hook is current. Compare its span from `# Check for classification markers` through its final `exit 0` with the same span in the block below. If they match, leave the hook as it is. If they differ, show the difference and offer Path C's replacement of that span, with replace recommended; carry `IMPL_PATTERNS`, its comment, and the skip clauses over verbatim exactly as Path C does. Ask none of Path A's questions: the trigger surface was settled at this project's install.

**No path — a hook that reads every path clause 1 tests is installed, and nobody is present.** Nothing in this skill applies: the hook needs no new path, and every section that could still do work here asks a human. Write nothing and report that. Callers are expected not to reach this case — `/execute` Step 0 does not invoke this skill on `hooks-lock-present`, and `/lfg` Step 4 skips the invocation on that verdict — so arriving here means a caller invoked it without running the gate first.

**The rest of the run, per path.** § 4 and § 5 are the two sections below that wait on a human — § 4 presents its detection findings and holds for a confirmation before invoking `/setup-pre-commit`, and § 5 asks whether to install the optional quality gate — and a run with nobody to ask cannot execute either. That is not hypothetical: `/execute` Step 0 sends both of its verdicts here and holds Step 1 until this skill reports, so a section waiting on an answer nobody is present to give stalls the caller rather than the callee, and an AFK Ralph iteration drives `claude --message` with no user at the keyboard at all. On **Path A**, run everything below, § 4, § 5 and § 8 included. On **Path B**, run § 3, § 6 and § 7; take § 4 without asking, applying what its detection block finds or the default it names when it finds nothing; and skip § 5, which is optional and whose unanswered default is no, and § 8, which creates nothing without a human to answer it. On **Path D**, run § 8, and run § 5 too when the hook carries Path B's exact line (as written in Path B, not the rewritten one § 5 leaves) above `IMPL_PATTERNS`: a Path B install skipped § 5 without ever asking, so its unanswered default was never an answer. Everything else this skill does was done at this project's install. § 8 is the one section a project set up before the sidecar existed has never run. On **Path C**, run § 3 (a merge, never an overwrite) and § 6 — whose `.gitignore` append is idempotent, and is the step that stops the lock's two flags from landing as committable untracked files in a repo that predates them — then stop: skip § 4, § 5, § 7 and § 8 outright, because this project answered them at its own install and a lock upgrade that re-opens a settled toolchain decision is doing something nothing asked it to do. That is the whole run when this skill was auto-invoked. When a user ran it by hand, the hook it just wrote reads every path, so the run continues as Path D — the span comparison then matches and is a no-op — and one hand-run gets a stale project both the upgrade and its sidecar. An auto-invoked Path C run that skips a section which never ran at that project says so in what it reports and leaves it; a later hand-run is Path D, which reaches § 8, and § 5 when the install was Path B and § 5 has not yet been answered (§ 5 retires Path B's line once it is). No path re-asks § 4 or § 7, or § 5 after an install that asked it: to change one of those answers, invoke `/setup-pre-commit` directly for § 4, or edit `.claude/settings.json` as § 5 or § 7 describes.

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
# Check for classification markers — on a file inside this project only. A
# Write to /tmp/scratch.ts or a sibling checkout is no business of either clause
# below, and refusing it sends the agent to /tdd, or to deleting .review-stamped,
# for a file the pipeline does not own. Both sides are resolved through `cd -P`
# first, the file through its nearest existing directory, so neither `..` nor a
# symlink carries a path across the boundary in either direction. A relative
# path is read against the project. The sentinel line below is how /execute
# Step 0 tells this clause apart from a hook that predates it.
# gate: project-scope
if [ -n "$CLAUDE_PROJECT_DIR" ]; then
  root=$(cd -P "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P)
  case "$FILE_PATH" in /*) path=$FILE_PATH ;; *) path="${CLAUDE_PROJECT_DIR%/}/$FILE_PATH" ;; esac
  dir=$(dirname "$path"); rest=$(basename "$path")
  while [ ! -d "$dir" ]; do rest="$(basename "$dir")/$rest"; dir=$(dirname "$dir"); done
  case "$(cd -P "$dir" && pwd -P)/$rest" in "${root%/}"/*) ;; *) exit 0 ;; esac
fi
# Stand down on a stamped branch, so the
# post-review clause below is the one that decides there. /execute Step 6 removes
# EVERY classification marker before it hands off to /pre-merge, so by the time
# .review-stamped exists there is never a marker left for this test to find.
# Without the .review-stamped term, this clause short-circuits every post-review
# write: the /fix-findings fixer is refused outright, and the authoring session is
# refused by the wrong clause, under a message that names /tdd and never names the
# route the lock was built to offer.
if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.review-stamped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-active" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-skipped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.lfg-active" ]; then
  echo '{"decision":"block","reason":"BLOCKED: classify work in /execute Step 3 before writing implementation files. Either invoke /tdd (backend/behavior-heavy), create .claude/.tdd-skipped (visual frontend), or invoke /lfg (proof-of-concept mode)."}' >&2
  exit 2
fi
# Post-review edit lock. /pre-merge Phase 4 touches .review-stamped beside the
# review-currency stamp; /fix-findings touches .fix-findings-active when it
# loads and removes it when it reports. Between those two, an implementation
# edit is a post-review fix authored by the session the review just went around.
if [ -f "$CLAUDE_PROJECT_DIR/.claude/.review-stamped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.fix-findings-active" ]; then
  echo '{"decision":"block","reason":"BLOCKED: this branch has been reviewed and stamped. A post-review fix needs an independent author. Ask the human which findings to fix and run /fix-findings with exactly the numbers they name (never numbers you chose), or delete .claude/.review-stamped to take the edit yourself."}' >&2
  exit 2
fi
exit 0
```

**The two routes the refusal names, and what the clause actually refuses.**
Invoking `/fix-findings` routes the edit to a sub-agent that did not write the
code; deleting `.claude/.review-stamped` by hand takes the edit anyway. That
second choice is made silently today, and printing it is what makes it visible.
It is not the only way out, and the difference matters at install time: the hook
is registered in § 3 below on `"matcher": "Write|Edit"`, so no `Bash` write is
ever presented to it — `sed -i`, `tee`, a heredoc, `printf >`, or `rm
.claude/.review-stamped` itself — and within Write/Edit it refuses only a path
that resolves inside `$CLAUDE_PROJECT_DIR`, matches `IMPL_PATTERNS`, and survives the skip logic, which leaves
`.claude/.fix-findings-active`, this hook script, and `.claude/settings.json`
all writable while the lock is armed, and leaves the model free to invoke
`/fix-findings` itself (it is model-invocable and its load-time marker opens the
lock), which is why the refusal sends it to the human for the numbers. Install it as a stop on the *default*
post-review edit, not as an enclosure around the branch.

**What the clause does not cover, in the matcher's terms rather than a file's
role.** It reuses the `IMPL_PATTERNS` list and the `*test*` / `*spec*` /
`*.d.ts` / `*.config.*` skip logic above, unchanged, and those patterns match a
*substring of the whole path*. Claude Code hands the hook an absolute path, so
the skips reach further than the file roles they were named for:
`src/latest-news.ts` and `src/respectful.ts` are skipped for containing `test`
and `spec`, so is anything under a `testimonials/` directory, so is
`src/app.config.local.ts`, and so is every file in a project checked out beneath
a path like `/Users/tester/`. Giving the two clauses different definitions of
"implementation file" would make the hook's behavior unreadable from its own
source, so the patterns stay — a re-run of `/pre-merge`, not this hook, covers
the edits they let through.

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

**Gated by § 2's rule for the rest of the run, per path — read it before asking anything here.**

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

The hook config itself, including every gate it scaffolds, is `/setup-pre-commit` Step 5's; do not write `lefthook.yml` here.

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

**Gated by § 2's rule for the rest of the run, per path — read it before asking anything here.**

Ask the user: "Do you want a quality gate hook that runs feedback loops during editing? This catches issues while Claude works, not just at commit time."

On Path D, once the user has answered — yes or no — rewrite Path B's line above `IMPL_PATTERNS` in the hook to this exact line, so the next hand-run no longer matches it and does not ask again: `# Path B: IMPL_PATTERNS is the default list; § 5 was offered at a later hand-run.` Change that one comment line only; the array and every other clause stay byte-identical, and a Path C re-scaffold carries the rewritten line over with the array like any other provenance comment.

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
.claude/.lfg-active
.claude/.ralph-checked
.claude/.review-stamped
.claude/.fix-findings-active
```

`.claude/.lfg-active` is the third classification marker the hook's first clause accepts, created by `/lfg` and removed by `/execute` Step 6 alongside the two `.tdd-*` markers. It is reserved here rather than created: `/init-pipeline` scaffolds the gate, never a classification.

`.claude/.ralph-checked` is reserved here but created by `/setup-ralph-loop`, which is auto-invoked by `/execute` when a multi-slice task needs AFK bounds or may be run manually. `/init-pipeline` does not create the marker itself.

`.claude/.review-stamped` and `.claude/.fix-findings-active` are the post-review edit lock's two flags, also reserved here rather than created: `/pre-merge` Phase 4 writes the first beside the review-currency stamp and `/closeout` removes it at merge; `/fix-findings` writes the second when it loads and removes it when it reports. Both are transient, and a committed one would hold the lock open or shut across every future branch.

### 7. Worktree provisioning mode (optional)

`/execute` Step 0 and `/closeout` consult an optional `.claude/settings.json` key, `worktree.provisioning`, to decide whether the *pipeline* owns worktree provisioning and teardown or whether the *host* environment does. It mirrors the existing `research.storage` precedent — a single, in-repo, authoritative representation of an environment fact (Hunt/Thomas, DRY) rather than env-sniffing scattered across skills.

- `"auto"` (default when the key is absent) — `/execute` stands down if a host env var describes the current tree (the block below) or the current tree is not the repo's primary working tree; otherwise it provisions via worktrunk or plain git.
- `"host"` — isolation is always host-owned. `/execute` works in place; `/closeout` merges but cedes worktree teardown and branch pruning to the host.
- `"pipeline"` — the pipeline always provisions and tears down (the pre-host behavior).

```json
{
  "worktree": {
    "provisioning": "host"
  }
}
```

**Do not scaffold this key — leave it unset.** Whether a tree is host-provisioned is a fact about the machine and the checkout, and `.claude/settings.json` is committed: a `"host"` written from one Conductor workspace travels to every other clone, including the maintainer's own plain checkout and other contributors', where `/execute` would then stand down permanently and `/closeout` would cede teardown to a host that is not there. `auto` re-derives the answer on every run from the tree it is standing in:

```bash
# host-signal: does a host env var describe THIS tree, not just this shell?
host_owned=no
top=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
if [ -n "${CONDUCTOR_WORKSPACE_PATH:-}" ]; then
  ws=$(cd "$CONDUCTOR_WORKSPACE_PATH" 2>/dev/null && pwd -P) || ws=
  if [ -n "$ws" ]; then
    case "$top/" in "$ws"/*) host_owned=yes ;; esac
  fi
fi
if [ -n "${CODESPACES:-}" ] || [ -n "${REMOTE_CONTAINERS:-}" ]; then host_owned=yes; fi
echo "host_owned=$host_owned"
```

The bare presence of a host env var does not answer the question: `CONDUCTOR_WORKSPACE_PATH` is inherited by any shell started under Conductor and can name a workspace of a different repository entirely, so it counts only when it contains the current toplevel. `"host"` and `"pipeline"` remain for a user who sets them by hand, knowing every clone of the repo shares the answer.

### 8. Sidecar (Path A and Path D only)

The sidecar is the project's private store outside its tree: `sidecar.json` (this project's pack configuration), the research archive, and solutions entries. [scripts/sidecar.sh](scripts/sidecar.sh) is the only thing that computes its path or commits to it; call it by its absolute installed path and never inline either. `/research`, `/compound`, and `/excavate` read it through their bundled copies.

**Path A or Path D (§ 2), the paths with a user present.** On Path B, and on a Path C run that was auto-invoked, skip this section: create no sidecar and ask nothing. A sidecar records two decisions only a human can make, and creating one is a human act. A run with nobody to ask that guesses them writes a store every later run trusts. The skills that read the sidecar print the resolver's `init` command on a miss, so skipping here strands nothing.

This section writes to the sidecar and never to the project. `.claude/settings.json` is byte-identical before and after it, and § 7's rule against scaffolding a machine fact into a committed file holds here too: the sidecar is per-machine and uncommitted to the project, which is why these answers live there.

**Resolve first.**

```bash
SC="<this skill's directory>/scripts/sidecar.sh"
bash "$SC" resolve
```

- **Hit** (exit 0, prints the sidecar path): show `mode` and `solutions` from its `sidecar.json` and offer to keep them; keep is the default. To change `mode`, run `bash "$SC" config set mode <owned|guest>`: `forge.write` is derived from `mode`, and the verb re-derives it and commits, where a hand edit would leave it stale. A key with no derived dependents (`solutions.*`) may be edited in `sidecar.json` and committed with `bash "$SC" commit -- sidecar.json -m "sidecar: <what changed>"`, except `solutions.related`, which `relate` writes (below), and `solutions.system`, which `config set system` writes and shape-checks (see Related projects below): a hand-set label that fails the check makes every sibling skip this repo silently. Do not run `init` again: it refuses a project that already has a sidecar.
- **Miss** (stderr carries a `SIDECAR MISS` line with an `init` command; exit 1 alone is not enough, because `resolve` also exits 1 outside a git repository and when it finds a sidecar but cannot commit a new alias, so on any other exit 1 stop and relay what it printed as printed, with no questions and no `init`): ask the three questions below, **one per turn**, each with the recommended answer first, then run `init`.

**Related projects.** When this repo is one of several that share code or infrastructure (services behind one gateway, a shared client library), offer once, after the sidecar exists, to set the group's label: `bash "$SC" config set system <label>`, one short `[a-z0-9._-]` name that every repo in the group sets to the same value. `/research`, `/write-a-prd`, and `/execute` then also search the lessons of every sidecar on this machine carrying that label and mark the hits; nothing writes to them. A label no other sidecar carries is written anyway and named on stderr with the labels in use: if that line shows a misspelling, set the label again. `bash "$SC" relate <path to the other checkout>` remains for a single link to a repo outside the group. Skip the offer for a standalone repo.

**Q1 — mode.** `owned` (your repository: the pack may write issues, labels, milestones, and PRs on its forge) or `guest` (someone else's, such as a client's: the pack writes nothing to its forge). The script derives the forge permissions from this answer; do not ask about them separately.

**Q2 — the repo's existing in-tree knowledge path.** Detect it, then show it for confirmation before anything is written.

```bash
ITP=none
for d in docs/solutions docs/adr docs/adrs docs/decisions; do
  if [ -d "$d" ]; then ITP="$d"; break; fi
done
echo "in_tree_path=$ITP"
```

Offer the detected value first. The user may replace it with any other path, or with `none`.

**Q3 — `solutions.write`**, where `/compound` puts a new lesson:

- `sidecar` — in the sidecar, committed there, never in the project's tree.
- `in-tree` — at the Q2 path, on the open PR.
- `ask` — `/compound` offers the choice per entry with the sidecar preselected. An AFK run resolves it to the sidecar without asking.

The default is `sidecar` whenever Q1 is `guest`, whatever path Q2 detected: a guest repo is someone else's, and a committed `docs/solutions` there is theirs, not a place for the pack's lessons. When Q1 is `owned`, the default is `in-tree` only when the confirmed path is `docs/solutions` and it is committed (`git ls-files docs/solutions | head -n 1` prints something). Otherwise the default is `sidecar`, including for `docs/adr`, `docs/adrs`, `docs/decisions`, and an uncommitted `docs/solutions`. A repo with its own convention keeps that convention for its own records and is not flooded with the pack's. When Q2's answer is `none`, skip Q3: `sidecar` is the only valid answer, because `init` refuses `in-tree` and `ask` without an in-tree path.

**Then create it**, with the miss line's suggested `--name`:

```bash
bash "$SC" init --name <suggested> --mode <Q1> --write <Q3> --in-tree-path <Q2>
```

`init` refuses rather than guesses: when the project's identity is already claimed by another sidecar, or when no global git identity is set, which it copies as the sidecar's committer. Relay a refusal as printed. Do not set a git identity on the user's behalf. By default `init` also moves this project's old research archive into the sidecar, and reports each move on stderr. Show those lines to the user.

**Then the repo's facts, on a hit or after `init`.** Each key below is asked only when the sidecar has no answer for it yet, so a re-run asks nothing already answered. A detected value is only the default the user confirms; nothing runs it or writes it before they do.

**Q4 — the base branch** (`base_ref`), the branch this repo's PRs merge into.

```bash
SC="<this skill's directory>/scripts/sidecar.sh"
CUR="$(bash "$SC" config get base_ref)" || { echo "base_ref: config get failed; stop and relay it" >&2; exit 1; }
if [ -n "$CUR" ]; then echo "base_ref=$CUR (answered; not asking)"; exit 0; fi
DETECTED="$(bash "$SC" base-ref --name 2>/dev/null)" || DETECTED=
echo "detected=${DETECTED:-none}"
```

When it prints `answered`, skip Q4. Otherwise ask, offering the detected branch first (it is `origin/HEAD`'s branch, or the first of the usual base names that exists). On `detected=none` there is no default: the user names the branch. Write the answer with:

```bash
bash "$SC" config set base_ref <branch>
```

`config set` takes the bare branch name, refuses `origin/<branch>`, and refuses a branch that resolves to no ref in this checkout. Relay a refusal as printed and ask again.

**Q5 — the verify commands**, one question per key, in the order the block below prints them. The block reads which keys are still unasked from `profile`, and proposes a default for each from this repo's files. It writes nothing and runs none of what it detects.

```bash
SC="<this skill's directory>/scripts/sidecar.sh"
P="$(bash "$SC" profile)" || { echo "profile failed; stop and relay it" >&2; exit 1; }
printf '%s\n' "$P" | sed -n 's/^Not declared (ask before running anything not listed): /unasked=/p'
PM=
for pair in pnpm-lock.yaml:pnpm package-lock.json:npm yarn.lock:yarn bun.lockb:bun bun.lock:bun; do
  if [ -f "${pair%%:*}" ]; then PM="${pair#*:}"; break; fi
done
echo "detected.package_manager=$PM"
for s in typecheck test lint; do
  d=
  if [ -n "$PM" ] && jq -e --arg s "$s" '.scripts[$s] | type == "string"' package.json >/dev/null 2>&1; then d="$PM run $s"; fi
  echo "detected.$s=$d"
done
HM=
if [ -f lefthook.yml ] || [ -f lefthook.yaml ]; then HM=lefthook
elif [ -d .husky ]; then HM=husky
elif [ -f .pre-commit-config.yaml ]; then HM=pre-commit
fi
echo "detected.hook_manager=$HM"
```

No `unasked=` line means every key is answered: skip Q5 and Q6. Otherwise ask each key on the `unasked=` line except `hazards`, which is Q6, one per turn. Offer its `detected.` value first. A blank detected value has no default, and the user names the command. The user may also answer that the repo has none. The package.json check follows `/setup-ralph-loop`'s feedback-loop check and the lockfile check follows `/setup-pre-commit`'s; the hook-manager check is this block's own. A script is proposed only when a lockfile names the package manager to run it with. On a guest repo, those files belong to someone else, so a script name chosen to look safe is still only a proposal. Write each answer only after the user confirms it:

```bash
bash "$SC" config set verify.<key> "<command the user confirmed>"
bash "$SC" config set verify.<key> ""   # the repo has none
```

`""` declares none, which `profile` renders as `none`, while a key never written stays under `Not declared`. On a sidecar `init` wrote before this question existed (schema 1), the first of these writes moves the sidecar to schema 2 in the same commit and drops the empty values that `init` stubbed, so keys not yet answered still read as unasked. `config set` refuses a value that spans lines. Relay a refusal as printed and ask again.

**Q6 — hazards** (`hazards` on the `unasked=` line): commands an agent must not run, or actions it must not take, in this repo without asking first. Nothing is detected, and the default is none. Each hazard needs a `reason`. A hazard may also carry a `command` in Claude Code permission-rule syntax, such as `Bash(pnpm test:e2e*)` ([hooks reference](https://code.claude.com/docs/en/hooks)), so that a later hook can match it. This skill does not enforce hazards. Write the confirmed list as one JSON array, or `[]` for none:

```bash
bash "$SC" config set verify.hazards '[{"reason":"resets the shared staging database","command":"Bash(pnpm test:e2e*)"},{"reason":"never push to the staging branch"}]'
```

`config set` refuses the whole list, writing nothing, when an entry has no non-empty one-line `reason`, carries a `command` that is not a non-empty one-line string, or has any other key. Relay the refusal as printed and ask again.

## Verification

Before considering setup complete, check — against the sections § 2's per-path rule actually sent this run through, not against all eight. An auto-invoked Path C re-scaffold produces § 2's hook body, § 3's merge and § 6's append and nothing else, and Path D produces at most a refreshed marker-check span, § 8's sidecar, § 5's quality gate when the install was Path B, and with it the one-line rewrite § 5 ends with, so on either the pre-commit items below — and the quality-gate item, unless Path D ran § 5 — belong to the install that already ran and are not this run's to satisfy:

- [ ] `.claude/hooks/enforce-classification.sh` exists and is executable
- [ ] Hook's `IMPL_PATTERNS` array matches the project's implementation surface: on § 2's Path A or B, the default list or the customized answer confirmed during this install; on Path C or Path D, byte-identical to the array in the hook that was already there
- [ ] `.claude/hooks/block-dangerous-git.sh` exists and is executable
- [ ] `.claude/hooks/sidecar.sh` exists beside it, so the guard can read a sidecar review stamp
- [ ] `.claude/settings.json` has both PreToolUse hooks configured
- [ ] Path D that ran § 5: the line above `IMPL_PATTERNS` is the one § 5 says to rewrite it to, whichever answer the user gave
- [ ] If quality gate accepted: `.claude/hooks/quality-gate.sh` exists, is executable, and PostToolUse hook is in settings
- [ ] Hook manager config exists (e.g. `lefthook.yml`)
- [ ] Pre-commit hooks run successfully
- [ ] `.gitignore` has marker entries
- [ ] `.claude/settings.json` has no `worktree.provisioning` key written by this run (`auto`), whether or not a host env var is set
- [ ] No existing project settings were overwritten
- [ ] Path A or Path D: `bash "$SC" resolve` exits 0 and prints the sidecar, and its `sidecar.json` carries the confirmed `mode`, `solutions.write`, and `solutions.in_tree_path`
- [ ] Path A or Path D: `bash "$SC" config get base_ref` prints the branch the user confirmed, or the one a previous run recorded
- [ ] `.claude/settings.json` is unchanged by § 8: take `shasum .claude/settings.json` right before § 8 starts and again after § 8, and the two match
- [ ] Path B or an auto-invoked Path C: no sidecar was created (`bash "$SC" resolve` gives the same answer it gave before the run)

## Handoff

- **Expected input:** any project that will use `/execute`
- **Produces:** complete enforcement infrastructure — Claude Code hooks, git guardrails, pre-commit hooks using detected or user-confirmed tools — and, on Path A or Path D, the project's sidecar with its `mode` and `solutions` target
- **Auto-invoked by:** `/execute` Step 0 when `.claude/hooks/enforce-classification.sh` is missing, or when it exists but does not read every term in that gate's `GATE_TERMS` or carry every sentinel in its `GATE_SENTINELS` — a pre-lock, pre-marker, or pre-project-scope install, re-scaffolded per § 2
- **Invokes:** `/git-guardrails-claude-code` (project scope), `/setup-pre-commit`
- **Supports downstream:** `/research`, `/compound`, and `/excavate` (they read the sidecar § 8 creates; `/lfg` stops on a miss before its AFK phase), `/tdd` (marker creation), `/execute` (marker cleanup); reserves `.claude/.ralph-checked` for `/setup-ralph-loop`, which creates the marker itself (auto-invoked by `/execute` for multi-slice work, or run manually); reserves `.claude/.review-stamped` and `.claude/.fix-findings-active` for the post-review edit lock, written by `/pre-merge` Phase 4 and `/fix-findings` respectively
