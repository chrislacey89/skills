#!/usr/bin/env bash
# test-handoff-mktemp.sh — runs /handoff Step 3's path block and pins what it
# produces, rather than restating mktemp's behavior in prose.
#
# THE DRIFT CLASS. A documented command that behaves differently on BSD and GNU
# userland. Step 3 used to say `mktemp -t handoff-XXXXXX.md`; on macOS, `-t`
# takes a prefix and appends its own suffix, so every doc came out as
# `handoff-XXXXXX.md.<random>`: literal X's, no `.md` (#581). Linux CI never saw
# it, because GNU mktemp fills the X's in.
#
# WHAT THIS PINS. The block, extracted from handoff/SKILL.md and run under bash
# (and zsh when installed), prints a path that exists, ends in `.md`, contains
# no literal XXXXXX, sits outside the repo, and differs between two runs. It
# runs on whatever mktemp the machine has, so the macOS reading is pinned on a
# Mac and the GNU reading in CI.

set -u
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

# The first fenced bash block under "### 3." in handoff/SKILL.md.
block="$(awk '/^### 3\./{s=1; next} s && /^### /{exit} s && /^```bash$/{on=1; next} on && /^```$/{exit} on{print}' handoff/SKILL.md)"

printf '\n=== /handoff Step 3 documents a path block ===\n'
if [ -n "$block" ]; then ok "Step 3 has a fenced bash block"; else bad "Step 3 has a fenced bash block"; fi
if grep -q -- 'mktemp -t' <<<"$block"; then
    bad "the block does not use mktemp -t" "-t is the flag BSD and GNU read differently"
else
    ok "the block does not use mktemp -t"
fi
if grep -n 'mktemp -t' handoff/SKILL.md >/dev/null; then
    bad "no prose in handoff/SKILL.md still names mktemp -t" "$(grep -n 'mktemp -t' handoff/SKILL.md)"
else
    ok "no prose in handoff/SKILL.md still names mktemp -t"
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

run_block() { # <shell> -> prints the path the block echoed (last line)
    TMPDIR="$scratch/" "$1" -c "$block" | tail -n 1
}

check_shell() {
    sh_name="$1"
    printf '\n=== the block under %s ===\n' "$sh_name"
    a="$(run_block "$sh_name")"; b="$(run_block "$sh_name")"
    case "$a" in *.md) ok "$sh_name: path ends in .md" ;; *) bad "$sh_name: path ends in .md" "got: $a" ;; esac
    case "$a" in *XXXXXX*) bad "$sh_name: no literal XXXXXX" "got: $a" ;; *) ok "$sh_name: no literal XXXXXX" ;; esac
    if [ -f "$a" ]; then ok "$sh_name: the file exists"; else bad "$sh_name: the file exists" "got: $a"; fi
    if [ -e "${a%.md}" ]; then bad "$sh_name: no extensionless twin left behind" "found: ${a%.md}"; else ok "$sh_name: no extensionless twin left behind"; fi
    case "$a" in "$repo_root"/*) bad "$sh_name: path is outside the repo" "got: $a" ;; *) ok "$sh_name: path is outside the repo" ;; esac
    case "$a" in *//*) bad "$sh_name: no doubled slash from a trailing-slash TMPDIR" "got: $a" ;; *) ok "$sh_name: no doubled slash from a trailing-slash TMPDIR" ;; esac
    if [ -n "$a" ] && [ "$a" != "$b" ]; then ok "$sh_name: two runs give two paths"; else bad "$sh_name: two runs give two paths" "a=$a b=$b"; fi
}

check_shell bash
if command -v zsh >/dev/null 2>&1; then check_shell zsh; else printf '\n  skip zsh not installed\n'; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
