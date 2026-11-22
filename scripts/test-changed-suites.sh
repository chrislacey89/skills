#!/usr/bin/env bash
# test-changed-suites.sh — the local run picks suites from changed paths, and
# may not miss a suite without saying so (#806).
#
# THE DRIFT CLASS. pre-push runs scripts/run-changed-suites.sh, which runs the
# suites scripts/suites-for-paths.sh selects: the ones whose text names a
# changed path, plus scripts/suites-always.txt. A suite that reaches its files
# through a glob names none of them, so absent from that list it is never
# selected, and the push reports green without it. A selection of nothing has
# the same shape: exit 0 having run nothing
# (docs/solutions/devops/declared-test-command-exits-zero-having-run-nothing-2026-11-18.md).
#
# WHAT IT PINS:
#   1. suites-for-paths.sh, on the real tree and on a fixture: the suites that
#      name a path, the changed suite itself, every always-run suite, and a
#      nonzero exit on a missing, empty, or stale list.
#   2. run-changed-suites.sh, on a fixture repo with planted suites: which
#      ones ran, with which arguments, and what a failure or an unresolvable
#      base does.
#   3. Every suite with a glob in its code is in the list, self-tested by
#      removing one line from a copy and by a planted suite.
#   4. lefthook.yml runs the runner on pre-push and the one cheap suite on
#      pre-commit, and the CI workflow runs every suite on disk.
#
# NOT CAUGHT. A suite that builds a path from variables has no glob to see.
# suites-always.txt's header says how those were found.

set -u
export LC_ALL=C
# A git hook exports these, and the fixture repos below must not inherit them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 2

SELECT="scripts/suites-for-paths.sh"
RUNNER="scripts/run-changed-suites.sh"
ALWAYS="scripts/suites-always.txt"
WORKFLOW=".github/workflows/validate-skills.yml"
HOOKS="lefthook.yml"

pass=0
fail=0
section() { printf '\n=== %s ===\n' "$1"; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ $# -ge 2 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
nonzero() { if [ "$2" -ne 0 ]; then ok "$1"; else bad "$1" "exit 0"; fi; }

for f in "$SELECT" "$RUNNER" "$ALWAYS" "$WORKFLOW" "$HOOKS"; do
    [ -f "$f" ] || fatal "$f is missing; this suite has nothing to check"
done

# list_entries <file> — the suites a list file holds, comments and blanks dropped.
list_entries() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# ----------------------------------------------------------------------------
section "1. suites-for-paths.sh, on the real tree"

probe="fix-findings/SKILL.md"
named="$(grep -lF -- "$probe" scripts/test-*.sh)"
[ -n "$named" ] || fatal "no suite names $probe; the probe no longer measures anything"
always="$(list_entries "$ALWAYS")"
[ -n "$always" ] || fatal "$ALWAYS lists no suite"
printed="$(bash "$SELECT" "$probe")"
check "$probe selects exactly the suites that name it plus every always-run suite" \
    "$(printf '%s\n%s\n' "$named" "$always" | sort -u)" "$(printf '%s\n' "$printed" | sort)"
check "no suite is printed twice" "" "$(printf '%s\n' "$printed" | sort | uniq -d)"

# ----------------------------------------------------------------------------
section "2. suites-for-paths.sh, on a fixture"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Changed Suites Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false

fx="$tmp/fx"
mkdir -p "$fx/scripts" "$fx/alpha" "$fx/beta" "$fx/two words" "$fx/.github/workflows"
cp "$SELECT" "$RUNNER" "$fx/scripts/"
export RAN="$tmp/ran"

# plant <name> <the path its text names> — a suite that records that it ran, and its args.
plant() {
    # shellcheck disable=SC2016  # $RAN and $* are for the planted suite to expand
    printf '#!/usr/bin/env bash\n# reads %s\necho "%s${*:+ $*}" >>"$RAN"\n' "$2" "$1" >"$fx/scripts/test-$1.sh"
}
plant alpha "alpha/SKILL.md"
plant beta "beta/SKILL.md"
plant spaced "two words/notes.md"
plant always "nothing"
plant args "nothing else"
plant fixture-git-isolation "alpha/SKILL.md"
plant fixture-root-collision "alpha/SKILL.md"
printf '# a comment\n\nscripts/test-always.sh\nscripts/test-args.sh\n' >"$fx/$ALWAYS"
printf '      - name: Run args\n        run: bash scripts/test-args.sh beta/arg.md\n' >"$fx/$WORKFLOW"
printf 'alpha, one\nalpha, two\nalpha, three\n' >"$fx/alpha/SKILL.md"
printf 'beta\n' >"$fx/beta/SKILL.md"
printf 'notes\n' >"$fx/two words/notes.md"

# selection <path>... — what the fixture's script prints, as short names on one line.
selection() { (cd "$fx" && bash "$SELECT" "$@") | sed 's#^scripts/test-##; s#\.sh$##' | sort | paste -sd' ' -; }

check "a path selects the suites naming it, plus the always-run ones" \
    "alpha always args fixture-git-isolation fixture-root-collision" "$(selection alpha/SKILL.md)"
check "a leading ./ is the same path" "always args beta" "$(selection ./beta/SKILL.md)"
check "an absolute path inside the repo is the same path" "always args beta" "$(selection "$fx/beta/SKILL.md")"
check "a path with a space is one path" "always args spaced" "$(selection "two words/notes.md")"
check "two paths select both" "always args beta spaced" "$(selection beta/SKILL.md "two words/notes.md")"
check "a changed suite selects itself" "always args beta" "$(selection scripts/test-beta.sh)"
check "a deleted suite is not selected" "always args" "$(selection scripts/test-gone.sh)"
check "no paths print exactly the always-run suites" "always args" "$(selection)"

mv "$fx/$ALWAYS" "$tmp/list.saved"
out="$(cd "$fx" && bash "$SELECT" alpha/SKILL.md 2>/dev/null)"; rc=$?
nonzero "a missing list exits nonzero" "$rc"
check "a missing list prints no partial selection" "" "$out"
printf '# only a comment\n' >"$fx/$ALWAYS"
(cd "$fx" && bash "$SELECT" >/dev/null 2>&1); rc=$?
nonzero "a list with no suite exits nonzero, never an empty selection" "$rc"
printf 'scripts/test-gone.sh\n' >"$fx/$ALWAYS"
(cd "$fx" && bash "$SELECT" >/dev/null 2>&1); rc=$?
nonzero "a list naming a suite that is not on disk exits nonzero" "$rc"
cp "$tmp/list.saved" "$fx/$ALWAYS"

# ----------------------------------------------------------------------------
section "3. run-changed-suites.sh, on a fixture"

# run_fx [args...] — run the fixture's runner; sets out, rc, and ran.
run_fx() {
    : >"$RAN"
    out="$(cd "$fx" && bash "$RUNNER" "$@" 2>&1)"
    rc=$?
    ran="$(sort "$RAN" | paste -sd, -)"
}

run_fx alpha/SKILL.md
check "named paths: exit 0" 0 "$rc"
check "named paths: the selection runs with CI's arguments, and the CI-only suites do not" \
    "alpha,always,args beta/arg.md" "$ran"
case "$out" in
    *"3 suites ran"*) ok "the runner says how many suites ran" ;;
    *) bad "the runner says how many suites ran" "$out" ;;
esac

run_fx --all
check "--all runs every suite but the CI-only two" "alpha,always,args beta/arg.md,beta,spaced" "$ran"
run_fx --nonsense
nonzero "an unknown option is refused" "$rc"
check "an unknown option runs nothing" "" "$ran"

git -C "$fx" init -q -b prod
git -C "$fx" add -A
git -C "$fx" commit -q -m base
run_fx
nonzero "with no default branch to diff against, the runner exits nonzero" "$rc"
check "with no default branch, it runs nothing" "" "$ran"

git -C "$fx" update-ref refs/remotes/origin/prod HEAD
run_fx
check "a push that changes nothing still runs the always-run suites" "always,args beta/arg.md" "$ran"

# The default branch moves on (beta) after the branch forks (alpha renamed).
git -C "$fx" checkout -q -b feature
git -C "$fx" mv alpha/SKILL.md alpha/RENAMED.md
git -C "$fx" commit -q -m "rename alpha"
git -C "$fx" checkout -q prod
printf 'beta, moved on\n' >"$fx/beta/SKILL.md"
git -C "$fx" commit -q -am "base moves"
git -C "$fx" update-ref refs/remotes/origin/prod HEAD
git -C "$fx" checkout -q feature
run_fx
check "a push runs what reads its changes from the merge base, a renamed-from path included" \
    "alpha,always,args beta/arg.md" "$ran"

# origin/HEAD decides which branch is the default.
git -C "$fx" update-ref refs/remotes/origin/main feature
git -C "$fx" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
run_fx
check "the base is origin/HEAD's branch when it is set" "always,args beta/arg.md" "$ran"

# A hook's GIT_DIR must not reach a suite.
# shellcheck disable=SC2016  # the planted suite expands these
printf '#!/usr/bin/env bash\necho "always git_dir=${GIT_DIR:-unset}" >>"$RAN"\n' >"$fx/scripts/test-always.sh"
: >"$RAN"
(cd "$fx" && GIT_DIR="$fx/.git" bash "$RUNNER" >/dev/null 2>&1)
check "under a hook's GIT_DIR the suites run without it" "always git_dir=unset,args beta/arg.md" "$(sort "$RAN" | paste -sd, -)"

printf '#!/usr/bin/env bash\necho "planted failure"\nexit 255\n' >"$fx/scripts/test-always.sh"
run_fx beta/SKILL.md
nonzero "a failing suite fails the run" "$rc"
check "a suite exiting 255 does not stop the others" "args beta/arg.md,beta" "$ran"
case "$out" in
    *"scripts/test-always.sh"*"planted failure"*) ok "the failure names its suite and prints its output" ;;
    *) bad "the failure names its suite and prints its output" "$out" ;;
esac

# ----------------------------------------------------------------------------
section "4. every suite that reads through a glob is in suites-always.txt"

# GLOB_READ is what a glob or a tree walk looks like in a suite's code.
# shellcheck disable=SC2016  # "$repo_root" is the text being matched
GLOB_READ='(^|[^[:alnum:]_])ls-files([^[:alnum:]_]|$)|(^|[^[:alnum:]_])git( -C [^ ]+)? grep |\*/(SKILL\.md|\*\.md|references/)|(^|[[:space:]("/])[a-z][a-z-]*/[a-z-]*\*\.(md|sh)|(^|[^[:alnum:]_])find (\.|"\$repo_root"|docs)([[:space:]/]|$)|(^|[^[:alnum:]_])grep +-[a-zA-Z]*r[a-zA-Z]* '

# NOT_THE_TREE — suites the pattern matches whose glob never reaches this
# repository's files, each with why. An entry that stops matching fails below.
NOT_THE_TREE="scripts/test-lesson-recall.sh globs inside its fixture projects
scripts/test-population-covers-untracked.sh runs its ls-files in a fixture
scripts/test-setup-pre-commit-gates.sh matches a skill's grep line as text
scripts/test-fixture-git-isolation.sh is CI only
scripts/test-fixture-root-collision.sh is CI only"

# globbers <suite>... — those whose code, whole-line comments dropped, matches GLOB_READ.
globbers() {
    local s hits
    for s in "$@"; do
        hits="$(sed 's/^[[:space:]]*#.*$//' "$s" | grep -cE "$GLOB_READ")"
        [ "$hits" -eq 0 ] || printf '%s\n' "$s"
    done
}

# unlisted <list-file> <suite>... — the globbing suites neither listed nor excused.
unlisted() {
    local list="$1" s listed
    shift
    listed="$(list_entries "$list"; printf '%s\n' "$NOT_THE_TREE" | cut -d' ' -f1)"
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        grep -qxF -- "$s" <<<"$listed" || printf '%s\n' "$s"
    done <<<"$(globbers "$@")"
}

found="$(globbers scripts/test-*.sh)"
found_n="$(printf '%s\n' "$found" | grep -c .)"
[ "$found_n" -ge 10 ] || fatal "the detector found $found_n globbing suites; it has stopped reading"
check "every globbing suite is listed in $ALWAYS" "" "$(unlisted "$ALWAYS" scripts/test-*.sh)"

while read -r excused _; do
    if grep -qxF -- "$excused" <<<"$found"; then
        ok "the exception for $excused still matches"
    else
        bad "the exception for $excused still matches" "remove it from NOT_THE_TREE"
    fi
done <<<"$NOT_THE_TREE"

# Self-test: a copy of the list with one globbing suite's line removed.
victim="scripts/test-bare-pack-refs.sh"
grep -qxF -- "$victim" "$ALWAYS" || fatal "self-test: $victim is not in $ALWAYS"
grep -vxF -- "$victim" "$ALWAYS" >"$tmp/list.short"
check "self-test: a copy with one line removed fails, naming that suite" \
    "$victim" "$(unlisted "$tmp/list.short" scripts/test-*.sh)"

# Self-test: a new suite in the real shape of a globbing one.
grep -F 'git ls-files' "$victim" >"$tmp/test-planted.sh"
check "self-test: a new globbing suite absent from the list is named" \
    "$tmp/test-planted.sh" "$(unlisted "$ALWAYS" "$tmp/test-planted.sh")"

# ----------------------------------------------------------------------------
section "5. where suites are registered"

# hook_runs <hook> — the run: values under one top-level key of lefthook.yml.
hook_runs() {
    awk -v key="$1:" '
        /^[^[:space:]#]/ { on = ($(0) == key) }
        on && /^[[:space:]]+run: / { sub(/^[[:space:]]+run: /, ""); print }
    ' "$HOOKS"
}

push_runs="$(hook_runs pre-push)"
check "pre-push runs the runner" 1 "$(grep -cxF "bash $RUNNER" <<<"$push_runs")"
check "pre-push lists no suite of its own" 0 "$(grep -c 'scripts/test-' <<<"$push_runs")"
check "pre-commit runs the one cheap suite and no other" \
    "bash scripts/test-pipefail-safe-matchers.sh" "$(hook_runs pre-commit | grep 'scripts/test-')"

in_ci="$(sed -n 's/^[[:space:]]*run: bash \(scripts\/test-[A-Za-z0-9_-]*\.sh\).*$/\1/p' "$WORKFLOW" | sort -u)"
check "CI runs every suite on disk" "$(printf '%s\n' scripts/test-*.sh | sort)" "$in_ci"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
