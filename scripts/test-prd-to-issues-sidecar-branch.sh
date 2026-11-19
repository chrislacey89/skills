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
# cycle. #564 replaced §8's close-and-re-create with an in-place rewrite of each
# dependent's blocked_by, so the re-decomposition fixtures run §8's dependents
# check (every open item, any parent; a failed read stops it) and its rewrite
# block, and #562 adds a two-unblocked tiebreak, the real issue template through
# the §7 read-back, §8's step order read from the prose, and the CI zsh step.
# `gh` on PATH is a stub that logs its argv; no arm may call it.
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
    # CI installs zsh in a workflow step; that step must exist and run before
    # this suite, or CI reaches the FAIL branch below on every run (#562).
    wf="$(cd "$(dirname "$0")/.." && pwd -P)/.github/workflows/validate-skills.yml"
    zl="$(grep -n 'name: Install zsh' "$wf" | head -n 1 | cut -d: -f1)"
    sl="$(grep -n 'run: bash scripts/test-prd-to-issues-sidecar-branch.sh' "$wf" | head -n 1 | cut -d: -f1)"
    if [ -n "$zl" ] && [ -n "$sl" ] && [ "$zl" -lt "$sl" ]; then
        printf '  ok   CI installs zsh before it runs this suite\n'
    else
        printf '  FAIL CI installs zsh before it runs this suite\n       Install zsh at line [%s], this suite at line [%s] in %s\n' "$zl" "$sl" "$wf"
        arms_rc=1
    fi
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
rewrite_block="$(block 7 | subst)"
next_block="$(block 8 | subst)"
[ -z "$(block 9)" ] || fatal "more than eight sidecar blocks; update this suite's block map"
# shellcheck disable=SC2016  # the patterns are the skill's literal text
{
case "$backend_block"   in *'backend slices'*) ;; *) fatal "block 1 is not the backend slices question" ;; esac
case "$view_block"      in *'work view "$PRD" --json'*) ;; *) fatal "block 2 is not the PRD read" ;; esac
case "$create_block"    in *'work create "$@"'*) ;; *) fatal "block 3 is not the slice create" ;; esac
case "$create_block"    in *'set -- --kind slice --parent "$PRD"'*) ;; *) fatal "block 3 is not the slice create" ;; esac
case "$reconcile_block" in *'MISMATCH'*) ;; *) fatal "block 4 is not the blocked_by reconcile" ;; esac
case "$set_block"       in *'decomposed_into "$SLICES"'*) ;; *) fatal "block 5 is not the decomposed_into set" ;; esac
case "$dependents_block" in *'OLD="W-<old>"'*) ;; *) fatal "block 6 is not the dependents check" ;; esac
case "$rewrite_block"   in *'blocked_by "$BLOCKED_BY"'*) ;; *) fatal "block 7 is not the dependent rewrite" ;; esac
case "$next_block"      in *'--unblocked'*'/execute'*) ;; *) fatal "block 8 is not the next-slice pick" ;; esac
}
for b in "$backend_block" "$view_block" "$create_block" "$reconcile_block" "$set_block" "$dependents_block" "$rewrite_block" "$next_block"; do
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

# Re-decompose W-1 (§8): W-8 replaces W-3. Closing W-3 alone would un-gate the
# QA slice W-4, so the procedure rewrites W-4's edge in place before W-3 closes.
slice W-1 "" "Big batch" ""
check "re-decompose: new slice W-8" W-8 "$out"
deps_of() { runb "$P" "${dependents_block//OLD=\"W-<old>\"/OLD=\"$1\"}"; }
# rw <id> <blocked_by> <body>: the §8 rewrite block with its placeholders filled.
rw() {
    local b="${rewrite_block//ID=\"W-<dependent>\"/ID=\"$1\"}"
    b="${b//BLOCKED_BY=\"W-<a>,W-<b>\"/BLOCKED_BY=\"$2\"}"
    runb "$P" "${b//<the dependent\'s body, with its ids changed and its \#\# Re-decomposed lines added>/$3}"
}
count_items() { find "$SKILL_KIT_SIDECAR_ROOT/guest/work" -name 'W-*.md' | wc -l | tr -d ' '; }
deps_of W-3
# W-6 and W-7 sit under the other PRD, W-5, and are blocked by W-3 too.
check "§8: the dependents check names the QA slice and the other PRD's dependents" "W-4 W-2,W-3
W-6 W-3
W-7 W-3" "$out"
items_before="$(count_items)"
# A body that only swaps ids can be shorter than the old one; work edit refuses
# it, and the block stops before it touches blocked_by.
short="$(field W-4 .body | perl -pe 's/\bW-3\b/W-8/g; s/^- Blocked by W-2\n//')"
rw W-4 W-2,W-8 "$short"
check "§8: a shorter body is refused" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
check "§8: a refused body leaves blocked_by alone" "W-2,W-3" "$(field W-4 '.blocked_by | join(",")')"
swapped="$(field W-4 .body | perl -pe 's/\bW-3\b/W-8/g')"$'\n\n## Re-decomposed\n\n- W-3 replaced by W-8'
rw W-4 W-2,W-8 "$swapped"
check "§8: the rewrite block exits 0" 0 "$rc"
check "§8: the dependent's blocked_by is rewritten in place" "W-2,W-8" "$(field W-4 '.blocked_by | join(",")')"
runb "$P" "${reconcile_block//W-<slice>/W-4}"
check "§8: the §7 read-back matches on the rewritten dependent" "match W-4: [W-2,W-8]" "$out"
check "§8: the rewritten body no longer names the superseded slice in Consumes" 0 "$(field W-4 .body | grep -c 'From W-3:')"
check "§8: the rewrite creates no work item" "$items_before" "$(count_items)"
check "§8: the dependent stays open" open "$(field W-4 .state)"
for d in W-6 W-7; do
    rw "$d" W-8 "$(field "$d" .body)"$'\n\n## Re-decomposed\n\n- W-3 replaced by W-8'
    check "§8: the other PRD's dependent $d is rewritten" "W-8" "$(field "$d" '.blocked_by | join(",")')"
done
(cd "$P" && bash "$SC_REAL" work close W-3 --superseded-by W-8 >/dev/null 2>&1) || fatal "could not close W-3"
deps_of W-3
check "§8: the re-run check prints nothing once every dependent is rewritten" "" "$out"
s8 W-1 W-4,W-8
check "re-decompose: decomposed_into holds only the open slices" "W-4,W-8" "$(field W-1 '.decomposed_into | join(",")')"
case "$(cd "$P" && bash "$SC_REAL" work list --parent W-1 --unblocked)" in
    *W-4*) bad "§9: the QA slice waits for the replacement W-8" "W-4 was listed unblocked" ;;
    *) ok "§9: the QA slice waits for the replacement W-8" ;;
esac
s9 W-1
check "§9: scoped to decomposed_into, not the parent's older slices" "**Next session:** /execute W-8" "$out"

# A decomposition whose only slice waits on an open slice outside it.
slice W-5 W-7 "" W-7
check "cycle fixture: slice waiting on an open W-7" W-9 "$out"
s8 W-5 W-9
s9 W-5
check "§9: none unblocked exits 1" 1 "$rc"
check "§9: prints no handoff line" "" "$out"
case "$err" in *"dependency cycle"*) ok "§9: reports the cycle" ;; *) bad "§9: reports the cycle" "got [$err]" ;; esac
printf 'third pitch\n' > "$tmp/pitch3"
W9="$(cd "$P" && bash "$SC_REAL" work create --kind prd --body-file "$tmp/pitch3" 2>/dev/null)"
s9 "$W9"
check "§9: an undecomposed PRD exits 1" 1 "$rc"
case "$err" in *"run §8 first"*) ok "§9: names §8 for an empty decomposed_into" ;; *) bad "§9: names §8 for an empty decomposed_into" "got [$err]" ;; esac

# A split, a dependent under another PRD, and a dependent of a dependent (#563).
# Slices A, B (blocked by A) and QA (blocked by A, B) under PQ; X under PX is
# blocked by A. A is split into R1 and R2. Every dependent of A is rewritten in
# place, A is closed without --superseded-by (it names one id), and nothing
# else is created or closed.
printf 'fourth pitch\n' > "$tmp/pitch4"
PQ="$(cd "$P" && bash "$SC_REAL" work create --kind prd --body-file "$tmp/pitch4" 2>/dev/null)"
PX="$(cd "$P" && bash "$SC_REAL" work create --kind prd --body-file "$tmp/pitch4" 2>/dev/null)"
slice "$PQ" "" "" ""; SA="$out"
slice "$PQ" "$SA" "" "$SA"; SB="$out"
slice "$PQ" "$SA,$SB" "" "$SA,$SB"; SQ="$out"
slice "$PX" "$SA" "" "$SA"; SX="$out"
slice "$PQ" "" "" ""; R1="$out"
slice "$PQ" "" "" ""; R2="$out"
deps_of "$SA"
check "split: the check lists every dependent, across parents" "$SB $SA
$SQ $SA,$SB
$SX $SA" "$out"
deps_of "$SA,$SB"
check "split: a superseded slice is not listed as a dependent of another" "$SQ $SA,$SB
$SX $SA" "$out"
items_before="$(count_items)"
# rewrite_split <id> <blocked_by>: swap A for R1 and R2 in the body, add the note.
rewrite_split() {
    local body
    body="$(field "$1" .body | perl -pe "s/^- Blocked by \Q$SA\E\$/- Blocked by $R1\n- Blocked by $R2/; s/\b\Q$SA\E\b/$R1/g")"$'\n\n## Re-decomposed\n\n'"- $SA split into $R1 and $R2"
    rw "$1" "$2" "$body"
    check "split: $1 rewritten" 0 "$rc"
    runb "$P" "${reconcile_block//W-<slice>/$1}"
    check "split: the read-back matches on $1" 0 "$rc"
}
rewrite_split "$SB" "$R1,$R2"
rewrite_split "$SQ" "$R1,$R2,$SB"
rewrite_split "$SX" "$R1,$R2"
(cd "$P" && bash "$SC_REAL" work close "$SA" >/dev/null 2>&1) || fatal "could not close $SA"
deps_of "$SA"
check "split: the re-run check prints nothing" "" "$out"
check "split: no work item was created by the rewrites" "$items_before" "$(count_items)"
check "split: only the superseded slice was closed" "$SA" "$(cd "$P" && bash "$SC_REAL" work list --kind slice --state closed | grep -x "$SA\|$SB\|$SQ\|$SX")"
check "split: the two replacements are the only unblocked slices under the PRD" "$R1
$R2" "$(cd "$P" && bash "$SC_REAL" work list --parent "$PQ" --unblocked)"
check "split: the dependent under the other PRD still waits" "" "$(cd "$P" && bash "$SC_REAL" work list --parent "$PX" --unblocked)"

# A dependents check whose read of one item fails stops; it never reads that
# item as not dependent. The stand-in resolver fails `work view` for $SX only.
failsc="$tmp/failview.sh"
# shellcheck disable=SC2016  # the stub body is literal sh
printf '#!/bin/sh\nif [ "$1" = work ] && [ "$2" = view ] && [ "$3" = "%s" ]; then echo "refused" >&2; exit 1; fi\nexec bash "%s" "$@"\n' "$SX" "$SC_REAL" > "$failsc"
(cd "$P" && bash "$SC_REAL" work set "$SX" blocked_by "$R1") >/dev/null 2>&1 || fatal "could not reset $SX"
fb="${dependents_block//$SC_REAL/$failsc}"
runb "$P" "${fb//OLD=\"W-<old>\"/OLD=\"$R1\"}"
check "a failed read stops the dependents check" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
# A read that exits 0 with output jq cannot parse stops it too.
# shellcheck disable=SC2016  # the stub body is literal sh
printf '#!/bin/sh\nif [ "$1" = work ] && [ "$2" = view ] && [ "$3" = "%s" ]; then echo "not json"; exit 0; fi\nexec bash "%s" "$@"\n' "$SX" "$SC_REAL" > "$failsc"
runb "$P" "${fb//OLD=\"W-<old>\"/OLD=\"$R1\"}"
check "an unparseable read stops the dependents check" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
# §9's tiebreak (#562 item 1): two slices unblocked at once, recorded in
# decomposed_into in reverse order, so neither the list order nor a loop that
# keeps the last match can pass for "lowest-numbered wins".
printf 'fifth pitch\n' > "$tmp/pitch5"
PL="$(cd "$P" && bash "$SC_REAL" work create --kind prd --body-file "$tmp/pitch5" 2>/dev/null)"
slice "$PL" "" "" ""; L1="$out"
slice "$PL" "" "" ""; L2="$out"
s8 "$PL" "$L2,$L1"
s9 "$PL"
check "§9: of two unblocked slices, the lower id is picked" "**Next session:** /execute $L1" "$out"

# The §7 read-back against the real issue template (#562 item 2), with every
# #<n> naming the PRD or a slice written W-<n>, as §7's sidecar rule says.
tpl="$(awk '/^<issue-template>$/{on=1; next} /^<\/issue-template>$/{on=0} on' "$SKILL")"
[ -n "$tpl" ] || fatal "no <issue-template> block in $SKILL"
tbody="$(printf '%s\n' "$tpl" | sed -e "s/#<prd-issue-number>/$PL/g" -e "s/#<issue-number>/$L1/g")"
slice "$PL" "$L1" "" "" "$tbody"; TS="$out"
runb "$P" "${reconcile_block//W-<slice>/$TS}"
check "§7: the read-back reads the real template's Blocked by section" "match $TS: [$L1]" "$out"

# §8's prose, read from the skill (#562 item 3, against the in-place procedure).
s8text="$(awk '/^### 8\. /{on=1} /^### 9\. /{on=0} on' "$SKILL")"
case "$s8text" in *"no dependent is closed or created again"*) ok "§8: says no dependent is closed or created again" ;;
    *) bad "§8: says no dependent is closed or created again" "sentence missing" ;; esac
# Wording only: this reaches the two literal phrases below, not the procedure; the blocks run above guard that.
case "$s8text" in *re-creat*|*"created again through"*) bad "§8: the words 're-creat' and 'created again through' are absent (wording only)" "found re-create wording" ;;
    *) ok "§8: the words 're-creat' and 'created again through' are absent (wording only)" ;; esac
# shellcheck disable=SC2016  # the needles are the skill's literal text
{
rw_line="$(printf '%s\n' "$s8text" | grep -n 'work set "$ID" blocked_by' | head -n 1 | cut -d: -f1)"
close_line="$(printf '%s\n' "$s8text" | grep -n 'Close each superseded slice' | head -n 1 | cut -d: -f1)"
recheck_line="$(printf '%s\n' "$s8text" | grep -n 'Run the step 2 check again' | head -n 1 | cut -d: -f1)"
}
check "§8: the superseded slices close after the dependents are rewritten" 1 \
    "$([ -n "$rw_line" ] && [ -n "$close_line" ] && [ "$rw_line" -lt "$close_line" ] && echo 1 || echo 0)"
check "§8: the check is re-run after the closes" 1 \
    "$([ -n "$close_line" ] && [ -n "$recheck_line" ] && [ "$close_line" -lt "$recheck_line" ] && echo 1 || echo 0)"
s7text="$(awk '/^### 7\. /{on=1} /^<issue-template>$/{on=0} on' "$SKILL")"
case "$s7text" in *'`work set W-<n> blocked_by'*) ok "§7: a wrong field is fixed with work set blocked_by" ;;
    *) bad "§7: a wrong field is fixed with work set blocked_by" "not found in §7" ;; esac

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
