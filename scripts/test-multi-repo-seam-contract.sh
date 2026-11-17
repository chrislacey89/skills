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
#      three dots, an empty repo path), names a ref its repository does not
#      have, or has no merge base, and when given fewer than two scopes or the
#      unfilled placeholders. Both checks run under bash and zsh.
#   3. The design's seam section exists, carries the three finding chips, and every finding in
#      its example cites both sides.
#   4. Core §3 lists the seam block and core §4 registers its two id shapes, and
#      the design example uses exactly those shapes.
#   5. SKILL.md and core point at the seam section by the number its heading
#      carries, so a renumber at merge time that misses a pointer fails here.
#   6. SKILL.md and the design header name Part I's range up to the last
#      numbered section the design actually has.

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

# The block opens with a `set -- "<placeholder>" …` line that the agent fills in;
# a pasted block has no argv. The suite fills that one line by substitution, the
# way the agent does, and never passes argv, so a block that went back to
# reading "$@" from its caller would run on the placeholders and fail here.
SET_LINE='set -- "<repo-path>@<base>..<head>" "<repo-path>@<base>..<head>"'
if grep -qxF "$SET_LINE" <<<"$block"; then ok "the block opens its scopes with a placeholder set -- line"; else bad "the block has no '$SET_LINE' line to fill in"; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
gc() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
mkrepo() { # mkrepo <dir> <base-ref> <head-ref> <file> <base-line> <head-line>
  git init -q -b "$2" "$1"
  gc "$1" commit -q --allow-empty -m root
  printf '%s\n' "$5" >"$1/$4"
  git -C "$1" add "$4"
  gc "$1" commit -q -m "base $4"
  git -C "$1" checkout -q -b "$3"
  printf '%s\n%s\n' "$5" "$6" >"$1/$4"
  gc "$1" commit -q -am "feature touches $4"
}
# Different ref names per repo, so a block that reused one scope's range for
# every scope fails to resolve instead of passing by coincidence.
mkrepo "$work/caller" main feat-web caller.ts 'send(status)' "send('CANCELED')"
mkrepo "$work/service" develop feat-billing service.php 'accept($status)' "accept('cancelled')"
# Base moves on after the feature forks. A three-dot diff never shows this
# file; a two-dot diff reports it as deleted on the feature side.
git -C "$work/service" checkout -q develop
printf 'later\n' >"$work/service/late-base.txt"
git -C "$work/service" add late-base.txt
gc "$work/service" commit -q -m "base moves on"
git -C "$work/service" checkout -q feat-billing
# A branch with no history in common with main: no merge base.
git -C "$work/caller" checkout -q --orphan unrelated
gc "$work/caller" commit -q --allow-empty -m unrelated
git -C "$work/caller" checkout -q feat-web

fill() { # fill <scopes...> -> the block with its set -- line filled in
  local args="set --" a
  for a in "$@"; do args+=" $(printf '%q' "$a")"; done
  SET="$args" awk -v want="$SET_LINE" '$0 == want { print ENVIRON["SET"]; next } { print }' <<<"$block"
}
SHELL_UNDER_TEST=bash
run_block() { "$SHELL_UNDER_TEST" -c "$(fill "$@")"; }

check_valid() {
  local sh="$SHELL_UNDER_TEST" out rc expect got
  out="$(run_block "$work/caller@main..feat-web" "$work/service@develop..feat-billing" 2>&1)" && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then ok "[$sh] two valid scopes exit 0"; else bad "[$sh] two valid scopes exited $rc: $out"; fi
  # Each scope's own file, in order, under its own header.
  expect="== scope: $work/caller @ main...feat-web
 caller.ts | 1 +
== scope: $work/service @ develop...feat-billing
 service.php | 1 +"
  got="$(grep -E '^== scope:|\| [0-9]+ ' <<<"$out" || true)"
  if [[ "$got" == "$expect" ]]; then ok "[$sh] each scope prints its own diff-stat, from its own repo, in order"; else bad "[$sh] scope stats wrong; got:
$got"; fi
  if grep -q 'late-base.txt' <<<"$out"; then bad "[$sh] base-side work after the fork shows in a scope's stat (a two-dot diff)"; else ok "[$sh] base-side work after the fork stays out of the stat (three-dot)"; fi
  if grep -qx '[0-9a-f]\{7,\} feature touches caller.ts' <<<"$out" && grep -qx '[0-9a-f]\{7,\} feature touches service.php' <<<"$out"; then
    ok "[$sh] each scope prints its own commit log"
  else
    bad "[$sh] a scope's commit log is missing"
  fi
  if grep -q 'base caller.ts\|base service.php' <<<"$out"; then bad "[$sh] a log line from before the base leaked into a scope"; else ok "[$sh] logs stop at each scope's base"; fi
  # A head ref containing `@` splits at the first `@` only.
  out="$(run_block "$work/caller@main..feat-web@{0}" "$work/service@develop..feat-billing" 2>&1)" && rc=0 || rc=$?
  if [[ $rc -eq 0 ]] && grep -qx " caller.ts | 1 +" <<<"$out"; then ok "[$sh] a head ref containing @ splits at the first @"; else bad "[$sh] head ref feat-web@{0} (exit $rc): $out"; fi
  # A relative repo path resolves from where the block runs.
  out="$(cd "$work/caller" && run_block "../caller@main..feat-web" "../service@develop..feat-billing" 2>&1)" && rc=0 || rc=$?
  if [[ $rc -eq 0 ]] && grep -qx " service.php | 1 +" <<<"$out"; then ok "[$sh] relative ../ repo paths resolve"; else bad "[$sh] relative ../ scopes (exit $rc): $out"; fi
}

refuses() { # refuses <label> <args...>
  local label="$1"; shift
  local o r
  o="$(run_block "$@" 2>&1)" && r=0 || r=$?
  if [[ $r -ne 0 ]] && ! grep -q '^== scope:' <<<"$o"; then ok "[$SHELL_UNDER_TEST] refuses $label, printing no scope"; else bad "[$SHELL_UNDER_TEST] did not refuse $label cleanly (exit $r): $o"; fi
}
check_refusals() {
  local c="$work/caller@main..feat-web"
  refuses "a head ref the repo does not have" "$c" "$work/service@develop..nope"
  refuses "a base ref the repo does not have" "$c" "$work/service@nope..feat-billing"
  refuses "three dots" "$c" "$work/service@develop...feat-billing"
  refuses "a scope with no @" "$c" "$work/service"
  refuses "a relative path with no @" "$c" "../service"
  refuses "an empty endpoint" "$c" "$work/service@..feat-billing"
  # Run from inside the service repo: `git -C ""` means the current directory,
  # so only the empty-path check stops this scope from diffing.
  local o r
  o="$(cd "$work/service" && run_block "$c" "@develop..feat-billing" 2>&1)" && r=0 || r=$?
  if [[ $r -ne 0 ]] && ! grep -q '^== scope:' <<<"$o"; then ok "[$SHELL_UNDER_TEST] refuses an empty repo path, printing no scope"; else bad "[$SHELL_UNDER_TEST] did not refuse an empty repo path cleanly (exit $r): $o"; fi
  refuses "a range with no merge base" "$c" "$work/caller@unrelated..feat-web"
  refuses "a single scope" "$c"
  refuses "the unfilled placeholders" "<repo-path>@<base>..<head>" "<repo-path>@<base>..<head>"
  # The unfilled block itself: no substitution at all.
  o="$("$SHELL_UNDER_TEST" -c "$block" 2>&1)" && r=0 || r=$?
  if [[ $r -ne 0 ]] && ! grep -q '^== scope:' <<<"$o"; then ok "[$SHELL_UNDER_TEST] the block as pasted refuses its placeholders"; else bad "[$SHELL_UNDER_TEST] the block as pasted did not refuse (exit $r): $o"; fi
}

check_valid
check_refusals
# The agent's shell is often zsh (macOS default). validate-skills.yml installs
# it in CI; locally it is usually present. Skip loudly when it is not.
if command -v zsh >/dev/null 2>&1; then
  SHELL_UNDER_TEST=zsh
  check_valid
  check_refusals
  SHELL_UNDER_TEST=bash
else
  printf 'SKIP zsh is not installed; the block ran under bash only\n'
fi

# --- 3. design: the seam block ----------------------------------------------
N="$(sed -nE 's/^## ([0-9]+)\. Block: seam.*/\1/p' "$DESIGN" | head -1 || true)"
secN=""
[[ -n "$N" ]] && secN="$(awk -v h="^## $N\\. Block: seam" '$0 ~ h {on=1; print; next} on&&/^## /{exit} on' "$DESIGN")"
if [[ -n "$secN" ]]; then ok "design has §$N Block: seam"; else bad "design has no '## <n>. Block: seam' section"; fi
for chip in mismatch fragile planned; do
  if grep -q "class=\"sf-chip sf-$chip\"" <<<"$secN"; then ok "seam example renders a $chip chip"; else bad "seam example has no sf-$chip chip"; fi
done
# Every finding (data-feedback-kind="seam-finding") cites both sides: two
# .sf-cite spans inside it. Count per finding, not in sum.
cites="$(awk '
  /data-feedback-kind="seam-finding"/ { if (inf) print n; inf=1; n=0 }
  inf { n += gsub(/class="sf-cite"/, "&") }
  inf && /<!-- \/finding -->/ { print n; inf=0 }
  END { if (inf) print n }
' <<<"$secN")"
nfind="$(grep -c 'data-feedback-kind="seam-finding"' <<<"$secN" || true)"
if [[ "$nfind" -ge 3 ]]; then ok "seam example has $nfind findings"; else bad "seam example has $nfind findings (< 3, one per chip)"; fi
if [[ -n "$cites" ]] && ! grep -qvx 2 <<<"$cites"; then ok "every seam finding cites exactly two sides"; else bad "a seam finding does not cite both sides; per-finding cite counts: $(tr '\n' ' ' <<<"$cites")"; fi
# The comparison table: every row cites both sides too.
rows="$(grep -c 'class="sm-row"' <<<"$secN" || true)"
rowcites="$({ grep 'class="sm-row"' <<<"$secN" || true; } | awk '{ print gsub(/class="sm-cite"/, "&") }' | sort -u | tr '\n' ' ')"
if [[ "$rows" -ge 2 && "$rowcites" == "2 " ]]; then ok "every comparison row ($rows) cites both sides"; else bad "comparison rows: $rows, per-row cite counts: $rowcites"; fi

# --- 4. core registration ----------------------------------------------------
if grep -qE '^\| \*\*seam\*\* \|' "$CORE"; then ok "core §3 table lists the seam block"; else bad "core §3 table has no seam row"; fi
for id in 'seam-<contract-slug>' 'sf-<finding-slug>'; do
  if grep -qF "→ \`$id\`" "$CORE"; then ok "core §4 registers $id"; else bad "core §4 does not register $id"; fi
done
bad_ids="$(grep -oE 'data-feedback-id="[^"]*"' <<<"$secN" | grep -vE '"(seam|sf)-[a-z0-9-]+"' || true)"
if [[ -z "$bad_ids" ]]; then ok "seam ids all take a registered seam-/sf- shape"; else bad "seam ids outside the registry: $bad_ids"; fi

# --- 5. skill pointer --------------------------------------------------------
for f in "$SKILL" "$CORE"; do
  if grep -q "visual-recap-design.md\` §$N\b" "$f"; then ok "$f points at design §$N"; else bad "$f does not point at design §$N"; fi
  stale="$(grep -n 'seam' "$f" | grep -oE 'visual-recap-design.md` §[0-9]+' | grep -v "§$N\$" || true)"
  if [[ -z "$stale" ]]; then ok "$f has no seam pointer at another section number"; else bad "$f points at the seam by a stale number: $stale"; fi
done

# --- 6. Part I's range ends at the last numbered section ----------------------
# SKILL.md and the design header both say "Part I (§1–§<n>)". It read §1–§12
# after §13–§16 landed, because nothing checked it when a section was added.
last="$(sed -nE 's/^## ([0-9]+)\. .*/\1/p' "$DESIGN" | sort -n | tail -1)"
# coverage: enumerated — the two files that state Part I's range (rg '§1–§[0-9]').
for f in "$SKILL" "$DESIGN"; do
  ranges="$(grep -oE 'Part I[^§]{0,40}§1–§[0-9]+|§1–§[0-9]+ is \*\*Part I' "$f" | grep -oE '§1–§[0-9]+' | sort -u || true)"
  if [[ -n "$ranges" && "$ranges" == "§1–§$last" ]]; then ok "$f names Part I as §1–§$last"; else bad "$f names Part I as [$(tr '\n' ' ' <<<"$ranges")], but the last numbered section is §$last"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
