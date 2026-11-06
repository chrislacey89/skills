#!/usr/bin/env bash
# test-hackathon-blocks.sh — contract test for the fenced bash blocks in
# hackathon/SKILL.md § State.
#
# THE DRIFT CLASS. A skill tells a downstream agent to run a fenced block, and
# the agent's shell is fresh for each block. A block that leans on a variable
# or a step from an earlier block fails only in the field. The incident
# (PR #713, review finding 6): the commit block used $SC without setting it, so
# in a fresh shell it died with exit 127 while every block read fine. Related
# findings pinned here: a remote added in setup must reach `init` (1), a
# resolve failure that is not a SIDECAR MISS must not run init (9), and resume
# must pick the newest dossier and exit 1 with none (10). CLAUDE.md
# § "Commands a skill documents" rule (b) is the standing response.
#
# WHAT THIS DOES. Extracts the blocks from the real SKILL.md by a stable anchor
# line (not a line number), substitutes only the documented placeholders, and
# runs EACH block in its OWN `env -i` shell (bash, and zsh when installed)
# inside a scratch repo, with HOME and SKILL_KIT_SIDECAR_ROOT in scratch dirs.
#
# APPARATUS. The commit block with its SC= line stripped must exit 127, and a
# resolve block whose failure is not a miss must stop before init; a runner
# that cannot go red on those measures nothing.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
skill="$repo_root/hackathon/SKILL.md"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$2', got '$3')"; fi; }

[[ -f "$skill" ]] || { echo "no $skill"; exit 1; }

# Print the column-0 fenced bash block containing $1 (fixed string); fail unless
# exactly one block does.
block() {
    local anchor="$1" out n
    out="$(awk -v a="$anchor" '
        /^```bash$/ { inb = 1; buf = ""; hit = 0; next }
        /^```$/ && inb { if (hit) { printf "%s\001", buf }; inb = 0; next }
        inb { buf = buf $0 "\n"; if (index($0, a)) hit = 1 }' "$skill")"
    n="$(printf '%s' "$out" | tr -cd '\001' | wc -c | tr -d ' ')"
    if [[ "$n" != 1 ]]; then echo "ANCHOR-ERROR: '$anchor' matched $n blocks" >&2; return 1; fi
    printf '%s' "$out" | tr -d '\001'
}

b_setup="$(block 'git init -q')" || exit 1
b_init="$(block ' init --name ')" || exit 1
b_path="$(block 'echo "dossier:')" || exit 1
b_commit="$(block ' commit -- ')" || exit 1
b_resume="$(block 'hackathon-*.md')" || exit 1

skilldir="$tmp/skilldir"
mkdir -p "$skilldir"
ln -s "$repo_root/hackathon/references" "$skilldir/references"
REMOTE="https://github.com/example/event-repo.git"

sub() { # placeholder substitution: stdin -> stdout
    sed -e "s|<this skill's directory>|$skilldir|g" \
        -e "s|<event repo remote URL>|$REMOTE|g" \
        -e "s|<owned\|guest>|${MODE:-owned}|g" \
        -e "s|<suggested name from the miss line>|${NAME:-hack-fixture}|g" \
        -e "s|<dossier path>|${DOSSIER:-/nonexistent}|g" \
        -e "s|<phase name>|Phase 0|g"
}

# run_block reads $P (fixture id) from the caller; one sidecar root per shell.
# run_block <shell> <dir> <block-text>  -> sets rc, out, err (fresh env -i shell)
run_block() {
    local sh="$1" dir="$2" text="$3" f="$tmp/blk.$$.sh"
    printf '%s\n' "$text" | sub >"$f"
    out="$(cd "$dir" && env -i PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" HOME="$tmp/home" \
        SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars-$P" GIT_CONFIG_GLOBAL="$tmp/home/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
        "$sh" "$f" 2>"$tmp/err")"
    rc=$?
    err="$(cat "$tmp/err")"
}

run_shell() {
    local sh="$1" repo="$tmp/$2/event"
    P="$2"
    echo "== sequence in $sh"
    REMOTE="https://github.com/example/event-repo-$P.git"
    mkdir -p "$repo" "$tmp/home" "$tmp/sidecars-$P"
    printf '[user]\n\tname = t\n\temail = t@example.com\n' >"$tmp/home/.gitconfig"

    run_block "$sh" "$repo" "$b_setup"
    check "[$P] setup exits 0 (miss is expected)" 0 "$rc"
    case "$err" in *"SIDECAR MISS"*) ok "[$P] setup reports SIDECAR MISS" ;; *) bad "[$P] setup reports SIDECAR MISS: $err" ;; esac
    check "[$P] setup recorded the remote" "$REMOTE" "$(git -C "$repo" remote get-url origin)"
    check "[$P] setup made no commit" 0 "$(git -C "$repo" rev-list --all 2>/dev/null | wc -l | tr -d ' ')"
    NAME="$(printf '%s\n' "$err" | sed -n 's/.*--name \([^ ]*\).*/\1/p' | head -n1)"
    : "${NAME:=hack-$P}"

    MODE=owned NAME="$NAME" run_block "$sh" "$repo" "$b_init"
    check "[$P] init exits 0" 0 "$rc"; [[ $rc == 0 ]] || echo "$err"
    # shellcheck disable=SC2016 # $SC is expanded by the block's own shell
    run_block "$sh" "$repo" "$(printf 'SC="%s/references/sidecar.sh"\nbash "$SC" backend stamp' "$skilldir")"
    check "[$P] backend stamp answers github after init (finding 1)" github "$out"

    run_block "$sh" "$repo" "$b_setup"
    check "[$P] setup re-run is a hit, exits 0" 0 "$rc"

    run_block "$sh" "$repo" "$b_path"
    check "[$P] path exits 0" 0 "$rc"
    dossier="${out#dossier: }"
    rdir="$(dirname "$dossier")"
    mkdir -p "$rdir"

    run_block "$sh" "$repo" "$b_resume"
    check "[$P] resume with no dossier exits 1 (finding 10)" 1 "$rc"

    printf -- '---\nphase: choose\n---\nold\n' >"$rdir/hackathon-2026-01-01.md"
    printf -- '---\nphase: shape\n---\nnew\n' >"$dossier"
    run_block "$sh" "$repo" "$b_resume"
    check "[$P] resume exits 0 with dossiers" 0 "$rc"
    case "$out" in *"hackathon-2026-01-01.md"*) bad "[$P] resume printed the old dossier first" ;; *"$(basename "$dossier")"*) ok "[$P] resume picks the newest dossier" ;; *) bad "[$P] resume output: $out" ;; esac

    DOSSIER="$dossier" run_block "$sh" "$repo" "$b_commit"
    check "[$P] commit exits 0 in a fresh shell (finding 6)" 0 "$rc"; [[ $rc == 0 ]] || echo "$err"
}

shells=(bash)
if command -v zsh >/dev/null 2>&1; then shells+=(zsh); else echo "SKIP zsh: not installed"; fi
for sh in "${shells[@]}"; do run_shell "$sh" "$sh"; done

echo "== apparatus (must go red)"
P=apparatus
repo="$tmp/app/event"; mkdir -p "$repo"
( cd "$repo" && git init -q )
stripped="$(printf '%s\n' "$b_commit" | grep -v '^SC=')"
[[ "$stripped" != "$b_commit" ]] || bad "commit block has no SC= line to strip"
DOSSIER=/x run_block bash "$repo" "$stripped"
check "commit block without SC= exits 127" 127 "$rc"

# Finding 1: without the remote-add line, init records `none` and the stamp
# routes to the sidecar, so the github assertion above can fail.
P=norem; repo="$tmp/norem/event"; mkdir -p "$repo" "$tmp/home" "$tmp/sidecars-norem"
printf '[user]\n\tname = t\n\temail = t@example.com\n' >"$tmp/home/.gitconfig"
run_block bash "$repo" "$(printf '%s\n' "$b_setup" | grep -v 'git remote add')"
MODE=owned NAME=norem run_block bash "$repo" "$b_init"
# shellcheck disable=SC2016
run_block bash "$repo" "$(printf 'SC="%s/references/sidecar.sh"\nbash "$SC" backend stamp' "$skilldir")"
check "setup without the remote-add line makes the stamp answer sidecar" sidecar "$out"
P=apparatus; repo="$tmp/app/event"

# A resolve failure that is not a miss must stop before init (finding 9): run
# the setup block against a stub resolver that fails without a MISS line.
stubdir="$tmp/stub"; mkdir -p "$stubdir/references"
printf '#!/bin/sh\necho "sidecar.sh: boom" >&2\nexit 2\n' >"$stubdir/references/sidecar.sh"
f="$tmp/fail.sh"; printf '%s\n' "$b_setup" | sub | sed "s|$skilldir|$stubdir|g" >"$f"
out="$(cd "$repo" && env -i PATH="/usr/bin:/bin:/opt/homebrew/bin" HOME="$tmp/home" \
    GIT_CONFIG_GLOBAL="$tmp/home/.gitconfig" bash "$f" 2>"$tmp/err")"; rc=$?
check "non-miss resolve failure exits 1 (finding 9)" 1 "$rc"
if grep -q 'without a SIDECAR MISS line' "$tmp/err"; then ok "non-miss failure is relayed, init not offered"; else bad "non-miss relay: $(cat "$tmp/err")"; fi

echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
