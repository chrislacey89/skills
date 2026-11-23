#!/usr/bin/env bash
# test-execute-session-marker.sh — /execute Step 0's session marker (#813),
# extracted from execute/SKILL.md and RUN, in bash and in zsh.
#
# THE DRIFT CLASS. Two sessions can run /execute in one checkout without either
# knowing: both write to the same tree, and the second one's commits land on
# the first one's slice. Step 0 writes .claude/.session (by=, at=, slice=) and
# stops when another session's marker is under 12 hours old. The block decides
# by comparing a session id and an age, and a block that compares the wrong
# way passes every run that has one session. So the decision is RUN here
# against each kind of marker: another session's fresh one (stop, unchanged),
# a 13-hour-old one (rewritten), one a second under 12 hours and one exactly
# 12 hours old on a held clock (stop, rewritten), this session's own (rewritten), one with no
# by= line (the maker is unknown: stop), and a take-over (rewritten). Step 6's
# removal is run too: it removes this session's marker and leaves another's.
# The exit a run takes when it cannot finish the slice skips Step 6, so it
# carries the same removal (#813): without it, each Ralph iteration (a new
# session) stopped on the marker the previous one left. A run that dies before
# any exit still leaves its marker; nothing here covers that.
#
# Agents run these blocks in zsh as well as bash
# (skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
EX="$repo_root/execute/SKILL.md"
[ -f "$EX" ] || { printf 'FATAL %s is missing\n' "$EX"; exit 1; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

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

section "the blocks"
# shellcheck disable=SC2016  # the needles are the skill's literal text
{
mark_block="$(block "$EX" 'slice=%s')"
rm_block="$(block "$EX" 'session marker removed')"
}
if [ -n "$mark_block" ]; then ok "execute Step 0 carries the session-marker block"; else bad "execute Step 0 carries the session-marker block" "not found"; fi
if [ -n "$rm_block" ]; then ok "execute Step 6 carries the session-marker removal"; else bad "execute Step 6 carries the session-marker removal" "not found"; fi
# The exit a run takes when it cannot finish skips Step 6's removal, so it carries its own.
exit_span="$(awk '/^If you cannot complete the task in this context window/{on=1} /^\*\*AFK progress and plateau detection\.\*\*/{on=0} on' "$EX")"
exit_block="$(printf '%s\n' "$exit_span" | awk '
    /^ *```bash$/ { buf = ""; on = 1; next }
    on && /^ *```$/ { on = 0; if (index(buf, "session marker removed")) { printf "%s", buf; exit } next }
    on { buf = buf $0 "\n" }
')"
if [ -n "$exit_block" ]; then ok "the cannot-finish exit carries a session-marker removal"; else bad "the cannot-finish exit carries a session-marker removal" "not found"; fi
check "the cannot-finish exit's removal is Step 6's, byte for byte" "$rm_block" "$exit_block"
step0="$(awk '/^### 0\. /{on=1} /^### 1\. /{on=0} on' "$EX")"
step6="$(awk '/^### 6\. /{on=1} /^## Review Notes/{on=0} on' "$EX")"
check "the marker block sits in Step 0" 1 "$(grep -cF 'slice=%s' <<<"$step0")"
check "the removal sits in Step 6" 1 "$(grep -cF 'session marker removed' <<<"$step6")"
# shellcheck disable=SC2016
check "Step 0 says an AFK run stops where it cannot ask" 1 "$(grep -c 'AFK.*stop' <<<"$(grep -F '.claude/.session' <<<"$step0")" | awk '{print ($1 > 0)}')"
check "the marker is not a classification marker: GATE_TERMS does not name it" 0 "$(awk '/^GATE_TERMS=/{on=1} on{print} on && /"$/{exit}' "$EX" | grep -c '\.session')"
check ".gitignore ignores the marker" 1 "$(grep -cx '.claude/.session' "$repo_root/.gitignore")"
check "/init-pipeline scaffolds the ignore line" 1 "$(awk '/^### 6\. `.gitignore` additions/{on=1} /^### 7\. /{on=0} on' "$repo_root/init-pipeline/SKILL.md" | grep -cx '.claude/.session')"

shells="bash"
if command -v zsh >/dev/null 2>&1; then shells="bash zsh"
elif [ -n "${CI:-}" ]; then bad "zsh is on PATH for the zsh arms" "zsh missing and CI is set"
else printf '  SKIP zsh arms: zsh is not on PATH\n'; fi

# utc <seconds-ago> — an at= value that many seconds in the past, on BSD or GNU date.
utc() {
    local t=$(( $(date +%s) - $1 ))
    date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$t" +%Y-%m-%dT%H:%M:%SZ
}

P="$tmp/proj"
git init -q "$P"
mkdir -p "$P/.claude"
M="$P/.claude/.session"
# A folder an inherited CLAUDE_PROJECT_DIR can name that does not contain $P (#812).
O="$tmp/other"
mkdir -p "$O/.claude"
CPD="$P"   # the CLAUDE_PROJECT_DIR run() hands the block
# A `date` shim holds the clock the block reads for "now" (`date +%s`), so the
# probes on either side of the 12-hour limit land on the second they name; every
# other call (parsing at=, writing at=) goes to the date found on PATH here.
NOW=1798761600   # 2027-01-01T00:00:00Z
real_date="$(command -v date)"
mkdir -p "$tmp/clock"
printf '#!/bin/sh
if [ "$*" = "+%%s" ]; then echo %s; else exec "%s" "$@"; fi\n' "$NOW" "$real_date" > "$tmp/clock/date"
chmod +x "$tmp/clock/date"
RUNPATH="$PATH"   # the PATH run() hands the block
# at <seconds-before-NOW> — an at= value that long before the held clock.
at() { date -u -r $(( NOW - $1 )) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
# run <shell> <block> <this session's id> [take over] — stdout in $out, exit in $rc.
run() {
    local b="${2//SLICE=\"<the W-<n> or issue number this run builds, or a short name for a one-off task>\"/SLICE=\"W-7\"}"
    [ "${4:-}" != yes ] || b="${b//TAKE_OVER=\"\"/TAKE_OVER=\"yes\"}"
    out="$(cd "$P" && PATH="$RUNPATH" CLAUDE_PROJECT_DIR="$CPD" CLAUDE_CODE_SESSION_ID="$3" "$1" -c "$b" 2>&1)"; rc=$?
}
field() { sed -n "s/^$1=//p" "$M"; }

for sh in $shells; do
    section "$sh: Step 0's marker"

    rm -f "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: no marker: the block exits 0" 0 "$rc"
    check "$sh: no marker: it writes by= as this session" s-me "$(field by)"
    check "$sh: no marker: it writes slice=" W-7 "$(field slice)"
    check "$sh: no marker: at= is UTC to the second" 1 "$(field at | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')"

    fresh="$(utc 600)"
    printf 'by=s-other\nat=%s\nslice=W-3\n' "$fresh" > "$M"
    cp "$M" "$tmp/before"
    run "$sh" "$mark_block" s-me
    check "$sh: another session's fresh marker: the block stops" 1 "$rc"
    check "$sh: …and leaves the marker as it was" "$(cat "$tmp/before")" "$(cat "$M")"
    check "$sh: …and names who holds it, since when and for which slice" 1 "$(grep -cF "held by session s-other since $fresh for W-3" <<<"$out")"
    check "$sh: …and offers take over or another slice" 1 "$(grep -c 'take over.*another slice' <<<"$out")"

    run "$sh" "$mark_block" s-me yes
    check "$sh: take over: the block exits 0" 0 "$rc"
    check "$sh: take over: the marker is this session's" s-me "$(field by)"
    check "$sh: take over: it names this run's slice" W-7 "$(field slice)"

    printf 'by=s-other\nat=%s\nslice=W-3\n' "$(utc 46800)" > "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: a 13-hour-old marker: the block exits 0" 0 "$rc"
    check "$sh: a 13-hour-old marker: it is rewritten as this session's" s-me "$(field by)"

    # The limit itself, on a held clock: one second under 12 hours stops, and
    # exactly 12 hours is old enough. These two pin both the value and the
    # strict comparison (a limit of -le 43200, or any other number, fails one).
    RUNPATH="$tmp/clock:$PATH"
    check "$sh: the shim holds the block's clock" "$NOW" "$(PATH="$RUNPATH" "$sh" -c 'date +%s')"
    printf 'by=s-other\nat=%s\nslice=W-3\n' "$(at 43199)" > "$M"
    cp "$M" "$tmp/before"
    run "$sh" "$mark_block" s-me
    check "$sh: a marker 1 second under 12 hours old: the block stops" 1 "$rc"
    check "$sh: …and leaves the marker as it was" "$(cat "$tmp/before")" "$(cat "$M")"
    printf 'by=s-other\nat=%s\nslice=W-3\n' "$(at 43200)" > "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: a marker exactly 12 hours old: the block exits 0" 0 "$rc"
    check "$sh: a marker exactly 12 hours old: it is rewritten as this session's" s-me "$(field by)"
    RUNPATH="$PATH"

    printf 'by=s-me\nat=%s\nslice=W-3\n' "$(utc 60)" > "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: this session's own marker: the block exits 0" 0 "$rc"
    check "$sh: this session's own marker: it is rewritten for this slice" W-7 "$(field slice)"

    printf 'at=%s\nslice=W-3\n' "$(utc 600)" > "$M"
    cp "$M" "$tmp/before"
    run "$sh" "$mark_block" s-me
    check "$sh: a fresh marker with no by=: the block stops" 1 "$rc"
    check "$sh: …it names the maker as unknown" 1 "$(grep -c 'held by session unknown' <<<"$out")"
    check "$sh: …and leaves the marker as it was" "$(cat "$tmp/before")" "$(cat "$M")"

    printf 'by=\nat=%s\nslice=W-3\n' "$(utc 600)" > "$M"
    run "$sh" "$mark_block" ""
    check "$sh: an empty by= is unknown even to a session with no id: the block stops" 1 "$rc"

    printf 'by=s-other\nat=yesterday\nslice=W-3\n' > "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: an at= that does not parse counts as fresh: the block stops" 1 "$rc"

    # GNU date -d reads "" as midnight today, so these read as expired after 12:00 UTC without the shape check.
    printf 'by=s-other\nat=\nslice=W-3\n' > "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: an empty at= counts as fresh: the block stops" 1 "$rc"

    printf 'by=s-other\nslice=W-3\n' > "$M"
    run "$sh" "$mark_block" s-me
    check "$sh: a marker with no at= counts as fresh: the block stops" 1 "$rc"

    section "$sh: Step 6's removal"

    printf 'by=s-me\nat=%s\nslice=W-7\n' "$(utc 60)" > "$M"
    run "$sh" "$rm_block" s-me
    check "$sh: this session's marker is removed" no "$([ -e "$M" ] && echo yes || echo no)"
    printf 'by=s-other\nat=%s\nslice=W-3\n' "$(utc 60)" > "$M"
    run "$sh" "$rm_block" s-me
    check "$sh: another session's marker is left (it took over)" yes "$([ -e "$M" ] && echo yes || echo no)"
    rm -f "$M"
    run "$sh" "$rm_block" s-me
    check "$sh: with no marker the removal exits 0" 0 "$rc"

    section "$sh: an AFK iteration that cannot finish, then the next one"

    rm -f "$M"
    run "$sh" "$mark_block" s-iter1
    run "$sh" "$exit_block" s-iter1
    check "$sh: the cannot-finish exit removes its own marker" no "$([ -e "$M" ] && echo yes || echo no)"
    run "$sh" "$mark_block" s-iter2
    check "$sh: the next iteration, a new session, is not stopped" 0 "$rc"
    check "$sh: …and the marker is now the next iteration's" s-iter2 "$(field by)"

    section "$sh: an inherited CLAUDE_PROJECT_DIR naming another folder"

    rm -f "$M" "$O/.claude/.session"
    printf 'by=s-other\nat=%s\nslice=W-3\n' "$(utc 60)" > "$tmp/held"
    cp "$tmp/held" "$O/.claude/.session"
    CPD="$O"
    run "$sh" "$mark_block" s-me
    check "$sh: the other folder's marker does not stop this checkout" 0 "$rc"
    check "$sh: …the marker is written in this checkout" s-me "$(field by)"
    check "$sh: …and the other folder's marker is untouched" "$(cat "$tmp/held")" "$(cat "$O/.claude/.session")"
    printf 'by=s-me\nat=%s\nslice=W-3\n' "$(utc 60)" > "$O/.claude/.session"
    cp "$O/.claude/.session" "$tmp/held"
    run "$sh" "$rm_block" s-me
    check "$sh: Step 6's removal takes this checkout's marker" no "$([ -e "$M" ] && echo yes || echo no)"
    check "$sh: …and leaves the other folder's, even one naming this session" "$(cat "$tmp/held")" "$(cat "$O/.claude/.session")"
    CPD="$P"
done

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
