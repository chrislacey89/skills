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

# A lesson with several folder pointers ranks by the deepest one that matches,
# not the first one listed: "Two folders" lists src first, but its src/core/io
# pointer puts it above "One folder" at src/core.
mkproj
lesson "$P" "a/two-2026-01-01.md" "Two folders" "paths: [src, src/core/io]"
lesson "$P" "b/one-2026-01-01.md" "One folder" "paths: [src/core]"
runo "$P" lessons match src/core/io/x.sh
check "several folder pointers: ranked by the deepest that matches" \
"folder${TAB}docs/solutions/a/two-2026-01-01.md${TAB}Two folders
folder${TAB}docs/solutions/b/one-2026-01-01.md${TAB}One folder" "$(printf '%s\n' "$out" | sed '$d')"

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
section "real lessons as fixtures: title, CRLF, quotes"

# Copied from this repo's own corpus, so the reader meets real input: this
# lesson has `# ` comment lines inside its code blocks after its title. Each
# copy gains one paths line after volatility.
REAL="$repo_root/docs/solutions/testing-patterns/mutate-the-oracle-not-only-the-subject-2026-08-19.md"
[ -f "$REAL" ] || fatal "the real-lesson fixture is gone: $REAL"
[ "$(grep -c '^# ' "$REAL")" -gt 1 ] || fatal "the real-lesson fixture no longer has a # line after its title"
REAL_TITLE="$(grep -m 1 '^# ' "$REAL" | sed 's/^# //')"
mkproj
mkdir -p "$P/docs/solutions/real"
awk '{ print } /^volatility:/ { print "paths: [real/plain.sh]" }' "$REAL" > "$P/docs/solutions/real/plain-2026-08-19.md"
awk '{ printf "%s\r\n", $0 } /^volatility:/ { printf "paths: [real/crlf.sh]\r\n" }' "$REAL" > "$P/docs/solutions/real/crlf-2026-08-19.md"
awk '{ print } /^volatility:/ { print "paths: [\"real/quoted.sh\"]" }' "$REAL" > "$P/docs/solutions/real/quoted-2026-08-19.md"
runo "$P" lessons match real/plain.sh
check "a real lesson's title is its first # heading, not a later code comment" \
    "exact${TAB}docs/solutions/real/plain-2026-08-19.md${TAB}$REAL_TITLE" "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" lessons match real/crlf.sh
check "the same lesson with CRLF line endings: found, title clean" \
    "exact${TAB}docs/solutions/real/crlf-2026-08-19.md${TAB}$REAL_TITLE" "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" lessons match real/quoted.sh
check "a quoted paths entry matches the bare path" \
    "exact${TAB}docs/solutions/real/quoted-2026-08-19.md${TAB}$REAL_TITLE" "$(printf '%s\n' "$out" | head -n 1)"

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
# With no sidecar, the project is named for its main checkout, so every
# worktree of one project reports the same name and not its own folder's.
mkproj
lesson "$P" "x/wt-2026-01-01.md" "In a worktree" "paths: [a.sh]"
git -C "$P" add docs && git -C "$P" commit -q -m "lesson"
git -C "$P" worktree add -q "$tmp/wt-feature-branch" -b feature-branch
runo "$tmp/wt-feature-branch" lessons match a.sh
check "in a worktree with no sidecar: projects names the main checkout" \
    "projects: $(basename "$P")" "$(printf '%s\n' "$out" | tail -n 1 | sed 's/.*, \(projects: [^,]*\),.*/\1/')"

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
lessons: 1 matched, 1 scanned, 1 with paths, projects: $(basename "$BP"), recorded: no: no sidecar resolves" "$out"
    out="$(cd "$BP" && TEST_FILES="" "${runner[@]}" "$lscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: no file list: exits 0" 0 "$rc"
    check "$sh: no file list: says no file list was given" "no file list given; nothing to match" \
        "$(printf '%s\n' "$out" | head -n 1)"
    out="$(cd "$tmp" && TEST_FILES="lib/one.sh" "${runner[@]}" "$lscript" 2>"$tmp/stderr")"; rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$out" ]; then ok "$sh: a failed lookup exits nonzero with nothing on stdout"
    else bad "$sh: a failed lookup exits nonzero with nothing on stdout" "rc=$rc out=[$out]"; fi
done

# -----------------------------------------------------------------------------
section "/execute's lookup blocks record their phase"

# One project with a sidecar, a base branch, and a slice branch that changed
# two files. The Step 1 block records phase start for the files it is given;
# the Step 4 block records phase changed for the files the branch changed.
mkproj
XP="$P"
runo "$XP" init --name blocks --mode owned --write sidecar --in-tree-path none --no-migrate-archive
XS="$out"
[ -d "$XS" ] || fatal "init did not create a sidecar: $err"
runo "$XP" config set base_ref main
[ "$rc" -eq 0 ] || fatal "config set base_ref main failed: $err"
lesson "$XP" "x/changed-2026-06-06.md" "Changed" "paths: [lib]"
git -C "$XP" add docs && git -C "$XP" commit -q -m "lesson"
git -C "$XP" checkout -q -b slice/one
mkdir -p "$XP/lib"
printf 'a\n' > "$XP/lib/one.sh"; printf 'b\n' > "$XP/top.txt"
git -C "$XP" add lib top.txt && git -C "$XP" commit -q -m "slice work"
XLOG="$XS/lookups/slice%2Fone.jsonl"
cblock="$(awk '/^<!-- sidecar-read: execute-lessons-changed -->$/ { on = 1; next }
               on && /^```bash$/ { inb = 1; next }
               inb && /^```$/ { exit }
               inb { print }' "$EXECUTE")"
[ -n "$cblock" ] || fatal "execute/SKILL.md has no \`\`\`bash block after <!-- sidecar-read: execute-lessons-changed -->"
ok "execute/SKILL.md carries the lessons-changed block"
cscript="$(printf '%s\n' "$cblock" | sed -e "s|^SC=.*|SC=\"$SC\"|")"
# The Step 4 block sits in Tier 1, after the slice-range diff it reuses.
cline="$(grep -n '^<!-- sidecar-read: execute-lessons-changed -->$' "$EXECUTE" | cut -d: -f1)"
t1line="$(grep -n '^#### Tier 1: Static Verification' "$EXECUTE" | cut -d: -f1)"
t2line="$(grep -n '^#### Tier 2: Command Verification' "$EXECUTE" | cut -d: -f1)"
if [ -n "$t1line" ] && [ -n "$t2line" ] && [ "$t1line" -lt "$cline" ] && [ "$cline" -lt "$t2line" ]; then
    ok "the lessons-changed block sits in Step 4 Tier 1"
else
    bad "the lessons-changed block sits in Step 4 Tier 1" "tier1=$t1line block=$cline tier2=$t2line"
fi
for sh in $block_shells; do
    if [ "$sh" = zsh ]; then runner=(zsh -f -c); else runner=("$BASH" -c); fi
    : > "$XLOG" 2>/dev/null || { mkdir -p "$XS/lookups"; : > "$XLOG"; }
    out="$(cd "$XP" && TEST_FILES="lib/one.sh" "${runner[@]}" "$lscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: Step 1 block with a sidecar: exits 0" 0 "$rc"
    check "$sh: Step 1 block: recorded: yes" "recorded: yes" "$(printf '%s\n' "$out" | tail -n 1 | sed 's/.*, recorded: /recorded: /')"
    check "$sh: Step 1 block: the record's phase is start" start "$(tail -n 1 "$XLOG" | jq -r .phase)"
    out="$(cd "$XP" && "${runner[@]}" "$cscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: Step 4 block: exits 0" 0 "$rc"
    check "$sh: Step 4 block: prints the lesson for the changed file" \
        "folder${TAB}docs/solutions/x/changed-2026-06-06.md${TAB}Changed" "$(printf '%s\n' "$out" | head -n 1)"
    check "$sh: Step 4 block: the record's phase is changed" changed "$(tail -n 1 "$XLOG" | jq -r .phase)"
    check "$sh: Step 4 block: the record names the files the slice changed" '["lib/one.sh","top.txt"]' \
        "$(tail -n 1 "$XLOG" | jq -c '.files | sort')"
done

# -----------------------------------------------------------------------------
section "the Review Notes template carries no lookup output"

# Review Notes go into the PR body, which other people read; lesson names are
# private sidecar content. The template is extracted as /execute ships it.
notes="$(awk '/^```markdown$/ { inb = 1; buf = ""; next }
              inb && /^```$/ { if (buf ~ /## Review Notes/) { printf "%s", buf; exit } inb = 0; next }
              inb { buf = buf $0 "\n" }' "$EXECUTE")"
[ -n "$notes" ] || fatal "execute/SKILL.md has no markdown block carrying ## Review Notes"
ok "execute/SKILL.md carries the Review Notes template"
leaks="$(printf '%s\n' "$notes" | grep -nE 'lessons match|lessons: [0-9]|recorded: (yes|no)|lookups/|^(exact|folder)	|docs/solutions/' || true)"
check "the template names no lesson lookup, receipt, run log, or lesson" "" "$leaks"

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

# -----------------------------------------------------------------------------
section "review fixes: a failure listing the lesson directories is recorded"

# The sidecar is resolved before any step that can fail, so a listing failure
# under --record is recorded as failed and never reads "no sidecar resolves".
# solutions-dirs fails when it cannot create the sidecar's solutions/: the
# sidecar is made read-only with solutions/ gone, and lookups/ kept writable.
if [ "$(id -u)" -ne 0 ]; then
    mkproj
    FP="$P"
    runo "$FP" init --name listfail --mode owned --write sidecar --in-tree-path none --no-migrate-archive
    FS="$out"
    [ -d "$FS" ] || fatal "init did not create a sidecar: $err"
    git -C "$FP" checkout -q -b feat/l
    mkdir -p "$FS/lookups"
    rmdir "$FS/solutions" 2>/dev/null || rm -rf "$FS/solutions"
    chmod 555 "$FS"
    runo "$FP" lessons match a/b.sh --record start
    chmod 755 "$FS"
    check "listing fails with --record: exits 1" 1 "$rc"
    check "listing fails with --record: nothing on stdout" "" "$out"
    case "$err" in *"could not list the lesson directories"*"(recorded as failed)"*) ok "listing fails with --record: stderr says it was recorded as failed" ;;
        *) bad "listing fails with --record: stderr says it was recorded as failed" "stderr: $err" ;; esac
    check "listing fails with --record: the record's outcome is failed" failed \
        "$(tail -n 1 "$FS/lookups/feat%2Fl.jsonl" 2>/dev/null | jq -r .outcome)"
    check "listing fails with --record: the record names the sidecar's project" '["listfail"]' \
        "$(tail -n 1 "$FS/lookups/feat%2Fl.jsonl" 2>/dev/null | jq -c .projects)"
fi

section "review fixes: guards that need a test that fails without them"

# The matcher's awk runs for real and prints its receipt, then exits nonzero:
# the receipt guard alone would take that as a complete result.
mkproj
GP="$P"
lesson "$GP" "x/g-2026-01-01.md" "Guarded" "paths: [a/b.sh]"
rshim="$tmp/receiptshim"
mkdir -p "$rshim"
printf '#!/bin/sh\nif [ "$1" = -F ]; then "%s" "$@"; exit 3; fi\nexec "%s" "$@"\n' "$(command -v awk)" "$(command -v awk)" > "$rshim/awk"
chmod +x "$rshim/awk"
out="$(cd "$GP" && PATH="$rshim:$PATH" "$BASH" "$SC" lessons match a/b.sh 2>"$tmp/stderr")"; rc=$?
err="$(cat "$tmp/stderr")"
check "a matcher that prints its receipt then fails: exits 1" 1 "$rc"
check "a matcher that prints its receipt then fails: nothing on stdout" "" "$out"

# The run log's directory cannot be written: the receipt says so, and no line
# is added.
if [ "$(id -u)" -ne 0 ]; then
    mkproj
    WP="$P"
    runo "$WP" init --name nowrite --mode owned --write sidecar --in-tree-path none --no-migrate-archive
    WS="$out"
    [ -d "$WS" ] || fatal "init did not create a sidecar: $err"
    git -C "$WP" checkout -q -b feat/w
    lesson "$WP" "x/w-2026-01-01.md" "Unwritten" "paths: [a/b.sh]"
    mkdir -p "$WS/lookups"
    printf '%s\n' '{"at":"2026-01-01T00:00:00Z"}' > "$WS/lookups/feat%2Fw.jsonl"
    chmod 555 "$WS/lookups"
    runo "$WP" lessons match a/b.sh --record start
    chmod 755 "$WS/lookups"
    check "an unwritable lookups/: exits 0" 0 "$rc"
    check "an unwritable lookups/: the receipt says the log could not be written" \
        "recorded: no: the run log could not be written" "$(printf '%s\n' "$out" | tail -n 1 | sed 's/.*, recorded: /recorded: /')"
    check "an unwritable lookups/: no line is added" 1 "$(wc -l < "$WS/lookups/feat%2Fw.jsonl" | tr -d ' ')"
fi

# -----------------------------------------------------------------------------
section "lessons check: loose ends (#750)"

# lessons check reports and never edits: every lesson file is compared byte
# for byte before and after.
mkproj
CP="$P"
mkdir -p "$CP/lib/sub" "$CP/tools"
: > "$CP/lib/sub/real.sh"
: > "$CP/tools/t.sh"
lesson "$CP" "a/nokey-2026-01-01.md" "No paths key"
lesson "$CP" "a/empty-2026-01-01.md" "Empty paths" "paths: []"
lesson "$CP" "b/good-2026-01-01.md" "Good" "paths: [lib/sub/real.sh, tools/]"
lesson "$CP" "b/dead-2026-01-01.md" "Dead path" "paths: [lib/sub/real.sh, lib/gone.sh, ../outside.sh]"
lesson "$CP" "c/multi-2026-01-01.md" "Multi-line" "paths:" "  - lib/sub/real.sh"
lesson "$CP" "c/space-2026-01-01.md" "Space entry" "paths: [\"lib/a b.sh\", tools]"
lesson "$CP" "c/comma-2026-01-01.md" "Comma entry" "paths: [\"lib/a,b.sh\"]"
lesson "$CP" "c/bracket-2026-01-01.md" "Bracket entry" "paths: [[tools]]"
lesson "$CP" "c/related-2026-01-01.md" "Bad related" "paths: [tools]" "related: not-a-list.md"
before="$(cd "$CP" && find docs -type f -exec cksum {} + | LC_ALL=C sort)"
runo "$CP" lessons check
check "check: exits 0" 0 "$rc"
check "check: one line per loose end in lesson order, unlisted n/a, then the total" \
"no-paths${TAB}docs/solutions/a/empty-2026-01-01.md${TAB}paths is empty
no-paths${TAB}docs/solutions/a/nokey-2026-01-01.md${TAB}no paths key
dead-path${TAB}docs/solutions/b/dead-2026-01-01.md${TAB}lib/gone.sh
dead-path${TAB}docs/solutions/b/dead-2026-01-01.md${TAB}../outside.sh (outside the project tree)
bad-list${TAB}docs/solutions/c/bracket-2026-01-01.md${TAB}paths: an entry holds a comma, space, or bracket: [tools]
bad-list${TAB}docs/solutions/c/comma-2026-01-01.md${TAB}paths: an entry holds a comma, space, or bracket: lib/a,b.sh
bad-list${TAB}docs/solutions/c/multi-2026-01-01.md${TAB}paths: not a one-line bracket list
bad-list${TAB}docs/solutions/c/related-2026-01-01.md${TAB}related: not a one-line bracket list
bad-list${TAB}docs/solutions/c/space-2026-01-01.md${TAB}paths: an entry holds a comma, space, or bracket: lib/a b.sh
unlisted: n/a
loose ends: 9" "$out"
check "check: every lesson file is byte-identical" "$before" "$(cd "$CP" && find docs -type f -exec cksum {} + | LC_ALL=C sort)"

runo "$CP" lessons check docs/solutions/b/dead-2026-01-01.md
check "check <file>: exits 0" 0 "$rc"
check "check <file>: that lesson only" \
"dead-path${TAB}docs/solutions/b/dead-2026-01-01.md${TAB}lib/gone.sh
dead-path${TAB}docs/solutions/b/dead-2026-01-01.md${TAB}../outside.sh (outside the project tree)
unlisted: n/a
loose ends: 2" "$out"
runo "$CP/docs" lessons check solutions/b/good-2026-01-01.md
check "check <file> from a subdirectory: a clean lesson" \
"unlisted: n/a
loose ends: 0" "$out"
runo "$CP" lessons check docs/solutions/none.md
check "check <file> that does not exist: exits 1" 1 "$rc"
check "check <file> that does not exist: nothing on stdout" "" "$out"
runo "$CP" lessons check a b
check "check with two files: exits 2" 2 "$rc"

# An unterminated frontmatter lends nothing to the next file in either order.
for order in first last; do
    mkproj
    if [ "$order" = first ]; then u="a-open-2026-01-01.md"; else u="z-open-2026-01-01.md"; fi
    mkdir -p "$P/docs/solutions/r" "$P/x"
    : > "$P/x/real.sh"
    printf -- '---\ntitle: "Open"\npaths: [only/gone.sh]\n\n# Open\n' > "$P/docs/solutions/r/$u"
    lesson "$P" "r/b-tail-2026-01-01.md" "Tail" "paths: [x/real.sh]"
    runo "$P" lessons check
    check "check, unterminated $order: the open file has no paths, the next is clean" \
"no-paths${TAB}docs/solutions/r/$u${TAB}no paths key
unlisted: n/a
loose ends: 1" "$out"
done

# An unreadable store: the check did not run, so it exits nonzero.
if [ "$(id -u)" -ne 0 ]; then
    mkproj
    lesson "$P" "y/b-2026-01-01.md" "Unreadable" "paths: [a]"
    chmod 000 "$P/docs/solutions/y/b-2026-01-01.md"
    runo "$P" lessons check
    check "check over an unreadable lesson: exits 1" 1 "$rc"
    check "check over an unreadable lesson: nothing on stdout" "" "$out"
    chmod 644 "$P/docs/solutions/y/b-2026-01-01.md"
fi

section "lessons check: unlisted on the sidecar backend (#750)"

# A guest sidecar answers sidecar for backend slices; a lesson no work item
# lists is reported, one a work item lists is not.
mkproj
UP="$P"
runo "$UP" init --name unlisted --mode guest --write sidecar --in-tree-path none --no-migrate-archive
US="$out"
[ -d "$US" ] || fatal "init did not create a sidecar: $err"
runo "$UP" backend slices
check "the guest fixture answers sidecar for backend slices" sidecar "$out"
mkdir -p "$UP/lib"; : > "$UP/lib/x.sh"
lesson "$UP" "a/listed-2026-01-01.md" "Listed" "paths: [lib/x.sh]"
lesson "$UP" "a/loose-2026-01-01.md" "Loose" "paths: [lib/x.sh]"
mkdir -p "$US/solutions/s"
printf -- '---\npaths: [lib/x.sh]\n---\n\n# Side\n' > "$US/solutions/s/side-2026-01-01.md"
printf 'slice body\n' > "$tmp/body"
runo "$UP" work create --kind slice --body-file "$tmp/body"
wid="$out"
runo "$UP" work lesson "$wid" docs/solutions/a/listed-2026-01-01.md
runo "$UP" work lesson "$wid" "$US/solutions/s/side-2026-01-01.md"
runo "$UP" lessons check
check "sidecar backend: one unlisted line, for the lesson no work item lists" \
"unlisted${TAB}docs/solutions/a/loose-2026-01-01.md${TAB}no work item lists it
loose ends: 1" "$out"
runo "$UP" lessons check docs/solutions/a/listed-2026-01-01.md
check "sidecar backend: a listed lesson checked alone is clean" "loose ends: 0" "$out"

section "/compound Phase 5's lessons-check block, run as written (#750)"

COMPOUND="$repo_root/compound/SKILL.md"
kblock="$(awk '/^<!-- sidecar-read: compound-lessons-check -->$/ { on = 1; next }
               on && /^```bash$/ { inb = 1; next }
               inb && /^```$/ { exit }
               inb { print }' "$COMPOUND")"
[ -n "$kblock" ] || fatal "compound/SKILL.md has no \`\`\`bash block after <!-- sidecar-read: compound-lessons-check -->"
ok "compound/SKILL.md carries the lessons-check block"
case "$kblock" in *'LESSON='*) ;; *) fatal "the lessons-check block sets no LESSON" ;; esac
kscript="$(printf '%s\n' "$kblock" | sed -e "s|^SC=.*|SC=\"$SC\"|" -e 's|^LESSON=.*|LESSON="$TEST_LESSON"|')"
# It sits in Phase 5, after the work-item block that follows the save.
kline="$(grep -n '^<!-- sidecar-read: compound-lessons-check -->$' "$COMPOUND" | cut -d: -f1)"
wline="$(grep -n '^<!-- work-lesson: compound -->$' "$COMPOUND" | cut -d: -f1)"
p6line="$(grep -n '^### Phase 6' "$COMPOUND" | cut -d: -f1)"
if [ -n "$wline" ] && [ -n "$p6line" ] && [ "$wline" -lt "$kline" ] && [ "$kline" -lt "$p6line" ]; then
    ok "the block sits in Phase 5 after the work-item block"
else
    bad "the block sits in Phase 5 after the work-item block" "work-lesson=$wline check=$kline phase6=$p6line"
fi
for sh in $block_shells; do
    if [ "$sh" = zsh ]; then runner=(zsh -f -c); else runner=("$BASH" -c); fi
    out="$(cd "$CP" && TEST_LESSON="docs/solutions/b/dead-2026-01-01.md" "${runner[@]}" "$kscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: exits 0" 0 "$rc"
    check "$sh: prints the check for the lesson it was given" \
"dead-path${TAB}docs/solutions/b/dead-2026-01-01.md${TAB}lib/gone.sh
dead-path${TAB}docs/solutions/b/dead-2026-01-01.md${TAB}../outside.sh (outside the project tree)
unlisted: n/a
loose ends: 2" "$out"
    out="$(cd "$UP" && TEST_LESSON="$US/solutions/s/side-2026-01-01.md" "${runner[@]}" "$kscript" 2>"$tmp/stderr")"; rc=$?
    check "$sh: a sidecar lesson by its absolute path: clean" "loose ends: 0" "$out"
done

# -----------------------------------------------------------------------------
section "replaces and related across the group (#751)"

# Two projects in one solutions.system group. The member's sidecar holds a
# lesson that replaces one of this project's lessons; nothing here may write
# into the member's directory.
mkproj
MP="$P"
runo "$MP" init --name member --mode owned --write sidecar --in-tree-path none --no-migrate-archive
MS="$out"
[ -d "$MS" ] || fatal "init did not create the member's sidecar: $err"
runo "$MP" config set system grp
mkproj
GRP="$P"
runo "$GRP" init --name home --mode owned --write sidecar --in-tree-path none --no-migrate-archive
GS="$out"
[ -d "$GS" ] || fatal "init did not create the home sidecar: $err"
runo "$GRP" config set system grp
mkdir -p "$GRP/lib"; : > "$GRP/lib/a.sh"
lesson "$GRP" "x/old-2026-01-01.md" "Old" "paths: [lib/a.sh]"
lesson "$GRP" "x/new-2026-02-01.md" "New" "paths: [lib]" "replaces: [old-2026-01-01.md]" "related: [peer-2026-01-01.md]"
lesson "$GRP" "x/plain-2026-01-01.md" "Plain" "paths: [lib/a.sh]"
lesson "$GRP" "y/dup-2026-01-01.md" "Dup one" "paths: [lib]"
lesson "$GRP" "z/dup-2026-01-01.md" "Dup two" "paths: [lib]"
lesson "$GRP" "x/links-2026-01-01.md" "Links" "paths: [lib]" "related: [nowhere-2026-01-01.md, dup-2026-01-01.md, peer-2026-01-01.md]"
mkdir -p "$MS/solutions/m"
printf -- '---\npaths: [svc]\nreplaces: [plain-2026-01-01.md]\n---\n\n# Member lesson\n' > "$MS/solutions/m/peer-2026-01-01.md"
git -C "$MS" add solutions && git -C "$MS" commit -q -m "member lesson"
runo "$GRP" related-solutions-dirs
check "the group fixture: the member's store is a related dir" "$MS/solutions" "$out"
msum() { (cd "$MS" && find . -path ./.git -prune -o -type f -exec cksum {} + | LC_ALL=C sort; git -C "$MS" rev-parse HEAD); }
mbefore="$(msum)"

runo "$GRP" lessons match lib/a.sh
check "match: exits 0" 0 "$rc"
check "match: replaced-by on a lesson another lesson replaces, here or in the group" \
"exact${TAB}docs/solutions/x/old-2026-01-01.md${TAB}Old${TAB}replaced-by:new-2026-02-01.md
exact${TAB}docs/solutions/x/plain-2026-01-01.md${TAB}Plain${TAB}replaced-by:peer-2026-01-01.md" "$(printf '%s\n' "$out" | grep '^exact')"
check "match: a lesson nothing replaces keeps three fields" \
"folder${TAB}docs/solutions/x/links-2026-01-01.md${TAB}Links" "$(printf '%s\n' "$out" | grep 'links-')"
check "match: the member's lesson is not matched by path" 0 "$(printf '%s\n' "$out" | awk -F '\t' '$2 ~ /peer-/' | wc -l | tr -d ' ')"

runo "$GRP" trace docs/solutions/x/new-2026-02-01.md
check "trace: replaces and related lines after the existing ones" \
"  replaces  $GRP/docs/solutions/x/old-2026-01-01.md
  related  related project: $MS/solutions/m/peer-2026-01-01.md" "$(printf '%s\n' "$out" | grep -E '^  (replaces|related|replaced by)  ')"
check "trace: the new lines come last" "  related  related project: $MS/solutions/m/peer-2026-01-01.md" "$(printf '%s\n' "$out" | tail -n 1)"
runo "$GRP" trace docs/solutions/x/old-2026-01-01.md
check "trace: replaced by, derived from the other lesson's replaces" \
"  replaced by  $GRP/docs/solutions/x/new-2026-02-01.md" "$(printf '%s\n' "$out" | grep -E '^  replaced by  ')"
runo "$GRP" trace docs/solutions/x/plain-2026-01-01.md --json
check "trace --json: replaced_by names the member's lesson" \
"[{\"path\":\"$MS/solutions/m/peer-2026-01-01.md\",\"related_project\":true}]" "$(printf '%s' "$out" | jq -c .replaced_by)"
runo "$GRP" trace docs/solutions/x/links-2026-01-01.md --json
check "trace --json: related lists each name with what it resolves to" \
"[{\"name\":\"nowhere-2026-01-01.md\",\"resolved\":[]},{\"name\":\"dup-2026-01-01.md\",\"resolved\":[{\"path\":\"$GRP/docs/solutions/y/dup-2026-01-01.md\",\"related_project\":false},{\"path\":\"$GRP/docs/solutions/z/dup-2026-01-01.md\",\"related_project\":false}]},{\"name\":\"peer-2026-01-01.md\",\"resolved\":[{\"path\":\"$MS/solutions/m/peer-2026-01-01.md\",\"related_project\":true}]}]" \
    "$(printf '%s' "$out" | jq -c .related)"
check "trace --json: no replaces key gives []" '[]' "$(printf '%s' "$out" | jq -c .replaces)"
runo "$GRP" trace docs/solutions/x/links-2026-01-01.md
check "trace: a name that resolves to nothing is MISSING" "  related  MISSING: nowhere-2026-01-01.md" \
    "$(printf '%s\n' "$out" | grep 'MISSING: nowhere')"

runo "$GRP" lessons check docs/solutions/x/links-2026-01-01.md
check "check: dead-link and ambiguous-link for a lesson's names" \
"dead-link${TAB}docs/solutions/x/links-2026-01-01.md${TAB}related: nowhere-2026-01-01.md
ambiguous-link${TAB}docs/solutions/x/links-2026-01-01.md${TAB}related: dup-2026-01-01.md (2 files)
unlisted${TAB}docs/solutions/x/links-2026-01-01.md${TAB}no work item lists it
loose ends: 3" "$out"
runo "$GRP" lessons check docs/solutions/x/new-2026-02-01.md
check "check: names that resolve here and in the group are not loose" \
"unlisted${TAB}docs/solutions/x/new-2026-02-01.md${TAB}no work item lists it
loose ends: 1" "$out"
check "no command wrote to the member's directory" "$mbefore" "$(msum)"

# A lesson with no replaces or related, in a project with no group: output as
# before this slice.
mkproj
lesson "$P" "x/solo-2026-01-01.md" "Solo" "paths: [a.sh]"
runo "$P" lessons match a.sh
check "no links anywhere: the match line has three fields" "exact${TAB}docs/solutions/x/solo-2026-01-01.md${TAB}Solo" \
    "$(printf '%s\n' "$out" | head -n 1)"
runo "$P" trace docs/solutions/x/solo-2026-01-01.md
check "no links anywhere: trace prints only the lesson line" "lesson  $P/docs/solutions/x/solo-2026-01-01.md" "$out"
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
