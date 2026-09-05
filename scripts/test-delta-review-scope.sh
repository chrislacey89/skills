#!/usr/bin/env bash
# test-delta-review-scope.sh — contract test for the review-scope decision
# /pre-merge Phase 1 step 4 documents, and the round count /fix-findings'
# next-step menu reads (#347).
#
# The incident: /fix-findings handed off to a /pre-merge re-run that re-read the
# whole branch with fresh reviewers, Phase 4's minimum-findings guard then
# demanded four findings on anything over 50 lines, and the loop had no exit but
# the human giving up — skills #345 merged four unreviewed fix commits past its
# stamp after counting its own rounds to five; matlock #140 merged three.
# #347 makes the re-run's subject the post-stamp delta, decided from branch
# state, and makes the round count something git reports rather than something
# the controller remembers.
#
# Both claims are executable prose in a SKILL.md, so both are RUN here, extracted
# verbatim from the skill rather than restated, against a real git repository
# and a stubbed `gh` that records what it was asked. Each branch state the skill
# names as a fallback is a fixture below; a state the block classifies
# differently from the prose fails.
#
# Lessons carried from test-documented-git-commands.sh's header apply: assert
# the answer (which files the diff names), not the presence of its parts; give
# the fixture every state the fault needs (an ancestor stamp, a non-ancestor
# stamp, a merge after the stamp) rather than only the happy one.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
premerge_skill="$repo_root/pre-merge/SKILL.md"
fixfindings_skill="$repo_root/fix-findings/SKILL.md"

pass=0
fail=0

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

section() { printf '\n== %s\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 1; }

# --- Extract the two blocks from the skills ---------------------------------

# The scope block: from the stamp read to the log line, inside Phase 1 step 4's
# fence. Anchored on the first and last command rather than on a marker comment,
# so a rewrite that drops either line fails here instead of shrinking the test.
scope_block="$(awk '
    /REVIEWED_SHA=\$\(gh pr list --head/ { on = 1 }
    on { sub(/^   /, ""); print }
    on && /git log --oneline "\$SCOPE_FROM\.\.HEAD"/ { exit }
' "$premerge_skill")"
[[ -n "$scope_block" ]] || fatal "no scope block found in $premerge_skill"
# A string test rather than piping into a quiet grep: under pipefail a ban on that shape passes
# precisely when the banned thing is present (test-pipefail-safe-matchers.sh).
# shellcheck disable=SC2016  # the pattern is the skill's literal text — $REVIEWED_SHA is markdown being matched, not an expansion
[[ "$scope_block" == *'SCOPE_FROM="$REVIEWED_SHA"'* ]] \
    || fatal "scope block extracted from $premerge_skill does not assign SCOPE_FROM from the stamp"

# The round-count line from /fix-findings' next-step menu.
# shellcheck disable=SC2016  # the grep pattern is the skill's literal text — $(git log is markdown being matched, not a command substitution
rounds_line="$(grep -m1 '^ROUNDS=\$(git log' "$fixfindings_skill" || true)"
[[ -n "$rounds_line" ]] || fatal "no ROUNDS= line found in $fixfindings_skill"

printf 'scope block (%s lines) and rounds line extracted\n' "$(printf '%s\n' "$scope_block" | grep -c .)"

# --- Fixture ------------------------------------------------------------------

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# A `gh` that answers `pr list ... -q '.[0].body // ""'` with whatever body the
# case sets, and records its argv so the test can assert the block asked for the
# body rather than getting it some other way.
stub_bin="$sandbox/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_STUB_ARGV_LOG:?}"
printf '%s' "${GH_STUB_BODY-}"
STUB
chmod +x "$stub_bin/gh"
export PATH="$stub_bin:$PATH"
export GH_STUB_ARGV_LOG="$sandbox/gh-argv.log"

repo="$sandbox/repo"
mkdir -p "$repo"
(
    cd "$repo"
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
) || fatal "fixture setup failed"

stamp_sha="$(git -C "$repo" rev-parse HEAD)"   # the reviewed commit
(
    cd "$repo"
    printf 'three\n' > three.txt
    git add three.txt && git commit -q -m 'fix: three (after the stamp)'
    printf 'four\n' > four.txt
    git add four.txt && git commit -q -m 'fix: four (after the stamp)'
) || fatal "fixture post-stamp commits failed"
head_sha="$(git -C "$repo" rev-parse HEAD)"

# run_scope <body> — runs the extracted block in the fixture with BASE_REF=main
# and prints "<scope line>|<files the diff --stat names, sorted, space-joined>".
run_scope() {
    local body="$1" out files scope
    : > "$GH_STUB_ARGV_LOG"
    out="$(cd "$repo" && GH_STUB_BODY="$body" BASE_REF=main bash -c "$scope_block" 2>&1)"
    scope="$(printf '%s\n' "$out" | grep '^review scope:' || true)"
    files="$(printf '%s\n' "$out" | grep -oE '^ [a-z]+\.txt' | tr -d ' ' | sort | tr '\n' ' ' | sed 's/ $//')"
    printf '%s|%s' "$scope" "$files"
}

stamped_body() { printf '## Summary\n\nbody\n\n## Review Currency\n\n<!-- reviewed-at: %s -->\nReviewed.\n' "$1"; }

# --- 1. No stamp → whole branch -------------------------------------------------
section "no stamp: a first review reads the whole branch"
assert_eq "review scope: whole branch, from main|four.txt one.txt three.txt two.txt" \
    "$(run_scope '## Summary'$'\n''no stamp here')" \
    "no stamp in the body: scope is the whole branch and the diff names every branch file"
if grep -q -- '--json body' "$GH_STUB_ARGV_LOG"; then
    printf '  ok   the block asked gh for the PR body\n'; pass=$((pass + 1))
else
    printf '  FAIL the block never asked gh for the PR body (argv: %s)\n' "$(cat "$GH_STUB_ARGV_LOG")"; fail=$((fail + 1))
fi

# --- 2. Stamp behind HEAD, linear history → post-stamp delta ---------------------
section "stamp is an ancestor of HEAD with linear history after it: the delta is the subject"
assert_eq "review scope: post-stamp delta, from $stamp_sha|four.txt three.txt" \
    "$(run_scope "$(stamped_body "$stamp_sha")")" \
    "the diff names only the two post-stamp files, and the scope line names the stamped SHA"

# --- 3. Stamp == HEAD → whole branch --------------------------------------------
section "stamp equals HEAD: nothing new to scope to, whole branch"
assert_eq "review scope: whole branch, from main" \
    "$(run_scope "$(stamped_body "$head_sha")" | cut -d'|' -f1)" \
    "a stamp equal to HEAD falls back to the whole branch"

# --- 4. Stamp not an ancestor (rewritten away) → whole branch -------------------
section "stamp is not an ancestor of HEAD (force-push rewrote it): whole branch"
ghost_sha="$(printf '%040d' 7)"
assert_eq "review scope: whole branch, from main" \
    "$(run_scope "$(stamped_body "$ghost_sha")" | cut -d'|' -f1)" \
    "an unresolvable stamp falls back to the whole branch rather than aborting"

# --- 5. Merge commit after the stamp → whole branch ------------------------------
section "a merge commit landed after the stamp: whole branch, so base's own changes are not the delta"
(
    cd "$repo"
    git switch -q main
    printf 'base grew\n' >> base.txt
    git add base.txt && git commit -q -m 'base: grew'
    git switch -q feature
    git merge -q --no-edit main
) || fatal "fixture merge failed"
assert_eq "review scope: whole branch, from main" \
    "$(run_scope "$(stamped_body "$stamp_sha")" | cut -d'|' -f1)" \
    "a merge after the stamp falls back to the whole branch"

# --- 6. Round count from the Fix-Findings-Run line -------------------------------
section "/fix-findings' round count is read from the tree"
run_rounds() { (cd "$repo" && BASE_REF=main bash -c "$rounds_line; printf '%s' \"\$ROUNDS\""); }

assert_eq "0" "$(run_rounds)" "no Fix-Findings-Run line on the branch: zero rounds"
(
    cd "$repo"
    printf 'r1a\n' > r1a.txt && git add r1a.txt \
        && git commit -q -m "$(printf 'fix: finding 1\n\nFix-Findings-Run: 20260904T200000Z')"
    printf 'r1b\n' > r1b.txt && git add r1b.txt \
        && git commit -q -m "$(printf 'fix: finding 3\n\nFix-Findings-Run: 20260904T200000Z')"
) || fatal "fixture round-1 commits failed"
assert_eq "1" "$(run_rounds)" "two fixer commits from one run count as one round"
(
    cd "$repo"
    printf 'r2\n' > r2.txt && git add r2.txt \
        && git commit -q -m "$(printf 'fix: finding 2\n\nFix-Findings-Run: 20260904T213000Z')"
) || fatal "fixture round-2 commit failed"
assert_eq "2" "$(run_rounds)" "a fixer commit from a second run makes it two rounds"
(
    cd "$repo"
    printf 'plain\n' > plain.txt && git add plain.txt \
        && git commit -q -m 'chore: mentions Fix-Findings-Run: 20260904T220000Z mid-line, not as a trailer line'
) || fatal "fixture hand commit failed"
assert_eq "2" "$(run_rounds)" "a mid-line mention is not a trailer line and does not count"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
