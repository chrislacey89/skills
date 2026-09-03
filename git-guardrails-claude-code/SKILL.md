---
name: git-guardrails-claude-code
description: "Infrastructure safety skill for blocking dangerous git commands, and merges that outran their review, in Claude-driven workflows. Use when the repo or user environment needs guardrails against destructive git operations or against a hand-typed/AFK `gh pr merge` that skips /closeout. Not a delivery-pipeline step; it makes later work safer."
---

# Setup Git Guardrails

Sets up a PreToolUse hook that intercepts and blocks dangerous git commands before Claude executes them, and refuses a `gh pr merge` whose PR head has moved past the SHA `/pre-merge` reviewed.

## Invocation Position

This is an infrastructure safety skill, not a feature-delivery step.

Use `/git-guardrails-claude-code` when the project or user wants stronger protection against destructive git operations in Claude-driven workflows.

Do not treat it as part of the normal feature pipeline. It is a repo or user setup action that makes later work safer.

## What Gets Blocked

- `git push --force` / `git push -f` (regular pushes are allowed)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`
- `gh pr merge` against a **stale review stamp** — see below

When blocked, Claude sees a message telling it that it does not have authority to access these commands.

### The review-currency refusal

`/pre-merge` Phase 4 writes a `<!-- reviewed-at: <sha> -->` marker into the PR body, and `/closeout` Step 2 compares it to the PR head before merging. That comparison only happens when the merge goes *through* `/closeout`. A merge typed by hand, or issued by an AFK loop, skips it — which is precisely the unattended case where nobody notices that the reviewed diff is not the merged diff.

So the hook performs the same read at the command itself. On a `gh pr merge` it resolves the PR, extracts the stamp, and refuses when the stamp and the PR head are two distinct 40-character OIDs. The refusal reports how far past the stamp the head is, so the response can be proportional to the delta rather than to the bare fact of one:

```
BLOCKED: 'gh pr merge --squash' would merge a PR whose head has moved past the SHA /pre-merge reviewed.
  reviewed-at: 3fb314c2b348787bae65c930ca8bd086ac17d17d
  PR head:     c19b50794c44ce4d282d627e56ecb7a75899b6df
  delta:       3 commit(s) past the stamp; 2 files changed, 6 insertions(+)
Re-review the delta with /pre-merge (it re-stamps at the new head), or run the merge again with ALLOW_STALE_STAMP_MERGE=1 to accept it as-is.
```

That block is a transcript, not a sketch — it is the script's real output against a fixture repo three commits past its stamp. Both OIDs are shown at full 40 characters because that is what the marker carries and what the comparison uses; a truncated form in a PR body cannot compare equal to the head and would make the gate report divergence forever.

**It fails open on every uncertainty**, because a gate that refuses wrongly is a gate that gets deleted:

- `gh` or `jq` not on `PATH`, or the `gh` call fails — nothing to compare against.
- The PR carries **no stamp**. Hand-authored PRs, external contributions, and PRs predating the stamp all land here; absence of a stamp is not evidence of an unreviewed diff, and refusing on every unstamped PR is the alarm fatigue that gets a gate reflexively defeated. `/closeout` treats this case the same way.
- The command line puts a **flag before the positional selector** (`gh pr merge --subject fix 4821`). A bare token there could equally be that flag's value, and telling the two apart would mean re-authoring `gh`'s flag table from memory. The hook declines to guess and lets the command through. The two forms it *does* resolve are the selector immediately after `merge` and no selector at all — see [`gh pr merge`](https://cli.github.com/manual/gh_pr_merge) for the full argument grammar.

**Escape hatch:** `ALLOW_STALE_STAMP_MERGE=1 gh pr merge …` skips the check for that one command. The refusal names it, so the way out is readable at the moment it is needed.

This is the only refusal in the hook that reaches the network, and only on a command that matches `gh pr merge` — every other Bash call still costs one `grep` over the command string.

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

The review-currency refusal needs a real PR to exercise, so verify it where one exists — on a PR whose `/pre-merge` stamp is current, `gh pr merge` should be allowed through untouched; push one more commit and it should refuse, naming both SHAs and the delta. In the Skill Kit repo itself, `scripts/test-review-currency-marker.sh` does this against a stubbed `gh` and a fixture repo, and also pins the hook's stamp-extraction to be byte-identical to `/closeout`'s.

## Handoff

- **Expected input:** a project or user environment that needs stronger git safety controls
- **Produces:** installed guardrail hooks and safer Claude git behavior, including a merge that refuses to outrun its own review
- **Supports downstream:** all implementation and review work by reducing destructive-command risk, and `/pre-merge` → `/closeout` by making the review-currency read unskippable at `gh pr merge`
- **What comes next:** return to normal workflow with the guardrails in place
