#!/usr/bin/env bash
# Its grep patterns match literal Markdown backticks; expansion would defeat them.
# shellcheck disable=SC2016
# test-execute-worktree-handoff.sh — /execute Step 0 hands a new worktree to a
# fresh session; EnterWorktree is only the fallback.
#
# THE DRIFT CLASS. /execute Step 0 used to move the running session into the
# worktree it had just created with Claude Code's EnterWorktree tool. A session
# moved that way runs under the harness's worktree-isolation guard, which
# refuses many of the pack's own documented blocks as "too complex to verify
# that it stays inside the worktree". The default is now a hand-off: print the
# command that starts a new session inside the worktree, and what to type
# there to resume, then stop. Prose drifts back toward the old default easily
# (one sentence elsewhere calling EnterWorktree "the inflow /execute uses" is
# enough to route a reader to it), so the shape is pinned here.
#
# THE INCIDENT BEHIND IT. chrislacey89/skills#782: 55 refused commands across
# five downstream sessions, all under EnterWorktree isolation; #693 was the
# first occurrence.
#
# WHAT THIS PINS.
#   1. execute/SKILL.md carries the hand-off: a fenced block whose command is
#      `cd <absolute-worktree-path> && claude`, a fenced block resuming with
#      `/execute <...>`, and a Re-entry rule so the new session does not hand
#      off again.
#   2. Every execute/SKILL.md line that names EnterWorktree names it as the
#      fallback, as what not to do by default, or as what headless runs skip.
#   3. Headless runs keep the `cd <absolute-worktree-path> &&` prefix.
#   4. No other inventory surface names EnterWorktree except /closeout's
#      re-anchor step, which names it as /execute's fallback.
#
# WHAT THIS DOES NOT PIN. Whether the harness guard still refuses those
# blocks, or what $CLAUDE_PROJECT_DIR holds in a hand-off session; both are
# harness behavior, measured on #782 and #693, not checked here.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ "$#" -gt 1 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}

ex=execute/SKILL.md

# Fenced blocks' bodies (fence lines dropped, leading indent stripped), one
# line each; a list item's fence is indented, so match fences after spaces.
fenced_lines() {
    awk '/^[[:space:]]*```/ { inb = !inb; next } inb { sub(/^[[:space:]]+/, ""); print }' "$1"
}

printf '\n=== /execute Step 0: the hand-off ===\n'

fenced="$(fenced_lines "$ex")"
afk="$(grep '^\*\*AFK / headless\.\*\*' "$ex" || true)"

if grep -qx 'cd <absolute-worktree-path> && claude' <<<"$fenced"; then
    ok "a fenced block starts a new session inside the worktree"
else
    bad "a fenced block starts a new session inside the worktree" "no fenced line 'cd <absolute-worktree-path> && claude' in $ex"
fi

if grep -qE '^/execute <[^>]+>$' <<<"$fenced"; then
    ok "a fenced block says what to type to resume"
else
    bad "a fenced block says what to type to resume" "no fenced line '/execute <...>' in $ex"
fi

if grep -q '^\*\*Hand off to a fresh session in the worktree' "$ex"; then
    ok "the hand-off paragraph exists"
else
    bad "the hand-off paragraph exists"
fi

if grep -q '^- \*\*Re-entry\.\*\*' "$ex"; then
    ok "a Re-entry rule keeps the new session from handing off again"
else
    bad "a Re-entry rule keeps the new session from handing off again"
fi

printf '\n=== /execute Step 0: EnterWorktree only as the fallback ===\n'

n=0
while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
        *[Ff]allback*|*"Do not move this session in"*|*"neither hand off nor call"*) ;;
        *) bad "an EnterWorktree mention is not framed as the fallback" "${line:0:200}" ;;
    esac
done < <(grep 'EnterWorktree' "$ex")
if [ "$n" -gt 0 ]; then ok "$n EnterWorktree mention(s) read, each checked above"; else bad "execute/SKILL.md names EnterWorktree as the fallback" "no mention found"; fi

if grep -q '^- \*\*Fallback: `EnterWorktree`, only when the human says no new session can be started\.\*\*' "$ex"; then
    ok "the fallback bullet names its condition"
else
    bad "the fallback bullet names its condition"
fi

if grep -qF 'cd <absolute-worktree-path> &&' <<<"$afk"; then
    ok "headless runs keep the cd prefix"
else
    bad "headless runs keep the cd prefix"
fi

printf '\n=== other surfaces point at /execute, not at the old default ===\n'

others="$(git ls-files -- '*.md' ':!:docs/solutions/**' ':!:*/references/**' ':!:execute/SKILL.md' \
    | xargs grep -l 'EnterWorktree' 2>/dev/null || true)"
case "$others" in
    closeout/SKILL.md|'') ok "only /closeout names EnterWorktree outside /execute" ;;
    *) bad "only /closeout names EnterWorktree outside /execute" "also: $(printf '%s' "$others" | tr '\n' ' ')" ;;
esac

if grep -q '^\*\*If this same session entered the worktree via `EnterWorktree`\*\*.*fallback' closeout/SKILL.md; then
    ok "/closeout names EnterWorktree as /execute's fallback"
else
    bad "/closeout names EnterWorktree as /execute's fallback"
fi

if grep -qF 'the inflow `/execute` now uses' closeout/SKILL.md; then
    bad "/closeout no longer calls EnterWorktree the inflow /execute uses"
else
    ok "/closeout no longer calls EnterWorktree the inflow /execute uses"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
