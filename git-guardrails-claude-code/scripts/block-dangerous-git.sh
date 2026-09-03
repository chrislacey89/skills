#!/bin/bash
# block-dangerous-git.sh — PreToolUse hook that refuses destructive git commands.
#
# Reads a Bash tool call as JSON on stdin. Exits 2 with a message on stderr to
# block; exits 0 to allow. Anything that is not recognizably a dangerous git
# invocation is allowed, including malformed input — this runs on every single
# Bash call, so failing loudly on surprise input would break the session rather
# than the command.
#
# This parses the command into arguments instead of searching it for substrings.
# The substring version leaked seven ways (#227): it could not see flag order
# (`push origin main -f`), flag bundling (`clean -df`), long-form aliases
# (`branch --delete --force`), or the `--` separator (`checkout -- .`), and it
# over-matched every path beginning with a dot, blocking ordinary commands like
# `git checkout .github/workflows/ci.yml`. Each leak was individually patchable
# and the class was not, which is why the matcher changed shape.
#
# scripts/test-git-guardrails.sh pins both directions against the skill's
# documented lists. Change a rule here and that suite is what tells you whether
# the documentation is still true.

set -f  # No globbing: the command is data to inspect, never a pattern to expand.

INPUT=$(cat)

# jq is a hard dependency: without it the command cannot be extracted, and a
# guard that cannot read its input must not report "nothing dangerous here".
#
# The test is whether the extraction SUCCEEDED, not whether a jq binary exists.
# `command -v jq` answers the wrong question — a jq that is present but broken
# passes it and then fails on the next line, which is how a force push once
# exited 0 here with empty stderr.
#
# Refusing only git-looking input keeps the blast radius at the commands this
# hook is responsible for, instead of halting every Bash call in the session.
if ! COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
    case "$INPUT" in
        *git*)
            echo "BLOCKED: the git guardrail hook could not run 'jq', so this git command cannot be inspected. Install or repair jq to restore the guard." >&2
            exit 2
            ;;
    esac
    exit 0
fi

[ -n "$COMMAND" ] || exit 0

REASON=""

# has <haystack> <needle> — membership test over a space-delimited, space-padded
# list. Used instead of arrays so the lists can cross function boundaries in the
# bash 3.2 that ships as /bin/bash on macOS.
has() {
    case "$1" in
        *" $2 "*) return 0 ;;
    esac
    return 1
}

# has_force_refspec <operands> — true when any operand is a refspec git will
# treat as a force update. A leading `+` is git's other spelling of --force, and
# it arrives as an operand, so the flag check alone cannot see it.
has_force_refspec() {
    local word
    for word in $1; do
        case "$word" in
            +*) return 0 ;;
        esac
    done
    return 1
}

# pathspec_is_everything <operands> — true when the operands name the whole
# working tree. Recognized by reduction rather than by listing spellings, since
# enumerating spellings is how the substring matcher this replaced kept leaking.
# Each operand is walked component by component: `.` and an empty component
# are nothing, `..` steps back out, and a trailing glob (`*`, `**`) is dropped
# because the shell expands it into every entry of the directory. An operand
# that walks back to the root — `.`, `./`, `./.`, `*`, `./*`, `sub/..` — names
# everything. Git's short pathspec magic is peeled first: `:/` anchors at the
# root, a bare `:` is the empty pathspec, and an exclusion (`:!`, `:^`) with no
# positive operand beside it means "everything but". The long form, `:(top)`
# and friends, never arrives here: parentheses are segment boundaries in the
# normalizer, so it reaches this function as a bare `:` and is refused — the
# harmless direction for a spelling nobody types by accident. A path that
# merely begins with a dot (`.gitignore`), ends in a glob under a directory
# (`src/*.ts`), or leaves the repository (`../x`, which git rejects) reduces to
# itself and is left alone.
pathspec_is_everything() {
    local word candidate rest comp depth outside positive=0 exclusion=0
    for word in $1; do
        candidate=$word
        case "$candidate" in
            :*)
                candidate=${candidate#:}
                while :; do
                    case "$candidate" in
                        /*)  candidate=${candidate#/} ;;
                        !*)  exclusion=1; candidate=${candidate#!} ;;
                        ^*)  exclusion=1; candidate=${candidate#^} ;;
                        *)   break ;;
                    esac
                done
                case "$word" in
                    :!*|:^*|:/!*|:/^*) continue ;;
                esac
                candidate=${candidate#:}
                ;;
        esac
        positive=1

        # Verified against git: a glob followed by a slash matches nothing.
        case "$candidate" in
            \*/|\*\*/|*/\*/|*/\*\*/) continue ;;
        esac

        depth=0
        outside=0
        rest=$candidate
        while [ -n "$rest" ]; do
            comp=${rest%%/*}
            if [ "$comp" = "$rest" ]; then rest=""; else rest=${rest#*/}; fi
            case "$comp" in
                ''|.) ;;
                \*|\*\*)
                    # A glob names everything only in last position; `*/x`
                    # is partial.
                    if [ -n "$rest" ]; then depth=$((depth + 1)); fi
                    ;;
                ..)
                    if [ "$depth" -gt 0 ]; then depth=$((depth - 1)); else outside=1; fi
                    ;;
                *)
                    depth=$((depth + 1))
                    ;;
            esac
        done
        if [ "$depth" -eq 0 ] && [ "$outside" -eq 0 ]; then
            return 0
        fi
    done
    if [ "$exclusion" -eq 1 ] && [ "$positive" -eq 0 ]; then
        return 0
    fi
    return 1
}

# inspect_git <args-after-the-git-token...>
# Returns 1 and sets REASON when the invocation is destructive.
inspect_git() {
    local subcommand=""
    local flags=" "
    local operands=" "
    local ddash=0
    local tok body i ch

    # Step past git's own global options to reach the subcommand, so
    # `git -C /path push -f` is still recognized as a push.
    while [ $# -gt 0 ]; do
        case "$1" in
            -C|-c|--git-dir|--work-tree|--namespace|--super-prefix)
                # These take a separate value argument.
                shift
                if [ $# -gt 0 ]; then shift; fi
                ;;
            --exec-path|--html-path|--man-path|--info-path|--version)
                # Verified against git: the bare form prints a path or the
                # version and exits without running whatever follows.
                # `--exec-path=<path>` is different and falls through below.
                return 0
                ;;
            -*)
                shift
                ;;
            *)
                subcommand=$1
                shift
                break
                ;;
        esac
    done

    [ -n "$subcommand" ] || return 0

    # Split the rest into flags and operands. Everything after `--` is a
    # pathspec by definition, which is what makes `checkout -- .` visible.
    while [ $# -gt 0 ]; do
        tok=$1
        shift

        if [ "$ddash" -eq 0 ] && [ "$tok" = "--" ]; then
            ddash=1
            continue
        fi

        if [ "$ddash" -eq 0 ]; then
            case "$tok" in
                --*)
                    # `--force-with-lease=origin/main` is still --force-with-lease.
                    flags="$flags${tok%%=*} "
                    continue
                    ;;
                -?*)
                    # Unbundle short flags: -df becomes -d and -f.
                    body=${tok#-}
                    i=0
                    while [ "$i" -lt "${#body}" ]; do
                        ch=${body:$i:1}
                        flags="$flags-$ch "
                        i=$((i + 1))
                    done
                    continue
                    ;;
            esac
        fi

        operands="$operands$tok "
    done

    case "$subcommand" in
        push)
            # --force-with-lease is the safer force push, but it still rewrites
            # published history, so it is blocked alongside --force.
            if has "$flags" -f || has "$flags" --force || has "$flags" --force-with-lease; then
                REASON="force push — rewrites published history"
                return 1
            fi
            # Verified against git: --mirror force-updates every ref on the
            # remote and deletes the ones that are gone locally.
            if has "$flags" --mirror; then
                REASON="mirror push — force-updates every remote ref"
                return 1
            fi
            # `git push origin +main` is a force push with no force flag.
            if has_force_refspec "$operands"; then
                REASON="force push via + refspec — rewrites published history"
                return 1
            fi
            ;;
        reset)
            # --soft, --mixed, and --keep all leave the working tree intact.
            if has "$flags" --hard; then
                REASON="hard reset — discards uncommitted work"
                return 1
            fi
            ;;
        clean)
            # Verified against git: a dry-run flag wins over --force and the
            # files survive, so that combination is genuinely non-destructive.
            if has "$flags" -n || has "$flags" --dry-run; then
                return 0
            fi
            if has "$flags" -f || has "$flags" --force; then
                REASON="forced clean — deletes untracked files"
                return 1
            fi
            ;;
        branch)
            # Verified against git: -D, --delete --force, and -f -d are three
            # spellings of the same force-delete, in any flag order.
            if has "$flags" -D; then
                REASON="force branch delete — discards unmerged commits"
                return 1
            fi
            if has "$flags" -d || has "$flags" --delete; then
                if has "$flags" -f || has "$flags" --force; then
                    REASON="force branch delete — discards unmerged commits"
                    return 1
                fi
            fi
            ;;
        checkout|restore)
            # Patch mode prompts per hunk before discarding anything, so the
            # operator is already being asked.
            if has "$flags" -p || has "$flags" --patch; then
                return 0
            fi
            # `git restore --staged .` unstages; it does not touch the working
            # tree. Only `--worktree` alongside it reaches the files. -S and -W
            # are git's short spellings of the same two flags.
            if ! has "$flags" --worktree && ! has "$flags" -W; then
                if has "$flags" --staged || has "$flags" -S || has "$flags" --cached; then
                    return 0
                fi
            fi
            # A pathspec naming the whole tree discards every working-tree
            # change at once. A path that merely starts with a dot is an
            # ordinary file and is left alone — that over-match is what made
            # the old matcher block `git checkout .github/workflows/ci.yml`.
            if pathspec_is_everything "$operands"; then
                REASON="discards all working-tree changes"
                return 1
            fi
            ;;
    esac

    return 0
}

# Quotes and backslashes are removed rather than honored, so a wrapped
# invocation like `bash -c "git push -f"` still tokenizes into inspectable
# words. Removed, not replaced with a space: the shell joins `g''it` and
# `\git` back into `git`, and a separator inserted there is what let those
# spellings walk past an earlier draft. A backslash-newline is a continuation,
# so it becomes a space before the backslashes go. The tradeoff is deliberate
# and fails closed: it also blocks a `git push --force` that only appears as
# search text, which is the harmless direction to be wrong in.
normalized=$COMMAND
normalized=${normalized//\\$'\n'/ }
normalized=${normalized//\\/}
normalized=${normalized//\"/}
normalized=${normalized//\'/}

# Shell control operators become segment boundaries, so `git status && rm -f x`
# is not read as one invocation with an -f flag. Two-character operators are
# replaced before their one-character prefixes.
normalized=${normalized//&&/$'\n'}
normalized=${normalized//||/$'\n'}
normalized=${normalized//\$(/$'\n'}
normalized=${normalized//&/$'\n'}
normalized=${normalized//|/$'\n'}
normalized=${normalized//;/$'\n'}
normalized=${normalized//\`/$'\n'}
normalized=${normalized//(/$'\n'}
normalized=${normalized//)/$'\n'}

while IFS= read -r segment; do
    [ -n "$segment" ] || continue

    tokens=()
    for word in $segment; do
        tokens+=("$word")
    done

    count=${#tokens[@]}
    index=0
    while [ "$index" -lt "$count" ]; do
        # A git token is inspected wherever it appears, not only in first
        # position, so `sudo git push -f` and `xargs git push -f` are covered.
        case "${tokens[$index]}" in
            git|*/git)
                REASON=""
                if ! inspect_git "${tokens[@]:$((index + 1))}"; then
                    echo "BLOCKED: '$COMMAND' is a destructive git command ($REASON). The user has prevented you from doing this." >&2
                    exit 2
                fi
                ;;
        esac
        index=$((index + 1))
    done
done <<EOF
$normalized
EOF

exit 0
