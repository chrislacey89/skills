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
#   4. /execute's `# fresh-tree` block (#712), executed: the generic signal
#      (toplevel is not the primary checkout) stands down only in a tree with
#      no commits past the base and nothing uncommitted; the env var still
#      stands down on its own in a tree with history.
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

section "/execute: the generic signal stands down only in a fresh tree (#712)"
# THE DRIFT CLASS, second half. Under `auto`, /execute also stood down on the
# generic signal alone (toplevel is not the primary checkout). A worktree this
# pipeline made satisfies that too, so a second session started inside another
# session's worktree read "already isolated", skipped rule 3's stale-branch
# stop, and worked in place on someone else's slice. The generic signal now
# counts only in a fresh tree: no commits past the base, nothing uncommitted.
# The env-var signal above is unchanged and still stands down on its own.
extract_marked() {
    awk -v mark="$2" '
        /^```bash$/ { inb = 1; buf = ""; hit = 0; next }
        inb && /^```$/ { if (hit) { printf "%s", buf; exit } inb = 0; next }
        inb { buf = buf $0 "\n"; if (index($0, mark) == 1) hit = 1 }
    ' "$1"
}
fresh_block="$(extract_marked execute/SKILL.md '# fresh-tree')"
if [ -z "$fresh_block" ]; then
    bad "execute/SKILL.md has a # fresh-tree block" "no \`\`\`bash fence containing '# fresh-tree' found"
elif [ -z "$reference" ]; then
    bad "host-signal block available to execute" "no site carried one"
else
    ok "execute/SKILL.md has a # fresh-tree block"
    ft="$(mktemp -d)"
    ft="$(cd "$ft" && pwd -P)"
    trap 'rm -rf "${scratch:-}" "$ft"' EXIT
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$ft/gitconfig"
    git config --file "$GIT_CONFIG_GLOBAL" user.name "Fresh Tester"
    git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
    git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
    export SKILL_KIT_SIDECAR_ROOT="$ft/sidecars"
    placeholder="<this skill's directory>/references/sidecar.sh"
    printf '%s' "${fresh_block//"$placeholder"/$repo_root/init-pipeline/scripts/sidecar.sh}" > "$ft/fresh.sh"
    if grep -qF "$placeholder" "$ft/fresh.sh" || ! grep -qF "$repo_root/init-pipeline/scripts/sidecar.sh" "$ft/fresh.sh"; then
        bad "the block reads sidecar.sh through the placeholder" "placeholder '$placeholder' not found once and substituted"
    fi
    printf '%s' "$reference" > "$ft/host.sh"

    git init -q "$ft/main"
    git -C "$ft/main" commit -q --allow-empty -m "root $ft/main"
    git -C "$ft/main" worktree add -q -b fresh-task "$ft/wt-fresh" main
    git -C "$ft/main" worktree add -q -b committed-task "$ft/wt-committed" main
    git -C "$ft/wt-committed" commit -q --allow-empty -m "someone else's slice"
    git -C "$ft/main" worktree add -q -b dirty-task "$ft/wt-dirty" main
    printf 'edit\n' > "$ft/wt-dirty/file.txt"
    # No base branch resolves here (no origin, none of the fallback names), so
    # base-ref refuses and the block must not read the tree as fresh.
    git init -q -b nobase "$ft/nobase"
    git -C "$ft/nobase" commit -q --allow-empty -m "root $ft/nobase"
    git -C "$ft/nobase" worktree add -q -b nobase-task "$ft/wt-nobase" nobase

    tree_of() { (cd "$1" && env -u CONDUCTOR_WORKSPACE_PATH -u CODESPACES -u REMOTE_CONTAINERS bash "$ft/fresh.sh" 2>/dev/null) | sed -n 's/^tree=\([a-z]*\).*/\1/p'; }
    expect_tree() {
        local want="$1" label="$2" got
        got="$(tree_of "$3")"
        if [ "$got" = "$want" ]; then ok "$label -> tree=$want"; else bad "$label -> tree=$want" "got '$got'"; fi
    }
    expect_tree primary "the primary checkout"                         "$ft/main"
    expect_tree fresh   "a pipeline-made worktree with nothing in it"  "$ft/wt-fresh"
    expect_tree used    "a worktree with a commit past the base"       "$ft/wt-committed"
    expect_tree used    "a worktree with an uncommitted file"          "$ft/wt-dirty"
    expect_tree unknown "a fresh worktree whose base cannot be read"   "$ft/wt-nobase"

    got="$(cd "$ft/wt-committed" && env -u CODESPACES -u REMOTE_CONTAINERS CONDUCTOR_WORKSPACE_PATH="$ft/wt-committed" bash "$ft/host.sh" | sed -n 's/^host_owned=//p')"
    if [ "$got" = yes ]; then
        ok "a host env var naming a worktree with commits still stands down -> host_owned=yes"
    else
        bad "a host env var naming a worktree with commits still stands down -> host_owned=yes" "got '$got'"
    fi
fi

# The prose that acts on the block's verdict: rule 3's stop names the way out,
# and the restated sites point at /execute Step 0 rather than restating the
# old generic rule.
# shellcheck disable=SC2016 # the backticks are literal Markdown
if grep -qF '`worktree.provisioning`' < <(grep -E '^3\. ' execute/SKILL.md); then
    ok "rule 3's stop names worktree.provisioning as the way out"
else
    bad "rule 3's stop names worktree.provisioning as the way out" "no '\`worktree.provisioning\`' on execute/SKILL.md's rule 3 line"
fi
# coverage: the two sites #712 named as restating /execute's auto rule.
for f in init-pipeline/SKILL.md SYSTEM-OVERVIEW.md; do
    if grep -qE 'or the current tree is not the repo.s primary working tree|or "toplevel ≠ primary working tree\."' "$f"; then
        bad "$f no longer restates the generic stand-down" "it still names toplevel ≠ primary as a stand-down on its own"
    else
        ok "$f no longer restates the generic stand-down"
    fi
done

section "/init-pipeline § 7 does not scaffold host into the committed file"
if grep -qF 'merge {"worktree":{"provisioning":"host"}}' init-pipeline/SKILL.md; then
    bad "no scaffold write of provisioning: host" "init-pipeline/SKILL.md still merges it into .claude/settings.json"
else
    ok "no scaffold write of provisioning: host"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
