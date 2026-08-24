#!/usr/bin/env bash
# CONTRACT: the local lint and the merge gate must agree on which shellcheck
# they mean, and both must DERIVE that from one file rather than restate it.
#
# DRIFT CLASS. A reviewer runs a linter locally, reads green, and reports the
# artifact clean — while the version that actually gates the merge reports a
# real defect. The local tool is not wrong; it is a different instrument, and
# nothing recorded that it was different.
#
# THE INCIDENT (PR #271, 2026-08-23). CI ran shellcheck 0.9.0 and failed on
# SC2317 (unreachable body of a duplicated function). Local 0.11.0 exits 0 on
# the same file. Two reviewers reported "shellcheck clean" three times between
# them while a required check sat red on the PR through four review rounds.
#
# WHAT THIS PINS: that .shellcheck-version exists and is the single source, that
# the workflow reads it rather than hardcoding a number, and that lefthook runs
# the comparison. It does NOT pin which version is correct — that is a judgment,
# and a suite asserting it would just be the same number written a third time.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n     -> %s\n' "$1" "$2"; fail=$((fail + 1)); }
fatal() { printf '\nFATAL: %s\n' "$1" >&2; exit 2; }
section() { printf '\n=== %s ===\n' "$1"; }

VERSION_FILE=".shellcheck-version"
WORKFLOW=".github/workflows/validate-skills.yml"
HOOKS="lefthook.yml"
WARNER="scripts/check-shellcheck-version.sh"

for f in "$VERSION_FILE" "$WORKFLOW" "$HOOKS" "$WARNER"; do
    [ -f "$f" ] || fatal "$f is missing; this suite has nothing to check"
done

section "the version file is a single, well-formed source"

pinned="$(tr -d '[:space:]' < "$VERSION_FILE")"
[ -n "$pinned" ] || fatal "$VERSION_FILE is empty — every check below would compare against nothing"

if printf '%s' "$pinned" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    ok "$VERSION_FILE holds an exact version ($pinned)"
else
    bad "$VERSION_FILE does not hold an exact version" \
        "read as '$pinned'; a range or a name cannot be compared against \`shellcheck --version\`"
fi

lines=$(grep -c . "$VERSION_FILE" || true)
if [ "$lines" -eq 1 ]; then
    ok "$VERSION_FILE is one line — nothing to disagree with itself"
else
    bad "$VERSION_FILE has $lines non-empty lines" "a second line is a second source"
fi

section "both surfaces DERIVE the version rather than restating it"

# The whole point is that the number lives in one place. A surface that hardcodes
# it agrees today and drifts silently the moment the file is bumped.
if grep -q '\.shellcheck-version' "$WORKFLOW"; then
    ok "$WORKFLOW reads $VERSION_FILE"
else
    bad "$WORKFLOW does not read $VERSION_FILE" \
        "the gate's version is then unrelated to the pin, which is the state this suite exists to end"
fi

if grep -qF "$pinned" "$WORKFLOW"; then
    bad "$WORKFLOW hardcodes the version string '$pinned'" \
        "restated, not derived — bumping $VERSION_FILE would leave this stale and silent"
else
    ok "$WORKFLOW does not restate the version string"
fi

if grep -q "$WARNER" "$HOOKS"; then
    ok "$HOOKS runs $WARNER"
else
    bad "$HOOKS does not run $WARNER" \
        "the local/gate mismatch then goes unannounced, which is exactly the incident"
fi

if grep -qF "$pinned" "$HOOKS"; then
    bad "$HOOKS hardcodes the version string '$pinned'" "restated, not derived"
else
    ok "$HOOKS does not restate the version string"
fi

if grep -q '\.shellcheck-version' "$WARNER"; then
    ok "$WARNER reads $VERSION_FILE"
else
    bad "$WARNER does not read $VERSION_FILE" "it would be comparing against something else"
fi

section "the warner behaves in both directions (probe)"

# An assertion that cannot fail is not an assertion. Drive the warner with a
# planted version file rather than trusting whatever this machine happens to have.
probe_dir="$(mktemp -d)"
mkdir -p "$probe_dir/scripts"
cp "$WARNER" "$probe_dir/scripts/"

run_probe() {  # $1 = pinned value to plant
    printf '%s\n' "$1" > "$probe_dir/.shellcheck-version"
    bash "$probe_dir/scripts/$(basename "$WARNER")" 2>&1 || true
}

if command -v shellcheck >/dev/null 2>&1; then
    here="$(shellcheck --version | awk -F': ' '/^version:/ {print $2}' | tr -d '[:space:]')"

    out="$(run_probe "$here")"
    if printf '%s' "$out" | grep -q 'local'; then
        bad "warner complains when local matches the pin" "it would cry wolf on every correct setup"
    else
        ok "warner is silent when local matches the pin ($here)"
    fi

    out="$(run_probe "0.0.1-not-a-real-version")"
    if printf '%s' "$out" | grep -q 'local'; then
        ok "warner announces a mismatch when local differs from the pin"
    else
        bad "warner said nothing on a planted mismatch" \
            "the failure branch is unreachable; this is the vacuous-green shape"
    fi
else
    ok "shellcheck absent on this machine — warner probes skipped (it exits 0 by design)"
fi

out="$(rm -f "$probe_dir/.shellcheck-version"; bash "$probe_dir/scripts/$(basename "$WARNER")" 2>&1 || true)"
if printf '%s' "$out" | grep -q 'missing'; then
    ok "warner fails loudly when the version file is absent"
else
    bad "warner tolerated a missing version file" "it would silently compare against nothing"
fi

rm -rf "$probe_dir"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
