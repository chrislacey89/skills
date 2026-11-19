#!/usr/bin/env bash
# test-differential-check.sh — runs the base-copy block of
# docs/differential-check.md against a fixture repo (#744).
#
# THE DRIFT CLASS. A skill's fenced block is copied out and run unsupervised in
# someone else's repo (CLAUDE.md § "Commands a skill documents" rule (b)). The
# differential check's block exports the slice's base commit into a throwaway
# directory. If it silently extracts nothing, or the wrong commit, the
# comparison that follows compares the branch with itself, or with an empty
# tree, and agrees or disagrees for no reason the author can see.
#
# THE INCIDENT BEHIND IT. Two performance changes to sidecar.sh (#742, #743)
# were verified by a green suite; the independent reviewer ran the base and
# branch scripts side by side and found the disagreement the suite could not.
#
# WHAT THIS PINS.
#   1. The block, extracted from the doc, its placeholders filled, and run under
#      bash and zsh, derives BASE_SHA itself from `sidecar.sh range` (nothing is
#      preset) and extracts that commit (not HEAD, not the working tree) into a
#      directory with no .git, and prints its path. With a recorded start that
#      still bounds the slice the copy is that commit; once the base has moved
#      and been merged in, the copy is the merge-base, so landed changes are
#      not reported as disagreements (ancestry-is-not-containment).
#   2. A range that fails aborts with a non-zero exit, prints no copy path, and
#      leaves no temp directory behind.
#   3. /execute Step 4 and /tdd's partition step point at the bundled copy.
#
# WHAT THIS DOES NOT PIN. Whether an author picks inputs that break the new
# mechanism; that is judgment, stated in the doc.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1
doc=docs/differential-check.md
SC="$repo_root/init-pipeline/scripts/sidecar.sh"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ "$#" -lt 2 ] || printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Diff Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

section "the doc carries the base-copy block"
block="$(awk '
    /^```bash$/ { inb = 1; buf = ""; hit = 0; next }
    inb && /^```$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
    inb { buf = buf $0 "\n"; if (index($0, "git archive \"$BASE_SHA\"")) hit = 1 }
' "$doc")"
if [ -n "$block" ]; then ok "$doc has a block that archives \$BASE_SHA"; else bad "$doc has a block that archives \$BASE_SHA"; fi

# Fixture: upstream main has file.txt=old. The clone's feature branch commits
# pre.txt (the slice's recorded start), then changes file.txt to new; the
# working tree changes it again, so each wrong source is distinguishable. Later
# upstream gains base.txt and feature merges it, so the recorded start is still
# an ancestor of HEAD but no longer bounds only this branch.
# mktemp shim: TMPDIR is not honored everywhere (a sandbox can pin it), so the
# leftover check puts the block's temp directory where it can look. Only the
# block's own `mktemp -d` is redirected; sidecar.sh's plain `mktemp` is not.
real_mktemp="$(command -v mktemp)"
mkdir -p "$tmp/shim"
# shellcheck disable=SC2016 # $SHIM_TMP expands when the shim runs
printf '#!/bin/sh\nif [ "$#" -eq 1 ] && [ "$1" = -d ]; then exec "%s" -d "$SHIM_TMP/tmp.XXXXXX"; fi\nexec "%s" "$@"\n' "$real_mktemp" "$real_mktemp" > "$tmp/shim/mktemp"
chmod +x "$tmp/shim/mktemp"

# Builds the fixture afresh for each shell: the moved case merges into it.
build_fixture() {
    U="$tmp/up-$1"; P="$tmp/p-$1"
    git init -q "$U"
    printf 'old\n' > "$U/file.txt"
    git -C "$U" add file.txt
    git -C "$U" commit -q -m "root $U"
    git clone -q "$U" "$P"
    git -C "$P" remote set-head origin main >/dev/null
    git -C "$P" switch -q -c feature
    (cd "$P" && bash "$SC" init --name "diff-$1" --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
        || { bad "init the fixture sidecar"; return 1; }
    printf 'slice\n' > "$tmp/body"
    W="$(cd "$P" && bash "$SC" work create --kind slice --body-file "$tmp/body" 2>/dev/null)"
    printf 'p\n' > "$P/pre.txt"; git -C "$P" add pre.txt; git -C "$P" commit -q -m "before the slice"
    start_sha="$(git -C "$P" rev-parse HEAD)"
    (cd "$P" && bash "$SC" work set "$W" start_sha "$start_sha" >/dev/null 2>&1) || bad "record start_sha (fixture sanity)"
    printf 'new\n' > "$P/file.txt"
    git -C "$P" commit -q -am "branch change"
    printf 'uncommitted\n' > "$P/file.txt"
}

# Fills the doc's placeholders with the fixture's sidecar and a work item id.
fill() {
    local b="$block"
    b="${b//"$placeholder_sc"/$SC}"
    b="${b//"$placeholder_w"/$1}"
    printf '%s' "$b" > "$tmp/block.sh"
}
placeholder_sc="<this skill's directory>/references/sidecar.sh"
placeholder_w="<W-n, or empty>"

for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf '  SKIP %s not on PATH\n' "$sh"; continue; }
    build_fixture "$sh" || continue
    for state in recorded moved; do
        if [ "$state" = moved ]; then
            printf 'b\n' > "$U/base.txt"; git -C "$U" add base.txt; git -C "$U" commit -q -m "base moves"
            git -C "$P" fetch -q origin
            git -C "$P" stash -q -u -m diffcheck 2>/dev/null
            git -C "$P" merge -q --no-edit origin/main >/dev/null 2>&1 || bad "merge the moved base (fixture sanity)"
            git -C "$P" stash pop -q 2>/dev/null
        fi
        section "the block, run under $sh, start $state"
        fill "$W"
        td="$tmp/tmpdir-$sh-$state"; mkdir -p "$td"
        out="$(cd "$P" && PATH="$tmp/shim:$PATH" SHIM_TMP="$td" "$sh" "$tmp/block.sh" 2>"$tmp/err")"; rc=$?
        copy="$(printf '%s\n' "$out" | sed -n 's/^base copy: //p')"
        if [ "$rc" -eq 0 ] && [ -n "$copy" ] && [ -d "$copy" ]; then ok "it exits 0 and prints the copy's path"; else bad "it exits 0 and prints the copy's path" "rc=$rc out=[$out] err=[$(cat "$tmp/err")]"; fi
        got="$(cat "$copy/file.txt" 2>/dev/null)"
        if [ "$got" = old ]; then ok "the copy holds the base side, not HEAD or the working tree"; else bad "the copy holds the base side, not HEAD or the working tree" "file.txt is [$got]"; fi
        if [ -n "$copy" ] && [ ! -e "$copy/.git" ]; then ok "the copy has no .git"; else bad "the copy has no .git"; fi
        if [ "$state" = recorded ]; then
            if [ -f "$copy/pre.txt" ] && [ ! -e "$copy/base.txt" ]; then ok "a recorded start bounds the slice: the copy is that commit"; else bad "a recorded start bounds the slice: the copy is that commit" "pre.txt/base.txt wrong in $copy"; fi
        else
            if [ -f "$copy/base.txt" ]; then ok "a base that moved after the start is in the copy, so landed changes are not disagreements"; else bad "a base that moved after the start is in the copy, so landed changes are not disagreements" "base.txt missing from $copy"; fi
        fi
    done

    section "the block, run under $sh, with a work item that does not exist"
    fill "W-999"
    td="$tmp/tmpdir-bad-$sh"; mkdir -p "$td"
    out="$(cd "$P" && PATH="$tmp/shim:$PATH" SHIM_TMP="$td" "$sh" "$tmp/block.sh" 2>"$tmp/err")"; rc=$?
    if [ "$rc" -ne 0 ]; then ok "a range that fails exits non-zero"; else bad "a range that fails exits non-zero" "rc=0 out=[$out]"; fi
    if ! grep -q '^base copy:' <<<"$out"; then ok "and prints no copy path"; else bad "and prints no copy path" "out=[$out]"; fi
    left="$(find "$td" -mindepth 1 | head -1)"
    if [ -z "$left" ]; then ok "and leaves no temp directory behind"; else bad "and leaves no temp directory behind" "found $left"; fi
done

section "the two skills point at the bundled copy"
# coverage: the two skills the manifest bundles docs/differential-check.md into.
for f in execute/SKILL.md tdd/SKILL.md; do
    if grep -qF '(references/differential-check.md)' "$f"; then ok "$f points at references/differential-check.md"; else bad "$f points at references/differential-check.md"; fi
    d="${f%/SKILL.md}"
    if cmp -s "$doc" "$d/references/differential-check.md"; then ok "$d bundles the doc"; else bad "$d bundles the doc" "$d/references/differential-check.md is missing or differs; run scripts/sync-skill-references.sh"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
