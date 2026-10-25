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

# A caller that reached this suite via a git hook (pre-push, run from a
# worktree) has GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE set in its environment.
# The scratch-repo `git init` below would inherit them and re-initialize the
# real repository instead, writing `core.bare=true` into its shared config.
# Unset before any git call.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

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

# The scope block: from the backend question to the log line, inside Phase 1
# step 4's fence. Anchored on the first and last command rather than on a marker
# comment, so a rewrite that drops either line fails here instead of shrinking
# the test. The block opens by asking `sidecar.sh backend stamp` where the stamp
# lives (#521), so its bundled-path placeholder is pointed at the canonical
# script; every arm below then runs the real routing rule, not a stand-in.
sidecar_sh="$repo_root/init-pipeline/scripts/sidecar.sh"
scope_block="$(awk '
    /^4\. \*\*Decide the scope/ { step = 1 }
    step && /^   SC=".*references\/sidecar\.sh"$/ { on = 1 }
    on { sub(/^   /, ""); print }
    on && /git log --oneline "\$SCOPE_FROM\.\.HEAD"/ { exit }
' "$premerge_skill")"
[[ -n "$scope_block" ]] || fatal "no scope block found in $premerge_skill"
scope_block="${scope_block//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
[[ "$scope_block" == *"$sidecar_sh"* ]] \
    || fatal "scope block's sidecar.sh placeholder was not substituted"
# shellcheck disable=SC2016  # the pattern is the skill's literal text
[[ "$scope_block" == *'REVIEWED_SHA=$(gh pr list --head'* ]] \
    || fatal "scope block extracted from $premerge_skill no longer reads the PR body on the github backend"
# shellcheck disable=SC2016
[[ "$scope_block" == *'stamp read "$(git branch --show-current)"'* ]] \
    || fatal "scope block extracted from $premerge_skill no longer reads the sidecar stamp on the sidecar backend"
# A string test rather than piping into a quiet grep: under pipefail a ban on that shape passes
# precisely when the banned thing is present (test-pipefail-safe-matchers.sh).
# shellcheck disable=SC2016  # the pattern is the skill's literal text — $REVIEWED_SHA is markdown being matched, not an expansion
[[ "$scope_block" == *'SCOPE_FROM="$REVIEWED_SHA"'* ]] \
    || fatal "scope block extracted from $premerge_skill does not assign SCOPE_FROM from the stamp"

# The round-count line from /fix-findings' next-step menu.
# shellcheck disable=SC2016  # the grep pattern is the skill's literal text — $(git log is markdown being matched, not a command substitution
rounds_line="$(grep -m1 '^ROUNDS=\$(git log' "$fixfindings_skill" || true)"
[[ -n "$rounds_line" ]] || fatal "no ROUNDS= line found in $fixfindings_skill"

# The fold block from Phase 4's handoff (#566): from its BASE_REF guard to the
# `fi` that closes the abort arm. Run in section 11 rather than restated, so a
# rewrite that rebases onto the base's tip instead of the fork point fails there.
fold_block="$(awk '
    /^: "\$\{BASE_REF:\?derive it with the Phase 1 step 3 block/ { on = 1 }
    on { print }
    on && /^fi$/ { exit }
' "$premerge_skill")"
[[ "$fold_block" == *'git rebase -q -i --autosquash'* ]] || fatal "no fold block found in $premerge_skill"

# The fixup-target block from /fix-findings Step 1 item 5 (#566), de-indented
# out of its list item. Section 12 runs it.
fixup_target_block="$(awk '
    /^   FIXUP_TARGET=\$\(git (-c [A-Za-z.]+=[a-z]+ )*blame/ { on = 1 }
    on { sub(/^   /, ""); print }
    on && /\|\| FIXUP_TARGET=$/ { exit }
' "$fixfindings_skill")"
[[ "$fixup_target_block" == *'|| FIXUP_TARGET='* ]] || fatal "no FIXUP_TARGET block found in $fixfindings_skill"

printf 'scope block (%s lines) and rounds line extracted\n' "$(printf '%s\n' "$scope_block" | grep -c .)"

# --- Fixture ------------------------------------------------------------------

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# A `gh` that answers `pr list --head feature --json body -q '.[0].body // ""'`
# with whatever body the case sets, and records its argv so the test can
# assert the block asked for the body rather than getting it some other way.
#
# (#348 review, finding 6): a stub that answers with the configured body
# regardless of argv lets `grep -q -- '--json body' "$GH_STUB_ARGV_LOG"` pass
# on any call carrying that flag — `gh pr view 1 --json body` (a different
# PR's body entirely) logs a line containing `--json body` too, so the
# assertion cannot tell "read this branch's PR body" from any other call
# shaped like it. Pinning the string `--json body` pins a flag, not the
# property (a-planted-term-cannot-discriminate-meaning-2026-09-04.md). The
# fixture's current branch is always `feature` (set at fixture setup below and
# restored after the merge fixture), so the stub answers with the configured
# body only for that exact call shape; anything else — the wrong branch, the
# wrong subcommand, a missing `--head` — gets nothing back. A block that asks
# the wrong question then gets no stamp and falls back to the whole branch,
# which the decision assertions in cases 2–7 below already catch (a stamp
# that should have produced "post-stamp delta" instead reads "whole branch").
# That turns the existing battery into the property check, rather than adding
# a second hand-maintained restatement of it.
stub_bin="$sandbox/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_STUB_ARGV_LOG:?}"
case "$*" in
    "pr list --head feature --json body"*)
        printf '%s' "${GH_STUB_BODY-}"
        ;;
    *)
        printf '%s\n' "$*" >> "${GH_STUB_ARGV_MISS_LOG:?}"
        ;;
esac
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
# The GitHub arm runs with no sidecar anywhere, so `backend stamp` answers
# github because nothing resolves, the way it does on a project that never ran
# `sidecar.sh init`. The sidecar arm (section 9) builds its own.
export SKILL_KIT_SIDECAR_ROOT="$sandbox/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$sandbox/archive"
export GH_STUB_ARGV_LOG="$sandbox/gh-argv.log"
export GH_STUB_ARGV_MISS_LOG="$sandbox/gh-argv-miss.log"
export GIT_STUB_ARGV_LOG="$sandbox/git-argv.log"
: > "$GIT_STUB_ARGV_LOG"
: > "$GH_STUB_ARGV_MISS_LOG"

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
    : > "$GH_STUB_ARGV_MISS_LOG"
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
# (#348 review, finding 6): named `pr list`, `--head feature`, and `--json body`
# together, not `--json body` alone, so a call for a different branch's PR (or
# a different gh subcommand) that happens to carry the same flag does not
# satisfy this. The stub above is the property check that actually
# discriminates the wrong call from the right one — a mismatch gets no body
# back and the decision assertions in cases 2-7 catch the fallout — this
# assertion documents the shape of the call the stub requires.
if grep -q -- 'pr list --head feature --json body' "$GH_STUB_ARGV_LOG"; then
    printf '  ok   the block asked gh pr list --head <this branch> --json body for the PR body\n'; pass=$((pass + 1))
else
    printf '  FAIL the block never asked gh pr list --head <this branch> --json body (argv: %s)\n' "$(cat "$GH_STUB_ARGV_LOG")"; fail=$((fail + 1))
fi
if [[ -s "$GH_STUB_ARGV_MISS_LOG" ]]; then
    printf '  FAIL the block made a gh call the stub did not recognize as "this branch'\''s PR body" (miss log: %s)\n' "$(cat "$GH_STUB_ARGV_MISS_LOG")"; fail=$((fail + 1))
else
    printf '  ok   no misfired gh calls (every call matched the expected shape)\n'; pass=$((pass + 1))
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

# --- 8. The pointer sites' target resolves ---------------------------------------
# Finding 4 of #348's review replaced two short restatements of the fallback
# list with pointers at "Phase 1 step 4". A pointer cannot drift short, but its
# breaker showed the target is held by nothing: renumber the step and every
# pointer dangles, green. This pins the structural half — the numbered anchor
# exists exactly once and each pointer names it — and leaves the meaning half
# (that the target still names four states) to a reader, which is the ceiling
# docs/solutions/testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md
# records for prose claims.
section "the 'Phase 1 step 4' pointer sites resolve to one numbered anchor (#348 compound, sweep-commits fifth observation)"
step4_count="$(grep -c '^4\. \*\*Decide the scope' "$premerge_skill" || true)"
assert_eq "1" "$step4_count" "pre-merge/SKILL.md carries exactly one step '4. **Decide the scope' anchor"
for site in "$fixfindings_skill" "$repo_root/SYSTEM-OVERVIEW.md"; do
    folded="$(tr '\n' ' ' < "$site")"
    if [[ "$folded" == *"Phase 1 step 4 names"* ]]; then
        printf '  ok   %s points at Phase 1 step 4\n' "${site#"$repo_root"/}"
        pass=$((pass + 1))
    else
        printf '  FAIL %s no longer points at Phase 1 step 4 — the pointer form was the fix for restating the list short\n' "${site#"$repo_root"/}"
        fail=$((fail + 1))
    fi
done

# --- 9. The sidecar backend ---------------------------------------------------
# The same decision, with the stamp in <sidecar>/reviews/ instead of the PR body
# (#521). A fresh fixture with the shape cases 1-5 used, and a sidecar whose
# forge.write is [] (owned, no remote: forge none), so `backend stamp` answers
# sidecar. The gh stub is armed with a PR-body stamp that would pick a
# DIFFERENT scope, so a block that read the PR body on this backend is caught
# by the file set, not only by the argv log.
section "sidecar backend: the stamp is read from the sidecar, never the PR body"

export GIT_CONFIG_GLOBAL="$sandbox/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Delta Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "delta@example.com"

repo2="$sandbox/repo2"
mkdir -p "$repo2"
before_count=0
(
    cd "$repo2" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base2\n' > base.txt
    git add base.txt && git commit -q -m 'base (sidecar fixture)'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
)
assert_fixture_committed "$repo2" "sidecar fixture setup" "$before_count" 3 base.txt one.txt two.txt
first_sha2="$(git -C "$repo2" rev-parse HEAD~1)"
stamp_sha2="$(git -C "$repo2" rev-parse HEAD)"
before_count="$(git -C "$repo2" rev-list --count HEAD)"
(
    cd "$repo2" || exit 1
    printf 'three\n' > three.txt
    git add three.txt && git commit -q -m 'fix: three (after the stamp)'
    printf 'four\n' > four.txt
    git add four.txt && git commit -q -m 'fix: four (after the stamp)'
)
assert_fixture_committed "$repo2" "sidecar fixture post-stamp commits" "$before_count" 2 three.txt four.txt
head_sha2="$(git -C "$repo2" rev-parse HEAD)"

(cd "$repo2" && bash "$sidecar_sh" init --name delta --mode owned --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || fatal "sidecar init failed in the sidecar fixture"
assert_eq "sidecar" "$(cd "$repo2" && bash "$sidecar_sh" backend stamp)" \
    "fixture precondition: backend stamp answers sidecar"

# sidecar_stamp <sha|clear> — set or clear this fixture's stamp through the verb.
sidecar_stamp() {
    if [[ "$1" == clear ]]; then
        (cd "$repo2" && bash "$sidecar_sh" stamp clear feature) || fatal "stamp clear failed"
    else
        (cd "$repo2" && bash "$sidecar_sh" stamp write feature "$1" >/dev/null) || fatal "stamp write $1 failed"
    fi
}

# run_scope2 — run_scope against the sidecar fixture. The PR body the gh stub
# would hand back carries a stamp at $first_sha2, whose delta would add two.txt.
run_scope2() {
    local out files scope
    : > "$GH_STUB_ARGV_LOG"
    : > "$GIT_STUB_ARGV_LOG"
    out="$(cd "$repo2" && GH_STUB_BODY="$(stamped_body "$first_sha2")" BASE_REF=main bash -c "$scope_block" 2>&1)"
    LAST_SCOPE_RAW="$out"
    scope="$(printf '%s\n' "$out" | grep '^review scope:' || true)"
    files="$(printf '%s\n' "$out" | grep -oE '^ [a-z0-9]+\.txt' | tr -d ' ' | sort | tr '\n' ' ' | sed 's/ $//')"
    printf '%s|%s' "$scope" "$files"
}

sidecar_stamp clear
assert_eq "review scope: whole branch, from main|four.txt one.txt three.txt two.txt" \
    "$(run_scope2)" \
    "sidecar, no stamp: scope is the whole branch"
if grep -q -- 'merge-base' "$GIT_STUB_ARGV_LOG"; then
    printf '  FAIL sidecar, no stamp: git merge-base --is-ancestor ran with no stamp to check\n'; fail=$((fail + 1))
else
    printf '  ok   sidecar, no stamp: git merge-base --is-ancestor never ran\n'; pass=$((pass + 1))
fi

sidecar_stamp "$stamp_sha2"
assert_eq "review scope: post-stamp delta, from $stamp_sha2|four.txt three.txt" \
    "$(run_scope2)" \
    "sidecar, stamp behind HEAD: the delta is the two post-stamp files, not the PR body's three"
if [[ -s "$GH_STUB_ARGV_LOG" ]]; then
    printf '  FAIL sidecar backend: the block called gh (argv: %s)\n' "$(cat "$GH_STUB_ARGV_LOG")"; fail=$((fail + 1))
else
    printf '  ok   sidecar backend: the block never called gh\n'; pass=$((pass + 1))
fi

sidecar_stamp "$head_sha2"
assert_eq "review scope: whole branch, from main" \
    "$(run_scope2 | cut -d'|' -f1)" \
    "sidecar, stamp equals HEAD: whole branch"

sidecar_stamp "$(printf '%040d' 7)"
assert_eq "review scope: whole branch, from main" \
    "$(run_scope2 | cut -d'|' -f1)" \
    "sidecar, stamp not an ancestor: whole branch"
if [[ "$LAST_SCOPE_RAW" == *'fatal:'* || "$LAST_SCOPE_RAW" == *'error:'* ]]; then
    printf '  FAIL sidecar, unresolvable stamp: readout leaked stderr noise:\n%s\n' "$LAST_SCOPE_RAW"; fail=$((fail + 1))
else
    printf '  ok   sidecar, unresolvable stamp: readout carries no fatal:/error: line\n'; pass=$((pass + 1))
fi

(
    cd "$repo2" || exit 1
    git switch -q main
    printf 'base grew\n' >> base.txt
    git add base.txt && git commit -q -m 'base: grew'
    git switch -q feature
    git merge -q --no-edit main
)
assert_fixture_merged "$repo2" "sidecar fixture merge"
sidecar_stamp "$stamp_sha2"
assert_eq "review scope: whole branch, from main" \
    "$(run_scope2 | cut -d'|' -f1)" \
    "sidecar, merge after the stamp: whole branch"
assert_eq "" "$(git -C "$repo2" status --porcelain)" \
    "sidecar backend: the scope read and every stamp verb left the project tree clean"

# --- 10. A failed backend -----------------------------------------------------

# #530: `backend stamp` that exits nonzero prints nothing. A block written as
# `if [ "$(backend)" = sidecar ]; then … else <gh> fi` reads that as github and
# reads the PR body; on a guest repo the github path is the harmful one. The
# block must abort instead: nonzero exit, no scope line, no gh call. The failure
# is real, not stubbed: the only sidecar under the root has a corrupt
# sidecar.json, which no readable sidecar outranks, so `backend` refuses.
section "failed backend: the scope block aborts rather than taking the gh path"
broken_root="$sandbox/broken-sidecars"
mkdir -p "$broken_root/broken"
printf '{"keys": [' > "$broken_root/broken/sidecar.json"
(cd "$repo" && SKILL_KIT_SIDECAR_ROOT="$broken_root" bash "$sidecar_sh" backend stamp >/dev/null 2>&1)
assert_eq 1 "$?" "fixture precondition: backend stamp exits 1 under the broken root"
: > "$GH_STUB_ARGV_LOG"
failed_out="$(cd "$repo" && SKILL_KIT_SIDECAR_ROOT="$broken_root" GH_STUB_BODY="<!-- reviewed-at: $stamp_sha -->" \
    BASE_REF=main bash -c "$scope_block" 2>&1)"
failed_rc=$?
assert_eq 1 "$failed_rc" "failed backend: the scope block exits 1"
assert_eq "" "$(printf '%s\n' "$failed_out" | grep '^review scope:' || true)" \
    "failed backend: the scope block prints no review scope"
assert_eq "" "$(cat "$GH_STUB_ARGV_LOG")" "failed backend: the scope block never called gh"
case "$failed_out" in
    *"scope aborted"*) assert_eq ok ok "failed backend: the abort is named on stderr" ;;
    *) assert_eq "scope aborted ..." "$failed_out" "failed backend: the abort is named on stderr" ;;
esac

# --- 11. A history-only rewrite of the reviewed tree (#566) ------------------
# The fold: review fixes are committed as `fixup!` commits, the re-run reviews
# them and stamps the fixup head, and an autosquash folds each fix into the
# commit it corrects. Every SHA changes and the tree does not, so the stamp is
# no longer an ancestor of HEAD while HEAD still carries exactly the reviewed
# content. Case 4's force-push fallback must not fire on that: re-reviewing an
# unchanged tree is the Shape-Shifting Review the fold would otherwise cost.
# The control is the same rewrite with one byte of content changed, which must
# still take the whole-branch fallback.
section "history-only rewrite: the reviewed tree survives an autosquash, and nothing is re-reviewed"
repo3="$sandbox/repo3"
mkdir -p "$repo3"
before_count=0
(
    cd "$repo3" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base (fold fixture)'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
    printf 'one, fixed\n' > one.txt
    git add one.txt && git commit -q --fixup=HEAD~1 -m 'Fix-Findings-Run: 20261025T000000Z'
    git switch -q main
    printf 'base moved\n' > moved.txt
    git add moved.txt && git commit -q -m 'base: moved after the branch forked'
    git switch -q feature
)
assert_fixture_committed "$repo3" "fold fixture setup" "$before_count" 4 base.txt one.txt two.txt
reviewed_sha3="$(git -C "$repo3" rev-parse HEAD)"   # the re-run stamped the fixup head
# The base moved after the fork, so a fold onto main's tip would change the tree.
fold_out="$(cd "$repo3" && BASE_REF=main bash -c "$fold_block" 2>&1)"
case "$fold_out" in
    folded:*) assert_eq ok ok "the documented fold block reports the fold" ;;
    *) assert_eq "folded: ..." "$fold_out" "the documented fold block reports the fold" ;;
esac
assert_eq "2" "$(git -C "$repo3" rev-list --count main..HEAD)" \
    "fold fixture precondition: the autosquash folded three commits into two"
assert_eq "$(git -C "$repo3" rev-parse "$reviewed_sha3^{tree}")" "$(git -C "$repo3" rev-parse 'HEAD^{tree}')" \
    "fold fixture precondition: the fold left the reviewed tree unchanged"

run_scope3() {
    local out files scope
    : > "$GH_STUB_ARGV_LOG"
    out="$(cd "$repo3" && GH_STUB_BODY="$(stamped_body "$1")" BASE_REF=main bash -c "$scope_block" 2>&1)"
    LAST_SCOPE_RAW="$out"
    scope="$(printf '%s\n' "$out" | grep '^review scope:' || true)"
    files="$(printf '%s\n' "$out" | grep -oE '^ [a-z0-9]+\.txt' | tr -d ' ' | sort | tr '\n' ' ' | sed 's/ $//')"
    printf '%s|%s' "$scope" "$files"
}

assert_eq "review scope: none, history-only rewrite — HEAD carries the tree reviewed at $reviewed_sha3|" \
    "$(run_scope3 "$reviewed_sha3")" \
    "a stamp rewritten away with its tree intact: no review scope, and the diff names no file"
if [[ "$LAST_SCOPE_RAW" == *'fatal:'* || "$LAST_SCOPE_RAW" == *'error:'* ]]; then
    printf '  FAIL history-only rewrite: readout leaked stderr noise:\n%s\n' "$LAST_SCOPE_RAW"; fail=$((fail + 1))
else
    printf '  ok   history-only rewrite: readout carries no fatal:/error: line\n'; pass=$((pass + 1))
fi

(
    cd "$repo3" || exit 1
    printf 'two, changed in the rewrite\n' > two.txt
    git add two.txt && git commit -q --amend --no-edit
)
assert_eq "review scope: whole branch, from main" \
    "$(run_scope3 "$reviewed_sha3" | cut -d'|' -f1)" \
    "control: a rewrite that also changed content still falls back to the whole branch"

# A fixup made against a later commit's version of a line conflicts when the
# autosquash moves it next to its target. The block must abort and leave the
# branch exactly where it was, not stop mid-rebase.
branch_commits3="$(git -C "$repo3" rev-list --reverse main..HEAD || true)"
first_commit3="${branch_commits3%%$'\n'*}"
[[ -n "$first_commit3" ]] || fatal "conflict fixture: no branch commit to make a fixup of"
(
    cd "$repo3" || exit 1
    printf 'one, rewritten by a later commit\n' > one.txt
    git add one.txt && git commit -q -m 'feature: rewrite one'
    printf 'one, fixed again\n' > one.txt
    git add one.txt && git commit -q --fixup="$first_commit3"
)
conflict_head="$(git -C "$repo3" rev-parse HEAD)"
conflict_out="$(cd "$repo3" && BASE_REF=main bash -c "$fold_block" 2>&1)"
case "$conflict_out" in
    *"fold aborted"*) assert_eq ok ok "a conflicting fixup: the fold block names the abort" ;;
    *) assert_eq "fold aborted ..." "$conflict_out" "a conflicting fixup: the fold block names the abort" ;;
esac
assert_eq "$conflict_head" "$(git -C "$repo3" rev-parse HEAD)" \
    "a conflicting fixup: HEAD is where it was before the fold"
assert_eq "" "$(git -C "$repo3" status --porcelain)" \
    "a conflicting fixup: no rebase is left in progress and the tree is clean"

# --- 12. Which commit a fix is a fixup of (#566) ------------------------------
# /fix-findings makes a fix a `fixup!` of a branch commit only when that one
# commit wrote every line the finding anchors on. Lines from the base, or from
# two branch commits, must yield no target, so the fixer makes an ordinary commit.
section "fixup target: one branch commit wrote every anchored line, or there is no target"
repo4="$sandbox/repo4"
mkdir -p "$repo4"
(
    cd "$repo4" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'a\nb\nc\n' > f.txt
    git add f.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'a\nB\nc\n' > f.txt
    git commit -q -am 'feature: change b'
    printf 'a\nB\nc\nd\n' > f.txt
    git commit -q -am 'feature: add d'
)
assert_fixture_committed "$repo4" "fixup-target fixture" 0 3 f.txt
change_b_sha="$(git -C "$repo4" rev-parse HEAD~1)"
run_target() {
    (cd "$repo4" && BASE_REF=main FILE=f.txt START="$1" END="$2" \
        bash -c "$fixup_target_block"'; printf "%s" "$FIXUP_TARGET"')
}
assert_eq "$change_b_sha" "$(run_target 2 2)" "a line one branch commit wrote: that commit is the target"
assert_eq "" "$(run_target 2 4)" "lines from two branch commits: no target"
assert_eq "" "$(run_target 1 1)" "a line from the base: no target"
assert_eq "" "$(run_target 1 2)" "a base line next to one branch commit's line: no target (every anchored line, not every non-base line)"
# A user's blame display config must not change the answer: blame.blankBoundary
# blanks the SHA column on a base line, and blame.markUnblamableLines prefixes
# `*`. Either would otherwise leak a non-SHA token into FIXUP_TARGET.
git -C "$repo4" config blame.blankBoundary true
git -C "$repo4" config blame.markUnblamableLines true
assert_eq "" "$(run_target 1 1)" "blame.blankBoundary/markUnblamableLines set: a base line still yields no target"
assert_eq "$change_b_sha" "$(run_target 2 2)" "blame display config set: a single-commit line is still the target"

# --- 13. "Unshared" means no upstream AND not on the remote (#566) --------------
# A plain `git push origin <branch>` publishes the branch with no upstream, so
# the `@{u}` check alone would keep deferring review of a branch others can read.
# The remote-side command is extracted from the skill's own prose and run.
section "unshared test: a branch pushed without -u is shared"
lsremote_cmd="$(grep -o "git ls-remote --heads origin [^\`]*" "$premerge_skill" | head -1 || true)"
[[ -n "$lsremote_cmd" ]] || fatal "no ls-remote command found in pre-merge/SKILL.md"
bare5="$sandbox/bare5.git"
repo5="$sandbox/repo5"
git init -q --bare "$bare5"
git init -q -b main "$repo5"
(
    cd "$repo5" || exit 1
    git config user.email t@example.com
    git config user.name t
    git remote add origin "$bare5"
    printf 'a\n' > f.txt
    git add f.txt && git commit -q -m 'base'
    git switch -q -c feature
)
unshared_remote() { (cd "$repo5" && bash -c "$lsremote_cmd" 2>/dev/null); }
assert_eq "" "$(unshared_remote)" "unpushed branch: remote check prints nothing (unshared)"
git -C "$repo5" push -q origin feature 2>/dev/null
assert_eq "" "$(git -C "$repo5" rev-parse -q --verify '@{u}' 2>/dev/null)" "plain push: still no upstream"
[[ -n "$(unshared_remote)" ]] && r=shared || r=unshared
assert_eq "shared" "$r" "plain push without -u: remote check sees the branch (shared)"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
