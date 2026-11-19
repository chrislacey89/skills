#!/usr/bin/env bash
# test-walk-commits-range.sh — runs /walk-commits' work-item range block against
# a fixture branch carrying two slices (#586).
#
# THE DRIFT CLASS. A branch can carry several slices of one PRD. Walked by its
# base range, the second slice's walkthrough re-walks the first slice's
# commits. Given a work item id, /walk-commits takes the slice's range from
# `sidecar.sh range`, which prints a two-dot range; the stat needs the merge
# base of its left end and HEAD (what three-dot means), or a base that moved
# after the fork shows up as deletions this branch never made.
#
# WHAT THIS PINS. The block, extracted from walk-commits/SKILL.md and run under
# bash and zsh:
#   1. with an item whose start_sha is recorded, the log and the stat cover
#      only that slice's commit;
#   2. with an item that has no start_sha, both cover the whole branch, and the
#      stat leaves out a file the base gained after the fork.
#
# Fixtures run with a private global git config and their own sidecar root, so
# the runner's identity and real sidecars cannot leak in.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
skill="$repo_root/walk-commits/SKILL.md"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ "$#" -lt 2 ] || printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Walk Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

section "walk-commits carries the work-item range block"
block="$(awk '
    /^```bash$/ { inb = 1; buf = ""; hit = 0; next }
    inb && /^```$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
    inb { buf = buf $0 "\n"; if (index($0, "bash \"$SC\" range \"$W\"")) hit = 1 }
' "$skill")"
if [ -z "$block" ]; then
    bad "walk-commits/SKILL.md has a block that runs sidecar.sh range \"\$W\""
    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi
ok "walk-commits/SKILL.md has a block that runs sidecar.sh range \"\$W\""
placeholder="<this skill's directory>/references/sidecar.sh"
block="${block//"$placeholder"/$SC}"

# Fixture: upstream main has a root commit; the clone branches `feature`,
# commits slice 1 (one.txt), then slice 2 (two.txt). Upstream main then gains
# base.txt, fetched, so origin/main is past the fork point.
git init -q "$tmp/up"
git -C "$tmp/up" commit -q --allow-empty -m "root $tmp/up"
git clone -q "$tmp/up" "$tmp/p"
P="$tmp/p"
git -C "$P" remote set-head origin main >/dev/null
git -C "$P" switch -q -c feature
(cd "$P" && bash "$SC" init --name walk --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || { bad "init the fixture sidecar"; printf '\n%d passed, %d failed\n' "$pass" "$fail"; exit 1; }
printf 'slice\n' > "$tmp/body"
W1="$(cd "$P" && bash "$SC" work create --kind slice --body-file "$tmp/body" 2>/dev/null)"
W2="$(cd "$P" && bash "$SC" work create --kind slice --body-file "$tmp/body" 2>/dev/null)"
printf '1\n' > "$P/one.txt"; git -C "$P" add one.txt; git -C "$P" commit -q -m "slice one"
(cd "$P" && bash "$SC" work set "$W2" start_sha "$(git rev-parse HEAD)" >/dev/null 2>&1) || bad "record W2's start_sha (fixture sanity)"
printf '2\n' > "$P/two.txt"; git -C "$P" add two.txt; git -C "$P" commit -q -m "slice two"
printf 'b\n' > "$tmp/up/base.txt"; git -C "$tmp/up" add base.txt; git -C "$tmp/up" commit -q -m "base moves"
git -C "$P" fetch -q origin

for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || { printf '  SKIP %s not on PATH\n' "$sh"; continue; }
    for w in "$W2" "$W1"; do
        b="${block//W-<n>/$w}"
        out="$(cd "$P" && "$sh" -c "$b" 2>"$tmp/err")"; rc=$?
        subjects="$(printf '%s\n' "$out" | sed -n 's/^[0-9a-f]\{7,\} //p' | tr '\n' '|')"
        files="$(printf '%s\n' "$out" | sed -n 's/^ \([^ ]*\) *|.*/\1/p' | tr '\n' ' ')"
        if [ "$w" = "$W2" ]; then
            section "$sh: an item with a recorded start walks only its slice"
            check "exit 0" 0 "$rc"
            check "the log lists only slice two" "slice two|" "$subjects"
            check "the stat lists only two.txt" "two.txt " "$files"
        else
            section "$sh: an item with no start walks the whole branch"
            check "exit 0" 0 "$rc"
            check "the log lists both slices, newest first" "slice two|slice one|" "$subjects"
            check "the stat lists both files and not the base's newer file" "one.txt two.txt " "$files"
        fi
    done
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
