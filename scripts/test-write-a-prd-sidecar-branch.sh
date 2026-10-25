#!/usr/bin/env bash
# test-write-a-prd-sidecar-branch.sh — extracts the fenced bash blocks of
# /write-a-prd Step 8 and RUNS them against scratch repos (#523).
#
# THE DRIFT CLASS. Step 8 routes where the pitch is saved on `backend prds`.
# Two recorded lessons apply to that block, and prose review caught both once:
#   - patterns/skill-command-blocks-run-one-shell-per-call-2026-10-13.md: every
#     tool call is a fresh shell, so each block must set `SC` and its body file
#     itself. Each block here runs in its own `bash -c`, never concatenated.
#   - architecture-decisions/compat-default-is-every-failures-answer-2026-10-24.md:
#     every `backend` consumer needs a "backend failed" arm, and that arm must
#     not fall back to `gh issue create` (on a guest repo that writes the pitch
#     into the client's tracker) nor exit 0.
#
# Three arms: github (no `work` call, no sidecar written), sidecar (creates
# W-<n>, expands one in place, makes no `gh` call), and a refusing backend
# (a guest sidecar whose sidecar.json is corrupt: exits nonzero, no `gh` call).
# `gh` on PATH is a stub that logs its argv.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SKILL="$repo_root/write-a-prd/SKILL.md"
SC_REAL="$repo_root/init-pipeline/scripts/sidecar.sh"
[ -f "$SKILL" ] || { printf 'FATAL %s is missing\n' "$SKILL"; exit 1; }

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
fatal() { printf 'FATAL %s\n' "$1"; exit 1; }

# The Nth fenced bash block between the Step 8 heading and the pitch template.
block() {
    awk -v want="$1" '
        /^### 8\. Write the pitch/ { in8 = 1; next }
        in8 && /^<pitch-template>/ { exit }
        in8 && /^```bash$/ { n++; on = (n == want); next }
        in8 && /^```$/ { on = 0; next }
        in8 && on { print }
    ' "$SKILL"
}
subst() { sed "s|<this skill's directory>/references/sidecar.sh|$SC_REAL|g"; }

backend_block="$(block 1 | subst)"
create_block="$(block 2 | subst)"
expand_block="$(block 3 | subst)"
[ -n "$backend_block" ] && [ -n "$create_block" ] && [ -n "$expand_block" ] \
    || fatal "Step 8 no longer has three fenced bash blocks (backend, create, expand)"
for b in "$backend_block" "$create_block" "$expand_block"; do
    case "$b" in *"$SC_REAL"*) ;; *) fatal "a Step 8 block does not set SC from the bundled path" ;; esac
done
# shellcheck disable=SC2016  # the pattern is the skill's literal text
case "$backend_block" in *'backend prds'*) ;; *) fatal "block 1 is not the backend prds question" ;; esac
# shellcheck disable=SC2016
case "$create_block" in *'work create --kind prd'*) ;; *) fatal "block 2 is not work create" ;; esac
# shellcheck disable=SC2016
case "$expand_block" in *'work edit'*'maturity prd'*) ;; *) fatal "block 3 is not the expand-in-place edit and set" ;; esac

tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Prd Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

stub="$tmp/bin"; mkdir -p "$stub"
export GH_LOG="$tmp/gh.log"
# shellcheck disable=SC2016  # the stub body is literal sh, expanded when gh runs
printf '#!/bin/sh\necho "$*" >> "$GH_LOG"\nexit 1\n' > "$stub/gh"; chmod +x "$stub/gh"
: > "$GH_LOG"

n=0
mkproj() {
    n=$((n + 1)); P="$tmp/proj$n"
    git init -q "$P"; git -C "$P" commit -q --allow-empty -m "root"
    git -C "$P" remote add origin "$1"
}
# runb <dir> <script> — run one block in its own fresh shell, stub gh first on PATH.
runb() { out="$(cd "$1" && PATH="$stub:$PATH" bash -c "$2" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }

printf '\n=== github: the block names the backend and writes nothing ===\n'
mkproj https://github.com/acme/owned.git
runb "$P" "$backend_block"
check "github: exits 0" 0 "$rc"
check "github: prints the github answer" "prds backend: github" "$out"
check "github: no gh call" "" "$(cat "$GH_LOG")"
check "github: no sidecar written" "no" "$([ -d "$SKILL_KIT_SIDECAR_ROOT" ] && echo yes || echo no)"

printf '\n=== sidecar: create and expand in a fresh shell each, no gh ===\n'
mkproj https://github.com/acme/guest.git
(cd "$P" && bash "$SC_REAL" init --name guest --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || fatal "could not init the guest sidecar fixture"
runb "$P" "$backend_block"
check "sidecar: backend block exits 0" 0 "$rc"
check "sidecar: backend block prints the sidecar answer" "prds backend: sidecar" "$out"
runb "$P" "$create_block"
check "sidecar: create block exits 0 in a fresh shell" 0 "$rc"
check "sidecar: create prints W-1" "W-1" "$out"
check "sidecar: the work item file exists" yes "$([ -f "$SKILL_KIT_SIDECAR_ROOT/guest/work/W-1.md" ] && echo yes || echo no)"
runb "$P" "${expand_block//W-<n>/W-1}"
check "sidecar: expand block exits 0 in a fresh shell" 0 "$rc"
check "sidecar: expand sets maturity prd" 1 "$(grep -c '^maturity: prd' "$SKILL_KIT_SIDECAR_ROOT/guest/work/W-1.md")"
check "sidecar: still one work item (expanded, not duplicated)" 1 "$(find "$SKILL_KIT_SIDECAR_ROOT/guest/work" -name 'W-*.md' | wc -l | tr -d ' ')"
check "sidecar: no gh call at all" "" "$(cat "$GH_LOG")"
check "sidecar: the project tree is untouched" "" "$(git -C "$P" status --porcelain)"

printf '\n=== refusing backend: nonzero, nothing written, no gh ===\n'
mkproj https://github.com/acme/broken.git
(cd "$P" && bash "$SC_REAL" init --name broken --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || fatal "could not init the broken sidecar fixture"
printf '{"keys": [' > "$SKILL_KIT_SIDECAR_ROOT/broken/sidecar.json"
runb "$P" "$backend_block"
check "refused: the block exits nonzero" 1 "$rc"
check "refused: nothing on stdout (not github, not sidecar)" "" "$out"
case "$err" in *"refused"*) ok "refused: the stop line is on stderr" ;; *) bad "refused: the stop line is on stderr" "got [$err]" ;; esac
check "refused: no gh call" "" "$(cat "$GH_LOG")"
check "refused: no work item created" "no" "$([ -f "$SKILL_KIT_SIDECAR_ROOT/broken/work/W-1.md" ] && echo yes || echo no)"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
