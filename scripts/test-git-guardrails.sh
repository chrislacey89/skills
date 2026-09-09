#!/usr/bin/env bash
# test-git-guardrails.sh — contract test for the git guardrail hook script.
#
# /git-guardrails-claude-code ships block-dangerous-git.sh as a PreToolUse hook:
# it reads a Bash tool call as JSON on stdin and exits 2 to block it. The skill's
# "What Gets Blocked" list is what a user reads when deciding whether to install
# the guard at all, which makes a wrong entry there worse than no entry.
#
# #227 is the incident. That list asserted `git push -f` was blocked. The matcher
# was a substring search for the literal `push --force`, which the short form
# does not contain, so the most commonly typed form of the most destructive
# command passed straight through. The skill's own Verify block tested only
# `--force` and a plain push, so the documented self-check could not surface it
# either. The gap survived because nothing executed the claim.
#
# A second /pre-merge round on PR #226 found four more unguarded forms, and
# writing this suite found two the correction comment had not: `git restore -- .`
# and `git branch -f -d`. Seven leaks in one substring list is the argument
# against patching it — the root cause is that substring matching cannot see
# flag order, flag bundling, long-form aliases, or the `--` separator, and it
# over-matches on any path beginning with a dot.
#
# So this suite does not restate the blocked list. It EXTRACTS both lists from
# the skill and runs every entry through the real script. The doc is the
# contract, and CI is what makes it true — the standing response in
# CLAUDE.md § "Commands a skill documents" rule (b), and the same shape as
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md.
#
# Both directions are asserted, deliberately. Pinning only the true positives
# would lock in the false positives the substring matcher also had: it blocked
# `git checkout .github/workflows/ci.yml` and `git restore .gitignore`, both
# legitimate. A guard that cries wolf on ordinary commands is a guard that gets
# uninstalled, so "stays allowed" is a real half of the contract, not a courtesy.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
skill="$repo_root/git-guardrails-claude-code/SKILL.md"
script="$repo_root/git-guardrails-claude-code/scripts/block-dangerous-git.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

fatal() {
    printf 'FATAL: %s\n' "$1" >&2
    printf '       The contract moved or its shape changed; update this suite with it.\n' >&2
    exit 2
}

[[ -f "$skill" ]]  || fatal "no SKILL.md at $skill"
[[ -f "$script" ]] || fatal "no guard script at $script"

# run_guard <command> — feed a command through the real hook exactly the way
# Claude Code does, and echo the exit status. Nothing is stubbed: this is the
# shipped script, reading the shipped JSON envelope.
#
# The command is injected with jq rather than string-concatenated into the JSON,
# so a test case containing a quote or a backslash stays a faithful test case
# instead of producing malformed JSON that the guard skips for the wrong reason.
run_guard() {
    local cmd="$1" payload
    payload="$(jq -nc --arg c "$cmd" '{tool_input: {command: $c}}')"
    printf '%s' "$payload" | bash "$script" >/dev/null 2>&1
    printf '%s' "$?"
}

# assert_eq <expected> <actual> <label> — plain value comparison, for the checks
# that are not "run this command through the guard".
assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %q\n       got:      %q\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

# assert_verdict <expected-exit> <command> <label>
assert_verdict() {
    local expected="$1" cmd="$2" label="$3" actual
    actual="$(run_guard "$cmd")"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %-46s %s\n' "$cmd" "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %-46s %s\n       expected exit %s, got exit %s\n' \
            "$cmd" "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

BLOCKED=2
ALLOWED=0

# --- Pull both lists out of the skill itself, never restate them -------------

# Every backticked `git ...` span in the bullet list under one "## " heading.
#
# Three rules, each learned the hard way. The section ends at the next heading
# of ANY level, so a "###" subsection's illustrative examples are not mistaken
# for contract entries. Only list items are read, because the prose around the
# list discusses commands too — the sentence explaining that `git push -f` was
# wrongly documented as blocked would otherwise be extracted as a claim that it
# is allowed. And a list item CONTINUES across wrapped lines until a blank line
# or the next bullet, which is the rule that stops a routine markdown re-wrap
# from silently deleting entries from the contract.
#
# That third rule is not hypothetical. Before it existed, wrapping the five-way
# `git clean` bullet onto a second line dropped `git clean -df` and
# `git clean -d -f` from the extraction, and the suite reported
# "65 passed, 0 failed" and exit 0 while asserting nothing about either. The
# count assertion below is the second line of defense against the same class:
# extraction that silently returns less than the document contains.
#
# The headings are named here because they are the contract's public shape. If
# either is renamed the extraction returns nothing and the guard below fires,
# rather than silently asserting over an empty list.
# shellcheck disable=SC2016  # backticks here are literal markdown, not command substitution
section_commands() {
    local heading="$1" word="${2:-git}"
    awk -v want="$heading" '
        $0 == want { inside = 1; in_item = 0; next }
        /^#/ { inside = 0; in_item = 0 }
        !inside { next }
        /^[[:space:]]*$/ { in_item = 0; next }
        /^[-*+] / { in_item = 1; print; next }
        in_item { print }
    ' "$skill" | grep -o "\`$word [^\`]*\`" | sed 's/^`//; s/`$//'
}

# `while read` rather than `mapfile`: mapfile is a bash 4 builtin, and /bin/bash
# on macOS is 3.2. Using it made this the only suite in scripts/ that could not
# run on a stock Mac — it died with "unbound variable" having run no assertions.
documented_blocked=()
while IFS= read -r extracted_line; do
    [ -n "$extracted_line" ] || continue
    documented_blocked+=("$extracted_line")
done < <(section_commands '## What Gets Blocked')

documented_allowed=()
while IFS= read -r extracted_line; do
    [ -n "$extracted_line" ] || continue
    documented_allowed+=("$extracted_line")
done < <(section_commands '## What Stays Allowed')

((${#documented_blocked[@]} > 0)) || fatal "no commands found under '## What Gets Blocked' in $skill"
((${#documented_allowed[@]} > 0)) || fatal "no commands found under '## What Stays Allowed' in $skill"

# Pin the counts. Without this the extractor can quietly return a subset and
# every remaining assertion still passes — the failure mode is a green suite
# that verifies less than it did yesterday, which is #227's own defect class
# (a claim nothing executes) relocated into the test that was meant to end it.
# Changing either documented list is expected to change these numbers; that is
# the forcing function, not an obstacle.
EXPECTED_BLOCKED=21
EXPECTED_ALLOWED=10
[ "${#documented_blocked[@]}" -eq "$EXPECTED_BLOCKED" ] || \
    fatal "extracted ${#documented_blocked[@]} blocked forms, expected $EXPECTED_BLOCKED. If you changed '## What Gets Blocked', update EXPECTED_BLOCKED; if you did not, the extractor is dropping entries."
[ "${#documented_allowed[@]}" -eq "$EXPECTED_ALLOWED" ] || \
    fatal "extracted ${#documented_allowed[@]} allowed forms, expected $EXPECTED_ALLOWED. If you changed '## What Stays Allowed', update EXPECTED_ALLOWED; if you did not, the extractor is dropping entries."

printf 'documented blocked forms: %d\n' "${#documented_blocked[@]}"
printf 'documented allowed forms: %d\n' "${#documented_allowed[@]}"

# The two lists are assertions in opposite directions, so an entry in both is a
# contradiction no guard can satisfy. Catching it here names the real problem;
# without this the suite reports a confusing "expected 0, got 2" against a
# command the doc also demands be blocked. This fired for real while writing the
# suite, when the section extractor ran past a "###" subheading and scooped its
# prose examples into the allowed list.
for blocked_cmd in "${documented_blocked[@]}"; do
    for allowed_cmd in "${documented_allowed[@]}"; do
        [[ "$blocked_cmd" != "$allowed_cmd" ]] || \
            fatal "'$blocked_cmd' is listed as both blocked and allowed in $skill"
    done
done

# -----------------------------------------------------------------------------

section "every command the skill documents as blocked is actually blocked"

# This is the assertion #227 needed and did not have. It reads the claim from
# the same list a user reads, so the doc cannot drift ahead of the mechanism.
for cmd in "${documented_blocked[@]}"; do
    assert_verdict "$BLOCKED" "$cmd" "documented as blocked"
done

# -----------------------------------------------------------------------------

section "every command the skill documents as allowed is actually allowed"

for cmd in "${documented_allowed[@]}"; do
    assert_verdict "$ALLOWED" "$cmd" "documented as allowed"
done

# -----------------------------------------------------------------------------

section "destructive forms the doc does not enumerate are still blocked"

# The skill's list names representative forms, not every permutation — a doc
# that enumerated all of them would be unreadable and would drift anyway. These
# are the permutations the guard must handle regardless, one per failure mode
# that defeated the substring matcher. Each is a real invocation of the
# corresponding blocked command, verified against git before being listed here.
assert_blocked_form() { assert_verdict "$BLOCKED" "$1" "$2"; }
assert_allowed_form() { assert_verdict "$ALLOWED" "$1" "$2"; }

# Flag order: the operand can precede the flag.
assert_blocked_form 'git push origin main -f'          'force flag after the operands'
assert_blocked_form 'git push origin main --force'     'long force flag after the operands'

# Flag bundling and ordering on clean.
assert_blocked_form 'git clean -xdf'                   'force bundled with -x and -d'
assert_blocked_form 'git clean -f -d'                  'force split from -d, reordered'
assert_blocked_form 'git clean --force -d'             'long force form'

# Branch force-delete has three spellings; git treats all three identically.
assert_blocked_form 'git branch -D feature'            'short combined force-delete'
assert_blocked_form 'git branch -d -f feature'         'force after delete'
assert_blocked_form 'git branch --force --delete feat' 'long forms, reversed order'

# The `--` separator is the canonical form in many workflows and is exactly as
# destructive as the form without it.
assert_blocked_form 'git checkout -- .'                'pathspec after the -- separator'
assert_blocked_form 'git restore -- .'                 'pathspec after the -- separator'
assert_blocked_form 'git checkout ./'                  'trailing-slash spelling of the cwd pathspec'

# Force and "the whole tree" each have spellings that carry no recognizable
# flag. Enumerating them is what the substring matcher did; the parser must
# recognize the concept, so these probe the reduction rather than a list.
assert_blocked_form 'git push origin +main'            'leading + on a refspec is a force push'
assert_blocked_form 'git push origin +HEAD:main'       'leading + on a full refspec'
assert_blocked_form 'git checkout :/'                  'the :/ top-level magic pathspec'
assert_blocked_form 'git restore :/'                   'the :/ top-level magic pathspec'
assert_blocked_form 'git checkout :/.'                 'magic prefix with a dot'
assert_blocked_form 'git checkout ./.'                 'the cwd written one character longer'
assert_blocked_form 'git checkout -- ./'               'trailing slash after the -- separator'
assert_blocked_form 'git restore --staged --worktree .' 'staged AND worktree does reach the files'

# Leading global options sit between `git` and the subcommand.
assert_blocked_form 'git -C /tmp/repo push -f'         'global -C before the subcommand'
assert_blocked_form 'git --no-pager reset --hard'      'global flag before the subcommand'

# Wrappers and compound commands. A guard that only inspected the first word
# would miss every one of these, so `git` is looked for at any token position.
assert_blocked_form 'sudo git push -f origin main'     'invoked through sudo'
assert_blocked_form 'cd /tmp/repo && git push -f'      'second command in an && chain'
assert_blocked_form 'git status; git reset --hard'     'second command after a semicolon'
assert_blocked_form 'bash -c "git push -f"'            'wrapped in bash -c'
assert_blocked_form '/usr/bin/git push -f'             'invoked by absolute path'

# Spellings the shell joins back into `git`: a quote pair or a backslash inside
# a word is removed by the shell before the command runs, so `g''it` and
# `\git` both execute git. An independent probe walked all of these past a
# draft that replaced quotes with a space instead of removing them.
assert_blocked_form "g''it push -f"                    'empty quotes spliced into the word git'
assert_blocked_form "git pu''sh -f"                    'empty quotes spliced into the subcommand'
assert_blocked_form "g'i't push -f"                    'a quoted letter inside the word git'
assert_blocked_form '\git push -f'                     'backslash before the word git'
assert_blocked_form 'g\it push -f'                     'backslash inside the word git'
assert_blocked_form 'git \push -f'                     'backslash before the subcommand'
assert_blocked_form $'git push \\\n-f'                  'backslash-newline continuation before the flag'

# A bare glob is expanded by the shell into every entry of the directory, so it
# names the whole tree as surely as `.` does. This also pins `set -f` in the
# guard: without it the guard itself would expand `*` into this directory's
# files while tokenizing, see a list of ordinary paths, and allow the command.
assert_blocked_form 'git checkout *'                   'a bare glob is the whole tree'
assert_blocked_form 'git restore -- *'                 'a bare glob after the -- separator'
assert_blocked_form 'git checkout ./*'                 'the cwd glob spelling'
assert_blocked_form 'git checkout **'                  'a doubled glob is still the whole tree'
assert_blocked_form 'git checkout ./**'                'the cwd spelling of the doubled glob'
assert_blocked_form "git checkout '[a-z]*'"            'a character class reaches every tracked file'
assert_blocked_form "git checkout -- '?*'"             'a single-character wildcard does too'
assert_blocked_form "git checkout -- '[[:alpha:]]*'"   'a POSIX class does too'
assert_allowed_form 'git checkout n?ext'               'a lone ? cannot cross a directory'
assert_allowed_form "git checkout '[a-z]'"             'a lone character class cannot either'

# Git's pathspec magic and path traversal, each verified to revert every
# tracked file in a scratch repository.
assert_blocked_form 'git checkout :'                   'a bare colon is the empty pathspec'
assert_blocked_form 'git checkout :.'                  'the empty magic prefix on the cwd'
assert_blocked_form 'git checkout ::'                  'a colon-terminated empty magic prefix'
assert_blocked_form "git checkout -- ':(top)'"         'the long-form top magic'
assert_blocked_form 'git checkout sub/..'              'a directory and back out is the root'
assert_blocked_form 'git checkout ./sub/../.'          'traversal with dot components'
assert_blocked_form "git checkout -- ':!README.md'"    'an exclusion alone is everything but one file'
assert_blocked_form "git checkout -- ':^docs/'"        'the caret spelling of an exclusion'

# Short spellings of restore's index/worktree flags (git help restore: -S is
# --staged, -W is --worktree), bundled and split.
assert_blocked_form 'git restore -W .'                 'short worktree flag'
assert_blocked_form 'git restore -S -W .'              'short staged AND worktree'
assert_blocked_form 'git restore -SW .'                'the same two, bundled'

# Everything after `--` is an operand, so a dry-run flag written there is a
# filename and does not neutralize the force. This is the one case that tells a
# guard honoring `--` from one that ignores it.
assert_blocked_form 'git clean -f -- -n'               'a flag-shaped filename after -- is not a flag'

# -----------------------------------------------------------------------------

section "benign near-misses stay allowed"

# The false-positive class the substring matcher had: `git checkout \.` matched
# any path beginning with a dot. Dotfiles and dot-directories are ordinary
# targets, and blocking them makes the guard actively obstructive.
assert_allowed_form 'git checkout .github/workflows/ci.yml' 'a dot-directory path is not the cwd pathspec'
assert_allowed_form 'git restore .gitignore'                'a dotfile path is not the cwd pathspec'
assert_allowed_form 'git checkout -- .gitignore'            'a dotfile after the -- separator'
assert_allowed_form 'git checkout .eslintrc.json'           'a dotfile with an extension'

# Near-misses on the flags themselves.
assert_allowed_form 'git reset --soft HEAD~1'          'soft reset does not touch the working tree'
assert_allowed_form 'git reset --keep HEAD~1'          'keep reset refuses to discard local changes'
assert_allowed_form 'git clean -n'                     'dry-run clean deletes nothing'
assert_allowed_form 'git clean --dry-run -d'           'long dry-run form with -d'
assert_allowed_form 'git branch -d merged-branch'      'safe delete refuses unmerged branches'
assert_allowed_form 'git branch --delete merged'       'long safe-delete form'
assert_allowed_form 'git push origin main'             'an ordinary push'
assert_allowed_form 'git checkout main'                'checking out a branch is not a pathspec'
assert_allowed_form 'git checkout -b new-feature'      'creating a branch'
assert_allowed_form 'git status'                       'a read-only command'
assert_allowed_form 'git log --oneline -5'             'a numeric flag is not a force flag'
assert_allowed_form 'git diff --stat'                  'a read-only command with flags'

# `git clean -f -n` is genuinely non-destructive: verified against git, the
# dry-run flag wins and the files survive. Allowing it keeps the guard honest
# about what it is actually preventing.
assert_allowed_form 'git clean -f -n'                  'dry-run neutralizes force, verified against git'

# Index-only and interactive variants. The rewrite briefly blocked these: it
# treated `restore` exactly like `checkout` and looked only at operands, so
# unstaging was refused. Removing the old matcher's false positives was the
# point of that rewrite, which makes a fresh one worth pinning.
assert_allowed_form 'git restore --staged .'           'unstaging never touches the working tree'
assert_allowed_form 'git restore --cached .'           'the --cached spelling of the same'
assert_allowed_form 'git checkout -p .'                'patch mode prompts before discarding'
assert_allowed_form 'git restore --patch .'            'long patch-mode spelling'
assert_allowed_form 'git push origin main:main'        'an ordinary refspec with no leading +'
assert_allowed_form 'git checkout .config/wt.toml'     'a dot-directory path, not the whole tree'
assert_allowed_form 'git restore -S .'                 'the short spelling of --staged'
assert_allowed_form 'git checkout src/*.ts'            'a glob under a path is not the whole tree'
assert_allowed_form 'git checkout */'                  'a trailing-slash glob matches nothing in git'
assert_allowed_form 'git checkout ./*/'                'the cwd spelling of the same'
assert_allowed_form 'git checkout sub/**'              'a doubled glob under a directory is that directory'
assert_allowed_form 'git checkout */*'                 'a glob before the last component is partial'
assert_allowed_form 'git checkout sub/../sub'          'traversal that lands back in a subdirectory'
assert_allowed_form 'git checkout ../*'                'a path outside the repository, which git rejects'
assert_allowed_form "git checkout -- ':!README.md' src/" 'an exclusion beside a positive operand is partial'
assert_allowed_form 'git --exec-path push -f'          'bare --exec-path prints a path and runs nothing'
assert_allowed_form 'git --version push -f'            'bare --version prints and runs nothing'
assert_allowed_form 'git --html-path push -f'          'bare --html-path prints and runs nothing'
assert_allowed_form 'git --man-path reset --hard'      'bare --man-path prints and runs nothing'
assert_allowed_form 'git --info-path reset --hard'     'bare --info-path prints and runs nothing'

# The guard must not choke on input that is not a git command at all.
assert_allowed_form 'echo hello'                       'a non-git command'
assert_allowed_form 'ls -la'                           'a non-git command with flags'

# -----------------------------------------------------------------------------

section "the deliberate over-block is pinned, not accidental"

# Quote characters are stripped before tokenizing, which is what lets the guard
# see into `bash -c "git push -f"`. The same stripping means a dangerous command
# quoted as *search text* is also blocked. The two cannot be separated: honoring
# quotes would keep the grep working and reopen the wrapper bypass.
#
# Fail closed is the right resolution — a blocked grep costs one rephrase, a
# missed force push costs history — but it is a real false positive, so it is
# asserted here rather than left to be rediscovered as a bug.
assert_verdict "$BLOCKED" "grep -r 'git push --force' docs/" \
    'the dangerous string as search text (accepted over-block: quotes are stripped)'

# A starred pattern at the root of a checkout or restore is refused whatever
# it spells, because `[a-z]*` and `?*` reach every tracked file and the guard
# cannot tell which names `*.txt` reaches without reading the tree. This one
# costs something real — `git checkout -- '*.txt'` is a legitimate partial
# revert — and #334 carries it as a known over-block.
assert_verdict "$BLOCKED" "git checkout -- '*.txt'" \
    'a root-level starred pattern (accepted over-block: the guard cannot see what it matches)'

# -----------------------------------------------------------------------------

section "the conditional gh pr merge lists are executed, not asserted"

# The review-currency refusal (#327, Lock 2) is the one rule here that depends
# on repository state rather than on the command's shape, so its two documented
# lists cannot be run through `run_guard` as written — they need a `gh` that
# answers and a stamp to disagree with. Everything else about them is the same
# contract as the git lists above: the doc is extracted and executed, in both
# directions, and a claim that stops being true fails here.
#
# EVERY backticked span in these two lists is read, not the ones beginning with
# a chosen word. The git lists above are extracted by their leading `git `, and
# that rule silently dropped `sudo gh pr merge 4821` from this one — a
# documented form the extractor cannot see is a claim nothing executes, which is
# #227's defect class relocated into the suite meant to end it. Two of these
# entries deliberately do not begin with `gh`: one runs through `sudo`, and one
# is a `git commit` whose message merely contains the words.
#
# The cost of reading every span is that a parenthetical `like this` in a list
# item is extracted as if it were a command. What catches that is the
# EXPECTED_STALE_* count pin below, not this extractor: the `grep -o` pattern is
# `\`[^\`]* [^\`]*\``, which requires a literal space inside the span, so every
# entry it can emit already has one. An earlier draft guarded the same worry
# with a two-word floor here and described that floor as the mechanism; the
# floor's reject branch was unreachable for exactly this reason, and it is
# deleted rather than kept as reassurance. Adding a stray two-word span to a
# list moves the count and the pin says so by name.
conditional_commands() {
    section_commands "$1" '[^`]*'
}

stale_blocked=()
while IFS= read -r extracted_line; do
    [ -n "$extracted_line" ] || continue
    stale_blocked+=("$extracted_line")
done < <(conditional_commands '### Refused when the review stamp is stale')

stale_allowed=()
while IFS= read -r extracted_line; do
    [ -n "$extracted_line" ] || continue
    stale_allowed+=("$extracted_line")
done < <(conditional_commands '### Allowed even when the stamp is stale')

# Same forcing function as EXPECTED_BLOCKED above: without a count pin the
# extractor can quietly return a subset and every assertion below still passes.
EXPECTED_STALE_BLOCKED=8
EXPECTED_STALE_ALLOWED=8
[ "${#stale_blocked[@]}" -eq "$EXPECTED_STALE_BLOCKED" ] || \
    fatal "extracted ${#stale_blocked[@]} stale-stamp blocked forms, expected $EXPECTED_STALE_BLOCKED. If you changed '### Refused when the review stamp is stale', update EXPECTED_STALE_BLOCKED; if you did not, the extractor is dropping entries."
[ "${#stale_allowed[@]}" -eq "$EXPECTED_STALE_ALLOWED" ] || \
    fatal "extracted ${#stale_allowed[@]} stale-stamp allowed forms, expected $EXPECTED_STALE_ALLOWED. If you changed '### Allowed even when the stamp is stale', update EXPECTED_STALE_ALLOWED; if you did not, the extractor is dropping entries."

for blocked_cmd in "${stale_blocked[@]}"; do
    for allowed_cmd in "${stale_allowed[@]}"; do
        [[ "$blocked_cmd" != "$allowed_cmd" ]] || \
            fatal "'$blocked_cmd' is listed as both refused and allowed in $skill"
    done
done

printf 'documented stale-stamp refusals: %d\n' "${#stale_blocked[@]}"
printf 'documented stale-stamp passes:   %d\n' "${#stale_allowed[@]}"

# --- a gh that answers, and two real commits to disagree about ---------------

gh_stub_dir="$(mktemp -d)"

# Two commits that exist in THIS repository, so the guard's delta measurement
# runs its measurable branch rather than its fallback. HEAD~1 is used rather
# than a literal SHA: a literal would have to be updated forever, and the
# suite would go quietly vacuous the day it stopped resolving.
stamp_sha="$(git -C "$repo_root" rev-parse HEAD~1 2>/dev/null)"
head_oid="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)"
[[ ${#stamp_sha} -eq 40 && ${#head_oid} -eq 40 && "$stamp_sha" != "$head_oid" ]] || \
    fatal "could not resolve two distinct 40-character commits in $repo_root (shallow clone?)"

# write_gh_stub <body> <headRefOid> — a `gh` on PATH that returns one canned
# PR. It appends its argv to $gh_stub_dir/calls so the selector and -R
# forwarding can be asserted on what the guard actually ASKED for, not only on
# the verdict it reached: a guard that looks up the wrong PR and refuses is
# indistinguishable from a correct one by exit code alone, and that was a real
# defect in the first version of this check.
write_gh_stub() {
    jq -nc --arg b "$1" --arg o "$2" '{body: $b, headRefOid: $o}' > "$gh_stub_dir/pr.json"
    : > "$gh_stub_dir/calls"
    cat > "$gh_stub_dir/gh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$gh_stub_dir/calls"
exec cat "$gh_stub_dir/pr.json"
STUB
    chmod +x "$gh_stub_dir/gh"
}

# run_guard_gh <command> — the real hook, with the stub `gh` ahead of PATH.
run_guard_gh() {
    local cmd="$1" payload
    payload="$(jq -nc --arg c "$cmd" '{tool_input: {command: $c}}')"
    printf '%s' "$payload" | PATH="$gh_stub_dir:$PATH" bash "$script" >/dev/null 2>&1
    printf '%s' "$?"
}

assert_verdict_gh() {
    local expected="$1" cmd="$2" label="$3" actual
    actual="$(run_guard_gh "$cmd")"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %-46s %s\n' "$cmd" "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %-46s %s\n       expected exit %s, got exit %s\n' \
            "$cmd" "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

stale_body="## Summary

reviewed and stamped <!-- reviewed-at: $stamp_sha -->

## Test plan"

write_gh_stub "$stale_body" "$head_oid"

for cmd in "${stale_blocked[@]}"; do
    assert_verdict_gh "$BLOCKED" "$cmd" 'documented as refused on a stale stamp'
done

for cmd in "${stale_allowed[@]}"; do
    assert_verdict_gh "$ALLOWED" "$cmd" 'documented as allowed on a stale stamp'
done

# -----------------------------------------------------------------------------

section "the guard asks about the PR the merge would actually act on"

# `-R` was dropped by the first version of this check, so `gh pr merge 123 -R
# other/repo` looked up PR 123 in the CURRENT repo and refused on the wrong
# pull request — a wrong refusal that exit code 2 alone reports as a success.
assert_gh_lookup() {
    local cmd="$1" expected="$2"
    : > "$gh_stub_dir/calls"
    run_guard_gh "$cmd" >/dev/null
    local actual
    actual="$(cat "$gh_stub_dir/calls" 2>/dev/null)"
    assert_eq "$expected" "$actual" "$cmd  ->  gh $expected"
}

assert_gh_lookup 'gh pr merge'                     'pr view --json body,headRefOid'
assert_gh_lookup 'gh pr merge 4821'                'pr view 4821 --json body,headRefOid'
assert_gh_lookup 'gh pr merge # ship it'           'pr view --json body,headRefOid'
assert_gh_lookup 'gh pr merge 4821 --squash --delete-branch' \
    'pr view 4821 --json body,headRefOid'
assert_gh_lookup 'gh pr merge 4821 -R owner/repo'  'pr view 4821 --repo owner/repo --json body,headRefOid'
assert_gh_lookup 'gh pr merge -R owner/repo 4821'  'pr view 4821 --repo owner/repo --json body,headRefOid'
assert_gh_lookup 'gh pr merge --repo=owner/repo 4821' 'pr view 4821 --repo owner/repo --json body,headRefOid'
assert_gh_lookup 'gh pr merge -Rowner/repo 4821'   'pr view 4821 --repo owner/repo --json body,headRefOid'
assert_gh_lookup 'gh pr merge https://github.com/o/r/pull/9 --squash' \
    'pr view https://github.com/o/r/pull/9 --json body,headRefOid'

# A form the guard declines to judge must not ask at all. Asking and then
# allowing would be a wasted API call on every merge; asking and then refusing
# is the wrong-PR defect below.
assert_gh_lookup 'gh pr merge --subject fix 4821'  ''
assert_gh_lookup 'echo gh pr merge now'            ''

# An operand that follows a flag may be that flag's value, and these are the
# five that take one:
#
#     -A, --author-email text    -b, --body text    -F, --body-file file
#     -t, --subject text         --match-head-commit SHA
#
# read out of `gh pr merge --help` by an independent probe, after a draft of
# this check accepted any all-digits operand on the reasoning that no gh flag
# takes a number. Under that draft `gh pr merge --subject 4821` looked up PR
# 4821 while the merge it would permit targets the CURRENT branch's PR — a
# confident verdict about a pull request nobody asked about, reached either
# way, and invisible in the exit code. The list above is not what the script
# checks and is not maintained anywhere: the rule is that a flag's value
# follows its flag, so an operand after any flag is unresolvable whatever the
# flag turns out to be.
assert_gh_lookup 'gh pr merge --subject 4821'      ''
assert_gh_lookup 'gh pr merge -t 4821'             ''
assert_gh_lookup 'gh pr merge --body 4821'         ''
assert_gh_lookup 'gh pr merge --author-email 4821' ''
assert_gh_lookup 'gh pr merge --match-head-commit 4821' ''
assert_gh_lookup 'gh pr merge --squash 4821'       ''
assert_gh_lookup 'gh pr merge --squash https://github.com/o/r/pull/9' ''

# -----------------------------------------------------------------------------

section "the refusal names both SHAs and a non-empty delta"

# One assertion binding the identity of the block to its stated reason, per
# rule 1 of docs/solutions/testing-patterns/mutate-the-oracle-not-only-the-subject-2026-08-19.md.
# Checking for "BLOCKED" and the SHAs as independent substrings would stay
# green with an empty delta, and the delta is the whole reason a human can
# decide proportionally instead of clicking through.
stderr_gh="$(jq -nc --arg c 'gh pr merge 4821' '{tool_input: {command: $c}}' \
    | PATH="$gh_stub_dir:$PATH" bash "$script" 2>&1 >/dev/null)"

if [[ "$stderr_gh" == *"reviewed-at: $stamp_sha"* \
   && "$stderr_gh" == *"PR head:     $head_oid"* \
   && "$stderr_gh" == *"delta:       1 commit(s) past the stamp; "* ]]; then
    printf '  ok   the refusal names the stamped SHA, the head, and a measured delta\n'
    pass=$((pass + 1))
else
    printf '  FAIL the refusal lost a SHA or its delta\n       got: %q\n' "$stderr_gh"
    fail=$((fail + 1))
fi

# The escape hatch is only an escape hatch if the message says how to use it,
# at the moment it is needed. Both exits are named, and the variable is spelled
# the same way the script tests for it.
opt_out_name="$(grep -o 'STALE_STAMP_OPT_OUT=[A-Z_]*' "$script" | head -1 | cut -d= -f2 || true)"
[[ -n "$opt_out_name" ]] || fatal "no STALE_STAMP_OPT_OUT assignment found in $script"
if [[ "$stderr_gh" == *"/pre-merge"* && "$stderr_gh" == *"$opt_out_name=1"* ]]; then
    printf '  ok   the refusal names both exits: /pre-merge and %s=1\n' "$opt_out_name"
    pass=$((pass + 1))
else
    printf '  FAIL the refusal does not name both exits\n       got: %q\n' "$stderr_gh"
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "the stale-stamp check fails open everywhere it cannot be certain"

# Every entry here is a case where the guard has no grounds to refuse. The
# direction matters more than for the git rules: those fail closed because a
# blocked grep costs a rephrase, while a merge wrongly refused blocks the one
# command that finishes a piece of work, and /closeout Step 2 reads the same
# stamp on the path most merges take.

write_gh_stub "$stale_body" "$stamp_sha"
assert_verdict_gh "$ALLOWED" 'gh pr merge 4821' 'the stamp matches the head'

write_gh_stub "## Summary

no stamp on this PR at all

## Test plan" "$head_oid"
assert_verdict_gh "$ALLOWED" 'gh pr merge 4821' 'the PR carries no stamp'

write_gh_stub "reviewed at <!-- reviewed-at: ${stamp_sha:0:7} -->" "$head_oid"
assert_verdict_gh "$ALLOWED" 'gh pr merge 4821' 'the stamp is a short SHA the reader rejects'

write_gh_stub "reviewed at <!-- reviewed-at: not-a-sha -->" "$head_oid"
assert_verdict_gh "$ALLOWED" 'gh pr merge 4821' 'the stamp is not a SHA'

write_gh_stub "$stale_body" "$head_oid"
assert_verdict_gh "$ALLOWED" "$opt_out_name=1 gh pr merge 4821" \
    'the inline opt-out assignment is honored'

# The opt-out is an ASSIGNMENT IN COMMAND POSITION, which is the only place a
# real shell would let it reach the process. An earlier draft scanned the whole
# token stream for the name, so any mention of it anywhere in the line disarmed
# the check while the command that actually ran was the bare, unblocked merge.
# The tokenizer already stops at `#` for operands; the opt-out scan did not, and
# the string is plausible in a trailing note without anyone intending a bypass.
assert_verdict_gh "$BLOCKED" "gh pr merge 4821 # $opt_out_name=1" \
    'the opt-out named in a trailing comment is not an opt-out'
assert_verdict_gh "$BLOCKED" "gh pr merge # $opt_out_name=1" \
    'the same, on the current-branch form that takes no operand'
assert_verdict_gh "$BLOCKED" "gh pr merge 4821 # see docs on $opt_out_name=1" \
    'the name inside prose in a comment is not an opt-out'
assert_verdict_gh "$BLOCKED" "gh pr merge $opt_out_name=1" \
    'an assignment after the command word is an operand, not an opt-out'
assert_verdict_gh "$ALLOWED" "gh pr merge 4821 $opt_out_name=1" \
    'and with a real operand already present it is a second one, so the target is unresolvable'

# And it is the VALUE the refusal message promises, not merely the name. A
# reader typing `=false` means "do not allow"; matching on the assignment alone
# reads that as consent. Anything but 1 leaves the check armed, which is the
# direction that cannot silently lose a review.
assert_verdict_gh "$BLOCKED" "$opt_out_name=0 gh pr merge 4821" \
    'the opt-out set to 0 does not opt out'
assert_verdict_gh "$BLOCKED" "$opt_out_name=false gh pr merge 4821" \
    'the opt-out set to false does not opt out'
assert_verdict_gh "$BLOCKED" "$opt_out_name= gh pr merge 4821" \
    'the opt-out set to nothing does not opt out'

# The exported spelling, for a repo that wants the check advisory. Asserted
# separately because it reaches the script by a different route — the hook's
# own environment rather than the command being inspected — and the refusal
# message only promises the inline one.
env_status="$(jq -nc --arg c 'gh pr merge 4821' '{tool_input: {command: $c}}' \
    | PATH="$gh_stub_dir:$PATH" ALLOW_STALE_STAMP_MERGE=1 bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 0 "$env_status" "an exported $opt_out_name makes the check advisory"

# The exported spelling carries the same value contract as the inline one. Left
# unasserted, a change that widened it back to "any non-empty value" passed the
# whole suite — the three value cases above all use the inline spelling, so they
# hold one of the two routes into this check and say nothing about the other.
env_status_false="$(jq -nc --arg c 'gh pr merge 4821' '{tool_input: {command: $c}}' \
    | PATH="$gh_stub_dir:$PATH" ALLOW_STALE_STAMP_MERGE=false bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 2 "$env_status_false" "an exported $opt_out_name=false does not opt out"

# A gh that fails — unauthenticated, offline, or pointed at a PR that does not
# exist. The check has nothing to read and must not guess.
printf '#!/bin/sh\nexit 1\n' > "$gh_stub_dir/gh"
chmod +x "$gh_stub_dir/gh"
assert_verdict_gh "$ALLOWED" 'gh pr merge 4821' 'the gh call fails'

printf '#!/bin/sh\nprintf "not json"\n' > "$gh_stub_dir/gh"
chmod +x "$gh_stub_dir/gh"
assert_verdict_gh "$ALLOWED" 'gh pr merge 4821' 'gh returns something that is not JSON'

# No gh at all. The git rules must be unaffected — a missing optional
# dependency for one conditional check cannot disarm the guard's main job.
rm -f "$gh_stub_dir/gh"
nogh_dir="$(mktemp -d)"
for tool in jq git sed tail printf; do
    tool_path="$(command -v "$tool" 2>/dev/null)" && ln -sf "$tool_path" "$nogh_dir/$tool"
done
nogh_merge="$(printf '%s' '{"tool_input":{"command":"gh pr merge 4821"}}' \
    | PATH="$nogh_dir:/usr/bin:/bin" bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 0 "$nogh_merge" "a merge is allowed when gh is not installed"
nogh_push="$(printf '%s' '{"tool_input":{"command":"git push --force origin main"}}' \
    | PATH="$nogh_dir:/usr/bin:/bin" bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 2 "$nogh_push" "a force push is still refused when gh is not installed"
rm -rf "$nogh_dir"

# -----------------------------------------------------------------------------

section "gh is read where it is invoked, and not where it is only mentioned"

write_gh_stub "$stale_body" "$head_oid"

# Command position. A wrapper the walk does not know produces a miss, which is
# the safe direction here; each entry below is a wrapper it does know.
assert_verdict_gh "$BLOCKED" 'sudo gh pr merge 4821'          'through sudo'
assert_verdict_gh "$BLOCKED" 'env gh pr merge 4821'           'through env'
assert_verdict_gh "$BLOCKED" 'GH_TOKEN=x gh pr merge 4821'     'after an assignment prefix'
assert_verdict_gh "$BLOCKED" 'if gh pr merge 4821; then echo ok; fi' 'as an if condition'
assert_verdict_gh "$BLOCKED" '/opt/homebrew/bin/gh pr merge 4821' 'by absolute path'
assert_verdict_gh "$BLOCKED" 'cd /tmp && gh pr merge 4821'    'second in an && chain'

# Indirect execution. The quote stripping that lets the git rules see into
# `bash -c "git push -f"` flattens these into ordinary tokens too, so the only
# thing that was missing was the wrapper name. An independent probe walked all
# four past a draft that listed only the process wrappers, and confirmed each
# one really does run the merge.
assert_verdict_gh "$BLOCKED" 'bash -c "gh pr merge 4821"'     'through bash -c'
assert_verdict_gh "$BLOCKED" 'sh -c "gh pr merge 4821"'       'through sh -c'
assert_verdict_gh "$BLOCKED" 'eval "gh pr merge 4821"'        'through eval'
assert_verdict_gh "$BLOCKED" "printf '%s' 4821 | xargs -I{} bash -c 'gh pr merge {}'" \
    'through xargs into bash -c'

# A trailing comment is prose, not an operand. Counting `#`, `ship` and `it`
# as three operands made this unresolvable, and it let the barest form of the
# command through — the same probe found it, and it is the cheapest bypass in
# the set because nobody typing it is trying to bypass anything.
assert_verdict_gh "$BLOCKED" 'gh pr merge # ship it'          'with a trailing comment'
assert_verdict_gh "$BLOCKED" 'gh pr merge 4821 # ship it'     'with a PR number and a trailing comment'

# The design limit, pinned as a MISS rather than left to be rediscovered. The
# command is read as tokens and never evaluated, so a merge assembled at run
# time is invisible — identical to the limit the git rules carry, and #334
# holds it for both halves. These assertions exist so that a future change
# claiming to close the class has to change them.
# shellcheck disable=SC2016  # the unexpanded $CMD and ${IFS} ARE the test data
assert_verdict_gh "$ALLOWED" 'CMD="gh pr merge 4821"; $CMD'   'assembled in a variable (known limit)'
# shellcheck disable=SC2016
assert_verdict_gh "$ALLOWED" 'gh${IFS}pr${IFS}merge 4821'     'spliced with ${IFS} (known limit)'

# The evasions the substring matcher had. Each of these passed it because the
# matcher required whitespace or end-of-line after the word `merge`; the
# tokenizer makes every one of them the same segment.
assert_verdict_gh "$BLOCKED" 'gh pr merge; true'              'semicolon immediately after merge'
assert_verdict_gh "$BLOCKED" 'gh pr merge&&true'              'no space before &&'
assert_verdict_gh "$BLOCKED" 'gh pr merge|cat'                'no space before a pipe'
assert_verdict_gh "$BLOCKED" 'gh pr merge 4821 &'             'backgrounded'

# Mentions. The substring matcher refused all four, and this hook runs before
# every Bash call in every repo it is installed into.
assert_verdict_gh "$ALLOWED" 'echo gh pr merge'               'echoed'
assert_verdict_gh "$ALLOWED" '# gh pr merge 4821'             'in a comment'
assert_verdict_gh "$ALLOWED" 'grep -rn "gh pr merge" docs/'   'as a search string'
assert_verdict_gh "$ALLOWED" 'rg -l "gh pr merge" .'          'as a search string for another tool'
assert_verdict_gh "$ALLOWED" 'git commit -m "document gh pr merge"' 'in a commit message'
assert_verdict_gh "$ALLOWED" 'printf "%s\n" "gh pr merge 4821"' 'as a printf argument'

# Negative controls for the wrappers added above. Widening the list is how a
# guard acquires a false positive, so each new wrapper is probed in the
# direction that would hurt: the same wrapper around a MENTION must still pass.
assert_verdict_gh "$ALLOWED" 'bash -c "echo gh pr merge"'     'a mention inside bash -c'
assert_verdict_gh "$ALLOWED" 'eval "echo gh pr merge 4821"'   'a mention inside eval'
assert_verdict_gh "$ALLOWED" "sh -c 'grep -rn \"gh pr merge\" .'" 'a search inside sh -c'

# A heredoc body is data. The terminator ends it, so an invocation after the
# body is still read — a one-way skip would be a bypass, not a narrowing.
assert_verdict_gh "$ALLOWED" "$(printf 'cat <<EOF > /tmp/notes\ngh pr merge 4821\nEOF')" \
    'inside a heredoc body'
assert_verdict_gh "$ALLOWED" "$(printf 'cat <<-DOC\ngh pr merge 4821\nDOC')" \
    'inside a dash-indented heredoc body'
assert_verdict_gh "$BLOCKED" "$(printf 'cat <<EOF > /tmp/notes\ngh pr merge 4821\nEOF\ngh pr merge 4821')" \
    'after the heredoc terminator'

# Not this command. `pr view` and `pr list` read; only `merge` merges, and
# nothing legitimately sits between `gh` and `pr` (gh's own global options are
# --help and --version).
assert_verdict_gh "$ALLOWED" 'gh pr view 4821'                'a read-only gh command'
assert_verdict_gh "$ALLOWED" 'gh pr list --state open'        'a read-only gh command with flags'
assert_verdict_gh "$ALLOWED" 'gh pr edit 4821 --add-label x'  'another gh pr subcommand'
assert_verdict_gh "$ALLOWED" 'gh repo view'                   'another gh command group'

rm -rf "$gh_stub_dir"

# -----------------------------------------------------------------------------

section "malformed and empty input fails open rather than crashing"

# A PreToolUse hook runs on every single Bash call. If it errors on unexpected
# input it breaks the session rather than the dangerous command, so the
# not-a-git-command path must be quiet and cheap.
for payload in '{}' '{"tool_input":{}}' '{"tool_input":{"command":""}}' 'not json at all'; do
    actual="$(printf '%s' "$payload" | bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
    if [[ "$actual" == "0" ]]; then
        printf '  ok   %-46s exits 0 on unusable input\n' "$payload"
        pass=$((pass + 1))
    else
        printf '  FAIL %-46s expected exit 0, got exit %s\n' "$payload" "$actual"
        fail=$((fail + 1))
    fi
done

# -----------------------------------------------------------------------------

section "the skill's own Verify block is a runnable check with the stated result"

# The Verify block is what a user runs to confirm the install worked. In #227 it
# tested only the one form that happened to be covered, which is how a guard
# with a hole passed its own acceptance check. Extract its commands and their
# documented verdicts and run them, so the self-check cannot again be narrower
# than the claim it is verifying.
verify_cases="$(awk '
    /^# Should be BLOCKED/ { verdict = 2; next }
    /^# Should be ALLOWED/ { verdict = 0; next }
    /^echo .*tool_input/ && verdict != "" { print verdict "\t" $0 }
' "$skill")"

[[ -n "$verify_cases" ]] || fatal "no annotated 'echo {tool_input...}' lines found in the Verify block of $skill"

while IFS=$'\t' read -r expected line; do
    # Substitute the documented placeholder for the real script, then run the
    # skill's own line verbatim. A malformed JSON envelope or a renamed field
    # fails here rather than in a downstream user's install.
    runnable="${line//<path-to-script>/bash \"$script\"}"
    [[ "$runnable" != "$line" ]] || fatal "the <path-to-script> placeholder is gone from the Verify block"
    eval "$runnable" >/dev/null 2>&1
    actual=$?
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   Verify block line exits %s as documented\n' "$expected"
        pass=$((pass + 1))
    else
        printf '  FAIL Verify block line: expected exit %s, got exit %s\n       %s\n' \
            "$expected" "$actual" "$line"
        fail=$((fail + 1))
    fi
done <<< "$verify_cases"

# -----------------------------------------------------------------------------

section "no second skill restates the blocked list"

# The contract above is only enforceable where it is extracted from, so a copy
# of the list in another skill is a claim nothing executes. init-pipeline/SKILL.md
# had one, and it was wrong the same way #227 was — it asserted plain `git push`
# was blocked, which it never has been. That file is the one most downstream
# projects read, because /execute Step 0 auto-invokes /init-pipeline.
#
# Rather than test the other file's prose for correctness, forbid the
# restatement: a skill that describes the guard must point at the canonical
# lists instead of enumerating them.
restating_files=""
while IFS= read -r candidate; do
    [ "$candidate" = "$skill" ] && continue
    # A line that both talks about blocking git commands and enumerates
    # backticked `git <verb>` forms is a restatement of the contract.
    if grep -qiE '(block|guard)[^.]*git command' "$candidate" 2>/dev/null; then
        if grep -q '`git ' < <(grep -iE '(block|guard)[^.]*git command' "$candidate"); then
            restating_files="$restating_files $candidate"
        fi
    fi
done <<EOF
$(find "$repo_root" -name SKILL.md -not -path '*/node_modules/*')
EOF

if [ -z "$restating_files" ]; then
    printf '  ok   no other SKILL.md enumerates the blocked commands\n'
    pass=$((pass + 1))
else
    printf '  FAIL these files restate the blocked list instead of pointing at it:%s\n' "$restating_files"
    printf '       A second copy is a second thing to keep true; #227 is what that costs.\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "a blocked command explains itself on stderr"

# Claude only sees stderr when the hook exits non-zero, so the message is the
# entire feedback channel. An empty one turns a deliberate block into what looks
# like a broken tool, and the agent retries instead of stopping.
stderr_out="$(jq -nc '{tool_input: {command: "git push -f origin main"}}' | bash "$script" 2>&1 >/dev/null)"

# Bind the identity of the block to its stated reason in ONE assertion. Checking
# for "BLOCKED" and the command as two independent substrings let the reason go
# empty — every REASON= assignment could be blanked, producing
# "...is a destructive git command ()." — and the suite still reported green.
# That is Prevention rule 1 of
# docs/solutions/testing-patterns/mutate-the-oracle-not-only-the-subject-2026-08-19.md:
# assert the answer, not the presence of its parts.
if [[ "$stderr_out" == *"BLOCKED: 'git push -f origin main' is a destructive git command (force push"* ]]; then
    printf '  ok   the block message names BLOCKED, the command, and a non-empty reason\n'
    pass=$((pass + 1))
else
    printf '  FAIL the block message lost BLOCKED, the command, or its reason\n       got: %q\n' "$stderr_out"
    fail=$((fail + 1))
fi

# Every blocked form must carry a reason, not just the one probed above. An
# empty parenthetical turns a deliberate refusal into what reads as a broken
# tool, and the agent retries instead of stopping.
for probe_cmd in 'git reset --hard' 'git clean -fd' 'git branch -D x' 'git checkout .' 'git push origin +main'; do
    probe_err="$(jq -nc --arg c "$probe_cmd" '{tool_input: {command: $c}}' | bash "$script" 2>&1 >/dev/null)"
    if [[ "$probe_err" == *"destructive git command ("* && "$probe_err" != *"destructive git command ()"* ]]; then
        printf '  ok   %-30s is refused with a non-empty reason\n' "$probe_cmd"
        pass=$((pass + 1))
    else
        printf '  FAIL %-30s was refused with an empty or missing reason\n       got: %q\n' "$probe_cmd" "$probe_err"
        fail=$((fail + 1))
    fi
done

# -----------------------------------------------------------------------------

section "the guard refuses git commands rather than failing open when jq is gone"

# Without jq the command cannot be extracted at all. Reporting "nothing
# dangerous here" would silently disarm the guard — a force push exited 0 with
# empty stderr before this was added. Non-git input stays unaffected, so a
# missing dependency does not halt the whole session.
jq_stub_dir="$(mktemp -d)"
printf '#!/bin/sh\nexit 127\n' > "$jq_stub_dir/jq"
chmod +x "$jq_stub_dir/jq"

nojq_status="$(printf '%s' '{"tool_input":{"command":"git push --force origin main"}}' \
    | PATH="$jq_stub_dir:/usr/bin:/bin" bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 2 "$nojq_status" "a force push is refused when jq is unavailable"

nojq_benign="$(printf '%s' '{"tool_input":{"command":"ls -la"}}' \
    | PATH="$jq_stub_dir:/usr/bin:/bin" bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 0 "$nojq_benign" "a non-git command still runs when jq is unavailable"

# The same condition reaching a `gh pr merge`, which the section above never
# exercised: it removes jq and then runs only `git`. `gh` is present here and
# jq alone is missing.
#
# The mechanism is worth naming, because it is not the stale-stamp check
# choosing to fail open — that check never runs. Without a working jq the hook
# returns at the top, before any rule, and refuses only input matching `*git*`
# so a session is not halted wholesale. `gh pr merge 4821` carries no such
# substring, so it is allowed. The consequence is real and asymmetric: a stale
# merge typed alone is unguarded when jq is broken, while the same merge in a
# chain that also names git is refused with the jq message.
nojq_gh_dir="$(mktemp -d)"
cp "$jq_stub_dir/jq" "$nojq_gh_dir/jq"
cat > "$nojq_gh_dir/gh" <<GH_STUB
#!/bin/sh
printf '{"body":"<!-- reviewed-at: $stamp_sha -->","headRefOid":"$head_oid"}'
GH_STUB
chmod +x "$nojq_gh_dir/gh"
nojq_merge="$(printf '%s' '{"tool_input":{"command":"gh pr merge 4821"}}' \
    | PATH="$nojq_gh_dir:/usr/bin:/bin" bash "$script" >/dev/null 2>&1; printf '%s' "$?")"
assert_eq 0 "$nojq_merge" "a stale-stamp merge is allowed when jq is unavailable"
rm -rf "$nojq_gh_dir"

rm -rf "$jq_stub_dir"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
