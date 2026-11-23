#!/usr/bin/env bash
# suites-for-paths.sh [<path>...] — print the contract suites that read any of
# the paths, then every suite in scripts/suites-always.txt, one per line.
#
# "Read" is decided by name: the suite's text contains the path, relative to
# the repo root. A changed suite selects itself. A suite that reaches files
# through a glob cannot be matched that way, which is what the always-run list
# is for, so a missing, empty, or stale list is an error rather than a smaller
# selection. With no paths the output is the always-run suites.
#
# It only prints. scripts/run-changed-suites.sh runs what it prints.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
list="scripts/suites-always.txt"

die() { printf 'suites-for-paths: %s\n' "$1" >&2; exit 2; }

[ -f "$list" ] || die "$list is missing; without it a suite that globs would never be selected"
always="$(grep -vE '^[[:space:]]*(#|$)' "$list" || true)"
[ -n "$always" ] || die "$list lists no suite"
while IFS= read -r suite; do
    [ -f "$suite" ] || die "$list names $suite, which is not on disk"
done <<<"$always"

selected=""
for path in "$@"; do
    path="${path#"$root"/}"
    path="${path#./}"
    [ -n "$path" ] || continue
    case "$path" in
        scripts/test-*.sh)
            if [ -f "$path" ]; then selected="$selected$path"$'\n'; fi ;;
    esac
    rc=0
    readers="$(grep -lF -- "$path" scripts/test-*.sh)" || rc=$?
    # 1 is "no suite names it"; anything higher is a search that did not run.
    [ "$rc" -le 1 ] || die "could not search the suites for $path"
    [ -z "$readers" ] || selected="$selected$readers"$'\n'
done

printf '%s%s\n' "$selected" "$always" | awk '!seen[$(0)]++'
