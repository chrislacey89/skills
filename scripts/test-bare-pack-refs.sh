#!/usr/bin/env bash
# test-bare-pack-refs.sh — every reference to this pack's own issues and PRs in a
# file that ships with the pack is written `chrislacey89/skills#N`, never bare.
#
# Skills run inside downstream repos. There a bare `#227` resolves against the
# downstream tracker, so a provenance marker or a "see #190" lands on an
# unrelated issue, or on nothing, and the reader cannot tell. Two hand sweeps
# fixed this (#421 for one reference, #433 for every */SKILL.md) and nothing
# stopped the next one; #435 found more in bundled docs and companion files
# that the SKILL.md-only sweep never looked at.
#
# Population, derived rather than listed:
#   - every tracked file in a directory that has a SKILL.md, except
#     `*/references/*` (bundled copies are checked at their canonical source
#     below; mermaid's vendored upstream docs are not pack prose), and
#   - every canonical source named in scripts/skill-references.manifest.
#
# Some numbers stay bare on purpose: illustrative samples, leverage-point ranks,
# and mockup content rendered from a downstream repo's point of view. Each is
# an ALLOWLIST entry `path|literal`, where the literal must appear on the
# flagged line. An entry that no longer matches any hit fails the suite, so the
# allowlist cannot quietly outlive the text it excuses.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok() { pass=$((pass + 1)); printf '  ok  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# A bare reference: `#` plus two or more digits, not preceded by a word
# character (so `chrislacey89/skills#N` and `issues#12` pass), `&` (HTML entity
# `&#39;`), or `-`/`_` (identifiers). Single digits are list ordinals, not refs.
bare_ref_re='(^|[^A-Za-z0-9&_-])#[0-9]{2,}'

ALLOWLIST=$(cat <<'EOF'
compound/SKILL.md|RFC #42
execute/SKILL.md|- #41 declared
pre-merge/SKILL.md|| filed | #199 — operator |
pre-merge/SKILL.md|in the Skill Kit repo, issue #190
prototype/FEASIBILITY.md|[#70 meta-glossary](https://github.com/chrislacey89/skills/issues/70)
triage-issue/SKILL.md|parameter-level fixes (#12) when a structural fix (#5–#3)
triage-issue/systems-reference.md|| #12 | Parameters |
triage-issue/systems-reference.md|| #11 | Buffers |
triage-issue/systems-reference.md|default to #12 (tweak a parameter) or #11 (add capacity)
docs/writing-for-humans.md|Closes #27.
docs/visual-recap-design.md|(so `#23` breaks
docs/visual-recap-design.md|the ref, not the branch name (#298)
docs/visual-recap-design.md|Revert, close #238 wontfix
docs/visual-recap-design.md|Widens the PR past #238's declared
docs/visual-recap-design.md|Reinstates the reason #239 just demoted
docs/visual-recap-design.md|#245 verdict:
docs/visual-recap-design.md|#317 Mediator verdict
docs/visual-recap-design.md|#317 revision comment
docs/visual-recap-design.md|PR #297 · closes #293
docs/visual-recap-design.md|CONTEXT · ISSUE #293
EOF
)

population() {
    local d
    for d in */; do
        [ -f "${d}SKILL.md" ] || continue
        git ls-files -- "$d" | grep -v '/references/' || true
    done
    grep -v '^[[:space:]]*#' scripts/skill-references.manifest | awk 'NF { print $1 }'
}

# --- detector self-check: prove the regex fires on what it should, so a green
# run below means "no bare refs" rather than "a regex that matches nothing".
section "detector"
for s in '(#227)' 'see #190.' '#128/#129' 'issue #322)' '([#94])'; do
    if grep -qE "$bare_ref_re" <<<"$s"; then ok "flags: $s"; else bad "misses: $s"; fi
done
for s in 'chrislacey89/skills#227' '&#39;' 'color: #fff' 'step #1' 'a-#12' 'issues/70'; do
    if grep -qE "$bare_ref_re" <<<"$s"; then bad "false positive: $s"; else ok "ignores: $s"; fi
done

section "population"
files=$(population | sort -u)
n=$(grep -c . <<<"$files" || true)
if [ "$n" -gt 50 ]; then ok "$n shipped files in scope"; else bad "population suspiciously small ($n files)"; fi

section "bare pack references"
used=""
unexpected=0
while IFS= read -r file; do
    [ -f "$file" ] || continue
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        line="${hit#*:}"
        allowed=""
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            apath="${entry%%|*}"
            alit="${entry#*|}"
            if [ "$apath" = "$file" ] && [[ "$line" == *"$alit"* ]]; then
                allowed="$entry"
                break
            fi
        done <<<"$ALLOWLIST"
        if [ -n "$allowed" ]; then
            used+="$allowed"$'\n'
        else
            unexpected=$((unexpected + 1))
            bad "$file:${hit%%:*}: $(printf '%s' "$line" | grep -oE ".{0,40}$bare_ref_re.{0,10}" | head -1)"
        fi
    done < <(grep -InE "$bare_ref_re" -- "$file" || true)
done <<<"$files"
[ "$unexpected" -eq 0 ] && ok "no unqualified pack references outside the allowlist"

section "allowlist is not stale"
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if grep -qxF -- "$entry" <<<"$used"; then ok "used: $entry"; else bad "stale allowlist entry: $entry"; fi
done <<<"$ALLOWLIST"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
