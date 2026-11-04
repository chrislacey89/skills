#!/usr/bin/env bash
# test-closeout-work-close.sh — /closeout closes the merged slice's work item
# on the sidecar backend (#695).
#
# THE DRIFT CLASS. On the github backend a slice closes itself: the PR body's
# `Closes #N` line closes the issue at merge. On the sidecar backend nothing
# does, so a merged slice stays `open` in work/: `work list --unblocked` keeps
# offering it to /execute, and every slice that lists it in `blocked_by` stays
# gated. The failure is silent: the merge succeeds and the store lies.
#
# So /closeout Step 3's work-close block is extracted and RUN against a real
# sidecar and a stubbed `gh` that answers the merged PR's URL. After it runs,
# the item whose `pr` field holds that URL reads `state: closed`, and nothing
# else changed. The refusals are run too: zero matches and two matches close
# nothing, a github backend touches nothing, and a pr recorded on a
# PRD closes nothing: the parent PRD is reported, never closed, and its close
# stays the user's confirm.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
CO="$repo_root/closeout/SKILL.md"
for f in "$SC" "$CO"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Closeout Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

# block <file> <literal> — the first fenced bash block containing <literal>.
block() {
    awk -v want="$2" '
        /^ *```bash$/ { buf = ""; on = 1; ind = index($0, "`") - 1; next }
        on && /^ *```$/ { on = 0; if (index(buf, want)) { printf "%s", buf; exit } next }
        on { buf = buf substr($0, ind + 1) "\n" }
    ' "$1"
}

# -----------------------------------------------------------------------------
section "the block"

# shellcheck disable=SC2016  # the needle is the skill's literal text
co_block="$(block "$CO" 'bash "$SC" work close "$W"')"
[ -n "$co_block" ] || { bad "closeout/SKILL.md Step 3 carries the work-close block" "not found"; printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"; exit 1; }
ok "closeout/SKILL.md Step 3 carries the work-close block"

# The stub answers `gh pr view <n> --json url` with $GH_URL, and fails on any
# other call: the block has no business editing, commenting, or closing on the forge.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
case "$*" in
    "pr view 7 --json url -q .url") printf '%s\n' "$GH_URL" ;;
    *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"

URL="https://github.com/acme/guest/pull/7"

# mkproj <guest|owned> — a fresh project in $P on a github.com remote, with a
# sidecar. An owned GitHub sidecar routes slices to github; a guest one to the sidecar.
n=0
mkproj() {
    n=$((n + 1))
    P="$tmp/proj$n"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
    git -C "$P" remote add origin "https://github.com/acme/guest$n.git"
    (cd "$P" && bash "$SC" init --name "guest$n" --mode "$1" --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>"$tmp/init.err") \
        || bad "init the $1 sidecar" "$(cat "$tmp/init.err")"
}
# mk <args...> — work create in $P with a placeholder body; prints the id.
mk() {
    printf 'body\n' > "$tmp/body.md"
    (cd "$P" && bash "$SC" work create "$@" --body-file "$tmp/body.md")
}
state() { (cd "$P" && bash "$SC" work view "$1" --json | jq -r .state); }
run_block() {
    local b="${co_block//<this skill\'s directory>\/references\/sidecar.sh/$SC}"
    b="${b//<number>/7}"
    : > "$tmp/calls"
    out="$(cd "$P" && GH_URL="$URL" GH_CALLS="$tmp/calls" PATH="$tmp/bin:$PATH" "${RUN_SHELL:-bash}" -c "$b" 2>"$tmp/stderr")"; rc=$?
}

# -----------------------------------------------------------------------------
section "the merged slice closes; its sibling and the PRD stay open"

mkproj guest
PRD="$(mk --kind prd)"
S1="$(mk --kind slice --parent "$PRD")"
S2="$(mk --kind slice --parent "$PRD" --blocked-by "$S1")"
(cd "$P" && bash "$SC" work set "$PRD" decomposed_into "$S1,$S2" && bash "$SC" work set "$S1" pr "$URL" && bash "$SC" work set "$S2" pr "https://github.com/acme/guest/pull/8") >/dev/null 2>&1 \
    || bad "fixture: wire the PRD and slices" "work set failed"
check "fixture: $S2 is gated by $S1 before the merge" "" "$(cd "$P" && bash "$SC" work list --unblocked | grep -x "$S2")"
run_block
check "the block exits 0" 0 "$rc"
check "the item whose pr is the merged PR reads closed" closed "$(state "$S1")"
check "the sibling slice stays open" open "$(state "$S2")"
check "the PRD stays open" open "$(state "$PRD")"
check "the block names the item it closed" 1 "$(grep -cx "work item: closed $S1" <<<"$out")"
check "the block reports the PRD's open slices" 1 "$(grep -cx "parent $PRD: still open: $S2" <<<"$out")"
check "closing $S1 unblocks $S2" "$S2" "$(cd "$P" && bash "$SC" work list --unblocked | grep -x "$S2")"
check "the only gh call reads the PR's URL" "pr view 7 --json url -q .url" "$(cat "$tmp/calls")"
check "the project tree is untouched" "" "$(git -C "$P" status --porcelain)"

# -----------------------------------------------------------------------------
section "the last slice closes; the PRD is reported complete, not closed"

URL="https://github.com/acme/guest/pull/8"
run_block
check "the block exits 0" 0 "$rc"
check "the last slice reads closed" closed "$(state "$S2")"
check "the block reports every slice closed" 1 "$(grep -cx "parent $PRD: every slice is closed" <<<"$out")"
check "the PRD is still open: its close is the user's confirm" open "$(state "$PRD")"
URL="https://github.com/acme/guest/pull/7"

# -----------------------------------------------------------------------------
section "zero or two matches close nothing"

mkproj guest
A="$(mk --kind slice)"
run_block
check "no recorded pr: the block exits 1" 1 "$rc"
check "no recorded pr: it says no item matched" 1 "$(grep -c "0 open slices record $URL" "$tmp/stderr")"
check "no recorded pr: the open item stays open" open "$(state "$A")"

B="$(mk --kind slice)"
(cd "$P" && bash "$SC" work set "$A" pr "$URL" && bash "$SC" work set "$B" pr "$URL") >/dev/null 2>&1
run_block
check "two claimants: the block exits 1" 1 "$rc"
check "two claimants: it names both" 1 "$(grep -c "2 open slices record $URL as their pr: $A $B" "$tmp/stderr")"
check "two claimants: $A stays open" open "$(state "$A")"
check "two claimants: $B stays open" open "$(state "$B")"

# A closed item holding the URL is not a match: the block reads open items only.
(cd "$P" && bash "$SC" work close "$B") >/dev/null 2>&1
run_block
check "a closed claimant is ignored: the open one closes" closed "$(state "$A")"

# -----------------------------------------------------------------------------
section "a pr recorded on the PRD closes nothing"

# /pre-merge Phase 1 accepts a slice or its PRD, and Phase 2 records the PR on
# whichever it was given. The block matches slices only, so a PRD that holds
# the URL is named and left for the user's confirm (#699).
mkproj guest
PRD="$(mk --kind prd)"
S1="$(mk --kind slice --parent "$PRD")"
(cd "$P" && bash "$SC" work set "$PRD" decomposed_into "$S1" && bash "$SC" work set "$PRD" pr "$URL") >/dev/null 2>&1 \
    || bad "fixture: record the pr on the PRD" "work set failed"
run_block
check "pr on the PRD: the block exits 1" 1 "$rc"
check "pr on the PRD: the PRD stays open" open "$(state "$PRD")"
check "pr on the PRD: the slice stays open" open "$(state "$S1")"
check "pr on the PRD: it names the PRD and closes nothing" 1 "$(grep -c "work item NOT closed: $URL is recorded on PRD $PRD, not a slice" "$tmp/stderr")"

(cd "$P" && bash "$SC" work set "$S1" pr "$URL") >/dev/null 2>&1
run_block
check "pr on the PRD and the slice: the block exits 0" 0 "$rc"
check "pr on the PRD and the slice: the slice closes" closed "$(state "$S1")"
check "pr on the PRD and the slice: the PRD stays open" open "$(state "$PRD")"

# -----------------------------------------------------------------------------
section "a github backend touches nothing"

mkproj owned
check "fixture: backend slices answers github" github "$(cd "$P" && bash "$SC" backend slices)"
run_block
check "github: the block exits 0" 0 "$rc"
check "github: no gh call" "" "$(cat "$tmp/calls")"
check "github: it says Closes #N did the work" 1 "$(grep -c 'Closes #N closed the issue the PR body names' <<<"$out")"

# -----------------------------------------------------------------------------
section "mutation: the check sees a block that closes nothing"

mkproj guest
M="$(mk --kind slice)"
(cd "$P" && bash "$SC" work set "$M" pr "$URL") >/dev/null 2>&1
saved="$co_block"
# shellcheck disable=SC2016
co_block="${co_block//bash \"\$SC\" work close \"\$W\"/true}"
run_block
check "with work close removed, the item stays open (the assertion above would go red)" open "$(state "$M")"
co_block="$saved"

# -----------------------------------------------------------------------------
section "the block under zsh, the shell an agent runs it in"

# zsh does not word-split an unquoted expansion, so a `for id in $IDS` loop
# would see one id holding the whole list (skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md).
if command -v zsh >/dev/null 2>&1; then
    mkproj guest
    PRD="$(mk --kind prd)"
    S1="$(mk --kind slice --parent "$PRD")"
    S2="$(mk --kind slice --parent "$PRD")"
    (cd "$P" && bash "$SC" work set "$PRD" decomposed_into "$S1,$S2" && bash "$SC" work set "$S1" pr "https://github.com/acme/guest/pull/8" && bash "$SC" work set "$S2" pr "$URL") >/dev/null 2>&1
    RUN_SHELL=zsh run_block
    check "zsh: the block exits 0" 0 "$rc"
    check "zsh: the matching item, not the first listed, reads closed" closed "$(state "$S2")"
    check "zsh: the other slice stays open" open "$(state "$S1")"
    check "zsh: the PRD's open slices are listed one by one" 1 "$(grep -cx "parent $PRD: still open: $S1" <<<"$out")"
else
    printf '  SKIP zsh not installed\n'
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
