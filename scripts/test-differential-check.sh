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
#   1. The block, extracted from the doc and run under bash and zsh, extracts
#      the commit BASE_SHA names (not HEAD, not the working tree) into a
#      directory with no .git, and prints its path.
#   2. A BASE_SHA that resolves nothing aborts with a non-zero exit, prints no
#      copy path, and leaves no temp directory behind.
#   3. /execute Step 4 and /tdd's partition step point at the bundled copy.
#
# WHAT THIS DOES NOT PIN. Whether an author picks inputs that break the new
# mechanism; that is judgment, stated in the doc.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1
doc=docs/differential-check.md

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ "$#" -lt 2 ] || printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
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
printf '%s' "$block" > "$tmp/block.sh"

# Fixture: base commit has file.txt=old; the branch head changes it to new and
# the working tree changes it again, so each wrong source is distinguishable.
P="$tmp/proj"
git init -q "$P"
printf 'old\n' > "$P/file.txt"
git -C "$P" add file.txt
git -C "$P" commit -q -m "base $P"
base_sha="$(git -C "$P" rev-parse HEAD)"
printf 'new\n' > "$P/file.txt"
git -C "$P" commit -q -am "branch change"
printf 'uncommitted\n' > "$P/file.txt"

# mktemp shim: TMPDIR is not honored everywhere (a sandbox can pin it), so the
# leftover check puts the block's temp directory where it can look.
real_mktemp="$(command -v mktemp)"
mkdir -p "$tmp/shim"
# shellcheck disable=SC2016 # $SHIM_TMP expands when the shim runs
printf '#!/bin/sh\nexec "%s" -d "$SHIM_TMP/tmp.XXXXXX"\n' "$real_mktemp" > "$tmp/shim/mktemp"
chmod +x "$tmp/shim/mktemp"

for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf '  SKIP %s not on PATH\n' "$sh"; continue; }
    section "the block, run under $sh"
    td="$tmp/tmpdir-$sh"; mkdir -p "$td"
    out="$(cd "$P" && PATH="$tmp/shim:$PATH" SHIM_TMP="$td" BASE_SHA="$base_sha" "$sh" "$tmp/block.sh" 2>"$tmp/err")"; rc=$?
    copy="$(printf '%s\n' "$out" | sed -n 's/^base copy: //p')"
    if [ "$rc" -eq 0 ] && [ -n "$copy" ] && [ -d "$copy" ]; then ok "it exits 0 and prints the copy's path"; else bad "it exits 0 and prints the copy's path" "rc=$rc out=[$out] err=[$(cat "$tmp/err")]"; fi
    got="$(cat "$copy/file.txt" 2>/dev/null)"
    if [ "$got" = old ]; then ok "the copy holds the base commit, not HEAD or the working tree"; else bad "the copy holds the base commit, not HEAD or the working tree" "file.txt is [$got]"; fi
    if [ -n "$copy" ] && [ ! -e "$copy/.git" ]; then ok "the copy has no .git"; else bad "the copy has no .git"; fi

    td="$tmp/tmpdir-bad-$sh"; mkdir -p "$td"
    out="$(cd "$P" && PATH="$tmp/shim:$PATH" SHIM_TMP="$td" BASE_SHA=0000000000000000000000000000000000000000 "$sh" "$tmp/block.sh" 2>"$tmp/err")"; rc=$?
    if [ "$rc" -ne 0 ]; then ok "a BASE_SHA that resolves nothing exits non-zero"; else bad "a BASE_SHA that resolves nothing exits non-zero" "rc=0 out=[$out]"; fi
    if ! printf '%s' "$out" | grep -q '^base copy:'; then ok "and prints no copy path"; else bad "and prints no copy path" "out=[$out]"; fi
    left="$(find "$td" -mindepth 1 | head -1)"
    if [ -z "$left" ]; then ok "and leaves no temp directory behind"; else bad "and leaves no temp directory behind" "found $left"; fi
done

section "the two skills point at the bundled copy"
for f in execute/SKILL.md tdd/SKILL.md; do
    if grep -qF '(references/differential-check.md)' "$f"; then ok "$f points at references/differential-check.md"; else bad "$f points at references/differential-check.md"; fi
    d="${f%/SKILL.md}"
    if cmp -s "$doc" "$d/references/differential-check.md"; then ok "$d bundles the doc"; else bad "$d bundles the doc" "$d/references/differential-check.md is missing or differs; run scripts/sync-skill-references.sh"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
