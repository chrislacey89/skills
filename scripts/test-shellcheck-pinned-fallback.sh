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
#   - a local-release fallback run without the override: see section 1 below
#   - with the override it exits 0 on a clean lint
#   - a fallback run with findings exits nonzero with or without the override
#   - when the native pinned binary is unavailable and Docker answers, the
#     pinned image lints, and the exit is the lint's result (0 or nonzero,
#     never 3); the local release is not run
#   - Docker installed with a daemon that does not answer (fails fast, or
#     hangs) falls through to the local fallback within a bound
#   - first use, image not yet present: a successful pull lets the pinned image
#     lint; a pull that succeeds but yields another release falls through to the
#     local fallback (exit 3), so the version check runs after a pull too; a
#     failed pull skips the Docker tier without running the image and
#     falls through to the local fallback (exit 3). The stub docker only records
#     the pull; no arm contacts a registry
#   - every `docker run` names the pinned image: the stub records the image
#     reference each run was handed, for the version check and for the lint,
#     so a script that checks the pinned image and then lints with another tag
#     (or checks another tag) goes red
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
    if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3" "no '$2' in: $1"; fi
}
assert_lacks() {
    if grep -qF -- "$2" <<<"$1"; then bad "$3" "unexpected '$2' in: $1"; else ok "$3"; fi
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
# the local release was (or was not) run. The local stub also records, in the
# case directory's override.seen, whether SHELLCHECK_PINNED_ALLOW_FALLBACK was
# in its environment at all, so an unset arm can prove it ran unset. The docker
# stub records, in the case directory's run.refs, the image reference each
# `docker run` was handed (`version <ref>` or `lint <ref>`), so a Docker-tier
# arm can assert both runs used the pinned tag.
lint_log="$sandbox/lint.log"

# make_stubs <dir> <docker-mode> <cached-mode> <local-version>
#   docker-mode:  none | ok | ok-findings | daemon-down | daemon-hang | wrong-version
#                 | absent-pull-ok | absent-pull-wrong-version | absent-pull-fails
#                 (absent-*: `image inspect` exits 1 until a pull succeeds;
#                 wrong-version and absent-pull-wrong-version: the image
#                 reports 0.0.1, not the pinned release)
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
if [ -n "\${SHELLCHECK_PINNED_ALLOW_FALLBACK+set}" ]; then echo present; else echo absent; fi >> "$dir/override.seen"
for f in "\$@"; do if grep -q FINDING "\$f"; then echo "\$f: finding"; exit 1; fi; done
exit 0
STUB
    fi

    if [ "$docker_mode" != none ]; then
        local image_v="$pinned" lint_exit_on_finding=1 pull_ok=0
        if [ "$docker_mode" = wrong-version ] || [ "$docker_mode" = absent-pull-wrong-version ]; then
            image_v="0.0.1"
        fi
        if [ "$docker_mode" = absent-pull-ok ] || [ "$docker_mode" = absent-pull-wrong-version ]; then
            pull_ok=1
        fi
        # The image is present unless the mode starts absent; only a pull in
        # absent-pull-ok or absent-pull-wrong-version creates it. A run without it stands in for docker's own
        # implicit pull, so it is logged and fails rather than answering.
        local present="$dir/image-present"
        case "$docker_mode" in absent-*) ;; *) : > "$present" ;; esac
        cat > "$dir/bin/docker" <<STUB
#!/bin/sh
mode="$docker_mode"
case "\$1" in
  version|info)
    [ "\$mode" = daemon-down ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
    [ "\$mode" = daemon-hang ] && exec sleep 30
    echo 27.0.0; exit 0 ;;
  image) [ -f "$present" ] && exit 0; exit 1 ;;
  pull)
    # Log the image reference pulled (the last argument), so an arm catches a
    # pull of any tag but the pinned one.
    for a in "\$@"; do ref="\$a"; done
    echo "pull \$ref" >> "$lint_log"
    [ "$pull_ok" = 1 ] && { : > "$present"; exit 0; }
    echo "stub docker: pull failed (this suite never contacts a registry)" >&2; exit 1 ;;
  run)
    if [ ! -f "$present" ]; then echo run-without-image >> "$lint_log"; echo "stub docker: Unable to find image" >&2; exit 125; fi
    # Everything after the image name is shellcheck's own argv. The image
    # reference itself is logged to run.refs, so an arm catches a run of any
    # tag but the pinned one.
    shift
    ref=none
    while [ \$# -gt 0 ]; do case "\$1" in koalaman/shellcheck:*) ref="\$1"; shift; break ;; *) shift ;; esac; done
    if [ "\${1:-}" = --version ]; then echo "version \$ref" >> "$dir/run.refs"; printf 'ShellCheck - stub\nversion: %s\n' "$image_v"; exit 0; fi
    echo "lint \$ref" >> "$dir/run.refs"
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

# run_case <docker-mode> <cached-mode> <local-version> <allow|strict|unset> <finding|clean>
# The case statement below says what each override word sets. Section 1 runs
# both exit-3 sites under strict and under unset, so a default that turns
# unset into accept, and a check that accepts any non-empty value, each go red.
# finding plants a script with a lint finding.
# Sets: rc, err (stderr), log (instruments that linted, space-joined), elapsed,
# seen (present or absent: whether the override reached the local stub),
# runs (the docker stub's run.refs, space-joined; empty when no image ran).
run_case() {
    local dir="$sandbox/case"
    local override=()
    make_stubs "$dir" "$1" "$2" "$3"
    : > "$lint_log"
    case "$4" in
        allow) override=(SHELLCHECK_PINNED_ALLOW_FALLBACK=1) ;;
        strict) override=(SHELLCHECK_PINNED_ALLOW_FALLBACK=0) ;;
        unset) ;;
        *) bad "run_case" "unknown override word: $4"; return 1 ;;
    esac
    if [ "$5" = finding ]; then
        printf '#!/usr/bin/env bash\n# FINDING\n' > "$repo/scripts/finding.sh"
    else
        rm -f "$repo/scripts/finding.sh"
    fi
    local start end
    start="$(date +%s)"
    err="$(cd "$repo" && env -i HOME="$dir/home" XDG_CACHE_HOME="$dir/cache" PATH="$dir/bin" \
        ${override[@]+"${override[@]}"} "$bash_bin" scripts/shellcheck-pinned.sh 2>&1 >/dev/null)"
    rc=$?
    end="$(date +%s)"
    elapsed=$((end - start))
    log="$(tr '\n' ' ' < "$lint_log" | sed 's/ $//')"
    seen="$(cat "$dir/override.seen" 2>/dev/null)"
    runs=""
    [ -f "$dir/run.refs" ] && runs="$(tr '\n' ' ' < "$dir/run.refs" | sed 's/ $//')"
}

# Both Docker runs, the version check and then the lint, on the pinned image.
pinned_runs="version koalaman/shellcheck:v$pinned lint koalaman/shellcheck:v$pinned"

# --- 0. The pinned paths are unchanged -------------------------------------------
section "the PATH shellcheck at the pinned release lints and exits 0"
run_case none none "$pinned" strict clean
assert_eq 0 "$rc" "exit 0"
assert_eq local "$log" "the local (pinned) release linted"

section "a runnable cached pinned binary lints and exits with the lint's result"
run_case none runnable 0.11.0 strict clean
assert_eq 0 "$rc" "clean: exit 0"
assert_eq native "$log" "the cached pinned binary linted, not the local release"
run_case none runnable 0.11.0 strict finding
assert_ne 0 "$rc" "finding: exit nonzero"
assert_ne 3 "$rc" "finding: not the fallback's 3"

# --- 1. Fallback without the override exits 3, at both sites --------------------
section "download impossible, no Docker: the local fallback lints, then exits 3"
run_case none none 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release still linted"
assert_eq present "$seen" "strict: the override variable is in the script's environment"
assert_contains "$err" "SHELLCHECK_PINNED_ALLOW_FALLBACK=1" "the exit-3 message names the override"
assert_contains "$err" "NOT THE MERGE GATE'S INSTRUMENT" "the warning is still printed"

section "cached binary will not run, no Docker: the local fallback lints, then exits 3"
run_case none unrunnable 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release still linted"
assert_contains "$err" "SHELLCHECK_PINNED_ALLOW_FALLBACK=1" "the exit-3 message names the override"

section "the override left unset: exit 3, at both sites"
run_case none none 0.11.0 unset clean
assert_eq 3 "$rc" "download site, unset: exit 3"
assert_eq local "$log" "download site, unset: the local release still linted"
assert_eq absent "$seen" "download site, unset: the override variable is not in the script's environment"
run_case none unrunnable 0.11.0 unset clean
assert_eq 3 "$rc" "unrunnable site, unset: exit 3"
assert_eq local "$log" "unrunnable site, unset: the local release still linted"
assert_eq absent "$seen" "unrunnable site, unset: the override variable is not in the script's environment"

# --- 2. With the override a clean fallback exits 0 ------------------------------
section "SHELLCHECK_PINNED_ALLOW_FALLBACK=1: a clean fallback exits 0, at both sites"
run_case none none 0.11.0 allow clean
assert_eq 0 "$rc" "download site: exit 0"
assert_eq local "$log" "download site: the local release linted"
run_case none unrunnable 0.11.0 allow clean
assert_eq 0 "$rc" "unrunnable site: exit 0"

# --- 3. A fallback with findings exits nonzero either way ------------------------
section "a fallback run with findings exits nonzero, with or without the override"
run_case none none 0.11.0 strict finding
assert_ne 0 "$rc" "no override: nonzero (got $rc)"
run_case none none 0.11.0 allow finding
assert_ne 0 "$rc" "override: nonzero (got $rc)"
run_case none unrunnable 0.11.0 allow finding
assert_ne 0 "$rc" "unrunnable site, override: nonzero (got $rc)"

# --- 4. The Docker tier ---------------------------------------------------------
section "native pinned binary unavailable, Docker answers: the pinned image lints"
run_case ok none 0.11.0 strict clean
assert_eq 0 "$rc" "download site, clean: exit 0"
assert_eq docker "$log" "the image linted; the local release did not"
assert_contains "$err" "Docker" "stderr names Docker as the instrument"
assert_contains "$err" "koalaman/shellcheck:v$pinned" "stderr names the pinned image"
assert_eq "$pinned_runs" "$runs" "the version check and the lint each ran the pinned image"
run_case ok unrunnable 0.11.0 strict clean
assert_eq 0 "$rc" "unrunnable site, clean: exit 0"
assert_eq docker "$log" "unrunnable site: the image linted"
assert_eq "$pinned_runs" "$runs" "unrunnable site: the version check and the lint each ran the pinned image"
run_case ok none 0.11.0 strict finding
assert_ne 0 "$rc" "finding: exit nonzero"
assert_ne 3 "$rc" "finding: the lint's result, not the fallback's 3"
assert_lacks "$log" local "finding: the local release did not lint"
assert_lacks "$log" pull "no image pull was attempted (the stub reports the image present)"
assert_eq "$pinned_runs" "$runs" "finding: the version check and the lint each ran the pinned image"

section "Docker answers but the image is not the pinned release: fall through to the local fallback"
run_case wrong-version none 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release linted"
assert_eq "version koalaman/shellcheck:v$pinned" "$runs" "the version check ran the pinned image, and no lint ran through Docker"

section "first use, image absent, pull succeeds: the pulled pinned image lints"
run_case absent-pull-ok none 0.11.0 strict clean
assert_eq 0 "$rc" "exit 0"
assert_eq "pull koalaman/shellcheck:v$pinned docker" "$log" "the pinned image was pulled, then it linted; the local release did not"
assert_contains "$err" "pulling koalaman/shellcheck:v$pinned (first use)" "stderr names the first-use pull"
assert_eq "$pinned_runs" "$runs" "the version check and the lint each ran the pulled pinned image"

section "first use, image absent, pull succeeds but the image is not the pinned release: the local fallback exits 3"
run_case absent-pull-wrong-version none 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq "pull koalaman/shellcheck:v$pinned local" "$log" "the pinned image was pulled, its version was checked, and the local release linted"
assert_contains "$err" "reports version '0.0.1', not $pinned" "stderr names the pulled image's wrong version"
assert_eq "version koalaman/shellcheck:v$pinned" "$runs" "the version check ran the pulled pinned image, and no lint ran through Docker"

section "first use, image absent, pull fails: skip the Docker tier, then the local fallback exits 3"
run_case absent-pull-fails none 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq "pull koalaman/shellcheck:v$pinned local" "$log" "the pull of the pinned image was tried, the image never ran, and the local release linted"
assert_contains "$err" "could not pull koalaman/shellcheck:v$pinned" "stderr names the failed pull"
assert_eq "" "$runs" "no image ran after the failed pull"

# --- 5. Docker installed, daemon not answering -----------------------------------
section "Docker installed, daemon down: falls through to the local fallback"
run_case daemon-down none 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release linted"

section "Docker installed, daemon hangs: the check is bounded, then the local fallback runs"
run_case daemon-hang none 0.11.0 strict clean
assert_eq 3 "$rc" "exit 3"
assert_eq local "$log" "the local release linted"
# This only proves the run did not wait for the stub to answer (it hangs 30s).
# The bound's own length (about 5s of wall-clock time) is not asserted: a
# tighter ceiling fails on a loaded machine, and an unbounded check is already
# caught above, since the stub answering would let Docker lint.
if [ "$elapsed" -lt 29 ]; then ok "returned in ${elapsed}s (the stub hangs for 30s)"; else bad "bounded daemon check" "took ${elapsed}s"; fi

# --- 6. No instrument at all ----------------------------------------------------
section "no pinned binary, no Docker, no local shellcheck: exit 1, not 0 or 3"
run_case none none none allow clean
assert_eq 1 "$rc" "exit 1 even with the override"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
