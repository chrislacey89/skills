#!/usr/bin/env bash
# test-compound-clustering-single-source.sh — single-source contract test for
# /compound Phase 4's defect clustering rule.
#
# THE DRIFT CLASS. /compound Phase 4 owns the rule that decides whether a
# recurring lesson becomes prose or a mechanism. SYSTEM-OVERVIEW.md summarizes
# every skill, and scripts/skill-references.manifest bundles it into four more
# `references/` copies. A restatement of the rule in that summary is therefore a
# rule maintained by hand in six places, with nothing constructing the agreement
# — which is precisely
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md,
# whose Prevention section says: "Adopt this whenever prose claims cross-file
# agreement. The assertion and the test should be added in the same change."
#
# THE INCIDENT. In PR #259 (issue #257) the rule changed in compound/SKILL.md
# and SYSTEM-OVERVIEW.md:207 kept saying "Flags systemic defect patterns when 3+
# solutions share the same root cause" — stale in both halves. Review caught it.
# The corrective sweep then MISSED A SIXTH COPY in vite-project/src/data/
# workflow-data.js, and the changelog entry written to narrate that very lesson
# asserted "with one copy left there is nothing to pin" — false when written.
# Six instances of this family are now on record and #208 tracks consolidating
# the four oldest. Careful reading is not the mechanism; this file is.
#
# WHAT IT PINS. Two properties, both extracted from the real files rather than
# restated here:
#
#   1. The retired phrasings appear in no tracked file except CHANGELOG.md,
#      which quotes them deliberately as history.
#   2. compound/SKILL.md is the ONLY file stating the rule's threshold. Every
#      other mention must be a reference by name, which a reader cannot rebuild
#      the rule from — the distinction by-construction-…-2026-08-11.md draws
#      under "referring and restating are not a clean binary."
#
# Deliberately NOT pinned: the rule's wording. Pinning prose would force a false
# uniformity and the suite would be deleted the first time someone legitimately
# reworded it. Only single-sourcing is pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

compound_skill="compound/SKILL.md"
overview="SYSTEM-OVERVIEW.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

# Tracked files only, and never CHANGELOG.md — the changelog quotes retired
# phrasings on purpose, as the record of what changed and why.
tracked_except_changelog() {
    git ls-files -- ':!CHANGELOG.md'
}

if [ ! -f "$compound_skill" ]; then
    printf 'FATAL: %s not found. Either the skill moved or this suite is stale.\n' "$compound_skill" >&2
    exit 2
fi

# -----------------------------------------------------------------------------
section "the retired phrasings are gone from every tracked file but CHANGELOG.md"

# Each of these was a live restatement of the pre-#257 rule at some point. They
# are listed as literal strings because they are HISTORY — fixed text that will
# never legitimately reappear — not as a restatement of the current rule.
retired=(
    '3+ solutions share the same root cause'
    '3+ entries in the same category'
    'systemic issue worth noting in the solution'
    'systemic patterns when 3+'
    'Flags systemic defect patterns'
)

for phrase in "${retired[@]}"; do
    hits="$(tracked_except_changelog | xargs -r grep -l -F -- "$phrase" 2>/dev/null || true)"
    if [ -z "$hits" ]; then
        ok "retired phrasing absent: \"$phrase\""
    else
        bad "retired phrasing still present: \"$phrase\"" "in: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done

# -----------------------------------------------------------------------------
section "compound/SKILL.md is the single source of the clustering rule"

# Extract the rule's own paragraph from the skill, so the suite reads the real
# text rather than carrying a copy of it.
rule_para="$(grep -n 'Defect clustering check' "$compound_skill" | head -1 || true)"
if [ -z "$rule_para" ]; then
    printf 'FATAL: no "Defect clustering check" found in %s.\n' "$compound_skill" >&2
    printf '       The rule moved or was renamed; update this suite with it.\n' >&2
    exit 2
fi
ok "compound/SKILL.md still declares the rule ($(printf '%s' "$rule_para" | cut -d: -f1):)"

# No other tracked file may declare it. A file that names "/compound Phase 4"
# is referring; a file that contains "Defect clustering check" is restating.
others="$(tracked_except_changelog \
    | grep -v -x "$compound_skill" \
    | xargs -r grep -l -F -- 'Defect clustering check' 2>/dev/null || true)"
# scripts/ is allowed to name it — this suite must be able to describe what it pins.
others="$(printf '%s' "$others" | grep -v '^scripts/' || true)"
if [ -z "$others" ]; then
    ok "no other tracked file restates the rule by name"
else
    bad "the rule is restated outside compound/SKILL.md" "in: $(printf '%s' "$others" | tr '\n' ' ')"
fi

# -----------------------------------------------------------------------------
section "SYSTEM-OVERVIEW.md refers to the rule instead of restating it"

if [ -f "$overview" ]; then
    if grep -q -F 'defect clustering check' "$overview"; then
        # It mentions the rule — so it must point at the owner by name, and must
        # not carry a threshold of its own.
        if grep -q -F '/compound` Phase 4' "$overview"; then
            ok "SYSTEM-OVERVIEW.md points at /compound Phase 4 by name"
        else
            bad "SYSTEM-OVERVIEW.md mentions the rule without naming /compound Phase 4" \
                "reference by name forces the reader to the source; partial enumeration does not"
        fi
        # A digit adjacent to the mention is the shape a restated threshold takes.
        if grep -F 'defect clustering check' "$overview" | grep -qE '[0-9]\+? (or more )?(solutions|entries)'; then
            bad "SYSTEM-OVERVIEW.md carries its own threshold for the rule" \
                "the threshold belongs only to compound/SKILL.md"
        else
            ok "SYSTEM-OVERVIEW.md carries no threshold of its own"
        fi
    else
        ok "SYSTEM-OVERVIEW.md does not mention the rule at all (also single-sourced)"
    fi
else
    bad "SYSTEM-OVERVIEW.md not found" "expected at repo root"
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
