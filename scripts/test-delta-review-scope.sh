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

# assert_fixture_committed <repo> <label> <before_count> <expected_new_commits> <file>...
#
# Checks the RESULT of a fixture-building subshell rather than the subshell's
# own exit status. `set -e` is suppressed inside the left operand of `||`
# (test-guards-can-fire.sh detector A), so `( … ) || fatal "…"` cannot report a
# failure that happens anywhere but the subshell's LAST command — an earlier
# `git commit` in the block could fail silently and this would still print
# green. Called after the subshell has already run, with no `||` attached to
# it, so a failure anywhere inside is caught here.
#
# A clean-working-tree check alone is not enough: if an earlier commit in the
# block fails (e.g. `git commit -m ''`, which git refuses), the file it staged
# stays staged and rides along into the NEXT `git add && git commit` in the
# block, which then succeeds and leaves nothing uncommitted — the failure
# leaves no dirt, only a commit graph with one commit too few. So the count of
# new commits reachable from HEAD is checked against what the block should have
# produced, and only then is the per-file presence in HEAD checked.
assert_fixture_committed() {
    local repo="$1" label="$2" before="$3" expected_new="$4"; shift 4
    local after; after="$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)"
    local got_new=$((after - before))
    [[ "$got_new" -eq "$expected_new" ]] \
        || fatal "$label: expected $expected_new new commit(s), HEAD gained $got_new (before=$before after=$after) — a commit in the block likely failed and its staged content merged into a later commit instead"
    local dirty; dirty="$(git -C "$repo" status --porcelain)"
    [[ -z "$dirty" ]] || fatal "$label: working tree not clean after the fixture ran:"$'\n'"$dirty"
    local f
    for f in "$@"; do
        git -C "$repo" cat-file -e "HEAD:$f" 2>/dev/null \
            || fatal "$label: $f is not present in HEAD, so its commit did not land"
    done
}

# assert_fixture_merged <repo> <label> — same idea, for the merge fixture: the
# meaningful result is that HEAD actually became a merge commit (two parents)
# whose first parent's tree really carries the "base: grew" content, not that
# the subshell's last command happened to exit 0.
assert_fixture_merged() {
    local repo="$1" label="$2"
    git -C "$repo" rev-parse -q --verify HEAD^2 >/dev/null \
        || fatal "$label: HEAD is not a merge commit (no second parent)"
    grep -q 'base grew' < <(git -C "$repo" show HEAD:base.txt 2>/dev/null) \
        || fatal "$label: base.txt at HEAD does not contain the post-stamp 'base: grew' commit's content"
    local dirty; dirty="$(git -C "$repo" status --porcelain)"
    [[ -z "$dirty" ]] || fatal "$label: working tree not clean after the merge fixture ran:"$'\n'"$dirty"
}

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

# A `git` that logs every argv it was called with, then execs the real git.
# (#348 review, finding 3): a mutation changing the scope block's
# `if [ -n "$REVIEWED_SHA" ]` to `if [ -n "$SCOPE_FROM" ]` keeps every
# string-shaped assertion above green, because `$SCOPE_FROM` was already set
# to `$BASE_REF` (always non-empty) two lines earlier, so the guard's
# `git merge-base --is-ancestor` call stops being conditioned on there being a
# stamp at all — it fires even with an empty `$REVIEWED_SHA`, and the "no
# stamp -> whole branch" outcome only happens to survive because that call
# then fails safely. Grepping the skill's prose for the string
# `$REVIEWED_SHA` would pin the term, not the property
# (docs/solutions/testing-patterns/a-planted-term-cannot-discriminate-meaning-2026-09-04.md);
# logging the real git process's argv pins the property directly: whether
# `merge-base --is-ancestor` was invoked at all.
real_git="$(command -v git)"
export REAL_GIT="$real_git"
cat > "$stub_bin/git" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GIT_STUB_ARGV_LOG:?}"
exec "${REAL_GIT:?}" "$@"
STUB
chmod +x "$stub_bin/git"

export PATH="$stub_bin:$PATH"
export GH_STUB_ARGV_LOG="$sandbox/gh-argv.log"
export GIT_STUB_ARGV_LOG="$sandbox/git-argv.log"
: > "$GIT_STUB_ARGV_LOG"

repo="$sandbox/repo"
mkdir -p "$repo"
before_count="$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)"
(
    cd "$repo" || exit 1
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
)
assert_fixture_committed "$repo" "fixture setup" "$before_count" 3 base.txt one.txt two.txt

stamp_sha="$(git -C "$repo" rev-parse HEAD)"   # the reviewed commit
before_count="$(git -C "$repo" rev-list --count HEAD)"
(
    cd "$repo" || exit 1
    printf 'three\n' > three.txt
    git add three.txt && git commit -q -m 'fix: three (after the stamp)'
    printf 'four\n' > four.txt
    git add four.txt && git commit -q -m 'fix: four (after the stamp)'
)
assert_fixture_committed "$repo" "fixture post-stamp commits" "$before_count" 2 three.txt four.txt
head_sha="$(git -C "$repo" rev-parse HEAD)"

# run_scope <body> — runs the extracted block in the fixture with BASE_REF=main
# and prints "<scope line>|<files the diff --stat names, sorted, space-joined>".
run_scope() {
    local body="$1" out files scope
    : > "$GH_STUB_ARGV_LOG"
    : > "$GIT_STUB_ARGV_LOG"
    out="$(cd "$repo" && GH_STUB_BODY="$body" BASE_REF=main bash -c "$scope_block" 2>&1)"
    # Exposed for callers that need the raw combined stdout+stderr rather than
    # the parsed "<scope>|<files>" pair (#348 review, finding 5's stderr-noise
    # assertion below).
    LAST_SCOPE_RAW="$out"
    scope="$(printf '%s\n' "$out" | grep '^review scope:' || true)"
    files="$(printf '%s\n' "$out" | grep -oE '^ [a-z0-9]+\.txt' | tr -d ' ' | sort | tr '\n' ' ' | sed 's/ $//')"
    printf '%s|%s' "$scope" "$files"
}

# stamped_body <sha>... — a PR body carrying one marker per argument, in the
# order given (earlier arg = earlier in the body). Mirrors
# test-review-currency-marker.sh's pr_body helper, which does the same for
# /closeout's reader.
stamped_body() {
    printf '## Summary\n\nbody\n\n## Review Currency\n\n'
    local sha
    for sha in "$@"; do
        printf '<!-- reviewed-at: %s -->\n' "$sha"
    done
    printf 'Reviewed.\n'
}

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
# #348 review, finding 3: the guard's stated purpose is to skip the ancestor
# check when there is no stamp, not merely to land on "whole branch" by some
# route. Pin that `merge-base --is-ancestor` itself never ran, from the real
# git process's own argv log, not from the skill's text.
if grep -q -- 'merge-base' "$GIT_STUB_ARGV_LOG"; then
    printf '  FAIL no stamp: git merge-base --is-ancestor ran even though there is no stamp to check (argv: %s)\n' "$(cat "$GIT_STUB_ARGV_LOG")"; fail=$((fail + 1))
else
    printf '  ok   no stamp: git merge-base --is-ancestor never ran (the ancestor check is skipped, not merely outrun)\n'; pass=$((pass + 1))
fi

# --- 2. Stamp behind HEAD, linear history → post-stamp delta ---------------------
section "stamp is an ancestor of HEAD with linear history after it: the delta is the subject"
assert_eq "review scope: post-stamp delta, from $stamp_sha|four.txt three.txt" \
    "$(run_scope "$(stamped_body "$stamp_sha")")" \
    "the diff names only the two post-stamp files, and the scope line names the stamped SHA"
# The control side of the same pin: when there IS a stamp, the ancestor check
# must actually run (a suite whose git shim never observed a merge-base call
# in any case would report "ok" above on a broken apparatus, not a working
# guard — docs/mutation-at-consumption.md's not-run/killed distinction).
if grep -q -- 'merge-base' "$GIT_STUB_ARGV_LOG"; then
    printf '  ok   stamp behind HEAD: git merge-base --is-ancestor ran to check it\n'; pass=$((pass + 1))
else
    printf '  FAIL stamp behind HEAD: git merge-base --is-ancestor never ran (argv: %s)\n' "$(cat "$GIT_STUB_ARGV_LOG")"; fail=$((fail + 1))
fi

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
# (#348 review, finding 5): dropping ` 2>/dev/null` from the ancestor check
# leaks git's `fatal: Not a valid object name '<ghost_sha>'` into the readout.
# The assertion above pins the DECISION (falls back to whole branch) but the
# mutation doesn't touch the decision — `git merge-base --is-ancestor` still
# fails and the `if` chain still falls through — so it survives that string
# check. Pin the separate property at the point of consumption: the combined
# output this case produces carries no fatal:/error: line.
run_scope "$(stamped_body "$ghost_sha")" > /dev/null
if [[ "$LAST_SCOPE_RAW" == *'fatal:'* || "$LAST_SCOPE_RAW" == *'error:'* ]]; then
    printf '  FAIL unresolvable stamp: readout leaked stderr noise:\n%s\n' "$LAST_SCOPE_RAW"; fail=$((fail + 1))
else
    printf '  ok   unresolvable stamp: readout carries no fatal:/error: line\n'; pass=$((pass + 1))
fi

# --- 5. Merge commit after the stamp → whole branch ------------------------------
section "a merge commit landed after the stamp: whole branch, so base's own changes are not the delta"
(
    cd "$repo" || exit 1
    git switch -q main
    printf 'base grew\n' >> base.txt
    git add base.txt && git commit -q -m 'base: grew'
    git switch -q feature
    git merge -q --no-edit main
)
assert_fixture_merged "$repo" "fixture merge"
merge_sha="$(git -C "$repo" rev-parse HEAD)"   # captured for the two-stamp fixture below
assert_eq "review scope: whole branch, from main" \
    "$(run_scope "$(stamped_body "$stamp_sha")" | cut -d'|' -f1)" \
    "a merge after the stamp falls back to the whole branch"

# --- 6. Round count from the Fix-Findings-Run line -------------------------------
section "/fix-findings' round count is read from the tree"
run_rounds() { (cd "$repo" && BASE_REF=main bash -c "$rounds_line; printf '%s' \"\$ROUNDS\""); }

assert_eq "0" "$(run_rounds)" "no Fix-Findings-Run line on the branch: zero rounds"
before_count="$(git -C "$repo" rev-list --count HEAD)"
(
    cd "$repo" || exit 1
    printf 'r1a\n' > r1a.txt && git add r1a.txt \
        && git commit -q -m "$(printf 'fix: finding 1\n\nFix-Findings-Run: 20260904T200000Z')"
    printf 'r1b\n' > r1b.txt && git add r1b.txt \
        && git commit -q -m "$(printf 'fix: finding 3\n\nFix-Findings-Run: 20260904T200000Z')"
)
assert_fixture_committed "$repo" "fixture round-1 commits" "$before_count" 2 r1a.txt r1b.txt
r1a_sha="$(git -C "$repo" rev-parse HEAD~1)"   # the r1a commit, one before r1b at HEAD; captured for the two-stamp fixture below
assert_eq "1" "$(run_rounds)" "two fixer commits from one run count as one round"
before_count="$(git -C "$repo" rev-list --count HEAD)"
(
    cd "$repo" || exit 1
    printf 'r2\n' > r2.txt && git add r2.txt \
        && git commit -q -m "$(printf 'fix: finding 2\n\nFix-Findings-Run: 20260904T213000Z')"
)
assert_fixture_committed "$repo" "fixture round-2 commit" "$before_count" 1 r2.txt
assert_eq "2" "$(run_rounds)" "a fixer commit from a second run makes it two rounds"
before_count="$(git -C "$repo" rev-list --count HEAD)"
(
    cd "$repo" || exit 1
    printf 'plain\n' > plain.txt && git add plain.txt \
        && git commit -q -m 'chore: mentions Fix-Findings-Run: 20260904T220000Z mid-line, not as a trailer line'
)
assert_fixture_committed "$repo" "fixture hand commit" "$before_count" 1 plain.txt
assert_eq "2" "$(run_rounds)" "a mid-line mention is not a trailer line and does not count"

# --- 7. Two stamps in the body → the last one wins -------------------------------
section "two stamps in the body: the last one wins, and the two decisions differ observably (#348 review, finding 5)"
# (#348 review, finding 5): dropping ` | tail -1` from the stamp-reading
# pipeline is untested here (test-review-currency-marker.sh's "a duplicated
# stamp resolves to the newer SHA, never the stale one" case covers /closeout's
# reader, not this one). $merge_sha and $r1a_sha are both real ancestors of
# HEAD, in that commit order, so the newer stamp's diff is missing r1a.txt
# relative to the older stamp's diff — a wrong pick (first stamp, or falling
# back to the whole branch) is observable in the file set, not just the SHA.
assert_eq "review scope: post-stamp delta, from $r1a_sha|plain.txt r1b.txt r2.txt" \
    "$(run_scope "$(stamped_body "$merge_sha" "$r1a_sha")")" \
    "an older stamp above a newer one resolves SCOPE_FROM to the newer, and its diff excludes the older-but-still-post-stamp r1a.txt"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
