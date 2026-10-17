#!/usr/bin/env bash
# test-sidecar-resolution.sh — runs the real init-pipeline/scripts/sidecar.sh
# against scratch repos and asserts identity, loud failure, concurrency, and
# isolation from the project.
#
# THE DRIFT CLASS. The research archive keyed projects on a slug cut from the
# remote URL. On the originating machine that produced 28 directories for about
# 17 projects: an org rename, a local repo later gaining a remote, and a repo
# with no remote each started a fresh directory nobody read. The slug rule was
# prose plus one sed, and nothing ran it. sidecar.sh replaces it with an
# identity keyed on the root commit; this suite is what keeps that identity
# from drifting the same way (#405, #410).
#
# TWO MEASURED HAZARDS it pins (git 2.43, research for #405):
#   - A leaked GIT_DIR makes `git -C <sidecar> commit` exit 0 and land the
#     commit in the project. Git exports GIT_DIR into hooks.
#     docs/solutions/testing-patterns/scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md
#   - Plain add-then-commit under 20 parallel writers loses most files to
#     index.lock contention.
#
# Section 9 runs the /compound sidecar block extracted from compound/SKILL.md,
# so an edit to that block is tested as written.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config, so a hook's GIT_DIR or the runner's identity cannot
# leak in.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
COMPOUND="$repo_root/compound/SKILL.md"
[ -f "$SC" ] || { printf 'FATAL %s is missing\n' "$SC"; exit 1; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Sidecar Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" protocol.file.allow always
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
contains() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "expected to contain [$2], got [$3]" ;; esac; }
lacks() { case "$3" in *"$2"*) bad "$1" "expected not to contain [$2], got [$3]" ;; *) ok "$1" ;; esac; }

# run <dir> <args...> — run sidecar.sh from <dir>; sets $out (stdout+stderr) and $rc
run() { local d="$1"; shift; out="$(cd "$d" && bash "$SC" "$@" 2>&1)"; rc=$?; }
# runo <dir> <args...> — stdout only
runo() { local d="$1"; shift; out="$(cd "$d" && bash "$SC" "$@" 2>/dev/null)"; rc=$?; }

mkrepo() {
    git init -q "$1"
    git -C "$1" commit -q --allow-empty -m "root"
    git -C "$1" commit -q --allow-empty -m "second"
}

# A snapshot of everything under a project's .git, plus its history.
fingerprint() {
    (cd "$1/.git" && find . -type f ! -name index -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256)
    git -C "$1" log --all --format='%H %s'
}

PROJ="$tmp/proj"
mkrepo "$PROJ"

# -----------------------------------------------------------------------------
section "init"

run "$PROJ" init --mode guest --write sidecar
check "init without --in-tree-path is a usage error" 2 "$rc"
run "$PROJ" init --mode visitor --write sidecar --in-tree-path none
check "init rejects an unknown --mode" 2 "$rc"
run "$PROJ" init --mode guest --write in-tree --in-tree-path none
check "init rejects --write in-tree with no in-tree path" 2 "$rc"

runo "$PROJ" init --name proj --mode guest --write ask --in-tree-path docs/adr
check "init succeeds" 0 "$rc"
SIDECAR="$out"
check "init prints the sidecar path under SKILL_KIT_SIDECAR_ROOT" "$SKILL_KIT_SIDECAR_ROOT/proj" "$SIDECAR"
J="$SIDECAR/sidecar.json"
check "sidecar.json declares schema 1" 1 "$(jq -r .schema "$J")"
check "solutions.write is recorded" ask "$(jq -r .solutions.write "$J")"
check "solutions.in_tree_path is recorded" docs/adr "$(jq -r .solutions.in_tree_path "$J")"
check "sidecar.json carries a root: key" 1 "$(jq '[.keys[] | select(startswith("root:"))] | length' "$J")"
check "sidecar.json carries the main checkout's path: key" \
    "path:$(printf '%s' "$PROJ" | tr '[:upper:]' '[:lower:]')" "$(jq -r '.keys[] | select(startswith("path:"))' "$J")"
check "the sidecar's committer is the global identity" "Sidecar Tester <tester@example.com>" \
    "$(git -C "$SIDECAR" log -1 --format='%an <%ae>')"
check "sidecar.json is committed" "" "$(git -C "$SIDECAR" status --porcelain)"
runo "$PROJ" config get solutions.write
check "config get solutions.write returns the value" ask "$out"
runo "$PROJ" config get verify.typecheck
check "config get on an empty key prints the empty string" "" "$out"

# -----------------------------------------------------------------------------
section "identity: main, subdirectory, linked worktree, fresh clone"

mkdir -p "$PROJ/sub/dir"
git -C "$PROJ" worktree add -q "$tmp/proj-wt" -b wt-branch
git clone -q "$PROJ" "$tmp/proj-clone"
for d in "$PROJ" "$PROJ/sub/dir" "$tmp/proj-wt" "$tmp/proj-clone"; do
    runo "$d" resolve
    check "resolve from ${d#"$tmp"/} prints the one sidecar" "$SIDECAR" "$out"
done
check "the worktree did not add a path: alias (it shares the main checkout's)" \
    0 "$(jq --arg p "path:$(printf '%s' "$tmp/proj-wt" | tr '[:upper:]' '[:lower:]')" '[.keys[] | select(. == $p)] | length' "$J")"
check "the clone's path was appended as an alias" \
    1 "$(jq --arg p "path:$(printf '%s' "$tmp/proj-clone" | tr '[:upper:]' '[:lower:]')" '[.keys[] | select(. == $p)] | length' "$J")"
check "the alias append is committed" "" "$(git -C "$SIDECAR" status --porcelain)"

# -----------------------------------------------------------------------------
section "a repo with no remote at init, which later gains one"

git -C "$PROJ" remote add origin git@github.com:Acme/Widget.git
runo "$PROJ" resolve
check "resolve still returns the same sidecar" "$SIDECAR" "$out"
check "the new remote: alias is appended, normalized and lowercased" \
    1 "$(jq '[.keys[] | select(. == "remote:github.com/acme/widget")] | length' "$J")"
check "the remote alias is committed" "" "$(git -C "$SIDECAR" status --porcelain)"

# -----------------------------------------------------------------------------
section "remote normalization"

NORM="$tmp/norm"
mkrepo "$NORM"
n=0
for pair in \
    "https://GitHub.com/Acme/Widget.git/|github.com/acme/widget" \
    "ssh://git@gitlab.com:2222/group/sub/repo.git|gitlab.com/group/sub/repo" \
    "https://dev.azure.com/org/project/_git/repo|dev.azure.com/org/project/_git/repo" \
    "git@github.com:owner/my.repo.git|github.com/owner/my.repo"; do
    url="${pair%%|*}"; want="${pair#*|}"
    git -C "$NORM" remote remove origin 2>/dev/null
    git -C "$NORM" remote add origin "$url"
    out="$(cd "$NORM" && SKILL_KIT_SIDECAR_ROOT="$tmp/empty-root" bash "$SC" resolve 2>&1)"
    contains "a miss on $url suggests a name from $want" \
        "--name $(basename "$(dirname "$want")")-$(basename "$want" | tr -c 'a-z0-9._-\n' '-')" "$out"
    # the suggested --name is a substring match that ignores host, port and
    # trailing slashes; the stored remote: key is what must be exact
    NORM_ROOT="$tmp/norm-sidecars-$n"; n=$((n + 1))
    (cd "$NORM" && SKILL_KIT_SIDECAR_ROOT="$NORM_ROOT" bash "$SC" init --name nk --mode guest --write sidecar --in-tree-path none >/dev/null 2>&1)
    check "init keys $url as exactly remote:$want" \
        "remote:$want" "$(jq -r '[.keys[] | select(startswith("remote:"))] | join(",")' "$NORM_ROOT/nk/sidecar.json" 2>&1)"
done
git -C "$NORM" remote set-url origin "https://x:token@GitLab.com/Group/Sub/Repo.git"
SUBGROUP_ROOT="$tmp/subgroup-sidecars"
out="$(cd "$NORM" && SKILL_KIT_SIDECAR_ROOT="$SUBGROUP_ROOT" bash "$SC" init --name sg --mode guest --write sidecar --in-tree-path none 2>&1)"
check "init keys a GitLab subgroup remote on the full path, without the credentials" \
    1 "$(jq '[.keys[] | select(. == "remote:gitlab.com/group/sub/repo")] | length' "$SUBGROUP_ROOT/sg/sidecar.json")"

# -----------------------------------------------------------------------------
section "shallow clone"

git clone -q --depth 1 "file://$PROJ" "$tmp/proj-shallow"
check "the fixture is shallow" true "$(git -C "$tmp/proj-shallow" rev-parse --is-shallow-repository)"
run "$tmp/proj-shallow" resolve
check "a shallow clone whose remote and path match nothing misses" 1 "$rc"
git -C "$tmp/proj-shallow" remote set-url origin git@github.com:acme/widget.git
roots_before="$(jq '[.keys[] | select(startswith("root:"))] | length' "$J")"
run "$tmp/proj-shallow" resolve
check "a shallow clone resolves by remote" 0 "$rc"
contains "resolve prints the one sidecar" "$SIDECAR" "$out"
contains "resolve prints a shallow notice" "shallow clone" "$out"
check "the shallow clone's false root was not added as an alias" \
    "$roots_before" "$(jq '[.keys[] | select(startswith("root:"))] | length' "$J")"

# -----------------------------------------------------------------------------
section "loud failure"

OTHER="$tmp/other"
mkrepo "$OTHER"
git -C "$OTHER" remote add origin git@github.com:Foo/Bar-Baz.git
run "$OTHER" resolve
check "resolve on an unknown repo exits 1" 1 "$rc"
contains "it prints SIDECAR MISS with the suggested name filled in" \
    "SIDECAR MISS: run: sidecar.sh init --name foo-bar-baz" "$out"
run "$OTHER" path solutions
check "path on a miss exits 1" 1 "$rc"
run "$OTHER" config get solutions.write
check "config get on a miss exits 1" 1 "$rc"
check "nothing was created for the missed repo" "proj" "$(ls "$SKILL_KIT_SIDECAR_ROOT")"

run "$tmp" require "$tmp/absent.md" --from "docs/x.md:12"
check "require on an absent path exits 1" 1 "$rc"
check "require prints the MISSING line" "MISSING: $tmp/absent.md (referenced by docs/x.md:12)" "$out"
run "$tmp" require "$J" --from "docs/x.md:12"
check "require on a present path exits 0 and prints nothing" "0:" "$rc:$out"
run "$tmp" require "$J"
check "require without --from is a usage error" 2 "$rc"
run "$tmp"
check "no verb is a usage error" 2 "$rc"
run "$PROJ" path dossier
check "path with an unknown kind is a usage error" 2 "$rc"

run "$tmp/proj-clone" init --name dup --mode owned --write sidecar --in-tree-path none
check "init refuses to create a sidecar sharing an alias" 1 "$rc"
contains "the refusal names the existing sidecar" "sidecar proj" "$out"
check "the refused init created nothing" "proj" "$(ls "$SKILL_KIT_SIDECAR_ROOT")"

: > "$tmp/empty-gitconfig"
out="$(cd "$OTHER" && GIT_CONFIG_GLOBAL="$tmp/empty-gitconfig" bash "$SC" init --mode guest --write sidecar --in-tree-path none 2>&1)"
rc=$?
check "init refuses when the global identity is empty" 1 "$rc"
contains "the refusal says why" "global git identity" "$out"
check "the refused init created nothing" "proj" "$(ls "$SKILL_KIT_SIDECAR_ROOT")"

# A second sidecar claiming the same root is a collision resolve must report.
cp -R "$SIDECAR" "$SKILL_KIT_SIDECAR_ROOT/proj-copy"
run "$PROJ" resolve
contains "resolve warns when two sidecars share a key" "ALIAS COLLISION" "$out"
check "a collision is a warning, not an exit" 0 "$rc"
rm -rf "$SKILL_KIT_SIDECAR_ROOT/proj-copy"

# -----------------------------------------------------------------------------
section "20 parallel commits, 3 runs"

SOL="$(cd "$PROJ" && bash "$SC" path solutions)"
check "path solutions is the sidecar's solutions/ directory" "$SIDECAR/solutions" "$SOL"
mkdir -p "$SOL/concurrency"
for r in 1 2 3; do
    before="$(git -C "$SIDECAR" rev-list --count HEAD)"
    pids=""
    for i in $(seq 1 20); do
        (
            f="$SOL/concurrency/r$r-$i.md"
            printf 'entry %s %s\n' "$r" "$i" > "$f"
            cd "$PROJ" && bash "$SC" commit -- "$f" -m "test: r$r-$i" >/dev/null 2>&1
        ) &
        pids="$pids $!"
    done
    failed=0
    for p in $pids; do wait "$p" || failed=$((failed + 1)); done
    after="$(git -C "$SIDECAR" rev-list --count HEAD)"
    landed="$(git -C "$SIDECAR" ls-files "solutions/concurrency/r$r-*" | wc -l | tr -d ' ')"
    check "run $r: every commit call exited 0" 0 "$failed"
    check "run $r: 20 commits landed" 20 "$((after - before))"
    check "run $r: 20 files are tracked" 20 "$landed"
done
check "the sidecar is clean after the concurrent runs" "" "$(git -C "$SIDECAR" status --porcelain)"

# A writer whose file another writer already committed finds nothing to commit.
run "$PROJ" commit -- "$SOL/concurrency/r1-1.md" -m "test: again"
check "committing an already-committed, unchanged file succeeds" 0 "$rc"

printf 'x\n' > "$tmp/outside.md"
run "$PROJ" commit -- "$tmp/outside.md" -m "nope"
check "commit refuses a path outside the sidecar" 1 "$rc"
run "$PROJ" commit -- "$SOL/concurrency/r1-1.md"
check "commit without -m is a usage error" 2 "$rc"

# -----------------------------------------------------------------------------
section "isolation: GIT_DIR exported to the project"

proj_log="$(git -C "$PROJ" log --all --format=%H)"
proj_cfg="$(shasum -a 256 < "$PROJ/.git/config")"
export GIT_DIR="$PROJ/.git"
printf 'leak test\n' > "$SOL/concurrency/leak.md"
(cd "$PROJ" && bash "$SC" commit -- "$SOL/concurrency/leak.md" -m "test: leak") >/dev/null 2>&1
leak_rc=$?
(cd "$tmp/proj-wt" && bash "$SC" resolve) >/dev/null 2>&1
unset GIT_DIR
check "commit with GIT_DIR exported still succeeds" 0 "$leak_rc"
check "the commit landed in the sidecar" "test: leak" "$(git -C "$SIDECAR" log -1 --format=%s)"
check "the project's history is unchanged" "$proj_log" "$(git -C "$PROJ" log --all --format=%H)"
check "the project's .git/config is unchanged" "$proj_cfg" "$(shasum -a 256 < "$PROJ/.git/config")"

# The guard can fire: the same run against a copy of the script with the env
# clearing removed must leak, or this section proves nothing.
VICTIM="$tmp/victim"
mkrepo "$VICTIM"
sed 's/env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git/git/' "$SC" > "$tmp/sidecar-unguarded.sh"
victim_sc="$(cd "$VICTIM" && SKILL_KIT_SIDECAR_ROOT="$tmp/victim-sidecars" bash "$SC" init --name v --mode guest --write sidecar --in-tree-path none 2>/dev/null)"
victim_before="$(git -C "$VICTIM" rev-list --count HEAD)"
printf 'x\n' > "$victim_sc/leak.md"
(cd "$VICTIM" && GIT_DIR="$VICTIM/.git" SKILL_KIT_SIDECAR_ROOT="$tmp/victim-sidecars" \
    bash "$tmp/sidecar-unguarded.sh" commit -- "$victim_sc/leak.md" -m "leaked") >/dev/null 2>&1
check "without the env clearing, the same commit lands in the project (the guard is load-bearing)" \
    "$((victim_before + 1))" "$(git -C "$VICTIM" rev-list --count HEAD)"

# -----------------------------------------------------------------------------
section "init, /compound's sidecar block, and commit never write the project"

# A fresh project, so no worktree or remote fixture has touched its .git.
GUEST="$tmp/guest"
mkrepo "$GUEST"
GUEST_BEFORE="$(fingerprint "$GUEST")"
runo "$GUEST" init --name guest --mode guest --write sidecar --in-tree-path none
GSC="$out"
check "init on the guest project succeeds" 0 "$rc"

block="$(awk '/^<!-- sidecar-write: compound -->$/ { on = 1; next }
              on && /^```bash$/ { inb = 1; next }
              inb && /^```$/ { exit }
              inb { print }' "$COMPOUND")"
if [ -z "$block" ]; then
    bad "compound/SKILL.md carries the sidecar write block" "no \`\`\`bash block after <!-- sidecar-write: compound -->"
else
    ok "compound/SKILL.md carries the sidecar write block"
    contains "the block calls the bundled resolver, not a computed path" 'references/sidecar.sh' "$block"
    lacks "the block runs no git of its own" 'git ' "$(printf '%s\n' "$block" | grep -v '^[[:space:]]*#')"
    script="$(printf '%s\n' "$block" \
        | sed -e "s|^SC=.*|SC=\"$SC\"|" \
              -e 's|<category>|integration-issues|g' \
              -e 's|<slug>|deploy-env-lesson|g' \
              -e 's|<YYYY-MM-DD>|2026-10-17|g')"
    out="$(cd "$GUEST" && bash -c "$script" 2>&1)"
    rc=$?
    check "the block runs cleanly" 0 "$rc"
    check "the entry is committed in the sidecar" "solutions/integration-issues/deploy-env-lesson-2026-10-17.md" \
        "$(git -C "$GSC" log -1 --name-only --format= | head -n 1)"
fi
RES="$(cd "$GUEST" && bash "$SC" path research)"
printf 'second\n' > "$RES/note.md"
run "$GUEST" commit -- "$RES/note.md" -m "test: note"
check "a direct commit from the guest project succeeds" 0 "$rc"
check "git status --porcelain in the project is empty" "" "$(git -C "$GUEST" status --porcelain)"
check "no file under the project's .git changed" "$GUEST_BEFORE" "$(fingerprint "$GUEST")"

# -----------------------------------------------------------------------------
section "resolve refuses to add an alias another sidecar owns"

# Sidecar A holds this checkout's root key; sidecar B (hand-written, isolated
# root) holds its remote key. resolve must not copy B's key into A: that is the
# collision init refuses to create.
COLL_SAVED_ROOT="$SKILL_KIT_SIDECAR_ROOT"
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars-collision"
COLL="$tmp/collide"
mkrepo "$COLL"
run "$COLL" init --name coll-a --mode guest --write sidecar --in-tree-path none
check "collision fixture: sidecar A is created" 0 "$rc"
COLL_A="$SKILL_KIT_SIDECAR_ROOT/coll-a"
mkdir -p "$SKILL_KIT_SIDECAR_ROOT/coll-b"
printf '{"name":"coll-b","keys":["remote:github.com/acme/collide"]}\n' > "$SKILL_KIT_SIDECAR_ROOT/coll-b/sidecar.json"
git -C "$COLL" remote add origin git@github.com:Acme/Collide.git
run "$COLL" resolve
check "resolve still succeeds on A's root key" 0 "$rc"
contains "resolve prints an ALIAS COLLISION warning" "ALIAS COLLISION: remote:github.com/acme/collide already belongs to $SKILL_KIT_SIDECAR_ROOT/coll-b" "$out"
check "A did not gain B's remote key" 0 \
    "$(jq '[.keys[] | select(. == "remote:github.com/acme/collide")] | length' "$COLL_A/sidecar.json")"
check "B still owns the remote key" 1 \
    "$(jq '[.keys[] | select(. == "remote:github.com/acme/collide")] | length' "$SKILL_KIT_SIDECAR_ROOT/coll-b/sidecar.json")"
export SKILL_KIT_SIDECAR_ROOT="$COLL_SAVED_ROOT"

# -----------------------------------------------------------------------------
section "init cleans up when its first commit fails"

HOSTILE="$tmp/hostile"
mkrepo "$HOSTILE"
mkdir -p "$tmp/badhooks"
printf '#!/bin/sh\necho "hostile global pre-commit" >&2\nexit 1\n' > "$tmp/badhooks/pre-commit"
chmod +x "$tmp/badhooks/pre-commit"
cp "$GIT_CONFIG_GLOBAL" "$tmp/gitconfig.good"
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath "$tmp/badhooks"
run "$HOSTILE" init --name hostile --mode guest --write sidecar --in-tree-path none
check "init exits 1 when the initial commit fails" 1 "$rc"
check "a failed init leaves no sidecar directory" "no" "$([ -e "$SKILL_KIT_SIDECAR_ROOT/hostile" ] && echo yes || echo no)"
cp "$tmp/gitconfig.good" "$GIT_CONFIG_GLOBAL"
run "$HOSTILE" init --name hostile --mode guest --write sidecar --in-tree-path none
check "a retry after removing the hook succeeds" 0 "$rc"
check "the retried sidecar.json is committed" "" "$(git -C "$SKILL_KIT_SIDECAR_ROOT/hostile" status --porcelain)"

section "init cleans up when the sidecar.json write fails"

# A PATH shim fails only the `jq -n` that builds sidecar.json; every other jq
# call passes through to the real binary. The redirect has already created an
# empty sidecar.json by then.
REAL_JQ="$(command -v jq)"
mkdir -p "$tmp/jqshim"
# shellcheck disable=SC2016 # the shim body is meant to be literal
printf '#!/bin/sh\n[ "$1" = "-n" ] && exit 1\nexec "%s" "$@"\n' "$REAL_JQ" > "$tmp/jqshim/jq"
chmod +x "$tmp/jqshim/jq"
JQFAIL="$tmp/jqfail"
mkrepo "$JQFAIL"
SAVED_PATH="$PATH"
PATH="$tmp/jqshim:$PATH"
run "$JQFAIL" init --name jqfail --mode guest --write sidecar --in-tree-path none
PATH="$SAVED_PATH"
check "init exits 1 when the sidecar.json write fails" 1 "$rc"
check "a failed jq write leaves no sidecar directory" "no" "$([ -e "$SKILL_KIT_SIDECAR_ROOT/jqfail" ] && echo yes || echo no)"
run "$JQFAIL" init --name jqfail --mode guest --write sidecar --in-tree-path none
check "a retry after the jq failure succeeds" 0 "$rc"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
