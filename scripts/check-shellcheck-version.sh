#!/usr/bin/env bash
# Warn when the local shellcheck disagrees with the one that gates the merge.
#
# THE INCIDENT (PR #271, 2026-08-23). CI ran shellcheck 0.9.0 and failed on
# SC2317 — the unreachable body of a duplicated `esc_re()` definition, a real
# defect. Local shellcheck 0.11.0 exits 0 on the same file, because SC2317's
# reachability analysis narrowed between the two releases. Two reviewers ran the
# local one, reported "shellcheck clean" three times between them, and the PR
# sat with a red required check through four review rounds. Nobody read the gate;
# both read a tool that agreed with them.
#
# This does not force a version. Forcing one would trade a silent disagreement
# for a silent downgrade. It makes the disagreement LOUD at the moment someone
# would otherwise trust a local green.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pinned_file="$root/.shellcheck-version"

[ -f "$pinned_file" ] || { echo "shellcheck-version: $pinned_file is missing" >&2; exit 1; }
pinned="$(tr -d '[:space:]' < "$pinned_file")"
[ -n "$pinned" ] || { echo "shellcheck-version: $pinned_file is empty" >&2; exit 1; }

command -v shellcheck >/dev/null 2>&1 || {
    echo "shellcheck-version: shellcheck is not installed; CI will lint with $pinned" >&2
    exit 0
}

local_v="$(shellcheck --version | awk -F': ' '/^version:/ {print $2}' | tr -d '[:space:]')"

if [ "$local_v" != "$pinned" ]; then
    cat >&2 <<MSG
shellcheck-version: local $local_v, CI gates on $pinned.

  A local pass does NOT mean the merge gate passes. Findings differ between
  releases in BOTH directions — 0.11.0 misses SC2317 cases that 0.9.0 reports.
  Run \`bash scripts/shellcheck-pinned.sh\` to lint with the gate's own binary
  (pre-push does this automatically); do not report "shellcheck clean" from a
  $local_v run. PR #299 shipped three commits on that exact claim.

  Update .shellcheck-version (and the workflow reads it) if the pin should move.
MSG
fi
exit 0
