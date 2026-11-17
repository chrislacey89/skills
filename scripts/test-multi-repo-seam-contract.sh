#!/usr/bin/env bash
# The needles here are HTML and shell, full of quotes and dollar signs.
# shellcheck disable=SC2016
# test-multi-repo-seam-contract.sh — contract test for /visual-recap's
# multi-repo mode (chrislacey89/skills#761): the multi-scope resolve block in
# visual-recap/SKILL.md §1, the seam block in visual-recap-design.md (its
# section number is read from the heading, not assumed), and
# its registration in visual-rendering-core.md §3 and §4.
#
# THE DRIFT CLASS: a command a downstream agent copies out of a SKILL.md and
# runs unsupervised in two repositories at once (CLAUDE.md § "Commands a skill
# documents", rule (b)). A scope parsed wrong diffs the wrong range in the
# wrong repo, and every ±count the recap prints is then a confident fabrication
# that the Grounding Rule exists to forbid. So the block is not read here. It is
# RUN, extracted verbatim from the skill, against two planted repositories.
#
# The second half pins the seam block's one load-bearing rule: every finding
# cites a line on both sides. A finding that cites one side is a single-repo
# note, and the block exists for what only both sides together show.
#
# WHAT IT PINS, extracted from the real files rather than restated:
#   1. The block, given two scopes, prints each scope's own diff-stat and log,
#      from its own repository, in the order given.
#   2. It refuses before printing anything when any scope is malformed (no `@`,
#      three dots) or names a ref its repository does not have, and when given
#      fewer than two scopes.
#   3. The design's seam section exists, carries the three finding chips, and every finding in
#      its example cites both sides.
#   4. Core §3 lists the seam block and core §4 registers its two id shapes, and
#      the design example uses exactly those shapes.
#   5. SKILL.md and core point at the seam section by the number its heading
#      carries, so a renumber at merge time that misses a pointer fails here.

set -euo pipefail

# A git hook runs with GIT_DIR exported. Without this, the fixture repos below
# re-initialize and commit into the repository the hook points at (#429;
# scripts/test-fixture-git-isolation.sh is the mechanism that catches it).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

SKILL=visual-recap/SKILL.md
DESIGN=docs/visual-recap-design.md
CORE=docs/visual-rendering-core.md

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# --- 1–2. run the documented block ------------------------------------------
# The block is the fenced bash block whose first line is the marker comment.
MARK='# visual-recap: multi-scope resolve'
block="$(awk -v m="$MARK" '
  /^```bash$/ { inb=1; buf=""; first=1; next }
  inb && /^```$/ { if (keep) { printf "%s", buf; exit } inb=0; keep=0; next }
  inb { if (first && $0 == m) keep=1; first=0; buf = buf $0 "\n" }
' "$SKILL")"

if [[ -n "$block" ]]; then ok "SKILL.md carries the multi-scope resolve block"; else bad "SKILL.md has no fenced bash block starting with '$MARK'"; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkrepo() { # mkrepo <dir> <file> <base-line> <head-line>
  git init -q -b base "$1"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m root
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "base $2"
  git -C "$1" checkout -q -b feature
  printf '%s\n%s\n' "$3" "$4" >"$1/$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -am "feature touches $2"
}
mkrepo "$work/caller" caller.ts 'send(status)' "send('CANCELED')"
mkrepo "$work/service" service.php 'accept($status)' "accept('cancelled')"

# The block sets its own scopes on one placeholder `set --` line, as the skill documents it
# (an agent pasting the block has no argv). Fill that line by substitution, never through argv.
if [[ "$(grep -c '^set -- ' <<<"$block")" -eq 1 ]]; then ok "block carries exactly one placeholder 'set --' line"; else bad "block must carry exactly one '^set -- ' placeholder line"; fi
run_block() {
  local argline line src=""
  argline="set --$(printf ' %q' "$@")"
  while IFS= read -r line; do
    if [[ "$line" == 'set -- '* ]]; then src+="$argline"$'\n'; else src+="$line"$'\n'; fi
  done <<<"$block"
  bash -c "$src"
}

out="$(run_block "$work/caller@base..feature" "$work/service@base..feature" 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]]; then ok "two valid scopes exit 0"; else bad "two valid scopes exited $rc: $out"; fi
# Each scope's own file, in order, under its own header.
expect="== scope: $work/caller @ base...feature
 caller.ts | 1 +
== scope: $work/service @ base...feature
 service.php | 1 +"
got="$(grep -E '^== scope:|\| [0-9]+ ' <<<"$out" || true)"
if [[ "$got" == "$expect" ]]; then ok "each scope prints its own diff-stat, from its own repo, in order"; else bad "scope stats wrong; got:
$got"; fi
if grep -qx '[0-9a-f]\{7,\} feature touches caller.ts' <<<"$out" && grep -qx '[0-9a-f]\{7,\} feature touches service.php' <<<"$out"; then
  ok "each scope prints its own commit log"
else
  bad "a scope's commit log is missing"
fi
if grep -q 'base caller.ts\|base service.php' <<<"$out"; then bad "a log line from before the base leaked into a scope"; else ok "logs stop at each scope's base"; fi

refuses() { # refuses <label> <args...>
  local label="$1"; shift
  local o r
  o="$(run_block "$@" 2>&1)" && r=0 || r=$?
  if [[ $r -ne 0 ]] && ! grep -q '^== scope:' <<<"$o"; then ok "refuses $label, printing no scope"; else bad "did not refuse $label cleanly (exit $r): $o"; fi
}
refuses "a ref the repo does not have" "$work/caller@base..feature" "$work/service@base..nope"
refuses "three dots" "$work/caller@base..feature" "$work/service@base...feature"
refuses "a scope with no @" "$work/caller@base..feature" "$work/service"
refuses "an empty endpoint" "$work/caller@base..feature" "$work/service@..feature"
refuses "an empty repo path" "$work/caller@base..feature" "@base..feature"
# Both refs resolve here; only the merge base is missing, so only that guard can refuse it.
git init -q -b orphanbase "$work/orphan"
git -C "$work/orphan" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
git -C "$work/orphan" checkout -q --orphan unrelated
git -C "$work/orphan" -c user.name=t -c user.email=t@t commit -q --allow-empty -m b
refuses "refs that resolve but share no merge base" "$work/caller@base..feature" "$work/orphan@orphanbase..unrelated"
refuses "a single scope" "$work/caller@base..feature"

# --- 3. design: the seam block ----------------------------------------------
N="$(sed -nE 's/^## ([0-9]+)\. Block: seam.*/\1/p' "$DESIGN" | head -1 || true)"
sec15=""
[[ -n "$N" ]] && sec15="$(awk -v h="^## $N\\. Block: seam" '$0 ~ h {on=1; print; next} on&&/^## /{exit} on' "$DESIGN")"
if [[ -n "$sec15" ]]; then ok "design has §$N Block: seam"; else bad "design has no '## <n>. Block: seam' section"; fi
for chip in mismatch fragile planned; do
  if grep -q "class=\"sf-chip sf-$chip\"" <<<"$sec15"; then ok "seam example renders a $chip chip"; else bad "seam example has no sf-$chip chip"; fi
done
# Every finding (data-feedback-kind="seam-finding") cites both sides: two
# .sf-cite spans inside it. Count per finding, not in sum. The END clause
# prints the last finding when no closing comment follows it.
cites="$(awk '
  /data-feedback-kind="seam-finding"/ { if (inf) print n; inf=1; n=0 }
  inf { n += gsub(/class="sf-cite"/, "&") }
  inf && /<!-- \/finding -->/ { print n; inf=0 }
  END { if (inf) print n }
' <<<"$sec15")"
nfind="$(grep -c 'data-feedback-kind="seam-finding"' <<<"$sec15" || true)"
if [[ "$nfind" -ge 3 ]]; then ok "seam example has $nfind findings"; else bad "seam example has $nfind findings (< 3, one per chip)"; fi
if [[ -n "$cites" ]] && ! grep -qvx 2 <<<"$cites"; then ok "every seam finding cites exactly two sides"; else bad "a seam finding does not cite both sides; per-finding cite counts: $(tr '\n' ' ' <<<"$cites")"; fi
# The comparison table: every row cites both sides too.
rows="$(grep -c 'class="sm-row"' <<<"$sec15" || true)"
rowcites="$({ grep 'class="sm-row"' <<<"$sec15" || true; } | awk '{ print gsub(/class="sm-cite"/, "&") }' | sort -u | tr '\n' ' ')"
if [[ "$rows" -ge 2 && "$rowcites" == "2 " ]]; then ok "every comparison row ($rows) cites both sides"; else bad "comparison rows: $rows, per-row cite counts: $rowcites"; fi

# --- 4. core registration ----------------------------------------------------
if grep -qE '^\| \*\*seam\*\* \|' "$CORE"; then ok "core §3 table lists the seam block"; else bad "core §3 table has no seam row"; fi
for id in 'seam-<contract-slug>' 'sf-<finding-slug>'; do
  if grep -qF "→ \`$id\`" "$CORE"; then ok "core §4 registers $id"; else bad "core §4 does not register $id"; fi
done
bad_ids="$(grep -oE 'data-feedback-id="[^"]*"' <<<"$sec15" | grep -vE '"(seam|sf)-[a-z0-9-]+"' || true)"
if [[ -z "$bad_ids" ]]; then ok "seam ids all take a registered seam-/sf- shape"; else bad "seam ids outside the registry: $bad_ids"; fi

# --- 5. skill pointer --------------------------------------------------------
for f in "$SKILL" "$CORE"; do
  if grep -q "visual-recap-design.md\` §$N\b" "$f"; then ok "$f points at design §$N"; else bad "$f does not point at design §$N"; fi
  stale="$(grep -n 'seam' "$f" | grep -oE 'visual-recap-design.md` §[0-9]+' | grep -v "§$N\$" || true)"
  if [[ -z "$stale" ]]; then ok "$f has no seam pointer at another section number"; else bad "$f points at the seam by a stale number: $stale"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
