#!/usr/bin/env bash
# test-authored-diff-pathspec.sh — contract test for the command CLAUDE.md
# § "Reading a prose diff" gives a reviewer to leave the bundled copies out.
#
# THE DRIFT CLASS. A change to a docs/ file lands again in every references/
# copy the manifest names, so a PR reads as several times its authored size
# (#731: 2,532 changed lines, 401 authored). The obvious pathspec,
# ':(exclude)*/references/*', also hides the files under references/ that are
# written by hand, so a reviewer using it would never see an edit to them. The
# command CLAUDE.md gives builds its excludes from the manifest instead.
#
# WHAT IT PINS, by extracting the fenced command from CLAUDE.md and running it
# in a scratch repo that carries this repo's manifest:
#   1. A generated copy changed on the branch is left out.
#   2. A hand-written file under references/ changed on the branch is shown.
#   3. A file outside references/ changed on the branch is shown.
# And against this repo: every hand-written references/ file CLAUDE.md names
# as an example exists and is not a manifest target.

set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

manifest=scripts/skill-references.manifest
[ -f "$manifest" ] || fatal "$manifest not found"

# The one fenced line in CLAUDE.md that runs `git diff` with a manifest-built
# pathspec.
cmd="$(grep -E '^git diff origin/prod\.\.\.HEAD -- \. \$\(.*skill-references\.manifest' CLAUDE.md || true)"
[ -n "$cmd" ] || fatal "CLAUDE.md carries no manifest-built git diff command"
[ "$(printf '%s\n' "$cmd" | wc -l | tr -d ' ')" = 1 ] || fatal "CLAUDE.md carries more than one such command"

# -----------------------------------------------------------------------------
section "the command leaves out generated copies and nothing else"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
r="$tmp/repo"
mkdir -p "$r/scripts"
cp "$manifest" "$r/scripts/"
git -C "$r" init -q -b prod
git -C "$r" config user.email t@example.com
git -C "$r" config user.name t
git -C "$r" config commit.gpgsign false

# A generated copy: the manifest's first source, at its first consumer.
read -r src skill < <(grep -vE '^(#|$)' "$manifest" | head -1)
gen="$skill/references/$(basename "$src")"
# A hand-written file under references/ that no manifest line produces.
hand="lfg/references/tracer-test.md"
grep -vE '^(#|$)' "$manifest" | awk '{n = split($1, p, "/"); print $2 "/references/" p[n]}' | grep -qxF "$hand" \
    && fatal "$hand is a manifest target; pick another hand-written file"
plain="docs/authored.md"
for f in "$gen" "$hand" "$plain"; do mkdir -p "$r/$(dirname "$f")"; echo one > "$r/$f"; done
git -C "$r" add -A
git -C "$r" commit -qm base
git -C "$r" update-ref refs/remotes/origin/prod HEAD
git -C "$r" checkout -qb feature
for f in "$gen" "$hand" "$plain"; do echo two >> "$r/$f"; done
git -C "$r" commit -qam change

shown="$(cd "$r" && bash -c "${cmd/git diff /git diff --name-only }")"
if grep -qxF "$gen" <<<"$shown"; then bad "a generated copy is left out" "shown: $gen"; else ok "a generated copy is left out"; fi
if grep -qxF "$hand" <<<"$shown"; then ok "a hand-written references/ file is shown"; else bad "a hand-written references/ file is shown" "missing: $hand"; fi
if grep -qxF "$plain" <<<"$shown"; then ok "a file outside references/ is shown"; else bad "a file outside references/ is shown" "missing: $plain"; fi

# -----------------------------------------------------------------------------
section "the hand-written examples CLAUDE.md names are hand-written"

# shellcheck disable=SC2016  # the patterns match literal backticks
examples="$(grep -E '^Do not exclude `\*/references/\*` wholesale' CLAUDE.md | grep -oE '`[a-z-]+/references/[^`]+`' | tr -d '`' || true)"
[ -n "$examples" ] || bad "CLAUDE.md names hand-written references/ files" "none found"
targets="$(grep -vE '^(#|$)' "$manifest" | awk '{n = split($1, p, "/"); print $2 "/references/" p[n]}')"
while IFS= read -r e; do
    [ -n "$e" ] || continue
    if [ ! -f "$e" ]; then bad "$e exists" "named in CLAUDE.md, not in the tree"
    elif grep -qxF "$e" <<<"$targets"; then bad "$e is not a manifest target" "the manifest generates it"
    else ok "$e is hand-written"; fi
done <<<"$examples"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
