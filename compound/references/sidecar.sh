#!/usr/bin/env bash
# sidecar.sh — find, create, read, and commit to a project's sidecar.
#
# A sidecar is a private git repository outside the project's tree, at
# ${SKILL_KIT_SIDECAR_ROOT:-$HOME/.claude/sidecars}/<name>/, holding the pack's
# per-project configuration (sidecar.json), the research archive (research/),
# and solutions entries (solutions/<category>/). This script is the only thing
# that computes a sidecar path or runs git against one; skills call it from
# their bundled references/sidecar.sh and never inline either.
#
# Usage:
#   sidecar.sh resolve
#   sidecar.sh init [--name <n>] --mode <owned|guest> --write <sidecar|in-tree|ask> --in-tree-path <path|none>
#                   [--migrate-archive | --no-migrate-archive] [--archive-alias <dir>]...
#   sidecar.sh config get <dotted.key>
#   sidecar.sh path <research|solutions>
#   sidecar.sh commit -- <path>... -m <msg>
#   sidecar.sh require <path> --from <referrer>
#
# Exit codes: 0 success, 1 miss or refusal, 2 usage.
#
# Archive migration. init, by default, moves the files of each directory under
# ${SKILL_KIT_RESEARCH_ARCHIVE:-$HOME/.claude/research} whose name matches this
# project into <sidecar>/research/, and leaves a symlink at the old directory
# pointing there. --no-migrate-archive skips it. A directory matches when its
# lowercased name is owner-repo cut from a remote key, or, only when the
# checkout has no remote, the main checkout's basename (the one form the old
# /research improvised, and only for repos without a remote). A basename is not
# project identity: a remote-less project archived as api/ must not be claimed
# by an unrelated repo that happens to be checked out at .../api. A project
# archived under its basename before it gained a remote opts that directory in
# with --archive-alias <dir> (repeatable, matched lowercased, one path component).
#
# Identity. A sidecar is found by the keys in its sidecar.json, tried in order:
#   root:<sha>               lexicographically first root commit; skipped in a
#                            shallow clone, whose root is not the real one
#   remote:<host/full/path>  every remote with a host, lowercased, with the
#                            scheme, user, port, trailing / and .git stripped;
#                            local-path remotes carry no identity and are skipped
#   path:<realpath>          the main checkout (not a linked worktree)
# Every key is lowercased, because default APFS is case-insensitive and Linux
# is not. On a hit, keys the current checkout has and the sidecar lacks are
# appended and committed. No two sidecars may share a key: init refuses to
# create a collision, and resolve warns when it finds one.
#
# Isolation. Every git call clears GIT_DIR, GIT_WORK_TREE, and GIT_INDEX_FILE.
# Git exports GIT_DIR into hooks; left set, `git -C <sidecar> commit` exits 0
# and lands the commit in the project. Nothing here writes to the project's
# tree or its .git, and nothing pushes, pulls, or fetches.
#
# Requires git >= 2.31 (--path-format=absolute) and jq >= 1.6.
#
# scripts/test-sidecar-resolution.sh runs this file against scratch repos.

set -u

SIDECAR_ROOT="${SKILL_KIT_SIDECAR_ROOT:-$HOME/.claude/sidecars}"
# Keys and paths are split on newlines only: a checkout path may contain spaces.
IFS=$'\n'

die_usage() { printf 'sidecar.sh: %s\n' "$1" >&2; exit 2; }
refuse()    { printf 'sidecar.sh: %s\n' "$1" >&2; exit 1; }

# git against the project, discovered from the cwd rather than from a leaked env.
pgit() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git "$@"; }
# git against a sidecar.
sgit() { local dir="$1"; shift; env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$dir" "$@"; }

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Normalize a remote URL to host/full/path, or print nothing.
norm_remote() {
    local u="$1" hostpart rest host
    case "$u" in
        file://*) return 0 ;;
        *://*)
            u="${u#*://}"
            hostpart="${u%%/*}"
            [ "$hostpart" = "$u" ] && return 0
            rest="${u#*/}"
            host="${hostpart##*@}"
            host="${host%%:*}"
            ;;
        *:*)
            # scp-like [user@]host:path — git reads it so only when no / precedes the colon
            hostpart="${u%%:*}"
            case "$hostpart" in */*) return 0 ;; esac
            rest="${u#*:}"
            host="${hostpart##*@}"
            ;;
        *) return 0 ;;
    esac
    while [ "${rest%/}" != "$rest" ]; do rest="${rest%/}"; done
    rest="${rest%.git}"
    while [ "${rest%/}" != "$rest" ]; do rest="${rest%/}"; done
    while [ "${rest#/}" != "$rest" ]; do rest="${rest#/}"; done
    if ! { [ -n "$host" ] && [ -n "$rest" ]; }; then return 0; fi
    lower "$host/$rest"
}

in_repo() { pgit rev-parse --git-dir >/dev/null 2>&1; }

main_checkout() {
    local common
    common="$(pgit rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    if [ "$(basename "$common")" = ".git" ]; then
        (cd "$(dirname "$common")" && pwd -P)
    else
        (cd "$(pgit rev-parse --show-toplevel)" && pwd -P)
    fi
}

# Print the current checkout's keys, one per line, in resolution order.
# Prints the shallow notice on stderr when it skips the root key.
current_keys() {
    local root r url n mc
    if [ "$(pgit rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
        printf 'sidecar.sh: shallow clone — skipping the root: key, resolving by remote or path\n' >&2
    else
        root="$(pgit rev-list --max-parents=0 HEAD 2>/dev/null | LC_ALL=C sort | head -n 1)"
        [ -n "$root" ] && printf 'root:%s\n' "$(lower "$root")"
    fi
    for r in $(pgit remote 2>/dev/null); do
        url="$(pgit remote get-url "$r" 2>/dev/null)" || continue
        n="$(norm_remote "$url")"
        [ -n "$n" ] && printf 'remote:%s\n' "$n"
    done
    mc="$(main_checkout)" && [ -n "$mc" ] && printf 'path:%s\n' "$(lower "$mc")"
}

# Sidecar directories whose sidecar.json carries key $1, one per line.
owners_of() {
    local key="$1" f
    for f in "$SIDECAR_ROOT"/*/sidecar.json; do
        [ -f "$f" ] || continue
        if jq -e --arg k "$key" '(.keys // []) | index($k) != null' "$f" >/dev/null 2>&1; then
            dirname "$f"
        fi
    done
}

suggest_name() {
    local r url n name
    for r in $(pgit remote 2>/dev/null); do
        url="$(pgit remote get-url "$r" 2>/dev/null)" || continue
        n="$(norm_remote "$url")"
        if [ -n "$n" ]; then
            n="${n#*/}"
            case "$n" in
                */*) name="$(basename "$(dirname "$n")")-$(basename "$n")" ;;
                *)   name="$n" ;;
            esac
            break
        fi
    done
    [ -n "${name:-}" ] || name="$(basename "$(main_checkout)")"
    lower "$name" | tr -c 'a-z0-9._-' '-' | sed 's/^-*//; s/-*$//'
}

# commit_paths <sidecar> <msg> <relpath>...
# Pathspec-only, so a concurrent writer's staged file is never swept in; retried
# because two sessions share one index.lock; "nothing to commit" means another
# writer already committed this exact content, which is success.
commit_paths() {
    local dir="$1" msg="$2" out i
    shift 2
    i=0
    while [ "$i" -lt 20 ]; do
        i=$((i + 1))
        if out="$(LC_ALL=C sgit "$dir" add -- "$@" 2>&1)"; then
            if out="$(LC_ALL=C sgit "$dir" commit -q --only -m "$msg" -- "$@" 2>&1)"; then
                return 0
            fi
            case "$out" in
                *"nothing to commit"*|*"no changes added to commit"*|*"nothing added to commit"*) return 0 ;;
            esac
        fi
        sleep 0.2
    done
    printf 'sidecar.sh: commit failed after 20 attempts: %s\n' "$out" >&2
    return 1
}

# Print the resolved sidecar path, or the miss message and return 1.
do_resolve() {
    local keys key owners count hit="" missing new_keys tmp k other
    in_repo || refuse "not inside a git repository"
    keys="$(current_keys)"
    for key in $keys; do
        owners="$(owners_of "$key")"
        [ -n "$owners" ] || continue
        count="$(printf '%s\n' "$owners" | wc -l | tr -d ' ')"
        hit="$(printf '%s\n' "$owners" | head -n 1)"
        if [ "$count" -gt 1 ]; then
            printf 'ALIAS COLLISION: %s is claimed by %s sidecars: %s — using %s\n' \
                "$key" "$count" "$(printf '%s' "$owners" | tr '\n' ' ')" "$hit" >&2
        fi
        break
    done
    if [ -z "$hit" ]; then
        # Absolute path to this script: a bare `sidecar.sh` is on no one's PATH.
        self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
        printf 'SIDECAR MISS: run: bash %s init --name %s --mode <owned|guest> --write <sidecar|in-tree|ask> --in-tree-path <path|none>\n' \
            "$self" "$(suggest_name)" >&2
        return 1
    fi
    new_keys=""
    for k in $keys; do
        if ! jq -e --arg k "$k" '(.keys // []) | index($k) != null' "$hit/sidecar.json" >/dev/null 2>&1; then
            other="$(owners_of "$k" | head -n 1)"
            if [ -n "$other" ]; then
                printf 'ALIAS COLLISION: %s already belongs to %s; not adding it to %s\n' "$k" "$other" "$hit" >&2
            else
                new_keys="$new_keys
$k"
            fi
        fi
    done
    if [ -n "$new_keys" ]; then
        new_keys="${new_keys#?}"
        tmp="$(mktemp "$hit/.sidecar.json.XXXXXX")"
        # shellcheck disable=SC2086 # word-splitting the key list is the point
        if jq '.keys += ($ARGS.positional - .keys)' --args $new_keys < "$hit/sidecar.json" > "$tmp"; then
            mv "$tmp" "$hit/sidecar.json"
            missing="$(printf '%s' "$new_keys" | tr '\n' ' ')"
            commit_paths "$hit" "sidecar: add alias $missing" sidecar.json || return 1
            printf 'sidecar.sh: added alias %s\n' "$missing" >&2
        else
            rm -f "$tmp"
        fi
    fi
    printf '%s\n' "$hit"
}

cmd_init() {
    local name="" mode="" write="" itp="" keys key owner gname gemail dir storage top forge_kind host forge_write migrate=1 aliases=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --name)         [ $# -ge 2 ] || die_usage "--name needs a value"; name="$2"; shift 2 ;;
            --mode)         [ $# -ge 2 ] || die_usage "--mode needs a value"; mode="$2"; shift 2 ;;
            --write)        [ $# -ge 2 ] || die_usage "--write needs a value"; write="$2"; shift 2 ;;
            --in-tree-path) [ $# -ge 2 ] || die_usage "--in-tree-path needs a value"; itp="$2"; shift 2 ;;
            --migrate-archive)    migrate=1; shift ;;
            --no-migrate-archive) migrate=0; shift ;;
            --archive-alias)
                [ $# -ge 2 ] || die_usage "--archive-alias needs a value"
                case "$2" in ''|*/*|.|..) die_usage "init: --archive-alias must be one directory name: $2" ;; esac
                aliases="${aliases:+$aliases$'\n'}$(lower "$2")"; shift 2 ;;
            *) die_usage "init: unknown argument: $1" ;;
        esac
    done
    case "$mode" in owned|guest) ;; *) die_usage "init: --mode must be owned or guest" ;; esac
    case "$write" in sidecar|in-tree|ask) ;; *) die_usage "init: --write must be sidecar, in-tree, or ask" ;; esac
    [ -n "$itp" ] || die_usage "init: --in-tree-path is required (a path, or none)"
    if [ "$write" != "sidecar" ] && [ "$itp" = "none" ]; then
        die_usage "init: --write $write needs an in-tree path, not none"
    fi
    in_repo || refuse "not inside a git repository"
    [ -n "$name" ] || name="$(suggest_name)"
    case "$name" in
        ''|.*|*/*|*[!a-z0-9._-]*) die_usage "init: --name must be lowercase letters, digits, '.', '_' or '-': $name" ;;
    esac

    keys="$(current_keys)"
    [ -n "$keys" ] || refuse "init: this checkout has no root commit, remote, or path to key on"
    for key in $keys; do
        owner="$(owners_of "$key" | head -n 1)"
        [ -z "$owner" ] || refuse "init refused: $key already belongs to sidecar $(basename "$owner") ($owner)"
    done
    dir="$SIDECAR_ROOT/$name"
    [ ! -e "$dir" ] || refuse "init refused: $dir already exists"

    gname="$(pgit config --global user.name 2>/dev/null || true)"
    gemail="$(pgit config --global user.email 2>/dev/null || true)"
    if [ -z "$gname" ] || [ -z "$gemail" ]; then
        refuse "init refused: set a global git identity first (git config --global user.name / user.email); the sidecar will not inherit a repo-local one"
    fi

    top="$(pgit rev-parse --show-toplevel)"
    storage="$(jq -r '.research.storage // "archive"' "$top/.claude/settings.json" 2>/dev/null || echo archive)"
    case "$storage" in archive|spike-issue) ;; *) storage=archive ;; esac

    forge_kind=none
    host="$(printf '%s\n' "$keys" | sed -n 's/^remote:\([^/]*\)\/.*/\1/p' | head -n 1)"
    case "$host" in
        github.com|*.github.com) forge_kind=github ;;
        gitlab.com|gitlab.*)     forge_kind=gitlab ;;
        bitbucket.org)           forge_kind=bitbucket ;;
    esac
    if [ "$mode" = "owned" ] && [ "$forge_kind" != "none" ]; then
        forge_write='["issues","labels","milestones","prs"]'
    else
        forge_write='[]'
    fi

    mkdir -p "$dir" || refuse "init: cannot create $dir"
    # $dir did not exist above, so init created it. Any failure from here on
    # (git init, config, the jq write, the first commit) would leave a
    # sidecar claiming these keys with no committed sidecar.json, and block
    # every retry; remove it on any exit until success clears the trap.
    INIT_CREATED_DIR="$dir"
    trap 'rm -rf "$INIT_CREATED_DIR"' EXIT
    sgit "$dir" init -q -b main || refuse "init: git init failed in $dir"
    sgit "$dir" config user.name "$gname"
    sgit "$dir" config user.email "$gemail"
    # shellcheck disable=SC2086 # word-splitting the key list is the point
    jq -n \
        --arg name "$name" --arg mode "$mode" --arg write "$write" --arg itp "$itp" \
        --arg storage "$storage" --arg forge "$forge_kind" --argjson fwrite "$forge_write" \
        --arg created "$(date +%Y-%m-%d)" \
        '{
           schema: 1,
           name: $name,
           keys: $ARGS.positional,
           mode: $mode,
           solutions: { write: $write, in_tree_path: $itp },
           research: { storage: $storage },
           forge: { kind: $forge, write: $fwrite },
           tracker: { kind: "none", url: "", write: [] },
           verify: { typecheck: "", test: "", lint: "", package_manager: "", hook_manager: "" },
           created: $created
         }' --args $keys > "$dir/sidecar.json" || refuse "init: could not write sidecar.json"
    commit_paths "$dir" "sidecar: init $name" sidecar.json || exit 1
    trap - EXIT
    # After the trap is cleared: a migration failure must not delete a sidecar
    # that already holds moved archive files.
    if [ "$migrate" -eq 1 ]; then
        migrate_archive "$dir" "$keys" "$aliases" || exit 1
    fi
    printf '%s\n' "$dir"
}

# Directory names the old research archive used for this project, lowercased:
# owner-repo cut from each remote key, and, only when there is no remote key,
# the main checkout's basename, which /research improvised for repos with no
# remote. <keys> is the checkout's key list.
archive_names() {
    local keys="$1" k n has_remote=0
    for k in $keys; do case "$k" in remote:*) has_remote=1 ;; esac; done
    for k in $keys; do
        case "$k" in
            remote:*)
                n="${k#remote:}"
                n="${n#*/}"
                case "$n" in
                    */*) printf '%s-%s\n' "$(basename "$(dirname "$n")")" "$(basename "$n")" ;;
                    *)   printf '%s\n' "$n" ;;
                esac
                ;;
            path:*) [ "$has_remote" -eq 1 ] || basename "${k#path:}" ;;
        esac
    done
}

# migrate_archive <sidecar> <keys> <aliases>
# Moves each matching archive directory's files into <sidecar>/research/ and
# replaces the directory with a symlink to it, so the absolute archive paths
# embedded in PRD issues still resolve. A directory holding a file whose name
# exists in research/ with different content is left untouched. Actions are
# printed on stderr; stdout stays the sidecar path.
migrate_archive() {
    local sc="$1" keys="$2" aliases="${3:-}" archive dest names d base e target moved conflict any=0
    archive="${SKILL_KIT_RESEARCH_ARCHIVE:-$HOME/.claude/research}"
    [ -d "$archive" ] || return 0
    dest="$sc/research"
    mkdir -p "$dest" || refuse "init: cannot create $dest"
    names="$({ archive_names "$keys"; [ -z "$aliases" ] || printf '%s\n' "$aliases"; } | LC_ALL=C sort -u)"
    [ -n "$names" ] || return 0
    for d in "$archive"/*; do
        [ -d "$d" ] || continue
        [ -L "$d" ] && continue
        base="$(lower "$(basename "$d")")"
        printf '%s\n' "$names" | grep -qxF -- "$base" || continue
        conflict=0
        for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do
            [ -e "$e" ] || [ -L "$e" ] || continue
            target="$dest/$(basename "$e")"
            if [ -e "$target" ] && ! { [ -f "$e" ] && [ -f "$target" ] && cmp -s "$e" "$target"; }; then
                printf 'sidecar.sh: archive: left %s untouched: %s already exists in %s with different content\n' \
                    "$d" "$(basename "$e")" "$dest" >&2
                conflict=1
                break
            fi
        done
        [ "$conflict" -eq 0 ] || continue
        moved=0
        for e in "$d"/* "$d"/.[!.]* "$d"/..?*; do
            [ -e "$e" ] || [ -L "$e" ] || continue
            target="$dest/$(basename "$e")"
            if [ -e "$target" ]; then
                rm -f "$e"
            else
                mv "$e" "$target" || refuse "init: archive: could not move $e into $dest"
            fi
            moved=$((moved + 1))
        done
        rmdir "$d" || refuse "init: archive: $d is not empty after the move; left in place"
        ln -s "$dest" "$d" || refuse "init: archive: could not link $d to $dest"
        printf 'sidecar.sh: archive: moved %s file(s) from %s into %s; %s is now a symlink to it\n' \
            "$moved" "$d" "$dest" "$d" >&2
        any=1
    done
    if [ "$any" -eq 1 ] && [ -n "$(ls -A "$dest")" ]; then
        commit_paths "$sc" "sidecar: migrate research archive" research || return 1
    fi
    return 0
}

cmd_config() {
    local sc
    if ! { [ "${1:-}" = "get" ] && [ $# -eq 2 ]; }; then die_usage "usage: sidecar.sh config get <dotted.key>"; fi
    sc="$(do_resolve)" || exit 1
    jq -r --arg k "$2" 'getpath($k | split(".")) // empty' "$sc/sidecar.json"
}

cmd_path() {
    local sc
    [ $# -eq 1 ] || die_usage "usage: sidecar.sh path <research|solutions>"
    case "$1" in research|solutions) ;; *) die_usage "path: expected research or solutions, got: $1" ;; esac
    sc="$(do_resolve)" || exit 1
    mkdir -p "$sc/$1" || refuse "path: cannot create $sc/$1"
    printf '%s\n' "$sc/$1"
}

cmd_commit() {
    local msg="" have_msg=0 sc real p d rel
    local paths=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -m) [ $# -ge 2 ] || die_usage "commit: -m needs a message"; msg="$2"; have_msg=1; shift 2 ;;
            --) shift ;;
            *)  paths+=("$1"); shift ;;
        esac
    done
    if ! { [ "$have_msg" -eq 1 ] && [ -n "$msg" ]; }; then die_usage "usage: sidecar.sh commit -- <path>... -m <msg>"; fi
    [ "${#paths[@]}" -gt 0 ] || die_usage "usage: sidecar.sh commit -- <path>... -m <msg>"
    sc="$(do_resolve)" || exit 1
    real="$(cd "$sc" && pwd -P)"
    local rels=()
    for p in "${paths[@]}"; do
        case "$p" in
            /*)
                d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || refuse "commit: no such directory: $(dirname "$p")"
                rel="$d/$(basename "$p")"
                case "$rel" in
                    "$real"/*) rel="${rel#"$real"/}" ;;
                    *) refuse "commit refused: $p is outside the sidecar ($sc)" ;;
                esac
                ;;
            *) rel="$p" ;;
        esac
        [ -e "$real/$rel" ] || refuse "commit: no such file in the sidecar: $rel"
        rels+=("$rel")
    done
    commit_paths "$real" "$msg" "${rels[@]}" || exit 1
}

cmd_require() {
    local path="" from=""
    [ $# -ge 1 ] || die_usage "usage: sidecar.sh require <path> --from <referrer>"
    path="$1"; shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --from) [ $# -ge 2 ] || die_usage "require: --from needs a value"; from="$2"; shift 2 ;;
            *) die_usage "require: unknown argument: $1" ;;
        esac
    done
    if ! { [ -n "$path" ] && [ -n "$from" ]; }; then die_usage "usage: sidecar.sh require <path> --from <referrer>"; fi
    # A quoted "~/..." reaches us unexpanded (older PRDs record research paths this way).
    local probe="$path"
    # shellcheck disable=SC2088  # the literal ~ is the point
    case "$path" in "~/"*) probe="$HOME/${path#"~/"}" ;; esac
    # A relative link inside a lesson is relative to the lesson's own folder, so when
    # --from names an existing file, also try the path beside it.
    if [ ! -e "$probe" ] && [ -f "$from" ]; then
        case "$probe" in /*) ;; *) [ -e "$(dirname "$from")/$probe" ] && probe="$(dirname "$from")/$probe" ;; esac
    fi
    if [ ! -e "$probe" ]; then
        printf 'MISSING: %s (referenced by %s)\n' "$path" "$from" >&2
        exit 1
    fi
}

verb="${1:-}"
[ $# -gt 0 ] && shift
case "$verb" in
    resolve) [ $# -eq 0 ] || die_usage "usage: sidecar.sh resolve"; do_resolve || exit 1 ;;
    init)    cmd_init "$@" ;;
    config)  cmd_config "$@" ;;
    path)    cmd_path "$@" ;;
    commit)  cmd_commit "$@" ;;
    require) cmd_require "$@" ;;
    *) die_usage "usage: sidecar.sh <resolve|init|config get|path|commit|require> ..." ;;
esac
