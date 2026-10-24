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
trap 'rm -rf "$tmp"' EXIT

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

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
