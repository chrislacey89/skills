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
#   - download impossible (offline, unknown platform), or the cached binary
#     will not run on this CPU -> lint with the same pinned release through
#     Docker, when a docker command exists and its daemon answers within a few
#     seconds; that is the pinned run, and exits with the lint's result
#   - neither -> fall back to the local binary, say LOUDLY that this run is
#     not the gate's instrument, and exit 3 so a caller that gates on the exit
#     code cannot read it as clean. SHELLCHECK_PINNED_ALLOW_FALLBACK=1 accepts
#     a clean fallback run (exit 0). A finding exits nonzero either way.
#   - every run says on stderr which instrument linted
#
# scripts/test-shellcheck-pinned-fallback.sh pins each tier against stubs.
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
# lint <command...> runs the command once per batch of files, and returns
# xargs' nonzero status when any batch reports a finding.
lint() {
    local n
    n="$(cd "$root" && git ls-files --cached --others --exclude-standard "*.sh" | grep -c .)" || true
    [ "$n" -gt 0 ] || { echo "shellcheck-pinned: git ls-files found no *.sh files to lint" >&2; return 1; }
    (cd "$root" && git ls-files -z --cached --others --exclude-standard "*.sh" | xargs -0 "$@")
}

# Fast path: the PATH shellcheck already is the gate's instrument.
if command -v shellcheck >/dev/null 2>&1; then
    local_v="$(shellcheck --version | awk -F': ' '/^version:/ {print $2}' | tr -d '[:space:]')"
    if [ "$local_v" = "$pinned" ]; then
        echo "shellcheck-pinned: linting with the local shellcheck $pinned (it matches the pin)." >&2
        lint shellcheck
        exit 0
    fi
fi

# Cached pinned binary, downloaded on first use. Either step can fail; the
# reason is kept for the message, and the Docker tier below is tried next.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/skill-kit/shellcheck-v$pinned"
cached="$cache_dir/shellcheck"
reason=""

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
        reason="could not obtain shellcheck $pinned (offline, or no release for this platform)"
    fi
fi

# A cached binary is not a runnable one: on Apple Silicon without Rosetta the
# darwin.x86_64 build exits 126 ("Bad CPU type"), and xargs turned that into a
# failed pre-push with no shellcheck finding behind it.
if [ -z "$reason" ] && ! "$cached" --version >/dev/null 2>&1; then
    reason="the cached shellcheck $pinned at $cached will not run on this machine
  (on Apple Silicon: install Rosetta with \`softwareupdate --install-rosetta\`)"
fi

if [ -z "$reason" ]; then
    echo "shellcheck-pinned: linting with shellcheck $pinned ($cached)." >&2
    lint "$cached"
    exit 0
fi

echo "shellcheck-pinned: $reason." >&2

# The Docker tier: the same pinned release, from the image the ShellCheck
# project publishes (https://hub.docker.com/r/koalaman/shellcheck, listed in
# https://github.com/koalaman/shellcheck#installing). A lint through it IS the
# pinned run, so it exits with the lint's result.
#
# docker_ready only checks; the lint itself runs at the top level below. A
# function called as an `if` condition runs with `set -e` suspended, so a lint
# inside it would return its findings as "Docker cannot run" and fall through.
image="koalaman/shellcheck:v$pinned"

# run_bounded <seconds> <command...> — run a command, and kill it if it has not
# finished in time. macOS ships no timeout(1), and a docker CLI whose daemon is
# not running can wait on its socket instead of failing.
run_bounded() {
    local secs="$1" pid ticks=0
    shift
    "$@" >/dev/null 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((secs * 10)) ]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 0.1
        ticks=$((ticks + 1))
    done
    wait "$pid"
}

docker_ready() {
    command -v docker >/dev/null 2>&1 || return 1
    if ! run_bounded 5 docker version --format '{{.Server.Version}}'; then
        echo "shellcheck-pinned: docker is installed but its daemon did not answer; skipping the Docker tier." >&2
        return 1
    fi
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "shellcheck-pinned: pulling $image (first use) ..." >&2
        docker pull -q "$image" >/dev/null || {
            echo "shellcheck-pinned: could not pull $image; skipping the Docker tier." >&2
            return 1
        }
    fi
    local image_v
    image_v="$(docker run --rm "$image" --version 2>/dev/null | awk -F': ' '/^version:/ {print $2}' | tr -d '[:space:]')" || true
    if [ "$image_v" != "$pinned" ]; then
        echo "shellcheck-pinned: $image reports version '${image_v:-none}', not $pinned; skipping the Docker tier." >&2
        return 1
    fi
}

if docker_ready; then
    echo "shellcheck-pinned: linting with shellcheck $pinned through Docker ($image)." >&2
    lint docker run --rm --network none -v "$root:/mnt" -w /mnt "$image"
    exit 0
fi

# The local fallback. It lints, because a finding is worth seeing, but it is
# not the gate's instrument, so it exits 3 unless the contributor accepts it.
# A finding exits nonzero before the override is read: lint fails, and
# `set -e` ends the script with xargs' status.
cat >&2 <<MSG
shellcheck-pinned: the pinned shellcheck $pinned cannot run here, natively or
  through Docker. Falling back to the local shellcheck —
  THIS RUN IS NOT THE MERGE GATE'S INSTRUMENT, and findings differ between
  releases in both directions. Read the PR's shellcheck check before reporting
  "clean".
MSG
command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck-pinned: and no local shellcheck exists either" >&2; exit 1; }
lint shellcheck
if [ "${SHELLCHECK_PINNED_ALLOW_FALLBACK:-0}" = 1 ]; then
    echo "shellcheck-pinned: SHELLCHECK_PINNED_ALLOW_FALLBACK=1 is set; accepting the local release's clean result." >&2
    exit 0
fi
cat >&2 <<MSG
shellcheck-pinned: linted with the local release, not $pinned. Exiting 3 so this
  run cannot pass as the gate. Install the pinned release (or start Docker), or
  set SHELLCHECK_PINNED_ALLOW_FALLBACK=1 to accept this run.
MSG
exit 3
