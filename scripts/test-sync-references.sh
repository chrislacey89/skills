#!/usr/bin/env bash
# test-sync-references.sh — negative-case and happy-path tests for sync-skill-references.sh
#
# Each test runs in its own sandbox under a tmpdir so the real repo is
# untouched. The script under test is copied verbatim; only the manifest
# and fake skill layout change per case.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
sync_script="$repo_root/scripts/sync-skill-references.sh"
sandbox_root="$(mktemp -d)"
trap 'rm -rf "$sandbox_root"' EXIT

pass=0
fail=0

# Print a section header.
section() {
    printf '\n=== %s ===\n' "$1"
}

# Create an isolated sandbox copy of the layout the script expects.
# Usage: make_sandbox <name>
# Populates $sandbox_root/<name>/scripts/ with a copy of sync-skill-references.sh
# and an empty manifest. Caller fills in sources and skill dirs as needed.
make_sandbox() {
    local name="$1"
    local dir="$sandbox_root/$name"
    mkdir -p "$dir/scripts"
    cp "$sync_script" "$dir/scripts/sync-skill-references.sh"
    : > "$dir/scripts/skill-references.manifest"
    printf '%s' "$dir"
}

# assert_exit <expected> <actual> <label>
assert_exit() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s (exit=%s)\n' "$label" "$actual"
        pass=$((pass + 1))
    else
        printf '  FAIL %s (expected exit=%s, got %s)\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

# assert_contains <haystack> <needle> <label>
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n' "$label"
        printf '       expected to contain: %s\n' "$needle"
        printf '       got: %s\n' "$haystack"
        fail=$((fail + 1))
    fi
}

# -----------------------------------------------------------------------------

section "happy path: sync then --check"
dir="$(make_sandbox happy)"
mkdir -p "$dir/docs" "$dir/consumer/references"
printf 'hello\n' > "$dir/docs/thing.md"
printf 'docs/thing.md  consumer\n' > "$dir/scripts/skill-references.manifest"
set +e
(cd "$dir" && bash scripts/sync-skill-references.sh >/dev/null)
rc=$?
set -e
assert_exit 0 "$rc" "sync succeeds"
[[ -f "$dir/consumer/references/thing.md" ]] && pass=$((pass + 1)) && printf '  ok   destination created\n' || { fail=$((fail + 1)); printf '  FAIL destination not created\n'; }
set +e
(cd "$dir" && bash scripts/sync-skill-references.sh --check >/dev/null)
rc=$?
set -e
assert_exit 0 "$rc" "--check green immediately after sync"

# -----------------------------------------------------------------------------

section "idempotence: second sync produces identical result"
set +e
(cd "$dir" && bash scripts/sync-skill-references.sh >/dev/null)
rc=$?
set -e
assert_exit 0 "$rc" "second sync succeeds"
(cd "$dir" && bash scripts/sync-skill-references.sh --check >/dev/null) && pass=$((pass + 1)) && printf '  ok   still green after second sync\n' || { fail=$((fail + 1)); printf '  FAIL --check failed after second sync\n'; }

# -----------------------------------------------------------------------------

section "drift detection: mutated destination makes --check fail"
printf 'tampered\n' >> "$dir/consumer/references/thing.md"
set +e
output="$(cd "$dir" && bash scripts/sync-skill-references.sh --check 2>&1)"
rc=$?
set -e
assert_exit 1 "$rc" "--check fails on drift"
assert_contains "$output" "drift:" "drift message printed"
assert_contains "$output" "sync-skill-references.sh" "hint to re-run sync printed"

# re-sync clears drift
set +e
(cd "$dir" && bash scripts/sync-skill-references.sh >/dev/null)
(cd "$dir" && bash scripts/sync-skill-references.sh --check >/dev/null)
rc=$?
set -e
assert_exit 0 "$rc" "re-sync clears drift"

# -----------------------------------------------------------------------------

section "missing source file errors cleanly"
dir="$(make_sandbox missing_source)"
mkdir -p "$dir/consumer/references"
printf 'docs/nope.md  consumer\n' > "$dir/scripts/skill-references.manifest"
set +e
output="$(cd "$dir" && bash scripts/sync-skill-references.sh 2>&1)"
rc=$?
set -e
assert_exit 2 "$rc" "sync exits 2 on missing source"
assert_contains "$output" "source missing" "error message names missing source"

# -----------------------------------------------------------------------------

section "missing skill directory errors cleanly"
dir="$(make_sandbox missing_skill)"
mkdir -p "$dir/docs"
printf 'hello\n' > "$dir/docs/thing.md"
printf 'docs/thing.md  no-such-skill\n' > "$dir/scripts/skill-references.manifest"
set +e
output="$(cd "$dir" && bash scripts/sync-skill-references.sh 2>&1)"
rc=$?
set -e
assert_exit 2 "$rc" "sync exits 2 on missing skill dir"
assert_contains "$output" "skill dir missing" "error message names missing skill"

# -----------------------------------------------------------------------------

section "malformed manifest line errors cleanly"
dir="$(make_sandbox malformed)"
mkdir -p "$dir/consumer"
printf 'only-one-token\n' > "$dir/scripts/skill-references.manifest"
set +e
output="$(cd "$dir" && bash scripts/sync-skill-references.sh 2>&1)"
rc=$?
set -e
assert_exit 2 "$rc" "sync exits 2 on single-token manifest line"
assert_contains "$output" "malformed manifest line" "error message identifies malformed line"

# -----------------------------------------------------------------------------

section "comments and blank lines are ignored"
dir="$(make_sandbox comments)"
mkdir -p "$dir/docs" "$dir/consumer/references"
printf 'hello\n' > "$dir/docs/thing.md"
cat > "$dir/scripts/skill-references.manifest" <<'EOF'
# this is a comment

docs/thing.md  consumer    # inline comment

# another comment line
EOF
set +e
(cd "$dir" && bash scripts/sync-skill-references.sh >/dev/null)
rc=$?
set -e
assert_exit 0 "$rc" "sync ignores comments and blank lines"
[[ -f "$dir/consumer/references/thing.md" ]] && pass=$((pass + 1)) && printf '  ok   valid entry still synced\n' || { fail=$((fail + 1)); printf '  FAIL valid entry not synced\n'; }

# -----------------------------------------------------------------------------

section "unknown flag errors cleanly"
dir="$(make_sandbox bad_flag)"
set +e
output="$(cd "$dir" && bash scripts/sync-skill-references.sh --bogus 2>&1)"
rc=$?
set -e
assert_exit 2 "$rc" "sync exits 2 on unknown flag"
assert_contains "$output" "usage" "usage message printed"

# -----------------------------------------------------------------------------

section "--check with missing destination reports drift"
dir="$(make_sandbox missing_dest)"
mkdir -p "$dir/docs" "$dir/consumer"
printf 'hello\n' > "$dir/docs/thing.md"
printf 'docs/thing.md  consumer\n' > "$dir/scripts/skill-references.manifest"
set +e
output="$(cd "$dir" && bash scripts/sync-skill-references.sh --check 2>&1)"
rc=$?
set -e
assert_exit 1 "$rc" "--check fails when destination absent"
assert_contains "$output" "drift:" "missing destination reported as drift"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
if [[ "$fail" -ne 0 ]]; then
    exit 1
fi
