#!/usr/bin/env bash
# Lint with the shellcheck that actually gates the merge — not whatever is on PATH.
#
# THE RECURRENCE (PR #299, 2026-08-27). The warner below this script in the
# stack (scripts/check-shellcheck-version.sh) was built after PR #271, where
# local 0.11.0 said clean and CI's 0.9.0 said SC2317. It fired correctly on
# #299 — its warning was even quoted into the PR body, twice — and the branch
# still shipped three commits and went red at the gate on SC2015, which 0.11.0
# special-cases and 0.9.0 reports. The warning prescribes *reading* ("Read the
# PR check, not this run") when the pinned binary is *runnable*: one ~1.4MB
# download, cached forever. A disclosed risk with a runnable verification is a
# to-do, not a disclosure — so this script runs it.
#
# Behavior:
#   - local shellcheck already matches the pin -> use it, no network
#   - otherwise use a cached pinned binary, downloading it on first use
#   - download impossible (offline, unknown platform) -> fall back to the
#     local binary and say LOUDLY that this run is not the gate's instrument
#
# The version is derived from .shellcheck-version, never restated here — the
# parity suite (scripts/test-shellcheck-version-parity.sh) pins that property
# for every surface that names the tool.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pinned_file="$root/.shellcheck-version"

[ -f "$pinned_file" ] || { echo "shellcheck-pinned: $pinned_file is missing" >&2; exit 1; }
pinned="$(tr -d '[:space:]' < "$pinned_file")"
[ -n "$pinned" ] || { echo "shellcheck-pinned: $pinned_file is empty" >&2; exit 1; }

# The file set is every *.sh in the tree, wherever it lives, whether or not it
# has been staged yet — tracked plus untracked-and-not-ignored. CI sees only
# tracked files because everything there is committed, so the two sets agree
# there; locally they differ by exactly the file being written. Keying on
# tracked files alone reported "clean" on PR #348's new suite twice, having
# never read it — the same blind spot PR #337 hit and the compound-clustering
# suite's header records. scripts/test-population-covers-untracked.sh runs the
# expression below in a fixture and pins that an unstaged file is in the set.
# An empty set is an error, not a clean run: xargs on empty input runs nothing
# and exits 0, which would report "linted" having linted nothing.
lint() {
    local n
    n="$(cd "$root" && git ls-files --cached --others --exclude-standard "*.sh" | grep -c .)" || true
    [ "$n" -gt 0 ] || { echo "shellcheck-pinned: git ls-files found no *.sh files to lint" >&2; return 1; }
    (cd "$root" && git ls-files -z --cached --others --exclude-standard "*.sh" | xargs -0 "$1")
}

# Fast path: the PATH shellcheck already is the gate's instrument.
if command -v shellcheck >/dev/null 2>&1; then
    local_v="$(shellcheck --version | awk -F': ' '/^version:/ {print $2}' | tr -d '[:space:]')"
    if [ "$local_v" = "$pinned" ]; then
        lint shellcheck
        exit 0
    fi
fi

# Cached pinned binary, downloaded on first use.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/skill-kit/shellcheck-v$pinned"
cached="$cache_dir/shellcheck"

if [ ! -x "$cached" ]; then
    case "$(uname -s)-$(uname -m)" in
        # v0.9.0 ships no darwin.aarch64 build; the x86_64 one runs under Rosetta.
        Darwin-*)              platform="darwin.x86_64" ;;
        Linux-x86_64)          platform="linux.x86_64" ;;
        Linux-aarch64)         platform="linux.aarch64" ;;
        *)                     platform="" ;;
    esac
    url="https://github.com/koalaman/shellcheck/releases/download/v$pinned/shellcheck-v$pinned.$platform.tar.xz"
    if [ -n "$platform" ] \
       && mkdir -p "$cache_dir" \
       && curl -fsSL --max-time 60 "$url" -o "$cache_dir/sc.tar.xz" \
       && tar -xf "$cache_dir/sc.tar.xz" -C "$cache_dir" --strip-components=1 "shellcheck-v$pinned/shellcheck" \
       && rm -f "$cache_dir/sc.tar.xz" \
       && [ -x "$cached" ]; then
        : # cached
    else
        rm -f "$cached" "$cache_dir/sc.tar.xz" 2>/dev/null || true
        cat >&2 <<MSG
shellcheck-pinned: could not obtain shellcheck $pinned (offline, or no release
  for this platform). Falling back to the local shellcheck — THIS RUN IS NOT
  THE MERGE GATE'S INSTRUMENT, and findings differ between releases in both
  directions. Read the PR's shellcheck check before reporting "clean".
MSG
        command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck-pinned: and no local shellcheck exists either" >&2; exit 1; }
        lint shellcheck
        exit 0
    fi
fi

lint "$cached"
