#!/usr/bin/env bash
# test-skill-arg-substitution.sh — no SKILL.md body may contain a bare `$N`
# (a dollar sign followed by a single digit).
#
# THE DRIFT CLASS. When a skill is invoked with arguments (`/prd-to-issues 42`,
# `/fix-findings 1 3`), Claude Code's skill loader replaces `$0` with the first
# argument, `$1` with the second, and so on: `$N` is shorthand for
# `$ARGUMENTS[N]` (https://code.claude.com/docs/en/skills). It does this
# everywhere in the body, inside fenced bash and awk blocks too. The file on
# disk stays correct, so the bug shows only in the text the agent loads, and
# no check that reads the file can see it.
#
# THE INCIDENT. prd-to-issues' slice reconcile block read the `## Blocked by`
# section with `awk '/^## /{on = ($0 ~ /^## Blocked by.../); next} on'`. Invoked
# with an argument, `$0` became e.g. `ITEM-9`, which awk parses as `ITEM - 9`,
# so the section always read as empty, with no error. Every slice with blockers
# then reported MISMATCH, and every slice without blockers passed.
#
# THE MECHANISM. Measured against Claude Code 2.1.318 with a probe skill:
# `$0` and `$1` were replaced, while `$(1)`, `${1}`, `$ 0`, `$NF` and `$10` were
# left as written. So awk field references are spelled `$(N)` (POSIX awk: a
# field expression), and shell positional parameters `${N}`. This suite fails
# on any bare `$<digit>` that is not followed by another digit, so a prose
# price like `$50` passes. `\$0` is not used as an escape: the probe could not
# show whether the loader strips the backslash in every case, and if one
# survives into awk, awk rejects it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
while IFS= read -r hit; do
  echo "FAIL: bare \$N in a skill body (the skill loader rewrites it to an argument): $hit" >&2
  fail=1
done < <(git ls-files -- '*/SKILL.md' | xargs grep -nE '\$[0-9]([^0-9]|$)' || true)

# Mutation check: the pattern must still catch the incident's own line, or a
# future edit to the regex could turn this suite into a pass-everything no-op.
# shellcheck disable=SC2016 # the $0 is the literal under test
probe='awk '"'"'/^## /{on = ($0 ~ /^## Blocked by/); next} on'"'"''
if ! grep -qE '\$[0-9]([^0-9]|$)' <<<"$probe"; then
  echo "FAIL: the detector no longer matches the incident's own awk line" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "Spell awk fields \$(N) and shell positional parameters \${N}. See this file's header." >&2
  exit 1
fi
echo "PASS: no bare \$N in any SKILL.md body"
