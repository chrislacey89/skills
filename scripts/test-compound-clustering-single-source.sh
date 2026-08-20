#!/usr/bin/env bash
# test-compound-clustering-single-source.sh — single-source contract test for
# /compound Phase 4's defect clustering rule.
#
# THE DRIFT CLASS. /compound Phase 4 owns the rule deciding whether a recurring
# lesson becomes prose or a mechanism. SYSTEM-OVERVIEW.md summarizes every
# skill, and scripts/skill-references.manifest bundles it into four more
# `references/` copies. A restatement of the rule in that summary is a rule
# maintained by hand in six places with nothing constructing the agreement —
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md,
# whose Rule Scope invert clause ("the claim is about the repo's own code →
# write the test") is what puts this suite in scope, not its Prevention text.
#
# THE INCIDENTS, all three of which this suite is mutation-tested against:
#   1. PR #259 changed the rule in compound/SKILL.md and left
#      SYSTEM-OVERVIEW.md:207 restating the old threshold. Review caught it.
#   2. The corrective sweep then missed a copy in vite-project/src/data/
#      workflow-data.js. A second review pass caught that.
#   3. The FIRST DRAFT OF THIS FILE was red on a clean tree the moment it was
#      staged: its retired[] array holds the very phrases it forbids, and
#      `git ls-files` sees a tracked file but not an untracked one — so every
#      mutation run before `git add` passed and the suite had never once been
#      run after. A third review pass caught that. It is the seventh instance
#      of the family, inside the mechanism written to stop the sixth.
#
# Incident 3 is why the exclusion below is load-bearing rather than tidy, and
# why `check_self_visible` asserts the file list is real before trusting an
# empty grep. Run this suite AFTER staging, never only before.
#
# WHAT IT PINS, all extracted from the real files rather than restated here:
#   1. The retired phrasings appear in no tracked file (this suite and
#      CHANGELOG.md excepted — both quote them deliberately).
#   2. The rule is DECLARED in exactly one place. Declaration is the bold
#      heading `**Defect clustering check`; a prose mention in any case is a
#      REFERENCE and is allowed anywhere, because a reader cannot rebuild the
#      rule from a name. That is by-construction-…'s referring/restating line.
#   3. Every SYSTEM-OVERVIEW copy names `/compound` Phase 4 as the owner and
#      carries no threshold of its own.
#
# Deliberately NOT pinned: the rule's wording. Pinning prose would force a
# false uniformity and the suite would be deleted the first time someone
# legitimately reworded it. Only single-sourcing is pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

self="scripts/test-compound-clustering-single-source.sh"
compound_skill="compound/SKILL.md"

# The bold heading that constitutes a DECLARATION of the rule.
declaration_marker='**Defect clustering check'
# The anchor opening /compound's description in every SYSTEM-OVERVIEW copy.
overview_anchor='Captures what was learned into'
# What a restated threshold looks like: a number attached to a countable, or a
# "when/at N". Deliberately wording-agnostic — a restatement uses new words.
threshold_re='[0-9]+\+?[[:space:]]+(or more[[:space:]]+)?(solutions|entries|docs|files|records|lessons)|(when|at)[[:space:]]+[0-9]+\+?[[:space:]]'

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }

# Tracked files, minus the two that quote retired text on purpose. This suite
# excludes ITSELF (incident 3) — which means a genuine restatement pasted into
# this file would not be caught here. That is the accepted cost of letting the
# suite name what it forbids.
scan_files() {
    git ls-files -- ':!CHANGELOG.md' ":!$self"
}

if [ ! -f "$compound_skill" ]; then
    printf 'FATAL: %s not found. The skill moved, or this suite is stale.\n' "$compound_skill" >&2
    exit 2
fi

# -----------------------------------------------------------------------------
section "the file list is real (guards every empty-grep pass below)"

file_count="$(scan_files | wc -l | tr -d ' ')"
if [ "$file_count" -gt 20 ]; then
    ok "scan covers $file_count tracked files"
else
    bad "scan_files returned only $file_count paths" \
        "an empty or truncated list makes every 'absent' assertion below pass vacuously"
    printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi

# -----------------------------------------------------------------------------
section "the retired phrasings are gone from every scanned file"

# Literal HISTORY — fixed text that will never legitimately reappear. These
# cannot catch a NEW wording; check 3's threshold regex is what covers that.
retired=(
    '3+ solutions share the same root cause'
    '3+ entries in the same category'
    'systemic issue worth noting in the solution'
    'systemic patterns when 3+'
    'Flags systemic defect patterns'
)

for phrase in "${retired[@]}"; do
    hits="$(scan_files | xargs grep -l -F -- "$phrase" 2>/dev/null || true)"
    if [ -z "$hits" ]; then
        ok "retired phrasing absent: \"$phrase\""
    else
        bad "retired phrasing still present: \"$phrase\"" "in: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done

# -----------------------------------------------------------------------------
section "the rule is declared in exactly one file"

if ! grep -qF -- "$declaration_marker" "$compound_skill"; then
    printf 'FATAL: no "%s" heading in %s.\n' "$declaration_marker" "$compound_skill" >&2
    printf '       The rule moved or was renamed; update this suite with it.\n' >&2
    exit 2
fi
ok "compound/SKILL.md declares the rule"

declarers="$(scan_files | xargs grep -l -F -- "$declaration_marker" 2>/dev/null || true)"
extra_declarers="$(printf '%s\n' "$declarers" | grep -v -x -F "$compound_skill" | grep -v '^$' || true)"
if [ -z "$extra_declarers" ]; then
    ok "no other file declares it (prose references by name remain allowed)"
else
    bad "the rule is declared outside compound/SKILL.md" \
        "in: $(printf '%s' "$extra_declarers" | tr '\n' ' ')"
fi

# -----------------------------------------------------------------------------
section "every SYSTEM-OVERVIEW copy refers to the owner and states no threshold"

overviews="$(scan_files | grep 'SYSTEM-OVERVIEW\.md$' || true)"
if [ -z "$overviews" ]; then
    bad "no SYSTEM-OVERVIEW.md found in the scan" "expected the canonical plus four bundled copies"
else
    while IFS= read -r ov; do
        [ -n "$ov" ] || continue
        para="$(grep -F -- "$overview_anchor" "$ov" || true)"
        if [ -z "$para" ]; then
            # Non-vacuous: a missing anchor is a failure, not a silent pass.
            bad "$ov has no /compound description to check" \
                "anchor \"$overview_anchor\" not found — the summary was restructured; update this suite"
            continue
        fi
        # shellcheck disable=SC2016  # literal backticks, no expansion intended
        if printf '%s' "$para" | grep -qF -- '`/compound` Phase 4'; then
            ok "$ov names /compound Phase 4 as the owner"
        else
            bad "$ov describes /compound without naming Phase 4 as the rule's owner" \
                "reference by name forces a reader to the source; partial enumeration does not"
        fi
        if printf '%s' "$para" | grep -qE -- "$threshold_re"; then
            bad "$ov carries a threshold of its own" \
                "matched: $(printf '%s' "$para" | grep -oE -- "$threshold_re" | head -1)"
        else
            ok "$ov states no threshold"
        fi
    done <<< "$overviews"
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
