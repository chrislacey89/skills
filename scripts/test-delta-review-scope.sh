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
# `stamp release` writes flags under $CLAUDE_PROJECT_DIR and the scope block
# reads one back; without this a run from a Claude Code session would reach
# that session's project instead of the fixture.
unset CLAUDE_PROJECT_DIR

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

# run_bounded <seconds> <command...> — runs the command with stdout and stderr
# combined, and kills it after <seconds>, exiting 124 as timeout(1) does.
# The watcher polls once a second and exits as soon as the command does, so it
# leaves no sleep behind holding the caller's command substitution open.
run_bounded() {
    local secs="$1" pid watcher rc; shift
    "$@" 2>&1 &
    pid=$!
    (
        i=0
        while [ "$i" -lt "$secs" ]; do
            sleep 1
            kill -0 "$pid" 2>/dev/null || exit 0
            i=$((i + 1))
        done
        kill -9 "$pid" 2>/dev/null
        exit 1
    ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"; rc=$?
    wait "$watcher" || return 124
    return "$rc"
}

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
# The work item step 2 named (#599): empty unless a case sets SCOPE_W, so every
# case before section 9b runs as the github backend does, with no work item.
# shellcheck disable=SC2016  # the ${...} is text for the extracted block to expand, not this shell
scope_block="$(printf '%s\n' "$scope_block" | sed 's/^W="<[^"]*>"$/W="${SCOPE_W:-}"/')"
# shellcheck disable=SC2016  # the pattern is the substituted literal text
[[ "$scope_block" == *'W="${SCOPE_W:-}"'* ]] \
    || fatal "scope block's W= placeholder was not substituted"
# shellcheck disable=SC2016
[[ "$scope_block" == *'RANGE="$(bash "$SC" range ${W:+"$W"})"'* ]] \
    || fatal "scope block extracted from $premerge_skill no longer takes the first-review endpoint from sidecar.sh range"
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

# The stacked-PR placeholder (#606). Step 3, step 4 and the fold each take the
# sibling slice's branch here, because no earlier block's variable reaches them.
# Each block is filled in by substitution, the way an agent fills it, and no
# case below presets BASE_REF: a preset tests a path no run takes
# (docs/solutions/testing-patterns/a-preset-variable-tests-a-path-no-run-takes-2026-10-26.md).
bb_placeholder='BASE_BRANCH="<sibling slice branch for a stacked PR, else empty>"'
# fill_base <block> <branch> — the block with its BASE_BRANCH placeholder filled.
fill_base() {
    local filled="BASE_BRANCH=\"$2\""
    [[ "$1" == *"$bb_placeholder"* ]] || { echo "FATAL: a block lost its stacked BASE_BRANCH placeholder" >&2; return 1; }
    printf '%s' "${1//"$bb_placeholder"/$filled}"
}
[[ "$scope_block" == *"$bb_placeholder"* ]] || fatal "scope block has no stacked BASE_BRANCH placeholder (#606)"
scope_block_template="$scope_block"
scope_block="$(fill_base "$scope_block_template" "")" || fatal "could not fill the scope block's BASE_BRANCH placeholder"

# fenced_with <file> <needle> — the first fenced block in <file> whose body holds
# <needle>, whole and de-indented, with the sidecar.sh placeholder pointed at the
# canonical script.
fenced_with() {
    awk -v needle="$2" '
        /^[[:space:]]*```/ {
            if (inblock) { if (found) { printf "%s", buf; exit } inblock = 0; next }
            inblock = 1; buf = ""; found = 0; next
        }
        inblock { line = $0; sub(/^[[:space:]]*/, "", line); buf = buf line "\n"; if (index($0, needle)) found = 1 }
    ' "$1" | sed "s|<this skill's directory>/references/sidecar.sh|$sidecar_sh|"
}

# Phase 1 step 3's block (#606): the base and the branch's diff against it.
# shellcheck disable=SC2016  # the needle is the skill's literal text
step3_block="$(fenced_with "$premerge_skill" 'git log --oneline "$BASE_REF..HEAD"')"
[[ "$step3_block" == *"$sidecar_sh"* ]] || fatal "no Phase 1 step 3 block found in $premerge_skill"
[[ "$step3_block" == *"$bb_placeholder"* ]] || fatal "Phase 1 step 3's block has no stacked BASE_BRANCH placeholder (#606)"

# The round-count block from /fix-findings' next-step menu, whole: the fence
# that holds the RANGE line, through its closing fence. Its github arm counts
# Fix-Findings-Run lines and its sidecar arm counts fixrun records (#585).
rounds_block="$(awk '
    /^```bash$/ { buf = ""; on = 1; next }
    on && /^```$/ { on = 0; if (index(buf, "round count aborted: sidecar.sh range failed")) { printf "%s", buf; exit } next }
    on { buf = buf $0 "\n" }
' "$fixfindings_skill")"
[[ -n "$rounds_block" ]] || fatal "no round-count block found in $fixfindings_skill"
# shellcheck disable=SC2016  # the patterns are the skill's literal text
{
[[ "$rounds_block" == *'git log --format=%B "$RANGE"'* ]] || fatal "the github arm in $fixfindings_skill no longer counts over \$RANGE"
[[ "$rounds_block" == *'fixrun list "$(git branch --show-current)" --range "$RANGE"'* ]] || fatal "the sidecar arm in $fixfindings_skill no longer counts fixrun records over \$RANGE"
[[ "$rounds_block" == *'RANGE="$(bash "$SC" range ${W:+"$W"})"'* ]] || fatal "no RANGE= line from sidecar.sh range found in $fixfindings_skill"
}
rounds_block="${rounds_block//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
# W taken from ROUNDS_W (empty: no work item).
# shellcheck disable=SC2016  # the ${...} is text for the extracted block to expand, not this shell
rounds_block="$(printf '%s\n' "$rounds_block" | sed 's/^W="<the slice[^"]*>"$/W="${ROUNDS_W:-}"/')"
# shellcheck disable=SC2016
[[ "$rounds_block" == *'W="${ROUNDS_W:-}"'* ]] || fatal "the round-count block's W= placeholder was not substituted"

# The fold block from Phase 4's handoff (#566), whole. Run in section 11 rather
# than restated, so a rewrite that rebases onto the base's tip instead of the
# fork point fails there. It computes its own base (#606), so it runs with no
# BASE_REF in its environment, as in the fresh shell an agent gives it.
fold_block_template="$(fenced_with "$premerge_skill" 'git rebase -q -i --autosquash')"
[[ "$fold_block_template" == *"$sidecar_sh"* ]] || fatal "no fold block found in $premerge_skill, or it does not ask sidecar.sh for its base"
[[ "$fold_block_template" == *"$bb_placeholder"* ]] || fatal "the fold block has no stacked BASE_BRANCH placeholder (#606)"
# run_fold <repo> [stacked branch] — the fold, in a shell with no BASE_REF.
run_fold() { (cd "$1" && env -u BASE_REF bash -c "$(fill_base "$fold_block_template" "${2:-}")" 2>&1); }

# /pre-merge Phase 2's shared-branch block (#572), whole: it prints its verdict.
shared_block="$(fenced_with "$premerge_skill" 'git ls-remote --heads')"
# shellcheck disable=SC2016  # the pattern is the skill's literal text
[[ "$shared_block" == *'echo "shared: $SHARED"'* ]] || fatal "no shared-branch block printing its verdict found in $premerge_skill"

# The fixup-target block from /fix-findings Step 1 item 5 (#566), de-indented
# out of its list item and whole, from its comment to the line that prints the
# answer. Section 12 runs it with nothing preset, the way a fresh shell does
# (#619): the anchor reaches it by substitution, as it reaches an agent.
fixup_target_block="$(awk '
    /^   # Which one commit on this branch wrote every line the finding anchors on\?$/ { on = 1 }
    on { sub(/^   /, ""); print }
    on && /^printf .FIXUP_TARGET=/ { exit }
' "$fixfindings_skill")"
fixup_target_block="${fixup_target_block//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
# shellcheck disable=SC2016  # the ${...} is text for the extracted block to expand, not this shell
fixup_target_block="$(printf '%s\n' "$fixup_target_block" | sed -e 's/^FILE="<[^"]*>"$/FILE="${TARGET_FILE:?}"/' \
    -e 's/^START="<[^"]*>"$/START="${TARGET_START:?}"/' -e 's/^END="<[^"]*>"$/END="${TARGET_END:?}"/')"
[[ "$fixup_target_block" == *"$sidecar_sh"* ]] || fatal "fixup-target block's sidecar.sh placeholder was not substituted"
# shellcheck disable=SC2016  # the pattern is the substituted literal text
[[ "$fixup_target_block" == *'END="${TARGET_END:?}"'* ]] || fatal "fixup-target block's anchor placeholders were not substituted"
[[ "$fixup_target_block" == *'|| FIXUP_TARGET='* ]] || fatal "no FIXUP_TARGET block found in $fixfindings_skill"
[[ "$fixup_target_block" == *'then FIXUP_TARGET=; fi'* ]] || fatal "FIXUP_TARGET block in $fixfindings_skill has no shared-branch line"
# Its stacked-PR placeholder takes the sibling branch /pre-merge's fold rebases
# from, so a fixup is never made of a commit the fold will not reach (RB-2).
# Section 12d fills it; everywhere else it is left empty, as on an unstacked branch.
[[ "$fixup_target_block" == *"$bb_placeholder"* ]] || fatal "the fixup-target block has no stacked BASE_BRANCH placeholder"
fixup_target_template="$fixup_target_block"
fixup_target_block="$(fill_base "$fixup_target_template" "")" || fatal "could not fill the fixup-target block's BASE_BRANCH placeholder"

# The fold-trial block that follows it (#611): from its comment line to its
# closing fence. Section 12 runs it whole against a fixup that folds, one that
# does not, and each failure that is not a conflict (#614).
fold_trial_block="$(awk '
    /^   # After `git commit --fixup`: would the commit just made fold\?/ { on = 1 }
    on && /^   ```$/ { exit }
    on { sub(/^   /, ""); print }
' "$fixfindings_skill")"
[[ "$fold_trial_block" == *'rebase -q -i --autosquash'* ]] || fatal "no fold-trial block found in $fixfindings_skill"
fold_trial_block="${fold_trial_block//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
[[ "$fold_trial_block" == *"$sidecar_sh"* ]] || fatal "fold-trial block's sidecar.sh placeholder was not substituted"
[[ "$fold_trial_block" == *"$bb_placeholder"* ]] || fatal "the fold-trial block has no stacked BASE_BRANCH placeholder"
fold_trial_template="$fold_trial_block"
fold_trial_block="$(fill_base "$fold_trial_template" "")" || fatal "could not fill the fold-trial block's BASE_BRANCH placeholder"

printf 'scope block (%s lines) and rounds block extracted\n' "$(printf '%s\n' "$scope_block" | grep -c .)"

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

# run_scope <body> — runs the extracted block in the fixture, with no BASE_REF preset,
# and prints "<scope line>|<files the diff --stat names, sorted, space-joined>".
run_scope() {
    local body="$1" out files scope
    : > "$GH_STUB_ARGV_LOG"
    : > "$GH_STUB_ARGV_MISS_LOG"
    : > "$GIT_STUB_ARGV_LOG"
    out="$(cd "$repo" && GH_STUB_BODY="$body" env -u BASE_REF bash -c "$scope_block" 2>&1)"
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
run_rounds() { (cd "$repo" && bash -c "$rounds_block"$'\n'"printf '%s' \"\$ROUNDS\"" 2>/dev/null); }

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
    out="$(cd "$repo2" && GH_STUB_BODY="$(stamped_body "$first_sha2")" env -u BASE_REF bash -c "$scope_block" 2>&1)"
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

# --- 9b. Two slices on one branch (#599) ----------------------------------------
section "two slices on one branch: the second slice's first review and round count cover only its commits"
# A long-lived branch carrying two slices, each with a fix round. /execute
# records each slice's start as start_sha; range reads it. Without it the second
# slice's first review re-read the first slice, and its round count included
# the first slice's Fix-Findings-Run lines, which reordered the next-step menu.
repo_slices="$sandbox/repo_slices"
mkdir -p "$repo_slices"
(
    cd "$repo_slices" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base4\n' > base.txt
    git add base.txt && git commit -q -m 'base (two-slice fixture)'
    git switch -q -c feature
)
(cd "$repo_slices" && bash "$sidecar_sh" init --name slices --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || fatal "sidecar init failed in the two-slice fixture"
printf 'slice\n' > "$sandbox/slice-body"
w1="$(cd "$repo_slices" && bash "$sidecar_sh" work create --kind slice --body-file "$sandbox/slice-body" 2>/dev/null)"
w2="$(cd "$repo_slices" && bash "$sidecar_sh" work create --kind slice --body-file "$sandbox/slice-body" 2>/dev/null)"
assert_eq "W-1 W-2" "$w1 $w2" "fixture precondition: two slice work items"
(cd "$repo_slices" && bash "$sidecar_sh" work set "$w1" start_sha "$(git rev-parse HEAD)" >/dev/null 2>&1) || fatal "start_sha for $w1 failed"
before_count="$(git -C "$repo_slices" rev-list --count HEAD)"
(
    cd "$repo_slices" || exit 1
    printf 's1\n' > s1.txt && git add s1.txt && git commit -q -m 'slice 1'
    printf 's1fix\n' > s1fix.txt && git add s1fix.txt \
        && git commit -q -m 'fix: slice 1 finding'
)
assert_fixture_committed "$repo_slices" "two-slice fixture: slice 1" "$before_count" 2 s1.txt s1fix.txt
# A guest repo is on the sidecar backend: the fix run is a sidecar record, not a trailer (#585).
(cd "$repo_slices" && bash "$sidecar_sh" fixrun record feature 20261001T100000Z "$(git rev-parse HEAD)" >/dev/null 2>&1) \
    || fatal "fixrun record for slice 1 failed"
(cd "$repo_slices" && bash "$sidecar_sh" work set "$w2" start_sha "$(git rev-parse HEAD)" >/dev/null 2>&1) || fatal "start_sha for $w2 failed"
w2_start="$(git -C "$repo_slices" rev-parse HEAD)"
before_count="$(git -C "$repo_slices" rev-list --count HEAD)"
(
    cd "$repo_slices" || exit 1
    printf 's2\n' > s2.txt && git add s2.txt && git commit -q -m 'slice 2'
    printf 's2fix\n' > s2fix.txt && git add s2fix.txt \
        && git commit -q -m "$(printf 'fix: slice 2 finding\n\nFix-Findings-Run: 20261002T999999Z')"
)
assert_fixture_committed "$repo_slices" "two-slice fixture: slice 2" "$before_count" 2 s2.txt s2fix.txt
(cd "$repo_slices" && bash "$sidecar_sh" fixrun record feature 20261002T100000Z "$(git rev-parse HEAD)" >/dev/null 2>&1) \
    || fatal "fixrun record for slice 2 failed"
(cd "$repo_slices" && bash "$sidecar_sh" stamp clear feature >/dev/null 2>&1)

run_scope_slices() {
    local out files scope
    out="$(cd "$repo_slices" && SCOPE_W="$1" bash -c "$scope_block" 2>&1)"
    scope="$(printf '%s\n' "$out" | grep '^review scope:' || true)"
    files="$(printf '%s\n' "$out" | grep -oE '^ [a-z0-9]+\.txt' | tr -d ' ' | sort | tr '\n' ' ' | sed 's/ $//')"
    printf '%s|%s' "$scope" "$files"
}
assert_eq "review scope: whole slice, from $w2_start ($w2's recorded start)|s2.txt s2fix.txt" \
    "$(run_scope_slices "$w2")" \
    "the second slice's first review reads only its own two files"
assert_eq "review scope: whole branch, from main|s1.txt s1fix.txt s2.txt s2fix.txt" \
    "$(run_scope_slices "")" \
    "with no work item the first review is the whole branch, as before"
w2_stamp="$(git -C "$repo_slices" rev-parse HEAD)"
(cd "$repo_slices" && bash "$sidecar_sh" stamp write feature "$w2_stamp" >/dev/null 2>&1) || fatal "stamp write failed"
before_count="$(git -C "$repo_slices" rev-list --count HEAD)"
( cd "$repo_slices" && printf 's2b\n' > s2b.txt && git add s2b.txt && git commit -q -m 'slice 2: after its stamp' )
assert_fixture_committed "$repo_slices" "two-slice fixture: post-stamp" "$before_count" 1 s2b.txt
assert_eq "review scope: post-stamp delta, from $w2_stamp|s2b.txt" \
    "$(run_scope_slices "$w2")" \
    "a stamped re-run still takes the post-stamp delta when a work item is named"

run_rounds_slices() { (cd "$repo_slices" && ROUNDS_W="$1" bash -c "$rounds_block"$'\n'"printf '%s' \"\$ROUNDS\"" 2>/dev/null); }
assert_eq "1" "$(run_rounds_slices "$w2")" "the second slice's round count ignores the first slice's fix-run record"
assert_eq "2" "$(run_rounds_slices "")" "with no work item the round count covers the branch, as before"
# The slice-2 commit also carries a stray Fix-Findings-Run line with a third run
# id. The sidecar arm reads records, never trailers, so it is not a third round.
assert_eq "2" "$(run_rounds_slices "")" "on the sidecar backend a trailer line in a commit is not counted"
(cd "$repo_slices" && bash "$sidecar_sh" fixrun record feature 20261003T100000Z 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1) \
    || fatal "fixrun record for an off-branch SHA failed"
assert_eq "2" "$(run_rounds_slices "")" "a record whose commit is not on the branch (a fold rewrote it) is not counted"

# --- 9c. A stacked slice is measured against its sibling (#606) --------------
# A stacked PR targets the sibling slice's branch, so step 3's diff and step 4's
# scope must start there, not at the base: measured from main, the review would
# re-read the sibling's commits as this slice's. Each block runs in a shell with
# no BASE_REF, and the sibling reaches it only through its placeholder.
section "stacked slice: step 3 and step 4 measure from the sibling branch named in their placeholder"
repo_stack="$sandbox/repo-stack"
mkdir -p "$repo_stack"
(
    cd "$repo_stack" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c slice-1
    printf 'sibling\n' > s1.txt
    git add s1.txt && git commit -q -m 'slice 1: sibling'
    git switch -q -c feature
    printf 'f1\n' > f1.txt
    git add f1.txt && git commit -q -m 'slice 2: f1'
    printf 'f2\n' > f2.txt
    git add f2.txt && git commit -q -m 'slice 2: f2'
)
assert_fixture_committed "$repo_stack" "stacked fixture" 0 4 base.txt s1.txt f1.txt f2.txt
# stat_files <output> — the files a --stat names, sorted, space-joined.
stat_files() { printf '%s\n' "$1" | grep -oE '^ [a-z0-9]+\.txt' | tr -d ' ' | sort | tr '\n' ' ' | sed 's/ $//'; }
run_step3() { (cd "$repo_stack" && env -u BASE_REF -u BASE_BRANCH bash -c "$(fill_base "$step3_block" "$1")" 2>&1); }
stack3="$(run_step3 slice-1)"
assert_eq "f1.txt f2.txt" "$(stat_files "$stack3")" "step 3, stacked on slice-1: the diff names only this slice's files"
assert_eq 2 "$(printf '%s\n' "$stack3" | grep -cE '^[0-9a-f]{7,} slice 2: ' || true)" "step 3, stacked on slice-1: the log lists only this slice's two commits"
assert_eq "f1.txt f2.txt s1.txt" "$(stat_files "$(run_step3 "")")" "control: step 3 with an empty placeholder measures from main, sibling included"
git -C "$repo_stack" update-ref refs/remotes/origin/slice-1 slice-1
git -C "$repo_stack" update-ref refs/remotes/origin/main main
git -C "$repo_stack" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
assert_eq "f1.txt f2.txt" "$(stat_files "$(run_step3 slice-1)")" "step 3, stacked, with origin/slice-1 present: still only this slice's files"
stack3="$(run_step3 no-such-sibling)" && rc=0 || rc=$?
[[ "$rc" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "step 3, stacked on a branch that does not resolve: the block stops"
assert_eq "" "$(stat_files "$stack3")" "step 3, stacked on a branch that does not resolve: it measures nothing"
run_scope_stack() {
    local out
    out="$(cd "$repo_stack" && GH_STUB_BODY="" env -u BASE_REF -u BASE_BRANCH bash -c "$(fill_base "$scope_block_template" "$1")" 2>&1)"
    printf '%s|%s' "$(printf '%s\n' "$out" | grep '^review scope:' || true)" "$(stat_files "$out")"
}
(cd "$repo_stack" && git switch -q feature)
assert_eq "review scope: whole branch, from origin/slice-1|f1.txt f2.txt" "$(run_scope_stack slice-1)" \
    "step 4, stacked on slice-1: the whole-branch scope starts at the sibling"
assert_eq "review scope: whole branch, from origin/main|f1.txt f2.txt s1.txt" "$(run_scope_stack "")" \
    "control: step 4 with an empty placeholder starts at the base"

# The fold, stacked: it rebases onto the fork point with the sibling, in a shell
# that has a stale BASE_REF it must not read.
(
    cd "$repo_stack" || exit 1
    printf 'f1, fixed\n' > f1.txt
    git add f1.txt && git commit -q --fixup=HEAD~1 -m 'fix f1'
)
sibling_tip="$(git -C "$repo_stack" rev-parse slice-1)"
stack_fold="$(cd "$repo_stack" && BASE_REF=origin/nope bash -c "$(fill_base "$fold_block_template" slice-1)" 2>&1)"
case "$stack_fold" in
    *"folded: tree unchanged"*) assert_eq ok ok "the fold, stacked on slice-1, in a shell with a stale BASE_REF: it folds" ;;
    *) assert_eq "folded: tree unchanged" "$stack_fold" "the fold, stacked on slice-1, in a shell with a stale BASE_REF: it folds" ;;
esac
assert_eq "2 $sibling_tip" "$(git -C "$repo_stack" rev-list --count slice-1..HEAD) $(git -C "$repo_stack" merge-base slice-1 HEAD)" \
    "the stacked fold leaves the sibling's commits as they were and this slice's two commits on top"

# The same three stacked blocks under zsh, the shell an agent runs them in on
# macOS (docs/solutions/patterns/skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md,
# § Prevention: a zsh arm is per block). A missing zsh skips locally and fails
# when CI is set.
stacked_zsh_arms() {
    local out z3 zs zf
    z3="$(cd "$repo_stack" && env -u BASE_REF -u BASE_BRANCH zsh -f -c "$(fill_base "$step3_block" slice-1)" 2>&1)"
    assert_eq "f1.txt f2.txt" "$(stat_files "$z3")" "zsh: step 3, stacked on slice-1: the diff names only this slice's files"
    assert_eq 2 "$(printf '%s\n' "$z3" | grep -cE '^[0-9a-f]{7,} slice 2: ' || true)" "zsh: step 3, stacked on slice-1: the log lists only this slice's two commits"
    z3="$(cd "$repo_stack" && env -u BASE_REF -u BASE_BRANCH zsh -f -c "$(fill_base "$step3_block" no-such-sibling)" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -ne 0 ]] && r=nonzero || r=zero
    assert_eq nonzero "$r" "zsh: step 3, stacked on a branch that does not resolve: the block stops"
    assert_eq "" "$(stat_files "$z3")" "zsh: step 3, stacked on a branch that does not resolve: it measures nothing"
    zs="$(cd "$repo_stack" && GH_STUB_BODY="" env -u BASE_REF -u BASE_BRANCH zsh -f -c "$(fill_base "$scope_block_template" slice-1)" 2>&1)"
    assert_eq "review scope: whole branch, from origin/slice-1|f1.txt f2.txt" \
        "$(printf '%s\n' "$zs" | grep '^review scope:' || true)|$(stat_files "$zs")" \
        "zsh: step 4, stacked on slice-1: the whole-branch scope starts at the sibling"
    (
        cd "$repo_stack" || exit 1
        printf 'f2, fixed\n' > f2.txt
        git add f2.txt && git commit -q --fixup=HEAD -m 'fix f2'
    )
    zf="$(cd "$repo_stack" && BASE_REF=origin/nope zsh -f -c "$(fill_base "$fold_block_template" slice-1)" 2>&1)" && rc=0 || rc=$?
    case "$zf" in
        *"folded: tree unchanged"*) assert_eq ok ok "zsh: the fold, stacked on slice-1, with a stale BASE_REF: it folds" ;;
        *) assert_eq "folded: tree unchanged" "$zf" "zsh: the fold, stacked on slice-1, with a stale BASE_REF: it folds" ;;
    esac
    assert_eq "0 2 $sibling_tip" "$rc $(git -C "$repo_stack" rev-list --count slice-1..HEAD) $(git -C "$repo_stack" merge-base slice-1 HEAD)" \
        "zsh: the stacked fold exits 0 and leaves this slice's two commits on the sibling"
}
if command -v zsh >/dev/null 2>&1; then
    stacked_zsh_arms
elif [[ -n "${CI:-}" ]]; then
    assert_eq "zsh on PATH" "zsh absent" "the stacked step 3, step 4 and fold blocks ran under zsh (CI is set, so a missing zsh fails)"
else
    printf '  SKIP zsh is not on PATH, so the stacked step 3, step 4 and fold blocks ran under bash only\n'
fi

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
    env -u BASE_REF bash -c "$scope_block" 2>&1)"
failed_rc=$?
assert_eq 1 "$failed_rc" "failed backend: the scope block exits 1"
assert_eq "" "$(printf '%s\n' "$failed_out" | grep '^review scope:' || true)" \
    "failed backend: the scope block prints no review scope"
assert_eq "" "$(cat "$GH_STUB_ARGV_LOG")" "failed backend: the scope block never called gh"
case "$failed_out" in
    *"scope aborted"*) assert_eq ok ok "failed backend: the abort is named on stderr" ;;
    *) assert_eq "scope aborted ..." "$failed_out" "failed backend: the abort is named on stderr" ;;
esac

# The round-count block has the same hazard. `range` succeeds here (so the abort
# under test is the block's own `*)` arm, not its RANGE guard) and `backend
# stamp` fails. Folding `*)` into the github arm would count trailers over the
# range: the branch holds Fix-Findings-Run lines, so that would print a count.
section "failed backend: the round-count block aborts rather than counting trailers"
failing_sc="$sandbox/failing-backend-sc.sh"
cat > "$failing_sc" <<'STUB'
#!/usr/bin/env bash
[ "$1" = range ] && { git merge-base HEAD main; exit 0; }
[ "$1 $2" = "backend stamp" ] && exit 1
echo "stub sidecar: unexpected call: $*" >&2; exit 1
STUB
rounds_failed_block="${rounds_block//$sidecar_sh/$failing_sc}"
[[ "$rounds_failed_block" == *"$failing_sc"* ]] || fatal "the failing-backend stub was not substituted into the round-count block"
rounds_failed_out="$(cd "$repo" && bash -c "$rounds_failed_block"$'\n'"printf 'ROUNDS=[%s]' \"\${ROUNDS:-}\"" 2>&1)"
rounds_failed_rc=$?
assert_eq 1 "$rounds_failed_rc" "failed backend: the round-count block exits 1"
case "$rounds_failed_out" in
    *"ROUNDS=["*) assert_eq "no count" "$rounds_failed_out" "failed backend: the round-count block counted nothing" ;;
    *) assert_eq ok ok "failed backend: the round-count block counted nothing" ;;
esac
case "$rounds_failed_out" in
    *"round count aborted"*) assert_eq ok ok "failed backend: the abort is named on stderr" ;;
    *) assert_eq "round count aborted ..." "$rounds_failed_out" "failed backend: the abort is named on stderr" ;;
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
fold_out="$(run_fold "$repo3")"
case "$fold_out" in
    *"folded: "*) assert_eq ok ok "the documented fold block reports the fold" ;;
    *) assert_eq "folded: ..." "$fold_out" "the documented fold block reports the fold" ;;
esac
assert_eq "2" "$(git -C "$repo3" rev-list --count main..HEAD)" \
    "fold fixture precondition: the autosquash folded three commits into two"
assert_eq "$(git -C "$repo3" rev-parse "$reviewed_sha3^{tree}")" "$(git -C "$repo3" rev-parse 'HEAD^{tree}')" \
    "fold fixture precondition: the fold left the reviewed tree unchanged"
# A fold must not carry /fix-findings' run trailer into the commit it corrects:
# git discards a fixup's -m text when it squashes it, and this pins that.
assert_eq "" "$(git -C "$repo3" log --format=%B main..HEAD | grep 'Fix-Findings-Run:' || true)" \
    "a folded fixup leaves no Fix-Findings-Run trailer in the branch's commit messages"

run_scope3() {
    local out files scope
    : > "$GH_STUB_ARGV_LOG"
    out="$(cd "$repo3" && GH_STUB_BODY="$(stamped_body "$1")" env -u BASE_REF bash -c "$scope_block" 2>&1)"
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
conflict_out="$(run_fold "$repo3")"
case "$conflict_out" in
    *"fold aborted: "*" conflicted"*) assert_eq ok ok "a conflicting fixup: the fold block names the abort as a conflict" ;;
    *) assert_eq "fold aborted: ... conflicted ..." "$conflict_out" "a conflicting fixup: the fold block names the abort as a conflict" ;;
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
# point_origin_at_main <repo> — gives a fixture the origin a clone has, so
# sidecar.sh base-ref answers origin/main with nothing on stderr. Only main is
# pushed: ls-remote answers and finds no feature branch, so the branch reads as
# unshared. A fixture with no origin at all would read as shared, because an
# ls-remote that cannot ask counts as shared (#572).
point_origin_at_main() {
    git init -q --bare "$1.origin.git"
    git -C "$1" remote add origin "$1.origin.git"
    git -C "$1" push -q origin main 2>/dev/null
    git -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
point_origin_at_main "$repo4"
change_b_sha="$(git -C "$repo4" rev-parse HEAD~1)"
# Prints the SHA the block's own last line printed, for <repo> <file> <start> <end>.
run_target_in() {
    local out
    out="$(cd "$1" && env -u BASE_REF TARGET_FILE="$2" TARGET_START="$3" TARGET_END="$4" bash -c "$fixup_target_block" 2>/dev/null)"
    printf '%s' "${out#FIXUP_TARGET=}"
}
run_target() { run_target_in "$repo4" f.txt "$1" "$2"; }
assert_eq "$change_b_sha" "$(run_target 2 2)" "a line one branch commit wrote: that commit is the target, with BASE_REF unset"
assert_eq "" "$(run_target 2 4)" "lines from two branch commits: no target"
assert_eq "" "$(run_target 1 1)" "a line from the base: no target"
assert_eq "" "$(run_target 1 2)" "a base line next to one branch commit's line: no target (every anchored line, not every non-base line)"
# A base that cannot be read is not "no target": the block stops, rather than
# sending the fixer to an ordinary commit on a broken lookup.
sc_refuses="$sandbox/sc-refuses.sh"
printf '#!/bin/sh\necho "base-ref: refused" >&2\nexit 1\n' > "$sc_refuses"
out4="$(cd "$repo4" && env -u BASE_REF TARGET_FILE=f.txt TARGET_START=2 TARGET_END=2 \
    bash -c "${fixup_target_block//$sidecar_sh/$sc_refuses}" 2>&1)" && rc4=0 || rc4=$?
[[ "$rc4" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "base-ref refuses: the fixup-target block exits nonzero"
case "$out4" in
    *FIXUP_TARGET=*) assert_eq "no answer printed" "$out4" "base-ref refuses: the block prints no target" ;;
    *) assert_eq ok ok "base-ref refuses: the block prints no target" ;;
esac
# A user's blame display config must not change the answer: blame.blankBoundary
# blanks the SHA column on a base line, and blame.markUnblamableLines prefixes
# `*`. Either would otherwise leak a non-SHA token into FIXUP_TARGET.
git -C "$repo4" config blame.blankBoundary true
git -C "$repo4" config blame.markUnblamableLines true
assert_eq "" "$(run_target 1 1)" "blame.blankBoundary/markUnblamableLines set: a base line still yields no target"
assert_eq "$change_b_sha" "$(run_target 2 2)" "blame display config set: a single-commit line is still the target"
# markUnblamableLines only marks a line an ignored revision changed and blame
# could not pass to another commit, so it needs blame.ignoreRevsFile to show at
# all (#573 item 1). Ignore 'feature: add d': line 4 has no counterpart in its
# parent, so a user's config would print `*<sha>` for it, and the block's
# `-c blame.markUnblamableLines=false` is what keeps the answer a bare SHA.
add_d_sha="$(git -C "$repo4" rev-parse HEAD)"
printf '%s\n' "$add_d_sha" > "$sandbox/ignore-revs4"
git -C "$repo4" config blame.ignoreRevsFile "$sandbox/ignore-revs4"
assert_eq "*${add_d_sha:0:39}" "$(git -C "$repo4" blame -l -s -L 4,4 main..HEAD -- f.txt | awk '{ print $1 }')" \
    "fixture precondition: with the ignore-revs file, the user's blame config marks line 4 with *"
assert_eq "$add_d_sha" "$(run_target 4 4)" "an unblamable line under the user's ignore-revs file: the target is a bare SHA"
git -C "$repo4" config --unset blame.ignoreRevsFile

# A shared branch never gets a fixup: /pre-merge offers the fold only on an
# unshared branch, so a `fixup!` subject there would merge as-is (#611). Both
# ways of sharing count — a push with -u, and a plain push with no upstream.
bare4="$sandbox/bare4.git"
git init -q --bare "$bare4"
git -C "$repo4" remote set-url origin "$bare4"
git -C "$repo4" push -q origin feature 2>/dev/null
assert_eq "" "$(run_target 2 2)" "plain push without -u: a single-commit line yields no target"
git -C "$repo4" branch -q --set-upstream-to=origin/feature
assert_eq "" "$(run_target 2 2)" "pushed with an upstream: a single-commit line yields no target"
# The unshared test is copied from /pre-merge Phase 2's shared-branch block;
# pin the copy to it, line by line, and the verdict to the same condition (#572).
shared_copy_lines() {
    printf '%s\n' "$1" | grep -E '^(B=|R=|HEADS=)' || true
    printf '%s\n' "$1" | sed -n 's/^if \(.*\); then .*/\1/p'
}
premerge_shared_lines="$(shared_copy_lines "$shared_block")"
assert_eq 4 "$(printf '%s\n' "$premerge_shared_lines" | grep -c .)" "/pre-merge's shared-branch block has its three lookups and one verdict"
missing=""
while IFS= read -r l; do
    [[ -z "$l" || "$fixup_target_block" == *"$l"* ]] || missing="$missing [$l]"
done <<<"$premerge_shared_lines"
assert_eq "" "$missing" "the fixup-target block's shared-branch test is /pre-merge Phase 2's, line for line"

# --- 12b. The fold trial demotes a fixup the fold could not apply (#611) ------
section "fold trial: a fixup that would not fold becomes an ordinary commit"
repo6="$sandbox/repo6"
mkdir -p "$repo6"
(
    cd "$repo6" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'a\nB\nc\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
    printf 'two, fixed\n' > two.txt
    git add two.txt && git commit -q --fixup=HEAD -m 'fix two' -m 'Fix-Findings-Run: 20261027T000000Z'
)
point_origin_at_main "$repo6"
# BASE_REF is cleared wherever the trial runs: a real run reaches it in a fresh
# shell, so the block must compute its own (#614, #619).
trial_in() { (cd "$1" && env -u BASE_REF bash -c "$fold_trial_block" 2>&1); }
run_trial() { trial_in "$repo6"; }
worktrees_before="$(git -C "$repo6" worktree list | grep -c .)"
clean_head="$(git -C "$repo6" rev-parse HEAD)"
assert_eq "fold trial: clean" "$(run_trial)" "a fixup no later commit overlaps: the trial reports clean"
assert_eq "$clean_head" "$(git -C "$repo6" rev-parse HEAD)" "a clean trial leaves the fixup commit as it was"

# The shape #611 reproduced: the anchored line (B) still belongs to 'feature:
# one', and a later commit edits the line next to it. The fixup target comes
# from /fix-findings' own selection block, so the fixture is one a real run
# reaches. repo6 has no remote or upstream, so the block does not clear it.
(
    cd "$repo6" || exit 1
    printf 'a\nB\nc2\n' > one.txt
    git add one.txt && git commit -q -m 'feature: edit the line next to B'
    printf 'a\nB, fixed\nc2\n' > one.txt
)
one_sha6="$(git -C "$repo6" rev-parse HEAD~3)"
target6="$(run_target_in "$repo6" one.txt 2 2)"
assert_eq "$one_sha6" "$target6" "the fixture's fixup target is the one /fix-findings' selection block picks"
(
    cd "$repo6" || exit 1
    git add one.txt && git commit -q --fixup="$target6" -m 'fix one again' -m 'Fix-Findings-Run: 20261027T000001Z'
)
conflict_tree6="$(git -C "$repo6" rev-parse 'HEAD^{tree}')"
count6="$(git -C "$repo6" rev-list --count main..HEAD)"
case "$(run_trial)" in
    *"would not fold"*) assert_eq ok ok "a fixup a later commit overlaps: the trial names the demotion" ;;
    *) assert_eq "fold trial: would not fold ..." "$(run_trial)" "a fixup a later commit overlaps: the trial names the demotion" ;;
esac
assert_eq "fix one again" "$(git -C "$repo6" log -1 --format=%s)" "demoted: the subject is the fixer's message, not fixup!"
assert_eq "Fix-Findings-Run: 20261027T000001Z" "$(git -C "$repo6" log -1 --format=%B | grep '^Fix-Findings-Run:')" \
    "demoted: the run trailer survives"
assert_eq "$conflict_tree6" "$(git -C "$repo6" rev-parse 'HEAD^{tree}')" "demoted: the fix's content is unchanged"
assert_eq "$count6" "$(git -C "$repo6" rev-list --count main..HEAD)" "demoted: still one commit per fix"
assert_eq "feature" "$(git -C "$repo6" branch --show-current)" "the trial leaves the branch checked out"
assert_eq "$worktrees_before" "$(git -C "$repo6" worktree list | grep -c .)" "the trial registers no worktree"
assert_eq "" "$(git -C "$repo6" status --porcelain)" "the trial leaves the working tree clean"
# The fold /pre-merge offers now succeeds where it would have aborted.
case "$(run_fold "$repo6")" in
    *"folded: "*) assert_eq ok ok "after the demotion, /pre-merge's fold applies" ;;
    *) assert_eq "folded: ..." "aborted" "after the demotion, /pre-merge's fold applies" ;;
esac

# The trial predicts /pre-merge's fold, so it must rebase onto the same commit:
# the branch's fork point. Here the base moved after the branch forked, with an
# edit that conflicts with the branch's first commit. A rebase onto the base's
# tip would conflict and demote a fixup the fold applies cleanly. This runs the
# trial and the fold on one fixture, so it compares behavior rather than text.
section "fold trial: rebases onto the fork point, as /pre-merge's fold does"
repo9="$sandbox/repo9"
mkdir -p "$repo9"
(
    cd "$repo9" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'a\nb\nc\n' > one.txt
    git add one.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'a\nB\nc\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
    printf 'two, fixed\n' > two.txt
    git add two.txt && git commit -q --fixup=HEAD -m 'fix two' -m 'Fix-Findings-Run: 20261027T000003Z'
    git switch -q main
    printf 'a\nb, moved\nc\n' > one.txt
    git add one.txt && git commit -q -m 'base moves on'
    git switch -q feature
)
point_origin_at_main "$repo9"
head9="$(git -C "$repo9" rev-parse HEAD)"
assert_eq "fold trial: clean" "$(trial_in "$repo9")" \
    "a base that moved after the fork: the trial still reports clean"
assert_eq "$head9" "$(git -C "$repo9" rev-parse HEAD)" "a base that moved after the fork: the fixup is not demoted"
case "$(run_fold "$repo9")" in
    *"folded: "*) assert_eq ok ok "a base that moved after the fork: /pre-merge's fold applies, as the trial said" ;;
    *) assert_eq "folded: ..." "aborted" "a base that moved after the fork: /pre-merge's fold applies, as the trial said" ;;
esac

# A recommit the amend refuses must not be reported as handled.
section "fold trial: a failed recommit is reported as a failure"
repo7="$sandbox/repo7"
mkdir -p "$repo7"
(
    cd "$repo7" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'one, rewritten\n' > one.txt
    git add one.txt && git commit -q -m 'feature: rewrite one'
    printf 'one, fixed\n' > one.txt
    git add one.txt && git commit -q --fixup=HEAD~1 -m 'fix one' -m 'Fix-Findings-Run: 20261027T000002Z'
    # shellcheck disable=SC2016  # the hook body is literal text for sh
    printf '#!/bin/sh\ncase "$(head -1 "$1")" in "fixup! "*) exit 0 ;; *) echo "commit-msg: bad subject" >&2; exit 1 ;; esac\n' > .git/hooks/commit-msg
    chmod +x .git/hooks/commit-msg
)
point_origin_at_main "$repo7"
head7="$(git -C "$repo7" rev-parse HEAD)"
out7="$(trial_in "$repo7")" && rc7=0 || rc7=$?
[[ "$rc7" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "a refused recommit: the block exits nonzero"
case "$out7" in
    *"recommitted as an ordinary commit"*) assert_eq "no success line" "$out7" "a refused recommit: no success line" ;;
    *) assert_eq ok ok "a refused recommit: no success line" ;;
esac
assert_eq "$head7" "$(git -C "$repo7" rev-parse HEAD)" "a refused recommit: HEAD is untouched"
assert_eq "fixup! feature: one" "$(git -C "$repo7" log -1 --format=%s)" "a refused recommit: the subject is still fixup!"

# --- 12c. Only a conflict demotes (#614) ---------------------------------------
# Each case below has a fixup that folds, so the demotion arm is always the wrong
# answer. A trial that read the failure as a conflict would exit 0 with an
# ordinary subject, which is what #614 reproduced.

# clean_fixup_repo <dir> — a branch whose newest commit is a fixup that folds.
clean_fixup_repo() {
    mkdir -p "$1"
    (
        cd "$1" || exit 1
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
        printf 'two, fixed\n' > two.txt
        git add two.txt && git commit -q --fixup=HEAD -m 'fix two' -m 'Fix-Findings-Run: 20261030T000000Z'
    )
    point_origin_at_main "$1"
}

# assert_refused <label> <repo> <head before> <rc> <output> <expected text>
assert_refused() {
    local r
    [[ "$4" -ne 0 ]] && r=nonzero || r=zero
    assert_eq nonzero "$r" "$1: the block exits nonzero"
    case "$5" in
        *"$6"*) assert_eq ok ok "$1: the refusal says why" ;;
        *) assert_eq "a message naming: $6" "$5" "$1: the refusal says why" ;;
    esac
    assert_eq "$3" "$(git -C "$2" rev-parse HEAD)" "$1: HEAD is untouched"
    assert_eq "fixup! feature: two" "$(git -C "$2" log -1 --format=%s)" "$1: the subject is still fixup!"
}

section "fold trial: a fresh shell computes its own base (#619)"
repo10="$sandbox/repo10"
clean_fixup_repo "$repo10"
head10="$(git -C "$repo10" rev-parse HEAD)"
# No commit-msg hook here, on purpose: with one, an unguarded block that read an
# empty BASE_REF would fail at the recommit and exit nonzero anyway, so this case
# could not tell it from a guarded one.
assert_eq "fold trial: clean" "$(trial_in "$repo10")" "BASE_REF unset: the block computes it and reports clean"
assert_eq "$head10" "$(git -C "$repo10" rev-parse HEAD)" "BASE_REF unset: the fixup keeps its SHA"
assert_eq "fold trial: clean" "$(cd "$repo10" && BASE_REF=origin/nope bash -c "$fold_trial_block" 2>&1)" \
    "a stale BASE_REF in the environment is not read"

section "fold trial: a base that cannot be used refuses (#614 item 1)"
sc_nope="$sandbox/sc-nope.sh"
printf '#!/bin/sh\necho origin/nope\n' > "$sc_nope"
out10="$(cd "$repo10" && env -u BASE_REF bash -c "${fold_trial_block//$sidecar_sh/$sc_nope}" 2>&1)" && rc10=0 || rc10=$?
assert_refused "a base ref that does not exist" "$repo10" "$head10" "$rc10" "$out10" "no merge base with origin/nope"
out10="$(cd "$repo10" && env -u BASE_REF bash -c "${fold_trial_block//$sidecar_sh/$sc_refuses}" 2>&1)" && rc10=0 || rc10=$?
assert_refused "base-ref refuses" "$repo10" "$head10" "$rc10" "$out10" "sidecar.sh base-ref failed"

section "fold trial: a failed clone or checkout refuses (#614 item 1)"
fail_bin="$sandbox/fail-bin"
mkdir -p "$fail_bin"
cat > "$fail_bin/git" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
    if [ "$arg" = "${GIT_FAIL_VERB:?}" ]; then echo "stub: git $arg fails" >&2; exit 128; fi
done
exec "${REAL_GIT:?}" "$@"
STUB
chmod +x "$fail_bin/git"
# Not every mktemp honors TMPDIR, so a stub puts the throwaway directory where the
# cleanup check can see it, and logs the path so an empty check cannot pass on a
# directory made somewhere else. A file request (sidecar.sh's) goes to the real one.
real_mktemp="$(command -v mktemp)"
export REAL_MKTEMP="$real_mktemp"
export TRIAL_TMP="$sandbox/trial-tmp" TRIAL_TMP_LOG="$sandbox/trial-tmp.log"
mkdir -p "$TRIAL_TMP"
cat > "$fail_bin/mktemp" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = -d ]; then
    if [ -n "${MKTEMP_FAIL:-}" ]; then echo "stub: mktemp -d fails" >&2; exit 1; fi
    dir="$("${REAL_MKTEMP:?}" -d "${TRIAL_TMP:?}/trial.XXXXXX")" || exit 1
    printf '%s\n' "$dir" >> "${TRIAL_TMP_LOG:?}"
    printf '%s\n' "$dir"
    exit 0
fi
exec "${REAL_MKTEMP:?}" "$@"
STUB
chmod +x "$fail_bin/mktemp"
# assert_trial_dir_gone <label> — one throwaway directory was made since the log
# was last cleared, and nothing of it is left.
assert_trial_dir_gone() {
    assert_eq 1 "$(grep -c . "$TRIAL_TMP_LOG")" "$1: the block made its throwaway directory here"
    assert_eq "" "$(find "$TRIAL_TMP" -mindepth 1 -print)" "$1: the throwaway directory is removed"
    : > "$TRIAL_TMP_LOG"
}
for verb in clone checkout; do
    out10="$(cd "$repo10" && env -u BASE_REF PATH="$fail_bin:$PATH" GIT_FAIL_VERB="$verb" \
        bash -c "$fold_trial_block" 2>&1)" && rc10=0 || rc10=$?
    assert_refused "a failing $verb" "$repo10" "$head10" "$rc10" "$out10" "the throwaway $verb failed"
    assert_trial_dir_gone "a failing $verb"
done

# #686 box 14: the mktemp guard, reached. Without it TRIAL_DIR is empty and the
# EXIT trap runs rm -rf "" ".msg" ".err", which deletes any .msg and .err in the
# working directory. So the files are planted first and must survive.
printf 'keep\n' > "$repo10/.msg"
printf 'keep\n' > "$repo10/.err"
status_before="$(git -C "$repo10" status --porcelain --ignored)"
out10="$(cd "$repo10" && env -u BASE_REF PATH="$fail_bin:$PATH" GIT_FAIL_VERB=--no-such-arg MKTEMP_FAIL=1 \
    bash -c "$fold_trial_block" 2>&1)" && rc10=0 || rc10=$?
assert_refused "a failing mktemp" "$repo10" "$head10" "$rc10" "$out10" "fold trial aborted: mktemp failed"
assert_eq "keep" "$(cat "$repo10/.msg" 2>/dev/null)" "a failing mktemp: a .msg in the working directory survives"
assert_eq "keep" "$(cat "$repo10/.err" 2>/dev/null)" "a failing mktemp: an .err in the working directory survives"
assert_eq "$status_before" "$(git -C "$repo10" status --porcelain --ignored)" "a failing mktemp: nothing new is written into the repository"
rm -f "$repo10/.msg" "$repo10/.err"

# #686 box 14: HEAD that cannot be read has no guard of its own. The throwaway
# checkout of an empty TRIAL_HEAD fails, and that guard refuses (a mutation of a
# separate rev-parse guard showed it, so the separate guard was dropped).
head_bin="$sandbox/head-bin"
mkdir -p "$head_bin"
cat > "$head_bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "$#" -eq 2 ] && [ "$1" = rev-parse ] && [ "$2" = HEAD ]; then echo "stub: git rev-parse HEAD fails" >&2; exit 128; fi
exec "${REAL_GIT:?}" "$@"
STUB
chmod +x "$head_bin/git"
: > "$TRIAL_TMP_LOG"
out10="$(cd "$repo10" && env -u BASE_REF PATH="$head_bin:$fail_bin:$PATH" \
    bash -c "$fold_trial_block" 2>&1)" && rc10=0 || rc10=$?
assert_refused "HEAD that cannot be read" "$repo10" "$head10" "$rc10" "$out10" "the throwaway checkout failed"
assert_trial_dir_gone "HEAD that cannot be read"

section "fold trial: a failing signer does not read as a conflict (#614 item 2)"
# This suite never saw this while global config was isolated: GIT_CONFIG_GLOBAL
# brings back the signing a user's run has.
failing_signer="$sandbox/failing-signer"
printf '#!/bin/sh\necho "signer: no one to approve this" >&2\nexit 1\n' > "$failing_signer"
chmod +x "$failing_signer"
signing_config="$sandbox/signing.gitconfig"
printf '[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = %s\n' "$failing_signer" > "$signing_config"
# The instrument: this config must really refuse a commit, or the case proves nothing.
GIT_CONFIG_GLOBAL="$signing_config" git -C "$repo10" commit -q --allow-empty -m 'probe' 2>/dev/null && r=signed || r=refused
assert_eq refused "$r" "the failing signer refuses a real commit under this config"
out10="$(cd "$repo10" && env -u BASE_REF GIT_CONFIG_GLOBAL="$signing_config" bash -c "$fold_trial_block" 2>&1)"
assert_eq "fold trial: clean" "$out10" "global signing with a failing signer: the trial still reports clean"
assert_eq "$head10" "$(git -C "$repo10" rev-parse HEAD)" "global signing with a failing signer: the fixup is not demoted"

# #686 box 11: the trial's own identity. The throwaway clone reads none of the
# repository's config, so its rebase commits with the -c user.name/user.email
# the block passes; without them a machine with no global identity aborts a
# fixup that folds. useConfigOnly stops git guessing one from the host.
no_identity_config="$sandbox/no-identity.gitconfig"
printf '[user]\n\tuseConfigOnly = true\n' > "$no_identity_config"
no_identity_env=(env -u BASE_REF -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u EMAIL
    GIT_CONFIG_GLOBAL="$no_identity_config" GIT_CONFIG_NOSYSTEM=1)
id_probe="$sandbox/id-probe"
git init -q "$id_probe"
"${no_identity_env[@]}" git -C "$id_probe" commit -q --allow-empty -m probe 2>/dev/null && r=committed || r=refused
assert_eq refused "$r" "the instrument: with no identity configured, a commit is refused"
out10="$(cd "$repo10" && "${no_identity_env[@]}" bash -c "$fold_trial_block" 2>&1)"
assert_eq "fold trial: clean" "$out10" "no identity anywhere: the trial's own identity still lets a clean fixup fold"
assert_eq "$head10" "$(git -C "$repo10" rev-parse HEAD)" "no identity anywhere: the fixup is not demoted"

section "fold trial: a rebase that fails without a conflict refuses (#614 item 1)"
# A global pre-rebase hook refuses before anything is replayed.
refusing_hooks="$sandbox/refusing-hooks"
mkdir -p "$refusing_hooks"
printf '#!/bin/sh\necho "pre-rebase: frozen until Friday" >&2\nexit 1\n' > "$refusing_hooks/pre-rebase"
chmod +x "$refusing_hooks/pre-rebase"
hooks_config="$sandbox/hooks.gitconfig"
printf '[core]\n\thooksPath = %s\n' "$refusing_hooks" > "$hooks_config"
: > "$TRIAL_TMP_LOG"
out10="$(cd "$repo10" && env -u BASE_REF GIT_CONFIG_GLOBAL="$hooks_config" PATH="$fail_bin:$PATH" GIT_FAIL_VERB=--no-such-arg \
    bash -c "$fold_trial_block" 2>&1)" && rc10=0 || rc10=$?
assert_refused "a refusing pre-rebase hook" "$repo10" "$head10" "$rc10" "$out10" "the rebase failed without a conflict"
# #686 box 6: the rebase's own error reaches the report, so a hook's reason is not lost.
case "$out10" in
    *"frozen until Friday"*) assert_eq ok ok "a refusing pre-rebase hook: the abort relays the hook's message" ;;
    *) assert_eq "the hook's message" "$out10" "a refusing pre-rebase hook: the abort relays the hook's message" ;;
esac
assert_trial_dir_gone "a refusing pre-rebase hook"

# A fixup that undoes its target stops the rebase with nothing unmerged: the fold
# aborts, but this is not a conflict either, so it goes to the human.
repo12="$sandbox/repo12"
clean_fixup_repo "$repo12"
(
    cd "$repo12" || exit 1
    git reset -q --hard HEAD~1
    printf 'three\n' > three.txt
    git add three.txt && git commit -q -m 'feature: three'
    git rm -q two.txt && git commit -q --fixup=HEAD~1 -m 'undo two' -m 'Fix-Findings-Run: 20261030T000001Z'
)
head12="$(git -C "$repo12" rev-parse HEAD)"
out12="$(trial_in "$repo12")" && rc12=0 || rc12=$?
assert_refused "a fixup that empties its target" "$repo12" "$head12" "$rc12" "$out12" "the rebase failed without a conflict"

# /pre-merge's own fold has the same two kinds of abort (#675): only a stop with
# unmerged paths is a conflict. A signer or a hook that refuses is something
# else, and a message that calls it a conflict sends the operator to the wrong
# fix. Either way the branch is left as it was.
section "/pre-merge's fold: an abort that is not a conflict is not called one (#675)"
repo14="$sandbox/repo14"
clean_fixup_repo "$repo14"
head14="$(git -C "$repo14" rev-parse HEAD)"
# fold_refused <label> <global config>
fold_refused() {
    local out
    out="$(cd "$repo14" && env -u BASE_REF GIT_CONFIG_GLOBAL="$2" bash -c "$(fill_base "$fold_block_template" "")" 2>&1)"
    case "$out" in
        *"fold aborted: the rebase failed without a conflict"*) assert_eq ok ok "$1: the abort says it was not a conflict" ;;
        *) assert_eq "fold aborted: the rebase failed without a conflict ..." "$out" "$1: the abort says it was not a conflict" ;;
    esac
    case "$out" in
        *conflicted*) assert_eq "no conflict claimed" "$out" "$1: no conflict is claimed" ;;
        *) assert_eq ok ok "$1: no conflict is claimed" ;;
    esac
    assert_eq "$head14" "$(git -C "$repo14" rev-parse HEAD)" "$1: HEAD is where it was"
    assert_eq "" "$(git -C "$repo14" status --porcelain)" "$1: the tree is clean"
    [[ -d "$(git -C "$repo14" rev-parse --git-path rebase-merge)" ]] && r=in-progress || r=none
    assert_eq none "$r" "$1: no rebase is left in progress"
}
fold_refused "a failing signer" "$signing_config"
fold_refused "a refusing pre-rebase hook" "$hooks_config"
assert_eq "folded: tree unchanged" "$(run_fold "$repo14" 2>/dev/null)" "control: with neither, the same branch folds"

section "fold trial: a blocked leftover does not fail later fixups (#614 item 4)"
repo11="$sandbox/repo11"
mkdir -p "$repo11"
(
    cd "$repo11" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'one, rewritten\n' > one.txt
    git add one.txt && git commit -q -m 'feature: rewrite one'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
    printf 'one, fixed\n' > one.txt
    git add one.txt && git commit -q --fixup=HEAD~2 -m 'fix one' -m 'Fix-Findings-Run: 20261030T000002Z'
    # shellcheck disable=SC2016  # the hook body is literal text for sh
    printf '#!/bin/sh\ncase "$(head -1 "$1")" in "fixup! "*) exit 0 ;; *) echo "commit-msg: bad subject" >&2; exit 1 ;; esac\n' > .git/hooks/commit-msg
    chmod +x .git/hooks/commit-msg
)
point_origin_at_main "$repo11"
leftover11="$(git -C "$repo11" rev-parse HEAD)"
out11="$(trial_in "$repo11")" && rc11=0 || rc11=$?
[[ "$rc11" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "the first fixup conflicts and its recommit is refused: blocked"
assert_eq "$leftover11" "$(git -C "$repo11" rev-parse HEAD)" "the blocked fixup stays on the branch"
(
    cd "$repo11" || exit 1
    printf 'two, fixed\n' > two.txt
    git add two.txt && git commit -q --fixup=HEAD~1 -m 'fix two' -m 'Fix-Findings-Run: 20261030T000003Z'
)
clean11="$(git -C "$repo11" rev-parse HEAD)"
out11="$(trial_in "$repo11")" && rc11=0 || rc11=$?
assert_eq 0 "$rc11" "a clean fixup after a leftover: the block exits 0"
assert_eq "$clean11" "$(git -C "$repo11" rev-parse HEAD)" "a clean fixup after a leftover: it is not demoted"
assert_eq "fixup! feature: two" "$(git -C "$repo11" log -1 --format=%s)" "a clean fixup after a leftover: the subject is still fixup!"
case "$out11" in
    *"$leftover11"*"fold trial: clean"*) assert_eq ok ok "a clean fixup after a leftover: clean, and the leftover is named" ;;
    *) assert_eq "clean, naming $leftover11" "$out11" "a clean fixup after a leftover: clean, and the leftover is named" ;;
esac
# A skip that cannot move on must not spin: an AFK fixer has no one to stop it.
# Bounded (#686 box 13): a regression here spins, so it fails by name after a
# minute instead of hanging pre-push and CI. macOS ships no `timeout`.
out11="$(cd "$repo11" && run_bounded 60 env -u BASE_REF PATH="$fail_bin:$PATH" GIT_FAIL_VERB=--skip \
    bash -c "$fold_trial_block")" && rc11=0 || rc11=$?
[[ "$rc11" -ne 124 ]] && r=finished || r=timed-out
assert_eq finished "$r" "a rebase --skip that fails: the block finishes within the bound"
assert_refused "a rebase --skip that fails" "$repo11" "$clean11" "$rc11" "$out11" "rebase --skip did not move past"
# The skip must judge the new commit, not wave everything through: a second
# conflicting fixup after the leftover is still demoted, and the leftover stays.
rm "$repo11/.git/hooks/commit-msg"
(
    cd "$repo11" || exit 1
    printf 'one, fixed again\n' > one.txt
    git add one.txt && git commit -q --fixup=HEAD~4 -m 'fix one again' -m 'Fix-Findings-Run: 20261030T000004Z'
)
out11="$(trial_in "$repo11")" && rc11=0 || rc11=$?
assert_eq 0 "$rc11" "a conflicting fixup after a leftover: the block exits 0"
assert_eq "fix one again" "$(git -C "$repo11" log -1 --format=%s)" "a conflicting fixup after a leftover: it is still demoted"
case "$out11" in
    *"$leftover11"*) assert_eq ok ok "a conflicting fixup after a leftover: the demotion still names the leftover (#686 box 2)" ;;
    *) assert_eq "a line naming $leftover11" "$out11" "a conflicting fixup after a leftover: the demotion still names the leftover (#686 box 2)" ;;
esac
assert_eq "fixup! feature: one" "$(git -C "$repo11" log -1 --format=%s "$leftover11")" "the leftover itself is not touched"

section "fold trial: a conflict the fixup causes in a later commit still demotes"
# The stop is on an ordinary commit, not the fixup: 'three' adds a file the fixup
# adds earlier by moving up. Skipping that stop would call a conflict clean.
repo13="$sandbox/repo13"
clean_fixup_repo "$repo13"
(
    cd "$repo13" || exit 1
    git reset -q --hard HEAD~1
    printf 'three\n' > three.txt
    git add three.txt && git commit -q -m 'feature: three'
    git rm -q three.txt && git commit -q -m 'feature: drop three'
    printf 'three, from the fix\n' > three.txt
    git add three.txt && git commit -q --fixup=HEAD~2 -m 'add three' -m 'Fix-Findings-Run: 20261030T000005Z'
)
out13="$(trial_in "$repo13")" && rc13=0 || rc13=$?
assert_eq 0 "$rc13" "a later commit conflicts: the block exits 0"
assert_eq "fold trial: would not fold; recommitted as an ordinary commit" "$out13" "a later commit conflicts: the trial names the demotion"
assert_eq "add three" "$(git -C "$repo13" log -1 --format=%s)" "a later commit conflicts: the fixup is demoted"

# The limits the fold-trial prose states (#686 boxes 1, 4, 12), each with its
# own cause. These pin today's behavior, wrong answer included, so a change to
# any is a decision someone makes on purpose rather than a drift nobody sees.
section "fold trial, stated limit: signing is off in the trial, so a repo-local signer is not exercised"
repo15="$sandbox/repo15"
clean_fixup_repo "$repo15"
git -C "$repo15" config commit.gpgsign true
git -C "$repo15" config gpg.program "$failing_signer"
head15="$(git -C "$repo15" rev-parse HEAD)"
git -C "$repo15" commit -q --allow-empty -m 'probe' 2>/dev/null && r=signed || r=refused
assert_eq refused "$r" "the instrument: the repo-local failing signer refuses a real commit in the repository"
assert_eq "fold trial: clean" "$(trial_in "$repo15")" "a repo-local failing signer: the trial reports clean"
assert_eq "$head15" "$(git -C "$repo15" rev-parse HEAD)" "a repo-local failing signer: the fixup is not demoted"
case "$(run_fold "$repo15")" in
    *"fold aborted: "*) assert_eq ok ok "a repo-local failing signer: /pre-merge's real fold aborts where the trial said clean" ;;
    *) assert_eq "fold aborted: ..." "$(run_fold "$repo15")" "a repo-local failing signer: /pre-merge's real fold aborts where the trial said clean" ;;
esac
assert_eq "$head15" "$(git -C "$repo15" rev-parse HEAD)" "a repo-local failing signer: the aborted fold leaves HEAD where it was"

# The clone-config claim needs a repo-local setting the trial's own -c flags do
# not override. The signer above cannot show it (the trial turns signing off
# itself), so a repo-local merge driver does, and a --shared clone is checked
# below to carry none of the repository's own config: it resolves a text conflict in the
# repository and is absent in the clone, so the trial demotes a fixup the real
# fold applies (#686 box 4). A trial that started reading the repository's config
# would report clean here.
section "fold trial, stated limit: a repo-local merge driver does not run in the trial"
repo17="$sandbox/repo17"
mkdir -p "$repo17"
(
    cd "$repo17" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'one.txt merge=theirs\n' > .gitattributes
    printf 'base\n' > base.txt
    git add .gitattributes base.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'one, edited later\n' > one.txt
    git add one.txt && git commit -q -m 'feature: edit one'
    printf 'one, fixed\n' > one.txt
    git add one.txt && git commit -q --fixup=HEAD~1 -m 'fix one' -m 'Fix-Findings-Run: 20261030T000006Z'
    git config merge.theirs.driver 'cp %B %A'
)
point_origin_at_main "$repo17"
clone17="$sandbox/repo17-clone"
git clone -q --shared --no-checkout "$repo17" "$clone17"
assert_eq "" "$(git -C "$clone17" config --get merge.theirs.driver || true)" \
    "a --shared clone carries none of the repository's own config: no merge.theirs.driver"
real17="$sandbox/repo17-real"
cp -R "$repo17" "$real17"
run_fold "$real17" >/dev/null
assert_eq "feature: edit one" "$(git -C "$real17" log -1 --format=%s)" "a repo-local merge driver: the real fold applies the fixup (the driver resolves the text conflict)"
assert_eq "one, fixed" "$(git -C "$real17" show HEAD~1:one.txt)" "a repo-local merge driver: the folded commit carries the fix (the take-theirs driver kept the fix's text, not the later edit's)"
out17="$(trial_in "$repo17")" && rc17=0 || rc17=$?
assert_eq 0 "$rc17" "a repo-local merge driver: the block exits 0"
assert_eq "fold trial: would not fold; recommitted as an ordinary commit" "$out17" \
    "a repo-local merge driver: the trial does not run it, so it demotes what the real fold applies"
assert_eq "fix one" "$(git -C "$repo17" log -1 --format=%s)" "a repo-local merge driver: the fixup is demoted"

section "fold trial, stated limit: a leftover that breaks a later ordinary commit misjudges a clean fixup"
# #665's four commits: one, three, drop three, two. The blocked leftover
# `fixup! one` adds three.txt, so the rebase stops on 'feature: three', an
# ordinary commit the skip loop cannot pass. A clean `fixup! two` after it is
# then reported blocked while the recommit hook refuses, and demoted once it does not.
repo16="$sandbox/repo16"
mkdir -p "$repo16"
(
    cd "$repo16" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c feature
    printf 'one\n' > one.txt
    git add one.txt && git commit -q -m 'feature: one'
    printf 'three\n' > three.txt
    git add three.txt && git commit -q -m 'feature: three'
    git rm -q three.txt && git commit -q -m 'feature: drop three'
    printf 'two\n' > two.txt
    git add two.txt && git commit -q -m 'feature: two'
    printf 'three, from the leftover\n' > three.txt
    git add three.txt && git commit -q --fixup=HEAD~3 -m 'add three' -m 'Fix-Findings-Run: 20261118T000002Z'
    # shellcheck disable=SC2016  # the hook body is literal text for sh
    printf '#!/bin/sh\ncase "$(head -1 "$1")" in "fixup! "*) exit 0 ;; *) echo "commit-msg: bad subject" >&2; exit 1 ;; esac\n' > .git/hooks/commit-msg
    chmod +x .git/hooks/commit-msg
)
point_origin_at_main "$repo16"
assert_fixture_committed "$repo16" "the four-commit leftover fixture" 0 6 one.txt two.txt three.txt
leftover16="$(git -C "$repo16" rev-parse HEAD)"
out16="$(trial_in "$repo16")" && rc16=0 || rc16=$?
[[ "$rc16" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "the leftover conflicts on a later ordinary commit and its recommit is refused: blocked"
(
    cd "$repo16" || exit 1
    printf 'two, fixed\n' > two.txt
    git add two.txt && git commit -q --fixup=HEAD~1 -m 'fix two' -m 'Fix-Findings-Run: 20261118T000003Z'
)
clean16="$(git -C "$repo16" rev-parse HEAD)"
out16="$(trial_in "$repo16")" && rc16=0 || rc16=$?
[[ "$rc16" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "a clean fixup behind that leftover, recommit refused: reported blocked"
case "$out16" in
    *"fold trial: would not fold, and the recommit failed"*) assert_eq ok ok "a clean fixup behind that leftover, recommit refused: the trial calls it a conflict" ;;
    *) assert_eq "fold trial: would not fold, and the recommit failed ..." "$out16" "a clean fixup behind that leftover, recommit refused: the trial calls it a conflict" ;;
esac
assert_eq "$clean16" "$(git -C "$repo16" rev-parse HEAD)" "a clean fixup behind that leftover, recommit refused: HEAD is untouched"
rm "$repo16/.git/hooks/commit-msg"
out16="$(trial_in "$repo16")" && rc16=0 || rc16=$?
assert_eq "0 fold trial: would not fold; recommitted as an ordinary commit" "$rc16 $out16" \
    "a clean fixup behind that leftover, no hook: demoted"
assert_eq "fix two" "$(git -C "$repo16" log -1 --format=%s)" "a clean fixup behind that leftover, no hook: the fixup! subject is gone"
assert_eq "fixup! feature: one" "$(git -C "$repo16" log -1 --format=%s "$leftover16")" "the leftover itself is not touched"

# --- 12d. A stacked slice: the fixup target and the trial use the fold's base (RB-2)
# The fold rebases from the sibling's tip, so a sibling commit is not in its
# todo list and a fixup of it would merge as `fixup!`. Measured from main, the
# fixup-target block named the sibling's commit and the trial called it clean.
# Only main is on origin, so the branch reads as unshared.
section "stacked slice: no fixup target on a sibling's line, and the trial folds from the sibling"
repo_sf="$sandbox/repo-stacked-fixup"
mkdir -p "$repo_sf"
(
    cd "$repo_sf" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c s1
    printf 's\n' > s.txt
    git add s.txt && git commit -q -m 's1 adds s'
    git switch -q -c f
    printf 'f\n' > f.txt
    git add f.txt && git commit -q -m 'f adds f'
)
point_origin_at_main "$repo_sf"
s1_sha="$(git -C "$repo_sf" rev-parse s1)"
f_sha="$(git -C "$repo_sf" rev-parse f)"
# run_stacked_target <placeholder value> <file> — what the block printed for
# line 1, and its exit status as the function's own.
run_stacked_target() {
    (cd "$repo_sf" && env -u BASE_REF -u BASE_BRANCH TARGET_FILE="$2" TARGET_START=1 TARGET_END=1 \
        bash -c "$(fill_base "$fixup_target_template" "$1")" 2>&1)
}
assert_eq "FIXUP_TARGET=$s1_sha" "$(run_stacked_target "" s.txt)" \
    "control: with an empty placeholder the sibling's line is measured from main and has a target"
assert_eq "FIXUP_TARGET=" "$(run_stacked_target s1 s.txt)" \
    "stacked on s1: a line the sibling wrote has no fixup target"
assert_eq "FIXUP_TARGET=$f_sha" "$(run_stacked_target s1 f.txt)" \
    "stacked on s1: a line this slice wrote still has its commit as the target"
out_sf="$(run_stacked_target no-such-sibling f.txt)" && rc_sf=0 || rc_sf=$?
[[ "$rc_sf" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "stacked on a branch that does not resolve: the fixup-target block stops"
case "$out_sf" in
    *FIXUP_TARGET=*) assert_eq "no answer printed" "$out_sf" "stacked on a branch that does not resolve: no target is printed" ;;
    *) assert_eq ok ok "stacked on a branch that does not resolve: no target is printed" ;;
esac
# The trial, stacked: a fixup of this slice's own commit folds, and the trial
# and the fold agree on it, both measured from s1.
(
    cd "$repo_sf" || exit 1
    printf 'f, fixed\n' > f.txt
    git add f.txt && git commit -q --fixup="$f_sha" -m 'fix f' -m 'Fix-Findings-Run: 20261118T000000Z'
)
head_sf="$(git -C "$repo_sf" rev-parse HEAD)"
assert_eq "fold trial: clean" "$(cd "$repo_sf" && BASE_REF=origin/nope bash -c "$(fill_base "$fold_trial_template" s1)" 2>&1)" \
    "stacked on s1, a stale BASE_REF in the environment: the trial folds from the sibling and reports clean"
assert_eq "$head_sf" "$(git -C "$repo_sf" rev-parse HEAD)" "stacked on s1: a clean trial leaves the fixup as it was"
out_sf="$(cd "$repo_sf" && env -u BASE_REF bash -c "$(fill_base "$fold_trial_template" no-such-sibling)" 2>&1)" && rc_sf=0 || rc_sf=$?
[[ "$rc_sf" -ne 0 ]] && r=nonzero || r=zero
assert_eq nonzero "$r" "stacked on a branch that does not resolve: the trial stops"
case "$out_sf" in
    *"fold trial aborted: neither origin/no-such-sibling nor no-such-sibling resolves"*) assert_eq ok ok "stacked on a branch that does not resolve: the trial says why" ;;
    *) assert_eq "fold trial aborted: neither ..." "$out_sf" "stacked on a branch that does not resolve: the trial says why" ;;
esac
case "$(run_fold "$repo_sf" s1)" in
    *"folded: tree unchanged"*) assert_eq ok ok "stacked on s1: /pre-merge's fold applies, as the trial said" ;;
    *) assert_eq "folded: tree unchanged" "aborted" "stacked on s1: /pre-merge's fold applies, as the trial said" ;;
esac
assert_eq "" "$(git -C "$repo_sf" log --format=%s s1..HEAD | grep '^fixup! ' || true)" \
    "stacked on s1: after the fold no fixup! commit is left on the branch"

# A fixup the fork point decides (RB-2): this slice rewrote the sibling's line,
# and a fixup! names the sibling's commit. Rebased from main it would fold into
# that commit and conflict with this slice's rewrite; rebased from s1, where the
# fold actually starts, the target is not in the todo list and the fixup stays
# in place. The stacked trial must say clean, so a trial measured from main fails.
repo_fp="$sandbox/repo-stacked-forkpoint"
mkdir -p "$repo_fp"
(
    cd "$repo_fp" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    printf 'base\n' > base.txt
    git add base.txt && git commit -q -m 'base'
    git switch -q -c s1
    printf 's\n' > s.txt
    git add s.txt && git commit -q -m 's1 adds s'
    git switch -q -c f
    printf 's, rewritten by f\n' > s.txt
    git add s.txt && git commit -q -m 'f rewrites s'
    printf 's, fixed\n' > s.txt
    git add s.txt && git commit -q --fixup="$(git rev-parse s1)" -m 'fix s' -m 'Fix-Findings-Run: 20261118T000001Z'
)
point_origin_at_main "$repo_fp"
head_fp="$(git -C "$repo_fp" rev-parse HEAD)"
assert_eq "fold trial: clean" "$(cd "$repo_fp" && env -u BASE_REF bash -c "$(fill_base "$fold_trial_template" s1)" 2>&1)"     "stacked on s1, a fixup that folds only from main: the trial measures from the sibling and reports clean"
assert_eq "$head_fp" "$(git -C "$repo_fp" rev-parse HEAD)" "stacked on s1, a fixup that folds only from main: the fixup is left as it was"
assert_eq "fold trial: would not fold; recommitted as an ordinary commit" "$(cd "$repo_fp" && env -u BASE_REF bash -c "$(fill_base "$fold_trial_template" "")" 2>&1)"     "control: the same fixup measured from main conflicts, so the fork point decides the verdict"

section "fold trial and fixup target: the blocks run under zsh, the shell an agent has on macOS"
# docs/solutions/patterns/skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md:
# the blocks run in zsh in a real session, so each path runs there too. A missing
# zsh skips locally and fails when CI is set (#686 box 9).
zsh_arms() {
    zsh_clean="$(cd "$repo10" && env -u BASE_REF zsh -f -c "$fold_trial_block" 2>&1)"
    assert_eq "fold trial: clean" "$zsh_clean" "zsh: a clean fixup reports clean"
    : > "$TRIAL_TMP_LOG"
    zsh_out="$(cd "$repo10" && env -u BASE_REF PATH="$fail_bin:$PATH" GIT_FAIL_VERB=clone \
        zsh -f -c "$fold_trial_block" 2>&1)" && rc10=0 || rc10=$?
    assert_refused "zsh, a failing clone" "$repo10" "$head10" "$rc10" "$zsh_out" "the throwaway clone failed"
    assert_trial_dir_gone "zsh, a failing clone"
    # The conflict path: a fixup a later commit rewrote over is demoted.
    local zc="$sandbox/zsh-conflict" zs="$sandbox/zsh-skip" zt="$sandbox/zsh-target" out rc
    mkdir -p "$zc"
    (
        cd "$zc" || exit 1
        git init -q -b main . && git config user.email t@example.com && git config user.name t
        printf 'base\n' > base.txt && git add base.txt && git commit -q -m base
        git switch -q -c feature
        printf 'one\n' > one.txt && git add one.txt && git commit -q -m 'feature: one'
        printf 'one, rewritten\n' > one.txt && git add one.txt && git commit -q -m 'feature: rewrite one'
        printf 'one, fixed\n' > one.txt && git add one.txt && git commit -q --fixup=HEAD~1 -m 'fix one'
    )
    point_origin_at_main "$zc"
    out="$(cd "$zc" && env -u BASE_REF zsh -f -c "$fold_trial_block" 2>&1)" && rc=0 || rc=$?
    assert_eq "0 fold trial: would not fold; recommitted as an ordinary commit" "$rc $out" "zsh: a conflicting fixup is demoted"
    assert_eq "fix one" "$(git -C "$zc" log -1 --format=%s)" "zsh: the demoted commit carries the fixer's subject"
    # The skip path: a leftover that will not fold is skipped and named, and the
    # clean fixup after it stays a fixup.
    mkdir -p "$zs"
    (
        cd "$zs" || exit 1
        git init -q -b main . && git config user.email t@example.com && git config user.name t
        printf 'base\n' > base.txt && git add base.txt && git commit -q -m base
        git switch -q -c feature
        printf 'one\n' > one.txt && git add one.txt && git commit -q -m 'feature: one'
        printf 'one, rewritten\n' > one.txt && git add one.txt && git commit -q -m 'feature: rewrite one'
        printf 'two\n' > two.txt && git add two.txt && git commit -q -m 'feature: two'
        printf 'one, fixed\n' > one.txt && git add one.txt && git commit -q --fixup=HEAD~2 -m 'fix one'
        printf 'two, fixed\n' > two.txt && git add two.txt && git commit -q --fixup=HEAD~1 -m 'fix two'
    )
    point_origin_at_main "$zs"
    local leftover_z head_z
    leftover_z="$(git -C "$zs" rev-parse HEAD~1)"
    head_z="$(git -C "$zs" rev-parse HEAD)"
    out="$(cd "$zs" && run_bounded 60 env -u BASE_REF zsh -f -c "$fold_trial_block")" && rc=0 || rc=$?
    case "$rc:$out" in
        "0:"*"$leftover_z"*"fold trial: clean"*) assert_eq ok ok "zsh: a leftover is skipped and named, and the clean fixup reports clean" ;;
        *) assert_eq "0:fold trial: clean ... $leftover_z" "$rc:$out" "zsh: a leftover is skipped and named, and the clean fixup reports clean" ;;
    esac
    assert_eq "$head_z" "$(git -C "$zs" rev-parse HEAD)" "zsh: the clean fixup after a leftover is not demoted"
    # The fixup-target block: one commit's line is its target, a base line has none.
    mkdir -p "$zt"
    (
        cd "$zt" || exit 1
        git init -q -b main . && git config user.email t@example.com && git config user.name t
        printf 'a\nb\n' > f.txt && git add f.txt && git commit -q -m base
        git switch -q -c feature
        printf 'a\nB\n' > f.txt && git commit -q -am 'feature: change b'
    )
    point_origin_at_main "$zt"
    out="$(cd "$zt" && env -u BASE_REF TARGET_FILE=f.txt TARGET_START=2 TARGET_END=2 zsh -f -c "$fixup_target_block" 2>/dev/null)"
    assert_eq "FIXUP_TARGET=$(git -C "$zt" rev-parse HEAD)" "$out" "zsh: the fixup-target block names the one commit that wrote the line"
    out="$(cd "$zt" && env -u BASE_REF TARGET_FILE=f.txt TARGET_START=1 TARGET_END=1 zsh -f -c "$fixup_target_block" 2>/dev/null)"
    assert_eq "FIXUP_TARGET=" "$out" "zsh: a base line has no fixup target"
}
if command -v zsh >/dev/null 2>&1; then
    zsh_arms
elif [ -n "${CI:-}" ]; then
    assert_eq "zsh on PATH" "zsh absent" "the fold-trial and fixup-target blocks ran under zsh (CI is set, so a missing zsh fails)"
else
    printf '  SKIP zsh is not on PATH, so the fold-trial and fixup-target blocks ran under bash only\n'
fi

# --- 13. "Unshared" means no upstream AND not on the push remote (#566, #572) --
# A plain `git push origin <branch>` publishes the branch with no upstream, so
# the `@{u}` check alone would keep deferring review of a branch others can read.
# A remote that cannot be asked is not an answer of "absent" (#572): ls-remote
# prints nothing and exits nonzero, and reading only its output called a pushed
# branch private. The branch is looked up on the remote it pushes to, and only
# an exact refs/heads/<branch> counts. The whole block is run in each state and
# its printed verdict is the assertion.
section "unshared test: the verdict on the push remote, in every state the prose names"
bare5="$sandbox/bare5.git"
fork5="$sandbox/fork5.git"
repo5="$sandbox/repo5"
git init -q --bare "$bare5"
git init -q --bare "$fork5"
git init -q -b main "$repo5"
(
    cd "$repo5" || exit 1
    git config user.email t@example.com
    git config user.name t
    git remote add origin "$bare5"
    git remote add fork "$fork5"
    printf 'a\n' > f.txt
    git add f.txt && git commit -q -m 'base'
    git switch -q -c feature
)
run_shared() { (cd "$repo5" && bash -c "$shared_block" 2>/dev/null); }
# The same block under zsh (#574), the shell an agent runs it in on macOS:
# each verdict below that names "zsh" is checked in both shells.
have_zsh=no
if command -v zsh >/dev/null 2>&1; then
    have_zsh=yes
elif [ -n "${CI:-}" ]; then
    assert_eq "zsh on PATH" "zsh absent" "the shared-branch block ran under zsh (CI is set, so a missing zsh fails)"
else
    printf '  SKIP zsh is not on PATH, so the shared-branch block runs under bash only\n'
fi
# shared_both <expected> <label> — the verdict in bash, and in zsh when present.
shared_both() {
    assert_eq "$1" "$(run_shared)" "$2"
    [ "$have_zsh" = no ] || assert_eq "$1" "$(cd "$repo5" && zsh -f -c "$shared_block" 2>/dev/null)" "zsh: $2"
}
shared_both "shared: no" "unpushed branch, origin reachable: unshared"
git -C "$repo5" push -q origin feature:alice/feature 2>/dev/null
assert_eq "shared: no" "$(run_shared)" "origin holds alice/feature, not feature: an exact refs/heads/ match only, so unshared"
# ls-remote matches a pattern against the tail of a ref name, so even the full
# refs/heads/feature pattern matches a branch named x/refs/heads/feature.
git -C "$repo5" push -q origin feature:x/refs/heads/feature 2>/dev/null
assert_eq "refs/heads/x/refs/heads/feature" "$(git -C "$repo5" ls-remote --heads origin refs/heads/feature | cut -f2)" \
    "fixture precondition: ls-remote's own pattern matches refs/heads/x/refs/heads/feature"
shared_both "shared: no" "origin holds x/refs/heads/feature, which ls-remote's pattern matches: the exact match still says unshared"
git -C "$repo5" remote set-url origin "$sandbox/no-such-remote.git"
shared_both "shared: yes" "origin cannot be reached: ls-remote fails, so shared"
git -C "$repo5" remote set-url origin "$bare5"
git -C "$repo5" push -q fork feature 2>/dev/null
assert_eq "shared: no" "$(run_shared)" "control: pushed only to fork, and nothing says fork is the push remote: origin is asked, unshared"
git -C "$repo5" config remote.pushDefault fork
shared_both "shared: yes" "remote.pushDefault is fork, which holds the branch: shared"
git -C "$repo5" config branch.feature.pushRemote origin
assert_eq "shared: no" "$(run_shared)" "branch.feature.pushRemote is origin, which outranks remote.pushDefault: unshared"
git -C "$repo5" config --unset branch.feature.pushRemote
git -C "$repo5" config --unset remote.pushDefault
git -C "$repo5" config branch.feature.remote fork
assert_eq "shared: yes" "$(run_shared)" "branch.feature.remote is fork, which holds the branch: shared"
git -C "$repo5" config --unset branch.feature.remote
git -C "$repo5" push -q origin feature 2>/dev/null
assert_eq "" "$(git -C "$repo5" rev-parse -q --verify '@{u}' 2>/dev/null)" "plain push: still no upstream"
shared_both "shared: yes" "plain push to origin without -u: shared"
git -C "$repo5" branch -q --set-upstream-to=origin/feature
git -C "$repo5" remote set-url origin "$sandbox/no-such-remote.git"
assert_eq "shared: yes" "$(run_shared)" "an upstream is set: shared, whatever the remote answers"
git -C "$repo5" remote set-url origin "$bare5"

# --- 14. A released lock (#807) -----------------------------------------------
# A release records the head it opened the lock at. Two states decide whether
# the next review may start there. When a fold replaced the stamped commit and
# the released head carries the stamped tree, it may, and it is the only start
# that is not the whole slice. When the head had already moved past the stamp,
# it may not: starting there would stamp the commits in between with nobody
# having read them, so the review starts at the stamp.
section "released lock: the delta starts at the released head, and never skips an unreviewed commit"
release_scope_case() {  # $1 = shell, $2 = folded | past-stamp
    local sh="$1" kind="$2" r="$sandbox/release-$1-$2" stamped released out
    mkdir -p "$r"
    git init -q -b main "$r"
    git -C "$r" config user.email t@example.com
    git -C "$r" config user.name t
    printf '.claude/\n' > "$r/.git/info/exclude"
    printf 'base %s\n' "$r" > "$r/base.txt"
    git -C "$r" add base.txt
    git -C "$r" commit -q -m "base $r"
    git -C "$r" switch -q -c feature
    printf 'one\n' > "$r/one.txt"
    git -C "$r" add one.txt
    git -C "$r" commit -q -m 'feature: one'
    stamped="$(git -C "$r" rev-parse HEAD)"
    if [[ "$kind" == folded ]]; then
        git -C "$r" commit -q --amend -m 'feature: one, reworded'
    else
        printf 'fix\n' > "$r/fix.txt"
        git -C "$r" add fix.txt
        git -C "$r" commit -q -m 'a fix no review has read'
    fi
    released="$(git -C "$r" rev-parse HEAD)"
    out="$(cd "$r" && GH_STUB_BODY="$(stamped_body "$stamped")" CLAUDE_PROJECT_DIR="$r" \
        bash "$sidecar_sh" stamp release feature --reason 'asked for' 2>&1)"
    if [[ "$kind" == folded ]]; then
        assert_eq "lock released: make the edit, then re-run /pre-merge to review $released..HEAD and re-stamp" "$out" \
            "$sh, folded then released: the verb names the released head"
    else
        assert_eq "lock released: make the edit, then re-run /pre-merge to review $stamped..HEAD and re-stamp" "$out" \
            "$sh, released past the stamp: the verb names the stamp, where the unread commits start"
    fi
    printf 'edit\n' > "$r/edit.txt"
    git -C "$r" add edit.txt
    git -C "$r" commit -q -m 'the requested edit'
    out="$(cd "$r" && GH_STUB_BODY="$(stamped_body "$stamped")" CLAUDE_PROJECT_DIR="$r" env -u BASE_REF "$sh" -c "$scope_block" 2>&1)"
    if [[ "$kind" == folded ]]; then
        assert_eq "review scope: post-stamp delta, from $released|edit.txt" \
            "$(printf '%s\n' "$out" | grep '^review scope:' || true)|$(stat_files "$out")" \
            "$sh, folded then released: the review starts at the released head"
    else
        assert_eq "review scope: post-stamp delta, from $stamped|edit.txt fix.txt" \
            "$(printf '%s\n' "$out" | grep '^review scope:' || true)|$(stat_files "$out")" \
            "$sh, released past the stamp: the review still reads the commit made before the release"
    fi
}
release_scope_case bash folded
release_scope_case bash past-stamp
if [[ "$have_zsh" == yes ]]; then
    release_scope_case zsh folded
    release_scope_case zsh past-stamp
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
