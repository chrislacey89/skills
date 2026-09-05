#!/usr/bin/env bash
# test-population-covers-untracked.sh — the instruments that lint or census
# this repo's shell scripts derive their population from `git ls-files`, and a
# bare `git ls-files` lists tracked files only. A file being written is not in
# that set until `git add`, so the instrument reports clean having never read
# it — and the report is indistinguishable from a real clean.
#
# THE INCIDENTS. PR #337's own review found an SC2001 hit in a new suite that
# the local lint had reported clean, because the file was untracked when the
# lint ran. The compound-clustering suite's header records its own first draft
# red on a clean tree for the same reason. PR #348 then hit it twice on one
# file: `shellcheck-pinned.sh` reported exit 0 on the new suite (three real
# findings) and `test-guards-can-fire.sh` reported green (six dead guards),
# both before `git add`, and both claims were written into the PR body.
# docs/solutions/testing-patterns/validate-the-instrument-not-only-the-subject
# -2026-08-23.md is the family; this is its second recorded observation.
#
# The fix widens the two populations that bit to tracked-plus-untracked,
# ignored files excluded. This suite EXTRACTS those two expressions from the
# real files and RUNS them in a fixture repository holding a tracked file, an
# untracked file, and an ignored file — so a later edit that narrows either
# population back to tracked-only fails here, not in someone's PR body.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pinned_lint="$repo_root/scripts/shellcheck-pinned.sh"
guards_suite="$repo_root/scripts/test-guards-can-fire.sh"

pass=0
fail=0

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %q\n       got:      %q\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

section() { printf '\n== %s\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 1; }

# --- Extract the two population expressions ------------------------------------

# The xargs line in scripts/shellcheck-pinned.sh: the `git ls-files …` segment up to the pipe.
lint_expr="$(grep -m1 'git ls-files -z' "$pinned_lint" | sed -E 's/.*(git ls-files[^|]*)\|.*/\1/' || true)"
[[ -n "$lint_expr" ]] || fatal "no 'git ls-files -z' population line found in $pinned_lint"

# test-guards-can-fire.sh's suites= line: the same segment.
# shellcheck disable=SC2016  # the pattern is the suite's literal text; `$(` is matched, not expanded
guards_expr="$(grep -m1 '^suites="\$(git ls-files' "$guards_suite" | sed -E 's/.*(git ls-files[^|]*)\|.*/\1/' || true)"
[[ -n "$guards_expr" ]] || fatal "no suites=\"\$(git ls-files …\" population line found in $guards_suite"

printf 'lint population:   %s\n' "$lint_expr"
printf 'guards population: %s\n' "$guards_expr"

# --- Fixture ---------------------------------------------------------------------

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
repo="$sandbox/repo"
mkdir -p "$repo/scripts"
(
    cd "$repo" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'scripts/ignored.sh\nscripts/test-ignored.sh\n' > .gitignore
    printf '#!/usr/bin/env bash\n' > scripts/tracked.sh
    printf '#!/usr/bin/env bash\n' > scripts/test-tracked.sh
    git add .gitignore scripts/tracked.sh scripts/test-tracked.sh
    git commit -q -m 'fixture: tracked files'
    printf '#!/usr/bin/env bash\n' > scripts/untracked.sh
    printf '#!/usr/bin/env bash\n' > scripts/test-untracked.sh
    printf '#!/usr/bin/env bash\n' > scripts/ignored.sh
    printf '#!/usr/bin/env bash\n' > scripts/test-ignored.sh
)
[[ "$(git -C "$repo" rev-list --count HEAD)" == "1" ]] || fatal "fixture: expected one commit"
[[ -f "$repo/scripts/untracked.sh" && -f "$repo/scripts/ignored.sh" ]] || fatal "fixture: untracked/ignored files missing"

# run_population <expr> — runs an extracted expression in the fixture (from the
# fixture's root, as both instruments do) and prints the sorted file list,
# space-joined. `-z` output is NUL-separated; translate either way.
run_population() {
    (cd "$repo" && bash -c "$1") 2>/dev/null | tr '\0' '\n' | grep . | sort | tr '\n' ' ' | sed 's/ $//'
}

# --- 1. The lint population -----------------------------------------------------
section "shellcheck-pinned.sh lints the unstaged file too, and not the ignored one"
assert_eq "scripts/test-tracked.sh scripts/test-untracked.sh scripts/tracked.sh scripts/untracked.sh" \
    "$(run_population "$lint_expr")" \
    "lint population = tracked + untracked, ignored excluded"

# --- 2. The guards census population ----------------------------------------------
section "test-guards-can-fire.sh censuses the unstaged suite too, and not the ignored one"
assert_eq "scripts/test-tracked.sh scripts/test-untracked.sh" \
    "$(run_population "$guards_expr")" \
    "guards population = tracked + untracked test-*.sh, ignored excluded"

# --- 3. The assertion can fail: a tracked-only population is the incident ------------
section "control: a bare git ls-files population drops the unstaged file (the incident shape)"
bare_lint="$(printf '%s' "$lint_expr" | sed 's/ --cached --others --exclude-standard//')"
[[ "$bare_lint" != "$lint_expr" ]] || fatal "control: could not derive a tracked-only variant from the lint expression"
assert_eq "scripts/test-tracked.sh scripts/tracked.sh" \
    "$(run_population "$bare_lint")" \
    "tracked-only variant lists only the tracked files — so the assertions above discriminate"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
