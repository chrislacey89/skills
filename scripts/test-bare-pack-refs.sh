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
#   - every tracked file in a directory that has a SKILL.md, except the synced
#     copies scripts/skill-references.manifest writes into `<skill>/references/`
#     (each is checked at its canonical source instead) and `mermaid/references/`
#     (vendored upstream docs, not pack prose). A hand-written file under
#     `references/` is not a copy, so it is scanned where it lives; and
#   - every canonical source named in the manifest.
#
# Some numbers stay bare on purpose: illustrative samples, leverage-point ranks,
# and the sample content inside rendered mockups, where a ref numbers against
# whichever repo renders the sample. Each is an ALLOWLIST entry `path|literal`.
# An entry excuses only its own literal: every matching literal is deleted from
# the flagged line and the line is re-checked, so a second ref sharing the line
# is still caught. An entry that no longer matches any hit fails the suite, so
# the allowlist cannot quietly outlive the text it excuses.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok() { pass=$((pass + 1)); printf '  ok  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# A bare reference is either
#   - `#` plus two or more digits, not preceded by a word character (so
#     `chrislacey89/skills#N` and `issues#12` pass), `&` (HTML entity `&#39;`),
#     or `-`/`_` (identifiers). Single digits are list ordinals, not refs; or
#   - `PR#N` / `issue#N`, which the first form skips because a word character
#     precedes the `#`. Any digit count: `PR#3` is never an ordinal.
bare_ref_re='(^|[^A-Za-z0-9&_-])#[0-9]{2,}|(^|[^A-Za-z0-9])(PR|[Ii]ssue)#[0-9]+'

ALLOWLIST=$(cat <<'EOF'
compound/SKILL.md|RFC #42
execute/SKILL.md|- #41 declared
execute/SKILL.md|filed on #41.
pre-merge/SKILL.md|| filed | #199 — operator |
pre-merge/SKILL.md|in the Skill Kit repo, issue #190
prototype/FEASIBILITY.md|[#70 meta-glossary](https://github.com/chrislacey89/skills/issues/70)
triage-issue/SKILL.md|parameter-level fixes (#12) when a structural fix (#5–#3)
triage-issue/systems-reference.md|| #12 | Parameters |
triage-issue/systems-reference.md|| #11 | Buffers |
triage-issue/systems-reference.md|default to #12 (tweak a parameter) or #11 (add capacity)
docs/comment-craft.md|PRs #134 and #147
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

# Synced copies: `<skill>/references/<basename of source>` for each manifest row.
synced_copies() {
    grep -v '^[[:space:]]*#' scripts/skill-references.manifest |
        awk 'NF { n = split($1, p, "/"); print $2 "/references/" p[n] }'
}

population() {
    local d copies
    copies=$(synced_copies)
    for d in */; do
        [ -f "${d}SKILL.md" ] || continue
        git ls-files -- "$d" | grep -v '^mermaid/references/' |
            grep -vxF -- "$copies" || true
    done
    grep -v '^[[:space:]]*#' scripts/skill-references.manifest | awk 'NF { print $1 }'
}

# Print each bare ref in $3 (default stdin) that no ALLOWLIST entry for path $1
# excuses, as `lineno: excerpt`. Matched entries are appended to the file $2.
unexcused_hits() {
    local file="$1" used_log="$2" hit lineno line entry apath alit
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        lineno="${hit%%:*}"
        line="${hit#*:}"
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            apath="${entry%%|*}"
            alit="${entry#*|}"
            if [ "$apath" = "$file" ] && [[ "$line" == *"$alit"* ]]; then
                line="${line//"$alit"/}"
                printf '%s\n' "$entry" >>"$used_log"
            fi
        done <<<"$ALLOWLIST"
        if grep -qE "$bare_ref_re" <<<"$line"; then
            printf '%s: %s\n' "$lineno" "$(grep -oE ".{0,40}($bare_ref_re).{0,10}" <<<"$line" | head -1)"
        fi
    done < <(grep -InE "$bare_ref_re" -- "${3:-/dev/stdin}" || true)
}

# Skill dirs with a SKILL.md that the file list on stdin does not cover.
uncovered_skills() {
    comm -23 <(git ls-files -- '*/SKILL.md' | sort) <(grep '/SKILL\.md$' | sort)
}

# --- detector self-check: prove the regex fires on what it should, so a green
# run below means "no bare refs" rather than "a regex that matches nothing".
section "detector"
for s in '(#227)' 'see #190.' '#128/#129' 'issue #322)' '([#94])'; do
    if grep -qE "$bare_ref_re" <<<"$s"; then ok "flags: $s"; else bad "misses: $s"; fi
done
for s in 'see PR#452' '(issue#7)' 'Issue#12'; do
    if grep -qE "$bare_ref_re" <<<"$s"; then ok "flags: $s"; else bad "misses: $s"; fi
done
for s in 'chrislacey89/skills#227' '&#39;' 'color: #fff' 'step #1' 'a-#12' 'issues/70' 'issues#12' 'chrislacey89/skills#452'; do
    if grep -qE "$bare_ref_re" <<<"$s"; then bad "false positive: $s"; else ok "ignores: $s"; fi
done
scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT
if [ -n "$(printf '%s\n' 'Rough sketch: RFC #42 (see #997) first.' | unexcused_hits compound/SKILL.md "$scratch")" ]; then
    ok "an allowlist entry does not excuse a second ref on its line"
else
    bad "allowlist entry RFC #42 excused #997 sharing its line"
fi
if [ -z "$(printf '%s\n' 'Rough sketch: RFC #42 first.' | unexcused_hits compound/SKILL.md "$scratch")" ]; then
    ok "an allowlist entry excuses its own literal"
else
    bad "allowlist entry RFC #42 failed to excuse itself"
fi

section "population"
files=$(population | sort -u)
missing=$(uncovered_skills <<<"$files")
if [ -z "$missing" ]; then ok "every */SKILL.md is in scope"; else bad "skills out of scope: $(tr '\n' ' ' <<<"$missing")"; fi
# Mutation: drop one skill dir from the list and the coverage check must notice.
dropped=$(git ls-files -- '*/SKILL.md' | head -1 || true)
if [ -n "$(grep -v "^${dropped%%/*}/" <<<"$files" | uncovered_skills)" ]; then
    ok "coverage check fires when ${dropped%%/*}/ is dropped"
else
    bad "coverage check stayed green with ${dropped%%/*}/ dropped"
fi
leaked=$(grep -xF -- "$(synced_copies)" <<<"$files" || true; grep '^mermaid/references/' <<<"$files" || true)
if [ -z "$leaked" ]; then ok "no synced copy or vendored doc in scope"; else bad "excluded files in scope: $(tr '\n' ' ' <<<"$leaked")"; fi
# A hand-written references/ file must be scanned: plant a ref in each and
# confirm it is flagged. An empty set would make this section vacuous.
handwritten=$(grep '/references/' <<<"$files" || true)
if [ -n "$handwritten" ]; then
    while IFS= read -r f; do
        if [ -n "$({ cat "$f"; echo 'See #999.'; } | unexcused_hits "$f" "$scratch")" ]; then
            ok "planted ref flagged in $f"
        else
            bad "planted ref passed in $f"
        fi
    done <<<"$handwritten"
else
    bad "no hand-written references/ file in scope"
fi

section "bare pack references"
used_log=$(mktemp)
trap 'rm -f "$scratch" "$used_log"' EXIT
unexpected=0
while IFS= read -r file; do
    [ -f "$file" ] || continue
    while IFS= read -r flagged; do
        [ -n "$flagged" ] || continue
        unexpected=$((unexpected + 1))
        bad "$file:$flagged"
    done < <(unexcused_hits "$file" "$used_log" "$file")
done <<<"$files"
[ "$unexpected" -eq 0 ] && ok "no unqualified pack references outside the allowlist"
used=$(cat "$used_log")

section "allowlist is not stale"
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    if grep -qxF -- "$entry" <<<"$used"; then ok "used: $entry"; else bad "stale allowlist entry: $entry"; fi
done <<<"$ALLOWLIST"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
