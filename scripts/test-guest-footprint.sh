#!/usr/bin/env bash
# test-guest-footprint.sh — a guest repo's PR carries no pack text (#526).
#
# THE DRIFT CLASS. On a repo whose `forge.write` lacks `prs`, the pack may open
# a PR but may not write its own content into it: no pack headings, no
# `Closes #`, no `W-` ids, no review stamp (PRD #407, "Footprint"). That
# promise is made in prose in three places, and the text that would break it
# is a fenced block an agent runs in a client's repository. The failure is
# silent in the worst direction: the PR opens, the merge succeeds, and the
# client's history carries the pack's bookkeeping forever.
#
# So the two blocks that hand text to the forge are extracted and RUN, in
# order, against a stubbed `gh` that records every title and body it is
# passed: /pre-merge Phase 2's sidecar block (`gh pr create`) and /closeout
# Step 3's merge block (`gh pr merge --body-file`). Everything they passed is
# grepped for the pack's markers, and the pack's PR headings are read out of
# /pre-merge's own github-backend templates rather than listed here, so a
# heading added there is checked here.
#
# Both blocks are run on a work item and on "none" (no work item to record the
# PR on), and the Phase 2 and Phase 1 lineage blocks are run against a backend
# that answers github and one that refuses: a refusal must stop them before any
# gh call, never fall through to the github templates.
#
# The detector is itself mutation-tested below: the same blocks run with a
# marker planted in the description must turn the check red.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
PM="$repo_root/pre-merge/SKILL.md"
CO="$repo_root/closeout/SKILL.md"
for f in "$SC" "$PM" "$CO"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Footprint Tester"
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

# -----------------------------------------------------------------------------
section "the markers"

# The pack's PR headings: every heading in /pre-merge's github-backend body
# templates, plus the three blocks it writes into a PR body on that backend,
# each of which must still be named in /pre-merge's text.
headings="$(awk '
    /^\*\*PR body template/ { t = 1; next }
    t && /^```markdown$/ { on = 1; next }
    on && /^```$/ { on = 0; t = 0; next }
    on && /^## / { print }
' "$PM" | LC_ALL=C sort -u)"
for h in '## Review Currency' '## Review Disposition Ledger' '## Review Notes'; do
    check "/pre-merge still names the '$h' block" 1 "$(grep -cF -- "$h" "$PM" | awk '{print ($1 > 0)}')"
    headings="$headings
$h"
done
for h in '## PRD' '## Slices' '## Summary'; do
    check "the marker set reads '$h' from /pre-merge's templates" 1 "$(grep -cxF -- "$h" <<<"$headings")"
done

# footprint <file> — print each pack marker the file carries, one per line.
footprint() {
    # `#[0-9]+` covers every closing keyword (Closes, Fixes, Resolves) and a bare
    # reference, any of which points at the client's tracker.
    grep -oE 'reviewed-at|#[0-9]+|W-[0-9]+|loop-pass|loop-judge|review-notes:' "$1"
    while IFS= read -r h; do
        [ -n "$h" ] && grep -xF -- "$h" "$1"
    done <<<"$headings"
    true
}

printf 'Plain words.\n\nCloses #12\n\n## Review Currency\n' > "$tmp/planted"
check "the detector fires on a planted body (Closes # and a pack heading)" 2 "$(footprint "$tmp/planted" | grep -c .)"
printf 'Fix the totals.\n\nThe report summed refunds twice.\n' > "$tmp/plain"
check "the detector is silent on a plain body" "" "$(footprint "$tmp/plain")"
for k in 'Fixes #12' 'resolves #3' 'see #4'; do
    printf 'Plain words. %s\n' "$k" > "$tmp/planted"
    check "the detector fires on [$k]" 1 "$(footprint "$tmp/planted" | grep -c .)"
done

# -----------------------------------------------------------------------------
section "the stubbed gh"

mkdir -p "$tmp/bin" "$tmp/gh"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call, and the file behind every --body-file, under $GH_STUB.
printf '%s\n' "$*" >> "$GH_STUB/calls"
bodyfile=""; prev=""
for a in "$@"; do [ "$prev" = --body-file ] && bodyfile="$a"; prev="$a"; done
case "$1 $2" in
    "pr list") [ -f "$GH_STUB/url" ] && cat "$GH_STUB/url" || echo "" ;;
    "pr create")
        cp "$bodyfile" "$GH_STUB/pr-body"
        echo "Creating pull request for feat into main" >&2
        echo "https://github.com/acme/guest/pull/7" | tee "$GH_STUB/url" ;;
    "pr view") cat "$GH_STUB/pr-body" ;;
    "pr merge") cp "$bodyfile" "$GH_STUB/merge-body" ;;
    *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"

# shellcheck disable=SC2016  # the needles are the skills' literal text
{
pm_block="$(block "$PM" 'work set "$W" pr')"
co_block="$(block "$CO" 'gh pr merge <number> --squash --delete-branch --body-file "$BODY_FILE"')"
}
[ -n "$pm_block" ] || bad "pre-merge/SKILL.md Phase 2 carries the sidecar PR block" "not found"
[ -n "$co_block" ] || bad "closeout/SKILL.md Step 3 carries the merge block" "not found"
check "the Phase 2 block carries exactly one description placeholder" 1 \
    "$(grep -c 'Nothing below adds to it\.' <<<"$pm_block")"

# mkguest <label> <init|noinit> — a fresh project on its own github remote in
# $P, with a guest sidecar and one slice work item (W-1) unless noinit.
n=0
mkguest() {
    n=$((n + 1))
    P="$tmp/proj$n"; export GH_STUB="$tmp/gh$n"; mkdir -p "$GH_STUB"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
    git -C "$P" remote add origin "https://github.com/acme/guest$n.git"
    git -C "$P" checkout -q -b feat
    [ "$2" = noinit ] && return 0
    (cd "$P" && bash "$SC" init --name "guest$n" --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
        || bad "$1: init the guest sidecar" "init failed"
    printf '## Parent PRD\n\nnone\n' > "$tmp/slice.md"
    (cd "$P" && bash "$SC" work create --kind slice --body-file "$tmp/slice.md" >/dev/null 2>&1) \
        || bad "$1: create the work item" "work create failed"
    check "$1: backend stamp answers sidecar on a guest repo" sidecar "$(cd "$P" && bash "$SC" backend stamp)"
}

# run_pm <W value> <sidecar.sh path> <extra description line or empty> — Phase
# 2's block in $P with the stubbed gh; stdout in $pm_out, exit in $pm_rc.
run_pm() {
    printf 'Fix the totals.\n\nThe report summed refunds twice.\n' > "$tmp/desc"
    [ -z "$3" ] || printf '%s\n' "$3" >> "$tmp/desc"
    local b="${pm_block//<this skill\'s directory>\/references\/sidecar.sh/$2}"
    b="${b//W=\"W-<n>\"/W=\"$1\"}"
    b="${b//TITLE=\"<plain title>\"/TITLE=\"Fix the report totals\"}"
    b="$(awk 'index($0, "Nothing below adds to it.") { print "cat \"$DESC_SRC\" > \"$DESC_FILE\""; next } 1' <<<"$b")"
    pm_out="$(cd "$P" && DESC_SRC="$tmp/desc" PATH="$tmp/bin:$PATH" BASE_BRANCH=main bash -c "$b" 2>"$tmp/stderr")"; pm_rc=$?
}

# run_chain <label> <W value> <extra description line or empty> — a fresh guest
# project, then Phase 2's block and Step 3's merge with the stubbed gh.
run_chain() {
    mkguest "$1" init
    run_pm "$2" "$SC" "$3"
    local c="${co_block//<number>/7}"
    (cd "$P" && PATH="$tmp/bin:$PATH" bash -c "$c" >/dev/null 2>>"$tmp/stderr"); co_rc=$?
}

# -----------------------------------------------------------------------------
section "a guest PR, opened and merged, carries no pack text"

run_chain "plain" W-1 ""
check "Phase 2's block exits 0" 0 "$pm_rc"
check "Phase 2's block prints the PR URL" "https://github.com/acme/guest/pull/7" "$pm_out"
check "Step 3's merge block exits 0" 0 "$co_rc"
check "the work item's pr field holds the PR URL" "https://github.com/acme/guest/pull/7" \
    "$(cd "$P" && bash "$SC" work view W-1 --json | jq -r .pr)"
check "the PR body carries no pack marker" "" "$(footprint "$GH_STUB/pr-body")"
check "the squash body carries no pack marker" "" "$(footprint "$GH_STUB/merge-body")"
check "the squash body is the PR's own description" "$(cat "$GH_STUB/pr-body")" "$(cat "$GH_STUB/merge-body")"
grep -E '^pr (create|merge)' "$GH_STUB/calls" > "$tmp/args"
check "no argument to gh pr create or merge carries a pack marker" "" "$(footprint "$tmp/args")"
check "nothing edits the PR body" 0 "$(grep -c '^pr edit' "$GH_STUB/calls")"
check "the project tree is untouched" "" "$(git -C "$P" status --porcelain)"

# A re-run against the PR that now exists records it again and leaves its body alone.
cp "$GH_STUB/pr-body" "$tmp/before"
b="${pm_block//<this skill\'s directory>\/references\/sidecar.sh/$SC}"
b="${b//W=\"W-<n>\"/W=\"W-1\"}"
(cd "$P" && PATH="$tmp/bin:$PATH" BASE_BRANCH=main bash -c "$b" >/dev/null 2>&1)
check "a re-run creates no second PR" 1 "$(grep -c '^pr create' "$GH_STUB/calls")"
check "a re-run leaves the existing PR body as it was" "$(cat "$tmp/before")" "$(cat "$GH_STUB/pr-body")"

# -----------------------------------------------------------------------------
section "no work item: the PR opens, is recorded nowhere, and carries no pack text"

run_chain "none" "" ""
check "with no work item, Phase 2's block exits 0" 0 "$pm_rc"
check "with no work item, it says the PR is recorded nowhere" 1 "$(grep -c 'recorded nowhere' "$tmp/stderr")"
check "with no work item, W-1's pr field stays empty" "" "$(cd "$P" && bash "$SC" work view W-1 --json | jq -r '.pr // empty')"
check "with no work item, the PR body carries no pack marker" "" "$(footprint "$GH_STUB/pr-body")"
check "with no work item, the squash body carries no pack marker" "" "$(footprint "$GH_STUB/merge-body")"

# -----------------------------------------------------------------------------
section "the backend decides: github skips the block, a refusal stops it"

mkguest "github" noinit
check "with no sidecar, backend stamp answers github" github "$(cd "$P" && bash "$SC" backend stamp)"
run_pm W-1 "$SC" ""
check "on github, Phase 2's sidecar block exits 0" 0 "$pm_rc"
check "on github, it calls no gh at all" 0 "$(cat "$GH_STUB/calls" 2>/dev/null | grep -c .)"

# A sidecar.sh whose backend verb refuses (nonzero, nothing printed), the way a
# corrupt sidecar.json makes the real one refuse.
cat > "$tmp/refusing-sc.sh" <<REFUSE
#!/usr/bin/env bash
[ "\$1" = backend ] && { echo "backend refused" >&2; exit 1; }
exec bash "$SC" "\$@"
REFUSE
mkguest "refusing" init
run_pm W-1 "$tmp/refusing-sc.sh" ""
check "on a refused backend, Phase 2's block exits nonzero" 1 "$pm_rc"
check "on a refused backend, it calls no gh at all" 0 "$(cat "$GH_STUB/calls" 2>/dev/null | grep -c .)"
check "on a refused backend, it says it is not guessing" 1 "$(grep -c 'not guessing' "$tmp/stderr")"

# -----------------------------------------------------------------------------
section "Phase 1's lineage block reads the boundary maps from the work items"

# shellcheck disable=SC2016  # the needle is the skill's literal text
lin_block="$(block "$PM" 'lineage aborted: cannot read $W')"
[ -n "$lin_block" ] || bad "pre-merge/SKILL.md Phase 1 carries the sidecar lineage block" "not found"
case "$lin_block" in *'gh '*) bad "the lineage block calls no gh" "found gh" ;; *) ok "the lineage block calls no gh" ;; esac
mkguest "lineage" noinit
(cd "$P" && bash "$SC" init --name "guest$n" --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || bad "lineage: init the guest sidecar" "init failed"
printf '## Problem\n\nx\n' > "$tmp/lprd.md"
printf '## Boundary Map\n\n### Produces\n\n- the %s thing\n' one > "$tmp/ls1.md"
printf '## Boundary Map\n\n### Produces\n\n- the %s thing\n' two > "$tmp/ls2.md"
(cd "$P" && bash "$SC" work create --kind prd --body-file "$tmp/lprd.md" >/dev/null)                    # W-1
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --body-file "$tmp/ls1.md" >/dev/null)     # W-2
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --body-file "$tmp/ls2.md" >/dev/null)     # W-3
lin_shells="bash"
command -v zsh >/dev/null 2>&1 && lin_shells="bash zsh"
for sh in $lin_shells; do
    for w in W-2 W-1; do
        b="${lin_block//<this skill\'s directory>\/references\/sidecar.sh/$SC}"
        b="${b//W=\"W-<n>\"/W=\"$w\"}"
        out="$(cd "$P" && "$sh" -c "$b" 2>/dev/null)"; rc=$?
        check "lineage from $w ($sh) exits 0" 0 "$rc"
        check "lineage from $w ($sh) prints the PRD and both slices" "W-1 W-2 W-3" \
            "$(printf '%s\n' "$out" | sed -n 's/^# \(W-[0-9]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
        check "lineage from $w ($sh) prints both boundary maps" 2 "$(grep -c '^- the .* thing$' <<<"$out")"
    done
done
b="${lin_block//<this skill\'s directory>\/references\/sidecar.sh/$tmp\/refusing-sc.sh}"
b="${b//W=\"W-<n>\"/W=\"W-2\"}"
(cd "$P" && bash -c "$b" >/dev/null 2>&1); rc=$?
check "lineage on a refused backend exits nonzero" 1 "$rc"

# -----------------------------------------------------------------------------
section "mutation: a marker planted in the description turns the check red"

for m in 'Closes #12' 'Fixes #12' 'see #4' 'Implements W-1' '<!-- reviewed-at: 0123456789abcdef0123456789abcdef01234567 -->' '## Review Notes'; do
    run_chain "planted [$m]" W-1 "$m"
    check "planted [$m]: the PR body's footprint is non-empty" 1 "$(footprint "$GH_STUB/pr-body" | grep -c . | awk '{print ($1 > 0)}')"
    check "planted [$m]: the squash body's footprint is non-empty" 1 "$(footprint "$GH_STUB/merge-body" | grep -c . | awk '{print ($1 > 0)}')"
done

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
