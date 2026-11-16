#!/usr/bin/env bash
# test-lesson-recall.sh — runs the real init-pipeline/scripts/sidecar.sh
# `lessons match` verb against scratch repos, and /execute Step 1's
# lessons-start block as written under bash and zsh (chrislacey89/skills#748).
#
# THE MISS. A lesson that applied to a branch was not found, because the
# keyword search over docs/solutions/ only finds a lesson whose words the
# author thought to type
# (docs/solutions/testing-patterns/a-planted-term-cannot-discriminate-meaning-2026-09-04.md).
# A lesson's `paths` line names the files it applies to, and `lessons match`
# returns it for those files whatever words the task uses. The planted case
# below executes the command and compares its output by identity; it never
# greps a skill's prose for a phrase.
#
# THREE OUTCOMES, NEVER CONFUSED. A match prints lesson lines, no match prints
# an explicit line, and a failed read exits nonzero with nothing on stdout
# (docs/solutions/architecture-decisions/compat-default-is-every-failures-answer-2026-10-24.md).
# Every outcome but the failure ends with the receipt line, so "nothing
# matched because no lesson carries paths" reads as that.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config, and every fixture root commit carries its own path
# (scripts/test-fixture-root-collision.sh).

# shellcheck disable=SC2016  # literal $ and backticks in sed and grep patterns
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
[ -f "$SC" ] || { printf 'FATAL %s is missing\n' "$SC"; exit 1; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Recall Tester"
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
fatal() { printf 'FATAL %s\n' "$1"; printf '\n---\n%d passed, %d failed\n' "$pass" "$((fail + 1))"; exit 1; }

# runo <dir> <args...> — run sidecar.sh from <dir>; stdout in $out, exit in $rc,
# stderr in $err.
runo() {
    local d="$1"; shift
    out="$(cd "$d" && "$BASH" "$SC" "$@" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}

n=0
# mkproj — a scratch project with its own root commit and no sidecar, in $P.
mkproj() {
    n=$((n + 1))
    P="$tmp/proj$n"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
}

# lesson <project> <relpath> <title> <frontmatter lines...> — write a lesson
# under the project's docs/solutions/.
lesson() {
    local p="$1" rel="$2" title="$3" f
    shift 3
    f="$p/docs/solutions/$rel"
    mkdir -p "$(dirname "$f")"
    {
        printf -- '---\n'
        printf 'title: "%s"\n' "$title"
        printf 'volatility: low\n'
        for l in "$@"; do printf '%s\n' "$l"; done
        printf -- '---\n\n# %s\n\nBody text.\n' "$title"
    } > "$f"
}

TAB="$(printf '\t')"

# -----------------------------------------------------------------------------
section "exact match"

mkproj
lesson "$P" "testing/a-2026-01-01.md" "Lesson A" "paths: [scripts/a.sh]"
runo "$P" lessons match scripts/a.sh
check "exits 0" 0 "$rc"
check "prints the lesson as exact, then the receipt" \
    "exact${TAB}docs/solutions/testing/a-2026-01-01.md${TAB}Lesson A
lessons: 1 matched, 1 scanned, 1 with paths, projects: $(basename "$P"), recorded: no" "$out"

runo "$P/docs" lessons match ../scripts/a.sh
check "a path relative to a subdirectory is read from there" \
    "exact${TAB}docs/solutions/testing/a-2026-01-01.md${TAB}Lesson A" "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" lessons match "$P/scripts/a.sh"
check "an absolute path inside the project is matched" \
    "exact${TAB}docs/solutions/testing/a-2026-01-01.md${TAB}Lesson A" "$(printf '%s\n' "$out" | head -n 1)"

# -----------------------------------------------------------------------------
section "folder match and the segment boundary"

mkproj
lesson "$P" "testing/f-2026-01-01.md" "Folder lesson" "paths: [scripts]"
runo "$P" lessons match scripts/deep/x.sh
check "a file under a pointed-at folder: exits 0" 0 "$rc"
check "a file under a pointed-at folder prints it as folder" \
    "folder${TAB}docs/solutions/testing/f-2026-01-01.md${TAB}Folder lesson" "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" lessons match scripts-old/x.sh
check "scripts does not match scripts-old/x.sh" "no lesson points at these files" "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" lessons match scriptsx
check "scripts does not match the file scriptsx" "no lesson points at these files" "$(printf '%s\n' "$out" | head -n 1)"
lesson "$P" "testing/g-2026-01-01.md" "Trailing slash" "paths: [./lib/]"
runo "$P" lessons match lib/y.sh
check "a pointer written ./lib/ is the folder lib" \
    "folder${TAB}docs/solutions/testing/g-2026-01-01.md${TAB}Trailing slash" "$(printf '%s\n' "$out" | head -n 1)"

# Context anchors name a file with a line or a range after it
# (`init-pipeline/scripts/sidecar.sh:1277`, `scripts/test-x.sh:120-131`).
# A folder pointer matches whatever follows it, so only an exact pointer can
# tell whether the suffix was removed.
lesson "$P" "testing/h-2026-01-01.md" "Exact file" "paths: [tools/run.sh]"
runo "$P" lessons match tools/run.sh:1277
check "a path with a :line suffix matches as the path" \
    "exact${TAB}docs/solutions/testing/h-2026-01-01.md${TAB}Exact file" "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" lessons match tools/run.sh:120-131
check "a path with a :start-end suffix matches as the path" \
    "exact${TAB}docs/solutions/testing/h-2026-01-01.md${TAB}Exact file" "$(printf '%s\n' "$out" | head -n 1)"

# -----------------------------------------------------------------------------
section "order: exact first, then folders deepest first"

# Lesson names run against the expected order, so a sort by lesson path alone
# cannot pass.
mkproj
lesson "$P" "a/shallow-2026-01-01.md" "Shallow" "paths: [src]"
lesson "$P" "b/deep-2026-01-01.md" "Deep" "paths: [src/core/io]"
lesson "$P" "c/middle-2026-01-01.md" "Middle" "paths: [src/core]"
lesson "$P" "d/exact-2026-01-01.md" "Exact" "paths: [src/core/io/read.sh]"
lesson "$P" "e/both-2026-01-01.md" "Both kinds" "paths: [src, src/core/io/read.sh]"
runo "$P" lessons match src/core/io/read.sh
check "order: exits 0" 0 "$rc"
check "exact lines in lesson order, then deepest folder first, each lesson once" \
"exact${TAB}docs/solutions/d/exact-2026-01-01.md${TAB}Exact
exact${TAB}docs/solutions/e/both-2026-01-01.md${TAB}Both kinds
folder${TAB}docs/solutions/b/deep-2026-01-01.md${TAB}Deep
folder${TAB}docs/solutions/c/middle-2026-01-01.md${TAB}Middle
folder${TAB}docs/solutions/a/shallow-2026-01-01.md${TAB}Shallow
lessons: 5 matched, 5 scanned, 5 with paths, projects: $(basename "$P"), recorded: no" "$out"
runo "$P" lessons match other/x.sh src/core/z.sh
check "several files: a lesson matched by any of them is printed" \
"folder${TAB}docs/solutions/c/middle-2026-01-01.md${TAB}Middle
folder${TAB}docs/solutions/a/shallow-2026-01-01.md${TAB}Shallow
folder${TAB}docs/solutions/e/both-2026-01-01.md${TAB}Both kinds" "$(printf '%s\n' "$out" | sed '$d')"

# -----------------------------------------------------------------------------
section "no match, and lessons with no paths"

mkproj
lesson "$P" "x/none-2026-01-01.md" "No paths key"
lesson "$P" "x/empty-2026-01-01.md" "Empty paths" "paths: []"
lesson "$P" "x/multi-2026-01-01.md" "Multi-line list" "paths:" "  - scripts/a.sh"
lesson "$P" "x/one-2026-01-01.md" "One path" "paths: [lib/z.sh]"
runo "$P" lessons match scripts/a.sh
check "no match: exits 0" 0 "$rc"
check "no match: the no-match line, then the receipt" \
"no lesson points at these files
lessons: 0 matched, 4 scanned, 1 with paths, projects: $(basename "$P"), recorded: no" "$out"
check "no match: nothing on stderr" "" "$err"
runo "$P" lessons match
check "no file list: exits 0" 0 "$rc"
check "no file list: says so, then the receipt" \
"no file list given; nothing to match
lessons: 0 matched, 4 scanned, 1 with paths, projects: $(basename "$P"), recorded: no" "$out"

mkproj
runo "$P" lessons match scripts/a.sh
check "no lessons at all: exits 0" 0 "$rc"
check "no lessons at all: zero scanned" \
"no lesson points at these files
lessons: 0 matched, 0 scanned, 0 with paths, projects: $(basename "$P"), recorded: no" "$out"

# -----------------------------------------------------------------------------
section "the reader resets at each file"

# An unterminated frontmatter must not reach into the next file. awk reads
# files in argument order, which find chooses, so both orders are built: the
# unterminated file sorts first in one project and last in the other.
for order in first last; do
    mkproj
    if [ "$order" = first ]; then u="a-open-2026-01-01.md"; t="b-tail-2026-01-01.md"; else u="z-open-2026-01-01.md"; t="b-tail-2026-01-01.md"; fi
    mkdir -p "$P/docs/solutions/r"
    # The open file names a path of its own; the next file is a well-formed lesson.
    printf -- '---\ntitle: "Open"\npaths: [only/in-the-open.sh]\n\n# Open\n' > "$P/docs/solutions/r/$u"
    lesson "$P" "r/$t" "Tail" "paths: [only/in-the-next.sh]"
    runo "$P" lessons match only/in-the-next.sh
    check "unterminated $order: the next file's paths stay the next file's" \
        "exact${TAB}docs/solutions/r/$t${TAB}Tail
lessons: 1 matched, 2 scanned, 1 with paths" "$(printf '%s\n' "$out" | sed 's/, projects.*//')"
    runo "$P" lessons match only/in-the-open.sh
    check "unterminated $order: the open file's fields are dropped, not lent" \
        "no lesson points at these files
lessons: 0 matched, 2 scanned, 1 with paths" "$(printf '%s\n' "$out" | sed 's/, projects.*//')"
done

# -----------------------------------------------------------------------------
section "a store that cannot be read"

if [ "$(id -u)" -eq 0 ]; then
    printf '  skip root reads every file\n'
else
    mkproj
    lesson "$P" "x/a-2026-01-01.md" "Readable" "paths: [scripts/a.sh]"
    lesson "$P" "y/b-2026-01-01.md" "Unreadable" "paths: [scripts/a.sh]"
    chmod 000 "$P/docs/solutions/y"
    runo "$P" lessons match scripts/a.sh
    check "an unreadable directory: exits nonzero" 1 "$rc"
    check "an unreadable directory: nothing on stdout" "" "$out"
    case "$err" in *"could not read the lesson headers"*) ok "an unreadable directory: says so on stderr" ;;
        *) bad "an unreadable directory: says so on stderr" "stderr: $err" ;; esac
    chmod 755 "$P/docs/solutions/y"
    chmod 000 "$P/docs/solutions/y/b-2026-01-01.md"
    runo "$P" lessons match scripts/a.sh
    check "an unreadable lesson file: exits nonzero" 1 "$rc"
    check "an unreadable lesson file: nothing on stdout" "" "$out"
    chmod 644 "$P/docs/solutions/y/b-2026-01-01.md"
fi
mkproj
runo "$tmp" lessons match scripts/a.sh
check "outside a repository: exits nonzero" 1 "$rc"
check "outside a repository: nothing on stdout" "" "$out"
runo "$P" lessons match --bogus
check "an unknown flag: exits 2" 2 "$rc"
runo "$P" lessons match a.sh --record
check "--record with no phase: exits 2" 2 "$rc"
runo "$P" lessons match a.sh --record later
check "--record with a phase other than start or changed: exits 2" 2 "$rc"
runo "$P" lessons
check "no sub-verb: exits 2" 2 "$rc"
runo "$P" lessons match "$(printf 'scripts/a.sh\nlib/b.sh')"
check "a list joined into one argument: exits 2" 2 "$rc"
check "a list joined into one argument: nothing on stdout" "" "$out"

# -----------------------------------------------------------------------------
section "the planted case: found by file, not by word"

# The lesson's text shares no word with the task. The keyword search /execute
# Step 1 runs finds nothing for the task's words; lessons match finds the
# lesson from the file the task touches. Both are executed, and the match is
# compared by identity.
mkproj
mkdir -p "$P/docs/solutions/patterns"
cat > "$P/docs/solutions/patterns/quoting-2026-02-02.md" <<'EOF'
---
title: "Quoting differs between shells"
volatility: low
paths: [tools/q7.sh]
---

# Quoting differs between shells

Word splitting is not done on an unquoted expansion in one of the two shells.
EOF
task_words="rename export helper"
hits=""
for kw in $task_words; do
    h="$(cd "$P" && grep -rli -- "$kw" docs/solutions)"
    hits="$hits$h"
done
check "the keyword search for the task's words finds nothing" "" "$hits"
runo "$P" lessons match tools/q7.sh
check "lessons match finds the planted lesson from the file" \
    "exact${TAB}docs/solutions/patterns/quoting-2026-02-02.md${TAB}Quoting differs between shells" \
    "$(printf '%s\n' "$out" | head -n 1)"

# -----------------------------------------------------------------------------
section "a lesson in the sidecar's store"

mkproj
runo "$P" init --name recall --mode owned --write sidecar --in-tree-path none --no-migrate-archive
S="$out"
[ -d "$S" ] || fatal "init did not create a sidecar: $err"
mkdir -p "$S/solutions/devops"
printf -- '---\npaths: [ci/run.sh]\n---\n\n# Sidecar lesson\n' > "$S/solutions/devops/side-2026-03-03.md"
git -C "$S" add solutions && git -C "$S" commit -q -m "fixture lesson"
lesson "$P" "x/tree-2026-03-03.md" "Tree lesson" "paths: [ci]"
runo "$P" lessons match ci/run.sh
check "sidecar and in-tree lessons are both read, the sidecar named" \
"exact${TAB}$S/solutions/devops/side-2026-03-03.md${TAB}Sidecar lesson
folder${TAB}docs/solutions/x/tree-2026-03-03.md${TAB}Tree lesson
lessons: 2 matched, 2 scanned, 2 with paths, projects: recall, recorded: no" "$out"
shead="$(git -C "$S" rev-parse HEAD)"
check "the sidecar's tree is untouched" "" "$(git -C "$S" status --porcelain)"
check "and its HEAD has not moved" "$shead" "$(git -C "$S" rev-parse HEAD)"

# -----------------------------------------------------------------------------
section "the process count does not grow with the store"

# Every external command sidecar.sh might start is shimmed to log its name
# and exec the real one. The count at 30 lessons must equal the count at 3.
shim="$tmp/shim"
mkdir -p "$shim"
for c in git jq awk find sort sed grep tr mktemp cat basename dirname head tail wc rm mkdir cut xargs uname id date ls cp mv; do
    real="$(command -v "$c")" || continue
    printf '#!/bin/sh\nprintf "%%s\\n" %s >> "%s/calls"\nexec "%s" "$@"\n' "$c" "$tmp" "$real" > "$shim/$c"
    chmod +x "$shim/$c"
done
count_calls() {
    : > "$tmp/calls"
    (cd "$1" && PATH="$shim:$PATH" "$BASH" "$SC" lessons match a/b.sh >/dev/null 2>&1)
    wc -l < "$tmp/calls" | tr -d ' '
}
mkproj; small="$P"
mkproj; large="$P"
i=0
while [ "$i" -lt 30 ]; do
    i=$((i + 1))
    [ "$i" -le 3 ] && lesson "$small" "p/l$i-2026-01-01.md" "L$i" "paths: [a/b.sh]"
    lesson "$large" "p/l$i-2026-01-01.md" "L$i" "paths: [a/b.sh]"
done
c3="$(count_calls "$small")"
c30="$(count_calls "$large")"
if [ "$c3" -gt 0 ]; then ok "the shim sees sidecar.sh's processes ($c3 at 3 lessons)"; else bad "the shim sees sidecar.sh's processes" "0 calls logged: the shim is not on the path"; fi
check "30 lessons start as many processes as 3" "$c3" "$c30"

# -----------------------------------------------------------------------------
section "/execute Step 1's lessons-start block, run as written"

# The agent runs the block in its own shell, which on macOS is zsh, so each
# case runs under bash and under zsh
# (docs/solutions/patterns/skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md).
# Only the SC and FILES lines are replaced; FILES takes the list from the
# environment so it can hold several lines.
EXECUTE="$repo_root/execute/SKILL.md"
lblock="$(awk '/^<!-- sidecar-read: execute-lessons-start -->$/ { on = 1; next }
               on && /^```bash$/ { inb = 1; next }
               inb && /^```$/ { exit }
               inb { print }' "$EXECUTE")"
[ -n "$lblock" ] || fatal "execute/SKILL.md has no \`\`\`bash block after <!-- sidecar-read: execute-lessons-start -->"
ok "execute/SKILL.md carries the lessons-start block"
case "$lblock" in *'FILES='*) ;; *) fatal "the lessons-start block sets no FILES" ;; esac
lscript="$(printf '%s\n' "$lblock" | sed -e "s|^SC=.*|SC=\"$SC\"|" -e 's|^FILES=.*|FILES="$TEST_FILES"|')"
# Step 1 reads the lessons before the keyword search, and after the trace.
lline="$(grep -n '^<!-- sidecar-read: execute-lessons-start -->$' "$EXECUTE" | cut -d: -f1)"
tline="$(grep -n '^<!-- sidecar-read: execute-trace -->$' "$EXECUTE" | cut -d: -f1)"
kline="$(grep -n '^Consult `docs/solutions/` and the sidecar' "$EXECUTE" | cut -d: -f1)"
if [ -n "$tline" ] && [ -n "$kline" ] && [ "$tline" -lt "$lline" ] && [ "$lline" -lt "$kline" ]; then
    ok "the block sits after the trace block and before the keyword search"
else
    bad "the block sits after the trace block and before the keyword search" "trace=$tline lessons=$lline keyword=$kline"
fi

mkproj
BP="$P"
lesson "$BP" "x/hit-2026-04-04.md" "Hit" "paths: [lib/one.sh]"
block_shells="bash"
if command -v zsh >/dev/null 2>&1; then block_shells="bash zsh"; else printf '  skip zsh not installed\n'; fi
for sh in $block_shells; do
    if [ "$sh" = zsh ]; then runner=(zsh -f -c); else runner=("$BASH" -c); fi
    out="$(cd "$BP" && TEST_FILES="lib/two.sh

lib/one.sh" "${runner[@]}" "$lscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: several files, one blank line: exits 0" 0 "$rc"
    check "$sh: each file is its own argument" \
"exact${TAB}docs/solutions/x/hit-2026-04-04.md${TAB}Hit
lessons: 1 matched, 1 scanned, 1 with paths, projects: $(basename "$BP"), recorded: no" "$out"
    out="$(cd "$BP" && TEST_FILES="" "${runner[@]}" "$lscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: no file list: exits 0" 0 "$rc"
    check "$sh: no file list: says no file list was given" "no file list given; nothing to match" \
        "$(printf '%s\n' "$out" | head -n 1)"
    out="$(cd "$tmp" && TEST_FILES="lib/one.sh" "${runner[@]}" "$lscript" 2>"$tmp/stderr")"; rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$out" ]; then ok "$sh: a failed lookup exits nonzero with nothing on stdout"
    else bad "$sh: a failed lookup exits nonzero with nothing on stdout" "rc=$rc out=[$out]"; fi
done

# -----------------------------------------------------------------------------
section "the run log: --record writes one line per lookup"

# The command writes the record itself, so a branch with no record is a branch
# where the lookup did not run. The line's shape is PRD #747's locked contract.
mkproj
LP="$P"
runo "$LP" init --name logproj --mode owned --write sidecar --in-tree-path none --no-migrate-archive
LS="$out"
[ -d "$LS" ] || fatal "init did not create a sidecar: $err"
git -C "$LP" checkout -q -b feat/x
lesson "$LP" "x/hit-2026-05-05.md" "Logged" "paths: [a/b.sh]"
LOG="$LS/lookups/feat%2Fx.jsonl"
lhead="$(git -C "$LS" rev-parse HEAD)"
runo "$LP" lessons match a/b.sh other/c.sh --record start
check "--record start: exits 0" 0 "$rc"
check "--record start: the receipt says recorded: yes" \
    "lessons: 1 matched, 1 scanned, 1 with paths, projects: logproj, recorded: yes" "$(printf '%s\n' "$out" | tail -n 1)"
check "--record start: one line in lookups/<branch-slug>.jsonl" 1 "$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"
check "the record carries exactly the contract's keys" \
    '["at","branch","files","matched","outcome","phase","projects","scanned","with_paths"]' \
    "$(jq -c 'keys' "$LOG" 2>/dev/null)"
check "the record's values" \
    '{"branch":"feat/x","phase":"start","files":["a/b.sh","other/c.sh"],"scanned":1,"with_paths":1,"projects":["logproj"],"matched":["hit-2026-05-05.md"],"outcome":"matched"}' \
    "$(jq -c 'del(.at)' "$LOG" 2>/dev/null)"
if jq -e '.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$LOG" >/dev/null 2>&1; then
    ok "the record's at is an ISO 8601 UTC time"
else bad "the record's at is an ISO 8601 UTC time" "$(cat "$LOG" 2>/dev/null)"; fi
check "the record is committed in the sidecar" "" "$(git -C "$LS" status --porcelain)"
if [ "$(git -C "$LS" rev-parse HEAD)" != "$lhead" ]; then ok "the sidecar's HEAD moved by the record's commit"
else bad "the sidecar's HEAD moved by the record's commit" "HEAD is still $lhead"; fi

lhead="$(git -C "$LS" rev-parse HEAD)"
runo "$LP" lessons match a/b.sh
check "without --record: the receipt still says recorded: no" \
    "lessons: 1 matched, 1 scanned, 1 with paths, projects: logproj, recorded: no" "$(printf '%s\n' "$out" | tail -n 1)"
check "without --record: the log is unchanged" 1 "$(wc -l < "$LOG" | tr -d ' ')"
check "without --record: the sidecar's HEAD has not moved" "$lhead" "$(git -C "$LS" rev-parse HEAD)"

git -C "$LP" checkout -q --detach
runo "$LP" lessons match a/b.sh --record start
check "detached HEAD: exits 0" 0 "$rc"
check "detached HEAD: still prints the match" \
    "exact${TAB}docs/solutions/x/hit-2026-05-05.md${TAB}Logged" "$(printf '%s\n' "$out" | head -n 1)"
check "detached HEAD: recorded: no, with the reason" \
    "lessons: 1 matched, 1 scanned, 1 with paths, projects: logproj, recorded: no: HEAD is detached" \
    "$(printf '%s\n' "$out" | tail -n 1)"
check "detached HEAD: the sidecar's HEAD has not moved" "$lhead" "$(git -C "$LS" rev-parse HEAD)"
git -C "$LP" checkout -q feat/x

runo "$LP" lessons match --record start
check "--record start with no paths: exits 0" 0 "$rc"
check "--record start with no paths: records outcome no-files" no-files "$(tail -n 1 "$LOG" | jq -r .outcome)"
check "--record start with no paths: records no files" '[]' "$(tail -n 1 "$LOG" | jq -c .files)"

# An append cut off before its newline: the next record must not be glued onto
# it, and the file must hold complete lines only.
printf '%s' '{"at":"2026-01-01T00:00:00Z","branch":"feat/x","phase":"st' >> "$LOG"
runo "$LP" lessons match a/b.sh --record changed
check "after an interrupted append: exits 0" 0 "$rc"
check "after an interrupted append: the file ends in a newline" 0a "$(tail -c 1 "$LOG" | od -An -tx1 | tr -d ' ')"
if jq -e . "$LOG" >/dev/null 2>&1; then ok "after an interrupted append: every line parses as JSON"
else bad "after an interrupted append: every line parses as JSON" "$(cat "$LOG")"; fi
check "after an interrupted append: the new record is the last line" changed "$(tail -n 1 "$LOG" | jq -r .phase)"
check "after an interrupted append: the partial line is gone" 0 "$(grep -c '"phase":"st$' "$LOG")"

# A lookup that fails while --record is set: nonzero exit, nothing on stdout,
# and a record whose outcome is failed, so the log never reads it as "none".
if [ "$(id -u)" -ne 0 ]; then
    lesson "$LP" "y/locked-2026-05-05.md" "Locked" "paths: [a/b.sh]"
    chmod 000 "$LP/docs/solutions/y/locked-2026-05-05.md"
    nlines="$(wc -l < "$LOG" | tr -d ' ')"
    runo "$LP" lessons match a/b.sh --record changed
    check "unreadable lesson with --record: exits 1" 1 "$rc"
    check "unreadable lesson with --record: nothing on stdout" "" "$out"
    check "unreadable lesson with --record: one record appended" "$((nlines + 1))" "$(wc -l < "$LOG" | tr -d ' ')"
    check "unreadable lesson with --record: its outcome is failed" failed "$(tail -n 1 "$LOG" | jq -r .outcome)"
    case "$err" in *"recorded as failed"*) ok "unreadable lesson with --record: stderr says it was recorded" ;;
        *) bad "unreadable lesson with --record: stderr says it was recorded" "stderr: $err" ;; esac
    chmod 644 "$LP/docs/solutions/y/locked-2026-05-05.md"
    rm -f "$LP/docs/solutions/y/locked-2026-05-05.md"
fi

# The matching step failing, with the header scan intact. The shim fails only
# the matcher's awk call, which is the one given -F.
fshim="$tmp/failshim"
mkdir -p "$fshim"
realawk="$(command -v awk)"
printf '#!/bin/sh\n[ "$1" = -F ] && { echo "awk: forced failure" >&2; exit 2; }\nexec "%s" "$@"\n' "$realawk" > "$fshim/awk"
chmod +x "$fshim/awk"
nlines="$(wc -l < "$LOG" | tr -d ' ')"
out="$(cd "$LP" && PATH="$fshim:$PATH" "$BASH" "$SC" lessons match a/b.sh --record changed 2>"$tmp/stderr")"; rc=$?
err="$(cat "$tmp/stderr")"
check "a failing match step: exits 1" 1 "$rc"
check "a failing match step: nothing on stdout, never the no-match line" "" "$out"
check "a failing match step: its record's outcome is failed" failed "$(tail -n 1 "$LOG" | jq -r .outcome)"
check "a failing match step: one record appended" "$((nlines + 1))" "$(wc -l < "$LOG" | tr -d ' ')"
out="$(cd "$LP" && PATH="$fshim:$PATH" "$BASH" "$SC" lessons match a/b.sh 2>"$tmp/stderr")"; rc=$?
check "a failing match step without --record: exits 1" 1 "$rc"
check "a failing match step without --record: nothing on stdout" "" "$out"

mkproj
git -C "$P" checkout -q -b feat/y
lesson "$P" "x/nosc-2026-05-05.md" "No sidecar" "paths: [a/b.sh]"
runo "$P" lessons match a/b.sh --record start
check "no sidecar: exits 0" 0 "$rc"
check "no sidecar: still prints the match" \
    "exact${TAB}docs/solutions/x/nosc-2026-05-05.md${TAB}No sidecar" "$(printf '%s\n' "$out" | head -n 1)"
check "no sidecar: recorded: no, with the reason" "recorded: no: no sidecar resolves" \
    "$(printf '%s\n' "$out" | tail -n 1 | sed 's/.*, recorded: /recorded: /')"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
