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
# are nothing, `..` steps back out, and a trailing wildcard component is
# dropped — `*` because the shell expands it into every entry of the
# directory, and `?*` or `[a-z]*` because git's own matching lets a star reach
# every tracked file just the same. That drops `*.md` and `*.txt` too; the
# guard cannot know which names a pattern reaches, so a starred pattern at the
# root is refused (the harmless direction) and pinned in the suite as an
# accepted over-block. An
# operand that walks back to the root — `.`, `./`, `./.`, `*`, `./*`,
# `sub/..` — names everything. Git's short pathspec magic is peeled first: `:/` anchors at the
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
                *\**)
                    # A star names everything only in last position; `*/x`
                    # is partial. `?` and `[...]` alone cannot reach every
                    # path — only a star crosses directories — so they are
                    # ordinary components.
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

# --- gh pr merge: the review-currency refusal --------------------------------
#
# /pre-merge Phase 4 stamps the SHA it reviewed into the PR body; /closeout
# Step 2 reads that stamp back and compares it to the PR's current head before
# merging. The read is correct and it is skippable: a merge typed by hand, or
# issued by an AFK loop, never passes through /closeout, and that unattended
# case is exactly where nobody notices the reviewed diff is not the merged
# diff. This makes the read unskippable at the one command that performs the
# merge (#327, Lock 2).
#
# The sed expression below is byte-identical to /closeout's by contract, not by
# intent: scripts/test-review-currency-marker.sh extracts it from this file and
# from closeout/SKILL.md and requires the two to be equal, so a change to
# either one that is not made to the other fails CI.
#
# THE DIRECTION OF ERROR IS DIFFERENT HERE THAN FOR git, and the asymmetry is
# the whole design. The git rules above fail closed: quotes are stripped, a
# `git` token is inspected wherever it appears, and a force push written as
# search text is refused, because a blocked grep costs one rephrase and a
# missed force push costs history. Neither half of that reasoning transfers.
# The words `gh pr merge` appear in ordinary prose, in this pack's own skills,
# in a commit message, and in every grep for them — and a miss here is caught
# a second time by /closeout Step 2, which performs the same read. So this
# check fails OPEN at every point it cannot be certain, and refuses only when
# it has resolved a specific PR and read two well-formed, unequal OIDs.

STALE_STAMP_OPT_OUT=ALLOW_STALE_STAMP_MERGE

# gh_invocation_index — index of the `gh` token in $tokens when this segment
# INVOKES gh, or empty when gh merely appears as an argument or as text.
#
# Command position, not any position. `echo gh pr merge`, `# gh pr merge`, and
# `grep -rn 'gh pr merge' .` all mention the words without running them, and
# this hook runs before every Bash call in every repo it is installed into. An
# earlier draft matched the words anywhere in the command and refused all three
# (#332); a hook that refuses `echo` is a hook that gets uninstalled.
#
# Leading environment assignments and the wrappers below keep the following
# word in command position. The list is short and every entry is probed in
# scripts/test-git-guardrails.sh rather than trusted from memory; a wrapper it
# does not know produces a miss, which is the safe direction.
#
# `bash -c`, `sh -c`, and `eval` are in the list because the quote stripping
# above has already flattened their argument into ordinary tokens by the time
# this runs — the same property that lets the git rules see into
# `bash -c "git push -f"`. An independent probe walked all three of them, plus
# `xargs -I{} bash -c '…'`, past a draft that had only the process wrappers.
gh_invocation_index() {
    GH_INDEX=""
    local i=0 tok
    while [ "$i" -lt "${#tokens[@]}" ]; do
        tok=${tokens[$i]}
        case "$tok" in
            gh|*/gh)
                GH_INDEX=$i
                return 0
                ;;
            [A-Za-z_]*=*)            ;;  # VAR=value prefix
            sudo|doas|env|command|exec|nohup|time|xargs) ;;
            bash|sh|zsh|dash|eval)                        ;;
            if|then|elif|else|do|while|until|!|\{)       ;;
            -*)                      ;;  # a wrapper's own flags
            *) return 1 ;;
        esac
        i=$((i + 1))
    done
    return 1
}

# heredoc_delimiter — the delimiter word when this segment opens a heredoc, so
# the lines that follow can be treated as data. `<<EOF`, `<< EOF`, `<<-EOF`
# and `<<'EOF'` all arrive here as one shape, because the normalizer has
# already removed the quotes.
#
# Tracked for the gh check only. Applying it to the git rules above would
# narrow them, and their suite pins the current reach — including the
# deliberate over-block on quoted search text.
heredoc_delimiter() {
    local i=0 tok
    while [ "$i" -lt "${#tokens[@]}" ]; do
        tok=${tokens[$i]}
        case "$tok" in
            "<<"|"<<-")
                if [ $((i + 1)) -lt "${#tokens[@]}" ]; then
                    printf '%s' "${tokens[$((i + 1))]}"
                    return 0
                fi
                ;;
            "<<"*)
                tok=${tok#<<}
                tok=${tok#-}
                if [ -n "$tok" ]; then
                    printf '%s' "$tok"
                    return 0
                fi
                ;;
        esac
        i=$((i + 1))
    done
    return 1
}

# gh_merge_target — resolve which PR `gh pr merge` would act on, from the
# tokens after `merge`. Sets GH_SELECTOR and GH_REPO, and returns 1 when the
# target cannot be determined without guessing.
#
# Two facts resolve this without re-authoring gh's flag table, which would be
# a paraphrase of another tool's option list and a permanent drift liability
# this repo would then own (CLAUDE.md § "Commands a skill documents", rule (a)):
# `gh pr merge` takes at most one positional argument, and a flag's value
# always follows the flag it belongs to. So an operand that appears BEFORE any
# flag cannot be a value, and is the positional:
#
#   no operands                        -> the PR for the current branch
#   one operand, before any flag       -> that operand IS the positional
#   one operand, after some flag       -> unresolvable; the command runs
#   anything else                      -> unresolvable; the command runs
#
# An earlier draft accepted an all-digits operand anywhere on the grounds that
# no gh flag takes a number. That was a claim about gh's option list made
# without reading it, and it is false: an independent probe read
# `gh pr merge --help` and found five value-taking flags, so
# `gh pr merge --subject 4821` was resolving to PR 4821 while the merge it
# would permit targets the current branch's PR. Looking up the wrong pull
# request is worse than not looking one up, because it reaches a confident
# verdict about a PR nobody asked about — so the rule above is the sound one,
# and `gh pr merge --squash 4821` is a documented miss rather than a guess.
#
# A `#` token starts a shell comment. Everything after it is prose, not
# operands — without this, `gh pr merge # ship it` counted three operands,
# fell through to unresolvable, and let the barest form of the command through.
#
# `-R` / `--repo` is read rather than dropped, and forwarded to the lookup.
# Dropping it was a real defect in the first version of this check: it made
# `gh pr merge 123 -R other/repo` refuse on PR 123 of the *current* repo.
gh_merge_target() {
    GH_SELECTOR=""
    GH_REPO=""
    local tok next_is_repo=0 other_flags=0 operand_count=0 first_operand=""

    while [ $# -gt 0 ]; do
        tok=$1
        shift

        if [ "$next_is_repo" -eq 1 ]; then
            GH_REPO=$tok
            next_is_repo=0
            continue
        fi

        case "$tok" in
            \#*)       break ;;
            --repo=*)  GH_REPO=${tok#--repo=} ; continue ;;
            --repo|-R) next_is_repo=1         ; continue ;;
            -R?*)      GH_REPO=${tok#-R}      ; continue ;;
            -*)        other_flags=1          ; continue ;;
        esac

        operand_count=$((operand_count + 1))
        if [ "$operand_count" -eq 1 ] && [ "$other_flags" -eq 0 ]; then
            first_operand=$tok
        fi
    done

    [ "$operand_count" -le 1 ] || return 1
    [ "$operand_count" -eq 0 ] && return 0
    [ -n "$first_operand" ]    || return 1
    GH_SELECTOR=$first_operand
    return 0
}

# check_gh_merge — the refusal itself. Returns 1 with the message on stderr
# already printed by the caller's contract: it fills GH_BLOCK_MSG instead of
# writing, so the caller owns the one exit path.
check_gh_merge() {
    local i=$GH_INDEX json head_oid reviewed_sha ahead shortstat delta
    local -a view_args

    # `gh pr merge` exactly — gh's own global options are only --help and
    # --version, so nothing legitimately sits between `gh` and `pr`.
    [ "$((i + 2))" -lt "${#tokens[@]}" ] || return 0
    [ "${tokens[$((i + 1))]}" = "pr" ]    || return 0
    [ "${tokens[$((i + 2))]}" = "merge" ] || return 0

    # The opt-out, in both spellings that can actually reach this process: an
    # inline assignment in the command being inspected, and an exported
    # variable in the hook's own environment (a settings.json `env` entry).
    # The refusal message names the inline form because that is the one a
    # reader can act on immediately.
    local t
    for t in "${tokens[@]}"; do
        case "$t" in
            "$STALE_STAMP_OPT_OUT"=*) return 0 ;;
        esac
    done
    [ -z "${ALLOW_STALE_STAMP_MERGE:-}" ] || return 0

    command -v gh >/dev/null 2>&1 || return 0

    gh_merge_target "${tokens[@]:$((i + 3))}" || return 0

    view_args=(pr view)
    [ -z "$GH_SELECTOR" ] || view_args+=("$GH_SELECTOR")
    [ -z "$GH_REPO" ]     || view_args+=(--repo "$GH_REPO")
    view_args+=(--json "body,headRefOid")

    json=$(gh "${view_args[@]}" 2>/dev/null) || return 0
    [ -n "$json" ] || return 0

    head_oid=$(printf '%s' "$json" | jq -r '.headRefOid // empty' 2>/dev/null)
    reviewed_sha=$(printf '%s' "$json" | jq -r '.body // empty' 2>/dev/null | sed -n 's/.*<!-- reviewed-at: \([0-9a-f]\{40\}\) -->.*/\1/p' | tail -1)

    # An absent stamp is not evidence of an unreviewed diff — a hand-authored
    # PR, an external contribution, a PR that predates the stamp, and a
    # malformed marker the expression rejects all land here. /closeout treats
    # this identically, and refusing on every unstamped PR is the alarm fatigue
    # that gets a gate defeated on purpose.
    [ -n "$reviewed_sha" ] || return 0
    [ -n "$head_oid" ]     || return 0
    [ "$reviewed_sha" != "$head_oid" ] || return 0

    if git cat-file -e "$reviewed_sha^{commit}" 2>/dev/null \
       && git cat-file -e "$head_oid^{commit}" 2>/dev/null; then
        ahead=$(git rev-list --count "$reviewed_sha..$head_oid" 2>/dev/null)
        shortstat=$(git diff --shortstat "$reviewed_sha..$head_oid" 2>/dev/null)
        delta="${ahead:-an unknown number of} commit(s) past the stamp;${shortstat}"
    else
        # /closeout says this outright and it bears repeating: an unmeasurable
        # delta is a stronger divergence signal than a measurable one, not a
        # weaker one. The reviewed commit was rewritten away, was never
        # fetched here, or lives in another repository.
        delta="not measurable in this checkout — the reviewed commit is not present (force-pushed away, never fetched, or in another repo)"
    fi

    GH_BLOCK_MSG="BLOCKED: '$COMMAND' would merge a PR whose head has moved past the commit /pre-merge reviewed.
  reviewed-at: $reviewed_sha
  PR head:     $head_oid
  delta:       $delta
Re-review the delta with /pre-merge, which re-stamps at the new head — or, to accept the diff as it stands, run the merge again with $STALE_STAMP_OPT_OUT=1 in front of it."
    return 1
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

heredoc_delim=""

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

    # gh is inspected only where it is being INVOKED, and never inside a
    # heredoc body. Both narrowings are deliberate and neither applies to the
    # git rules above — see the asymmetry note above check_gh_merge.
    if [ -n "$heredoc_delim" ]; then
        if [ "$count" -eq 1 ] && [ "${tokens[0]}" = "$heredoc_delim" ]; then
            heredoc_delim=""
        fi
    else
        if gh_invocation_index; then
            GH_BLOCK_MSG=""
            if ! check_gh_merge; then
                printf '%s\n' "$GH_BLOCK_MSG" >&2
                exit 2
            fi
        fi
        heredoc_delim=$(heredoc_delimiter)
    fi
done <<EOF
$normalized
EOF

exit 0
