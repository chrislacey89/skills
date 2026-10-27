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
#   sidecar.sh config set mode <owned|guest>   (re-derives forge.write from the new mode, the way init does, and commits)
#   sidecar.sh config set base_ref <branch>   (refuses a branch that resolves to no ref)
#   sidecar.sh base-ref [--name]   (the base branch: a ref safe as a range endpoint, or with --name the bare branch name)
#   sidecar.sh path <research|solutions>
#   sidecar.sh solutions-dirs   (prints, one per line, the directories to search for lessons; no sidecar needed)
#   sidecar.sh migrate-archive [--archive-alias <dir>]...   (init's archive migration, for a sidecar that already exists; safe to re-run)
#   sidecar.sh archive-dir   (prints <archive root>/<suggested name>; no sidecar needed)
#   sidecar.sh commit -- <path>... -m <msg>
#   sidecar.sh require <path> --from <referrer>   (on a hit, prints the absolute resolved path)
#   sidecar.sh backend <prds|slices|stamp>   (prints github or sidecar; github when no sidecar resolves)
#   sidecar.sh stamp write <branch> <sha> [--base-ref <ref>]
#   sidecar.sh stamp read <branch>   (prints the 40-hex SHA, or nothing with exit 0)
#   sidecar.sh stamp clear <branch>
#   sidecar.sh work create --kind <prd|slice> [--parent W-n] [--blocked-by W-n,...] [--milestone <str>]
#                          [--maturity <roadmap bet|research-ready|prd>] --body-file <f>   (prints the new id)
#   sidecar.sh work view <W-n> [--json]
#   sidecar.sh work edit <W-n> --body-file <f>   (refuses a body shorter than the one it replaces)
#   sidecar.sh work set <W-n> <state|maturity|decomposed_into|pr|reviewed_sha> <value>
#   sidecar.sh work comment <W-n> --body-file <f>
#   sidecar.sh work close <W-n> [--superseded-by W-m]
#   sidecar.sh work list [--kind <prd|slice>] [--parent W-n] [--unblocked] [--state <open|closed|all>]
#
# backend. The routing rule is docs/state-backend.md's: prds and slices go to
# GitHub when forge.write contains "issues", the stamp when it contains "prs",
# and only when forge.kind is github, because every consumer of the github
# answer runs `gh`. Anything else is sidecar. No sidecar is github, which is
# the behavior before the sidecar existed.
#
# stamp. <sidecar>/reviews/<slug>.json holds the review stamp on the sidecar
# backend. The slug keeps [a-z0-9._-] and writes every other byte as %XX
# (uppercase hex), so it is reversible and two branches differing only in case
# cannot share a file on a case-insensitive filesystem. read matches on the
# JSON branch field, and prints nothing for a stamp it cannot parse or whose
# reviewed_sha is not 40 lowercase hex. /pre-merge is the only skill that
# writes one (scripts/test-review-currency-marker.sh).
#
# work. <sidecar>/work/W-<n>.md is a PRD or slice on the sidecar backend: YAML
# frontmatter between --- lines, the body, then "## Comment <ISO-8601>"
# sections, which `work comment` alone appends. Frontmatter is written one
# "key: value" per line in a fixed order: ids, enums, and dates plain, lists
# as [W-1, W-2], free strings (milestone, pr) as JSON strings, so the reader
# below can parse what the writer writes without a YAML library. A new id is
# max(existing)+1, claimed by hard-linking a finished temp file to W-<n>.md,
# which fails if another writer got there first; the loser takes the next
# number. decomposed_into is replaced on every set, never appended to. edit
# compares byte counts against the body it read and refuses a shorter one. A
# body may not contain a comment heading, because the reader splits on it.
# The id regex is WORK_ID_RE, the one docs/state-backend.md states.
#
# require resolution order. The first candidate that exists wins; each step runs
# only when the one before found nothing.
#   1. <path> as given, relative to the current directory. A leading "~/" is
#      expanded to $HOME; "~user/" and a bare "~" are left alone, so they are
#      looked up literally and miss. A "#anchor" suffix is stripped when <path>
#      does not exist with it, so name.md#section finds name.md.
#   2. beside the referrer: dirname(<referrer>)/<path>, for a relative <path>.
#   3. for a bare name (no "/"): <name> in each sibling category folder, that is
#      dirname(dirname(<referrer>))/*/<name>, in glob (alphabetical) order. A name
#      found in more than one prints a warning naming every match on stderr, then
#      uses the first.
# Steps 2 and 3 run only when <referrer> is an existing file. A "path:line" or a
# prose referrer ("PRD #1") is only the label in the MISSING line, and disables
# both. A hit prints the physical path (pwd -P: symlinked folders resolved) of
# the file found; a miss prints "MISSING: <path> (referenced by <referrer>)" on
# stderr and exits 1.
#
# Exit codes: 0 success, 1 miss or refusal, 2 usage.
#
# Archive root. The pre-sidecar research archive lives under ARCHIVE_ROOT
# below; this file is the only place that default is spelled. On a miss,
# /research writes its entry to the directory archive-dir prints and
# /write-a-prd lists it from there, so the two cannot name different places.
#
# Archive migration. init, by default, moves the files of each directory under
# ARCHIVE_ROOT whose name matches this project into <sidecar>/research/, and
# leaves a symlink at the old directory pointing there. --no-migrate-archive
# skips it. A directory matches when its lowercased name is owner-repo cut from
# a remote key, or, only when the checkout has no remote, the main checkout's
# basename (the one form the old /research improvised, and only for repos
# without a remote). A basename is not
# project identity: a remote-less project archived as api/ must not be claimed
# by an unrelated repo that happens to be checked out at .../api. A project
# archived under its basename before it gained a remote opts that directory in
# with --archive-alias <dir> (repeatable, matched lowercased, one path component).
#
# solutions-dirs policy. The directories a reader searches for lessons, one per
# line: the sidecar's solutions/ (created if absent), then the project's
# solutions.in_tree_path unless it is "none", then docs/solutions when that
# directory exists in the tree and is not already listed (a /excavate PR commits
# there whatever in_tree_path says). With no sidecar it prints docs/solutions
# alone. In-tree entries are relative to the current directory.
#
# config set. forge.write is derived from mode (owned on a known forge gets
# write access, guest gets none), so mode is changed through this verb and
# never by editing sidecar.json. It overwrites forge.write with the derived
# value. base_ref is the base branch's bare name (develop, not origin/develop),
# checked against the same rule base-ref reads it with before it is written.
#
# base-ref. A declared base_ref wins. A sidecar miss, or a sidecar with no
# base_ref key, falls back to the derivation every skill used to inline:
# origin/HEAD's branch, else the first of main master prod develop trunk that
# resolves. The ref form is origin/<name> when that resolves, else the local
# <name> with a note on stderr that it may be stale; --name prints <name>.
# Three outcomes, as backend's: a value (declared or fallback) exits 0; could
# not look (no jq, an unreadable sidecar.json, a base_ref that is not a
# string) and a declared base_ref that resolves to no ref exit 1 and print
# nothing, because the fallback answers "nothing declared", never "could not
# read what was declared". No base branch found at all exits 1 as well.
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
# An inherited CDPATH sends every `cd "<relative dir>"` below into another tree
# and echoes it into the captured path; the paths this script prints must not
# depend on the caller's shell.
unset CDPATH

SIDECAR_ROOT="${SKILL_KIT_SIDECAR_ROOT:-$HOME/.claude/sidecars}"
ARCHIVE_ROOT="${SKILL_KIT_RESEARCH_ARCHIVE:-$HOME/.claude/research}"
# Keys and paths are split on newlines only: a checkout path may contain spaces.
IFS=$'\n'

die_usage() { printf 'sidecar.sh: %s\n' "$1" >&2; exit 2; }
refuse()    { printf 'sidecar.sh: %s\n' "$1" >&2; exit 1; }

# git against the project, discovered from the cwd rather than from a leaked env.
pgit() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git "$@"; }
# git against a sidecar.
sgit() { local dir="$1"; shift; env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$dir" "$@"; }

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# One path component, no newline: a newline would register two aliases.
alias_ok() { case "$1" in ''|*/*|.|..|*$'\n'*) return 1 ;; esac; }

# forge_kind_of <keys>: the forge a remote key's host belongs to, or none.
forge_kind_of() {
    local host
    host="$(printf '%s\n' "$1" | sed -n 's/^remote:\([^/]*\)\/.*/\1/p' | head -n 1)"
    case "$host" in
        github.com|*.github.com) echo github ;;
        gitlab.com|gitlab.*)     echo gitlab ;;
        bitbucket.org)           echo bitbucket ;;
        *)                       echo none ;;
    esac
}

# derive_forge_write <mode> <forge_kind>: the forge.write JSON array. The one
# place mode becomes write permission; init and config set both call it.
derive_forge_write() {
    if [ "$1" = "owned" ] && [ "$2" != "none" ]; then
        printf '%s' '["issues","labels","milestones","prs"]'
    else
        printf '%s' '[]'
    fi
}

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
# With -e, jq exits 1 for a false result (this key is not listed) and 0 for a
# true one (see `man jq`, --exit-status), so any other status is an error: the
# file is corrupt or unreadable, which is not a miss. Such a file cannot be
# ruled out as the key's owner without parsing it, so when no readable sidecar
# claims the key this returns 2 and names it; when one does, the key is owned
# and the unreadable file is only named, as a warning (chrislacey89/skills#530: one corrupt
# sidecar.json used to refuse every lookup in every repo). A caller must check
# the status; `$(owners_of …)` inside a pipeline discards it.
#
# The scan walks directories, not "$SIDECAR_ROOT"/*/sidecar.json: a glob never
# matches a path under a directory it cannot search, so a sidecar directory at
# mode 000 or 444 used to drop out of the scan and read as a miss, which
# `backend` answers with `github` (chrislacey89/skills#542). A directory that
# cannot be entered is unread, like a corrupt file, and so is a sidecar.json
# that is present but not a regular file; a directory with no sidecar.json is
# skipped.
owners_of() {
    local key="$1" d f rc hits="" unread=""
    # A root that exists but cannot be listed and entered hides every sidecar
    # in it; only a root that does not exist at all is a miss.
    if [ -e "$SIDECAR_ROOT" ] && ! { [ -d "$SIDECAR_ROOT" ] && [ -r "$SIDECAR_ROOT" ] && [ -x "$SIDECAR_ROOT" ]; }; then
        printf 'sidecar.sh: cannot list %s; refusing to treat it as a miss\n' "$SIDECAR_ROOT" >&2
        return 2
    fi
    for d in "$SIDECAR_ROOT"/*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        f="$d/sidecar.json"
        if [ ! -x "$d" ]; then
            unread="${unread:+$unread$'\n'}$d (cannot enter the directory)"
            continue
        fi
        if [ ! -f "$f" ]; then
            # Present but not a regular file, such as a symlink whose target
            # is gone: as unparseable as a corrupt one, so not a miss.
            if [ -L "$f" ] || [ -e "$f" ]; then
                unread="${unread:+$unread$'\n'}$f (not a readable regular file)"
            fi
            continue
        fi
        rc=0
        jq -e --arg k "$key" '(.keys // []) | index($k) != null' "$f" >/dev/null 2>&1 || rc=$?
        case "$rc" in
            0) hits="${hits:+$hits$'\n'}$(dirname "$f")" ;;
            1) ;;
            *) unread="${unread:+$unread$'\n'}$f (jq exited $rc)" ;;
        esac
    done
    if [ -n "$unread" ]; then
        if [ -z "$hits" ]; then
            printf '%s\n' "$unread" | while IFS= read -r f; do
                printf 'sidecar.sh: cannot read %s; refusing to treat it as a miss\n' "$f" >&2
            done
            return 2
        fi
        printf '%s\n' "$unread" | while IFS= read -r f; do
            printf 'sidecar.sh: warning: cannot read %s; ignored, because a readable sidecar claims %s\n' "$f" "$key" >&2
        done
    fi
    [ -z "$hits" ] || printf '%s\n' "$hits"
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
        owners="$(owners_of "$key")" || exit 1
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
            # An unreadable sidecar.json might claim this alias; skip adding it
            # rather than refuse a resolve that already has its hit.
            other="$(owners_of "$k")" || continue
            other="$(printf '%s\n' "$other" | head -n 1)"
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
    local name="" mode="" write="" itp="" keys key owner gname gemail dir storage top forge_kind forge_write migrate=1 aliases=""
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
                alias_ok "$2" || die_usage "init: --archive-alias must be one directory name: $2"
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
        owner="$(owners_of "$key")" || exit 1
        owner="$(printf '%s\n' "$owner" | head -n 1)"
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

    forge_kind="$(forge_kind_of "$keys")"
    forge_write="$(derive_forge_write "$mode" "$forge_kind")"

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
    local sc="$1" keys="$2" aliases="${3:-}" archive dest names d base e target moved conflict any=0 mbase self tmpl
    archive="$ARCHIVE_ROOT"
    mbase="$(lower "$(basename "$(main_checkout)")")"
    self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
    [ -d "$archive" ] || return 0
    dest="$sc/research"
    mkdir -p "$dest" || refuse "archive: cannot create $dest"
    names="$({ archive_names "$keys"; [ -z "$aliases" ] || printf '%s\n' "$aliases"; } | LC_ALL=C sort -u)"
    [ -n "$names" ] || return 0
    for d in "$archive"/*; do
        [ -d "$d" ] || continue
        [ -L "$d" ] && continue
        base="$(lower "$(basename "$d")")"
        if ! printf '%s\n' "$names" | grep -qxF -- "$base"; then
            if [ "$base" = "$mbase" ]; then
                printf 'sidecar.sh: archive: skipped %s: this checkout has a remote, so a folder named for the checkout is not claimed; if it is this project'"'"'s, run: bash %s migrate-archive --archive-alias %s\n' \
                    "$d" "$self" "$base" >&2
            fi
            continue
        fi
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
                mv "$e" "$target" || refuse "archive: could not move $e into $dest"
            fi
            moved=$((moved + 1))
        done
        # The link is made at a temp name first, so a failed ln leaves the old
        # directory in place; if the final rename fails, the directory is
        # recreated so the old path is never left missing.
        tmpl="$d.sidecar-link.$$"
        ln -s "$dest" "$tmpl" || refuse "archive: could not link $d to $dest"
        rmdir "$d" || { rm -f "$tmpl"; refuse "archive: $d is not empty after the move; left in place"; }
        mv -f "$tmpl" "$d" || { rm -f "$tmpl"; mkdir -p "$d"; refuse "archive: could not link $d to $dest"; }
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
    case "${1:-}" in
        get)
            [ $# -eq 2 ] || die_usage "usage: sidecar.sh config get <dotted.key>"
            sc="$(do_resolve)" || exit 1
            jq -r --arg k "$2" 'getpath($k | split(".")) // empty' "$sc/sidecar.json"
            ;;
        set)
            [ $# -eq 3 ] || die_usage "usage: sidecar.sh config set <mode <owned|guest>|base_ref <branch>>"
            case "$2" in
                mode) config_set_mode "$3" ;;
                base_ref) config_set_base_ref "$3" ;;
                *) die_usage "config set: expected mode or base_ref, got: $2" ;;
            esac
            ;;
        *) die_usage "usage: sidecar.sh config <get <dotted.key>|set <mode <owned|guest>|base_ref <branch>>>" ;;
    esac
}

config_set_mode() {
    local mode="$1" sc kind fw tmp
    case "$mode" in owned|guest) ;; *) die_usage "config set: mode must be owned or guest" ;; esac
    sc="$(do_resolve)" || exit 1
    kind="$(jq -r '.forge.kind // "none"' "$sc/sidecar.json")"
    fw="$(derive_forge_write "$mode" "$kind")"
    tmp="$(mktemp "$sc/.sidecar.json.XXXXXX")" || refuse "config set: cannot write in $sc"
    if jq --arg mode "$mode" --argjson fw "$fw" '.mode = $mode | .forge.write = $fw' < "$sc/sidecar.json" > "$tmp"; then
        mv "$tmp" "$sc/sidecar.json"
    else
        rm -f "$tmp"; refuse "config set: could not update sidecar.json"
    fi
    commit_paths "$sc" "sidecar: set mode $mode" sidecar.json || exit 1
}

config_set_base_ref() {
    local b="$1" sc tmp
    [ -n "$b" ] || die_usage "config set: base_ref needs a branch name"
    case "$b" in origin/*) die_usage "config set: base_ref is the bare branch name (${b#origin/}), not the remote ref $b" ;; esac
    in_repo || refuse "not inside a git repository"
    pgit check-ref-format --branch "$b" >/dev/null 2>&1 || die_usage "config set: not a valid branch name: $b"
    base_ref_of "$b" >/dev/null 2>&1 \
        || refuse "config set: neither origin/$b nor $b resolves in this checkout; fetch it, or check the name"
    sc="$(do_resolve)" || exit 1
    tmp="$(mktemp "$sc/.sidecar.json.XXXXXX")" || refuse "config set: cannot write in $sc"
    if jq --arg b "$b" '.base_ref = $b' < "$sc/sidecar.json" > "$tmp"; then
        mv "$tmp" "$sc/sidecar.json"
    else
        rm -f "$tmp"; refuse "config set: could not update sidecar.json"
    fi
    commit_paths "$sc" "sidecar: set base_ref $b" sidecar.json || exit 1
}

# base_ref_of <name>: the range-endpoint ref for a base branch name, per the
# header; returns 1, printing nothing, when neither form resolves.
# Only a remote-tracking or local branch counts: a tag, or a revision expression
# such as @{-1}, develop~1 or HEAD, is not a base: the name must be a valid
# branch name, which no revision expression is, and HEAD is refused by name.
base_ref_of() {
    [ "$1" != HEAD ] || return 1
    pgit check-ref-format "refs/heads/$1" >/dev/null 2>&1 || return 1
    if pgit rev-parse --verify -q "refs/remotes/origin/$1" >/dev/null 2>&1; then
        printf 'origin/%s\n' "$1"
    elif pgit rev-parse --verify -q "refs/heads/$1" >/dev/null 2>&1; then
        printf 'note: origin/%s does not resolve — measuring against the local branch, which may be stale\n' "$1" >&2
        printf '%s\n' "$1"
    else
        return 1
    fi
}

# The base branch; the three outcomes are in the header.
cmd_base_ref() {
    local want=ref sc errf v name="" candidate ref
    case "$#:${1:-}" in
        0:) ;;
        1:--name) want=name ;;
        *) die_usage "usage: sidecar.sh base-ref [--name]" ;;
    esac
    in_repo || refuse "not inside a git repository"
    command -v jq >/dev/null 2>&1 || refuse "base-ref: jq is required to read the sidecar and is not on PATH; refusing rather than answering the origin/HEAD default"
    errf="$(mktemp)" || refuse "base-ref: cannot create a temp file"
    if sc="$(do_resolve 2>"$errf")"; then
        cat "$errf" >&2; rm -f "$errf"
        v="$(jq -r 'if type != "object" then error("not an object")
                    elif has("base_ref") | not then "absent"
                    elif (.base_ref | type) != "string" then error("base_ref is not a string")
                    else "declared:" + .base_ref end' "$sc/sidecar.json" 2>&1)" \
            || refuse "base-ref: cannot read base_ref from $sc/sidecar.json: $v"
        if [ "$v" != absent ]; then
            name="${v#declared:}"
            [ -n "$name" ] || refuse "base-ref: base_ref in $sc/sidecar.json is empty; set it with: sidecar.sh config set base_ref <branch>"
            ref="$(base_ref_of "$name")" \
                || refuse "base-ref: base_ref is $name in $sc/sidecar.json, and neither origin/$name nor $name resolves"
            if [ "$want" = name ]; then printf '%s\n' "$name"; else printf '%s\n' "$ref"; fi
            return 0
        fi
    elif grep -q 'SIDECAR MISS:' "$errf"; then
        rm -f "$errf"
    else
        cat "$errf" >&2; rm -f "$errf"; exit 1
    fi
    name="$(pgit symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's@^origin/@@')"
    if [ -z "$name" ]; then
        for candidate in main master prod develop trunk; do
            if pgit rev-parse --verify -q "$candidate" >/dev/null 2>&1; then name=$candidate; break; fi
        done
    fi
    [ -n "$name" ] || refuse "base-ref: no base branch found: origin/HEAD is unset and none of main master prod develop trunk resolves; declare one with: sidecar.sh config set base_ref <branch>"
    if [ "$want" = name ]; then
        printf '%s\n' "$name"
    elif ! base_ref_of "$name"; then
        # origin/HEAD named a branch that no longer resolves either way.
        refuse "base-ref: origin/HEAD names $name, and neither origin/$name nor $name resolves; run git remote set-head origin --auto"
    fi
}

cmd_migrate_archive() {
    local aliases="" sc keys
    while [ $# -gt 0 ]; do
        case "$1" in
            --archive-alias)
                [ $# -ge 2 ] || die_usage "--archive-alias needs a value"
                alias_ok "$2" || die_usage "migrate-archive: --archive-alias must be one directory name: $2"
                aliases="${aliases:+$aliases$'\n'}$(lower "$2")"; shift 2 ;;
            *) die_usage "migrate-archive: unknown argument: $1" ;;
        esac
    done
    sc="$(do_resolve)" || exit 1
    keys="$(current_keys)"
    migrate_archive "$sc" "$keys" "$aliases" || exit 1
}

# The directories a reader searches for lessons; the policy is in the header.
cmd_solutions_dirs() {
    local sc="" err itp seen=""
    [ $# -eq 0 ] || die_usage "usage: sidecar.sh solutions-dirs"
    err="$(mktemp)" || refuse "solutions-dirs: cannot create a temp file"
    if sc="$(do_resolve 2>"$err")"; then
        cat "$err" >&2
        mkdir -p "$sc/solutions" || { rm -f "$err"; refuse "solutions-dirs: cannot create $sc/solutions"; }
        printf '%s\n' "$sc/solutions"
        itp="$(jq -r '.solutions.in_tree_path // empty' "$sc/sidecar.json")"
        case "$itp" in ''|none) ;; *) printf '%s\n' "$itp"; seen="$itp" ;; esac
    else
        sc=""
        grep -q 'SIDECAR MISS:' "$err" || cat "$err" >&2
    fi
    rm -f "$err"
    # A /excavate PR commits to docs/solutions whatever in_tree_path says, so an
    # existing docs/solutions is read even when in_tree_path is none; with no
    # sidecar it is the default store and is named whether or not it exists.
    if [ "$seen" != "docs/solutions" ]; then
        if [ -d docs/solutions ] || [ -z "$sc" ]; then printf 'docs/solutions\n'; fi
    fi
}

cmd_path() {
    local sc
    [ $# -eq 1 ] || die_usage "usage: sidecar.sh path <research|solutions>"
    case "$1" in research|solutions) ;; *) die_usage "path: expected research or solutions, got: $1" ;; esac
    sc="$(do_resolve)" || exit 1
    mkdir -p "$sc/$1" || refuse "path: cannot create $sc/$1"
    printf '%s\n' "$sc/$1"
}

# The pre-sidecar archive directory for this checkout, keyed by the same name
# the SIDECAR MISS line suggests. Prints it whether or not a sidecar resolves,
# and does not create it.
cmd_archive_dir() {
    local name
    [ $# -eq 0 ] || die_usage "usage: sidecar.sh archive-dir"
    in_repo || refuse "not inside a git repository"
    name="$(suggest_name)"
    case "$name" in ''|.*|*/*|*[!a-z0-9._-]*) refuse "archive-dir: no usable name for this checkout: [$name]" ;; esac
    printf '%s/%s\n' "$ARCHIVE_ROOT" "$name"
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
    # A link may carry a section anchor (name.md#section); look up the file.
    case "$probe" in *"#"*) [ -e "$probe" ] || probe="${probe%%#*}" ;; esac
    # A relative link inside a lesson is relative to the lesson's own folder, so when
    # --from names an existing file, also try the path beside it.
    if [ ! -e "$probe" ] && [ -f "$from" ]; then
        case "$probe" in /*) ;; *) [ -e "$(dirname "$from")/$probe" ] && probe="$(dirname "$from")/$probe" ;; esac
    fi
    # A bare name may also live in a sibling category folder (<store>/<category>/<name>.md),
    # so look one level up and across, never deeper.
    if [ ! -e "$probe" ] && [ -f "$from" ]; then
        case "$probe" in
            /*|*/*) ;;
            *) local cand first="" hits=""
               for cand in "$(dirname "$(dirname "$from")")"/*/"$probe"; do
                   [ -e "$cand" ] || continue
                   [ -n "$first" ] || first="$cand"
                   hits="${hits:+$hits }$cand"
               done
               if [ -n "$first" ]; then
                   [ "$hits" = "$first" ] || printf 'sidecar.sh: warning: %s is in more than one category folder: %s; using %s\n' "$probe" "$hits" "$first" >&2
                   probe="$first"
               fi ;;
        esac
    fi
    if [ ! -e "$probe" ]; then
        printf 'MISSING: %s (referenced by %s)\n' "$path" "$from" >&2
        exit 1
    fi
    # A hit may be beside the referrer or in a sibling category, not where the
    # caller would guess, so print where it was found and let the caller open that.
    printf '%s/%s\n' "$(cd "$(dirname "$probe")" && pwd -P)" "$(basename "$probe")"
}

cmd_backend() {
    local sc errf item kind
    [ $# -eq 1 ] || die_usage "usage: sidecar.sh backend <prds|slices|stamp>"
    case "$1" in
        prds|slices) item="issues" ;;
        stamp)       item="prs" ;;
        *) die_usage "backend: expected prds, slices, or stamp, got: $1" ;;
    esac
    # Without jq no sidecar.json can be matched, so a guest's sidecar would read
    # as SIDECAR MISS and the answer would be `github`: pack text in a client's
    # PR body. "Could not look" must not share "no sidecar"'s answer.
    command -v jq >/dev/null 2>&1 || refuse "backend: jq is required to read the sidecar and is not on PATH; refusing rather than answering github"
    errf="$(mktemp)" || refuse "backend: cannot create a temp file"
    if ! sc="$(do_resolve 2>"$errf")"; then
        if grep -q 'SIDECAR MISS:' "$errf"; then
            rm -f "$errf"; printf 'github\n'; return 0
        fi
        cat "$errf" >&2; rm -f "$errf"; exit 1
    fi
    cat "$errf" >&2; rm -f "$errf"
    kind="$(jq -r '.forge.kind // "none"' "$sc/sidecar.json")" || refuse "backend: cannot read $sc/sidecar.json"
    if ! jq -e '(.forge.write // []) | type == "array"' "$sc/sidecar.json" >/dev/null 2>&1; then
        refuse "backend: forge.write in $sc/sidecar.json is not an array"
    fi
    if [ "$kind" = "github" ] \
        && jq -e --arg i "$item" '(.forge.write // []) | index($i) != null' "$sc/sidecar.json" >/dev/null; then
        printf 'github\n'
    else
        printf 'sidecar\n'
    fi
}

# branch_slug <branch>: the reversible file name for a branch; the rule is in the header.
branch_slug() {
    local h out=""
    for h in $(printf '%s' "$1" | od -An -v -tx1 | tr ' ' '\n'); do
        [ -n "$h" ] || continue
        case "$h" in
            2d|2e|3[0-9]|5f|6[1-9a-f]|7[0-9a]) out="$out$(printf '%b' "\\x$h")" ;;
            *) out="$out%$(printf '%s' "$h" | tr 'a-f' 'A-F')" ;;
        esac
    done
    printf '%s' "$out"
}

cmd_stamp() {
    local sub="${1:-}" branch sha base="" sc f tmp
    [ $# -gt 0 ] && shift
    case "$sub" in
        write)
            [ $# -ge 2 ] || die_usage "usage: sidecar.sh stamp write <branch> <sha> [--base-ref <ref>]"
            branch="$1"; sha="$2"; shift 2
            while [ $# -gt 0 ]; do
                case "$1" in
                    --base-ref) [ $# -ge 2 ] || die_usage "stamp write: --base-ref needs a value"; base="$2"; shift 2 ;;
                    *) die_usage "stamp write: unknown argument: $1" ;;
                esac
            done
            ;;
        read|clear)
            [ $# -eq 1 ] || die_usage "usage: sidecar.sh stamp $sub <branch>"
            branch="$1"
            ;;
        *) die_usage "usage: sidecar.sh stamp <write|read|clear> <branch> ..." ;;
    esac
    case "$branch" in ''|*$'\n'*) die_usage "stamp $sub: the branch must be one non-empty line" ;; esac
    if [ "$sub" = write ] && ! printf '%s' "$sha" | grep -qxE '[0-9a-f]{40}'; then
        refuse "stamp write refused: the SHA must be 40 lowercase hex characters (git rev-parse HEAD): $sha"
    fi
    sc="$(do_resolve)" || exit 1
    f="reviews/$(branch_slug "$branch").json"
    case "$sub" in
        write)
            mkdir -p "$sc/reviews" || refuse "stamp write: cannot create $sc/reviews"
            tmp="$(mktemp "$sc/reviews/.stamp.XXXXXX")" || refuse "stamp write: cannot write in $sc/reviews"
            if jq -n --arg b "$branch" --arg s "$sha" --arg r "$base" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                '{schema: 1, branch: $b, reviewed_sha: $s, base_ref: $r, at: $at}' > "$tmp"; then
                mv "$tmp" "$sc/$f"
            else
                rm -f "$tmp"; refuse "stamp write: could not write $sc/$f"
            fi
            commit_paths "$sc" "sidecar: stamp $branch at ${sha:0:7}" "$f" || exit 1
            ;;
        read)
            [ -f "$sc/$f" ] || return 0
            sha="$(jq -r --arg b "$branch" 'select(.branch == $b) | .reviewed_sha // empty' "$sc/$f" 2>/dev/null)" || {
                printf 'sidecar.sh: stamp read: %s does not parse; treating it as no stamp\n' "$sc/$f" >&2; return 0; }
            printf '%s' "$sha" | grep -qxE '[0-9a-f]{40}' && printf '%s\n' "$sha"
            return 0
            ;;
        clear)
            [ -f "$sc/$f" ] || return 0
            rm -f "$sc/$f"
            if sgit "$sc" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
                commit_paths "$sc" "sidecar: clear stamp $branch" "$f" || exit 1
            fi
            ;;
    esac
}

WORK_ID_RE='W-[0-9]+'
WORK_COMMENT_RE='^## Comment [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
WORK_FIELDS='["id","kind","state","maturity","parent","blocked_by","decomposed_into","milestone","pr","reviewed_sha","superseded_by","created"]'

# jq definitions shared by every work verb. parse_work reads a whole work file
# (jq -Rs) into {fm, body, tail}: tail is the comment sections, kept as raw
# text so a rewrite never re-renders a comment. render_work is its inverse.
# Lines are split on "\n" rather than located with index(), which jq 1.6
# counts in bytes while slicing counts codepoints.
# shellcheck disable=SC2016  # $cre and $order are jq variables
WORK_JQ='
def trim_end: sub("\n+$"; "");
def fm_value:
  if . == "" then null
  elif startswith("\"") then fromjson
  elif startswith("[") then ltrimstr("[") | rtrimstr("]") | split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))
  else . end;
def parse_work:
  split("\n") as $l
  | if $l[0] != "---" then error("no frontmatter") else . end
  | ([range(1; $l | length) | select($l[.] == "---")] | .[0]) as $close
  | if $close == null then error("unterminated frontmatter") else . end
  | ($l[$close + 1:]) as $rest
  | ([range(0; $rest | length) | select($rest[.] | test($cre))] | .[0] // ($rest | length)) as $c
  | { fm: ($l[1:$close] | map(select(length > 0)
          | (capture("^(?<k>[a-z_]+): ?(?<v>.*)$") // error("bad frontmatter line: \(.)"))
          | {key: .k, value: (.v | fm_value)}) | from_entries),
      body: ($rest[:$c] | join("\n") | trim_end),
      tail: ($rest[$c:] | join("\n") | trim_end) };
def comments:
  .tail | split("\n")
  | reduce .[] as $x ([];
      if ($x | test($cre)) then . + [{at: ($x | ltrimstr("## Comment ")), lines: []}]
      elif length == 0 then .
      else .[-1].lines += [$x] end)
  | map({at, body: (.lines | join("\n") | sub("^\n+"; "") | trim_end)});
def fm_line($k; $v):
  "\($k): " + ($v | if type == "array" then "[" + join(", ") + "]"
                   elif ($k == "milestone" or $k == "pr" or type != "string") then tojson
                   else . end);
def render_work:
  . as $w
  | ($w.fm | to_entries | map(select(.value != null))) as $e
  | ([$order[] as $k | $e[] | select(.key == $k)] + [$e[] | select(.key as $k | $order | index($k) | not)]) as $sorted
  | "---\n" + ($sorted | map(fm_line(.key; .value) + "\n") | join(""))
    + "---\n" + $w.body + "\n"
    + (if $w.tail == "" then "" else "\n" + $w.tail + "\n" end);
'

# work_jq <args...>: jq with the work definitions and their two constants bound.
work_jq() { jq --arg cre "$WORK_COMMENT_RE" --argjson order "$WORK_FIELDS" "$@"; }

is_work_id() { [[ "$1" =~ ^${WORK_ID_RE}$ ]]; }

# work_ids_csv <label> <csv>: validate a comma list of ids that must exist in
# $WORK_DIR; prints the normalized list (comma-separated, no spaces).
work_ids_csv() {
    local label="$1" csv="$2" id out=""
    for id in $(printf '%s' "$csv" | tr ',' '\n'); do
        id="$(printf '%s' "$id" | tr -d ' ')"
        [ -n "$id" ] || continue
        is_work_id "$id" || die_usage "work: $label must be ids like W-3: $id"
        [ -f "$WORK_DIR/$id.md" ] || refuse "work: $label names $id, which does not exist"
        out="${out:+$out,}$id"
    done
    printf '%s' "$out"
}

# work_body <file>: the body file's content, trailing newlines trimmed, or refuse.
work_body() {
    local f="$1" b
    [ -f "$f" ] || refuse "work: no such body file: $f"
    b="$(cat "$f")" || refuse "work: cannot read $f"
    [ -n "$b" ] || refuse "work: the body in $f is empty"
    if printf '%s\n' "$b" | grep -qE "$WORK_COMMENT_RE"; then
        refuse "work: the body in $f contains a '## Comment <timestamp>' line, which only work comment writes"
    fi
    printf '%s' "$b"
}

# work_rewrite <id> <msg> <jq filter> [jq args...]: parse the item, apply the
# filter to the parsed {fm, body, tail}, write it back atomically, and commit.
work_rewrite() {
    local id="$1" msg="$2" filter="$3" f tmp
    shift 3
    f="$WORK_DIR/$id.md"
    tmp="$(mktemp "$WORK_DIR/.work.XXXXXX")" || refuse "work: cannot write in $WORK_DIR"
    if ! work_jq -Rsj "$@" "$WORK_JQ parse_work | $filter | render_work" "$f" > "$tmp"; then
        rm -f "$tmp"; refuse "work: could not update $f"
    fi
    mv "$tmp" "$f" || { rm -f "$tmp"; refuse "work: could not replace $f"; }
    commit_paths "$WORK_SC" "$msg" "work/$id.md" || exit 1
}

# work_existing <id>: refuse unless the id is well-formed and its file exists.
work_existing() {
    is_work_id "$1" || die_usage "work: expected an id like W-3, got: $1"
    [ -f "$WORK_DIR/$1.md" ] || refuse "work: no such work item: $1"
}

cmd_work() {
    local sub="${1:-}"
    [ $# -gt 0 ] && shift
    case "$sub" in
        create|view|edit|set|comment|close|list) ;;
        *) die_usage "usage: sidecar.sh work <create|view|edit|set|comment|close|list> ..." ;;
    esac
    WORK_SC="$(do_resolve)" || exit 1
    WORK_DIR="$WORK_SC/work"
    "work_$sub" "$@"
}

work_create() {
    local kind="" parent="" blocked="" milestone="" maturity="" bf="" body max b n tmp target fm i
    while [ $# -gt 0 ]; do
        case "$1" in
            --kind)       [ $# -ge 2 ] || die_usage "work create: --kind needs a value"; kind="$2"; shift 2 ;;
            --parent)     [ $# -ge 2 ] || die_usage "work create: --parent needs a value"; parent="$2"; shift 2 ;;
            --blocked-by) [ $# -ge 2 ] || die_usage "work create: --blocked-by needs a value"; blocked="$2"; shift 2 ;;
            --milestone)  [ $# -ge 2 ] || die_usage "work create: --milestone needs a value"; milestone="$2"; shift 2 ;;
            --maturity)   [ $# -ge 2 ] || die_usage "work create: --maturity needs a value"; maturity="$2"; shift 2 ;;
            --body-file)  [ $# -ge 2 ] || die_usage "work create: --body-file needs a value"; bf="$2"; shift 2 ;;
            *) die_usage "work create: unknown argument: $1" ;;
        esac
    done
    case "$kind" in prd|slice) ;; *) die_usage "work create: --kind must be prd or slice" ;; esac
    [ -n "$bf" ] || die_usage "work create: --body-file is required"
    case "$milestone" in *$'\n'*) die_usage "work create: --milestone must be one line" ;; esac
    if [ "$kind" = prd ]; then
        [ -z "$parent" ] || die_usage "work create: --parent is for slices"
        maturity="${maturity:-prd}"
        case "$maturity" in "roadmap bet"|research-ready|prd) ;; *) die_usage "work create: --maturity must be roadmap bet, research-ready, or prd" ;; esac
    else
        [ -z "$maturity" ] || die_usage "work create: --maturity is for prds"
    fi
    mkdir -p "$WORK_DIR" || refuse "work create: cannot create $WORK_DIR"
    if [ -n "$parent" ]; then
        is_work_id "$parent" || die_usage "work create: --parent must be an id like W-3: $parent"
        [ -f "$WORK_DIR/$parent.md" ] || refuse "work create: --parent names $parent, which does not exist"
    fi
    blocked="$(work_ids_csv --blocked-by "$blocked")" || exit $?
    body="$(work_body "$bf")" || exit 1
    i=0
    while [ "$i" -lt 50 ]; do
        i=$((i + 1))
        max=0
        for b in "$WORK_DIR"/W-*.md; do
            b="${b##*/W-}"; b="${b%.md}"
            [[ "$b" =~ ^[0-9]+$ ]] || continue
            [ "$((10#$b))" -le "$max" ] || max="$((10#$b))"
        done
        n="W-$((max + 1))"
        fm="$(jq -n --arg id "$n" --arg kind "$kind" --arg m "$maturity" --arg p "$parent" \
                --arg bl "$blocked" --arg ms "$milestone" --arg c "$(date +%Y-%m-%d)" \
            '{id: $id, kind: $kind, state: "open",
              maturity: (if $m == "" then null else $m end),
              parent: (if $p == "" then null else $p end),
              blocked_by: ($bl | split(",") | map(select(length > 0))),
              milestone: (if $ms == "" then null else $ms end),
              created: $c}')" || refuse "work create: could not build the frontmatter"
        tmp="$(mktemp "$WORK_DIR/.work.XXXXXX")" || refuse "work create: cannot write in $WORK_DIR"
        if ! work_jq -nj --argjson fm "$fm" --arg body "$body" "$WORK_JQ {fm: \$fm, body: \$body, tail: \"\"} | render_work" > "$tmp"; then
            rm -f "$tmp"; refuse "work create: could not render $n"
        fi
        target="$WORK_DIR/$n.md"
        # ln fails when the target exists, so of two racing writers exactly one
        # claims a number; the other recomputes max and takes the next.
        if ln "$tmp" "$target" 2>/dev/null; then
            rm -f "$tmp"
            if ! commit_paths "$WORK_SC" "sidecar: work create $n ($kind)" "work/$n.md"; then
                rm -f "$target"; exit 1
            fi
            printf '%s\n' "$n"
            return 0
        fi
        rm -f "$tmp"
    done
    refuse "work create: could not claim an id after 50 attempts"
}

work_view() {
    local id="${1:-}" json=0
    [ $# -ge 1 ] || die_usage "usage: sidecar.sh work view <W-n> [--json]"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in --json) json=1; shift ;; *) die_usage "work view: unknown argument: $1" ;; esac
    done
    work_existing "$id"
    if [ "$json" -eq 0 ]; then cat "$WORK_DIR/$id.md"; return 0; fi
    work_jq -Rs "$WORK_JQ parse_work | .fm + {body, comments: comments}" "$WORK_DIR/$id.md" \
        || refuse "work view: $WORK_DIR/$id.md does not parse"
}

work_edit() {
    local id="${1:-}" bf="" cur new
    [ $# -ge 1 ] || die_usage "usage: sidecar.sh work edit <W-n> --body-file <f>"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --body-file) [ $# -ge 2 ] || die_usage "work edit: --body-file needs a value"; bf="$2"; shift 2 ;;
            *) die_usage "work edit: unknown argument: $1" ;;
        esac
    done
    [ -n "$bf" ] || die_usage "work edit: --body-file is required"
    work_existing "$id"
    new="$(work_body "$bf")" || exit 1
    cur="$(work_jq -Rsr "$WORK_JQ parse_work | .body" "$WORK_DIR/$id.md")" || refuse "work edit: $WORK_DIR/$id.md does not parse"
    # Ticking a checkbox keeps the length; a shorter body means content was dropped.
    if [ "$(printf '%s' "$new" | wc -c)" -lt "$(printf '%s' "$cur" | wc -c)" ]; then
        refuse "work edit refused: the new body is shorter than the one in $id; $id is unchanged"
    fi
    # shellcheck disable=SC2016  # $-names are jq variables
    work_rewrite "$id" "sidecar: work edit $id" '.body = $body' --arg body "$new"
}

work_set() {
    local id="${1:-}" field="${2:-}" value="${3-}" kind
    [ $# -eq 3 ] || die_usage "usage: sidecar.sh work set <W-n> <state|maturity|decomposed_into|pr|reviewed_sha> <value>"
    work_existing "$id"
    case "$value" in *$'\n'*) die_usage "work set: the value must be one line" ;; esac
    kind="$(work_jq -Rsr "$WORK_JQ parse_work | .fm.kind" "$WORK_DIR/$id.md")" || refuse "work set: $WORK_DIR/$id.md does not parse"
    case "$field" in
        state) case "$value" in open|closed) ;; *) die_usage "work set: state must be open or closed" ;; esac ;;
        maturity)
            [ "$kind" = prd ] || refuse "work set: maturity is for prds; $id is a $kind"
            case "$value" in "roadmap bet"|research-ready|prd) ;; *) die_usage "work set: maturity must be roadmap bet, research-ready, or prd" ;; esac ;;
        decomposed_into)
            [ "$kind" = prd ] || refuse "work set: decomposed_into is for prds; $id is a $kind"
            value="$(work_ids_csv decomposed_into "$value")" || exit $? ;;
        pr) [ -n "$value" ] || die_usage "work set: pr needs a value" ;;
        reviewed_sha)
            printf '%s' "$value" | grep -qxE '[0-9a-f]{40}' || refuse "work set refused: reviewed_sha must be 40 lowercase hex characters: $value" ;;
        *) die_usage "work set: field must be state, maturity, decomposed_into, pr, or reviewed_sha" ;;
    esac
    if [ "$field" = decomposed_into ]; then
        # Replaced, never appended to: the reader always sees the latest decomposition.
        # shellcheck disable=SC2016  # $-names are jq variables
        work_rewrite "$id" "sidecar: work set $id $field" '.fm.decomposed_into = ($v | split(",") | map(select(length > 0)))' --arg v "$value"
    else
        # shellcheck disable=SC2016  # $-names are jq variables
        work_rewrite "$id" "sidecar: work set $id $field" '.fm[$k] = $v' --arg k "$field" --arg v "$value"
    fi
}

work_comment() {
    local id="${1:-}" bf="" body
    [ $# -ge 1 ] || die_usage "usage: sidecar.sh work comment <W-n> --body-file <f>"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --body-file) [ $# -ge 2 ] || die_usage "work comment: --body-file needs a value"; bf="$2"; shift 2 ;;
            *) die_usage "work comment: unknown argument: $1" ;;
        esac
    done
    [ -n "$bf" ] || die_usage "work comment: --body-file is required"
    work_existing "$id"
    body="$(work_body "$bf")" || exit 1
    # shellcheck disable=SC2016  # $-names are jq variables
    work_rewrite "$id" "sidecar: work comment $id" \
        '.tail = ((if .tail == "" then "" else .tail + "\n\n" end) + "## Comment \($at)\n\n\($c)")' \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg c "$body"
}

work_close() {
    local id="${1:-}" sup=""
    [ $# -ge 1 ] || die_usage "usage: sidecar.sh work close <W-n> [--superseded-by W-m]"
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --superseded-by) [ $# -ge 2 ] || die_usage "work close: --superseded-by needs a value"; sup="$2"; shift 2 ;;
            *) die_usage "work close: unknown argument: $1" ;;
        esac
    done
    work_existing "$id"
    if [ -n "$sup" ]; then
        work_existing "$sup"
        [ "$sup" != "$id" ] || die_usage "work close: an item cannot supersede itself"
    fi
    # shellcheck disable=SC2016  # $-names are jq variables
    work_rewrite "$id" "sidecar: work close $id" \
        '.fm.state = "closed" | if $s == "" then . else .fm.superseded_by = $s end' --arg s "$sup"
}

work_list() {
    local kind="" parent="" unblocked=0 state=open f all one
    while [ $# -gt 0 ]; do
        case "$1" in
            --kind)   [ $# -ge 2 ] || die_usage "work list: --kind needs a value"; kind="$2"; shift 2 ;;
            --parent) [ $# -ge 2 ] || die_usage "work list: --parent needs a value"; parent="$2"; shift 2 ;;
            --state)  [ $# -ge 2 ] || die_usage "work list: --state needs a value"; state="$2"; shift 2 ;;
            --unblocked) unblocked=1; shift ;;
            *) die_usage "work list: unknown argument: $1" ;;
        esac
    done
    case "$kind" in ''|prd|slice) ;; *) die_usage "work list: --kind must be prd or slice" ;; esac
    case "$state" in open|closed|all) ;; *) die_usage "work list: --state must be open, closed, or all" ;; esac
    [ -z "$parent" ] || is_work_id "$parent" || die_usage "work list: --parent must be an id like W-3: $parent"
    [ -d "$WORK_DIR" ] || return 0
    # A parse failure is the assignment's exit status, never a word in the
    # output: an item's own frontmatter (a milestone, a pr URL) can say anything.
    all=""
    for f in "$WORK_DIR"/W-*.md; do
        [ -f "$f" ] || continue
        one="$(work_jq -Rsc "$WORK_JQ parse_work | .fm" "$f")" || { printf 'sidecar.sh: work list: %s does not parse\n' "$f" >&2; exit 1; }
        all="$all$one"$'\n'
    done
    # An --unblocked item is open and every blocked_by id is closed; an id
    # missing from the store counts as open, so a typo never unblocks.
    printf '%s\n' "$all" | jq -rs --arg k "$kind" --arg p "$parent" --arg s "$state" --argjson u "$unblocked" '
        map(select(. != null)) as $items
        | ($items | map({key: .id, value: .state}) | from_entries) as $st
        | $items
        | map(select(($k == "" or .kind == $k)
                 and ($p == "" or .parent == $p)
                 and (if $u == 1 then .state == "open" and ((.blocked_by // []) | all(. as $b | $st[$b] == "closed"))
                      elif $s == "all" then true else .state == $s end)))
        | sort_by(.id | ltrimstr("W-") | tonumber)
        | .[].id'
}

verb="${1:-}"
[ $# -gt 0 ] && shift
case "$verb" in
    resolve) [ $# -eq 0 ] || die_usage "usage: sidecar.sh resolve"; do_resolve || exit 1 ;;
    init)    cmd_init "$@" ;;
    config)  cmd_config "$@" ;;
    base-ref) cmd_base_ref "$@" ;;
    path)    cmd_path "$@" ;;
    solutions-dirs) cmd_solutions_dirs "$@" ;;
    migrate-archive) cmd_migrate_archive "$@" ;;
    archive-dir) cmd_archive_dir "$@" ;;
    commit)  cmd_commit "$@" ;;
    require) cmd_require "$@" ;;
    backend) cmd_backend "$@" ;;
    stamp)   cmd_stamp "$@" ;;
    work)    cmd_work "$@" ;;
    *) die_usage "usage: sidecar.sh <resolve|init|config get|config set|base-ref|path|solutions-dirs|migrate-archive|archive-dir|commit|require|backend|stamp|work> ..." ;;
esac
