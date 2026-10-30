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
check "sidecar.json declares schema 2" 2 "$(jq -r .schema "$J")"
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
check "config get on an absent key prints the empty string" "" "$out"

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
# #454: a bare cd on a relative folder consults an inherited CDPATH, which can
# land in a different tree and echo that folder too. Plant a decoy tree holding
# the same relative path and require one line naming the real one.
mkdir -p "$tmp/decoy/lessons/a"; : > "$tmp/decoy/lessons/a/sibling.md"
out=$(cd "$tmp" && CDPATH="$tmp/decoy" bash "$SC" require "sibling.md" --from "lessons/b/entry.md" 2>&1); rc=$?
check "require under an exported CDPATH prints one line naming the real tree" "0:$tmp/lessons/a/sibling.md" "$rc:$out"
out=$(cd "$tmp" && bash "$SC" require "nowhere.md" --from "lessons/b/entry.md" 2>&1); rc=$?
check "require on a bare name absent from every category still reports MISSING" "1:MISSING: nowhere.md (referenced by lessons/b/entry.md)" "$rc:$out"
# #432: the rest of require's resolution order, pinned as the header states it.
# A "path:line" referrer is a label, not a file, so it disables the lookup beside
# the lesson and across category folders.
out=$(cd "$tmp" && bash "$SC" require "sibling.md" --from "lessons/a/entry.md:12" 2>&1); rc=$?
check "a --from <file>:<line> referrer disables the lookup beside the lesson" "1:MISSING: sibling.md (referenced by lessons/a/entry.md:12)" "$rc:$out"
mkdir -p "$tmp/cwdwin" "$tmp/lessons/c"; : > "$tmp/cwdwin/sibling.md"; : > "$tmp/lessons/c/entry.md"
out=$(cd "$tmp/cwdwin" && bash "$SC" require "sibling.md" --from "$tmp/lessons/a/entry.md" 2>&1); rc=$?
check "the current directory wins over the real sibling" "0:$tmp/cwdwin/sibling.md" "$rc:$out"
: > "$tmp/lessons/a/dup.md"; : > "$tmp/lessons/b/dup.md"
out=$(cd "$tmp" && bash "$SC" require "dup.md" --from "lessons/c/entry.md" 2>/dev/null); rc=$?
check "a name in two category folders resolves to the alphabetically first" "0:$tmp/lessons/a/dup.md" "$rc:$out"
err=$(cd "$tmp" && bash "$SC" require "dup.md" --from "lessons/c/entry.md" 2>&1 >/dev/null)
contains "the ambiguity warning names the first match" "lessons/a/dup.md" "$err"
contains "the ambiguity warning names the other match" "lessons/b/dup.md" "$err"
err=$(cd "$tmp" && bash "$SC" require "sibling.md" --from "lessons/b/entry.md" 2>&1 >/dev/null)
check "a name found in one category folder prints no warning" "" "$err"
out=$(cd "$tmp" && bash "$SC" require "sibling.md#why" --from "lessons/a/entry.md" 2>&1); rc=$?
check "require strips a #anchor and finds the file" "0:$tmp/lessons/a/sibling.md" "$rc:$out"
out=$(cd "$tmp" && bash "$SC" require "nowhere.md#why" --from "lessons/a/entry.md" 2>&1); rc=$?
check "require on an absent name with an anchor reports the path as given" "1:MISSING: nowhere.md#why (referenced by lessons/a/entry.md)" "$rc:$out"
# shellcheck disable=SC2088  # literal ~user and ~ are the inputs under test
out=$(HOME="$tmp/home" bash "$SC" require "~user/r/a.md" --from "PRD #1" 2>&1); rc=$?
# shellcheck disable=SC2088
check "require leaves ~user/ alone" "1:MISSING: ~user/r/a.md (referenced by PRD #1)" "$rc:$out"
# shellcheck disable=SC2088
out=$(cd "$tmp" && HOME="$tmp/home" bash "$SC" require "~" --from "PRD #1" 2>&1); rc=$?
# shellcheck disable=SC2088
check "require leaves a bare ~ alone (it is not expanded to \$HOME)" "1:MISSING: ~ (referenced by PRD #1)" "$rc:$out"
# The printed path is physical (pwd -P): a symlinked folder resolves to its target.
mkdir -p "$tmp/realdir"; : > "$tmp/realdir/linked.md"; ln -s "$tmp/realdir" "$tmp/linkdir"
out=$(cd "$tmp" && bash "$SC" require "linkdir/linked.md" --from "PRD #1" 2>&1); rc=$?
check "require prints the physical path, resolving a symlinked folder" "0:$tmp/realdir/linked.md" "$rc:$out"
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
RR="$(cd "$PROJ" && bash "$SC" path review-responses)"
check "path review-responses is the sidecar's review-responses/ directory" "$SIDECAR/review-responses" "$RR"
check "path review-responses creates the directory" "yes" "$([ -d "$SIDECAR/review-responses" ] && echo yes || echo no)"
run "$PROJ" path reviews
check "path refuses a directory it does not name (reviews/ belongs to the stamp)" 2 "$rc"
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
lacks "nothing is reported moved from api/" "from $A/api into" "$out"
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
section "config set mode re-derives forge.write (#425)"

# forge.write is derived from mode inside init, so a hand edit of mode left it
# stale. The verb must produce exactly what init produces for the new mode:
# the expected values come from real init runs, not from a restated literal.
mkdir -p "$tmp/cfg"
CFG_O="$tmp/cfg/own"; CFG_G="$tmp/cfg/guest"
mkrepo "$CFG_O"; git -C "$CFG_O" remote add origin git@github.com:acme/cfg-own.git
mkrepo "$CFG_G"; git -C "$CFG_G" remote add origin git@github.com:acme/cfg-guest.git
run "$CFG_O" init --name cfg-own --mode owned --write sidecar --in-tree-path none
run "$CFG_G" init --name cfg-guest --mode guest --write sidecar --in-tree-path none
OWN_FW="$(jq -c '.forge.write' "$SKILL_KIT_SIDECAR_ROOT/cfg-own/sidecar.json")"
GUEST_FW="$(jq -c '.forge.write' "$SKILL_KIT_SIDECAR_ROOT/cfg-guest/sidecar.json")"
check "init gives an owned repo on a known forge write access (fixture sanity)" "yes" "$(if [ "$OWN_FW" != "[]" ]; then echo yes; fi)"
run "$CFG_O" config set mode guest
check "config set mode guest succeeds" 0 "$rc"
check "mode is now guest" "guest" "$(jq -r '.mode' "$SKILL_KIT_SIDECAR_ROOT/cfg-own/sidecar.json")"
check "forge.write matches what init produces for guest" "$GUEST_FW" "$(jq -c '.forge.write' "$SKILL_KIT_SIDECAR_ROOT/cfg-own/sidecar.json")"
check "the change is committed" "" "$(git -C "$SKILL_KIT_SIDECAR_ROOT/cfg-own" status --porcelain)"
check "the commit subject names the mode" "sidecar: set mode guest" "$(git -C "$SKILL_KIT_SIDECAR_ROOT/cfg-own" log -1 --format=%s)"
run "$CFG_O" config set mode owned
check "forge.write matches what init produces for owned, going back" "$OWN_FW" "$(jq -c '.forge.write' "$SKILL_KIT_SIDECAR_ROOT/cfg-own/sidecar.json")"
run "$CFG_O" config set mode admin
check "config set mode rejects an unknown mode" 2 "$rc"
run "$CFG_O" config set forge.kind none
check "config set refuses a key it does not own" 2 "$rc"
run "$CFG_O" config set mode
check "config set mode needs a value" 2 "$rc"
# The skill points at the verb for mode.
contains "/init-pipeline section 8 tells the reader to change mode with the verb" 'config set mode' "$(cat "$repo_root/init-pipeline/SKILL.md")"

# -----------------------------------------------------------------------------
section "base-ref: the fallback, a declared base_ref, and could-not-look (#597)"

# Its own sidecar root: the corrupt-sidecar.json case below would otherwise make
# every later miss in this suite refuse instead of miss.
BR="$tmp/br"; mkdir -p "$BR"
BR_ROOT="$BR/sidecars"
# brun <dir> <args...> — sidecar.sh under BR_ROOT; stdout in $out, stderr in $err, exit in $rc
brun() {
    local d="$1"; shift
    out="$(cd "$d" && SKILL_KIT_SIDECAR_ROOT="$BR_ROOT" bash "$SC" "$@" 2>"$BR/err")"; rc=$?
    err="$(cat "$BR/err")"
}
mkrepo "$BR/up"
git -C "$BR/up" branch develop
git clone -q "$BR/up" "$BR/clone"
# origin/HEAD points at develop, not main: main is first in the fallback list, so
# a clone whose origin/HEAD were main could not tell "follow origin/HEAD" from
# "pick the first candidate" (the bug #596 exists to fix).
git -C "$BR/clone" remote set-head origin develop >/dev/null
check "the clone's origin/HEAD is origin/develop (fixture sanity)" origin/develop \
    "$(git -C "$BR/clone" symbolic-ref refs/remotes/origin/HEAD --short)"

brun "$BR/clone" base-ref
check "a miss falls back to origin/HEAD's ref" "0 origin/develop" "$rc $out"
check "a miss on a resolving origin ref prints nothing on stderr" "" "$err"
brun "$BR/clone" base-ref --name
check "a miss with --name prints the bare branch" "0 develop" "$rc $out"

mkrepo "$BR/local"; git -C "$BR/local" branch -m prod
brun "$BR/local" base-ref
check "no origin: the first resolving candidate, as the local branch" "0 prod" "$rc $out"
contains "no origin: the note says the local branch may be stale" "may be stale" "$err"
brun "$BR/local" base-ref --name
check "no origin, --name: the candidate's name" "0 prod" "$rc $out"

mkrepo "$BR/none"; git -C "$BR/none" branch -m feature
brun "$BR/none" base-ref
check "no base branch found exits 1 and prints no ref" "1 " "$rc $out"
contains "no base branch found points at config set base_ref" "config set base_ref" "$err"

brun "$BR/clone" init --name br --mode owned --write sidecar --in-tree-path none --no-migrate-archive
check "init the base-ref sidecar (fixture sanity)" 0 "$rc"
BSJ="$BR_ROOT/br/sidecar.json"
brun "$BR/clone" base-ref
check "a sidecar with no base_ref key falls back like a miss" "0 origin/develop" "$rc $out"

brun "$BR/clone" config set base_ref develop
check "config set base_ref develop succeeds" 0 "$rc"
check "the key is written" develop "$(jq -r .base_ref "$BSJ")"
check "the change is committed" "" "$(git -C "$BR_ROOT/br" status --porcelain)"
check "the commit subject names the key" "sidecar: set base_ref develop" "$(git -C "$BR_ROOT/br" log -1 --format=%s)"
brun "$BR/clone" config get base_ref
check "config get base_ref reads it back" develop "$out"
brun "$BR/clone" base-ref
check "a declared base_ref prints origin/<base_ref>" "0 origin/develop" "$rc $out"
brun "$BR/clone" base-ref --name
check "a declared base_ref with --name prints the bare name" "0 develop" "$rc $out"

brun "$BR/clone" config set base_ref origin/develop
check "config set refuses the remote ref form" 2 "$rc"
brun "$BR/clone" config set base_ref 'bad..name'
check "config set refuses an invalid branch name" 2 "$rc"
brun "$BR/clone" config set base_ref nosuch
check "config set refuses a branch that resolves to no ref" 1 "$rc"
check "a refused set leaves the key as it was" develop "$(jq -r .base_ref "$BSJ")"
brun "$BR/clone" config set base_ref
check "config set base_ref needs a value" 2 "$rc"
git -C "$BR/clone" tag v1
# A branch switch gives @{-1} something to expand to, so git's own name check accepts it.
git -C "$BR/clone" checkout -q -b prev && git -C "$BR/clone" checkout -q -
brun "$BR/clone" config set base_ref '@{-1}'
check "config set refuses a revision expression like @{-1}" 1 "$rc"
check "a refused @{-1} leaves the key as it was" develop "$(jq -r .base_ref "$BSJ")"
brun "$BR/clone" config set base_ref v1
check "config set refuses a tag name" 1 "$rc"
check "a refused tag leaves the key as it was" develop "$(jq -r .base_ref "$BSJ")"

# Hand edits: the verb refuses each shape, and never prints the fallback.
bset() { jq "$@" "$BSJ" > "$BR/sj" && mv "$BR/sj" "$BSJ"; }
bset '.base_ref = "gone"'
brun "$BR/clone" base-ref
check "a declared base_ref that resolves to no ref exits 1 and prints no ref" "1 " "$rc $out"
contains "the refusal names the key" "base_ref is gone" "$err"
brun "$BR/clone" base-ref --name
check "--name refuses the same unresolvable base_ref" "1 " "$rc $out"
bset '.base_ref = "v1"'
brun "$BR/clone" base-ref
check "a declared base_ref naming only a tag exits 1 and prints no ref" "1 " "$rc $out"
for expr in 'develop~1' 'develop^' 'develop^{tree}' 'HEAD'; do
    # shellcheck disable=SC2016 # $e is a jq variable, not a shell one
    bset --arg e "$expr" '.base_ref = $e'
    brun "$BR/clone" base-ref
    check "a hand-set revision expression $expr exits 1 and prints no ref" "1 " "$rc $out"
done
bset '.base_ref = ""'
brun "$BR/clone" base-ref
check "a declared-empty base_ref exits 1 rather than falling back" "1 " "$rc $out"
bset '.base_ref = 42'
brun "$BR/clone" base-ref
check "a non-string base_ref exits 1" "1 " "$rc $out"
bset '.base_ref = "develop"'

cp "$BSJ" "$BR/good.json"
printf '{ not json\n' > "$BSJ"
brun "$BR/clone" base-ref
check "an unreadable sidecar.json exits 1 and prints no ref" "1 " "$rc $out"
lacks "an unreadable sidecar.json is not reported as a miss" "SIDECAR MISS" "$err"
cp "$BR/good.json" "$BSJ"

nojq="$BR/nojq-bin"; mkdir -p "$nojq"
for d in /opt/homebrew/bin /usr/local/bin /usr/bin /bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        b="${f##*/}"; [ "$b" = jq ] && continue
        [ -e "$nojq/$b" ] || ln -s "$f" "$nojq/$b"
    done
done
out="$(cd "$BR/clone" && SKILL_KIT_SIDECAR_ROOT="$BR_ROOT" PATH="$nojq" bash "$SC" base-ref 2>"$BR/err")"; rc=$?
check "with jq missing, base-ref exits 1 and prints no ref" "1 " "$rc $out"
contains "with jq missing, the refusal says why" "jq is required" "$(cat "$BR/err")"
check "base-ref commits nothing in the project" "" "$(git -C "$BR/clone" status --porcelain)"

# fenced_with <file> <marker> — the first fenced block containing <marker>, dedented.
fenced_with() {
    awk -v m="$2" '
        /^[[:space:]]*```/ { if (inb) { if (f) { for (i = 1; i <= n; i++) print b[i]; exit } inb = 0 } else { inb = 1; n = 0; f = 0 } next }
        inb { b[++n] = $0; if (index($0, m)) f = 1 }
    ' "$1" | sed 's/^[[:space:]]*//'
}

# /init-pipeline section 8's Q4 block, as written: it offers the detected branch
# when base_ref is unasked, and stands down once the key is answered.
q4="$(fenced_with "$repo_root/init-pipeline/SKILL.md" 'config get base_ref')"
[ -n "$q4" ] || bad "/init-pipeline carries the Q4 base_ref block" "no fenced block mentions config get base_ref"
q4="${q4//<this skill\'s directory>\/scripts\/sidecar.sh/$SC}"
bset 'del(.base_ref)'
q4out="$(cd "$BR/clone" && SKILL_KIT_SIDECAR_ROOT="$BR_ROOT" bash -c "$q4" 2>&1)"
check "Q4 on an unasked key offers the detected origin/HEAD branch" "detected=develop" "$q4out"
brun "$BR/none" init --name brnone --mode owned --write sidecar --in-tree-path none --no-migrate-archive
q4out="$(cd "$BR/none" && SKILL_KIT_SIDECAR_ROOT="$BR_ROOT" bash -c "$q4" 2>&1)"
check "Q4 with nothing detected offers no default" "detected=none" "$q4out"
bset '.base_ref = "develop"'
q4out="$(cd "$BR/clone" && SKILL_KIT_SIDECAR_ROOT="$BR_ROOT" bash -c "$q4" 2>&1)"
check "Q4 on an answered key does not ask" "base_ref=develop (answered; not asking)" "$q4out"
contains "/init-pipeline writes the answer through config set base_ref" 'config set base_ref <branch>' "$(cat "$repo_root/init-pipeline/SKILL.md")"

# /pre-merge Phase 1 step 3 takes both forms from the verb and derives nothing itself.
# shellcheck disable=SC2016 # the dollars are the skill's literal text
pm3="$(fenced_with "$repo_root/pre-merge/SKILL.md" 'git log --oneline "$BASE_REF..HEAD"')"
lacks "/pre-merge step 3 carries no symbolic-ref derivation" "symbolic-ref" "$pm3"
# shellcheck disable=SC2016
contains "/pre-merge step 3 takes BASE_REF from the verb" 'BASE_REF="$(bash "$SC" base-ref)"' "$pm3"
# shellcheck disable=SC2016
contains "/pre-merge step 3 takes BASE_BRANCH from the verb" 'BASE_BRANCH="$(bash "$SC" base-ref --name)"' "$pm3"
pm3="${pm3//<this skill\'s directory>\/references\/sidecar.sh/$SC}"
pm3out="$(cd "$BR/clone" && SKILL_KIT_SIDECAR_ROOT="$BR_ROOT" bash -c "$pm3"' >/dev/null; printf "%s|%s" "$BASE_BRANCH" "$BASE_REF"' 2>/dev/null)"
check "/pre-merge step 3, run, takes the declared base for both forms" "develop|origin/develop" "$pm3out"

# -----------------------------------------------------------------------------
section "profile: unasked, declared, declared-empty, and could-not-look (#600)"

# Its own root, for the same reason as base-ref's: the corrupt case below.
PF="$tmp/pf"; mkdir -p "$PF"
PF_ROOT="$PF/sidecars"
# prun <dir> <args...> — sidecar.sh under PF_ROOT; stdout in $out, stderr in $err, exit in $rc
prun() {
    local d="$1"; shift
    out="$(cd "$d" && SKILL_KIT_SIDECAR_ROOT="$PF_ROOT" bash "$SC" "$@" 2>"$PF/err")"; rc=$?
    err="$(cat "$PF/err")"
}
mkrepo "$PF/up"
git -C "$PF/up" branch develop
git clone -q "$PF/up" "$PF/clone"
git -C "$PF/clone" remote set-head origin develop >/dev/null
PFH="## Repo profile (from the operator's sidecar; follow it)"
ALL_UNASKED="Not declared (ask before running anything not listed): typecheck, test, lint, package_manager, hook_manager, hazards"

prun "$PF/clone" profile
check "a miss prints the all-unasked block, with base-ref's fallback" \
    "0 $PFH"$'\n'"Base ref: origin/develop"$'\n'"$ALL_UNASKED" "$rc $out"
prun "$PF/clone" profile extra
check "profile takes no arguments" 2 "$rc"

prun "$PF/clone" init --name pf --mode owned --write sidecar --in-tree-path none --no-migrate-archive
check "init the profile sidecar (fixture sanity)" 0 "$rc"
PSJ="$PF_ROOT/pf/sidecar.json"
check "a new init writes schema 2" 2 "$(jq -r .schema "$PSJ")"
check "a new init writes no verify stub" false "$(jq 'has("verify")' "$PSJ")"
prun "$PF/clone" profile
check "a schema-2 sidecar with no verify key renders every key unasked" \
    "0 $PFH"$'\n'"Base ref: origin/develop"$'\n'"$ALL_UNASKED" "$rc $out"

# The four schema-1 sidecars in the wild carry init's old stub; "" there was never an answer.
pset() { jq "$@" "$PSJ" > "$PF/sj" && mv "$PF/sj" "$PSJ"; }
pset '.schema = 1 | .verify = {typecheck: "", test: "", lint: "", package_manager: "", hook_manager: ""}'
git -C "$PF_ROOT/pf" commit -q -am "fixture: schema-1 stub"
prun "$PF/clone" profile
check "schema 1 with the init stub lists every verify field under Not declared" \
    "0 $PFH"$'\n'"Base ref: origin/develop"$'\n'"$ALL_UNASKED" "$rc $out"
lacks "schema 1's empty stub never renders as none" "none" "$out"

prun "$PF/clone" config set verify.typecheck "pnpm run typecheck"
check "config set verify.typecheck succeeds" 0 "$rc"
check "the first verify write moves the sidecar to schema 2" 2 "$(jq -r .schema "$PSJ")"
check "the migration drops the schema-1 stub, leaving only the answer" '{"typecheck":"pnpm run typecheck"}' "$(jq -c .verify "$PSJ")"
check "the write is committed" "" "$(git -C "$PF_ROOT/pf" status --porcelain)"
check "the commit subject names the key" "sidecar: set verify.typecheck" "$(git -C "$PF_ROOT/pf" log -1 --format=%s)"

prun "$PF/clone" config set verify.lint ""
check "config set verify.lint to empty succeeds" 0 "$rc"
prun "$PF/clone" profile
contains "a declared-empty field on schema 2 renders as none" "  lint: none" "$out"
contains "the unasked fields stay under Not declared" \
    "Not declared (ask before running anything not listed): test, package_manager, hook_manager, hazards" "$out"
lacks "a declared-empty field is not under Not declared" "lint, " "${out##*Not declared}"

prun "$PF/clone" config set verify.test "pnpm run test"
prun "$PF/clone" config set verify.hazards \
    '[{"reason":"resets the shared staging database","command":"Bash(pnpm test:e2e*)"},{"reason":"never push to the staging branch"}]'
check "config set verify.hazards with valid entries succeeds" 0 "$rc"
prun "$PF/clone" profile
check "the block matches the format #601 pastes" "0 $PFH
Base ref: origin/develop
Verify:
  typecheck: pnpm run typecheck
  test: pnpm run test
  lint: none
Hazards (do not run; ask first):
  - Bash(pnpm test:e2e*): resets the shared staging database
  - never push to the staging branch
Not declared (ask before running anything not listed): package_manager, hook_manager" "$rc $out"

# Every refused hazard list writes nothing and commits nothing.
cp "$PSJ" "$PF/good.json"
before="$(git -C "$PF_ROOT/pf" rev-parse HEAD)"
for bad_h in '[{"command":"Bash(rm *)"}]' '[{"reason":""}]' '[{"reason":"   "}]' '[{"reason":42}]' \
             '[{"reason":"x","command":42}]' '[{"reason":"x","command":""}]' '[{"reason":"x","cmd":"y"}]' \
             '[{"reason":"x","command":"   "}]' \
             '["just a string"]' '{"reason":"x"}' 'not json' '[{"reason":"two\nlines"}]'; do
    prun "$PF/clone" config set verify.hazards "$bad_h"
    if [ "$rc" -ne 0 ] && cmp -s "$PSJ" "$PF/good.json" && [ "$(git -C "$PF_ROOT/pf" rev-parse HEAD)" = "$before" ]; then
        ok "config set verify.hazards refuses $bad_h and writes nothing"
    else
        bad "config set verify.hazards refuses $bad_h and writes nothing" "rc=$rc, sidecar.json or HEAD changed"
    fi
done
prun "$PF/clone" config set verify.hazards '[{"command":"Bash(rm *)"}]'
contains "a hazard with no reason is refused by name" "reason" "$err"

prun "$PF/clone" config set verify.test $'pnpm test\nrm -rf /'
check "a verify command containing a newline is refused" 1 "$rc"
check "a refused command writes nothing" "pnpm run test" "$(jq -r .verify.test "$PSJ")"
prun "$PF/clone" config set verify.test "   "
check "a whitespace-only verify command is refused" 1 "$rc"
check "a refused whitespace-only command writes nothing" "pnpm run test" "$(jq -r .verify.test "$PSJ")"
prun "$PF/clone" config set verify.nosuch x
check "an unknown verify field is a usage error" 2 "$rc"
prun "$PF/clone" config set verify x
check "a bare verify key is a usage error" 2 "$rc"

prun "$PF/clone" config set verify.hazards '[]'
prun "$PF/clone" profile
contains "a declared-empty hazard list renders as none" "Hazards (do not run; ask first): none" "$out"
lacks "a declared-empty hazard list is not under Not declared" "hazards" "${out##*Not declared}"

# Hand edits the verbs would refuse: profile cannot trust what it read, so it prints no block.
for shape in '.verify.test = 42' '.verify = "x"' '.verify.hazards = "x"' '.verify.hazards = [{"command":"y"}]' \
             '.verify.test = "a\nb"' '.verify.test = "  "' '.verify.hazards = [{"reason":"x","command":" "}]' '.schema = "2"'; do
    cp "$PF/good.json" "$PSJ"; pset "$shape"
    prun "$PF/clone" profile
    check "a hand-set $shape makes profile exit 1 and print no block" "1 " "$rc $out"
    contains "a hand-set $shape is refused by profile's own read, not base-ref's" "profile: cannot read verify" "$err"
done
# base-ref reads sidecar.json first, so an unparseable file stops there; this
# case covers that refusal, and the shapes above cover profile's own read.
printf '{ not json\n' > "$PSJ"
prun "$PF/clone" profile
check "an unreadable sidecar.json makes profile exit 1 and print no block" "1 " "$rc $out"
contains "an unreadable sidecar.json stops at base-ref" "profile: no base ref" "$err"
lacks "an unreadable sidecar.json is not reported as a miss" "SIDECAR MISS" "$err"
cp "$PF/good.json" "$PSJ"

out="$(cd "$PF/clone" && SKILL_KIT_SIDECAR_ROOT="$PF_ROOT" PATH="$nojq" bash "$SC" profile 2>"$PF/err")"; rc=$?
check "with jq missing, profile exits 1 and prints no block" "1 " "$rc $out"
mkrepo "$PF/nobase"; git -C "$PF/nobase" branch -m feature
prun "$PF/nobase" profile
check "with no base branch found, profile exits 1 and prints no block" "1 " "$rc $out"
check "profile and config set write nothing in the project" "" "$(git -C "$PF/clone" status --porcelain)"

# /init-pipeline section 8's Q5 block, as written: it names the unasked keys,
# proposes defaults from the repo's files, and writes nothing.
q5="$(fenced_with "$repo_root/init-pipeline/SKILL.md" 'detected.hook_manager')"
[ -n "$q5" ] || bad "/init-pipeline carries the Q5 verify block" "no fenced block mentions detected.hook_manager"
q5="${q5//<this skill\'s directory>\/scripts\/sidecar.sh/$SC}"
printf '{"scripts":{"typecheck":"tsc --noEmit","test":"vitest run"}}\n' > "$PF/clone/package.json"
: > "$PF/clone/pnpm-lock.yaml"; : > "$PF/clone/lefthook.yml"
cp "$PF/good.json" "$PSJ"; pset 'del(.verify.lint, .verify.hazards)'
git -C "$PF_ROOT/pf" commit -q -am "fixture: two keys unasked"
before="$(git -C "$PF_ROOT/pf" rev-parse HEAD)"
q5out="$(cd "$PF/clone" && SKILL_KIT_SIDECAR_ROOT="$PF_ROOT" bash -c "$q5" 2>&1)"
check "Q5 names exactly the unasked keys" "unasked=lint, package_manager, hook_manager, hazards" "$(printf '%s\n' "$q5out" | grep '^unasked=')"
contains "Q5 proposes the lockfile's package manager" "detected.package_manager=pnpm" "$q5out"
contains "Q5 proposes a package.json script through the package manager" "detected.test=pnpm run test" "$q5out"
check "Q5 proposes nothing for lint when the script is absent" "detected.lint=" "$(printf '%s\n' "$q5out" | grep '^detected.lint=')"
contains "Q5 proposes the hook manager" "detected.hook_manager=lefthook" "$q5out"
check "Q5 writes nothing to the sidecar before the user confirms" "$before" "$(git -C "$PF_ROOT/pf" rev-parse HEAD)"
check "Q5 leaves sidecar.json clean" "" "$(git -C "$PF_ROOT/pf" status --porcelain)"
rm -f "$PF/clone/package.json" "$PF/clone/pnpm-lock.yaml" "$PF/clone/lefthook.yml"
cp "$PF/good.json" "$PSJ"; pset '.verify.package_manager = "pnpm" | .verify.hook_manager = ""'
git -C "$PF_ROOT/pf" commit -q -am "fixture: every key answered"
q5out="$(cd "$PF/clone" && SKILL_KIT_SIDECAR_ROOT="$PF_ROOT" bash -c "$q5" 2>&1)"
check "Q5 on a fully answered sidecar prints no unasked line" "" "$(printf '%s\n' "$q5out" | grep '^unasked=')"
check "Q5 with no package.json or lockfile proposes no test command" "detected.test=" "$(printf '%s\n' "$q5out" | grep '^detected.test=')"
printf '{"scripts":{"test":"vitest run"}}\n' > "$PF/clone/package.json"
q5out="$(cd "$PF/clone" && SKILL_KIT_SIDECAR_ROOT="$PF_ROOT" bash -c "$q5" 2>&1)"
check "Q5 with a test script but no lockfile proposes no test command" "detected.test=" "$(printf '%s\n' "$q5out" | grep '^detected.test=')"
rm -f "$PF/clone/package.json"
# A failed profile prints no Not declared line, which the prose reads as
# "every key answered"; the guard must stop the block instead.
printf '{ not json\n' > "$PSJ"
q5out="$(cd "$PF/clone" && SKILL_KIT_SIDECAR_ROOT="$PF_ROOT" bash -c "$q5" 2>&1)"; rc=$?
check "Q5 on an unreadable sidecar.json exits 1" 1 "$rc"
lacks "Q5 on an unreadable sidecar.json prints no unasked line" "unasked=" "$q5out"
cp "$PF/good.json" "$PSJ"; pset '.verify.package_manager = "pnpm" | .verify.hook_manager = ""'

# /execute Step 4 reads the declared commands from profile and hard-codes no pnpm line.
ex4="$(awk '/^### 4\. Verify/{f=1} /^#### Tier 1/{f=0} f' "$repo_root/execute/SKILL.md")"
# shellcheck disable=SC2016
contains "/execute Step 4 runs profile" 'bash "$SC" profile' "$ex4"
lacks "/execute Step 4 hard-codes no pnpm command" "pnpm run" "$ex4"
# An AFK run with no typecheck or test would commit every unit unchecked (#625).
lacks "/execute Step 4 no longer runs an AFK iteration past an undeclared command" "run nothing for it" "$ex4"
contains "/execute Step 4 stops an AFK iteration on an undeclared typecheck or test" "In an AFK iteration, **stop**" "$ex4"
lacks "/execute's Review Notes template hard-codes no pnpm command" '| `pnpm run' "$(cat "$repo_root/execute/SKILL.md")"


# -----------------------------------------------------------------------------
section "range: a slice's own commits, the base fallback, and could-not-look (#599)"

# Its own root, for the same reason as base-ref's: the corrupt case below.
RG="$tmp/rg"; mkdir -p "$RG"
RG_ROOT="$RG/sidecars"
rrun() {
    local d="$1"; shift
    out="$(cd "$d" && SKILL_KIT_SIDECAR_ROOT="$RG_ROOT" bash "$SC" "$@" 2>"$RG/err")"; rc=$?
    err="$(cat "$RG/err")"
}
mkrepo "$RG/up"
git clone -q "$RG/up" "$RG/p"
git -C "$RG/p" remote set-head origin main >/dev/null
rrun "$RG/p" range
check "a miss with no id is the base range" "0 origin/main..HEAD" "$rc $out"
rrun "$RG/p" range W-1
check "a miss with an id is the base range too: no sidecar, no work item" "0 origin/main..HEAD" "$rc $out"
rrun "$RG/p" range nope
check "range refuses an id that is not W-<n>" 2 "$rc"

rrun "$RG/p" init --name rg --mode guest --write sidecar --in-tree-path none --no-migrate-archive
check "init the range sidecar (fixture sanity)" 0 "$rc"
RSJ="$RG_ROOT/rg/sidecar.json"
printf 'slice body\n' > "$RG/body"
rrun "$RG/p" work create --kind slice --body-file "$RG/body"; S1="$out"
rrun "$RG/p" work create --kind slice --body-file "$RG/body"; S2="$out"
check "two slices created (fixture sanity)" "W-1 W-2" "$S1 $S2"
rrun "$RG/p" range "$S1"
check "an item with no start_sha is the base range" "0 origin/main..HEAD" "$rc $out"
check "no start_sha prints no notice" "" "$err"

# Two slices committed on one branch, each start recorded the way /execute does.
git -C "$RG/p" switch -q -c feature
rrun "$RG/p" work set "$S1" start_sha "$(git -C "$RG/p" rev-parse HEAD)"
check "work set start_sha accepts 40 hex" 0 "$rc"
rrun "$RG/p" work view "$S1" --json
check "start_sha reads back from view --json" "$(git -C "$RG/p" rev-parse HEAD)" "$(printf '%s' "$out" | jq -r .start_sha)"
printf 'a\n' > "$RG/p/a.txt"; git -C "$RG/p" add a.txt; git -C "$RG/p" commit -q -m 'slice 1: a'
S2_START="$(git -C "$RG/p" rev-parse HEAD)"
rrun "$RG/p" work set "$S2" start_sha "$S2_START"
printf 'b\n' > "$RG/p/b.txt"; git -C "$RG/p" add b.txt; git -C "$RG/p" commit -q -m 'slice 2: b'
printf 'c\n' > "$RG/p/c.txt"; git -C "$RG/p" add c.txt; git -C "$RG/p" commit -q -m 'slice 2: c'
rrun "$RG/p" range "$S2"
check "range on the second slice starts at its start_sha" "0 $S2_START..HEAD" "$rc $out"
check "range on the second slice lists only its own commits" "slice 2: b slice 2: c" \
    "$(git -C "$RG/p" log --reverse --format=%s "$out" | tr '\n' ' ' | sed 's/ $//')"
rrun "$RG/p" range "$S1"
check "range on the first slice covers both, never narrower than its span" \
    "slice 1: a slice 2: b slice 2: c" "$(git -C "$RG/p" log --reverse --format=%s "$out" | tr '\n' ' ' | sed 's/ $//')"

rrun "$RG/p" work set "$S2" start_sha abc1234
check "work set refuses a start_sha that is not 40 hex" 1 "$rc"
rrun "$RG/p" work set "$S2" start_sha "$(printf '%s' "$S2_START" | tr 'a-f' 'A-F')"
check "work set refuses an uppercase start_sha" 1 "$rc"
rrun "$RG/p" work view "$S2" --json
check "a refused set leaves start_sha as it was" "$S2_START" "$(printf '%s' "$out" | jq -r .start_sha)"

# A fold rewrites the start: reset slice 1's commit away and recommit on a new parent.
git -C "$RG/p" switch -q -c folded main
printf 'a2\n' > "$RG/p/a.txt"; git -C "$RG/p" add a.txt; git -C "$RG/p" commit -q -m 'slice 1: a (folded)'
git -C "$RG/p" cherry-pick "$S2_START..feature" >/dev/null 2>&1
check "the folded branch carries slice 2's commits on a rewritten start (fixture sanity)" \
    "slice 1: a (folded) slice 2: b slice 2: c" "$(git -C "$RG/p" log --reverse --format=%s main..HEAD | tr '\n' ' ' | sed 's/ $//')"
rrun "$RG/p" range "$S2"
check "a start_sha the fold rewrote away falls back to the base range" "0 origin/main..HEAD" "$rc $out"
contains "the notice names the work item" "$S2 started at" "$err"
contains "the notice says the start is no longer on this branch" "no longer on this branch" "$err"
git -C "$RG/p" switch -q feature

# A start_sha naming no commit in this repository is no longer on the branch either.
sed -i.bak "s/^start_sha: .*/start_sha: $(printf '%040d' 7)/" "$RG_ROOT/rg/work/$S2.md"
rrun "$RG/p" range "$S2"
check "a start_sha naming no commit falls back" "0 origin/main..HEAD" "$rc $out"
contains "and names the item" "$S2 started at" "$err"
mv "$RG_ROOT/rg/work/$S2.md.bak" "$RG_ROOT/rg/work/$S2.md"

# The base moves under a recorded start: the start stays an ancestor of HEAD
# but the range would fill with another PR's commits (and its Fix-Findings-Run
# line). Its own clone, so the later cases keep their base.
git clone -q "$RG/up" "$RG/p2"
git -C "$RG/p2" remote set-head origin main >/dev/null
git -C "$RG/p2" switch -q -c rebased
P2_START="$(git -C "$RG/p2" rev-parse HEAD)"
rrun "$RG/p2" work set "$S2" start_sha "$P2_START"
printf 'f\n' > "$RG/p2/f.txt"; git -C "$RG/p2" add f.txt; git -C "$RG/p2" commit -q -m 'slice: f'
rrun "$RG/p2" range "$S2"
check "before the base moves the start is used (fixture sanity)" "0 $P2_START..HEAD" "$rc $out"
printf 'o\n' > "$RG/up/o.txt"; git -C "$RG/up" add o.txt
git -C "$RG/up" commit -q -m 'other PR: o' -m 'Fix-Findings-Run: 20200101T000000Z'
git -C "$RG/p2" fetch -q origin
git -C "$RG/p2" branch -q merged rebased
git -C "$RG/p2" rebase -q origin/main >/dev/null 2>&1
check "the rebased start is still an ancestor of HEAD (fixture sanity)" 0 \
    "$(git -C "$RG/p2" merge-base --is-ancestor "$P2_START" HEAD; echo $?)"
rrun "$RG/p2" range "$S2"
check "after a rebase onto an advanced base the range is the base range" "0 origin/main..HEAD" "$rc $out"
contains "the rebase notice names the work item" "$S2 started at" "$err"
contains "and says the base moved" "the base moved under it" "$err"
check "the base range lists only the slice's commit" "slice: f" \
    "$(git -C "$RG/p2" log --format=%s "$out")"
git -C "$RG/p2" switch -q merged
git -C "$RG/p2" merge -q --no-edit origin/main >/dev/null 2>&1
check "the merged branch holds the other PR's commit (fixture sanity)" "other PR: o" \
    "$(git -C "$RG/p2" log --no-merges --format=%s -1 origin/main)"
rrun "$RG/p2" range "$S2"
check "after a merge from the base the range is the base range" "0 origin/main..HEAD" "$rc $out"
contains "the merge notice names the work item" "$S2 started at" "$err"
git -C "$RG/p2" switch -q rebased
rrun "$RG/p2" work set "$S2" start_sha "$(git -C "$RG/p2" merge-base origin/main HEAD)"
rrun "$RG/p2" range "$S2"
check "a start recorded after the rebase is used again" \
    "0 $(git -C "$RG/p2" merge-base origin/main HEAD)..HEAD" "$rc $out"
check "and prints no notice" "" "$err"

rrun "$RG/p" range W-99
check "an id the sidecar backend does not hold exits 1 and prints no range" "1 " "$rc $out"
printf 'not a work item\n' > "$RG_ROOT/rg/work/W-3.md"
rrun "$RG/p" range W-3
check "an unparseable work item exits 1 and prints no range" "1 " "$rc $out"
rm -f "$RG_ROOT/rg/work/W-3.md"

cp "$RSJ" "$RG/good.json"
printf '{ not json\n' > "$RSJ"
rrun "$RG/p" range "$S2"
check "an unreadable sidecar.json exits 1 and prints no range" "1 " "$rc $out"
rrun "$RG/p" range
check "an unreadable sidecar.json exits 1 with no id too" "1 " "$rc $out"
cp "$RG/good.json" "$RSJ"

# The github slices backend has no work item to hold start_sha, so it always falls back.
jq '.mode = "owned" | .forge.kind = "github" | .forge.write = ["issues","labels","milestones","prs"]' "$RSJ" > "$RG/sj" && mv "$RG/sj" "$RSJ"
rrun "$RG/p" range W-99
check "on the github backend an id with no work item is the base range" "0 origin/main..HEAD" "$rc $out"
check "range commits nothing in the project" "" "$(git -C "$RG/p" status --porcelain)"

# -----------------------------------------------------------------------------
section "migrate-archive verb, --archive-alias validation, skipped-folder hint (#420)"

mkdir -p "$tmp/mv"
MV="$tmp/mv/Widget"
mkrepo "$MV"
git -C "$MV" remote add origin git@github.com:acme/widget-core.git
mkdir -p "$A/widget" "$A/acme-widget-core"
printf 'w\n' > "$A/widget/w-2026-01-01.md"
printf 'c\n' > "$A/acme-widget-core/c-2026-01-02.md"

# A sidecar made before migration existed (or with --no-migrate-archive): the
# old folders are still real directories, and init now refuses to run again.
run "$MV" init --name widget --mode owned --write sidecar --in-tree-path none --no-migrate-archive
WSC="$SKILL_KIT_SIDECAR_ROOT/widget"
check "fixture: a sidecar exists with the archive unmigrated" "dir dir" \
    "$(if [ -L "$A/widget" ]; then echo link; else echo dir; fi) $(if [ -L "$A/acme-widget-core" ]; then echo link; else echo dir; fi)"

# A newline in --archive-alias registered two aliases; reject it in both verbs.
run "$MV" migrate-archive --archive-alias $'x\nacme-widget-core'
check "migrate-archive rejects an alias containing a newline" 2 "$rc"
check "a rejected alias migrates nothing" "dir" "$(if [ -L "$A/acme-widget-core" ]; then echo link; else echo dir; fi)"
run "$MV" init --name widget-nl --mode owned --write sidecar --in-tree-path none --archive-alias $'x\nfoo'
check "init rejects an alias containing a newline" 2 "$rc"
check "a rejected init creates no sidecar" "" "$(ls -d "$SKILL_KIT_SIDECAR_ROOT/widget-nl" 2>/dev/null)"

# The skipped basename folder names the way out; the remote-derived one migrates.
run "$MV" migrate-archive
check "migrate-archive succeeds on an existing sidecar" 0 "$rc"
check "the remote-derived folder is migrated" "$WSC/research" "$(readlink "$A/acme-widget-core")"
contains "the skipped basename folder gets a hint naming --archive-alias" "migrate-archive --archive-alias widget" "$out"
contains "the hint names the folder it skipped" "skipped $A/widget" "$out"
check "the skipped folder is left a directory" "dir" "$(if [ -L "$A/widget" ]; then echo link; else echo dir; fi)"
run "$MV" migrate-archive --archive-alias Widget
check "following the hint migrates the basename folder" "$WSC/research" "$(readlink "$A/widget")"
check "both archive files are in the sidecar and committed" "2 " \
    "$(git -C "$WSC" ls-files research | wc -l | tr -d ' ') $(git -C "$WSC" status --porcelain)"
run "$MV" migrate-archive --archive-alias widget
check "migrate-archive is idempotent: a re-run succeeds" 0 "$rc"
lacks "a re-run moves nothing" "moved" "$out"
check "a re-run adds no commit" "" "$(git -C "$WSC" status --porcelain)"

# A migration that fails partway can be retried, and never leaves the old path
# missing. `ln` fails; the folder must still exist, then a plain retry links it.
mkdir -p "$A/widget-retry" "$tmp/shim"
printf 'r\n' > "$A/widget-retry/r.md"
printf '#!/bin/sh\nexit 1\n' > "$tmp/shim/ln"; chmod +x "$tmp/shim/ln"
out="$(cd "$MV" && PATH="$tmp/shim:$PATH" bash "$SC" migrate-archive --archive-alias widget-retry 2>&1)"; rc=$?
check "a failing ln makes migrate-archive exit 1" 1 "$rc"
check "a failing ln leaves the old path in place (never missing)" "yes" "$(if [ -d "$A/widget-retry" ] && [ ! -L "$A/widget-retry" ]; then echo yes; fi)"
check "a failing ln leaves no stray temp link" "" "$(find "$A" -maxdepth 1 -name '*sidecar-link*')"
run "$MV" migrate-archive --archive-alias widget-retry
check "the retry succeeds" 0 "$rc"
check "the retry links the folder" "$WSC/research" "$(readlink "$A/widget-retry")"
check "the retried file is in the sidecar" "yes" "$(if [ -f "$WSC/research/r.md" ]; then echo yes; fi)"
run "$tmp" migrate-archive
check "migrate-archive outside a git repository exits 1" 1 "$rc"

# -----------------------------------------------------------------------------
section "/research: Phase 3 read, Phase 5a storage, Phase 5c write"

# first_bash_after <file> <start-regex> — the first ```bash block after the
# first line matching the regex. A fence inside a list item is indented; the
# fence's own indent is stripped from every line of the block.
first_bash_after() {
    awk -v pat="$2" '$0 ~ pat { on = 1; next }
                     on && !inb && /^ *```bash$/ { ind = $0; sub(/```bash$/, "", ind); inb = 1; next }
                     inb && $0 == ind "```" { exit }
                     inb { if (index($0, ind) == 1) $0 = substr($0, length(ind) + 1); print }' "$1"
}
with_sc() { printf '%s\n' "$1" | sed -e "s|^SC=.*|SC=\"$SC\"|"; }

p5c="$(first_bash_after "$RESEARCH" '^<!-- sidecar-write: research -->$')"
p3="$(first_bash_after "$RESEARCH" '^### Phase 3: ')"
p5a="$(first_bash_after "$RESEARCH" '^#### Phase 5a: ')"
# /write-a-prd's archive-mode reader. Its block sits in a numbered list.
prd_read="$(first_bash_after "$repo_root/write-a-prd/SKILL.md" '^ *<!-- sidecar-read: research -->$')"
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
# /write-a-prd's reader on the same sidecar: the found branch lists what
# Phase 5c just committed, and never falls back to the pre-sidecar archive.
# The archive root is an empty scratch dir: the migrated fixture's old archive
# folder is a symlink to the sidecar's research/, so it would hold the same
# entry and a reader that listed it instead would pass.
if [ -n "$prd_read" ]; then
    EMPTYARCH="$tmp/emptyarch"; mkdir -p "$EMPTYARCH"
    out="$(cd "$MIG" && SKILL_KIT_RESEARCH_ARCHIVE="$EMPTYARCH" bash -c "$(with_sc "$prd_read")" 2>&1)"; rc=$?
    check "the /write-a-prd read block on a sidecar hit runs cleanly" 0 "$rc"
    contains "on a hit /write-a-prd lists the entry Phase 5c wrote" "search-index-2026-10-17.md" "$out"
    lacks "on a hit /write-a-prd does not read the pre-sidecar archive" "pre-sidecar archive" "$out"
fi

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

# /write-a-prd's archive-mode reader, run against what Phase 5c just wrote
# (#419). The reader used to be prose and its own remote-derived slug, so on a
# case-sensitive filesystem it listed a directory the writer never made. The
# second fixture's remote is mixed-case and dotted, the shape #419 measured.
if [ -z "$prd_read" ]; then
    bad "write-a-prd/SKILL.md carries the archive-mode read block" "no bash block after <!-- sidecar-read: research -->"
else
    ok "write-a-prd/SKILL.md carries the archive-mode read block"
    out="$(cd "$MISSREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$MISSARCH" bash -c "$(with_sc "$prd_read")" 2>&1)"; rc=$?
    check "the /write-a-prd read block on a miss runs cleanly" 0 "$rc"
    contains "on a miss /write-a-prd lists the entry Phase 5c wrote" "miss-case-2026-10-17.md" "$out"
    contains "on a miss /write-a-prd shows the user the init command" \
        "SIDECAR MISS: run: bash $SC init --name foo-bar-baz" "$out"
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
fi

# A sidecar exists but `path research` refuses (research is a file, so the
# directory cannot be created). That is not a SIDECAR MISS: both blocks must
# show the resolver's refusal and exit 1, and nothing may land in the
# pre-sidecar archive. The blocks used to fall back on any failure.
REFREPO="$tmp/refrepo"
mkrepo "$REFREPO"
SAVED_ROOT="$SKILL_KIT_SIDECAR_ROOT"
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars-refuse"
run "$REFREPO" init --name ref-sc --mode guest --write sidecar --in-tree-path none
check "refusal fixture: the sidecar is created" 0 "$rc"
rm -rf "$SKILL_KIT_SIDECAR_ROOT/ref-sc/research"
printf 'not a directory\n' > "$SKILL_KIT_SIDECAR_ROOT/ref-sc/research"
REFARCH="$tmp/refarch"
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|refused|g' -e 's|<YYYY-MM-DD>|2026-10-19|g')"
out="$(cd "$REFREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$REFARCH" bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block exits 1 when a sidecar exists but path research refuses" 1 "$rc"
lacks "the refusal is not reported as a SIDECAR MISS" "SIDECAR MISS" "$out"
check "a refused Phase 5c writes nothing to the pre-sidecar archive" "" "$(find "$REFARCH" -type f 2>/dev/null)"
if [ -n "$prd_read" ]; then
    out="$(cd "$REFREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$REFARCH" bash -c "$(with_sc "$prd_read")" 2>&1)"; rc=$?
    check "the /write-a-prd read block exits 1 when path research refuses" 1 "$rc"
    lacks "/write-a-prd does not list the pre-sidecar archive on a refusal" "pre-sidecar archive" "$out"
fi
export SKILL_KIT_SIDECAR_ROOT="$SAVED_ROOT"

# #420: the resolver's warnings reach the user on the hit branch too. Two
# sidecars claim this checkout's keys; the first is used and ALIAS COLLISION
# is printed, which the fallback used to discard.
COLREPO="$tmp/colrepo"
mkrepo "$COLREPO"
SAVED_ROOT="$SKILL_KIT_SIDECAR_ROOT"
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars-collide"
run "$COLREPO" init --name col-a --mode guest --write sidecar --in-tree-path none
mkdir -p "$SKILL_KIT_SIDECAR_ROOT/col-b"
cp "$SKILL_KIT_SIDECAR_ROOT/col-a/sidecar.json" "$SKILL_KIT_SIDECAR_ROOT/col-b/sidecar.json"
# commit and require resolve too and would print the same warning, which would
# mask a block that dropped it; this wrapper silences every verb but path.
# shellcheck disable=SC2016 # the wrapper body is meant to be literal
printf '#!/usr/bin/env bash\ncase "$1" in path) exec bash "%s" "$@" ;; *) exec bash "%s" "$@" 2>/dev/null ;; esac\n' "$SC" "$SC" > "$tmp/path-only-stderr.sh"
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|collide|g' -e 's|<YYYY-MM-DD>|2026-10-20|g' -e "s|^SC=.*|SC=\"$tmp/path-only-stderr.sh\"|")"
out="$(cd "$COLREPO" && bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block still writes on an alias collision" 0 "$rc"
contains "the Phase 5c block prints ALIAS COLLISION on the hit branch" "ALIAS COLLISION" "$out"
check "the colliding entry went to the first sidecar" "yes" "$(if [ -f "$SKILL_KIT_SIDECAR_ROOT/col-a/research/collide-2026-10-20.md" ]; then echo yes; fi)"
export SKILL_KIT_SIDECAR_ROOT="$SAVED_ROOT"

# A checkout whose name archive-dir refuses (a leading dot) cannot be filed in
# the pre-sidecar archive; the block must say the entry was not written.
mkdir -p "$tmp/slug"
SLUGREPO="$tmp/slug/.hidden"
mkrepo "$SLUGREPO"
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|slugless|g' -e 's|<YYYY-MM-DD>|2026-10-20|g')"
out="$(cd "$SLUGREPO" && SKILL_KIT_RESEARCH_ARCHIVE="$tmp/slugarch" bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block exits 1 when archive-dir rejects the name" 1 "$rc"
contains "a rejected slug says the entry was not written" "research entry NOT written" "$out"
check "a rejected slug writes nothing" "" "$(find "$tmp/slugarch" -type f 2>/dev/null)"

# The default archive root (#470). Every run above exports
# SKILL_KIT_RESEARCH_ARCHIVE, so the ${...:-default} branch never ran, and a
# copy of the default in a skill block could drift with the suite green. Here
# the var is unset and HOME is a scratch directory, so the real
# ~/.claude/research is never touched; then a census holds the default to
# the one file that defines it.
SCRATCH_HOME="$tmp/home"
mkdir -p "$SCRATCH_HOME"
DEFAULT_DIR="$SCRATCH_HOME/.claude/""research/foo-bar-baz"
out="$(cd "$MISSREPO" && env -u SKILL_KIT_RESEARCH_ARCHIVE HOME="$SCRATCH_HOME" bash "$SC" archive-dir 2>&1)"; rc=$?
check "archive-dir with the var unset prints the default root plus the suggested name" "0 $DEFAULT_DIR" "$rc $out"
out="$(cd "$MISSREPO" && bash "$SC" archive-dir 2>&1)"
check "archive-dir honors SKILL_KIT_RESEARCH_ARCHIVE" "$SKILL_KIT_RESEARCH_ARCHIVE/foo-bar-baz" "$out"
out="$(cd "$tmp" && bash "$SC" archive-dir 2>&1)"; rc=$?
check "archive-dir outside a git repository exits 1" 1 "$rc"
script="$(with_sc "$p5c" | sed -e 's|<feature-slug>|default-root|g' -e 's|<YYYY-MM-DD>|2026-10-18|g')"
out="$(cd "$MISSREPO" && env -u SKILL_KIT_RESEARCH_ARCHIVE HOME="$SCRATCH_HOME" bash -c "$script" 2>&1)"; rc=$?
check "the Phase 5c block with the var unset runs cleanly" 0 "$rc"
contains "with the var unset Phase 5c still shows the miss line" "SIDECAR MISS: run: bash $SC init --name foo-bar-baz" "$out"
check "with the var unset Phase 5c writes under the default root" "yes" \
    "$(if [ -f "$DEFAULT_DIR/default-root-2026-10-18.md" ]; then echo yes; fi)"
if [ -n "$prd_read" ]; then
    out="$(cd "$MISSREPO" && env -u SKILL_KIT_RESEARCH_ARCHIVE HOME="$SCRATCH_HOME" bash -c "$(with_sc "$prd_read")" 2>&1)"; rc=$?
    check "the /write-a-prd read block with the var unset runs cleanly" 0 "$rc"
    contains "with the var unset /write-a-prd names the default root" "pre-sidecar archive: $DEFAULT_DIR" "$out"
    contains "with the var unset /write-a-prd lists the entry Phase 5c wrote" "default-root-2026-10-18.md" "$out"
fi
# Census: the default root, however it is spelled, is not restated outside
# sidecar.sh. The token is the path itself, not one spelling of the
# ${...:-default} expansion, so $HOME vs ${HOME}, a quoted copy, or an inlined
# literal all match. Exempt: the definition (init-pipeline/scripts/sidecar.sh)
# and the bundled copies the manifest lists, by exact path and never by file
# name (a stray docs/sidecar.sh must still be caught), CHANGELOG.md and docs/solutions/ (history and lessons that name the
# path as prose), and comment-only lines. The token is assembled so this file
# does not match itself.
root_tok=".claude""/research"
sc_exempt="$(awk '$1 == "init-pipeline/scripts/sidecar.sh" { print "^" $2 "/references/sidecar\\.sh:" }' \
    "$repo_root/scripts/skill-references.manifest"; echo '^init-pipeline/scripts/sidecar\.sh:')"
strays="$(git -C "$repo_root" grep -nIF -- "$root_tok" \
    | grep -v -e "$sc_exempt" -e '^CHANGELOG\.md:' -e '^docs/solutions/' \
    | grep -v -e '^[^:]*:[0-9]*:[[:space:]]*#')"
check "no tracked file outside the exemptions mentions the default archive root path" "" "$strays"
# The census exempts sidecar.sh, so a second ${...:-default} inside it (the
# #470 shape, once in migrate_archive) would pass. The env var's name cannot
# drift the way the path can: it is read on exactly one code line.
check "sidecar.sh reads SKILL_KIT_RESEARCH_ARCHIVE on exactly one code line" 1 \
    "$(grep -v '^[[:space:]]*#' "$SC" | grep -c 'SKILL_KIT_RESEARCH_ARCHIVE')"
# Both skill blocks must get the root from the resolver, not from the env var.
for pair in "Phase 5c:$p5c" "/write-a-prd read:$prd_read"; do
    contains "the ${pair%%:*} block calls archive-dir" "archive-dir" "${pair#*:}"
    lacks "the ${pair%%:*} block does not name SKILL_KIT_RESEARCH_ARCHIVE" "SKILL_KIT_RESEARCH_ARCHIVE" "${pair#*:}"
done

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
# #420: an existing docs/solutions is read even when in_tree_path is none,
# because a /excavate PR commits there whatever in_tree_path says.
contains "with in_tree_path none, Phase 3 still reads an existing docs/solutions" "docs/solutions/planted.md" "$out"
dirs="$(cd "$MIG" && bash "$SC" solutions-dirs 2>/dev/null)"
check "solutions-dirs with in_tree_path none: the sidecar store, then the existing docs/solutions" \
    "$SOLS
docs/solutions" "$dirs"
jq '.solutions.in_tree_path = "docs/adr"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
dirs="$(cd "$MIG" && bash "$SC" solutions-dirs 2>/dev/null)"
check "solutions-dirs lists the sidecar store, in_tree_path, then docs/solutions" "$SOLS
docs/adr
docs/solutions" "$dirs"
jq '.solutions.in_tree_path = "docs/solutions"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
dirs="$(cd "$MIG" && bash "$SC" solutions-dirs 2>/dev/null)"
check "solutions-dirs does not list docs/solutions twice" "$SOLS
docs/solutions" "$dirs"
git -C "$MSC" checkout -q -- sidecar.json
rm -f "$MIG/docs/solutions/planted.md"; rmdir "$MIG/docs/solutions"
jq '.solutions.in_tree_path = "docs/adr"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
dirs="$(cd "$MIG" && bash "$SC" solutions-dirs 2>/dev/null)"
check "with no docs/solutions in the tree, solutions-dirs omits it" "$SOLS
docs/adr" "$dirs"
git -C "$MSC" checkout -q -- sidecar.json
# No sidecar: the default store, named whether or not it exists; a SIDECAR MISS
# is not an error here and prints nothing on stderr.
NOSD="$tmp/mig/nosolutions"
mkrepo "$NOSD"
dirs="$(cd "$NOSD" && bash "$SC" solutions-dirs 2>"$tmp/sd.err")"; rc=$?
check "solutions-dirs with no sidecar exits 0 and names docs/solutions" "0 docs/solutions" "$rc $dirs"
check "solutions-dirs with no sidecar stays quiet on a SIDECAR MISS" "" "$(cat "$tmp/sd.err")"
dirs="$(cd "$tmp" && bash "$SC" solutions-dirs 2>&1)"; rc=$?
check "solutions-dirs outside a git repository still names the default store" "0 docs/solutions" "$rc $(printf '%s' "$dirs" | tail -n 1)"
# Policy lives in one place: /research and /compound both ask the verb, and the
# compound block runs as written.
c_read="$(first_bash_after "$COMPOUND" '^Search every place a lesson can live, not just')"
# #503 review finding 1: /execute, /write-a-prd, /help and /pre-merge kept a
# copy of the old policy that skipped docs/solutions when in_tree_path is none.
# shellcheck disable=SC2016  # backticks and $SC below are literal patterns
e_read="$(first_bash_after "$repo_root/execute/SKILL.md" '^Consult `docs/solutions/` and the sidecar for relevant past solutions')"
w_read="$(first_bash_after "$repo_root/write-a-prd/SKILL.md" '^\*\*Past solutions\*\*')"
for pair in "research Phase 3:$p3" "compound overlap:$c_read" "execute past-solutions:$e_read" "write-a-prd past-solutions:$w_read"; do
    contains "the ${pair%%:*} block calls solutions-dirs" "solutions-dirs" "${pair#*:}"
    lacks "the ${pair%%:*} block derives no path itself" "path solutions" "${pair#*:}"
done
mkdir -p "$MIG/docs/solutions"
printf 'needle again\n' > "$MIG/docs/solutions/planted2.md"
out="$(cd "$MIG" && bash -c "$(with_sc "$c_read" | sed -e 's|^KW=.*|KW="needle"|')" 2>/dev/null)"; rc=$?
check "the compound overlap block runs cleanly" 0 "$rc"
contains "the compound overlap block lists the sidecar match" "$SOLS/perf/a.md" "$out"
contains "the compound overlap block lists the docs/solutions match" "docs/solutions/planted2.md" "$out"
jq '.solutions.in_tree_path = "none"' "$MSC/sidecar.json" > "$MSC/sj" && mv "$MSC/sj" "$MSC/sidecar.json"
for pair in "execute past-solutions:$e_read" "write-a-prd past-solutions:$w_read"; do
    out="$(cd "$MIG" && bash -c "$(with_sc "${pair#*:}" | sed -e 's|^KW=.*|KW="needle"|')" 2>/dev/null)"; rc=$?
    check "the ${pair%%:*} block runs cleanly" 0 "$rc"
    contains "with in_tree_path none, the ${pair%%:*} block lists the sidecar match" "$SOLS/perf/a.md" "$out"
    contains "with in_tree_path none, the ${pair%%:*} block still reads an existing docs/solutions" "docs/solutions/planted2.md" "$out"
done
git -C "$MSC" checkout -q -- sidecar.json
pm_text="$(cat "$repo_root/pre-merge/review-checklist.md")"
# shellcheck disable=SC2016  # literal patterns
contains "pre-merge's docs/solutions dimension asks solutions-dirs" 'bash "$SC" solutions-dirs' "$pm_text"
# shellcheck disable=SC2016  # literal pattern
lacks "pre-merge restates no in_tree_path-none skip" 'unless it is `none`' "$pm_text"
cc_text="$(cat "$repo_root/correct-course/SKILL.md")"
# shellcheck disable=SC2016  # literal patterns
contains "correct-course's stale-artifact check asks solutions-dirs" 'bash "$SC" solutions-dirs' "$cc_text"
# shellcheck disable=SC2016  # literal pattern
lacks "correct-course restates no in_tree_path-none skip" '(unless `none`)' "$cc_text"
# shellcheck disable=SC2016  # literal pattern
lacks "correct-course reads no solutions.in_tree_path itself" 'config get solutions.in_tree_path' "$cc_text"
rm -f "$MIG/docs/solutions/planted2.md"; rmdir "$MIG/docs/solutions"

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
    script="$(with_sc "$req" | sed -e "s|<cited dossier path>|$DOSSIER|")"
    contains "the dossier require block sets SC itself (#430)" 'SC="' "$req"
    out="$(cd "$MIG" && bash -c "$script" 2>&1)"
    contains "the skill's require block surfaces the MISSING line" \
        "MISSING: $DOSSIER (referenced by /research Phase 3)" "$out"
    contains "the skill's require block signals the miss" "dossier missing" "$out"
    # The HIT path: the same block with the dossier present prints where it
    # found it and does not signal a miss.
    printf 'dossier\n' > "$DOSSIER"
    out="$(cd "$MIG" && bash -c "$script" 2>&1)"
    contains "on a hit the skill's require block prints the resolved dossier path" "$DOSSIER" "$out"
    lacks "on a hit the skill's require block reports no miss" "dossier missing" "$out"
    lacks "on a hit the skill's require block prints no MISSING line" "MISSING:" "$out"
    rm -f "$DOSSIER"
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
# A stub resolver in a fake skill directory records every call, so a block whose
# SC= points at a missing file is visible even when the block hides stderr and the
# exit code (`2>/dev/null) || SIDE=""`, #430). The stub exits 0 on every verb.
STUBDIR="$tmp/stubskill"; STUBLOG="$tmp/stub.log"; STUBSTORE="$tmp/stubstore"
mkdir -p "$STUBDIR/references" "$STUBSTORE"
cat > "$STUBDIR/references/sidecar.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUBLOG"
case "${1:-}" in
    path|archive-dir) mkdir -p "$STUBSTORE/${2:-x}"; printf '%s\n' "$STUBSTORE/${2:-x}" ;;
    config) printf 'none\n' ;;
esac
exit 0
STUB
export STUBLOG STUBSTORE
for entry in execute:execute/SKILL.md:3 write-a-prd:write-a-prd/SKILL.md:2 pre-merge:pre-merge/review-checklist.md:1 research:research/SKILL.md:4 compound:compound/SKILL.md:3; do
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
        # SC= as a whole word: SIDE_SC= or MYSC= is a different variable (#430).
        if grep -Eq '(^|[^A-Za-z0-9_])SC=' "$f"; then ok "$label defines SC itself"; else bad "$label defines SC itself" "uses \$SC with no SC= in the block"; fi
        : > "$STUBLOG"
        stubscript="$(sed -e "s|<this skill's directory>|$STUBDIR|g" -e 's|<[A-Za-z][^<>]*>|x|g' "$f")"
        (cd "$SCREPO" && env -u SC bash -c "$stubscript" >/dev/null 2>&1 </dev/null)
        if [ -s "$STUBLOG" ]; then ok "$label reaches its resolver (stub saw a call)"; else bad "$label reaches its resolver" "the stub resolver was never called: SC is unset, misnamed, or points at the wrong file"; fi
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

# #503 review finding 1: with in_tree_path none, an /excavate PR's docs/solutions
# entries are still in-tree entries, so row 10 does not re-fire.
mkdir -p "$HR/docs/solutions/history"
printf 'excavated\n' > "$HR/docs/solutions/history/a.md"
hrun "$HR"
contains "with in_tree_path none, an existing docs/solutions is counted (row 10 does not fire)" "in-tree (docs/solutions)=1" "$hout"
rm -rf "$HR/docs/solutions"

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

# /correct-course's no-PRD research lookup points at /write-a-prd's whole
# "Research document" lookup (#495); the pointer must name text that exists.
cc_ptr="$(grep -c 'write-a-prd` § 4.s "Research document" lookup' "$repo_root/correct-course/SKILL.md")"
check "correct-course points at write-a-prd's Research document lookup" "1" "$cc_ptr"
contains "write-a-prd carries the Research document lookup correct-course points at" '**Research document** — Find the most recent research artifact' "$(cat "$repo_root/write-a-prd/SKILL.md")"

# -----------------------------------------------------------------------------
section "related projects: relate and related-solutions-dirs"

# A lesson about something several repos share is written to one repo's
# sidecar, and solutions-dirs only ever resolves the current one. relate links
# another project by identity key; related-solutions-dirs reads it one hop,
# read-only, and solutions-dirs (which /compound's overlap check reads) stays
# as it was.
RA="$tmp/rel/a"; RB="$tmp/rel/b"; RC="$tmp/rel/c"
for d in "$RA" "$RB" "$RC"; do
    mkrepo "$d"
    (cd "$d" && bash "$SC" init --name "rel-$(basename "$d")" --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1)
done
SA="$SKILL_KIT_SIDECAR_ROOT/rel-a"; SB="$SKILL_KIT_SIDECAR_ROOT/rel-b"; SCC="$SKILL_KIT_SIDECAR_ROOT/rel-c"
mkdir -p "$SB/solutions/integration" "$SCC/solutions/integration"
printf 'needle from b\n' > "$SB/solutions/integration/gateway.md"
printf 'needle from c\n' > "$SCC/solutions/integration/bus.md"
a_dirs_before="$(cd "$RA" && bash "$SC" solutions-dirs 2>/dev/null)"
# B gains a remote after init, so a resolve run in B would have a new alias to
# commit; without it the "relate wrote nothing into B" check below cannot fail.
# The URL is never fetched.
git -C "$RB" remote add origin git@github.com:acme/rel-b.git
# init lists root: first, so "prefer root:" and "take the first key" agree.
# Put a non-root key first so only the preference picks root:.
jq '.keys = (["name:rel-b-first"] + .keys)' "$SB/sidecar.json" > "$SB/sj" && mv "$SB/sj" "$SB/sidecar.json"
git -C "$SB" commit -q -am "test: non-root key first"
check "fixture: B's first key is not root:" "name:rel-b-first" "$(jq -r '.keys[0]' "$SB/sidecar.json")"
b_head_before="$(git -C "$SB" rev-parse HEAD)"

runo "$RA" related-solutions-dirs
check "with nothing related, related-solutions-dirs prints nothing and exits 0" "0 " "$rc $out"

runo "$RA" relate "$RB"
check "relate exits 0" 0 "$rc"
b_root="$(jq -r '.keys[] | select(startswith("root:"))' "$SB/sidecar.json")"
check "relate prints the key it stored" "$b_root" "$out"
check "relate stores the other project's root: key, not its directory name" \
    "[\"$b_root\"]" "$(jq -c '.solutions.related' "$SA/sidecar.json")"
check "relate commits sidecar.json" "" "$(git -C "$SA" status --porcelain)"
runo "$RA" relate "$RB"
check "relating the same project twice stores it once" 1 "$(jq '.solutions.related | length' "$SA/sidecar.json")"
run "$RA" relate "$RA"
check "relate refuses the project's own checkout" 1 "$rc"
run "$RA" relate "$tmp/rel/nowhere"
check "relate refuses a path that is not a checkout" 1 "$rc"
check "a refused relate leaves sidecar.json as it was" 1 "$(jq '.solutions.related | length' "$SA/sidecar.json")"
check "relate made no commit in the related project's sidecar" "$b_head_before" "$(git -C "$SB" rev-parse HEAD)"

# B relates C; reading from A must not follow B's link.
runo "$RB" relate "$RC"
runo "$RA" related-solutions-dirs
check "related-solutions-dirs prints the related project's solutions dir, one hop only" "$SB/solutions" "$out"
check "solutions-dirs is unchanged by a related project" "$a_dirs_before" "$(cd "$RA" && bash "$SC" solutions-dirs 2>/dev/null)"

# A key that matches no sidecar (the project was removed) is skipped, not refused.
jq '.solutions.related += ["root:0000000000000000000000000000000000000000"]' "$SA/sidecar.json" > "$SA/sj" && mv "$SA/sj" "$SA/sidecar.json"
out="$(cd "$RA" && bash "$SC" related-solutions-dirs 2>"$tmp/rel.err")"; rc=$?
check "a dangling related key still exits 0 and prints the live one" "0 $SB/solutions" "$rc $out"
contains "a dangling related key is named on stderr" "matches no sidecar" "$(cat "$tmp/rel.err")"
git -C "$SA" checkout -q -- sidecar.json

# A related project with no solutions/ yet is skipped, and not created.
rm -rf "$SB/solutions"
runo "$RA" related-solutions-dirs
check "a related project with no solutions dir prints nothing" "0 " "$rc $out"
check "related-solutions-dirs does not create the related solutions dir" "no" "$([ -e "$SB/solutions" ] && echo yes || echo no)"
mkdir -p "$SB/solutions/integration"
printf 'needle from b\n' > "$SB/solutions/integration/gateway.md"

# No sidecar here: nothing related, and no SIDECAR MISS noise for a reader.
out="$(cd "$NOSD" && bash "$SC" related-solutions-dirs 2>"$tmp/rel.err")"; rc=$?
check "related-solutions-dirs with no sidecar exits 0 and prints nothing" "0 " "$rc $out"
check "related-solutions-dirs with no sidecar stays quiet on a SIDECAR MISS" "" "$(cat "$tmp/rel.err")"

# The three planning readers search related projects and label the hits;
# /compound's overlap check and /help do not, so a sibling's entry can neither
# suppress a local one nor count toward defect clustering.
for pair in "research Phase 3:$p3" "execute past-solutions:$e_read" "write-a-prd past-solutions:$w_read"; do
    # shellcheck disable=SC2016  # literal pattern
    contains "the ${pair%%:*} block calls related-solutions-dirs" 'bash "$SC" related-solutions-dirs' "${pair#*:}"
    out="$(cd "$RA" && bash -c "$(with_sc "${pair#*:}" | sed -e 's|^KW=.*|KW="needle"|')" 2>/dev/null)"; rc=$?
    check "the ${pair%%:*} block runs cleanly with a related project" 0 "$rc"
    contains "the ${pair%%:*} block labels the related hit" "related project, unverified here: $SB/solutions/integration/gateway.md" "$out"
    lacks "the ${pair%%:*} block does not follow the related project's own link" "bus.md" "$out"
done
lacks "the compound overlap block does not read related projects" "related-solutions-dirs" "$c_read"
lacks "compound/SKILL.md does not read related projects" "related-solutions-dirs" "$(cat "$COMPOUND")"
lacks "help/SKILL.md does not read related projects" "related-solutions-dirs" "$(cat "$repo_root/help/SKILL.md")"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
