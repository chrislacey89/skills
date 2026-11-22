#!/usr/bin/env bash
# run-changed-suites.sh [--all | <path>...] — run the contract suites that read
# what changed. CI runs every suite; this is the early-warning layer.
#
#   (no arguments)  the paths HEAD changes since its merge base with the remote
#                   default branch (https://git-scm.com/docs/git-merge-base).
#                   pre-push runs this form.
#   <path>...       those paths. This is the form to declare as this repo's
#                   verify.test_changed.
#   --all           every suite but the CI-only two: the full local run.
#
# Each suite runs with the arguments the CI workflow gives it, so that workflow
# is the one place an invocation is written. The run says how many suites ran,
# because exit 0 alone cannot tell a pass from a selection of nothing
# (docs/solutions/devops/declared-test-command-exits-zero-having-run-nothing-2026-11-18.md).
set -euo pipefail

# A git hook exports these. The suites build scratch repos and must not inherit them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
workflow=".github/workflows/validate-skills.yml"
jobs=8

# These two re-run the other suites, so they run in CI only. Their headers say why.
ci_only="scripts/test-fixture-git-isolation.sh
scripts/test-fixture-root-collision.sh"

die() { printf 'run-changed-suites: %s\n' "$1" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "${1:-}" in
    --all)
        [ $# -eq 1 ] || die "--all takes no paths"
        printf '%s\n' scripts/test-*.sh >"$tmp/selected" ;;
    -*)
        die "usage: run-changed-suites.sh [--all | <path>...]" ;;
    *)
        if [ $# -eq 0 ]; then
            default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/prod)"
            base="$(git merge-base "$default" HEAD)" || die "no merge base with $default; nothing ran"
            # --no-renames: the suites that name a moved file name its old path.
            git diff --no-renames --name-only -z "$base" HEAD >"$tmp/changed" \
                || die "cannot read what changed since $base; nothing ran"
            while IFS= read -r -d '' path; do set -- "$@" "$path"; done <"$tmp/changed"
        fi
        bash scripts/suites-for-paths.sh "$@" >"$tmp/selected" || die "suite selection failed; nothing ran" ;;
esac

grep -vxF -- "$ci_only" "$tmp/selected" >"$tmp/suites" || die "no suite was selected; nothing ran"
want="$(grep -c . "$tmp/suites")"

# run_one <suite> — run it with CI's arguments, keeping its status and output.
run_one() {
    local suite="$1" name="${1##*/}" args rc=0
    args="$(sed -n "s|^[[:space:]]*run: bash ${suite} \(.*\)\$|\1|p" "$workflow" | sed -n 1p)"
    # Word-split on purpose: these are the workflow line's own arguments.
    # shellcheck disable=SC2086
    bash "$suite" $args </dev/null >"$tmp/$name.out" 2>&1 || rc=$?
    printf '%s %s\n' "$rc" "$suite" >"$tmp/$name.rc"
}
export -f run_one
export tmp workflow

printf 'running %s suites...\n' "$want"
# shellcheck disable=SC2016  # $1 is the child shell's argument
xargs -P "$jobs" -n 1 bash -c 'run_one "$1"' _ <"$tmp/suites" || die "could not run the selected suites"

ran=0
failed=0
while IFS= read -r suite; do
    name="${suite##*/}"
    [ -f "$tmp/$name.rc" ] || die "$suite left no result"
    ran=$((ran + 1))
    read -r rc _ <"$tmp/$name.rc"
    [ "$rc" -ne 0 ] || continue
    failed=$((failed + 1))
    printf '\n=== FAILED (exit %s): %s ===\n' "$rc" "$suite"
    cat "$tmp/$name.out"
done <"$tmp/suites"

printf '\n%s suites ran, %s failed\n' "$ran" "$failed"
[ "$failed" -eq 0 ]
