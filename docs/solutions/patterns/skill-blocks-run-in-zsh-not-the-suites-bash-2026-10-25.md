---
date: 2026-10-25
category: patterns
problem_type: a skill's fenced command blocks rely on bash word splitting, but agents run them in the harness's login shell (zsh on macOS) while the contract suite runs them with `bash -c` and CI's runner has no zsh, so the suite proves the blocks in a shell nobody uses
components: [prd-to-issues/SKILL.md, write-a-prd/SKILL.md, execute/SKILL.md, respond-to-review/SKILL.md, scripts/test-prd-to-issues-sidecar-branch.sh, scripts/test-respond-to-review-contract.sh, scripts/test-skill-blocks-zsh-safe.sh, .github/workflows/validate-skills.yml]
technologies: [bash, zsh, claude-code, github-actions]
severity: high
volatility: stable
---

# Skill blocks run in zsh, not in the suite's bash

## Problem

`/prd-to-issues` gained sidecar blocks that create slices with `${BLOCKED_BY:+--blocked-by "$BLOCKED_BY"} ${MILESTONE:+--milestone "$MILESTONE"}` and pick the next slice with `for id in $UNBLOCKED`. Under zsh the first reaches `sidecar.sh` as one argument (`unknown argument: --milestone Big batch`), and the second runs once over the newline-joined list. With two or more slices unblocked, the second reports a dependency cycle that does not exist. The contract suite ran every extracted block and passed 45/45.

## Context

An agent copies a skill's fenced block into its Bash tool, which runs the user's login shell. On macOS that is zsh, and zsh does not split an unquoted expansion into words. The repo's suites extract blocks and run them, which is the right check, but with `bash -c`. CI runs on `ubuntu-latest`, which has no zsh at all.

## Symptoms

- `sidecar.sh` (or any CLI) rejects `--flag value` as one unknown argument, only when an optional variable is set.
- A loop over a list variable sees one item. A gate that greps for each term reports every term missing (`hooks-stale` in #393), and a picker reports "none found".
- The repo's suite is green, because it never runs the block in zsh.
- A `git fetch` refspec names a ref that does not exist, such as `refs/heads/mainefs/remotes/origin/main`. zsh read `$DEST:r` in `"+refs/heads/$DEST:refs/remotes/origin/$DEST"` as the history modifier `:r` (strip a suffix), and it does that inside double quotes too.

## Root Cause

The suite's interpreter is chosen by the suite author, not by the environment that runs the blocks, and nothing ties the two together. This is the same shape as `skill-command-blocks-run-one-shell-per-call-2026-10-13.md`: there, the suite ran blocks in one process while agents get a fresh shell per call; here, the suite runs bash while agents get zsh. Both times the suite made the skill's claim true by accident.

## Learning Level

- **Level:** Pattern, recorded three times.
  - First: #393 found a zsh case in `/execute` on 2026-10-02. It lived only in an open issue, so `/execute`'s `docs/solutions/` grep never surfaced it.
  - Second: this slice repeated it.
  - Third: PR #612 (2026-10-27), in a different shape, word splitting is fine but `$NAME:<letter>` is a modifier. It landed in a suite that already ran a zsh arm, but only for the Step 1 block. The Step 2 block added by a review fix in the same file ran under bash alone. A zsh arm protects the blocks it names, not the file.
- **Feedback loop or delay:** missing feedback. The author's machine runs zsh, but the suite and CI both run bash, so only an independent reviewer reading the block in the real shell reported it.

## Rule Scope

- **Applies when:** a skill documents a fenced bash/sh block that relies on a bash-only reading of an expansion:
  - word splitting of an unquoted expansion: a `for x in $LIST` loop, an optional-flag `${VAR:+--flag "$VAR"}`, or a bare `$FLAGS` meant to become several arguments;
  - an unbraced `$NAME` followed by `:` and a zsh modifier letter (`a A c e g h l P q Q r s t u x &`), as in a refspec, a `host:path`, or a `key:value`. Other letters after the colon are literal in zsh.
- **Inverts or does not apply when:** the block runs through an explicit `bash -c '…'` or a script file with a bash shebang. The interpreter is then fixed by the block itself, and bash idioms are correct there.
- **Sibling docs:** `skill-command-blocks-run-one-shell-per-call-2026-10-13.md` (the same pattern along a different axis); `by-construction-claims-need-a-mechanism-2026-08-11.md`.

## Solution

Write blocks that mean the same in bash and zsh, and run the suite's extracted blocks under both.

**Before:**
```bash
bash "$SC" work create --kind slice --parent "$PRD" ${BLOCKED_BY:+--blocked-by "$BLOCKED_BY"} --body-file "$f"
for id in $UNBLOCKED; do …; done
```

**After:**
```bash
set -- --kind slice --parent "$PRD"
[ -z "$BLOCKED_BY" ] || set -- "$@" --blocked-by "$BLOCKED_BY"
bash "$SC" work create "$@" --body-file "$f"
while IFS= read -r id; do …; done <<<"$UNBLOCKED"
```

`scripts/test-prd-to-issues-sidecar-branch.sh` re-runs itself once per shell. CI installs zsh, and the suite fails rather than skips when `CI` is set and zsh is missing, so the zsh arm cannot drop out without notice.

## Prevention

**Code-level:** `scripts/test-skill-blocks-zsh-safe.sh` scans every fenced bash/sh block in `*/SKILL.md`, `SYSTEM-OVERVIEW.md`, and `docs/*.md` for three textual shapes: the two above, and, since PR #612, the unbraced `$NAME:<modifier>` (fix: `${NAME}:`). PR #612's refspec is listed as a known site until its fix lands. Pre-existing sites are listed with the issue that owns each, and an entry that stops matching fails, so the list only shrinks. The two it shipped with (`/execute`'s `for term in $GATE_TERMS`, `/write-a-prd` Step 8's `${MILESTONE:+…}`) were fixed in #393, so it is empty. It cannot see a bare `$FLAGS` meant to split, unmatched globs, or array differences. A suite that runs a skill's blocks under zsh is the stronger check; `/prd-to-issues`' suite does, and `scripts/test-post-review-edit-lock.sh` runs `/execute`'s hooks gate under both shells.

**Process-level:** when a suite extracts and runs skill blocks, run each block it runs under every shell agents use (bash and zsh), and make CI provide that shell instead of skipping. A zsh arm is per block. A new block added to a file whose suite already has one, including a block added by a review fix, needs its own zsh run, or it runs under bash alone. A lesson that lives only in an open issue is invisible to `/execute`'s and `/research`'s `docs/solutions/` grep, so the first recording of a pattern belongs here as well as in the issue.

## Key Decision

**Decision:** a static scan with a shrinking allowlist, rather than fixing `/execute` and `/write-a-prd` in this PR.
**Rationale:** both sites are outside #524's scope and already owned by #393. The scan stops a third site from landing, and its allowlist forces each entry out when its fix ships.
**Alternatives considered:** running every suite's `bash -c` under zsh too. That is broader and correct, but it is a cross-suite change that belongs to #393.
**Revisable:** yes. Once every block-running suite has a zsh arm, the static scan is redundant.

## Related

- PR #561 (slice #524): the shipping change, the fixes a60beb6 and 6610547, and the scan.
- chrislacey89/skills#393: the first zsh recording, and the owner of the two remaining sites.
- PR #612: the third recording, a `$DEST:r` refspec in `/respond-to-review` Step 2, and the scan's third shape.

## Shelf Life

When every suite that executes skill blocks runs them under zsh as well as bash, and #393's sites are fixed, delete the scan's allowlist. Keep this entry as long as agents run blocks in a login shell that is not bash.
