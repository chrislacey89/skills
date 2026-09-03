#!/usr/bin/env bash
# test-review-currency-marker.sh — cross-skill contract test for the
# `<!-- reviewed-at: <sha> -->` review-currency stamp.
#
# /pre-merge Phase 4 WRITES the marker into the PR body. /closeout Step 2 READS
# it back and compares it to `headRefOid` before merging, and
# git-guardrails-claude-code/scripts/block-dangerous-git.sh READS it a second
# time to refuse a `gh pr merge` whose head has moved past the stamp. Three
# copies of one string across two skills and a hook, and no shared definition of
# the string's shape — which is exactly the drift class
# docs/solutions/architecture-decisions/staleness-gate-intermediate-writers-2026-08-06.md
# named under Prevention → Code-level.
#
# The hook is the copy most likely to drift unnoticed: it lives outside both
# SKILL.md files, is installed by copy into someone else's `.claude/hooks/`, and
# nothing else in this repo reads it. So this suite extracts its sed script from
# the real file and requires byte equality with /closeout's, then RUNS the hook
# end to end against a stubbed `gh` — because an extractor that agrees and a
# guard that never exits 2 look identical from the outside
# (docs/solutions/testing-patterns/dead-guards-report-coverage-they-do-not-have-2026-08-27.md).
#
# The contract is: the marker carries a full 40-character OID. `headRefOid` is
# always 40 characters, so a short SHA reaching the marker would parse fine and
# then compare unequal forever — /closeout would report divergence on a PR whose
# head never moved. A gate that cries wolf on an unchanged commit is a gate that
# gets clicked through.
#
# These tests extract the real sed script from closeout/SKILL.md and the real
# marker template from pre-merge/SKILL.md rather than restating either. That is
# the point: the suite fails when either half drifts from the other, which a
# hand-copied regex could not detect.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
closeout_skill="$repo_root/closeout/SKILL.md"
premerge_skill="$repo_root/pre-merge/SKILL.md"
guard_hook="$repo_root/git-guardrails-claude-code/scripts/block-dangerous-git.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

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

# --- Pull every copy of the contract out of the real files -------------------
#
# One extractor, called once per reading site. Each site is expected to carry
# the reader on a single physical line of the form
#
#     … | sed -n '<script>' | tail -1)
#
# so the same three-step split works on a fenced block inside a SKILL.md and on
# a live shell script alike. The helpers are functions rather than repeated
# pipelines because scripts/test-duplicate-guard-programs.sh is right about the
# reason: two copies of a reader inside one suite means mutating one leaves the
# other green.

# reader_line_of <file> — the physical line carrying the reviewed-at sed reader.
# grep's no-match status is absorbed rather than left to trip `set -e`: an empty
# result is a real answer here, and the FATALs below turn it into a message that
# names which site went missing. Without the `|| true` the suite aborted at this
# assignment with no output at all, which reads as a harness problem rather than
# as a deleted reader.
reader_line_of() { { grep "sed -n 's/[^']*reviewed-at" "$1" || true; } | head -1; }

# reader_expr_of <line> — the sed script that line pipes the PR body through.
# Absorbs grep's no-match status for the same reason reader_line_of does: an
# empty expression is the input the FATALs below are written to report on.
reader_expr_of() {
    { printf '%s' "$1" | grep -o "sed -n 's/[^']*reviewed-at[^']*'" || true; } \
        | sed "s/^sed -n '//; s/'\$//"
}

# reader_filter_of <line> — whatever the site pipes the sed output into:
# everything past the sed script's closing quote, minus the trailing ")" of the
# command substitution.
reader_filter_of() {
    printf '%s' "$1" | sed "s/.*'[[:space:]]*|[[:space:]]*//; s/)[[:space:]]*\$//"
}

# The canonical reader: /closeout Step 2.
reader_line="$(reader_line_of "$closeout_skill")"
reader_expr="$(reader_expr_of "$reader_line")"
reader_filter="$(reader_filter_of "$reader_line")"

# The second reader: the git-guardrails PreToolUse hook, which refuses a
# `gh pr merge` against a stale stamp. Same split, different file.
guard_line="$(reader_line_of "$guard_hook")"
guard_expr="$(reader_expr_of "$guard_line")"
guard_filter="$(reader_filter_of "$guard_line")"

# The marker template /pre-merge Phase 4 substitutes the reviewed SHA into.
writer_template="$(grep -o '<!-- reviewed-at: [^ ]* -->' "$premerge_skill" | head -1)"

if [[ -z "$reader_expr" ]]; then
    printf 'FATAL: no sed -n reviewed-at extraction found in %s\n' "$closeout_skill" >&2
    printf '       Either the reader moved or its shape changed; update this suite with it.\n' >&2
    exit 2
fi
if [[ -z "$guard_expr" ]]; then
    printf 'FATAL: no sed -n reviewed-at extraction found in %s\n' "$guard_hook" >&2
    printf '       The hook is the stamp reader that fires on a hand-typed or AFK "gh pr merge".\n' >&2
    printf '       If it moved, point this suite at it; if it was deleted, that gate is gone.\n' >&2
    exit 2
fi
if [[ -z "$writer_template" ]]; then
    printf 'FATAL: no reviewed-at marker template found in %s\n' "$premerge_skill" >&2
    printf '       Either the writer moved or its shape changed; update this suite with it.\n' >&2
    exit 2
fi

printf 'reader (closeout/SKILL.md):   %s\n' "$reader_expr"
printf 'reader filter:                %s\n' "$reader_filter"
printf 'reader (block-dangerous-git): %s\n' "$guard_expr"
printf 'reader filter:                %s\n' "$guard_filter"
printf 'writer (pre-merge/SKILL.md):  %s\n' "$writer_template"

# read_marker <<< body — run /closeout's own extraction over a PR body on stdin.
# The `| tail -1` is the one part of the reader not expressible inside the sed
# script, so it is replicated here rather than extracted. That replication is a
# restatement, which is exactly what this suite exists to avoid — so the first
# assertion below pins $reader_filter against it. Without that pin, switching
# the skill to `head -1` would leave the "newer stamp wins" test green while
# describing the opposite reader, and a stale SHA is the dangerous answer.
read_marker() { sed -n "$reader_expr" | tail -1; }

# pr_body <marker-line>... — a realistic PR body with prose either side of the
# stamp, so the reader is exercised against a whole body rather than one line.
# The bare "<!-- -->" on the first line is a deliberate decoy: real PR bodies
# contain other HTML comments, and the reader must not latch onto them.
#
# shellcheck disable=SC2016  # backticks here are literal markdown, not command substitution
pr_body() {
    printf '## Summary\n\nSome PR description with a <!-- --> comment nearby.\n\n## Review Currency\n\n'
    printf '%s\n' "$@"
    printf 'Reviewed by `/pre-merge`.\n\n## Test plan\n\n- ran it\n'
}

full_sha='0123456789abcdef0123456789abcdef01234567'   # 40 hex chars, like headRefOid

# -----------------------------------------------------------------------------

section "the reader is fully accounted for"

assert_eq 'tail -1' "$reader_filter" \
    "the post-sed filter is still 'tail -1', which read_marker replicates"

# -----------------------------------------------------------------------------

section "writer declares a full-SHA placeholder"

# Also covers the substitution itself: an unsubstituted template still contains
# the literal "<full-sha>" and cannot equal the expected marker, so a swapped or
# renamed placeholder fails here rather than surfacing later as a parse miss.
marker="${writer_template//<full-sha>/$full_sha}"
assert_eq "<!-- reviewed-at: $full_sha -->" "$marker" \
    "the <full-sha> placeholder substitutes into a well-formed marker"

# -----------------------------------------------------------------------------

section "round trip: what the writer emits is what the reader extracts"

extracted="$(pr_body "$marker" | read_marker)"
assert_eq "$full_sha" "$extracted" "reader returns exactly the SHA the writer wrote"
assert_eq 40 "${#extracted}" "extracted value is a full 40-character OID"

# -----------------------------------------------------------------------------

section "short SHAs are rejected, not silently accepted"

# A short SHA can never equal a 40-character headRefOid. Rejecting it routes
# /closeout to the graceful "no stamp found" branch instead of the "divergence"
# branch, which interrupts the user over a commit that never moved.
for width in 7 8 12 39; do
    short_marker="${writer_template//<full-sha>/${full_sha:0:$width}}"
    extracted="$(pr_body "$short_marker" | read_marker)"
    assert_eq "" "$extracted" "a ${width}-character SHA is not accepted as a stamp"
done

# -----------------------------------------------------------------------------

section "over-long and non-hex markers are rejected"

long_marker="${writer_template//<full-sha>/${full_sha}f}"   # 41 hex chars
extracted="$(pr_body "$long_marker" | read_marker)"
assert_eq "" "$extracted" "a 41-character value is rejected rather than truncated to 40"

junk_marker="${writer_template//<full-sha>/not-a-sha}"
extracted="$(pr_body "$junk_marker" | read_marker)"
assert_eq "" "$extracted" "a non-hex value is rejected"

extracted="$(pr_body 'No stamp here at all.' | read_marker)"
assert_eq "" "$extracted" "a body with no marker yields the empty 'no stamp found' result"

# -----------------------------------------------------------------------------

section "a duplicated stamp resolves to the newer SHA, never the stale one"

# /pre-merge specifies exactly one stamp per PR, but if a second is ever
# appended the reader must not settle on the earlier — a stale SHA is the
# dangerous answer, because it reports divergence that was already reviewed.
newer_sha='fedcba9876543210fedcba9876543210fedcba98'
stale_marker="$marker"
newer_marker="${writer_template//<full-sha>/$newer_sha}"
extracted="$(pr_body "$stale_marker" "$newer_marker" | read_marker)"
assert_eq "$newer_sha" "$extracted" "the last stamp in the body wins"

# -----------------------------------------------------------------------------

section "the guardrail hook reads the stamp the same way /closeout does"

# Byte equality, not "equivalent". Two regexes that accept the same strings
# today can diverge on the next edit, and the whole point of a third copy is
# that nobody will notice when it does. Equality here is also what lets the
# battery above stand for both readers: one expression, exercised once.
assert_eq "$reader_expr" "$guard_expr" \
    "block-dangerous-git.sh runs byte-identical sed to closeout/SKILL.md"
assert_eq 'tail -1' "$guard_filter" \
    "the hook's post-sed filter is 'tail -1' too, so a duplicated stamp resolves the same way"

# -----------------------------------------------------------------------------

section "the guardrail hook actually refuses a stale stamp"

# Everything above grades the hook's *reader*. A reader that agrees perfectly
# and a hook that never exits 2 are indistinguishable from the outside, which
# is the shape docs/solutions/testing-patterns/
# dead-guards-report-coverage-they-do-not-have-2026-08-27.md names. So these
# run the real script, with a stubbed `gh` on PATH, and assert on exit status.

hook_scratch="$(mktemp -d)"
cleanup() { rm -rf "$hook_scratch"; }
trap cleanup EXIT

stub_bin="$hook_scratch/bin"
mkdir -p "$stub_bin"

# make_gh_stub <body-file> <head-oid> — a `gh` that answers `pr view --json
# body,headRefOid` from disk and records its argv, so the selector the hook
# derived from the command line is checkable rather than assumed.
make_gh_stub() {
    local body_file="$1" head_oid="$2"
    cat > "$stub_bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$hook_scratch/gh-argv"
jq -n --rawfile b "$body_file" --arg h "$head_oid" '{body: \$b, headRefOid: \$h}'
STUB
    chmod +x "$stub_bin/gh"
    rm -f "$hook_scratch/gh-argv"
}

# run_hook <cwd> <command> [env-assignment...] — feed the hook a PreToolUse
# payload and report its exit status. Callers invoke this inside $( … ) to read
# the status, so the refusal text is parked in a FILE rather than a variable: an
# assignment made inside a command substitution dies with the subshell, and the
# first draft of this suite lost every stderr assertion that way while the exit
# codes it checked alongside them stayed green.
hook_stderr_file="$hook_scratch/hook-stderr"
run_hook() {
    local cwd="$1" cmd="$2"; shift 2
    local status=0
    ( cd "$cwd" && env PATH="$stub_bin:$PATH" "$@" \
        bash "$guard_hook" <<< "$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')" \
        > /dev/null 2> "$hook_stderr_file" ) || status=$?
    printf '%s' "$status"
}

# assert_contains <needle> <label> — grade the refusal text this run produced.
assert_contains() {
    local needle="$1" label="$2"
    if grep -qF -- "$needle" "$hook_stderr_file"; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected to contain: %q\n       stderr was: %q\n' \
            "$label" "$needle" "$(cat "$hook_stderr_file")"
        fail=$((fail + 1))
    fi
}

# A real repo with three commits, so the "how far past the stamp" figure the
# refusal prints is measured against real history rather than asserted.
fixture_repo="$hook_scratch/repo"
mkdir -p "$fixture_repo"
git -c init.defaultBranch=main init --quiet "$fixture_repo"
git -C "$fixture_repo" config user.email test@example.com
git -C "$fixture_repo" config user.name 'Contract Suite'
for n in 1 2 3; do
    printf 'line %s\n' "$n" >> "$fixture_repo/file.txt"
    git -C "$fixture_repo" add file.txt
    git -C "$fixture_repo" -c core.hooksPath=/dev/null commit --quiet -m "commit $n"
done
reviewed_oid="$(git -C "$fixture_repo" rev-parse HEAD~2)"
head_commit_oid="$(git -C "$fixture_repo" rev-parse HEAD)"

if [[ "${#reviewed_oid}" -ne 40 || "$reviewed_oid" == "$head_commit_oid" ]]; then
    printf 'FATAL: the fixture repo did not produce three distinct commits.\n' >&2
    printf '       Every assertion below would then compare a SHA against itself.\n' >&2
    exit 2
fi

body_stale="$hook_scratch/body-stale.md"
pr_body "${writer_template//<full-sha>/$reviewed_oid}" > "$body_stale"
body_current="$hook_scratch/body-current.md"
pr_body "${writer_template//<full-sha>/$head_commit_oid}" > "$body_current"
body_unstamped="$hook_scratch/body-unstamped.md"
pr_body 'No stamp here at all.' > "$body_unstamped"

# --- the refusal itself ---
make_gh_stub "$body_stale" "$head_commit_oid"
assert_eq 2 "$(run_hook "$fixture_repo" 'gh pr merge --squash')" \
    "a PR head two commits past its stamp is refused"
assert_contains "$reviewed_oid" "the refusal names the reviewed SHA"
assert_contains "$head_commit_oid" "the refusal names the PR head"

# The magnitude, not just the fact — /closeout shows a delta so the response can
# be proportional to it, and the hook has no interactive channel to show one later.
assert_contains "2 commit" "the refusal reports how far past the stamp the head is"

# The escape hatch has to be readable at the moment the block happens; naming it
# only in the script is a knowledge-in-the-head answer to a knowledge-in-the-world
# problem.
assert_contains "ALLOW_STALE_STAMP_MERGE" "the refusal names its own escape hatch"
assert_contains "/pre-merge" "the refusal names the re-review route"

# --- every fail-open path, because a gate that refuses wrongly gets deleted ---
make_gh_stub "$body_current" "$head_commit_oid"
assert_eq 0 "$(run_hook "$fixture_repo" 'gh pr merge --squash')" \
    "a stamp equal to the PR head is allowed through"

make_gh_stub "$body_unstamped" "$head_commit_oid"
assert_eq 0 "$(run_hook "$fixture_repo" 'gh pr merge --squash')" \
    "an unstamped PR is allowed — absence of a stamp is not evidence of an unreviewed diff"

make_gh_stub "$body_stale" "$head_commit_oid"
assert_eq 0 "$(run_hook "$fixture_repo" 'gh pr merge --squash' ALLOW_STALE_STAMP_MERGE=1)" \
    "ALLOW_STALE_STAMP_MERGE=1 is an escape hatch the refusal names"
assert_eq 0 "$(run_hook "$fixture_repo" 'gh pr view 4 --json body')" \
    "a gh command that is not 'pr merge' is untouched"
assert_eq 0 "$(run_hook "$fixture_repo" 'echo hello')" \
    "an unrelated command is untouched"

printf '#!/usr/bin/env bash\nexit 1\n' > "$stub_bin/gh"
chmod +x "$stub_bin/gh"
assert_eq 0 "$(run_hook "$fixture_repo" 'gh pr merge --squash')" \
    "a failing gh call fails open rather than blocking the merge"

# --- the selector the hook hands to gh ---
make_gh_stub "$body_current" "$head_commit_oid"
run_hook "$fixture_repo" 'gh pr merge 4821 --squash --delete-branch' > /dev/null
assert_eq 'pr view 4821 --json body,headRefOid' "$(cat "$hook_scratch/gh-argv")" \
    "an explicit PR number is passed through to gh, not silently replaced by the current branch"

make_gh_stub "$body_current" "$head_commit_oid"
run_hook "$fixture_repo" 'gh pr merge --squash' > /dev/null
assert_eq 'pr view --json body,headRefOid' "$(cat "$hook_scratch/gh-argv")" \
    "with no positional selector the hook lets gh resolve the current branch"

# A flag before the positional means the hook cannot tell a selector from a
# flag's value without re-authoring gh's flag table, which CLAUDE.md rule (a)
# forbids. It declines to guess and lets the command through, and the stub
# records that no lookup happened at all.
make_gh_stub "$body_stale" "$head_commit_oid"
assert_eq 0 "$(run_hook "$fixture_repo" 'gh pr merge --subject fix 4821')" \
    "an ambiguous selector fails open rather than checking the wrong PR"
assert_eq '' "$(cat "$hook_scratch/gh-argv" 2>/dev/null || true)" \
    "and it does not call gh at all in that case"

# --- the pre-existing patterns still block ---
assert_eq 2 "$(run_hook "$fixture_repo" 'git push --force origin main')" \
    "the dangerous-pattern list still refuses a force push"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
