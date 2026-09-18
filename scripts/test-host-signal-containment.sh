#!/usr/bin/env bash
# test-host-signal-containment.sh — a host env var counts as isolation only
# when it describes the tree the skill is standing in.
#
# THE DRIFT CLASS. Four skills read "is this repo host-provisioned?" off the
# environment: /execute Step 0 (stand down from provisioning), /closeout Step 0
# (cede teardown), /lfg's branch rule, and /init-pipeline § 7 (which used to
# commit the answer to .claude/settings.json). Each tested the env var for
# presence and nothing else. Presence answers "is there a host workspace
# somewhere in this shell's ancestry", not "is THIS tree that workspace".
#
# THE INCIDENT BEHIND IT. #378: during the first /lfg feature-path run (#372),
# /init-pipeline ran in an ordinary primary checkout started from a plain
# Terminal, with CONDUCTOR_WORKSPACE_PATH leaked into the shell and naming a
# workspace of a different repository. § 7 as written would have committed
# `worktree.provisioning: "host"` for a repo the host had never seen; /execute
# would have stood down there and worked in place on whatever branch was
# checked out, and /closeout would have ceded teardown to nobody.
#
# WHAT THIS PINS.
#   1. Every site carries the same `# host-signal` block, byte-identical, so
#      the four readings cannot drift apart.
#   2. That block, executed, says yes when CONDUCTOR_WORKSPACE_PATH contains
#      the current toplevel and no when it names some other directory —
#      including a sibling whose path merely shares a string prefix.
#   3. /init-pipeline § 7 no longer scaffolds `host` into the committed file.
#
# WHAT THIS DOES NOT PIN. CODESPACES and REMOTE_CONTAINERS are still read for
# presence: they carry no path to compare, and they are container-scoped, so a
# shell that sees them is inside the container whose repos they describe. That
# is an argument, not a check.

set -euo pipefail

# A caller that reached this suite via a git hook has GIT_DIR and friends set;
# the scratch repos below would inherit them. Unset before any git call.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ "$#" -gt 1 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}

sites=(execute/SKILL.md closeout/SKILL.md lfg/SKILL.md init-pipeline/SKILL.md)

# Print the first ```bash fence in $1 that contains a `# host-signal` line.
extract_block() {
    awk '
        /^```bash$/ { inb = 1; buf = ""; hit = 0; next }
        inb && /^```$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
        inb { buf = buf $0 "\n"; if ($0 ~ /^# host-signal/) hit = 1 }
    ' "$1"
}

section "every site carries the host-signal block"
reference=""
for f in "${sites[@]}"; do
    block="$(extract_block "$f")"
    if [ -z "$block" ]; then
        bad "$f has a # host-signal block" "no \`\`\`bash fence containing '# host-signal' found"
        continue
    fi
    ok "$f has a # host-signal block"
    if [ -z "$reference" ]; then
        reference="$block"
    elif [ "$block" = "$reference" ]; then
        ok "$f block is byte-identical to ${sites[0]}'s"
    else
        bad "$f block is byte-identical to ${sites[0]}'s" \
            "$(diff <(printf '%s\n' "$reference") <(printf '%s\n' "$block") | head -20)"
    fi
done

section "the block answers for this tree, not for the shell"
if [ -z "$reference" ]; then
    bad "block available to execute" "no site carried one"
else
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT
    scratch="$(cd "$scratch" && pwd -P)"
    mkdir -p "$scratch/ws" "$scratch/repo" "$scratch/repo-other" "$scratch/elsewhere"
    git init -q "$scratch/repo"
    git init -q "$scratch/ws"
    git init -q "$scratch/repo-other"
    printf '%s' "$reference" > "$scratch/block.sh"

    # run_block <cwd> <env assignments...> — prints the block's host_owned value.
    run_block() {
        local dir="$1"; shift
        (cd "$dir" && env -u CONDUCTOR_WORKSPACE_PATH -u CODESPACES -u REMOTE_CONTAINERS \
            "$@" bash "$scratch/block.sh") | sed -n 's/^host_owned=//p'
    }

    expect() {
        local want="$1" label="$2"; shift 2
        local got
        got="$(run_block "$@")"
        if [ "$got" = "$want" ]; then ok "$label -> $want"; else bad "$label -> $want" "got '$got'"; fi
    }

    expect no  "no host var at all"                        "$scratch/repo"
    expect yes "var names this toplevel"                   "$scratch/repo" CONDUCTOR_WORKSPACE_PATH="$scratch/repo"
    expect yes "var names this toplevel with trailing /"   "$scratch/repo" CONDUCTOR_WORKSPACE_PATH="$scratch/repo/"
    expect yes "var names a directory containing it"       "$scratch/repo" CONDUCTOR_WORKSPACE_PATH="$scratch"
    expect no  "var leaked from another repo (#378)"       "$scratch/repo" CONDUCTOR_WORKSPACE_PATH="$scratch/ws"
    expect no  "var names an unrelated directory"          "$scratch/repo" CONDUCTOR_WORKSPACE_PATH="$scratch/elsewhere"
    expect no  "var names a sibling sharing a prefix"      "$scratch/repo-other" CONDUCTOR_WORKSPACE_PATH="$scratch/repo"
    expect no  "var names a path that does not exist"      "$scratch/repo" CONDUCTOR_WORKSPACE_PATH="$scratch/gone"
    expect yes "CODESPACES present"                        "$scratch/repo" CODESPACES=true
    expect yes "REMOTE_CONTAINERS present"                 "$scratch/repo" REMOTE_CONTAINERS=true
fi

section "/init-pipeline § 7 does not scaffold host into the committed file"
if grep -qF 'merge {"worktree":{"provisioning":"host"}}' init-pipeline/SKILL.md; then
    bad "no scaffold write of provisioning: host" "init-pipeline/SKILL.md still merges it into .claude/settings.json"
else
    ok "no scaffold write of provisioning: host"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
