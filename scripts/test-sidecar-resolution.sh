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
# The "archive migration" section pins init's move of the old per-slug
# research directories into the sidecar: PRD issues embed those absolute
# paths, so each old directory must survive as a symlink that still resolves.
#
# Section 9 runs the /compound sidecar block extracted from compound/SKILL.md,
# and the "/research" section runs research/SKILL.md's Phase 3 read, Phase 5a
# storage read, and Phase 5c write, plus /write-a-prd's archive-mode read of
# what that write left, and the "/help" section runs help/SKILL.md's
# Phase 1b sidecar block, so an edit to any of them is tested as written.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config, so a hook's GIT_DIR or the runner's identity cannot
# leak in.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
COMPOUND="$repo_root/compound/SKILL.md"
RESEARCH="$repo_root/research/SKILL.md"
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
# init migrates the research archive by default; never let it touch the
# runner's real ~/.claude/research.
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

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
    # The path is in the message so every fixture has its own root SHA: with
    # identical empty commits, repos made in the same second share a root
    # commit, which sidecar.sh rightly treats as one project.
    git -C "$1" commit -q --allow-empty -m "root $1"
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
    "SIDECAR MISS: run: bash $SC init --name foo-bar-baz" "$out"
run "$OTHER" path solutions
check "path on a miss exits 1" 1 "$rc"
run "$OTHER" config get solutions.write
check "config get on a miss exits 1" 1 "$rc"
check "nothing was created for the missed repo" "proj" "$(ls "$SKILL_KIT_SIDECAR_ROOT")"

run "$tmp" require "$tmp/absent.md" --from "docs/x.md:12"
check "require on an absent path exits 1" 1 "$rc"
check "require prints the MISSING line" "MISSING: $tmp/absent.md (referenced by docs/x.md:12)" "$out"
run "$tmp" require "$J" --from "docs/x.md:12"
# #431: a hit prints the path it resolved to, so a caller opens that path instead
# of re-deriving the location from prose that may describe a different rule.
check "require on a present path exits 0 and prints its absolute path" "0:$J" "$rc:$out"
runr() { local d="$1"; shift; out="$(cd "$d" && bash "$SC" "$@" 2>/dev/null)"; err="$(cd "$d" && bash "$SC" "$@" 2>&1 >/dev/null)"; rc=$?; }
runr "$tmp" require "$J" --from "docs/x.md:12"
check "the resolved path goes to stdout, nothing to stderr" "0:$J:" "$rc:$out:$err"
run "$tmp" require "$J"
check "require without --from is a usage error" 2 "$rc"
mkdir -p "$tmp/home/r"; : > "$tmp/home/r/a.md"
# shellcheck disable=SC2088  # literal ~ is the input under test
out=$(HOME="$tmp/home" bash "$SC" require "~/r/a.md" --from "PRD #1" 2>&1); rc=$?
check "require expands a quoted leading ~/ and prints the expanded path" "0:$tmp/home/r/a.md" "$rc:$out"
# shellcheck disable=SC2088  # literal ~ is the input under test
out=$(HOME="$tmp/home" bash "$SC" require "~/r/b.md" --from "PRD #1" 2>&1); rc=$?
check "require on an absent ~/ path shows the path as given" "1:MISSING: ~/r/b.md (referenced by PRD #1)" "$rc:$out"
mkdir -p "$tmp/lessons/a" "$tmp/lessons/b"; : > "$tmp/lessons/a/entry.md"; : > "$tmp/lessons/a/sibling.md"; : > "$tmp/lessons/b/entry.md"
out=$(cd "$tmp" && bash "$SC" require "sibling.md" --from "lessons/a/entry.md" 2>&1); rc=$?
check "require resolves a bare sibling name against the citing file's folder" "0:$tmp/lessons/a/sibling.md" "$rc:$out"
out=$(cd "$tmp" && bash "$SC" require "sibling.md" --from "lessons/b/entry.md" 2>&1); rc=$?
check "require resolves a bare name in a sibling category folder and prints that folder" "0:$tmp/lessons/a/sibling.md" "$rc:$out"
out=$(cd "$tmp/lessons" && bash "$SC" require "a/sibling.md" --from "elsewhere" 2>&1); rc=$?
check "require prints a cwd-relative hit as an absolute path" "0:$tmp/lessons/a/sibling.md" "$rc:$out"
out=$(cd "$tmp" && bash "$SC" require "nowhere.md" --from "lessons/b/entry.md" 2>&1); rc=$?
check "require on a bare name absent from every category still reports MISSING" "1:MISSING: nowhere.md (referenced by lessons/b/entry.md)" "$rc:$out"
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
contains "the failure is the hostile hook, not an alias refusal" "hostile global pre-commit" "$out"
check "a failed init leaves no sidecar directory" "no" "$(if [ -e "$SKILL_KIT_SIDECAR_ROOT/hostile" ]; then echo yes; else echo no; fi)"
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
check "a failed jq write leaves no sidecar directory" "no" "$(if [ -e "$SKILL_KIT_SIDECAR_ROOT/jqfail" ]; then echo yes; else echo no; fi)"
run "$JQFAIL" init --name jqfail --mode guest --write sidecar --in-tree-path none
check "a retry after the jq failure succeeds" 0 "$rc"

# -----------------------------------------------------------------------------
section "archive migration"

# One project under three old slugs, as the originating machine's archive
# holds mimir: the checkout basename (pre-remote), and owner-repo for each of
# two remotes (an org rename). Mixed case, because the old slugs were.
mkdir -p "$tmp/mig"
MIG="$tmp/mig/mimir"
mkrepo "$MIG"
git -C "$MIG" remote add origin git@github.com:NewEra-Alliances/Mimir.git
git -C "$MIG" remote add old https://github.com/New-Era-Technology/mimir.git
A="$SKILL_KIT_RESEARCH_ARCHIVE"
mkdir -p "$A/mimir" "$A/New-Era-Technology-mimir" "$A/NewEra-Alliances-mimir" "$A/unrelated"
printf 'local\n'  > "$A/mimir/local-2026-01-01.md"
printf 'tech\n'   > "$A/New-Era-Technology-mimir/tech-2026-02-01.md"
printf 'alli\n'   > "$A/NewEra-Alliances-mimir/alli-2026-03-01.md"
cp "$A/mimir/local-2026-01-01.md" "$A/NewEra-Alliances-mimir/"
printf 'other\n'  > "$A/unrelated/z.md"

# The basename is not a match for a checkout that has a remote: mimir/ above is
# claimed only because the run below names it with --archive-alias.
run "$MIG" init --name mig-noalias --mode owned --write sidecar --in-tree-path none
check "a basename directory is not migrated for a checkout with a remote" "dir" \
    "$(if [ -L "$A/mimir" ]; then echo link; elif [ -d "$A/mimir" ]; then echo dir; fi)"
check "the remote-derived directories still migrate without an alias" "link link" \
    "$(if [ -L "$A/New-Era-Technology-mimir" ]; then echo link; fi) $(if [ -L "$A/NewEra-Alliances-mimir" ]; then echo link; fi)"
# Undo, so the sections below start from the planted fixture.
rm -rf "$SKILL_KIT_SIDECAR_ROOT/mig-noalias"
for d in New-Era-Technology-mimir NewEra-Alliances-mimir; do
    rm -f "$A/$d"; mkdir -p "$A/$d"
done
printf 'tech\n' > "$A/New-Era-Technology-mimir/tech-2026-02-01.md"
printf 'alli\n' > "$A/NewEra-Alliances-mimir/alli-2026-03-01.md"
cp "$A/mimir/local-2026-01-01.md" "$A/NewEra-Alliances-mimir/"

run "$MIG" init --name mig-nomig --mode owned --write sidecar --in-tree-path none --no-migrate-archive
check "init --no-migrate-archive succeeds" 0 "$rc"
check "--no-migrate-archive leaves the archive directory a directory" "dir" \
    "$(if [ -L "$A/mimir" ]; then echo link; elif [ -d "$A/mimir" ]; then echo dir; fi)"
rm -rf "$SKILL_KIT_SIDECAR_ROOT/mig-nomig"

run "$MIG" init --name mig --mode owned --write sidecar --in-tree-path none --archive-alias Mimir
check "init with a matching archive succeeds" 0 "$rc"
MSC="$SKILL_KIT_SIDECAR_ROOT/mig"
for d in mimir New-Era-Technology-mimir NewEra-Alliances-mimir; do
    check "$d is now a symlink to the sidecar's research/" "$MSC/research" "$(readlink "$A/$d")"
    contains "init printed the move for $d" "from $A/$d into $MSC/research" "$out"
done
# coverage: enumerated — the three files the fixture above planted, one per old directory
for f in local-2026-01-01.md tech-2026-02-01.md alli-2026-03-01.md; do
    check "$f is readable through the sidecar" "yes" "$(if [ -f "$MSC/research/$f" ]; then echo yes; fi)"
    for d in mimir New-Era-Technology-mimir NewEra-Alliances-mimir; do
        check "$f is readable through the old path $d" "yes" "$(if [ -f "$A/$d/$f" ]; then echo yes; fi)"
    done
done
check "an archive directory matching no alias is untouched" "dir other" \
    "$(if [ -L "$A/unrelated" ]; then echo link; else echo dir; fi) $(cat "$A/unrelated/z.md")"
check "the moved files are committed in the sidecar" "" "$(git -C "$MSC" status --porcelain)"
check "the migration commit carries all three files" 3 \
    "$(git -C "$MSC" show --name-only --format= HEAD | grep -c '^research/')"
check "stdout is still only the sidecar path" "$MSC" "$(printf '%s\n' "$out" | grep -v '^sidecar.sh:' | tail -n 1)"
run "$MIG" path research
check "path research resolves to the migrated directory" "$MSC/research" "$out"

# An unrelated remote-less project archived as api/, and a different repo with a
# remote checked out at .../api: the folder name alone must not claim it.
mkdir -p "$tmp/mig/co"
API="$tmp/mig/co/api"
mkrepo "$API"
git -C "$API" remote add origin git@github.com:acme/api-server.git
mkdir -p "$A/api" "$A/Co-Api"
printf 'theirs\n' > "$A/api/theirs.md"
run "$API" init --name api-server --mode owned --write sidecar --in-tree-path none
check "init beside an unrelated api/ archive succeeds" 0 "$rc"
check "the unrelated api/ archive is still a real directory with its file" "dir theirs" \
    "$(if [ -L "$A/api" ]; then echo link; else echo dir; fi) $(cat "$A/api/theirs.md")"
lacks "nothing is reported moved from api/" "$A/api" "$out"
# A remote-less checkout is the one case the basename still means something.
NOREM="$tmp/mig/norem/solo"
mkdir -p "$A/solo"; printf 's\n' > "$A/solo/s.md"
mkrepo "$NOREM"
run "$NOREM" init --name solo --mode owned --write sidecar --in-tree-path none
check "a remote-less checkout still claims its basename directory" "$SKILL_KIT_SIDECAR_ROOT/solo/research" "$(readlink "$A/solo")"
run "$NOREM" init --name solo2 --mode owned --write sidecar --in-tree-path none --archive-alias a/b
check "--archive-alias rejects a path" 2 "$rc"

# Two old directories that disagree about one file name: the first moves, the
# second is left as it was rather than overwritten.
CLASH="$tmp/mig/clash"
mkrepo "$CLASH"
git -C "$CLASH" remote add origin git@github.com:acme/clash.git
mkdir -p "$A/acme-clash" "$A/clash"
printf 'one\n' > "$A/acme-clash/n.md"
printf 'two\n' > "$A/clash/n.md"
run "$CLASH" init --name clash --mode owned --write sidecar --in-tree-path none --archive-alias clash
check "init with a conflicting archive still succeeds" 0 "$rc"
contains "the conflict is reported" "left $A/clash untouched: n.md already exists" "$out"
check "the conflicting directory is still a directory with its own file" "dir two" \
    "$(if [ -L "$A/clash" ]; then echo link; else echo dir; fi) $(cat "$A/clash/n.md")"
check "the first directory moved" "$SKILL_KIT_SIDECAR_ROOT/clash/research" "$(readlink "$A/acme-clash")"

# -----------------------------------------------------------------------------
section "/research: Phase 3 read, Phase 5a storage, Phase 5c write"

# first_bash_after <file> <start-regex> — the first ```bash block after the
# first line matching the regex.
first_bash_after() {
    awk -v pat="$2" '$0 ~ pat { on = 1; next }
                     on && /^```bash$/ { inb = 1; next }
                     inb && /^```$/ { exit }
                     inb { print }' "$1"
}
with_sc() { printf '%s\n' "$1" | sed -e "s|^SC=.*|SC=\"$SC\"|"; }

p5c="$(first_bash_after "$RESEARCH" '^<!-- sidecar-write: research -->$')"
p3="$(first_bash_after "$RESEARCH" '^### Phase 3: ')"
p5a="$(first_bash_after "$RESEARCH" '^#### Phase 5a: ')"
for pair in "Phase 3:$p3" "Phase 5a:$p5a" "Phase 5c:$p5c"; do
    name="${pair%%:*}"; body="${pair#*:}"
    if [ -z "$body" ]; then
        bad "research/SKILL.md carries the $name block" "no bash block found"
    else
        ok "research/SKILL.md carries the $name block"
        contains "the $name block calls the bundled resolver" 'references/sidecar.sh' "$body"
        lacks "the $name block runs no git of its own" 'git ' "$(printf '%s\n' "$body" | grep -v '^[[:space:]]*#')"
    fi
done

# Phase 5c, on the migrated mimir sidecar.
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|search-index|g' -e 's|<YYYY-MM-DD>|2026-10-17|g')"
out="$(cd "$MIG" && bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block runs cleanly" 0 "$rc"
check "the research entry is the sidecar's HEAD commit" "research/search-index-2026-10-17.md" \
    "$(git -C "$MSC" log -1 --name-only --format= | head -n 1)"
check "the entry is readable through an old archive path" "yes" \
    "$(if [ -f "$A/mimir/search-index-2026-10-17.md" ]; then echo yes; fi)"
check "the project's tree is untouched by Phase 5c" "" "$(git -C "$MIG" status --porcelain)"

# Phase 5c on a SIDECAR MISS: the entry lands in the pre-sidecar archive
# (a private archive root, never the real ~/.claude/research), uncommitted.
MISSREPO="$tmp/missrepo"
mkrepo "$MISSREPO"
git -C "$MISSREPO" remote add origin git@github.com:Foo/Bar-Baz.git
MISSARCH="$tmp/missarch"
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|miss-case|g' -e 's|<YYYY-MM-DD>|2026-10-17|g')"
sc_before="$(ls "$SKILL_KIT_SIDECAR_ROOT")"
out="$(cd "$MISSREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$MISSARCH" bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block on a miss runs cleanly" 0 "$rc"
check "on a miss the entry lands in the pre-sidecar archive under the suggested slug" "yes" \
    "$(if [ -f "$MISSARCH/foo-bar-baz/miss-case-2026-10-17.md" ]; then echo yes; fi)"
contains "on a miss the user is shown the init command with an absolute path" \
    "SIDECAR MISS: run: bash $SC init --name foo-bar-baz" "$out"
check "on a miss no sidecar is created" "$sc_before" "$(ls "$SKILL_KIT_SIDECAR_ROOT")"
check "the project's tree is untouched by a missed Phase 5c" "" "$(git -C "$MISSREPO" status --porcelain)"

# A sidecar that resolves but refuses `path research` is not a miss (#481):
# the block must fail and leave the pre-sidecar archive empty, not fall into it.
REFREPO="$tmp/refrepo"
mkrepo "$REFREPO"
git -C "$REFREPO" remote add origin git@github.com:Foo/Refuse.git
run "$REFREPO" init --name refuse --mode owned --write sidecar --in-tree-path none --no-migrate-archive
check "init for the refusing-sidecar case succeeds" 0 "$rc"
rm -rf "$SKILL_KIT_SIDECAR_ROOT/refuse/research"
: > "$SKILL_KIT_SIDECAR_ROOT/refuse/research"
REFARCH="$tmp/refarch"
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|refuse-case|g' -e 's|<YYYY-MM-DD>|2026-10-17|g')"
out="$(cd "$REFREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$REFARCH" bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block fails when a resolving sidecar refuses path research" 1 "$rc"
check "nothing is written to the pre-sidecar archive when the sidecar refuses" "" \
    "$(find "$REFARCH" -type f 2>/dev/null)"
lacks "a refusing sidecar is not reported as a SIDECAR MISS" "SIDECAR MISS" "$out"
run "$REFREPO" archive-dir
check "archive-dir refuses when a sidecar resolves" 1 "$rc"

# /write-a-prd's archive-mode reader, run against what Phase 5c just wrote
# (#419). The reader used to be prose and its own remote-derived slug, so on a
# case-sensitive filesystem it listed a directory the writer never made. The
# second fixture's remote is mixed-case and dotted, the shape #419 measured.
# The block sits in a numbered list, so its fence is indented.
prd_read="$(awk '/^ *<!-- sidecar-read: research -->$/ { on = 1; next }
                 on && /^ *```bash$/ { inb = 1; next }
                 inb && /^ *```$/ { exit }
                 inb { sub(/^   /, ""); print }' "$repo_root/write-a-prd/SKILL.md")"
if [ -z "$prd_read" ]; then
    bad "write-a-prd/SKILL.md carries the archive-mode read block" "no bash block after <!-- sidecar-read: research -->"
else
    ok "write-a-prd/SKILL.md carries the archive-mode read block"
    out="$(cd "$MISSREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$MISSARCH" bash -c "$(with_sc "$prd_read")" 2>&1)"; rc=$?
    check "the /write-a-prd read block on a miss runs cleanly" 0 "$rc"
    contains "on a miss /write-a-prd lists the entry Phase 5c wrote" "miss-case-2026-10-17.md" "$out"
    DOTREPO="$tmp/dotrepo"
    mkrepo "$DOTREPO"
    git -C "$DOTREPO" remote add origin https://github.com/Own.Er/My.Repo.git
    script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|dotted|g' -e 's|<YYYY-MM-DD>|2026-10-18|g')"
    (cd "$DOTREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$MISSARCH" bash -c "$script" >/dev/null 2>&1)
    written="$(cd "$MISSARCH" && find . -name 'dotted-2026-10-18.md' | sed 's|^\./||')"
    out="$(cd "$DOTREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$MISSARCH" bash -c "$(with_sc "$prd_read")" 2>&1)"; rc=$?
    check "Phase 5c writes the dotted, mixed-case remote's entry somewhere" "yes" "$(if [ -n "$written" ]; then echo yes; fi)"
    contains "/write-a-prd names the directory Phase 5c wrote to" "pre-sidecar archive: $MISSARCH/${written%/*}" "$out"
    contains "/write-a-prd lists the dotted remote's entry" "dotted-2026-10-18.md" "$out"

    # The archive root's default, not only its override (#470). The suite
    # exports SKILL_KIT_RESEARCH_ARCHIVE above, so without this case the `:-`
    # default never runs and a mutated copy stays green. Unset it under a
    # scratch HOME, so the real ~/.claude/research is never touched.
    HOMEX="$tmp/home"
    mkdir -p "$HOMEX"
    DEFDIR="$HOMEX/.claude/research/foo-bar-baz"
    run_default() { (cd "$MISSREPO" && env -u SKILL_KIT_RESEARCH_ARCHIVE HOME="$HOMEX" bash -c "$1" 2>&1); }
    out="$(cd "$MISSREPO" && env -u SKILL_KIT_RESEARCH_ARCHIVE HOME="$HOMEX" bash "$SC" archive-dir 2>/dev/null)"
    check "with the override unset, archive-dir names \$HOME/.claude/research/<slug>" "$DEFDIR" "$out"
    script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|default-root|g' -e 's|<YYYY-MM-DD>|2026-10-18|g')"
    out="$(run_default "$script")"; rc=$?
    check "the Phase 5c block on a miss runs cleanly with the override unset" 0 "$rc"
    check "with the override unset, Phase 5c writes under \$HOME/.claude/research" "yes" \
        "$(if [ -f "$DEFDIR/default-root-2026-10-18.md" ]; then echo yes; fi)"
    out="$(run_default "$(with_sc "$prd_read")")"
    contains "with the override unset, /write-a-prd names the directory Phase 5c wrote to" "pre-sidecar archive: $DEFDIR" "$out"
    contains "with the override unset, /write-a-prd lists the entry" "default-root-2026-10-18.md" "$out"
fi

# One site owns the archive root (#470, docs/restated-claims.md). The writer
# and the reader ask the resolver for the directory; neither carries the
# default or re-parses the miss line's slug.
for pair in "research Phase 5c:$p5c" "write-a-prd:$prd_read"; do
    name="${pair%%:*}"; body="${pair#*:}"
    lacks "the $name block carries no archive root of its own" 'SKILL_KIT_RESEARCH_ARCHIVE' "$body"
    lacks "the $name block does not re-parse the miss line's slug" '--name' "$body"
    contains "the $name block asks the resolver for the archive dir" 'archive-dir' "$body"
done
check "the archive root's default is written once, in sidecar.sh" \
    "init-pipeline/scripts/sidecar.sh:1" \
    "$(cd "$repo_root" && grep -c -F '.claude/research}' research/SKILL.md write-a-prd/SKILL.md init-pipeline/scripts/sidecar.sh | grep -v ':0$')"

# Phase 3, with matches in both stores, then with in_tree_path none.
SOLS="$(cd "$MIG" && bash "$SC" path solutions)"
mkdir -p "$SOLS/perf" "$MIG/docs/adr"
printf 'needle sidecar\n' > "$SOLS/perf/a.md"
printf 'needle in-tree\n' > "$MIG/docs/adr/0001.md"
mkdir -p "$MIG/docs/solutions"
printf 'needle default-store\n' > "$MIG/docs/solutions/planted.md"
jq '.solutions.in_tree_path = "docs/adr"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
script="$(with_sc "$p3" | sed -e 's|^KW=.*|KW="needle"|')"
out="$(cd "$MIG" && bash -c "$script" 2>/dev/null)"; rc=$?
check "the Phase 3 block runs cleanly" 0 "$rc"
contains "Phase 3 lists the sidecar match" "$SOLS/perf/a.md" "$out"
contains "Phase 3 lists the in_tree_path match" "docs/adr/0001.md" "$out"
jq '.solutions.in_tree_path = "none"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
out="$(cd "$MIG" && bash -c "$script" 2>/dev/null)"
contains "with in_tree_path none, Phase 3 still lists the sidecar match" "$SOLS/perf/a.md" "$out"
lacks "with in_tree_path none, Phase 3 reads no in-tree path" "docs/adr" "$out"
lacks "with in_tree_path none, Phase 3 never reads a planted docs/solutions" "docs/solutions/planted.md" "$out"
git -C "$MSC" checkout -q -- sidecar.json

# Phase 5a: sidecar value, settings fallback with no sidecar, then the default.
script="$(with_sc "$p5a")"
jq '.research.storage = "spike-issue"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
out="$(cd "$MIG" && bash -c "$script" 2>/dev/null)"
check "Phase 5a reads research.storage from the sidecar" "research.storage = spike-issue, from sidecar" "$out"
git -C "$MSC" checkout -q -- sidecar.json
NOSC="$tmp/mig/nosidecar"
mkrepo "$NOSC"
mkdir -p "$NOSC/.claude"
printf '{"research":{"storage":"spike-issue"}}\n' > "$NOSC/.claude/settings.json"
out="$(cd "$NOSC" && bash -c "$script" 2>/dev/null)"
check "with no sidecar, Phase 5a honors .claude/settings.json and says so" \
    "research.storage = spike-issue, from .claude/settings.json (no sidecar resolved)" "$out"
rm "$NOSC/.claude/settings.json"
out="$(cd "$NOSC" && bash -c "$script" 2>/dev/null)"
check "with neither, Phase 5a defaults to archive" "research.storage = archive, from default" "$out"

# The dossier require block Phase 3 documents, extracted from the skill and run
# (not #410's resolver called directly), so deleting or breaking the line in
# research/SKILL.md turns this red. Found by its --from content, not position.
req="$(awk '/^```bash$/ { inb = 1; blk = ""; next }
            inb && /^```$/ { inb = 0; if (blk ~ /--from "\/research Phase 3"/) printf "%s", blk; next }
            inb { blk = blk $0 "\n" }' "$RESEARCH")"
if [ -z "$req" ]; then
    bad "research/SKILL.md carries the dossier require block" "no bash block with --from \"/research Phase 3\""
else
    ok "research/SKILL.md carries the dossier require block"
    DOSSIER="$MSC/research/excavation-2026-01-01.md"
    script="SC=\"$SC\"
$(printf '%s\n' "$req" | sed -e "s|<cited dossier path>|$DOSSIER|")"
    out="$(cd "$MIG" && bash -c "$script" 2>&1)"
    contains "the skill's require block surfaces the MISSING line" \
        "MISSING: $DOSSIER (referenced by /research Phase 3)" "$out"
    contains "the skill's require block signals the miss" "dossier missing" "$out"
fi

# -----------------------------------------------------------------------------
section "Each documented \$SC command runs in its own fresh shell"

# THE DRIFT CLASS (#413, PR #426 finding 2; the third recording of the
# by-construction-claim-with-no-mechanism pattern). The agent harness runs every
# fenced block in a fresh shell, so a block that reads $SC must define it. A
# first pass left execute, write-a-prd and pre-merge sharing one SC=; with SC
# empty, `bash ""` fails and a resolver miss reads as "no lessons", which the
# skill treats as a valid answer. The fix (5c1fc25) had no guard: a reviewer's
# deletion of the SC= lines in a scratch copy turned no suite red, because the
# /research section above rewrites `SC=` through with_sc, which hides exactly
# this defect. docs/solutions/patterns/
# skill-command-blocks-run-one-shell-per-call-2026-10-13.md names the
# mechanism: run each block in its own process.
#
# So: every fenced bash block (indented or not) and every inline code span
# that mentions $SC is cut out of the three skills, only the placeholders are
# filled, and each is run in its own `env -u SC bash -c`, with no SC injected.
# It passes only if the shell was able to define SC itself.

# blocks_using_sc <file> <outdir> <tag> — write each fenced bash block that
# mentions $SC to <outdir>/<tag>-N.sh (leading fence indent stripped).
blocks_using_sc() {
    awk -v dir="$2" -v tag="$3" '
        /^[[:space:]]*```bash[[:space:]]*$/ { inb = 1; ind = $0; sub(/```.*/, "", ind); blk = ""; next }
        inb && /^[[:space:]]*```[[:space:]]*$/ {
            inb = 0
            if (blk ~ /\$SC|\$\{SC/) { n++; f = sprintf("%s/%s-%d.sh", dir, tag, n); printf "%s", blk > f; close(f) }
            next }
        inb { l = $0; if (index(l, ind) == 1) l = substr(l, length(ind) + 1); blk = blk l "\n" }
    ' "$1"
}
# spans_using_sc <file> <outdir> <tag> — same for inline code spans that both
# define and use SC (a span that only uses it is covered by the prose rule
# asserted below).
spans_using_sc() {
    # shellcheck disable=SC2016  # backticks and $SC are literal patterns here
    grep -o '`[^`]*`' "$1" | sed -e 's/^`//' -e 's/`$//' \
        | grep -F 'SC=' | grep -F '$SC' \
        | awk -v dir="$2" -v tag="$3" '{ f = sprintf("%s/%s-span%d.sh", dir, tag, NR); print > f; close(f) }'
}

SCDIR="$tmp/scblocks"
SCREPO="$tmp/screpo"
mkdir -p "$SCDIR"
mkrepo "$SCREPO"
for entry in execute:execute/SKILL.md:3 write-a-prd:write-a-prd/SKILL.md:2 pre-merge:pre-merge/review-checklist.md:1; do
    skill="${entry%%:*}"; rest="${entry#*:}"; rel="${rest%%:*}"; min="${rest##*:}"
    skdir="$repo_root/$skill"
    blocks_using_sc "$repo_root/$rel" "$SCDIR" "$skill"
    spans_using_sc "$repo_root/$rel" "$SCDIR" "$skill"
    found=0
    for f in "$SCDIR/$skill"-*.sh; do
        [ -f "$f" ] || continue
        found=$((found + 1))
        script="$(sed -e "s|<this skill's directory>|$skdir|g" -e 's|<[A-Za-z][^<>]*>|x|g' "$f")"
        out="$(cd "$SCREPO" && env -u SC bash -c "$script" 2>&1 </dev/null)"; rc=$?
        label="$(basename "$f") from $rel"
        if grep -q 'SC=' "$f"; then ok "$label defines SC itself"; else bad "$label defines SC itself" "uses \$SC with no SC= in the block"; fi
        if [ "$rc" -eq 127 ] || [ "$rc" -eq 126 ] || case "$out" in *"No such file or directory"*) true ;; *) false ;; esac; then
            bad "$label runs in a fresh shell" "rc=$rc: $out"
        else
            ok "$label runs in a fresh shell with no SC injected"
        fi
    done
    if [ "$found" -ge "$min" ]; then ok "$rel yields at least $min \$SC commands ($found found)"
    else bad "$rel yields at least $min \$SC commands" "found $found; the extractor or the skill drifted"; fi
done
# pre-merge's sidecar commands are inline prose, and two of them lean on a rule
# rather than carrying their own SC=; pin the rule they lean on.
contains "pre-merge tells every sidecar command to begin with its own SC=" \
    'begin every one with `SC="<this skill'"'"'s directory>/references/sidecar.sh"`' \
    "$(cat "$repo_root/pre-merge/review-checklist.md")"

# -----------------------------------------------------------------------------
section "/help: Phase 1b sidecar block"

HELP_SKILL="$repo_root/help/SKILL.md"
hblock="$(first_bash_after "$HELP_SKILL" '^<!-- sidecar-read: help -->$')"
if [ -z "$hblock" ]; then
    bad "help/SKILL.md carries the sidecar-read block" "no bash block after <!-- sidecar-read: help -->"
else
    ok "help/SKILL.md carries the sidecar-read block"
fi
check "help/SKILL.md no longer cuts a slug from the remote URL" "" \
    "$(grep -n 'REPO_SLUG' "$HELP_SKILL")"
# BASE_REF comes from /help's Phase 1a. Prepending it runs Phase 1a's variable in the
# block's own process, which a real parallel call does not get; the unset case is
# exercised separately below.
hscript="BASE_REF=main
$(with_sc "$hblock")"

# A project whose base branch has three dated landings.
HR="$tmp/helprepo"
git init -q "$HR"
hc() { GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git -C "$HR" commit -q --allow-empty -m "$2"; }
hc 2026-01-01T00:00:00Z "root $HR"
hc 2026-02-01T00:00:00Z "landing 1"
hc 2026-03-01T00:00:00Z "landing 2"
(cd "$HR" && bash "$SC" init --name helprepo --mode guest --write sidecar --in-tree-path none \
    --no-migrate-archive >/dev/null 2>&1)
HSC="$SKILL_KIT_SIDECAR_ROOT/helprepo"
hrun() { hout="$(cd "$1" && bash -c "$hscript" 2>/dev/null)"; hall="$(cd "$1" && bash -c "$hscript" 2>&1)"; }

hrun "$HR"
contains "a hit prints the sidecar path and its last commit date" \
    "Sidecar: $HSC (last commit $(git -C "$HSC" log -1 --format=%cs))" "$hout"
lacks "a hit prints no SIDECAR MISS" "SIDECAR MISS" "$hall"
contains "with no entries anywhere, both counts are 0" "solutions entries: in-tree (none)=0 sidecar=0" "$hout"
contains "with no entries and two landings, the last merge reads uncompounded" "last merge compounded: no" "$hout"

# A parallel call starts a fresh shell, so BASE_REF can be empty: the verdict must be unknown, never yes.
unset_out="$(cd "$HR" && env -u BASE_REF bash -c "$(with_sc "$hblock")" 2>/dev/null)"; unset_rc=$?
contains "without BASE_REF the last-merge verdict is unknown" "last merge compounded: unknown" "$unset_out"
lacks "without BASE_REF the last-merge verdict is not yes" "last merge compounded: yes" "$unset_out"
check "without BASE_REF the block still exits 0" "0" "$unset_rc"

# A sidecar entry older than the landing before the last one does not cover the last merge.
mkdir -p "$HSC/solutions/perf"
printf 'old\n' > "$HSC/solutions/perf/old.md"
(cd "$HR" && GIT_COMMITTER_DATE=2026-01-15T00:00:00Z bash "$SC" commit -- solutions/perf/old.md -m old >/dev/null 2>&1)
hrun "$HR"
contains "a sidecar entry counts with docs/solutions absent (row 10 does not fire)" "sidecar=1" "$hout"
contains "an entry from before the previous landing leaves the last merge uncompounded" "last merge compounded: no" "$hout"

# An entry written after the previous landing, before the last one lands, covers it.
printf 'new\n' > "$HSC/solutions/perf/new.md"
(cd "$HR" && GIT_COMMITTER_DATE=2026-02-15T00:00:00Z bash "$SC" commit -- solutions/perf/new.md -m new >/dev/null 2>&1)
hrun "$HR"
contains "a sidecar entry written before the last merge landed counts as compounding it" \
    "last merge compounded: yes" "$hout"

# in_tree_path docs/adr with an entry counts as an in-tree entry.
jq '.solutions.in_tree_path = "docs/adr"' "$HSC/sidecar.json" > "$HSC/sj" && mv "$HSC/sj" "$HSC/sidecar.json"
mkdir -p "$HR/docs/adr"
printf '# ADR 1\n' > "$HR/docs/adr/0001.md"
git -C "$HR" add docs/adr/0001.md
hc 2026-03-10T00:00:00Z "adr"
hrun "$HR"
contains "entries at in_tree_path docs/adr are counted (row 10 does not fire)" "in-tree (docs/adr)=1" "$hout"
contains "an in-tree entry committed after the previous landing counts as compounding the last merge" \
    "last merge compounded: yes" "$hout"
git -C "$HSC" checkout -q -- sidecar.json

# Two sidecars claiming one key: a warning naming both, and the block still reports a sidecar.
DUP="$SKILL_KIT_SIDECAR_ROOT/dup-helprepo"
git init -q "$DUP"
cp "$HSC/sidecar.json" "$DUP/sidecar.json"
git -C "$DUP" add sidecar.json && git -C "$DUP" commit -q -m dup
hrun "$HR"
contains "an alias collision prints ALIAS COLLISION" "ALIAS COLLISION" "$hall"
contains "the collision line names the first sidecar" "$DUP" "$hall"
contains "the collision line names the second sidecar" "$HSC" "$hall"
contains "a collision is a warning: the block still prints a sidecar" "Sidecar: " "$hout"
rm -rf "$DUP"
check "the project's tree is untouched by the /help block" "" "$(git -C "$HR" status --porcelain)"

# A miss: SIDECAR MISS on stdout, the init command on stderr, no sidecar created.
sc_before="$(ls "$SKILL_KIT_SIDECAR_ROOT")"
hrun "$MISSREPO"
contains "a miss prints SIDECAR MISS" "SIDECAR MISS" "$hout"
contains "a miss relays the resolver's init command" "SIDECAR MISS: run: bash $SC init" "$hall"
contains "a miss probes the default in-tree store" "in-tree (docs/solutions)=0 sidecar=0" "$hout"
check "a miss creates no sidecar" "$sc_before" "$(ls "$SKILL_KIT_SIDECAR_ROOT")"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
