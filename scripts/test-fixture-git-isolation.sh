#!/usr/bin/env bash
# test-fixture-git-isolation.sh — no test suite may write into the repository
# that a git hook's environment points at.
#
# THE INCIDENT (#429, on PR #426). A git hook runs with GIT_DIR exported. A
# suite that builds a scratch fixture repo and runs `git init` or `git config`
# in it without first clearing that variable writes to the REAL repository
# instead. Two pushes left `core.bare = true`, a temp `core.hooksPath`, and a
# fixture `[user]` identity in the shared `.git/config` — the one the main
# checkout and every worktree read. The second push "succeeded" only because
# the first had switched hooks off. Run outside a hook, every suite passed and
# left the config clean, so nothing short of reproducing the hook environment
# can see the defect.
#
# WHY A MECHANISM RATHER THAN A RULE. The guard is one line
# (`unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE`), and nothing made a suite
# carry it. The next suite written will not either, unless something fails when
# it is missing.
#
# WHAT THIS DOES. Clones this repo into a scratch directory, adds a linked
# worktree to the clone, overlays the working tree onto it (so uncommitted and
# untracked suites are exercised as written), and runs every suite pre-push
# runs — read from lefthook.yml, args included, and checked to be exactly
# scripts/test-*.sh minus this one, so a suite registered in a shape the
# extraction cannot read fails here instead of dropping out — from that
# worktree with GIT_DIR exported at the worktree's git dir, the way a hook run
# from a Conductor workspace sees it. After each suite the clone's shared
# config is compared byte-for-byte with its snapshot, and so are its refs and
# the worktree's HEAD; a difference fails this suite, names the suite that
# caused it, and rebuilds the worktree before the next one runs. A suite
# failing on its own is reported but is not this suite's verdict: it may fail
# for reasons unrelated to isolation (a missing tool, network), and its own
# registration already gates that.
#
# WHY A LINKED WORKTREE AND NOT A PLAIN CLONE. A bare `git init` under an
# inherited GIT_DIR re-initializes the repository GIT_DIR names, and git
# guesses `core.bare` from that path: a GIT_DIR named `.git` stays non-bare and
# leaves the config byte-identical, while a worktree's
# `.git/worktrees/<name>` flips the shared config to `core.bare = true`. The
# first draft of this suite simulated a plain clone and passed
# test-post-review-edit-lock.sh, the suite that wrote #429's `core.bare`.
#
# Before trusting the instrument it is run against planted suites, two that
# leak in each of those shapes and one that guards, and must tell them apart.
#
# WHY REFS TOO (#374). The same leak that writes the config also commits into
# the repository GIT_DIR names: a sandbox pre-push moved the pushing
# worktree's branch to fixture commits and left a stray `feature` branch in the
# shared refs. A config-only comparison passes a suite that does only that.
#
# WHAT THIS DOES NOT CATCH. A write to anything but the shared `config`, the
# refs, and the worktree's HEAD (hooks, objects, the index, the worktree's own
# files), and a leak on a code path a suite
# only reaches under conditions this run does not reproduce — a suite that
# exits early in the scratch worktree never gets to its fixture. It simulates
# GIT_DIR alone; that is the variable every observed leak followed.
#
# WHY CI ONLY, NOT PRE-PUSH (#442). It re-runs every suite, so it took about
# two minutes and doubled pre-push CPU. Run locally it cannot prevent what it
# detects: pre-push runs the leaky suite itself in parallel, so the real config
# is written before this reports. And #429's leak left a dead core.hooksPath,
# which switches local hooks off, so local hooks are the least reliable place
# to catch this class. Scoping the hook to pushes that touch shell scripts does
# not work either: several suites run blocks taken from SKILL.md files.

set -u

# Run from a hook, the hook's GIT_DIR points at the real repo here. Clear it
# before any git call; children get the scratch one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
self="scripts/$(basename "$0")"

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
leaks=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

clone="$tmp/clone"
wt="$tmp/wt"
git clone -q "$repo_root" "$clone" || { echo "FATAL clone failed"; exit 1; }
git -C "$clone" worktree add -q --detach "$wt" HEAD || { echo "FATAL worktree add failed"; exit 1; }
wt_gitdir="$(git -C "$wt" rev-parse --absolute-git-dir)"
case "$wt_gitdir" in */.git/worktrees/*) ;; *) echo "FATAL $wt_gitdir is not a linked worktree's git dir"; exit 1 ;; esac
# sync_worktree — reset the worktree's index and files to its HEAD, then
# overlay the working tree: tracked files as they are now, plus untracked
# files that are not ignored. A tracked file deleted in the tree is deleted.
sync_worktree() {
  git -C "$wt" reset -q --hard HEAD && git -C "$wt" clean -qfdx || return 1
  (
    cd "$repo_root" || exit 1
    git ls-files -z -co --exclude-standard | while IFS= read -r -d '' f; do
      if [ -e "$f" ] || [ -L "$f" ]; then
        mkdir -p "$wt/$(dirname "$f")"
        cp -pP "$f" "$wt/$f"
      else
        rm -f "$wt/$f"
      fi
    done
  )
}
sync_worktree || { echo "FATAL overlaying the working tree onto $wt failed"; exit 1; }
cfg="$clone/.git/config"
[ -f "$cfg" ] || { echo "FATAL $cfg missing after clone"; exit 1; }

# refs_state — every ref in the clone, plus the worktree's HEAD (detached, so
# a fixture commit moves it without touching any ref).
refs_state() {
  git -C "$clone" for-each-ref --format='%(refname) %(objectname)'
  printf 'worktree HEAD %s\n' "$(git -C "$wt" rev-parse HEAD)"
}

# tree_state — the worktree's index and files, as status sees them against HEAD.
tree_state() {
  git -C "$wt" status --porcelain=v1 --untracked-files=all
}

# run_isolated <command...> — run in the worktree with a hook's GIT_DIR, then
# report whether the shared config, the refs, or the worktree's HEAD moved.
# Restores them either way, config first: a leaked `core.bare = true` would
# otherwise break the git calls that restore the refs. After a leak the
# worktree is rebuilt too, because the write that moved HEAD may also have
# changed the index or deleted files, and a later suite run against that tree
# can exit before reaching its fixture and so hide a second leak.
leaked_diff=""
run_isolated() {
  cp "$cfg" "$tmp/config.before"
  refs_state >"$tmp/refs.before"
  (cd "$wt" && GIT_DIR="$wt_gitdir" "$@") </dev/null >"$tmp/out" 2>&1
  local rc=$?
  leaked_diff=""
  if ! cmp -s "$tmp/config.before" "$cfg"; then
    leaked_diff="$(diff "$tmp/config.before" "$cfg")"
    cp "$tmp/config.before" "$cfg"
  fi
  refs_state >"$tmp/refs.after"
  if ! cmp -s "$tmp/refs.before" "$tmp/refs.after"; then
    leaked_diff="${leaked_diff:+$leaked_diff
}$(diff "$tmp/refs.before" "$tmp/refs.after")"
    local ref sha
    while read -r ref sha; do
      git -C "$clone" show-ref --verify -q "$ref" && ! grep -q "^$ref " "$tmp/refs.before" \
        && git -C "$clone" update-ref -d "$ref"
    done <"$tmp/refs.after"
    while read -r ref sha; do
      case "$ref" in worktree) git -C "$wt" update-ref --no-deref HEAD "${sha#HEAD }" ;;
                     *) git -C "$clone" update-ref "$ref" "$sha" ;; esac
    done <"$tmp/refs.before"
  fi
  if [ -n "$leaked_diff" ]; then
    sync_worktree || { echo "FATAL rebuilding $wt after a leak failed"; exit 1; }
  fi
  return $rc
}

# --- Apparatus check: the instrument must tell a leak from a guard. ---------
cat >"$tmp/leaky-init.sh" <<'EOF'
d=$(mktemp -d); git -C "$d" init -q; rm -rf "$d"
EOF
cat >"$tmp/leaky-config.sh" <<'EOF'
d=$(mktemp -d); git init -q "$d"; git -C "$d" config user.email leak@test; rm -rf "$d"
EOF
cat >"$tmp/leaky-ref.sh" <<'EOF'
git branch -f feature HEAD
EOF
cat >"$tmp/leaky-head.sh" <<'EOF'
git -c user.name=fixture -c user.email=fixture@test commit -q --allow-empty -m fixture
EOF
cat >"$tmp/leaky-tree.sh" <<'EOF'
git rm -qf lefthook.yml && git -c user.name=fixture -c user.email=fixture@test commit -q -m fixture
EOF
cat >"$tmp/guarded.sh" <<'EOF'
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
d=$(mktemp -d); git -C "$d" init -q; git -C "$d" config user.email leak@test; rm -rf "$d"
EOF
refs_state >"$tmp/refs.base"; cp "$cfg" "$tmp/config.base"; tree_state >"$tmp/tree.base"
for shape in init config ref head tree; do
  run_isolated bash "$tmp/leaky-$shape.sh"
  if [ -n "$leaked_diff" ]; then ok "apparatus: a planted unguarded $shape write is detected"
  else bad "apparatus: a planted unguarded $shape write was NOT detected — the simulated hook env is not reaching children"; fi
done
# Restoration must hold, or every later suite is measured against a moved base.
refs_state >"$tmp/refs.now"; tree_state >"$tmp/tree.now"
if cmp -s "$tmp/refs.base" "$tmp/refs.now" && cmp -s "$tmp/config.base" "$cfg" \
  && cmp -s "$tmp/tree.base" "$tmp/tree.now"; then
  ok "apparatus: planted leaks are rolled back before the next suite runs"
else bad "apparatus: a planted leak survived its rollback — later verdicts are unreliable"; fi
run_isolated bash "$tmp/guarded.sh"
if [ -z "$leaked_diff" ]; then ok "apparatus: a planted guarded suite is not flagged"
else bad "apparatus: a planted guarded suite was flagged — the check is not measuring the suite"; fi

# --- Every suite pre-push runs, as pre-push runs it. -------------------------
# read_suites <lefthook.yml> <out> — write the suite invocations the
# extraction can read to <out>, and print one line per suite on disk that it
# did not read, or read but not on disk. A `run: |` block or an env-prefixed
# entry is invisible to the extraction, so the set is checked against
# scripts/test-*.sh rather than trusted.
read_suites() {
  sed -n 's/^[[:space:]]*run: \(bash scripts\/test-[A-Za-z0-9_-]*\.sh.*\)$/\1/p' "$1" \
    | grep -vF -- "$self" >"$2" || true
  awk '{print $2}' "$2" | sort -u >"$tmp/suites.read"
  (cd "$repo_root" && printf '%s\n' scripts/test-*.sh) | grep -vxF -- "$self" | sort >"$tmp/suites.disk"
  comm -23 "$tmp/suites.disk" "$tmp/suites.read" | sed 's/$/ is on disk but was not read from lefthook.yml/'
  comm -13 "$tmp/suites.disk" "$tmp/suites.read" | sed 's/$/ was read from lefthook.yml but is not on disk/'
}

# Apparatus: a suite registered as a `run: |` block must show up as unread.
sed 's/^\([[:space:]]*\)run: bash scripts\/test-sync-references\.sh$/\1run: |\
\1  bash scripts\/test-sync-references.sh/' "$repo_root/lefthook.yml" >"$tmp/lefthook.block.yml"
block_mismatch="$(read_suites "$tmp/lefthook.block.yml" "$tmp/suites.block")"
if grep -qF "scripts/test-sync-references.sh is on disk" <<<"$block_mismatch"; then
  ok "apparatus: a suite registered as a run: | block is reported as unread"
else bad "apparatus: a suite registered as a run: | block was NOT reported — the set check is not measuring the extraction"; fi

suites="$tmp/suites"
mismatch="$(read_suites "$repo_root/lefthook.yml" "$suites")"
count=$(wc -l <"$suites" | tr -d ' ')
if [ -z "$mismatch" ] && [ "$count" -gt 0 ]; then
  ok "read $count suite invocations from lefthook.yml, one per scripts/test-*.sh"
else
  bad "the suites read from lefthook.yml are not scripts/test-*.sh minus this one:"
  printf '%s\n' "$mismatch" | sed 's/^/       /'
fi

while IFS= read -r invocation; do
  # Word-split the lefthook line on purpose: it is `bash <script> [args]`.
  # shellcheck disable=SC2086
  run_isolated $invocation
  rc=$?
  if [ -n "$leaked_diff" ]; then
    leaks=$((leaks + 1))
    bad "$invocation wrote into the hook's repo (config, refs, or HEAD):"
    printf '%s\n' "$leaked_diff" | sed 's/^/       /'
  else
    ok "$invocation left the hook's repo config and refs untouched"
  fi
  if [ "$rc" -ne 0 ]; then
    printf '     note: %s exited %s in the scratch worktree (not this suite'"'"'s verdict)\n' "$invocation" "$rc"
  fi
done <"$suites"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$leaks" -gt 0 ]; then
  echo "A suite that leaks here also writes into the real repo when pre-push runs it."
  echo "If you pushed this branch locally, check the shared .git/config for"
  echo "core.bare = true, a core.hooksPath under a temp dir, or a fixture [user]."
fi
[ "$fail" -eq 0 ]
