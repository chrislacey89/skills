#!/usr/bin/env bash
# test-handoff-path.sh — runs /handoff Step 3's path block and pins what it
# produces, rather than restating its behavior in prose (#581, #813).
#
# THE DRIFT CLASS. A documented command whose result depends on the machine.
# Step 3 once used `mktemp -t handoff-XXXXXX.md`, which BSD and GNU read
# differently: on macOS every doc came out as `handoff-XXXXXX.md.<random>`
# (#581). The block now computes a path instead of creating a file, in the
# project's sidecar (`sidecar.sh path handoffs`) so the doc survives a restart,
# and in the temp folder when no sidecar answers. Either way the doc must never
# land in the project tree, and two docs must never share a path.
#
# WHAT THIS PINS. The block, extracted from handoff/SKILL.md and run under bash
# (and zsh when installed): with a sidecar it prints a path in the sidecar's
# handoffs/ directory; with none it prints one in $TMPDIR; the path ends in
# `.md`, carries a timestamped name, is outside the project tree, does not
# exist yet (nothing is created until the first write), and leaves the
# project's `git status` empty. The step's prose drops the read-the-empty-file
# step and the stance that a doc should not survive.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
HO="$repo_root/handoff/SKILL.md"
for f in "$SC" "$HO"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Handoff Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

step3="$(awk '/^### 3\./{s=1; print; next} s && /^### /{exit} s{print}' "$HO")"
# The first fenced bash block under "### 3." in handoff/SKILL.md, with the real resolver.
block="$(printf '%s\n' "$step3" | awk '/^```bash$/{on=1; next} on && /^```$/{exit} on{print}')"
block="${block//<this skill\'s directory>\/references\/sidecar.sh/$SC}"

printf '\n=== /handoff Step 3 documents a path block ===\n'
if [ -n "$block" ]; then ok "Step 3 has a fenced bash block"; else bad "Step 3 has a fenced bash block"; fi
check "the block asks sidecar.sh for the handoffs directory" 1 "$(grep -c 'path handoffs' <<<"$block")"
check "the block does not use mktemp" 0 "$(grep -c 'mktemp' <<<"$block")"
check "no prose in handoff/SKILL.md still names mktemp -t" 0 "$(grep -c 'mktemp -t' "$HO")"
check "Step 3 no longer says to read the empty file" 0 "$(grep -ci 'read the path before writing\|the file exists, empty' <<<"$step3")"
check "the skill no longer says surviving the session is not the goal" 0 "$(grep -c 'Surviving the session is not the goal' "$HO")"
check "the commit-the-doc row answers: do not commit it; it survives in the sidecar" 1 \
    "$(grep -c '^| "I.ll commit the handoff doc to the repo so it survives\." | Do not commit it; it already survives, in the sidecar, outside the project tree' "$HO")"
check "the doc still opens with its Written and Reader lines" 2 "$(grep -cE '^(Written|Reader): ' "$HO")"

n=0
mkproj() { # <with-sidecar|none> — a project in $P
    n=$((n + 1))
    P="$tmp/proj$n"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
    git -C "$P" remote add origin "https://github.com/acme/handoff$n.git"
    if [ "$1" = with-sidecar ]; then
        (cd "$P" && bash "$SC" init --name "handoff$n" --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
            || bad "init the sidecar" "init failed"
    fi
}
run_block() { # <shell> — the path the block echoed (last line)
    (cd "$P" && TMPDIR="$tmp/t/" "$1" -c "$block" 2>/dev/null) | tail -n 1
}
mkdir -p "$tmp/t"

check_shell() {
    local sh="$1" a b
    printf '\n=== the block under %s, with a sidecar ===\n' "$sh"
    mkproj with-sidecar
    a="$(run_block "$sh")"
    case "$a" in "$SKILL_KIT_SIDECAR_ROOT/handoff$n/handoffs/"*) ok "$sh: the path is in the sidecar's handoffs/" ;; *) bad "$sh: the path is in the sidecar's handoffs/" "got: $a" ;; esac
    case "$(basename "$a")" in handoff-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].md) ok "$sh: the name is handoff-<date>-<time>.md" ;; *) bad "$sh: the name is handoff-<date>-<time>.md" "got: $a" ;; esac
    if [ -e "$a" ]; then bad "$sh: nothing is created before the first write" "found: $a"; else ok "$sh: nothing is created before the first write"; fi
    if [ -d "$(dirname "$a")" ]; then ok "$sh: the directory exists, so the first write succeeds"; else bad "$sh: the directory exists, so the first write succeeds" "$(dirname "$a")"; fi
    case "$a" in "$P"/*) bad "$sh: the path is outside the project tree" "got: $a" ;; *) ok "$sh: the path is outside the project tree" ;; esac
    check "$sh: the project tree is untouched" "" "$(git -C "$P" status --porcelain)"
    printf '\n=== the block under %s, with no sidecar ===\n' "$sh"
    mkproj none
    a="$(run_block "$sh")"
    case "$a" in "$tmp/t/handoff-"*.md) ok "$sh: the path falls back to \$TMPDIR" ;; *) bad "$sh: the path falls back to \$TMPDIR" "got: $a" ;; esac
    case "$a" in *//*) bad "$sh: no doubled slash from a trailing-slash TMPDIR" "got: $a" ;; *) ok "$sh: no doubled slash from a trailing-slash TMPDIR" ;; esac
    case "$a" in *XXXXXX*) bad "$sh: no literal XXXXXX" "got: $a" ;; *) ok "$sh: no literal XXXXXX" ;; esac
    if [ -e "$a" ]; then bad "$sh: nothing is created in the fallback either" "found: $a"; else ok "$sh: nothing is created in the fallback either"; fi
    check "$sh: the project tree is untouched" "" "$(git -C "$P" status --porcelain)"
    # A doc written in the same second as an earlier one gets its own path.
    : > "$a"
    b="$(run_block "$sh")"
    if [ -n "$b" ] && [ "$b" != "$a" ]; then ok "$sh: a second doc in the same second gets its own path"; else bad "$sh: a second doc in the same second gets its own path" "a=$a b=$b"; fi
}

check_shell bash
if command -v zsh >/dev/null 2>&1; then check_shell zsh
elif [ -n "${CI:-}" ]; then bad "zsh is on PATH for the zsh arm" "zsh missing and CI is set"
else printf '\n  skip zsh not installed\n'; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
