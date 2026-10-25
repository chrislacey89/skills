#!/usr/bin/env bash
# test-state-backend.sh — runs the real init-pipeline/scripts/sidecar.sh
# `backend` and `stamp` verbs against scratch repos (#407, #521).
#
# THE DRIFT CLASS. `backend <artifact>` is the one routing rule every skill
# asks before it writes pack state, and docs/state-backend.md is where that
# rule is written down. A rule stated in a doc and implemented in a script
# drifts the moment one is edited without the other, and the failure is
# silent in the worst direction: a guest repo routed to `github` gets pack
# text written into a client's PR body, and an owned repo routed to `sidecar`
# loses a stamp nobody reads. So the truth table below is RUN, across
# owned/guest × forge kinds × no sidecar, not restated.
#
# THE STAMP CONTRACT. `stamp write` is the sidecar twin of /pre-merge Phase 4's
# PR-body marker, and /closeout Step 2 compares it with the branch head by
# string equality. So `stamp read` must return exactly the 40-hex SHA written,
# nothing for another branch, and nothing (exit 0) for a stamp it cannot
# trust; a short or malformed value would compare unequal forever, which is a
# gate that cries wolf. Branch names are not safe filenames (`feat/x`,
# unicode), so the file is named by a reversible slug and the reader matches
# on the JSON `branch` field.
#
# THE FOOTPRINT. Every verb must leave the project's `git status --porcelain`
# empty: a stamp is state about the project, never state in it.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config, so a hook's GIT_DIR or the runner's identity cannot
# leak in (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md).

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
DOC="$repo_root/docs/state-backend.md"
[ -f "$SC" ] || { printf 'FATAL %s is missing\n' "$SC"; exit 1; }
[ -f "$DOC" ] || { printf 'FATAL %s is missing\n' "$DOC"; exit 1; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
# chmod first: an arm that dies mid-way leaves a mode-000 fixture rm cannot enter.
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Backend Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

# runo <dir> <args...> — run sidecar.sh from <dir>; stdout in $out, exit in $rc,
# stderr in $err.
runo() {
    local d="$1"; shift
    out="$(cd "$d" && bash "$SC" "$@" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}

n=0
# mkproj <remote-url|none> — a scratch project with its own root commit, in $P.
# Sets a global rather than printing, so the counter survives: a $(mkproj)
# subshell would hand every caller the same path.
mkproj() {
    n=$((n + 1))
    P="$tmp/proj$n"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
    [ "$1" = none ] || git -C "$P" remote add origin "$1"
}

# clean <label> <project> — the project tree and index are untouched.
clean() { check "$1" "" "$(git -C "$2" status --porcelain)"; }

# -----------------------------------------------------------------------------
section "backend: no sidecar resolves"

mkproj https://github.com/acme/widgets.git
for a in prds slices stamp; do
    runo "$P" backend "$a"
    check "no sidecar: backend $a prints github" github "$out"
    check "no sidecar: backend $a exits 0" 0 "$rc"
done
check "no sidecar: the SIDECAR MISS line is not echoed (a miss is the github answer, not an error)" "" "$err"
clean "no sidecar: backend leaves the project clean" "$P"

runo "$tmp" backend stamp
check "outside a git repository, backend exits nonzero rather than guessing" 1 "$rc"
runo "$P" backend milestones
check "an unknown artifact is a usage error" 2 "$rc"
runo "$P" backend
check "a missing artifact is a usage error" 2 "$rc"

# -----------------------------------------------------------------------------
section "backend: jq absent is a refusal, never the github default"

# A guest sidecar on a github remote answers `sidecar` (the control). With a
# PATH that holds every real binary except jq, the same repo must be refused:
# without jq no sidecar matches, and the miss would otherwise read as `github`.
nojq="$tmp/nojq-bin"; mkdir -p "$nojq"
for d in /opt/homebrew/bin /usr/bin /bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        b="${f##*/}"; [ "$b" = jq ] && continue
        [ -e "$nojq/$b" ] || ln -s "$f" "$nojq/$b"
    done
done
mkproj https://github.com/acme/nojq.git
runo "$P" init --name nojq --mode guest --write sidecar --in-tree-path none --no-migrate-archive
[ "$rc" -eq 0 ] || bad "init guest for the no-jq arm" "$err"
for a in prds slices stamp; do
    runo "$P" backend "$a"
    check "jq present (control): guest backend $a → sidecar" sidecar "$out"
    saved_path="$PATH"
    PATH="$nojq" runo "$P" backend "$a"
    PATH="$saved_path"
    check "jq absent: backend $a exits 1" 1 "$rc"
    check "jq absent: backend $a prints nothing on stdout (not github)" "" "$out"
    case "$err" in *jq*) ok "jq absent: backend $a names jq on stderr" ;; *) bad "jq absent: backend $a names jq on stderr" "got [$err]" ;; esac
done
if PATH="$nojq" command -v jq >/dev/null 2>&1; then bad "the jq-less PATH really has no jq" "jq found"; else ok "the jq-less PATH really has no jq"; fi
clean "jq absent: backend leaves the project clean" "$P"

# -----------------------------------------------------------------------------
section "backend: an unreadable sidecar.json is a refusal, never the github default"

# jq is present but cannot read the sidecar: a corrupt file, or a jq that errors.
# Either must not read as "no sidecar", whose answer is `github`.
mkproj https://github.com/acme/corrupt.git
runo "$P" init --name corrupt --mode guest --write sidecar --in-tree-path none --no-migrate-archive
[ "$rc" -eq 0 ] || bad "init guest for the unreadable-sidecar arms" "$err"
badjq="$tmp/badjq-bin"; mkdir -p "$badjq"
for d in /opt/homebrew/bin /usr/bin /bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        b="${f##*/}"; [ "$b" = jq ] && continue
        [ -e "$badjq/$b" ] || ln -s "$f" "$badjq/$b"
    done
done
printf '#!/bin/sh\nexit 3\n' > "$badjq/jq"; chmod +x "$badjq/jq"
cp "$SKILL_KIT_SIDECAR_ROOT/corrupt/sidecar.json" "$tmp/corrupt-good.json"
for a in prds slices stamp; do
    runo "$P" backend "$a"
    check "well-formed sidecar (control): guest backend $a → sidecar" sidecar "$out"
    saved_path="$PATH"
    PATH="$badjq" runo "$P" backend "$a"
    PATH="$saved_path"
    check "jq exits 3: backend $a exits nonzero" 1 "$rc"
    check "jq exits 3: backend $a prints nothing on stdout (not github)" "" "$out"
    printf '{"keys": [' > "$SKILL_KIT_SIDECAR_ROOT/corrupt/sidecar.json"
    runo "$P" backend "$a"
    cp "$tmp/corrupt-good.json" "$SKILL_KIT_SIDECAR_ROOT/corrupt/sidecar.json"
    check "corrupt sidecar.json: backend $a exits nonzero" 1 "$rc"
    check "corrupt sidecar.json: backend $a prints nothing on stdout (not github)" "" "$out"
    case "$err" in *sidecar.json*) ok "corrupt sidecar.json: backend $a names the file on stderr" ;; *) bad "corrupt sidecar.json: backend $a names the file on stderr" "got [$err]" ;; esac
done
runo "$P" resolve
check "corrupt sidecar.json restored: resolve succeeds again" 0 "$rc"

# A file jq cannot open (mode 000, or owned by another user) must be refused
# like a corrupt one. `owners_of` guards with `[ -f ]`, so the file reaches jq,
# which fails; a guard of `[ -r ]` would skip it as "not found", and the miss
# would answer `github` (#530: a /fix-findings breaker made exactly that edit
# and both suites stayed green). uid 0 reads mode-000 files, so root skips.
if [ "$(id -u)" -eq 0 ]; then
    ok "unreadable sidecar.json: skipped under root, which reads mode-000 files"
else
    chmod 000 "$SKILL_KIT_SIDECAR_ROOT/corrupt/sidecar.json"
    for a in prds slices stamp; do
        runo "$P" backend "$a"
        check "unreadable sidecar.json: backend $a exits 1" 1 "$rc"
        check "unreadable sidecar.json: backend $a prints nothing on stdout (not github)" "" "$out"
        case "$err" in *corrupt/sidecar.json*) ok "unreadable sidecar.json: backend $a names the file on stderr" ;; *) bad "unreadable sidecar.json: backend $a names the file on stderr" "got [$err]" ;; esac
    done
    chmod 644 "$SKILL_KIT_SIDECAR_ROOT/corrupt/sidecar.json"
    runo "$P" backend stamp
    check "unreadable sidecar.json restored: backend stamp answers sidecar again" sidecar "$out"
fi

# -----------------------------------------------------------------------------
section "backend: a corrupt sidecar refuses only the keys no readable sidecar claims"

# #530's scope decision. A corrupt sidecar.json cannot be ruled out as a key's
# owner without parsing it, so a repo that no readable sidecar claims is still
# refused: it might be the corrupt one's, and `github` there could be a guest's
# PR. A repo a readable sidecar does claim resolves to it, and the corrupt file
# is named on stderr; before #530 one corrupt file refused every repo.
# Own root, so the stray cannot leak into the sections below.
scope_root="$tmp/scope-sidecars"
mkproj https://github.com/acme/claimed.git
claimed="$P"
SKILL_KIT_SIDECAR_ROOT="$scope_root" runo "$claimed" init --name claimed --mode guest --write sidecar --in-tree-path none --no-migrate-archive
[ "$rc" -eq 0 ] || bad "init guest for the scope arms" "$err"
mkproj https://github.com/acme/unclaimed.git
unclaimed="$P"
mkdir -p "$scope_root/stray"
printf '{"keys": [' > "$scope_root/stray/sidecar.json"
SKILL_KIT_SIDECAR_ROOT="$scope_root" runo "$claimed" backend stamp
check "claimed repo beside a corrupt sidecar: backend stamp answers sidecar" sidecar "$out"
check "claimed repo beside a corrupt sidecar: backend stamp exits 0" 0 "$rc"
case "$err" in *stray/sidecar.json*) ok "claimed repo beside a corrupt sidecar: the corrupt file is named on stderr" ;; *) bad "claimed repo beside a corrupt sidecar: the corrupt file is named on stderr" "got [$err]" ;; esac
SKILL_KIT_SIDECAR_ROOT="$scope_root" runo "$claimed" resolve
check "claimed repo beside a corrupt sidecar: resolve prints its own sidecar" "$scope_root/claimed" "$out"
# A new remote is an alias resolve would add; the corrupt file might claim it,
# so it is skipped, not refused, and the resolve keeps its hit.
git -C "$claimed" remote add mirror https://github.com/acme/claimed-mirror.git
SKILL_KIT_SIDECAR_ROOT="$scope_root" runo "$claimed" resolve
check "new alias beside a corrupt sidecar: resolve still exits 0" 0 "$rc"
check "new alias beside a corrupt sidecar: the alias is not added" "" \
    "$(jq -r '.keys[] | select(. == "remote:github.com/acme/claimed-mirror")' "$scope_root/claimed/sidecar.json")"
SKILL_KIT_SIDECAR_ROOT="$scope_root" runo "$unclaimed" backend stamp
check "unclaimed repo beside a corrupt sidecar: backend stamp exits 1" 1 "$rc"
check "unclaimed repo beside a corrupt sidecar: backend stamp prints nothing (not github)" "" "$out"
case "$err" in *stray/sidecar.json*) ok "unclaimed repo beside a corrupt sidecar: the corrupt file is named on stderr" ;; *) bad "unclaimed repo beside a corrupt sidecar: the corrupt file is named on stderr" "got [$err]" ;; esac
SKILL_KIT_SIDECAR_ROOT="$scope_root" runo "$unclaimed" init --name unclaimed --mode owned --write sidecar --in-tree-path none --no-migrate-archive
check "unclaimed repo beside a corrupt sidecar: init refuses rather than risk a second owner" 1 "$rc"
clean "scope arms leave the claimed project clean" "$claimed"
clean "scope arms leave the unclaimed project clean" "$unclaimed"

# -----------------------------------------------------------------------------
section "backend: a sidecar directory the scan cannot enter is a refusal, never the github default"

# #542. The scan used to glob "$SIDECAR_ROOT"/*/sidecar.json, and a glob never
# matches a path under a directory it cannot search: a guest sidecar at mode
# 000, or 444 (readable, not searchable), vanished from the scan, the lookup
# read as SIDECAR MISS, and backend answered github on the guest repo. Same
# precedence as #530: refused only when no readable sidecar claims the key.
# uid 0 searches mode-000 directories, so root skips.
if [ "$(id -u)" -eq 0 ]; then
    ok "unenterable sidecar directory: skipped under root, which searches mode-000 directories"
else
    dir_root="$tmp/dir-sidecars"
    mkproj https://github.com/acme/dirguest.git
    dirguest="$P"
    SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirguest" init --name g --mode guest --write sidecar --in-tree-path none --no-migrate-archive
    [ "$rc" -eq 0 ] || bad "init guest for the unenterable-directory arms" "$err"
    for m in 000 444; do
        chmod "$m" "$dir_root/g"
        for a in prds slices stamp; do
            SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirguest" backend "$a"
            check "sidecar dir at mode $m: backend $a exits 1" 1 "$rc"
            check "sidecar dir at mode $m: backend $a prints nothing on stdout (not github)" "" "$out"
            case "$err" in *"$dir_root/g"*) ok "sidecar dir at mode $m: backend $a names the directory on stderr" ;; *) bad "sidecar dir at mode $m: backend $a names the directory on stderr" "got [$err]" ;; esac
        done
        chmod 755 "$dir_root/g"
    done
    SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirguest" backend stamp
    check "sidecar dir restored: backend stamp answers sidecar again" sidecar "$out"

    # A readable claimant still resolves beside a stray it cannot enter.
    mkproj https://github.com/acme/dirclaimed.git
    dirclaimed="$P"
    SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirclaimed" init --name claimed --mode guest --write sidecar --in-tree-path none --no-migrate-archive
    [ "$rc" -eq 0 ] || bad "init the readable claimant" "$err"
    chmod 000 "$dir_root/g"
    SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirclaimed" backend stamp
    check "claimed repo beside an unenterable sidecar dir: backend stamp answers sidecar" sidecar "$out"
    case "$err" in *"$dir_root/g"*) ok "claimed repo beside an unenterable sidecar dir: the directory is named on stderr" ;; *) bad "claimed repo beside an unenterable sidecar dir: the directory is named on stderr" "got [$err]" ;; esac
    chmod 755 "$dir_root/g"
    clean "unenterable-directory arms leave the guest project clean" "$dirguest"
    clean "unenterable-directory arms leave the claimed project clean" "$dirclaimed"

    # The root itself. At mode 000 the */ glob returns its own pattern, and at
    # 111 (searchable, not listable) it cannot list a single entry; either way
    # the scan used to find nothing and read as a miss. A root that does not
    # exist is still the honest miss, whose answer is github.
    for m in 000 111; do
        chmod "$m" "$dir_root"
        for a in prds slices stamp; do
            SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirguest" backend "$a"
            check "sidecar root at mode $m: backend $a exits 1" 1 "$rc"
            check "sidecar root at mode $m: backend $a prints nothing on stdout (not github)" "" "$out"
            case "$err" in *"$dir_root"*) ok "sidecar root at mode $m: backend $a names the root on stderr" ;; *) bad "sidecar root at mode $m: backend $a names the root on stderr" "got [$err]" ;; esac
        done
        chmod 755 "$dir_root"
    done
    SKILL_KIT_SIDECAR_ROOT="$dir_root" runo "$dirguest" backend stamp
    check "sidecar root restored: backend stamp answers sidecar again" sidecar "$out"
    SKILL_KIT_SIDECAR_ROOT="$tmp/no-such-root" runo "$dirguest" backend stamp
    check "absent sidecar root: backend stamp is still the github miss" "0:github" "$rc:$out"
fi

# A sidecar.json symlink whose target is gone fails `[ -f ]`, so the scan used
# to skip it as "no sidecar here". It is the same class as an unreadable file:
# present, and unparseable. No chmod, so this arm runs under root too.
link_root="$tmp/link-sidecars"
mkproj https://github.com/acme/linkguest.git
linkguest="$P"
SKILL_KIT_SIDECAR_ROOT="$link_root" runo "$linkguest" init --name g --mode guest --write sidecar --in-tree-path none --no-migrate-archive
[ "$rc" -eq 0 ] || bad "init guest for the dangling-symlink arms" "$err"
mv "$link_root/g/sidecar.json" "$tmp/link-good.json"
ln -s "$tmp/link-gone.json" "$link_root/g/sidecar.json"
for a in prds slices stamp; do
    SKILL_KIT_SIDECAR_ROOT="$link_root" runo "$linkguest" backend "$a"
    check "dangling sidecar.json symlink: backend $a exits 1" 1 "$rc"
    check "dangling sidecar.json symlink: backend $a prints nothing on stdout (not github)" "" "$out"
    case "$err" in *"$link_root/g/sidecar.json"*) ok "dangling sidecar.json symlink: backend $a names the file on stderr" ;; *) bad "dangling sidecar.json symlink: backend $a names the file on stderr" "got [$err]" ;; esac
done
rm "$link_root/g/sidecar.json"
mv "$tmp/link-good.json" "$link_root/g/sidecar.json"
SKILL_KIT_SIDECAR_ROOT="$link_root" runo "$linkguest" backend stamp
check "dangling symlink replaced: backend stamp answers sidecar again" sidecar "$out"

# -----------------------------------------------------------------------------
section "backend: truth table across mode × forge kind"

# expect <mode> <remote> <prds> <slices> <stamp>
expect() {
    local mode="$1" remote="$2" label
    local p; mkproj "$remote"; p="$P"
    runo "$p" init --name "t$n" --mode "$mode" --write sidecar --in-tree-path none --no-migrate-archive
    [ "$rc" -eq 0 ] || { bad "init $mode $remote" "$err"; return; }
    label="$mode on $( [ "$remote" = none ] && echo 'no remote' || echo "$remote")"
    runo "$p" backend prds;   check "$label: prds → $3"   "$3" "$out"
    runo "$p" backend slices; check "$label: slices → $4" "$4" "$out"
    runo "$p" backend stamp;  check "$label: stamp → $5"  "$5" "$out"
    clean "$label: backend leaves the project clean" "$p"
}
expect owned https://github.com/acme/a.git      github  github  github
expect guest https://github.com/acme/b.git      sidecar sidecar sidecar
expect owned none                               sidecar sidecar sidecar
expect guest none                               sidecar sidecar sidecar
# forge.write is derived from mode alone, so an owned GitLab or Bitbucket repo
# carries the full write list; `github` must still not be the answer there,
# because the consumers of `github` run `gh`.
expect owned https://gitlab.com/acme/c.git      sidecar sidecar sidecar
expect guest https://gitlab.com/acme/d.git      sidecar sidecar sidecar
expect owned https://bitbucket.org/acme/e.git   sidecar sidecar sidecar

# The two write lists route independently: an owned GitHub repo whose
# forge.write lost `prs` keeps its issues on GitHub and its stamp in the sidecar.
mkproj https://github.com/acme/split.git
runo "$P" init --name split --mode owned --write sidecar --in-tree-path none --no-migrate-archive
S="$out"
jq '.forge.write = ["issues"]' "$S/sidecar.json" > "$tmp/j" && mv "$tmp/j" "$S/sidecar.json"
runo "$P" backend prds;  check "forge.write [issues]: prds → github" github "$out"
runo "$P" backend stamp; check "forge.write [issues]: stamp → sidecar" sidecar "$out"
jq '.forge.write = ["prs"]' "$S/sidecar.json" > "$tmp/j" && mv "$tmp/j" "$S/sidecar.json"
runo "$P" backend slices; check "forge.write [prs]: slices → sidecar" sidecar "$out"
runo "$P" backend stamp;  check "forge.write [prs]: stamp → github" github "$out"
jq '.forge.write = "prs"' "$S/sidecar.json" > "$tmp/j" && mv "$tmp/j" "$S/sidecar.json"
runo "$P" backend stamp
check "a forge.write that is not an array fails loudly rather than routing" 1 "$rc"

# -----------------------------------------------------------------------------
section "stamp: write, read, clear"

mkproj none
runo "$P" init --name stamps --mode guest --write sidecar --in-tree-path none --no-migrate-archive
S="$out"
sha_a="0123456789abcdef0123456789abcdef01234567"
sha_b="fedcba9876543210fedcba9876543210fedcba98"

runo "$P" stamp read feature
check "no stamp yet: read prints nothing" "" "$out"
check "no stamp yet: read exits 0" 0 "$rc"

runo "$P" stamp write feature "$sha_a" --base-ref origin/main
check "write exits 0" 0 "$rc"
clean "write leaves the project clean" "$P"
check "write commits the stamp in the sidecar" "" "$(git -C "$S" status --porcelain)"
runo "$P" stamp read feature
check "read returns exactly the SHA written" "$sha_a" "$out"
check "the SHA read is a full 40-character OID" 40 "${#out}"
clean "read leaves the project clean" "$P"
runo "$P" stamp read other
check "read for a different branch prints nothing" "" "$out"
check "read for a different branch exits 0" 0 "$rc"

f="$(find "$S/reviews" -name '*.json' 2>/dev/null | head -1)"
check "the stamp file records the branch" feature "$(jq -r .branch "$f")"
check "the stamp file records schema 1" 1 "$(jq -r .schema "$f")"
check "the stamp file records the base ref" origin/main "$(jq -r .base_ref "$f")"
check "the stamp file records an ISO-8601 UTC time" 1 \
    "$(jq -r .at "$f" | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')"

runo "$P" stamp write feature "$sha_b"
runo "$P" stamp read feature
check "a re-stamp replaces the SHA rather than adding a second" "$sha_b" "$out"
check "one branch, one stamp file" 1 "$(find "$S/reviews" -name '*.json' | wc -l | tr -d ' ')"

for bad_sha in "${sha_a:0:7}" "${sha_a}f" "not-a-sha" "$(printf '%s' "$sha_a" | tr 'a-f' 'A-F')"; do
    runo "$P" stamp write feature "$bad_sha"
    check "write refuses a SHA that is not 40 lowercase hex: [$bad_sha]" 1 "$rc"
done
runo "$P" stamp read feature
check "a refused write leaves the previous stamp standing" "$sha_b" "$out"

runo "$P" stamp clear feature
check "clear exits 0" 0 "$rc"
runo "$P" stamp read feature
check "after clear, read prints nothing" "" "$out"
check "clear commits the removal" "" "$(git -C "$S" status --porcelain)"
clean "clear leaves the project clean" "$P"
runo "$P" stamp clear feature
check "clearing a branch with no stamp is a no-op that exits 0" 0 "$rc"

# A stamp whose JSON names another branch is not this branch's stamp, whatever
# its filename says; one that does not parse is no stamp at all.
runo "$P" stamp write feature "$sha_a"
f="$(find "$S/reviews" -name '*.json' | head -1)"
jq '.branch = "someone-else"' "$f" > "$tmp/j" && mv "$tmp/j" "$f"
runo "$P" stamp read feature
check "read matches on the JSON branch field, not the filename" "" "$out"
printf '{ not json' > "$f"
runo "$P" stamp read feature
check "a malformed stamp reads as no stamp" "" "$out"
check "a malformed stamp read still exits 0" 0 "$rc"
jq -n --arg b feature '{schema:1, branch:$b, reviewed_sha:"abc1234"}' > "$f"
runo "$P" stamp read feature
check "a stored short SHA is not returned" "" "$out"

runo "$P" stamp write "" "$sha_a"
check "write refuses an empty branch" 2 "$rc"

# -----------------------------------------------------------------------------
section "stamp: branch slugs"

for b in "feat/x" "feat-x" "Feat/X" "user/émile/ünïcode" "a%2Fb" "a/b/c" "dots.in.name"; do
    runo "$P" stamp write "$b" "$sha_a"
    [ "$rc" -eq 0 ] || { bad "write [$b]" "$err"; continue; }
    runo "$P" stamp read "$b"
    check "round trip for [$b]" "$sha_a" "$out"
done
# Distinct branches that a lossy slug would merge must stay distinct.
runo "$P" stamp write "feat/x" "$sha_b"
runo "$P" stamp read "feat-x"
check "feat/x and feat-x do not share a stamp" "$sha_a" "$out"
runo "$P" stamp read "a%2Fb"
check "a/b's encoding and a literal a%2Fb do not share a stamp" "$sha_a" "$out"
runo "$P" stamp read "Feat/X"
check "Feat/X and feat/x do not share a stamp on a case-insensitive filesystem" "$sha_a" "$out"
check "every slug is one path component of [a-z0-9._-] and %XX escapes" "" \
    "$(find "$S/reviews" -name '*.json' -exec basename {} \; | grep -vE '^([a-z0-9._-]|%[0-9A-F]{2})+\.json$' || true)"
clean "slug writes leave the project clean" "$P"

# The slug rule is the doc's, so its decoding must recover the branch: decode
# each filename by the rule and compare with the JSON body it names.
mismatch=""
for f in "$S"/reviews/*.json; do
    slug="$(basename "$f" .json)"
    decoded="$(printf '%b' "$(printf '%s' "$slug" | sed 's/%\([0-9A-F][0-9A-F]\)/\\x\1/g')")"
    body="$(jq -r .branch "$f" 2>/dev/null || true)"
    [ -z "$body" ] || [ "$body" = "someone-else" ] || [ "$decoded" = "$body" ] || mismatch="$mismatch $slug→$decoded≠$body"
done
check "every slug decodes back to the branch its JSON names" "" "$mismatch"

# -----------------------------------------------------------------------------
section "stamp: no sidecar"

mkproj none
runo "$P" stamp read feature
check "read with no sidecar exits nonzero (a caller asks backend first)" 1 "$rc"
runo "$P" stamp write feature "$sha_a"
check "write with no sidecar exits nonzero" 1 "$rc"
clean "a refused write leaves the project clean" "$P"

# -----------------------------------------------------------------------------
section "work: the id regex is the doc's"

# The regex is a single line in a fenced block of its own under "## Work
# items". It is extracted, never restated, so a doc edit and a script edit
# cannot disagree about what an id looks like.
ID_RE="$(awk '/^## Work items/{w=1} w && /^```$/{if (f) exit; f=1; next} w && f' "$DOC")"
check "the doc carries one id-regex line in a fenced block under ## Work items" 1 "$(printf '%s\n' "$ID_RE" | grep -c .)"
check "the script's WORK_ID_RE is the doc's regex" "WORK_ID_RE='$ID_RE'" "$(grep -E "^WORK_ID_RE=" "$SC")"
is_id() { grep -qxE "$ID_RE" <<<"$1"; }

# -----------------------------------------------------------------------------
section "work: create, view, edit, set, comment, close, list"

mkproj https://github.com/acme/guestwork.git
runo "$P" init --name work --mode guest --write sidecar --in-tree-path none --no-migrate-archive
S="$out"
W="$S/work"
printf '## Problem\n\nA contractor ships.\n\n## Acceptance Criteria\n\n- [ ] one\n- [ ] two\n' > "$tmp/prd.md"

runo "$P" work create --kind prd --milestone 'Sidecar: guest-mode Skill Kit' --body-file "$tmp/prd.md"
check "create exits 0" 0 "$rc"
prd="$out"
if is_id "$prd"; then ok "create prints an id matching the doc's regex [$prd]"; else bad "create prints an id matching the doc's regex" "got [$prd]"; fi
check "create commits exactly one file under work/" "work/$prd.md" "$(git -C "$S" show --name-only --format= HEAD)"
check "create leaves the sidecar clean" "" "$(git -C "$S" status --porcelain)"
clean "create leaves the project clean" "$P"

runo "$P" work view "$prd" --json
check "view --json: id" "$prd" "$(printf '%s' "$out" | jq -r .id)"
check "view --json: kind" prd "$(printf '%s' "$out" | jq -r .kind)"
check "view --json: state starts open" open "$(printf '%s' "$out" | jq -r .state)"
check "view --json: a prd's maturity defaults to prd" prd "$(printf '%s' "$out" | jq -r .maturity)"
check "view --json: milestone is a free string" "Sidecar: guest-mode Skill Kit" "$(printf '%s' "$out" | jq -r .milestone)"
check "view --json: body is the body file, trailing newline trimmed" "$(cat "$tmp/prd.md")" "$(printf '%s' "$out" | jq -r .body)"
check "view --json: comments starts empty" 0 "$(printf '%s' "$out" | jq '.comments | length')"
check "view --json: created is a date" 1 "$(printf '%s' "$out" | jq -r .created | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')"
runo "$P" work view "$prd"
check "view prints the file as stored" "$(cat "$W/$prd.md")" "$out"
check "the file opens with a frontmatter fence" "---" "$(head -n 1 "$W/$prd.md")"

# Slices and their edges.
runo "$P" work create --kind slice --parent "$prd" --body-file "$tmp/prd.md"; s1="$out"
runo "$P" work create --kind slice --parent "$prd" --blocked-by "$s1" --body-file "$tmp/prd.md"; s2="$out"
runo "$P" work view "$s2" --json
check "a slice records its parent" "$prd" "$(printf '%s' "$out" | jq -r .parent)"
check "a slice records blocked_by as a list" "[\"$s1\"]" "$(printf '%s' "$out" | jq -c .blocked_by)"
check "a slice carries no maturity" null "$(printf '%s' "$out" | jq -r .maturity)"
runo "$P" work create --kind slice --parent W-999 --body-file "$tmp/prd.md"
check "create refuses a parent that does not exist" 1 "$rc"
runo "$P" work create --kind slice --blocked-by "#12" --body-file "$tmp/prd.md"
check "create refuses a bare #N blocker" 2 "$rc"
runo "$P" work create --kind prd --body-file "$tmp/no-such-file"
check "create refuses a missing body file" 1 "$rc"
: > "$tmp/empty.md"
runo "$P" work create --kind prd --body-file "$tmp/empty.md"
check "create refuses an empty body" 1 "$rc"
printf 'x\n## Comment 2026-01-01T00:00:00Z\n' > "$tmp/forged.md"
runo "$P" work create --kind prd --body-file "$tmp/forged.md"
check "create refuses a body carrying a comment heading" 1 "$rc"
check "refused creates leave no file behind" 3 "$(find "$W" -name 'W-*.md' | wc -l | tr -d ' ')"
check "refused creates leave no temp file behind" "" "$(find "$W" -name '.work.*')"

# edit: a ticked box keeps the length; a dropped line is refused.
sed 's/- \[ \] one/- [x] one/' "$tmp/prd.md" > "$tmp/ticked.md"
runo "$P" work edit "$prd" --body-file "$tmp/ticked.md"
check "edit accepts a same-length body" 0 "$rc"
runo "$P" work view "$prd" --json
check "edit replaced the body" "$(cat "$tmp/ticked.md")" "$(printf '%s' "$out" | jq -r .body)"
before="$(cat "$W/$prd.md")"
head_before="$(git -C "$S" rev-parse HEAD)"
grep -v 'two' "$tmp/ticked.md" > "$tmp/shorter.md"
runo "$P" work edit "$prd" --body-file "$tmp/shorter.md"
check "edit refuses a body shorter than the one it read" 1 "$rc"
check "a refused edit leaves the file unchanged" "$before" "$(cat "$W/$prd.md")"
check "a refused edit makes no sidecar commit" "$head_before" "$(git -C "$S" rev-parse HEAD)"

# comment: appended as dated sections, survive later edits and sets.
printf 'first note\n' > "$tmp/c1.md"
printf 'second note\nwith two lines\n' > "$tmp/c2.md"
runo "$P" work comment "$prd" --body-file "$tmp/c1.md"
runo "$P" work comment "$prd" --body-file "$tmp/c2.md"
runo "$P" work view "$prd" --json
check "two comments read back" 2 "$(printf '%s' "$out" | jq '.comments | length')"
check "comments keep their order and text" "first note|second note
with two lines" "$(printf '%s' "$out" | jq -r '.comments | map(.body) | join("|")')"
check "a comment's at is ISO-8601 UTC" 1 "$(printf '%s' "$out" | jq -r '.comments[0].at' | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')"
check "comments do not leak into the body" "$(cat "$tmp/ticked.md")" "$(printf '%s' "$out" | jq -r .body)"
check "each comment is a '## Comment <ISO-8601>' section" 2 "$(grep -cE '^## Comment [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$W/$prd.md")"
comments_before="$(printf '%s' "$out" | jq -c .comments)"
cp "$tmp/ticked.md" "$tmp/longer.md"; printf -- '- [ ] three\n' >> "$tmp/longer.md"
runo "$P" work edit "$prd" --body-file "$tmp/longer.md"
runo "$P" work view "$prd" --json
check "edit keeps the comments" "$comments_before" "$(printf '%s' "$out" | jq -c .comments)"

# set: decomposed_into is replaced, never appended to.
runo "$P" work set "$prd" decomposed_into "$s1,$s2"
runo "$P" work view "$prd" --json
check "set decomposed_into records the list" "[\"$s1\",\"$s2\"]" "$(printf '%s' "$out" | jq -c .decomposed_into)"
runo "$P" work set "$prd" decomposed_into "$s2"
runo "$P" work view "$prd" --json
check "a second set decomposed_into replaces the first" "[\"$s2\"]" "$(printf '%s' "$out" | jq -c .decomposed_into)"
check "the file holds one decomposed_into line" 1 "$(grep -c '^decomposed_into:' "$W/$prd.md")"
check "set keeps the comments" "$comments_before" "$(printf '%s' "$out" | jq -c .comments)"
runo "$P" work set "$s1" decomposed_into "$s2"
check "decomposed_into is refused on a slice" 1 "$rc"
runo "$P" work set "$prd" maturity research-ready
runo "$P" work view "$prd" --json
check "set maturity" research-ready "$(printf '%s' "$out" | jq -r .maturity)"
runo "$P" work set "$prd" maturity "roadmap bet"
runo "$P" work view "$prd" --json
check "a maturity with a space round-trips" "roadmap bet" "$(printf '%s' "$out" | jq -r .maturity)"
runo "$P" work set "$prd" pr "https://github.com/acme/guestwork/pull/7"
runo "$P" work view "$prd" --json
check "set pr" "https://github.com/acme/guestwork/pull/7" "$(printf '%s' "$out" | jq -r .pr)"
runo "$P" work set "$prd" reviewed_sha "$sha_a"
runo "$P" work view "$prd" --json
check "set reviewed_sha" "$sha_a" "$(printf '%s' "$out" | jq -r .reviewed_sha)"
runo "$P" work set "$prd" reviewed_sha abc1234
check "set refuses a reviewed_sha that is not 40 hex" 1 "$rc"
runo "$P" work set "$prd" state finished
check "set refuses an unknown state" 2 "$rc"
runo "$P" work set "$prd" milestone other
check "set refuses a field outside its list" 2 "$rc"
runo "$P" work view "#1"
check "a bare #N is not an id" 2 "$rc"

# list and close.
runo "$P" work list
check "list prints open items in id order" "$prd
$s1
$s2" "$out"
runo "$P" work list --kind slice --parent "$prd"
check "list --kind slice --parent" "$s1
$s2" "$out"
runo "$P" work list --unblocked --kind slice
check "list --unblocked holds back a slice with an open blocker" "$s1" "$out"
runo "$P" work close "$s1"
check "close exits 0" 0 "$rc"
runo "$P" work list --unblocked --kind slice
check "closing the blocker unblocks the slice" "$s2" "$out"
runo "$P" work list --state closed
check "list --state closed" "$s1" "$out"
runo "$P" work create --kind prd --body-file "$tmp/prd.md"; prd2="$out"
runo "$P" work close "$prd" --superseded-by "$prd2"
runo "$P" work view "$prd" --json
check "close --superseded-by records state" closed "$(printf '%s' "$out" | jq -r .state)"
check "close --superseded-by records the successor" "$prd2" "$(printf '%s' "$out" | jq -r .superseded_by)"
runo "$P" work close "$prd2" --superseded-by W-999
check "close refuses a successor that does not exist" 1 "$rc"
runo "$P" work list --state all
check "list --state all" "$prd
$s1
$s2
$prd2" "$out"

# The word FAIL inside an item's own frontmatter is data, not a parse failure;
# a file that genuinely does not parse still fails the list and names itself.
runo "$P" work create --kind prd --milestone 'FAIL-safe rollout' --body-file "$tmp/prd.md"; failid="$out"
runo "$P" work set "$failid" pr "https://github.com/acme/FAIL/pull/9"
runo "$P" work list --state all
check "list still lists when a milestone and pr contain FAIL" "$prd
$s1
$s2
$prd2
$failid" "$out"
check "list exits 0 when a milestone and pr contain FAIL" 0 "$rc"
printf 'not frontmatter at all\n' > "$W/W-98.md"
runo "$P" work list --state all
check "list exits nonzero on a work file that does not parse" 1 "$rc"
case "$err" in *"work list: $W/W-98.md does not parse"*) named=1 ;; *) named=0 ;; esac
check "list names the unparseable file on stderr" 1 "$named"
rm -f "$W/W-98.md"

check "work verbs leave the sidecar clean" "" "$(git -C "$S" status --porcelain)"
clean "work verbs leave the project clean" "$P"

# -----------------------------------------------------------------------------
section "work: concurrent creates claim distinct ids"

mkproj none
runo "$P" init --name race --mode guest --write sidecar --in-tree-path none --no-migrate-archive
S="$out"
for i in 1 2 3 4 5 6; do
    (cd "$P" && bash "$SC" work create --kind slice --body-file "$tmp/prd.md" > "$tmp/race.$i" 2>"$tmp/race.$i.err"; echo $? > "$tmp/race.$i.rc") &
done
wait
ids="$(cat "$tmp"/race.[0-9] | LC_ALL=C sort)"
check "every racing create exits 0" "000000" "$(cat "$tmp"/race.[0-9].rc | tr -d '\n')"
check "six racing creates print six ids" 6 "$(printf '%s\n' "$ids" | grep -c .)"
check "six racing creates print six distinct ids" 6 "$(printf '%s\n' "$ids" | sort -u | grep -c .)"
check "six racing creates leave six files" 6 "$(find "$S/work" -name 'W-*.md' | wc -l | tr -d ' ')"
check "every raced file is committed" "" "$(git -C "$S" status --porcelain)"
check "every raced file's id field matches its name" "" \
    "$(for f in "$S"/work/W-*.md; do [ "$(sed -n 's/^id: //p' "$f")" = "$(basename "$f" .md)" ] || echo "$f"; done)"
clean "racing creates leave the project clean" "$P"

# -----------------------------------------------------------------------------
section "work: no sidecar"

mkproj none
runo "$P" work list
check "work with no sidecar exits nonzero (a caller asks backend first)" 1 "$rc"
runo "$P" work create --kind prd --body-file "$tmp/prd.md"
check "work create with no sidecar exits nonzero" 1 "$rc"
clean "a refused work create leaves the project clean" "$P"

# -----------------------------------------------------------------------------
section "docs/state-backend.md states the rule the script runs"

# shellcheck disable=SC2016  # the backticks are the doc's literal markdown
# The routing rule's two write-list items are the doc's, extracted from its
# rule table, so a doc edit that renames one fails here rather than drifting.
check "the doc routes prds and slices on 'issues'" 1 \
    "$(grep -cE '^\| *`prds`, `slices` *\| *`issues` *\|' "$DOC")"
# shellcheck disable=SC2016
check "the doc routes the stamp on 'prs'" 1 \
    "$(grep -cE '^\| *`stamp` *\| *`prs` *\|' "$DOC")"
check "the doc points at PRD #407 for the stamp shape rather than restating it" 1 \
    "$(grep -c 'chrislacey89/skills#407' "$DOC" | awk '{print ($1 > 0)}')"

# -----------------------------------------------------------------------------
section "/execute on a work item: the Step 0 gate's verdicts (#525)"

# /execute W-<n> must refuse the same work on the sidecar that it refuses on
# GitHub: an undecomposed PRD, a slice with an open blocker. The gate is a
# fenced block a downstream agent runs unsupervised, so it is extracted from
# execute/SKILL.md and RUN here, in bash and in zsh (agents use both), never
# restated. The decomposed-PRD fixture is written by /prd-to-issues §8's own
# sidecar block, so the writer and the reader of `decomposed_into` meet in a run.
EXEC="$repo_root/execute/SKILL.md"
PTI="$repo_root/prd-to-issues/SKILL.md"
# skill_block <file> <literal> — the fenced bash block that sets SC from the
# bundled resolver and contains <literal>, with the real script substituted.
skill_block() {
    awk -v want="$2" '
        /^```bash$/ { buf = ""; on = 1; next }
        on && /^```$/ {
            on = 0
            if (buf ~ /<this skill.s directory>\/references\/sidecar\.sh/ && index(buf, want)) { printf "%s", buf; exit }
            next
        }
        on { buf = buf $0 "\n" }
    ' "$1" | sed "s|<this skill's directory>/references/sidecar.sh|$SC|g"
}
# shellcheck disable=SC2016  # the needles are the skills' literal text
{
gate_block="$(skill_block "$EXEC" 'SIDECAR_VERDICT_JQ=')"
writeback_block="$(skill_block "$EXEC" 'work edit "$W"')"
decomp_block="$(skill_block "$PTI" 'decomposed_into "$SLICES"')"
}
[ -n "$gate_block" ] || { bad "execute/SKILL.md carries the sidecar gate block" "not found"; }
[ -n "$writeback_block" ] || { bad "execute/SKILL.md carries the sidecar writeback block" "not found"; }
[ -n "$decomp_block" ] || { bad "prd-to-issues/SKILL.md §8 carries the decomposed_into block" "not found"; }
case "$gate_block$writeback_block" in *'gh '*) bad "no execute sidecar block calls gh" "found gh" ;; *) ok "no execute sidecar block calls gh" ;; esac

# The writer↔reader pair: the field §8 sets is the field Step 0 reads, and both
# skills state the replace semantics the gate relies on.
# shellcheck disable=SC2016  # the pattern is the skill's literal text
w_field="$(sed -n 's/.*work set "\$PRD" \([a-z_]*\) "\$SLICES".*/\1/p' <<<"$decomp_block")"
# shellcheck disable=SC2016
r_field="$(grep -o '(\$i\.[a-z_]* // \[\])' <<<"$gate_block" | sed 's/(\$i\.\([a-z_]*\) .*/\1/')"
check "/prd-to-issues §8 writes decomposed_into" decomposed_into "$w_field"
check "/execute Step 0 reads the field /prd-to-issues §8 writes" "$w_field" "$r_field"
check "/prd-to-issues states work set replaces decomposed_into" 1 \
    "$(grep -c 'replaces the field rather than appending' "$PTI" | awk '{print ($1 > 0)}')"
# shellcheck disable=SC2016
check "/execute states work set replaces decomposed_into" 1 \
    "$(grep -c '`work set` replaces it on every write' "$EXEC" | awk '{print ($1 > 0)}')"

gate_shells="bash"
if command -v zsh >/dev/null 2>&1; then gate_shells="bash zsh"
elif [ -n "${CI:-}" ]; then bad "zsh is on PATH for the gate's zsh arm" "zsh missing and CI is set"
else printf '  SKIP zsh arm: zsh is not on PATH\n'; fi

mkproj https://github.com/acme/exec-guest.git
(cd "$P" && bash "$SC" init --name exec-guest --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1) \
    || bad "init the /execute gate fixture" "init failed"
printf '## Problem\n\nx\n\n## Appetite\n\n2 weeks\n' > "$tmp/xprd.md"
printf '## Parent PRD\n\nW-1\n\n## Acceptance Criteria\n\n- [ ] one\n- [ ] two\n' > "$tmp/xslice.md"
(cd "$P" && bash "$SC" work create --kind prd --body-file "$tmp/xprd.md" >/dev/null)                           # W-1
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --body-file "$tmp/xslice.md" >/dev/null)          # W-2
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --blocked-by W-2 --body-file "$tmp/xslice.md" >/dev/null) # W-3

# gate <label> <W-id> <expected> — run the extracted gate in every shell.
gate() {
    local sh b="${gate_block//W=\"W-<n>\"/W=\"$2\"}"
    for sh in $gate_shells; do
        out="$(cd "$P" && "$sh" -c "$b" 2>"$tmp/stderr")"
        check "$1 ($sh)" "$3" "$out"
    done
}
gate "an undecomposed sidecar PRD is undecomposed-prd" W-1 "undecomposed-prd"
gate "a slice with an open blocker is blocked, naming it" W-3 'blocked [{"id":"W-2","state":"open"}]'
gate "a slice with no blockers is takeable" W-2 "takeable ever_wired=0 comments=0"
gate "a work item that does not exist is unknown" W-99 "unknown"

d="${decomp_block//PRD=\"W-<prd>\"/PRD=\"W-1\"}"
d="${d//SLICES=\"W-<a>,W-<b>\"/SLICES=\"W-2,W-3\"}"
(cd "$P" && bash -c "$d" >/dev/null 2>&1) || bad "/prd-to-issues §8's block runs" "exit nonzero"
gate "a PRD /prd-to-issues §8 decomposed falls through to takeable" W-1 "takeable ever_wired=0 comments=0"

(cd "$P" && bash "$SC" work close W-2 >/dev/null)
gate "a slice whose blockers are all closed is takeable" W-3 "takeable ever_wired=1 comments=0"
printf 'handoff note\n' > "$tmp/xnote.md"
(cd "$P" && bash "$SC" work comment W-3 --body-file "$tmp/xnote.md" >/dev/null)
gate "the takeable line counts the comment thread" W-3 "takeable ever_wired=1 comments=1"
(cd "$P" && bash "$SC" work set W-3 pr "https://github.com/acme/exec-guest/pull/9" >/dev/null)
gate "a slice with a recorded pr is in-flight" W-3 'in-flight [{"pr":"https://github.com/acme/exec-guest/pull/9"}]'
# The kind field decides, not the body: a prd without the shaped-pitch headings
# is still undecomposed, and a slice that carries one is never a PRD.
printf '## Problem\n\nx\n' > "$tmp/xplain.md"
printf '## Parent PRD\n\nW-1\n\n## Implementation Decisions\n\nx\n' > "$tmp/xheadslice.md"
(cd "$P" && bash "$SC" work create --kind prd --body-file "$tmp/xplain.md" >/dev/null)                              # W-4
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --body-file "$tmp/xheadslice.md" >/dev/null)          # W-5
gate "a prd without the shaped-pitch headings is undecomposed-prd" W-4 "undecomposed-prd"
gate "a slice whose body has a shaped-pitch heading is takeable" W-5 "takeable ever_wired=0 comments=0"
# An unreadable blocker counts as open, and a blocker outranks a recorded pr.
# `work create --blocked-by` refuses an id that does not exist, so the dangling
# id is written into the item's frontmatter by hand (and committed, so the
# sidecar stays clean) the way a deleted or mistyped blocker would arrive.
xs="$SKILL_KIT_SIDECAR_ROOT/exec-guest"
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --body-file "$tmp/xslice.md" >/dev/null)          # W-6
(cd "$P" && bash "$SC" work create --kind slice --parent W-1 --body-file "$tmp/xslice.md" >/dev/null)          # W-7
sed 's/^blocked_by:.*/blocked_by: [W-99]/' "$xs/work/W-6.md" > "$tmp/w6.md" && cp "$tmp/w6.md" "$xs/work/W-6.md"
sed 's/^blocked_by:.*/blocked_by: [W-2, W-99]/' "$xs/work/W-7.md" > "$tmp/w7.md" && cp "$tmp/w7.md" "$xs/work/W-7.md"
git -C "$xs" add work/W-6.md work/W-7.md
git -C "$xs" commit -q -m "test: hand-written dangling blockers" || bad "commit the dangling-blocker fixtures" "commit failed"
(cd "$P" && bash "$SC" work set W-7 pr "https://github.com/acme/exec-guest/pull/10" >/dev/null)
gate "a blocker id that does not exist is blocked as unreadable" W-6 'blocked [{"id":"W-99","state":"unreadable"}]'
gate "a blocked item with a recorded pr is blocked, not in-flight" W-7 'blocked [{"id":"W-99","state":"unreadable"}]'
clean "the gate leaves the project clean" "$P"

# -----------------------------------------------------------------------------
section "/execute on a work item: acceptance-criteria writeback (#525)"

S="$SKILL_KIT_SIDECAR_ROOT/exec-guest"
# shellcheck disable=SC2016  # the injected edit is literal sh for the block
flip='awk '\''!d && /^- \[ \]/{sub(/- \[ \]/,"- [x]"); d=1} 1'\'' "$BODY_FILE" > "$BODY_FILE.n" && mv "$BODY_FILE.n" "$BODY_FILE"'
# wb <W-id> <edit> — run the writeback block with <edit> in place of the
# "Leave every other line untouched." comment line.
wb() {
    local b="${writeback_block//W=\"W-<n>\"/W=\"$1\"}"
    # A literal match: in a ${b//pat/} pattern, the comment's "[ ]" is a bracket expression.
    b="$(E="$2" awk 'index($0, "Leave every other line untouched.") { print ENVIRON["E"]; n++; next } 1; END { exit n != 1 }' <<<"$b")" \
        || bad "the writeback block carries exactly one edit placeholder" "awk found none or several"
    out="$(cd "$P" && bash -c "$b" 2>"$tmp/stderr")"; rc=$?; err="$(cat "$tmp/stderr")"
}
before_body="$(cd "$P" && bash "$SC" work view W-2 --json | jq -r .body)"
commits_before="$(git -C "$S" rev-list --count HEAD)"
wb W-2 "$flip"
check "writeback exits 0" 0 "$rc"
after_body="$(cd "$P" && bash "$SC" work view W-2 --json | jq -r .body)"
check "writeback ticks exactly the verified box" "$(awk '!d && /^- \[ \]/{sub(/- \[ \]/,"- [x]"); d=1} 1' <<<"$before_body")" "$after_body"
check "writeback leaves the second box alone" 1 "$(grep -c '^- \[ \] two$' <<<"$after_body")"
check "writeback commits once in the sidecar" "$((commits_before + 1))" "$(git -C "$S" rev-list --count HEAD)"
check "writeback leaves the sidecar clean" "" "$(git -C "$S" status --porcelain)"
wb W-2 "$flip"
check "a second tick does not grow the body by a newline" 0 \
    "$(( $(cd "$P" && bash "$SC" work view W-2 --json | jq -r .body | wc -c) - $(printf '%s\n' "$after_body" | wc -c) ))"

commits_before="$(git -C "$S" rev-list --count HEAD)"
wb W-99 "$flip"
check "a failed read aborts the writeback" 1 "$rc"
check "a failed read commits nothing" "$commits_before" "$(git -C "$S" rev-list --count HEAD)"
# shellcheck disable=SC2016
wb W-2 'sed -i.bak "/two/d" "$BODY_FILE"'
check "a shorter body is refused and named" 1 "$(grep -c 'writeback refused' <<<"$err")"
check "a refused writeback commits nothing" "$commits_before" "$(git -C "$S" rev-list --count HEAD)"
clean "the writeback leaves the project clean" "$P"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
