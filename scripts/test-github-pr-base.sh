#!/usr/bin/env bash
# test-github-pr-base.sh — the github backend's `gh pr create` gets the declared base (#604).
#
# THE DRIFT CLASS. /pre-merge Phase 1 computes $BASE_BRANCH, but each fenced
# block runs in its own shell, so Phase 2's `gh pr create --base "$BASE_BRANCH"`
# on the github backend ran with it empty, and gh fell back to the repo's
# default branch. A repo declaring `base_ref develop` whose GitHub default is
# `main` got a PR against `main`. The old base guess and gh's default usually
# agreed, which hid it. This extracts the github-backend block and RUNS it
# against a stubbed `gh`: the declared base must reach --base, a stacked-PR
# placeholder must win, and a failing `base-ref` must abort with no `pr create`.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
PM="$repo_root/pre-merge/SKILL.md"
for f in "$SC" "$PM"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done

tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Base Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars" SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

block() {
    awk -v want="$2" '
        /^ *```bash$/ { buf = ""; on = 1; ind = index($0, "`") - 1; next }
        on && /^ *```$/ { on = 0; if (index(buf, want)) { printf "%s", buf; exit } next }
        on { buf = buf substr($0, ind + 1) "\n" }
    ' "$1"
}

# shellcheck disable=SC2016  # the needle is the skill's literal text
gh_block="$(block "$PM" 'gh pr create --base "$BASE_BRANCH" --head')"
[ -n "$gh_block" ] || { bad "pre-merge/SKILL.md carries the github-backend PR block" "not found"; printf '\n%s passed, %s failed\n' "$pass" "$fail"; exit 1; }

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
echo "https://github.com/acme/repo/pull/9"
STUB
chmod +x "$tmp/bin/gh"

# Remote whose default branch is main; a second branch, develop, is declared.
git init -q --bare "$tmp/remote.git"
git clone -q "$tmp/remote.git" "$tmp/proj" 2>/dev/null
P="$tmp/proj"
git -C "$P" commit -q --allow-empty -m root
git -C "$P" push -q origin main
git -C "$P" branch -q develop && git -C "$P" push -q origin develop
git -C "$P" remote set-head origin main >/dev/null
git -C "$P" checkout -q -b feat
(cd "$P" && bash "$SC" init --name basetest --mode owned --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || bad "init the sidecar" "init failed"

# run <sidecar path> <BASE_BRANCH placeholder value> — the block, filled in.
run() {
    : > "$tmp/calls"; export GH_CALLS="$tmp/calls"
    local b="${gh_block//<this skill\'s directory>\/references\/sidecar.sh/$1}"
    b="${b//TITLE=\"<title>\"/TITLE=\"t\"}"
    b="${b//BODY_FILE=\"<path of the file holding the body written from the templates below>\"/BODY_FILE=\"$tmp/body\"}"
    b="${b//BASE_BRANCH=\"<sibling slice branch for a stacked PR, else empty>\"/BASE_BRANCH=\"$2\"}"
    : > "$tmp/body"
    (cd "$P" && PATH="$tmp/bin:$PATH" bash -c "$b" >/dev/null 2>"$tmp/stderr"); rc=$?
}

(cd "$P" && bash "$SC" config set base_ref develop >/dev/null 2>&1)
run "$SC" ""
check "a declared base_ref reaches --base with the placeholder empty" "yes" \
    "$(grep -q -- '--base develop ' "$tmp/calls" && echo yes || echo no)"
check "the block exits 0" 0 "$rc"

run "$SC" "slice-1-branch"
check "a stacked-PR placeholder overrides the declared base" "yes" \
    "$(grep -q -- '--base slice-1-branch ' "$tmp/calls" && echo yes || echo no)"

printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > "$tmp/failing-sc.sh"
run "$tmp/failing-sc.sh" ""
check "a failing base-ref aborts nonzero" 1 "$rc"
check "a failing base-ref makes no gh call" "0" "$(grep -c . "$tmp/calls")"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
