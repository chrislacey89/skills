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
    local heading="$1"
    awk -v want="$heading" '
        $0 == want { inside = 1; in_item = 0; next }
        /^#/ { inside = 0; in_item = 0 }
        !inside { next }
        /^[[:space:]]*$/ { in_item = 0; next }
        /^[-*+] / { in_item = 1; print; next }
        in_item { print }
    ' "$skill" | grep -o '`git [^`]*`' | sed 's/^`//; s/`$//'
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

assert_allowed_form() { assert_verdict "$ALLOWED" "$1" "$2"; }

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
        if grep -iE '(block|guard)[^.]*git command' "$candidate" | grep -q '`git '; then
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

rm -rf "$jq_stub_dir"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
