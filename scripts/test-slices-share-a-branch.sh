#!/usr/bin/env bash
# test-slices-share-a-branch.sh — several slices built on one branch (#812):
# the fenced blocks that write and read a slice's `built` state and its
# `pr_mode`, extracted from the skills and RUN, in bash and in zsh.
#
# THE DRIFT CLASS. A work item's state was open or closed, and each slice was
# assumed to get its own PR. When slices are built in order on one branch, the
# blocks that move a slice along the pipeline each have to agree on what
# `built` and `pr_mode none` mean: /execute Step 6 writes `built`, /pre-merge
# Phase 2 records one PR on every built slice of the branch, the Stamp only
# choice records `pr_mode none` and a later Phase 2 then opens nothing, and
# /execute Step 0 keeps a review lock whose stamp names the branch. A block
# that drifts from the others fails quietly: a slice is never closed at merge,
# or a branch meant to stay local gets a PR. So each block is run here against
# a real sidecar and a stubbed gh, and the state it leaves is read back with
# `sidecar.sh work view`.
#
# Agents run these blocks in zsh, which does not word-split an unquoted
# expansion, so every block runs in both shells
# (skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md).
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md).
# Every fixture root commit carries its own path, so two fixtures made in the
# same second are not one project (scripts/test-fixture-root-collision.sh).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
# The lock block and the stamp verbs act on $CLAUDE_PROJECT_DIR/.claude, so an
# inherited value would point them at a real checkout. run() sets it per fixture.
unset CLAUDE_PROJECT_DIR
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
PM="$repo_root/pre-merge/SKILL.md"
EX="$repo_root/execute/SKILL.md"
for f in "$SC" "$PM" "$EX"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Slices Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

# block <file> <literal> — the first fenced bash block containing <literal>,
# with the fence's own indent (a block inside a list item) stripped.
block() {
    awk -v want="$2" '
        /^ *```bash$/ { buf = ""; on = 1; ind = index($0, "`") - 1; next }
        on && /^ *```$/ { on = 0; if (index(buf, want)) { printf "%s", buf; exit } next }
        on { buf = buf substr($0, ind + 1) "\n" }
    ' "$1"
}

shells="bash"
if command -v zsh >/dev/null 2>&1; then shells="bash zsh"
elif [ -n "${CI:-}" ]; then bad "zsh is on PATH for the zsh arms" "zsh missing and CI is set"
else printf '  SKIP zsh arms: zsh is not on PATH\n'; fi

# The stub answers the two calls Phase 2's sidecar block makes, and records every call.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$1 $2" in
    "pr list") echo "" ;;
    "pr create") echo "https://github.com/acme/stack/pull/7" ;;
    *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
# A sidecar.sh whose `work pr-mode` fails and whose every other verb is the real one.
cat > "$tmp/pr-mode-fails-sc.sh" <<VF
#!/usr/bin/env bash
[ "\$1 \${2:-}" = "work pr-mode" ] && { echo "work pr-mode refused" >&2; exit 1; }
exec bash "$SC" "\$@"
VF
# A sidecar.sh whose `work pr-mode` exits 0 with an answer that is neither
# "pr" nor "none <W-n>": the blocks' last case arm, which no real store reaches.
cat > "$tmp/pr-mode-odd-sc.sh" <<VF
#!/usr/bin/env bash
[ "\$1 \${2:-}" = "work pr-mode" ] && { echo "maybe"; exit 0; }
exec bash "$SC" "\$@"
VF
URL="https://github.com/acme/stack/pull/7"

# shellcheck disable=SC2016  # the needles are the skills' literal text
{
pm_block="$(block "$PM" 'echo "PR opened, but $PR_URL is not recorded on $W"')"
url_block="$(block "$PM" 'PR_URL="<the URL the human gave>"')"
so_block="$(block "$PM" 'work set "$W" pr_mode none')"
mode_block="$(block "$PM" 'Does this branch record Stamp only?')"
lock_block="$(block "$EX" 'review lock kept')"
built_block="$(block "$EX" 'work set "$W" state built')"
}
section "the blocks"
for pair in "pre-merge Phase 2's sidecar PR block:$pm_block" "pre-merge Phase 2's URL block:$url_block" \
            "pre-merge's Stamp only block:$so_block" "pre-merge's pr_mode read before the menu:$mode_block" \
            "execute Step 0's review-lock block:$lock_block" \
            "execute Step 6's built block:$built_block"; do
    if [ -n "${pair#*:}" ]; then ok "${pair%%:*} is found"; else bad "${pair%%:*} is found" "not found"; fi
done

n=0
# mkproj <guest|owned> — a fresh project on a github.com remote with a sidecar,
# on branch stack, whose base main holds the root commit. Sets $P.
mkproj() {
    n=$((n + 1))
    P="$tmp/proj$n"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
    git -C "$P" remote add origin "https://github.com/acme/stack$n.git"
    git -C "$P" update-ref refs/remotes/origin/main main
    git -C "$P" checkout -q -b stack
    git -C "$P" commit -q --allow-empty -m "Add the totals report"
    (cd "$P" && bash "$SC" init --name "stack$n" --mode "$1" --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>"$tmp/init.err") \
        || bad "init the $1 sidecar" "$(cat "$tmp/init.err")"
}
mk() {
    printf 'body\n' > "$tmp/body.md"
    (cd "$P" && bash "$SC" work create "$@" --body-file "$tmp/body.md")
}
field() { (cd "$P" && bash "$SC" work view "$1" --json | jq -r ".$2 // empty"); }
fill() { # <block> <W value> — the placeholders an agent fills, filled
    local b="${1//<this skill\'s directory>\/references\/sidecar.sh/$SC}"
    b="${b//W=\"W-<n>\"/W=\"$2\"}"
    b="${b//W=\"<the W-<n> Phase 1 step 2 named, or empty>\"/W=\"$2\"}"
    b="${b//TITLE=\"<plain title>\"/TITLE=\"Add the totals report\"}"
    b="${b//BASE_BRANCH=\"<sibling slice branch for a stacked PR, else empty>\"/BASE_BRANCH=\"\"}"
    b="${b//PR_URL=\"<the URL the human gave>\"/PR_URL=\"$URL\"}"
    printf '%s' "$b" | awk 'index($0, "Nothing below adds to it.") { print "printf \"Adds the totals report.\\n\" > \"$DESC_FILE\""; next } 1'
}
# run <shell> <block> <W value> — stdout in $out, stderr in $err, exit in $rc.
run() {
    : > "$tmp/calls"
    out="$(cd "$P" && CLAUDE_PROJECT_DIR="${CPD:-$P}" GH_CALLS="$tmp/calls" PATH="$tmp/bin:$PATH" "$1" -c "$(fill "$2" "$3")" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}

for sh in $shells; do
    # -------------------------------------------------------------------------
    section "$sh: /execute Step 6 marks the slice built"

    mkproj guest
    A="$(mk --kind slice)"
    run "$sh" "$built_block" "$A"
    check "$sh: the block exits 0" 0 "$rc"
    check "$sh: an open slice reads built" built "$(field "$A" state)"
    check "$sh: it names the branch" "work item: $A built on stack" "$out"
    run "$sh" "$built_block" "$A"
    check "$sh: a second run leaves it built" built "$(field "$A" state)"
    (cd "$P" && bash "$SC" work close "$A") >/dev/null 2>&1
    run "$sh" "$built_block" "$A"
    check "$sh: a closed slice is left closed" closed "$(field "$A" state)"
    check "$sh: the project tree is untouched" "" "$(git -C "$P" status --porcelain)"
    mkproj owned
    run "$sh" "$built_block" "W-1"
    check "$sh: on the github backend the block exits 0" 0 "$rc"
    check "$sh: on the github backend no work item is read" 1 "$(grep -c 'none on the github backend' <<<"$out")"

    # -------------------------------------------------------------------------
    section "$sh: /pre-merge records one PR on every built slice of the branch"

    mkproj guest
    S1="$(mk --kind slice)"; S2="$(mk --kind slice)"; S3="$(mk --kind slice)"; S4="$(mk --kind slice)"
    (cd "$P" && bash "$SC" work set "$S1" state built && bash "$SC" work set "$S1" branch stack \
        && bash "$SC" work set "$S3" branch stack \
        && bash "$SC" work set "$S4" state built && bash "$SC" work set "$S4" branch elsewhere) >/dev/null 2>&1 \
        || bad "$sh: fixture: slices on the branch" "work set failed"
    run "$sh" "$pm_block" "$S2"
    check "$sh: Phase 2's block exits 0" 0 "$rc"
    check "$sh: Phase 2's block prints the PR URL" "$URL" "$out"
    check "$sh: the item Phase 1 named holds the PR" "$URL" "$(field "$S2" pr)"
    check "$sh: a built slice of the branch holds the same PR" "$URL" "$(field "$S1" pr)"
    check "$sh: an open slice of the branch does not" "" "$(field "$S3" pr)"
    check "$sh: a built slice of another branch does not" "" "$(field "$S4" pr)"
    check "$sh: one PR is opened" 1 "$(grep -c '^pr create' "$tmp/calls")"

    mkproj guest
    S1="$(mk --kind slice)"; S2="$(mk --kind slice)"
    (cd "$P" && bash "$SC" work set "$S1" state built && bash "$SC" work set "$S1" branch stack) >/dev/null 2>&1
    run "$sh" "$url_block" "$S2"
    check "$sh: the URL block exits 0" 0 "$rc"
    check "$sh: the URL block records the PR on the named item" "$URL" "$(field "$S2" pr)"
    check "$sh: the URL block records it on the branch's built slice" "$URL" "$(field "$S1" pr)"
    check "$sh: the URL block calls no gh" "" "$(cat "$tmp/calls")"

    # -------------------------------------------------------------------------
    section "$sh: Stamp only records pr_mode none, and Phase 2 then opens nothing"

    mkproj guest
    S1="$(mk --kind slice)"; S2="$(mk --kind slice)"
    (cd "$P" && bash "$SC" work set "$S1" branch stack && bash "$SC" work set "$S2" branch stack) >/dev/null 2>&1
    run "$sh" "$mode_block" "$S1"
    check "$sh: before Stamp only, the menu read says pr" "pr_mode: pr" "$out"
    run "$sh" "$so_block" "$S1"
    check "$sh: the Stamp only block exits 0" 0 "$rc"
    check "$sh: it records pr_mode none" none "$(field "$S1" pr_mode)"
    check "$sh: it leaves pr empty" "" "$(field "$S1" pr)"
    run "$sh" "$pm_block" "$S1"
    check "$sh: Phase 2 on that item exits 0" 0 "$rc"
    check "$sh: Phase 2 on that item opens no PR and calls no gh" "" "$(cat "$tmp/calls")"
    check "$sh: Phase 2 on that item says why" 1 "$(grep -c 'pr_mode none' <<<"$out")"
    check "$sh: Phase 2 on that item records no pr" "" "$(field "$S1" pr)"
    run "$sh" "$pm_block" "$S2"
    check "$sh: Phase 2 on the branch's next slice opens no PR either" "" "$(cat "$tmp/calls")"
    run "$sh" "$mode_block" "$S1"
    check "$sh: the menu read on that item says none" "pr_mode: none ($S1)" "$out"
    run "$sh" "$mode_block" "$S2"
    check "$sh: the menu read on the branch's next slice says none" "pr_mode: none ($S1)" "$out"
    run "$sh" "$mode_block" ""
    check "$sh: the menu read with no work item finds the branch's" "pr_mode: none ($S1)" "$out"
    git -C "$P" checkout -q -b other
    run "$sh" "$mode_block" ""
    check "$sh: the menu read on another branch says pr" "pr_mode: pr" "$out"
    (cd "$P" && bash "$SC" work set "$S1" branch other && bash "$SC" work close "$S1") >/dev/null 2>&1
    run "$sh" "$mode_block" ""
    check "$sh: a closed item on the branch records nothing for it" "pr_mode: pr" "$out"
    run "$sh" "$mode_block" "$S1"
    check "$sh: …but the named item is read whatever its state" "pr_mode: none ($S1)" "$out"
    (cd "$P" && bash "$SC" work set "$S1" state open && bash "$SC" work set "$S1" branch stack) >/dev/null 2>&1
    git -C "$P" checkout -q stack
    run "$sh" "$so_block" ""
    check "$sh: Stamp only with no work item records nothing and says so" 1 "$rc"
    check "$sh: …naming the missing work item" 1 "$(grep -c 'no work item' <<<"$err")"
    mkproj owned
    run "$sh" "$so_block" "W-1"
    check "$sh: Stamp only on the github stamp backend is refused" 1 "$rc"
    check "$sh: …saying the stamp lives in the PR body there" 1 "$(grep -c 'PR body' <<<"$err")"
    run "$sh" "$mode_block" "W-1"
    check "$sh: the menu read on the github stamp backend says pr" "pr_mode: pr" "$out"

    # -------------------------------------------------------------------------
    # Both Stamp only messages print the command that takes it back. Each one is
    # pulled out of the message as printed and run as written.
    section "$sh: the take-back command each message prints gives the branch its PR back"

    mkproj guest
    S1="$(mk --kind slice)"
    (cd "$P" && bash "$SC" work set "$S1" branch stack) >/dev/null 2>&1 \
        || bad "$sh: fixture: a slice on the branch" "work set failed"
    for which in so pm; do
        run "$sh" "$so_block" "$S1"
        [ "$which" = so ] || run "$sh" "$pm_block" "$S1"
        tb="$(grep -o 'sidecar\.sh work set [^ ]* pr_mode [^ ]*' <<<"$out")"
        check "$sh: the $which block's message prints one take-back command" 1 "$(grep -c . <<<"$tb")"
        read -r -a tb_args <<<"${tb#sidecar.sh }"
        (cd "$P" && bash "$SC" "${tb_args[@]}") >/dev/null 2>"$tmp/tb.err" \
            || bad "$sh: the $which block's take-back command runs" "$(cat "$tmp/tb.err")"
        run "$sh" "$mode_block" "$S1"
        check "$sh: …and after the $which block's command the menu read says pr" "pr_mode: pr" "$out"
    done

    # Phase 2 run on the branch's next slice, while the earlier slice records
    # Stamp only: the command it prints must name the item that records it.
    mkproj guest
    S1="$(mk --kind slice)"; S2="$(mk --kind slice)"
    (cd "$P" && bash "$SC" work set "$S1" branch stack && bash "$SC" work set "$S2" branch stack) >/dev/null 2>&1 \
        || bad "$sh: fixture: two slices on the branch" "work set failed"
    run "$sh" "$so_block" "$S1"
    run "$sh" "$pm_block" "$S2"
    tb="$(grep -o 'sidecar\.sh work set [^ ]* pr_mode [^ ]*' <<<"$out")"
    check "$sh: Phase 2 on the next slice prints one take-back command" 1 "$(grep -c . <<<"$tb")"
    read -r -a tb_args <<<"${tb#sidecar.sh }"
    (cd "$P" && bash "$SC" "${tb_args[@]}") >/dev/null 2>"$tmp/tb.err" \
        || bad "$sh: Phase 2's take-back command on the next slice runs" "$(cat "$tmp/tb.err")"
    run "$sh" "$pm_block" "$S2"
    check "$sh: …and after it Phase 2 on the next slice opens the PR" 1 "$(grep -c '^pr create' "$tmp/calls")"
    check "$sh: …and records it on that slice" "$URL" "$(field "$S2" pr)"

    # -------------------------------------------------------------------------
    # A read that fails is not a "pr" answer: a PR is an outside write (#812).
    section "$sh: a failed pr_mode read opens no PR and answers no menu"

    mkproj guest
    S1="$(mk --kind slice)"; S2="$(mk --kind slice)"
    (cd "$P" && bash "$SC" work set "$S1" branch stack && bash "$SC" work set "$S1" pr_mode none \
        && bash "$SC" work set "$S2" branch stack) >/dev/null 2>&1 \
        || bad "$sh: fixture: a Stamp only slice on the branch" "work set failed"
    WD="$(cd "$P" && bash "$SC" resolve)/work"
    cp "$WD/$S1.md" "$tmp/s1.md"
    { printf 'not frontmatter\n'; cat "$tmp/s1.md"; } > "$WD/$S1.md"
    run "$sh" "$pm_block" "$S2"
    check "$sh: work list fails: Phase 2 exits non-zero" 1 "$rc"
    check "$sh: …opens no PR and calls no gh" "" "$(cat "$tmp/calls")"
    check "$sh: …records no pr" "" "$(field "$S2" pr)"
    check "$sh: …and says the read failed" 1 "$(grep -c 'PR aborted: sidecar.sh work pr-mode failed' <<<"$err")"
    check "$sh: …because the store does not parse" 1 "$(grep -c 'does not parse' <<<"$err")"
    run "$sh" "$mode_block" "$S2"
    check "$sh: work list fails: the menu read exits non-zero" 1 "$rc"
    check "$sh: …answers neither pr nor none" "" "$out"
    check "$sh: …and says pr_mode is unread" 1 "$(grep -c 'pr_mode unread: sidecar.sh work pr-mode failed' <<<"$err")"
    cp "$tmp/s1.md" "$WD/$S1.md"
    # A W naming no work item is not a failed read: it records nothing (as
    # test-guest-footprint.sh pins for Phase 2), and the branch's item still answers.
    run "$sh" "$mode_block" "W-99"
    check "$sh: a W naming no item: the menu read still finds the branch's" "pr_mode: none ($S1)" "$out"
    VSC="$SC"; SC="$tmp/pr-mode-fails-sc.sh"
    run "$sh" "$pm_block" "$S2"
    check "$sh: work pr-mode fails: Phase 2 exits non-zero" 1 "$rc"
    check "$sh: …opens no PR and calls no gh" "" "$(cat "$tmp/calls")"
    check "$sh: …and says the read failed" 1 "$(grep -c 'PR aborted: sidecar.sh work pr-mode failed' <<<"$err")"
    run "$sh" "$mode_block" "$S2"
    check "$sh: work pr-mode fails: the menu read exits non-zero" 1 "$rc"
    check "$sh: …answers neither pr nor none" "" "$out"
    check "$sh: …and says pr_mode is unread" 1 "$(grep -c 'pr_mode unread: sidecar.sh work pr-mode failed' <<<"$err")"
    SC="$tmp/pr-mode-odd-sc.sh"
    run "$sh" "$pm_block" "$S2"
    check "$sh: work pr-mode answers neither pr nor none: Phase 2 exits non-zero" 1 "$rc"
    check "$sh: …opens no PR and calls no gh" "" "$(cat "$tmp/calls")"
    check "$sh: …and names the answer it could not read" 1 "$(grep -c "PR aborted: sidecar.sh work pr-mode answered 'maybe'" <<<"$err")"
    run "$sh" "$mode_block" "$S2"
    check "$sh: work pr-mode answers neither pr nor none: the menu read exits non-zero" 1 "$rc"
    check "$sh: …answers neither pr nor none" "" "$out"
    check "$sh: …and says pr_mode is unread" 1 "$(grep -c "pr_mode unread: sidecar.sh work pr-mode answered 'maybe'" <<<"$err")"
    SC="$VSC"
    check "$sh: …and Phase 2 recorded no pr" "" "$(field "$S2" pr)"

    # -------------------------------------------------------------------------
    section "$sh: /execute Step 0 keeps a review lock whose stamp names this branch"

    mkproj guest
    mkdir -p "$P/.claude"
    printf 'by=x\nat=2026-01-01T00:00:00Z\nhead=%s\n' "$(git -C "$P" rev-parse HEAD)" > "$P/.claude/.review-stamped"
    run "$sh" "$lock_block" ""
    check "$sh: a lock with no stamp for this branch is removed" "" "$(ls -A "$P/.claude")"
    check "$sh: …and the block says it was left over" 1 "$(grep -c 'left over' <<<"$out")"
    printf 'by=x\n' > "$P/.claude/.review-stamped"
    (cd "$P" && bash "$SC" stamp write stack "$(git rev-parse HEAD)") >/dev/null 2>&1 || bad "$sh: fixture: stamp stack" "stamp write failed"
    run "$sh" "$lock_block" ""
    check "$sh: a lock whose stamp names this branch is kept" ".review-stamped" "$(ls -A "$P/.claude")"
    check "$sh: …and the block names stamp release" 1 "$(grep -c 'stamp release stack' <<<"$out")"
    git -C "$P" checkout -q -b next
    run "$sh" "$lock_block" ""
    check "$sh: on another branch the same lock is removed" "" "$(ls -A "$P/.claude")"
    run "$sh" "$lock_block" ""
    check "$sh: with no lock the block prints nothing" "" "$out"
    # A CLAUDE_PROJECT_DIR naming another folder (#812): the block judges the lock in
    # the folder the hook reads and /pre-merge writes, and the stamp release it prints
    # clears that same file. This checkout's own .claude is not the hook's, so it is left.
    O="$tmp/other$n"
    mkdir -p "$O/.claude"
    printf 'by=x\n' > "$O/.claude/.review-stamped"
    git -C "$P" checkout -q stack
    CPD="$O"
    run "$sh" "$lock_block" ""
    check "$sh: CLAUDE_PROJECT_DIR elsewhere: the stamped branch keeps the lock in that folder" yes "$([ -f "$O/.claude/.review-stamped" ] && echo yes)"
    check "$sh: …and prints the stamp release for it" 1 "$(grep -c 'stamp release stack' <<<"$out")"
    rel="$(sed -n 's/.*the human runs: //p' <<<"$out")"
    rel="${rel//<why>/fixture}"
    (cd "$P" && CLAUDE_PROJECT_DIR="$O" bash -c "$rel") >/dev/null 2>"$tmp/rel.err" || bad "$sh: the printed stamp release runs" "$(cat "$tmp/rel.err")"
    check "$sh: …the printed stamp release clears the lock the block kept" "" "$([ -f "$O/.claude/.review-stamped" ] && echo left)"
    check "$sh: …and records the release beside it" yes "$([ -f "$O/.claude/.post-review-edit" ] && echo yes)"
    git -C "$P" checkout -q next
    printf 'by=x\n' > "$O/.claude/.review-stamped"
    printf 'by=x\n' > "$P/.claude/.review-stamped"
    run "$sh" "$lock_block" ""
    CPD=""
    check "$sh: …on an unstamped branch the leftover lock in that folder is removed" "" "$([ -f "$O/.claude/.review-stamped" ] && echo left)"
    check "$sh: …and this checkout's .claude is not judged" yes "$([ -f "$P/.claude/.review-stamped" ] && echo yes)"
    # A CLAUDE_PROJECT_DIR that contains this checkout: a worktree nested in the
    # main checkout, with the variable naming the main checkout. The block names
    # that folder, as the hook does, and never the worktree's own top level.
    M="$P"
    W="$M/wt$n"
    git -C "$M" worktree add -q -b nest "$W" >/dev/null 2>&1 || bad "$sh: fixture: nested worktree" "worktree add failed"
    (cd "$W" && bash "$SC" stamp write nest "$(git rev-parse HEAD)") >/dev/null 2>&1 || bad "$sh: fixture: stamp nest" "stamp write failed"
    rm -f "$M/.claude/.review-stamped"
    printf 'by=x\n' > "$M/.claude/.review-stamped"
    P="$W"; CPD="$M"
    run "$sh" "$lock_block" ""
    check "$sh: CLAUDE_PROJECT_DIR containing the checkout: the stamped branch keeps the lock in that folder" yes "$([ -f "$M/.claude/.review-stamped" ] && echo yes)"
    check "$sh: …and prints the stamp release for this branch" 1 "$(grep -c 'stamp release nest' <<<"$out")"
    check "$sh: …and writes nothing under the worktree's own top level" "" "$([ -e "$W/.claude" ] && echo made)"
    git -C "$W" checkout -q -b nest-next
    run "$sh" "$lock_block" ""
    check "$sh: …on an unstamped branch the leftover lock in that folder is removed" "" "$([ -f "$M/.claude/.review-stamped" ] && echo left)"
    P="$M"; CPD=""
done

# -----------------------------------------------------------------------------
section "the prose says where Stamp only can exist"

# shellcheck disable=SC2016  # the needles are the skill's literal text
{
check "the deferred-PR paragraph offers Stamp only" 1 "$(grep -c '^\*\*While Phase 2 is deferred, lead with the PR\.\*\*.*\*\*Stamp only' "$PM")"
check "the Stamp only menu leads with something other than the PR, /compound, or /closeout" 1 "$(grep -c '^\*\*A branch that records Stamp only gets neither menu\.\*\*.*leave out \*\*Open the PR\*\*, \*\*`/compound` in this PR\*\*, and \*\*`/closeout`\*\*.*Lead with \*\*→ Stop here' "$PM")"
check "it says the option needs the sidecar stamp backend" 1 "$(grep -c '^\*\*While Phase 2 is deferred.*on the `github` backend the stamp lives in the PR body' "$PM")"
}

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
