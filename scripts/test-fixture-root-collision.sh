#!/usr/bin/env bash
# test-fixture-root-collision.sh — no suite that builds sidecars may give two
# fixtures the same root commit.
#
# THE DRIFT CLASS. sidecar.sh identifies a project by its root commit. A
# fixture helper that makes an empty root commit with a fixed message and a
# fixed identity varies nothing but the one-second timestamp, so two fixtures
# built in the same second are one project to the code under test: the later
# `init` is refused, or a fixture reads another one's work items. The suite
# goes red on a fast CI runner and stays green on a laptop most of the time.
#
# THE INCIDENT. docs/solutions/testing-patterns/
# identical-scratch-commits-share-a-root-sha-2026-10-17.md recorded this trap
# and its fix (`-m "root $P"`) on 2026-10-17. On 2026-10-25,
# scripts/test-guest-footprint.sh (#526) reintroduced it with `-m root`: CI
# ended 61 passed, 14 failed while every local run read 70 passed. The lesson
# was prose; nothing failed when a new suite ignored it.
#
# WHAT THIS DOES. Takes every scripts/test-*.sh that runs `sidecar.sh init`,
# found by grep rather than listed here so the next one is covered, and runs
# each with GIT_AUTHOR_DATE and GIT_COMMITTER_DATE pinned to one value. That
# is the entry's own proof step: it makes every fixture land in the same
# second, so a collision fails every run instead of some. A suite that fails
# under the pin fails this suite.
#
# APPARATUS. Before trusting a green result, the same runner is pointed at a
# copy of the tree whose test-guest-footprint.sh has its root message put
# back to `-m root`, and must report that suite red. A runner that cannot fail
# that copy is not measuring anything.
#
# CI ONLY, like test-fixture-git-isolation.sh, because it re-runs other suites
# (about three minutes). That suite excludes this one from its "every suite
# but itself" check, and lefthook.yml says why it is absent.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
self="scripts/$(basename "$0")"
PIN="2026-01-01T00:00:00Z"

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }

# sidecar_suites <root> — every scripts/test-*.sh under <root> that runs
# `sidecar.sh init`, except this one. Keyed on `init --name`, the flag the
# verb requires, because callers reach the script through several variable
# names ($SC, $SC_REAL, a literal path) and a key on the name misses some.
sidecar_suites() {
    (cd "$1" && grep -l -- ' init --name' scripts/test-*.sh) | grep -vxF -- "$self" | sort
}

# pinned <root> <suite> — run <suite> from <root> with both dates pinned; the
# exit status in $rc, the last line in $last.
pinned() {
    (cd "$1" && GIT_AUTHOR_DATE="$PIN" GIT_COMMITTER_DATE="$PIN" bash "$2") >"$tmp/out" 2>&1
    rc=$?
    last="$(tail -1 "$tmp/out")"
}

printf '\n=== apparatus: a colliding fixture is reported red ===\n'

# A copy of the tree with one suite's root message made constant. Everything
# but scripts/ is a symlink to the real tree, so the suite reads the real
# skills and the real sidecar.sh.
fake="$tmp/fake"
mkdir -p "$fake/scripts"
for entry in "$repo_root"/* "$repo_root"/.[!.]*; do
    [ -e "$entry" ] || continue
    name="${entry##*/}"
    case "$name" in scripts|.git) continue ;; esac
    ln -s "$entry" "$fake/$name"
done
cp "$repo_root"/scripts/* "$fake/scripts/"
# shellcheck disable=SC2016  # the pattern is the suite's literal text
sed 's/commit -q --allow-empty -m "root \$P"/commit -q --allow-empty -m root/' \
    "$repo_root/scripts/test-guest-footprint.sh" > "$fake/scripts/test-guest-footprint.sh"
if cmp -s "$repo_root/scripts/test-guest-footprint.sh" "$fake/scripts/test-guest-footprint.sh"; then
    bad "apparatus: the planted constant root message" "sed changed nothing; the root commit line moved"
else
    pinned "$fake" scripts/test-guest-footprint.sh
    if [ "$rc" -ne 0 ]; then
        ok "apparatus: a constant root message fails under the pin ($last)"
    else
        bad "apparatus: a constant root message fails under the pin" "it passed ($last); this runner cannot see a collision"
    fi
fi

printf '\n=== every suite that builds sidecars passes with the dates pinned ===\n'

suites="$(sidecar_suites "$repo_root")"
count="$(printf '%s\n' "$suites" | grep -c .)"
if [ "$count" -ge 2 ]; then
    ok "found $count suites that run sidecar.sh init"
else
    bad "found suites that run sidecar.sh init" "only $count; the grep no longer matches how suites call it"
fi
case "$suites" in
    *scripts/test-guest-footprint.sh*) ok "the grep finds the suite this incident came from" ;;
    *) bad "the grep finds the suite this incident came from" "scripts/test-guest-footprint.sh is not in the list" ;;
esac

while IFS= read -r s; do
    [ -n "$s" ] || continue
    pinned "$repo_root" "$s"
    if [ "$rc" -eq 0 ]; then
        ok "$s passes with both dates pinned"
    else
        bad "$s passes with both dates pinned" "exit $rc: $last — two fixtures likely share a root commit; put \$P in its message"
    fi
done <<<"$suites"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
