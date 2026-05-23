#!/usr/bin/env bash
# test-verify-install.sh — tests for scripts/verify-install.sh
#
# verify-install.sh asserts that a skills-install directory contains, for
# every mapping in scripts/skill-references.manifest, the expected bundled
# reference file. It does NOT run `npx skills add` itself — the caller is
# responsible for populating the install dir (or using --install-here).
# These tests feed a hand-built install dir so they stay offline and fast.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/scripts/verify-install.sh"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# Derived from the manifest so the test never needs a hand-edit when entries
# are added or removed. Mirrors the comment-and-blank filtering used by
# populate_install_dir below.
expected_count=$(awk 'NF && !/^[[:space:]]*#/' "$repo_root/scripts/skill-references.manifest" | wc -l | tr -d ' ')

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s (exit=%s)\n' "$label" "$actual"
        pass=$((pass + 1))
    else
        printf '  FAIL %s (expected %s, got %s)\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected to contain: %s\n       got: %s\n' "$label" "$needle" "$haystack"
        fail=$((fail + 1))
    fi
}

# populate_install_dir <dir> — materialize one reference file per manifest entry
populate_install_dir() {
    local dir="$1"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | awk '{$1=$1};1')"
        [[ -z "$line" ]] && continue
        local src skill base
        src="$(printf '%s\n' "$line" | awk '{print $1}')"
        skill="$(printf '%s\n' "$line" | awk '{print $2}')"
        base="$(basename "$src")"
        mkdir -p "$dir/$skill/references"
        printf 'stub\n' > "$dir/$skill/references/$base"
    done < "$repo_root/scripts/skill-references.manifest"
}

# -----------------------------------------------------------------------------

section "happy path: install dir with all bundled refs present → exit 0"
install_dir="$sandbox/happy"
populate_install_dir "$install_dir"
set +e
output="$(bash "$script" "$install_dir" 2>&1)"
rc=$?
set -e
assert_exit 0 "$rc" "exit 0 when all files present"
assert_contains "$output" "$expected_count reference(s) present" "reports count"

# -----------------------------------------------------------------------------

section "missing reference: one file deleted → exit 1 with diagnostic"
install_dir="$sandbox/missing"
populate_install_dir "$install_dir"
rm "$install_dir/help/references/SYSTEM-OVERVIEW.md"
set +e
output="$(bash "$script" "$install_dir" 2>&1)"
rc=$?
set -e
assert_exit 1 "$rc" "exit 1 when a bundled file is missing"
assert_contains "$output" "missing:" "diagnostic identifies the missing file"
assert_contains "$output" "help/references/SYSTEM-OVERVIEW.md" "names the absent path"

# -----------------------------------------------------------------------------

section "missing skill dir entirely → exit 1"
install_dir="$sandbox/skipped"
populate_install_dir "$install_dir"
rm -rf "$install_dir/setup-ralph-loop"
set +e
output="$(bash "$script" "$install_dir" 2>&1)"
rc=$?
set -e
assert_exit 1 "$rc" "exit 1 when an entire skill dir is absent"
assert_contains "$output" "setup-ralph-loop" "names the affected skill"

# -----------------------------------------------------------------------------

section "missing install dir argument errors cleanly"
set +e
output="$(bash "$script" 2>&1)"
rc=$?
set -e
assert_exit 2 "$rc" "exit 2 when invoked with no install dir"
assert_contains "$output" "usage" "usage message printed"

# -----------------------------------------------------------------------------

section "install dir that doesn't exist errors cleanly"
set +e
output="$(bash "$script" "$sandbox/does-not-exist" 2>&1)"
rc=$?
set -e
assert_exit 2 "$rc" "exit 2 when install dir missing"
assert_contains "$output" "not a directory" "diagnostic identifies missing dir"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
