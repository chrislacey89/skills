#!/usr/bin/env bash
# test-closeout-prune.sh — /closeout finishes honestly: the prune block, the
# open-items read, and the project-directory check (#809).
#
# THE DRIFT CLASS. /closeout Step 6 used to end on `git branch -d <branch>`.
# After a squash or rebase merge git does not count the branch as merged, so
# that command refuses every time, and the pack's own guard refuses the forced
# form (git-guardrails-claude-code/scripts/block-dangerous-git.sh, the `-D`
# arm). The step's only completing command was one the guard would not let
# through, so the step could not finish. Nothing executed it, so nothing said
# so.
#
# The replacement deletes the ref with `git update-ref -d`, and is honest only
# because of the proof in front of it: the PR's state is MERGED and the local
# tip is the commit the PR carried. This suite extracts Step 6's block from the
# real closeout/SKILL.md and RUNS it, under bash and under zsh (the shell an
# agent runs it in on macOS), in a scratch repo, after the real guard has
# allowed it. Both arms are run: the proof holds and the ref goes; the proof
# fails and every ref stays. `gh` is a stub that answers the two reads the block
# makes and fails on anything else.
#
# The suite also runs Step 1's open-items read against a stubbed `gh` and a
# planted PR body, and Step 5's project-directory check against planted paths.
# And it pins the prose that has no command to run: the single question, the
# sentence that a menu pick is not the go-ahead, the git documentation the
# prune block rests on, and the stop message.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md,
# and scripts/test-fixture-git-isolation.sh, which checks it). Every git command
# runs inside the scratch directory made with mktemp, never in this repository.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
CO="$repo_root/closeout/SKILL.md"
GUARD="$repo_root/git-guardrails-claude-code/scripts/block-dangerous-git.sh"
for f in "$CO" "$GUARD"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { printf 'FATAL jq is required (the guard reads its payload with it)\n'; exit 1; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Closeout Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
has() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1" "[$3] not found in: $2"; fi; }
hasnt() { if grep -qF -- "$3" <<<"$2"; then bad "$1" "[$3] found in: $2"; else ok "$1"; fi; }

# block <file> <literal> — the first fenced bash block containing <literal>.
block() {
    awk -v want="$2" '
        /^ *```bash$/ { buf = ""; on = 1; ind = index($0, "`") - 1; next }
        on && /^ *```$/ { on = 0; if (index(buf, want)) { printf "%s", buf; exit } next }
        on { buf = buf substr($0, ind + 1) "\n" }
    ' "$1"
}

finish() { printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"; [ "$fail" -eq 0 ]; exit $?; }

# -----------------------------------------------------------------------------
section "the blocks are in closeout/SKILL.md"

# shellcheck disable=SC2016  # the needles are the skill's literal text
prune_block="$(block "$CO" 'git update-ref -d')"
# shellcheck disable=SC2016
open_block="$(block "$CO" 'unticked checklist lines')"
# shellcheck disable=SC2016
projdir_block="$(block "$CO" '<worktree-path>" && pwd -P')"
for pair in "Step 6 prune:$prune_block" "Step 1 open-items:$open_block" "Step 5 project-directory:$projdir_block"; do
    if [ -n "${pair#*:}" ]; then ok "${pair%%:*} block found"; else bad "${pair%%:*} block found" "not found in closeout/SKILL.md"; fi
done
if [ -z "$prune_block" ] || [ -z "$open_block" ] || [ -z "$projdir_block" ]; then finish; fi

# -----------------------------------------------------------------------------
section "no fenced block in closeout/SKILL.md uses the forced branch delete"

# The guard refuses `git branch -D`; a block that carried it could never run.
forced="$(awk '/^ *```bash$/ { on = 1; next } on && /^ *```$/ { on = 0; next } on' "$CO" | grep -E 'git branch (-D|.*--force)' || true)"
check "no bash block carries the forced delete" "" "$forced"

# -----------------------------------------------------------------------------
section "the stub gh and the guard"

# The stub answers the two reads the prune block makes, the body read Step 1
# makes, and fails on anything else: none of these blocks edits, comments on,
# or merges anything on the forge.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$*" in
    "pr view 7 --json state -q .state")
        [ "${GH_FAIL:-}" = state ] && { echo "stub gh: cannot reach the forge" >&2; exit 1; }
        printf '%s\n' "${GH_STATE:-MERGED}" ;;
    "pr view 7 --json headRefOid -q .headRefOid")
        [ "${GH_FAIL:-}" = head ] && { echo "stub gh: cannot reach the forge" >&2; exit 1; }
        printf '%s\n' "$GH_HEAD" ;;
    "pr view 7 --json body -q .body")
        [ "${GH_FAIL:-}" = body ] && { echo "stub gh: cannot reach the forge" >&2; exit 1; }
        printf '%s\n' "$GH_BODY" ;;
    *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"

# guard_rc <dir> <command> — the guard's exit status for a command, fed the way
# Claude Code feeds it: the whole text as one Bash tool call.
guard_rc() {
    local payload
    payload="$(jq -nc --arg c "$2" '{tool_input: {command: $c}}')"
    (cd "$1" && printf '%s' "$payload" | bash "$GUARD" >/dev/null 2>&1)
    printf '%s' "$?"
}

# -----------------------------------------------------------------------------
section "the prune block, run under the guard, bash and zsh"

n=0
# mkfix <squash|merge> — $R: a repo on main with an origin; branch feat holds
# two commits and has been merged into main. Prints nothing; sets R, FEAT_TIP.
mkfix() {
    n=$((n + 1))
    R="$tmp/fix$n"
    git init -q "$R"
    git init -q --bare "$tmp/origin$n.git"
    git -C "$R" remote add origin "$tmp/origin$n.git"
    printf 'base\n' > "$R/base.txt"
    git -C "$R" add base.txt && git -C "$R" commit -q -m "base"
    git -C "$R" push -q origin main
    git -C "$R" switch -q -c feat
    printf 'one\n' > "$R/f.txt" && git -C "$R" add f.txt && git -C "$R" commit -q -m "feat one"
    printf 'two\n' >> "$R/f.txt" && git -C "$R" commit -q -am "feat two"
    git -C "$R" push -q -u origin feat
    FEAT_TIP="$(git -C "$R" rev-parse feat)"
    git -C "$R" switch -q main
    if [ "$1" = squash ]; then
        git -C "$R" merge -q --squash feat >/dev/null && git -C "$R" commit -q -m "feat (#7)"
    else
        git -C "$R" merge -q --no-ff feat -m "merge feat"
    fi
    git -C "$R" push -q origin main
    git -C "$R" push -q origin --delete feat   # what --delete-branch did at merge
}

# run_prune <shell> — the extracted block, placeholders filled, run in $R after
# the guard has allowed it. Sets out and rc; GH_* come from the caller.
run_prune() {
    local b="${prune_block//<feature-branch>/feat}"
    b="${b//<pr-number>/7}"
    : > "$tmp/calls"
    guard="$(guard_rc "$R" "$b")"
    if [ "$guard" != 0 ]; then out="(guard refused the block, exit $guard)"; rc=99; return; fi
    out="$(cd "$R" && GH_CALLS="$tmp/calls" PATH="$tmp/bin:$PATH" "$1" -c "$b" 2>&1)"; rc=$?
}
branch_exists() { git -C "$R" rev-parse --verify -q refs/heads/feat >/dev/null && echo yes || echo no; }

for sh in bash zsh; do
    if [ "$sh" = zsh ] && ! command -v zsh >/dev/null 2>&1; then printf '  SKIP zsh not installed\n'; continue; fi
    section "[$sh] squash merge, the proof holds: the ref goes"
    mkfix squash
    safe="$(git -C "$R" branch -d feat 2>&1 >/dev/null || true)"
    has "[$sh] fixture: the safe delete refuses after a squash merge" "$safe" "not fully merged"
    check "[$sh] fixture: the branch is still there" yes "$(branch_exists)"
    GH_STATE=MERGED GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the guard allowed the block" "" "$(grep -F 'guard refused' <<<"$out")"
    check "[$sh] the block exits 0" 0 "$rc"
    check "[$sh] the branch ref is gone" no "$(branch_exists)"
    has "[$sh] it prints that it pruned the branch" "$out" "pruned feat"
    check "[$sh] its tracking config is gone too" "" "$(git -C "$R" config --get-regexp '^branch\.feat\.' || true)"
    check "[$sh] main is untouched" "feat (#7)" "$(git -C "$R" log -1 --format=%s main)"

    section "[$sh] the local tip is not the commit the PR carried: nothing is deleted"
    mkfix squash
    printf 'late\n' > "$R/late.txt"
    git -C "$R" switch -q feat && git -C "$R" add late.txt && git -C "$R" commit -q -m "after the merge" && git -C "$R" switch -q main
    LOCAL_TIP="$(git -C "$R" rev-parse feat)"
    GH_STATE=MERGED GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the branch ref stays" yes "$(branch_exists)"
    check "[$sh] the ref still holds the late commit" "$LOCAL_TIP" "$(git -C "$R" rev-parse feat)"
    has "[$sh] it prints the local commit" "$out" "$LOCAL_TIP"
    has "[$sh] it prints the PR's commit" "$out" "$FEAT_TIP"
    has "[$sh] it says the prune was skipped" "$out" "prune skipped"

    section "[$sh] the PR is not merged: nothing is deleted even when the tips match"
    mkfix squash
    GH_STATE=OPEN GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the branch ref stays" yes "$(branch_exists)"
    has "[$sh] it says the prune was skipped" "$out" "prune skipped"
    has "[$sh] it names the PR's state" "$out" "OPEN"

    section "[$sh] the PR's state cannot be read: nothing is deleted, exit nonzero"
    mkfix squash
    GH_FAIL=state GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the block exits 1" 1 "$rc"
    check "[$sh] the branch ref stays" yes "$(branch_exists)"
    has "[$sh] it says why" "$out" "cannot read the PR's state"

    section "[$sh] the PR's head cannot be read: nothing is deleted, exit nonzero"
    mkfix squash
    GH_FAIL=head GH_STATE=MERGED run_prune "$sh"
    check "[$sh] the block exits 1" 1 "$rc"
    check "[$sh] the branch ref stays" yes "$(branch_exists)"
    has "[$sh] it says why" "$out" "cannot read the PR's head"

    section "[$sh] the branch is checked out in another worktree: nothing is deleted"
    mkfix squash
    git -C "$R" worktree add -q "$tmp/wt$n" feat
    GH_STATE=MERGED GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the branch ref stays" yes "$(branch_exists)"
    has "[$sh] it says a worktree holds the branch" "$out" "checked out in a worktree"

    section "[$sh] an ordinary merge: the safe delete works and gh is never called"
    mkfix merge
    GH_STATE=MERGED GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the block exits 0" 0 "$rc"
    check "[$sh] the branch ref is gone" no "$(branch_exists)"
    check "[$sh] gh was not called" "" "$(cat "$tmp/calls")"

    section "[$sh] the branch is already gone: nothing to prune, no forge call"
    mkfix squash
    git -C "$R" update-ref -d refs/heads/feat
    GH_STATE=MERGED GH_HEAD="$FEAT_TIP" run_prune "$sh"
    check "[$sh] the block exits 0" 0 "$rc"
    has "[$sh] it says there is nothing to prune" "$out" "nothing to prune"
    check "[$sh] gh was not called" "" "$(cat "$tmp/calls")"
done

# -----------------------------------------------------------------------------
section "the guard still refuses the forced delete, and allows the one the block uses"

mkfix squash
check "guard: the forced branch delete is refused (exit 2)" 2 "$(guard_rc "$R" 'git branch -D feat')"
check "guard: the long forced form is refused (exit 2)" 2 "$(guard_rc "$R" 'git branch --delete --force feat')"
check "guard: update-ref -d with its old value is allowed (exit 0)" 0 "$(guard_rc "$R" "git update-ref -d refs/heads/feat $FEAT_TIP")"

# -----------------------------------------------------------------------------
section "Step 1's open-items read, bash and zsh"

BODY="$(printf '%s\n' \
    '## Summary' '' 'Does a thing.' '' \
    '- [x] ticked item' \
    '- [ ] unticked item one' \
    '  - [ ] unticked nested item' '' \
    '## Review Disposition Ledger' '' \
    '| Pass | Finding | Dimension | State | Evidence / outcome |' \
    '|---|---|---|---|---|' \
    '| 1 | Duplicate date formatter | Deep Modules | fixed | abc1234 — operator |' \
    '| 1 | Same pattern in lib/export | Deep Modules | filed | #199 — operator |' \
    '| 2 | Presence helper claimed as a Layer | Boundary Map Contracts | open | confirmed — lib/presence.ts:12 |' \
    '| 2 | Stamp block "no-ops" | Adherence | accepted | open question, accepted |')"
CLEAN_BODY="$(printf '%s\n' '## Summary' '' '- [x] ticked item' '' '## Review Disposition Ledger' '' '| Pass | Finding | Dimension | State | Evidence / outcome |' '|---|---|---|---|---|' '| 1 | A finding | Deep Modules | fixed | abc1234 |')"
# An author-mode body: no ledger, which only loop-mode writes.
NO_LEDGER_BODY="$(printf '%s\n' '## Summary' '' 'Does a thing.' '' '## Review Notes' '' '- [x] ticked item' '- [ ] unticked item one')"
# The ledger as pre-merge/SKILL.md prints it: the first markdown fence that holds it.
TEMPLATE="$(awk '
    /^```markdown$/ { buf = ""; on = 1; next }
    on && /^```$/ { on = 0; if (index(buf, "## Review Disposition Ledger") && index(buf, "loop-pass")) { printf "%s", buf; exit } next }
    on { buf = buf $0 "\n" }
' "$repo_root/pre-merge/SKILL.md")"
TEMPLATE_BODY="$(printf '%s\n\n%s' '## Summary' "$TEMPLATE")"
TEMPLATE_CRLF_BODY="$(printf '%s\n' "$TEMPLATE_BODY" | sed 's/$/\r/')"

run_open() {
    local b="${open_block//<number>/7}"
    : > "$tmp/calls"
    out="$(cd "$tmp" && GH_BODY="$1" GH_CALLS="$tmp/calls" PATH="$tmp/bin:$PATH" "$2" -c "$b" 2>&1)"; rc=$?
}
for sh in bash zsh; do
    if [ "$sh" = zsh ] && ! command -v zsh >/dev/null 2>&1; then printf '  SKIP zsh not installed\n'; continue; fi
    run_open "$BODY" "$sh"
    check "[$sh] the block exits 0" 0 "$rc"
    has "[$sh] it lists an unticked line" "$out" "unticked item one"
    has "[$sh] it lists a nested unticked line" "$out" "unticked nested item"
    hasnt "[$sh] it does not list a ticked line" "$out" "- [x]"
    has "[$sh] it lists the ledger row still open" "$out" "Presence helper claimed as a Layer"
    hasnt "[$sh] it does not list a fixed row" "$out" "Duplicate date formatter"
    hasnt "[$sh] it does not list a filed row" "$out" "Same pattern in lib/export"
    hasnt "[$sh] an accepted row whose evidence says 'open' is not listed" "$out" "no-ops"
    check "[$sh] the only gh call reads the PR body" "pr view 7 --json body -q .body" "$(cat "$tmp/calls")"
    run_open "$CLEAN_BODY" "$sh"
    check "[$sh] a clean body: the block exits 0" 0 "$rc"
    has "[$sh] a clean body: it says there are no unticked lines" "$out" "unticked checklist lines: none"
    has "[$sh] a clean body: it says there are no open ledger rows" "$out" "open ledger rows: none"
    hasnt "[$sh] a clean body: it does not say there is no ledger block" "$out" "no ledger block"
    run_open "$NO_LEDGER_BODY" "$sh"
    check "[$sh] no ledger: the block exits 0" 0 "$rc"
    has "[$sh] no ledger: it still lists an unticked line" "$out" "unticked item one"
    has "[$sh] no ledger: it says there is no ledger block" "$out" "no ledger block in the PR body"
    hasnt "[$sh] no ledger: it does not say a ledger had no open rows" "$out" "open ledger rows: none"
    for form in "$TEMPLATE_BODY" "$TEMPLATE_CRLF_BODY"; do
        run_open "$form" "$sh"
        has "[$sh] the real template: it lists the open Stamp row" "$out" 'Stamp block "no-ops"'
        has "[$sh] the real template: it lists the open Presence row" "$out" "Presence helper claimed as Effect Layer"
        hasnt "[$sh] the real template: it does not list a fixed row" "$out" "Duplicate date formatter"
        hasnt "[$sh] the real template: it does not list a filed row" "$out" "Same pattern in"
        hasnt "[$sh] the real template: it does not say there is no ledger block" "$out" "no ledger block"
    done
    GH_FAIL=body run_open "$BODY" "$sh"
    check "[$sh] an unreadable body: the block exits 1" 1 "$rc"
    has "[$sh] an unreadable body: it says the open items are unknown, not empty" "$out" "open items unknown"
done

# -----------------------------------------------------------------------------
section "Step 5's project-directory check, bash and zsh"

mkdir -p "$tmp/proj/wt" "$tmp/proj/other"
ln -s "$tmp/proj/wt" "$tmp/link-to-wt"
run_projdir() {
    local b="${projdir_block//<worktree-path>/$1}"
    out="$(cd "$tmp" && env -u CLAUDE_PROJECT_DIR ${2:+CLAUDE_PROJECT_DIR="$2"} "$3" -c "$b" 2>&1)"; rc=$?
}
for sh in bash zsh; do
    if [ "$sh" = zsh ] && ! command -v zsh >/dev/null 2>&1; then printf '  SKIP zsh not installed\n'; continue; fi
    run_projdir "$tmp/proj/wt" "$tmp/proj/wt" "$sh"
    check "[$sh] same path: the block exits 0" 0 "$rc"
    has "[$sh] same path: it reports the project directory is being removed" "$out" "this session's project directory"
    run_projdir "$tmp/proj/wt" "$tmp/link-to-wt" "$sh"
    has "[$sh] a symlink to the same directory counts as the same path" "$out" "this session's project directory"
    run_projdir "$tmp/proj/wt" "$tmp/proj/other" "$sh"
    check "[$sh] another directory: the block exits 0" 0 "$rc"
    check "[$sh] another directory: it prints nothing" "" "$out"
    run_projdir "$tmp/proj/wt" "" "$sh"
    check "[$sh] CLAUDE_PROJECT_DIR unset: the block exits 0" 0 "$rc"
    has "[$sh] CLAUDE_PROJECT_DIR unset: it says it could not tell" "$out" "project-dir-unknown: CLAUDE_PROJECT_DIR is not set in this shell"
    hasnt "[$sh] CLAUDE_PROJECT_DIR unset: it does not claim the worktree is the project directory (an unset value must not compare as the current directory)" "$out" "project-dir: the worktree"
    out="$(cd "$tmp" && CLAUDE_PROJECT_DIR="" "$sh" -c "${projdir_block//<worktree-path>/$tmp/proj/wt}" 2>&1)"; rc=$?
    check "[$sh] CLAUDE_PROJECT_DIR empty: the block exits 0" 0 "$rc"
    has "[$sh] CLAUDE_PROJECT_DIR empty: it says it could not tell" "$out" "project-dir-unknown: CLAUDE_PROJECT_DIR is not set in this shell"
    hasnt "[$sh] CLAUDE_PROJECT_DIR empty: it does not claim the worktree is the project directory" "$out" "project-dir: the worktree"
done

# -----------------------------------------------------------------------------
section "the prose that has no command to run"

co="$(cat "$CO")"
has "Step 1 asks once, with the three options" "$co" "**fix first**, **file as follow-ups, then merge**, or **merge as is**"
has "Step 1 says a menu pick is not the go-ahead" "$co" "A menu pick starts this skill; it does not answer this step."
has "Step 1 asks however the user came in, so it cannot collide with the route: value" "$co" "however the user came into this skill, except where the paragraph above says the question is not asked."
has "Step 1 takes a merge as is answer as the confirmation" "$co" "A **merge as is** answer is the confirmation the block below waits for, so the user is not asked a second time."
has "Step 1 reads the unticked checklist lines" "$co" "Every unticked \`- [ ]\` line in the PR body"
has "Step 1 reads the breaker verdicts" "$co" "\`survived\` or \`not-run\`"
has "Step 6 cites git's own documentation for update-ref" "$co" "https://git-scm.com/docs/git-update-ref"
has "Step 6 cites git's own documentation for branch -d" "$co" "https://git-scm.com/docs/git-branch"
has "Step 6 names the proof it rests on" "$co" "the PR's state is \`MERGED\` and the local tip equals the PR's head"
has "Step 5 prints the stop message" "$co" "This session's project hooks no longer run. Start the next piece of work in a new session."
has "Step 5 cites the hooks reference rather than restating it" "$co" "https://code.claude.com/docs/en/hooks"
has "Step 5 tells the user when the check could not tell" "$co" "If the check printed the \`project-dir-unknown:\` line, tell the user in your report that it could not tell"
has "Step 5 offers no next step that continues in this session" "$co" "offer no next step that continues in this session"

# The claims quoted from git's own manual are checked against the installed git,
# so a changed manual fails here instead of silently drifting.
um="$(git help -m update-ref 2>/dev/null | col -b | tr -s ' \t\n' ' ')"
if [ -n "$um" ]; then
    has "git's manual still says update-ref -d verifies the old value" "$um" "Delete <ref> after verifying it exists with <oldvalue>, if given."
else
    printf '  SKIP git manual pages are not installed\n'
fi
bm="$(git help -m branch 2>/dev/null | col -b | tr -s ' \t\n' ' ')"
if [ -n "$bm" ]; then
    has "git's manual still says -d needs a fully merged branch" "$bm" "Delete a branch. The branch must be fully merged in its upstream branch, or in HEAD if no upstream was set"
fi

finish
