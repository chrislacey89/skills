#!/usr/bin/env bash
# test-prd-to-issues-sidecar-branch.sh — extracts the sidecar-backend bash
# blocks of /prd-to-issues §§1, 7, 8, 9 and RUNS them against scratch repos (#524).
#
# THE DRIFT CLASS. Decomposition on a guest repo is prose a downstream agent
# copies and runs unsupervised. The same two lessons as the /write-a-prd branch
# (#523) apply: every block runs in a fresh shell, so each one sets `SC` itself,
# and a refusing `backend` must neither fall back to `gh` nor exit 0. #524 adds
# three behaviors only a run can show: the §7 read-back reports a prose/field
# blocker mismatch, §8's `decomposed_into` holds only the latest ids, and §9
# picks the lowest-numbered unblocked slice of THIS decomposition or reports a
# cycle. `gh` on PATH is a stub that logs its argv; no arm may call it.
#
# SHELLS. Agents run these blocks in zsh as often as bash, and the two split
# unquoted expansions differently (`${X:+--flag "$X"}` stays one word, `for id in
# $LIST` runs once over a newline-joined list in zsh). The suite therefore re-runs
# itself once per shell, each arm on fresh fixtures. A missing zsh prints a
# visible SKIP line locally, and fails the suite when CI is set, so a runner
# without zsh cannot turn the zsh arm into a silent pass.
#
# Blocks are selected by content (the ones that set SC from the bundled path),
# not by position, because §§7 and 9 also carry the GitHub path's bash blocks.

set -u
if [ -z "${PTI_SHELL:-}" ]; then
    arms_rc=0
    PTI_SHELL=bash bash "$0" || arms_rc=1
    if command -v zsh >/dev/null 2>&1; then
        PTI_SHELL=zsh bash "$0" || arms_rc=1
    elif [ -n "${CI:-}" ]; then
        printf '\nFAIL zsh arm: zsh is not on PATH and CI is set, so the blocks were not run under zsh\n'
        arms_rc=1
    else
        printf '\nSKIP zsh arm: zsh is not on PATH, so the blocks were not run under zsh\n'
    fi
    exit "$arms_rc"
fi
printf '\n##### blocks run under: %s #####\n' "$PTI_SHELL"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SKILL="$repo_root/prd-to-issues/SKILL.md"
SC_REAL="$repo_root/init-pipeline/scripts/sidecar.sh"
[ -f "$SKILL" ] || { printf 'FATAL %s is missing\n' "$SKILL"; exit 1; }

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
fatal() { printf 'FATAL %s\n' "$1"; exit 1; }

# The Nth fenced bash block that sets SC from the bundled resolver.
block() {
    awk -v want="$1" '
        /^```bash$/ { buf = ""; on = 1; next }
        on && /^```$/ {
            on = 0
            if (buf ~ /<this skill.s directory>\/references\/sidecar\.sh/) { n++; if (n == want) { printf "%s", buf; exit } }
            next
        }
        on { buf = buf $0 "\n" }
    ' "$SKILL"
}
subst() { sed "s|<this skill's directory>/references/sidecar.sh|$SC_REAL|g"; }

backend_block="$(block 1 | subst)"
view_block="$(block 2 | subst)"
create_block="$(block 3 | subst)"
reconcile_block="$(block 4 | subst)"
set_block="$(block 5 | subst)"
dependents_block="$(block 6 | subst)"
next_block="$(block 7 | subst)"
[ -z "$(block 8)" ] || fatal "more than seven sidecar blocks; update this suite's block map"
# shellcheck disable=SC2016  # the patterns are the skill's literal text
{
case "$backend_block"   in *'backend slices'*) ;; *) fatal "block 1 is not the backend slices question" ;; esac
case "$view_block"      in *'work view "$PRD" --json'*) ;; *) fatal "block 2 is not the PRD read" ;; esac
case "$create_block"    in *'work create "$@"'*) ;; *) fatal "block 3 is not the slice create" ;; esac
case "$create_block"    in *'set -- --kind slice --parent "$PRD"'*) ;; *) fatal "block 3 is not the slice create" ;; esac
case "$reconcile_block" in *'MISMATCH'*) ;; *) fatal "block 4 is not the blocked_by reconcile" ;; esac
case "$set_block"       in *'decomposed_into "$SLICES"'*) ;; *) fatal "block 5 is not the decomposed_into set" ;; esac
case "$dependents_block" in *'OLD="W-<closed>"'*) ;; *) fatal "block 6 is not the dependents check" ;; esac
case "$next_block"      in *'--unblocked'*'/execute'*) ;; *) fatal "block 7 is not the next-slice pick" ;; esac
}
for b in "$backend_block" "$view_block" "$create_block" "$reconcile_block" "$set_block" "$dependents_block" "$next_block"; do
    case "$b" in *gh\ *) fatal "a sidecar block calls gh" ;; esac
done

tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Pti Tester"
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
    git init -q "$P"; git -C "$P" commit -q --allow-empty -m "root $P"
    git -C "$P" remote add origin "$1"
}
runb() { out="$(cd "$1" && PATH="$stub:$PATH" "$PTI_SHELL" -c "$2" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"; }
field() { (cd "$P" && bash "$SC_REAL" work view "$1" --json) | jq -r "$2"; }

# slice <prd> <blocked_by csv> <milestone> <prose blocker ids>: run the §7 create
# block with its placeholders filled; the body's ## Blocked by names the prose ids.
# An optional fifth argument is the body itself (a replacement's, read from the
# dependent it supersedes), used instead of the generated one.
slice() {
    local b="$create_block" body prose
    # shellcheck disable=SC2086  # split on purpose: one line per id
    if [ -n "$4" ]; then prose="$(printf -- '- Blocked by %s\n' ${4//,/ })"; else prose="None — can start immediately"; fi
    body="$(printf '## Parent PRD\n\n%s\n\n## What to Build\n\nA slice.\n\n## Blocked by\n\n%s\n\n## Consumes\n\n- From %s: the shared module\n\n## User Stories Addressed\n\n- User story 2' "$1" "$prose" "${4##*,}")"
    [ -z "${5:-}" ] || body="$5"
    b="${b//PRD=\"W-<prd>\"/PRD=\"$1\"}"
    b="${b//BLOCKED_BY=\"\"/BLOCKED_BY=\"$2\"}"
    b="${b//MILESTONE=\"\"/MILESTONE=\"$3\"}"
    b="${b//<the slice body, from the issue template below>/$body}"
    runb "$P" "$b"
}

printf '\n=== github: the backend block names github and writes nothing ===\n'
mkproj https://github.com/acme/owned.git
runb "$P" "$backend_block"
check "github: exits 0" 0 "$rc"
check "github: prints the github answer" "slices backend: github" "$out"
check "github: no sidecar written" no "$([ -d "$SKILL_KIT_SIDECAR_ROOT" ] && echo yes || echo no)"

printf '\n=== sidecar: §1 reads the PRD ===\n'
mkproj https://github.com/acme/guest.git
(cd "$P" && bash "$SC_REAL" init --name guest --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || fatal "could not init the guest sidecar fixture"
runb "$P" "$backend_block"
check "sidecar: backend block prints the sidecar answer" "slices backend: sidecar" "$out"
printf 'the pitch\n' > "$tmp/pitch"
check "sidecar: seed PRD W-1" W-1 "$(cd "$P" && bash "$SC_REAL" work create --kind prd --milestone "Big batch" --body-file "$tmp/pitch" 2>/dev/null)"
runb "$P" "${view_block//W-<n>/W-1}"
check "§1: view block exits 0" 0 "$rc"
check "§1: view shows kind prd" prd "$(jq -r .kind <<<"$out")"
check "§1: view shows the milestone string" "Big batch" "$(jq -r .milestone <<<"$out")"

printf '\n=== sidecar: §7 creates slices in dependency order ===\n'
slice W-1 "" "Big batch" ""
check "§7: first slice is W-2" W-2 "$out"
slice W-1 W-2 "Big batch" W-2
check "§7: second slice is W-3" W-3 "$out"
slice W-1 W-2,W-3 "Big batch" W-2,W-3
check "§7: QA slice is W-4" W-4 "$out"
check "§7: W-4 parent" W-1 "$(field W-4 .parent)"
check "§7: QA slice blocked by every other slice" "W-2,W-3" "$(field W-4 '.blocked_by | join(",")')"
check "§7: milestone string copied onto the slice" "Big batch" "$(field W-3 .milestone)"
check "§7: W-2 has no blockers" "" "$(field W-2 '.blocked_by // [] | join(",")')"
check "§7: the body carries the W- parent, not #N" 1 "$(field W-2 .body | grep -cx 'W-1')"
slice W-1 W-99 "" W-99
check "§7: a blocker that does not exist yet is refused" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"

printf '\n=== sidecar: §7 read-back reconciles prose against the field ===\n'
for id in W-2 W-3 W-4; do
    runb "$P" "${reconcile_block//W-<slice>/$id}"
    check "§7: $id matches" 0 "$rc"
done
check "§7: match line names the set" "match W-4: [W-2,W-3]" "$out"
printf 'the other pitch\n' > "$tmp/pitch2"
check "sidecar: seed PRD W-5 for the mismatch fixture" W-5 "$(cd "$P" && bash "$SC_REAL" work create --kind prd --body-file "$tmp/pitch2" 2>/dev/null)"
slice W-5 W-3 "" W-2
check "§7: mismatch fixture is W-6" W-6 "$out"
runb "$P" "${reconcile_block//W-<slice>/W-6}"
check "§7: a mismatch exits 1" 1 "$rc"
check "§7: the mismatch is reported on stderr" "MISMATCH W-6: blocked_by=[W-3] prose=[W-2]" "$err"
slice W-5 W-3 "" ""
runb "$P" "${reconcile_block//W-<slice>/W-7}"
check "§7: a field blocker missing from the prose is a mismatch" 1 "$rc"

printf '\n=== sidecar: §8 records decomposed_into, replaced on re-decomposition ===\n'
s8() { local b="${set_block//PRD=\"W-<prd>\"/PRD=\"$1\"}"; runb "$P" "${b//SLICES=\"W-<a>,W-<b>\"/SLICES=\"$2\"}"; }
s8 W-1 W-2,W-3,W-4
check "§8: set exits 0" 0 "$rc"
check "§8: decomposed_into holds the slices" "W-2,W-3,W-4" "$(field W-1 '.decomposed_into | join(",")')"

printf '\n=== sidecar: §9 picks the first unblocked slice of this decomposition ===\n'
s9() { runb "$P" "${next_block//PRD=\"W-<prd>\"/PRD=\"$1\"}"; }
s9 W-1
check "§9: exits 0" 0 "$rc"
check "§9: lowest-numbered unblocked slice" "**Next session:** /execute W-2" "$out"
(cd "$P" && bash "$SC_REAL" work close W-2 >/dev/null 2>&1) || fatal "could not close W-2"
s9 W-1
check "§9: a closed blocker does not gate" "**Next session:** /execute W-3" "$out"

# Re-decompose W-1: W-8 replaces W-3. The superseded W-3 is closed, which un-gates
# W-4 (the QA slice) unless the dependents check finds it and it is re-created.
slice W-1 "" "Big batch" ""
check "re-decompose: new slice W-8" W-8 "$out"
(cd "$P" && bash "$SC_REAL" work close W-3 --superseded-by W-8 >/dev/null 2>&1) || fatal "could not close W-3"
case "$(cd "$P" && bash "$SC_REAL" work list --parent W-1 --unblocked)" in
    *W-4*) ok "re-decompose: closing W-3 alone leaves the QA slice W-4 unblocked (the hazard)" ;;
    *) bad "re-decompose: the hazard fixture" "W-4 was not unblocked after closing W-3" ;;
esac
deps_of() { local b="${dependents_block//PRD=\"W-<prd>\"/PRD=\"W-1\"}"; runb "$P" "${b//OLD=\"W-<closed>\"/OLD=\"$1\"}"; }
deps_of W-3
check "§8: the dependents check names the QA slice" "W-4" "$out"
# Follow §8 literally: the replacement's body is the dependent's own body with the
# closed id swapped for its replacement, and the §7 read-back runs on it.
swapped="$(field W-4 .body | perl -pe 's/\bW-3\b/W-8/g')"
case "$swapped" in *W-3*) fatal "the id swap left W-3 in the body" ;; esac
slice W-1 W-2,W-8 "Big batch" W-2,W-8 "$swapped"
check "re-decompose: re-created QA slice is W-9" W-9 "$out"
runb "$P" "${reconcile_block//W-<slice>/W-9}"
check "§8: the §7 read-back matches on the replacement" "match W-9: [W-2,W-8]" "$out"
check "§8: the replacement body no longer names the closed slice" 0 "$(field W-9 .body | grep -c 'W-3')"
check "§8: the replacement body's Consumes names the new id" 1 "$(field W-9 .body | grep -c 'From W-8:')"
(cd "$P" && bash "$SC_REAL" work close W-4 --superseded-by W-9 >/dev/null 2>&1) || fatal "could not close W-4"
deps_of W-4
check "§8: nothing depends on the closed QA slice, so the check ends" "" "$out"
deps_of W-3
check "§8: nothing open names W-3 after the re-create" "" "$out"
s8 W-1 W-8,W-9
check "re-decompose: decomposed_into holds only the new ids" "W-8,W-9" "$(field W-1 '.decomposed_into | join(",")')"
case "$(cd "$P" && bash "$SC_REAL" work list --parent W-1 --unblocked)" in
    *W-9*) bad "§9: the re-created QA slice waits for W-8" "W-9 was listed unblocked" ;;
    *) ok "§9: the re-created QA slice waits for W-8" ;;
esac
s9 W-1
check "§9: scoped to decomposed_into, not the parent's older slices" "**Next session:** /execute W-8" "$out"

# A decomposition whose only slice waits on an open slice outside it.
slice W-5 W-7 "" W-7
check "cycle fixture: slice waiting on an open W-7" W-10 "$out"
s8 W-5 W-10
s9 W-5
check "§9: none unblocked exits 1" 1 "$rc"
check "§9: prints no handoff line" "" "$out"
case "$err" in *"dependency cycle"*) ok "§9: reports the cycle" ;; *) bad "§9: reports the cycle" "got [$err]" ;; esac
printf 'third pitch\n' > "$tmp/pitch3"
W9="$(cd "$P" && bash "$SC_REAL" work create --kind prd --body-file "$tmp/pitch3" 2>/dev/null)"
s9 "$W9"
check "§9: an undecomposed PRD exits 1" 1 "$rc"
case "$err" in *"run §8 first"*) ok "§9: names §8 for an empty decomposed_into" ;; *) bad "§9: names §8 for an empty decomposed_into" "got [$err]" ;; esac

check "sidecar: no gh call at all" "" "$(cat "$GH_LOG")"
check "sidecar: the project tree is untouched" "" "$(git -C "$P" status --porcelain)"

printf '\n=== refusing backend: nonzero, nothing on stdout, no gh ===\n'
mkproj https://github.com/acme/broken.git
(cd "$P" && bash "$SC_REAL" init --name broken --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || fatal "could not init the broken sidecar fixture"
printf '{"keys": [' > "$SKILL_KIT_SIDECAR_ROOT/broken/sidecar.json"
runb "$P" "$backend_block"
check "refused: the block exits nonzero" 1 "$rc"
check "refused: nothing on stdout" "" "$out"
case "$err" in *"refused"*) ok "refused: the stop line is on stderr" ;; *) bad "refused: the stop line is on stderr" "got [$err]" ;; esac
check "refused: no gh call" "" "$(cat "$GH_LOG")"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
