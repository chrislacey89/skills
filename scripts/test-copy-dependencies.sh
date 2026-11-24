#!/usr/bin/env bash
# test-copy-dependencies.sh — runs the source-location check of
# docs/copy-dependencies.md against fixture copies (#823).
#
# THE DRIFT CLASS. /fix-findings' breaker and the differential check run code in
# a throwaway `git archive` copy, which has no dependency tree. Both used to say
# to symlink the original's tree in, as if a tree were inert. Under a loader that
# finds the project's source from its own real path, a linked tree sends the
# copy's run back to the original checkout's source. The breaker then tests the
# working tree rather than the fix commit, and the differential check's base run
# executes the branch's code and agrees with it on every input. Nothing says so.
#
# THE INCIDENT BEHIND IT. #823 reproduced it with Composer: a copy with `vendor/`
# linked, its class edited to return the wrong value, ran PHPUnit green on the
# original's class. The fixture here needs no PHP: a loader script inside the
# dependency directory finds the project from its own `pwd -P`, the same move.
#
# WHAT THIS PINS.
#   1. The premise: through a linked tree, a resolving loader picks the original
#      checkout's source; through an installed tree, the copy's.
#   2. The block, extracted from the doc, its placeholders filled, and run under
#      bash and zsh: it fails and names the resolved path when the loader
#      resolves outside the copy (including into a sibling whose path shares the
#      copy's prefix), and passes when the tree was installed in the copy, when a
#      linked loader does not resolve its own real path, and when the copy is
#      reached through a symlinked path. A probe that fails, prints nothing, or
#      prints a path that does not exist fails the check.
#   3. /fix-findings and the differential check point at the doc, and each
#      bundled copy matches it.
#
# WHAT THIS DOES NOT PIN. Which probe command fits a given stack; the doc sends
# the author to the stack's own documentation for that.

set -u
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1
doc=docs/copy-dependencies.md

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ "$#" -lt 2 ] || printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

section "the doc carries the source-location block"
block="$(awk '
    /^<!-- copy-check: source-location -->$/ { want = 1; next }
    want && /^```bash$/ { inb = 1; next }
    inb && /^```$/ { exit }
    inb { print }
' "$doc")"
if [ -n "$block" ]; then ok "$doc has the block under its marker"; else bad "$doc has the block under its marker"; fi
placeholder_copy="<the copy's path, as its block printed it>"
placeholder_probe="<a command, run from the copy, whose last line is the path the loader resolved one project source file to>"
for p in "$placeholder_copy" "$placeholder_probe"; do
    if grep -qF -- "$p" <<<"$block"; then ok "the block carries the placeholder [$p]"; else bad "the block carries the placeholder [$p]"; fi
done

# Fixture. The original checkout `orig` has src/foo.sh, which prints "orig", and
# two loaders in deps/: `resolving.sh` finds the project from its own real path,
# as Composer's autoload does through __DIR__; `relative.sh` names the source
# relative to the directory it is run from. A copy's src/foo.sh prints "copy".
make_orig() {
    mkdir -p "$1/src" "$1/deps"
    printf '#!/bin/sh\necho orig\n' > "$1/src/foo.sh"
    # shellcheck disable=SC2016 # expands when the loader runs
    printf '#!/bin/sh\nHERE=$(cd "$(dirname "$0")" && pwd -P)\necho "$(dirname "$HERE")/src/foo.sh"\n' > "$1/deps/resolving.sh"
    printf '#!/bin/sh\necho src/foo.sh\n' > "$1/deps/relative.sh"
}
# make_copy <dir> <link|install>: the copy's own source, with the tree linked or installed.
make_copy() {
    mkdir -p "$1/src"
    printf '#!/bin/sh\necho copy\n' > "$1/src/foo.sh"
    if [ "$2" = link ]; then ln -s "$tmp/orig/deps" "$1/deps"; else cp -R "$tmp/orig/deps" "$1/deps"; fi
}
make_orig "$tmp/orig"
make_copy "$tmp/linked" link
make_copy "$tmp/installed" install
# A sibling whose path starts with the copy's: a prefix match would let it pass.
# The copy is $tmp/pre and its linked tree points into $tmp/pre-orig.
make_orig "$tmp/pre-orig"
make_copy "$tmp/pre" install
rm -rf "$tmp/pre/deps"; ln -s "$tmp/pre-orig/deps" "$tmp/pre/deps"
ln -s "$tmp/installed" "$tmp/via-link"

section "the premise: what a resolving loader runs through each tree"
got="$(cd "$tmp/linked" && sh "$(sh deps/resolving.sh)")"
if [ "$got" = orig ]; then ok "through a linked tree it runs the original's source"; else bad "through a linked tree it runs the original's source" "got [$got]"; fi
got="$(cd "$tmp/installed" && sh "$(sh deps/resolving.sh)")"
if [ "$got" = copy ]; then ok "through an installed tree it runs the copy's source"; else bad "through an installed tree it runs the copy's source" "got [$got]"; fi

fill() {
    local b="$block"
    b="${b//"$placeholder_copy"/$1}"
    b="${b//"$placeholder_probe"/$2}"
    printf '%s\n' "$b" > "$tmp/block.sh"
}
# run_case <shell> <label> <copy> <probe> <pass|fail> [<text stderr must name>]
run_case() {
    fill "$3" "$4"
    out="$("$1" "$tmp/block.sh" 2>"$tmp/err")"; rc=$?
    err="$(cat "$tmp/err")"
    if [ "$5" = pass ]; then
        if [ "$rc" -eq 0 ] && grep -q '^copy check: .*inside the copy' <<<"$out"; then ok "$2"; else bad "$2" "rc=$rc out=[$out] err=[$err]"; fi
    else
        if [ "$rc" -ne 0 ] && grep -q '^copy check failed:' <<<"$err" && { [ "$#" -lt 6 ] || grep -qF -- "$6" <<<"$err"; }; then ok "$2"; else bad "$2" "rc=$rc out=[$out] err=[$err]"; fi
    fi
}

for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf '  SKIP %s not on PATH\n' "$sh"; continue; }
    section "the block, run under $sh"
    run_case "$sh" "a linked resolving loader fails and names the original's file" \
        "$tmp/linked" 'sh deps/resolving.sh' fail "$tmp/orig/src/foo.sh, outside the copy"
    run_case "$sh" "an installed tree passes" \
        "$tmp/installed" 'sh deps/resolving.sh' pass
    run_case "$sh" "a linked loader that does not resolve its own real path passes" \
        "$tmp/linked" 'sh deps/relative.sh' pass
    run_case "$sh" "a sibling sharing the copy's path prefix is outside the copy" \
        "$tmp/pre" 'sh deps/resolving.sh' fail "$tmp/pre-orig/src/foo.sh"
    run_case "$sh" "a copy reached through a symlinked path still passes" \
        "$tmp/via-link" 'sh deps/resolving.sh' pass
    run_case "$sh" "a .. path through a linked folder is resolved by the kernel, not lexically" \
        "$tmp/linked" 'echo deps/../src/foo.sh' fail "$tmp/orig/src/foo.sh, outside the copy"
    run_case "$sh" "a probe that exits nonzero fails" \
        "$tmp/installed" 'sh deps/resolving.sh; exit 3' fail "the probe exited nonzero"
    run_case "$sh" "a probe that prints nothing fails" \
        "$tmp/installed" 'true' fail "printed no path"
    run_case "$sh" "a probe that prints a path that does not exist fails" \
        "$tmp/installed" 'echo nowhere/at/all.sh' fail "does not exist"
    run_case "$sh" "a probe that prints a missing file in a real folder fails" \
        "$tmp/installed" 'echo src/missing.sh' fail "is not an existing file"
    run_case "$sh" "a probe whose only output is whitespace prints no path" \
        "$tmp/installed" 'echo "   "' fail "printed no path"
done

section "the skills point at the doc, and bundle it"
if grep -qF '(references/copy-dependencies.md)' fix-findings/SKILL.md; then ok "fix-findings/SKILL.md points at references/copy-dependencies.md"; else bad "fix-findings/SKILL.md points at references/copy-dependencies.md"; fi
if grep -qF 'source-location check' fix-findings/SKILL.md; then ok "fix-findings/SKILL.md runs the source-location check before the control"; else bad "fix-findings/SKILL.md runs the source-location check before the control"; fi
if grep -qF '(copy-dependencies.md)' docs/differential-check.md; then ok "docs/differential-check.md points at copy-dependencies.md"; else bad "docs/differential-check.md points at copy-dependencies.md"; fi
# coverage: the three skills the manifest bundles docs/copy-dependencies.md into.
for d in execute fix-findings tdd; do
    if cmp -s "$doc" "$d/references/copy-dependencies.md"; then ok "$d bundles the doc"; else bad "$d bundles the doc" "$d/references/copy-dependencies.md is missing or differs; run scripts/sync-skill-references.sh"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
