#!/usr/bin/env bash
# test-shellcheck-pinned-fallback.sh — scripts/shellcheck-pinned.sh must not
# let a different ShellCheck release pass as the pinned one (#814).
#
# THE DRIFT CLASS. The script lints with the release in .shellcheck-version,
# the one CI gates on. When that release cannot run natively (no download, or
# a binary this CPU will not execute), it used to lint with the local release,
# print a warning, and exit 0, so the pre-push hook and any other caller that
# gates on the exit code read another release's result as clean. Findings
# differ between releases in both directions.
#
# What this suite pins, each arm against stubs so it never touches the network
# or a Docker daemon and never pulls an image:
#   - a local-release fallback run exits 3, at both fallback sites, unless
#     SHELLCHECK_PINNED_ALLOW_FALLBACK=1 is set; it still lints first, and the
#     exit-3 message names the override
#   - with the override it exits 0 on a clean lint
#   - a fallback run with findings exits nonzero with or without the override
#   - when the native pinned binary is unavailable and Docker answers, the
#     pinned image lints, and the exit is the lint's result (0 or nonzero,
#     never 3); the local release is not run
#   - Docker installed with a daemon that does not answer (fails fast, or
#     hangs) falls through to the local fallback within a bound
#
# The script is copied into a fixture repository with its own .shellcheck-version,
# and PATH is a directory of symlinks to the few real tools the script needs plus
# stubs for shellcheck, docker and curl, so a runner's own shellcheck or docker
# can never be what answers.

set -uo pipefail

# A caller that reached this suite via a git hook has GIT_DIR and friends set;
# the fixture's `git init` would otherwise write into the real repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_src="$repo_root/scripts/shellcheck-pinned.sh"
pinned="$(tr -d '[:space:]' < "$repo_root/.shellcheck-version")"
bash_bin="$(command -v bash)"

pass=0
fail=0

ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n== %s\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 1; }

assert_eq() {
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "expected '$1', got '$2'"; fi
}
assert_ne() {
    if [ "$1" != "$2" ]; then ok "$3"; else bad "$3" "expected anything but '$1'"; fi
}
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3" "no '$2' in: $1"; fi
}
assert_lacks() {
    if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3" "unexpected '$2' in: $1"; else ok "$3"; fi
}

[ -f "$script_src" ] || fatal "missing $script_src"
[ -n "$pinned" ] || fatal ".shellcheck-version is empty"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# --- The fixture repository ------------------------------------------------------
repo="$sandbox/repo"
mkdir -p "$repo/scripts"
cp "$script_src" "$repo/scripts/shellcheck-pinned.sh"
printf '%s\n' "$pinned" > "$repo/.shellcheck-version"
printf '#!/usr/bin/env bash\necho clean\n' > "$repo/scripts/clean.sh"
(
    cd "$repo" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    git add -A
    git commit -q -m fixture
)
[ "$(git -C "$repo" rev-list --count HEAD 2>/dev/null)" = 1 ] || fatal "fixture: expected one commit"

# --- PATH: real tools by symlink, stubs for the instruments ----------------------
# Whatever the script calls must resolve here and nowhere else.
realbin="$sandbox/realbin"
mkdir -p "$realbin"
for tool in git xargs awk tr grep cat mkdir tar rm sleep dirname uname sed head; do
    p="$(command -v "$tool")" || fatal "tool not found: $tool"
    ln -s "$p" "$realbin/$tool"
done

# A stub's log line records which instrument linted, so an arm can assert that
# the local release was (or was not) run.
lint_log="$sandbox/lint.log"

# make_stubs <dir> <docker-mode> <cached-mode> <local-version>
#   docker-mode:  none | ok | ok-findings | daemon-down | daemon-hang | wrong-version
#   cached-mode:  none | runnable | unrunnable
#   local-version: version the PATH shellcheck reports, or "none"
make_stubs() {
    local dir="$1" docker_mode="$2" cached_mode="$3" local_v="$4"
    rm -rf "$dir"
    mkdir -p "$dir/bin" "$dir/cache"
    for f in "$realbin"/*; do ln -s "$(readlink "$f")" "$dir/bin/$(basename "$f")"; done

    # curl always fails: no arm may reach the network.
    printf '#!/bin/sh\nexit 22\n' > "$dir/bin/curl"

    if [ "$local_v" != none ]; then
        cat > "$dir/bin/shellcheck" <<STUB
#!/bin/sh
if [ "\$1" = --version ]; then printf 'ShellCheck - stub\nversion: %s\n' "$local_v"; exit 0; fi
echo local >> "$lint_log"
for f in "\$@"; do if grep -q FINDING "\$f"; then echo "\$f: finding"; exit 1; fi; done
exit 0
STUB
    fi

    if [ "$docker_mode" != none ]; then
        local image_v="$pinned" lint_exit_on_finding=1
        [ "$docker_mode" = wrong-version ] && image_v="0.0.1"
        cat > "$dir/bin/docker" <<STUB
#!/bin/sh
mode="$docker_mode"
case "\$1" in
  version|info)
    [ "\$mode" = daemon-down ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
    [ "\$mode" = daemon-hang ] && exec sleep 30
    echo 27.0.0; exit 0 ;;
  image) exit 0 ;;
  pull) echo "stub docker: pull must never run in this suite" >&2; echo pull >> "$lint_log"; exit 1 ;;
  run)
    # Everything after the image name is shellcheck's own argv.
    shift
    while [ \$# -gt 0 ]; do case "\$1" in koalaman/shellcheck:*) shift; break ;; *) shift ;; esac; done
    if [ "\${1:-}" = --version ]; then printf 'ShellCheck - stub\nversion: %s\n' "$image_v"; exit 0; fi
    echo docker >> "$lint_log"
    for f in "\$@"; do if grep -q FINDING "\$f"; then echo "\$f: finding"; exit $lint_exit_on_finding; fi; done
    exit 0 ;;
esac
exit 0
STUB
    fi

    local cdir="$dir/cache/skill-kit/shellcheck-v$pinned"
    case "$cached_mode" in
        runnable)
            mkdir -p "$cdir"
            cat > "$cdir/shellcheck" <<STUB
#!/bin/sh
if [ "\$1" = --version ]; then printf 'version: %s\n' "$pinned"; exit 0; fi
echo native >> "$lint_log"
for f in "\$@"; do if grep -q FINDING "\$f"; then echo "\$f: finding"; exit 1; fi; done
exit 0
STUB
            ;;
        unrunnable)
            mkdir -p "$cdir"
            printf '#!/bin/sh\necho "Bad CPU type in executable" >&2\nexit 126\n' > "$cdir/shellcheck"
            ;;
    esac
    chmod +x "$dir"/bin/* 2>/dev/null
    [ -f "$cdir/shellcheck" ] && chmod +x "$cdir/shellcheck"
    return 0
}

# run_case <docker-mode> <cached-mode> <local-version> <override 0|1> <finding 0|1>
# Sets: rc, err (stderr), log (instruments that linted, space-joined), elapsed.
run_case() {
    local dir="$sandbox/case"
    make_stubs "$dir" "$1" "$2" "$3"
    : > "$lint_log"
    if [ "$5" = 1 ]; then
        printf '#!/usr/bin/env bash\n# FINDING\n' > "$repo/scripts/finding.sh"
    else
        rm -f "$repo/scripts/finding.sh"
    fi
    local start end
    start="$(date +%s)"
    if [ "$4" = 1 ]; then
        err="$(cd "$repo" && env -i HOME="$dir/home" XDG_CACHE_HOME="$dir/cache" PATH="$dir/bin" \
            SHELLCHECK_PINNED_ALLOW_FALLBACK=1 "$bash_bin" scripts/shellcheck-pinned.sh 2>&1 >/dev/null)"
        rc=$?
    else
        err="$(cd "$repo" && env -i HOME="$dir/home" XDG_CACHE_HOME="$dir/cache" PATH="$dir/bin" \
            "$bash_bin" scripts/shellcheck-pinned.sh 2>&1 >/dev/null)"
        rc=$?
    fi
    end="$(date +%s)"
    elapsed=$((end - start))
    log="$(tr '\n' ' ' < "$lint_log" | sed 's/ $//')"
}

# --- 0. The pinned paths are unchanged -------------------------------------------
section "the PATH shellcheck at the pinned release lints and exits 0"
run_case none none "$pinned" 0 0
assert_eq 0 "$rc" "exit 0"
assert_eq local "$log" "the local (pinned) release linted"

section "a runnable cached pinned binary lints and exits with the lint's result"
run_case none runnable 0.11.0 0 0
assert_eq 0 "$rc" "clean: exit 0"
assert_eq native "$log" "the cached pinned binary linted, not the local release"
run_case none runnable 0.11.0 0 1
assert_ne 0 "$rc" "finding: exit nonzero"
assert_ne 3 "$rc" "finding: not the fallback's 3"

# --- 1. Fallback without the override exits 3, at both sites --------------------
section "download impossible, no Docker: the local fallback lints, then exits 3"
run_case none none 0.11.0 0 0
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release still linted"
assert_contains "$err" "SHELLCHECK_PINNED_ALLOW_FALLBACK=1" "the exit-3 message names the override"
assert_contains "$err" "NOT THE MERGE GATE'S INSTRUMENT" "the warning is still printed"

section "cached binary will not run, no Docker: the local fallback lints, then exits 3"
run_case none unrunnable 0.11.0 0 0
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release still linted"
assert_contains "$err" "SHELLCHECK_PINNED_ALLOW_FALLBACK=1" "the exit-3 message names the override"

# --- 2. With the override a clean fallback exits 0 ------------------------------
section "SHELLCHECK_PINNED_ALLOW_FALLBACK=1: a clean fallback exits 0, at both sites"
run_case none none 0.11.0 1 0
assert_eq 0 "$rc" "download site: exit 0"
assert_eq local "$log" "download site: the local release linted"
run_case none unrunnable 0.11.0 1 0
assert_eq 0 "$rc" "unrunnable site: exit 0"

# --- 3. A fallback with findings exits nonzero either way ------------------------
section "a fallback run with findings exits nonzero, with or without the override"
run_case none none 0.11.0 0 1
assert_ne 0 "$rc" "no override: nonzero (got $rc)"
run_case none none 0.11.0 1 1
assert_ne 0 "$rc" "override: nonzero (got $rc)"
run_case none unrunnable 0.11.0 1 1
assert_ne 0 "$rc" "unrunnable site, override: nonzero (got $rc)"

# --- 4. The Docker tier ---------------------------------------------------------
section "native pinned binary unavailable, Docker answers: the pinned image lints"
run_case ok none 0.11.0 0 0
assert_eq 0 "$rc" "download site, clean: exit 0"
assert_eq docker "$log" "the image linted; the local release did not"
assert_contains "$err" "Docker" "stderr names Docker as the instrument"
assert_contains "$err" "koalaman/shellcheck:v$pinned" "stderr names the pinned image"
run_case ok unrunnable 0.11.0 0 0
assert_eq 0 "$rc" "unrunnable site, clean: exit 0"
assert_eq docker "$log" "unrunnable site: the image linted"
run_case ok none 0.11.0 0 1
assert_ne 0 "$rc" "finding: exit nonzero"
assert_ne 3 "$rc" "finding: the lint's result, not the fallback's 3"
assert_lacks "$log" local "finding: the local release did not lint"
assert_lacks "$log" pull "no image pull was attempted (the stub reports the image present)"

section "Docker answers but the image is not the pinned release: fall through to the local fallback"
run_case wrong-version none 0.11.0 0 0
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release linted"

# --- 5. Docker installed, daemon not answering -----------------------------------
section "Docker installed, daemon down: falls through to the local fallback"
run_case daemon-down none 0.11.0 0 0
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release linted"

section "Docker installed, daemon hangs: the check is bounded, then the local fallback runs"
run_case daemon-hang none 0.11.0 0 0
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release linted"
if [ "$elapsed" -lt 20 ]; then ok "returned in ${elapsed}s (the stub hangs for 30s)"; else bad "bounded daemon check" "took ${elapsed}s"; fi

# --- 6. No instrument at all ----------------------------------------------------
section "no pinned binary, no Docker, no local shellcheck: exit 1, not 0 or 3"
run_case none none none 1 0
assert_eq 1 "$rc" "exit 1 even with the override"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
