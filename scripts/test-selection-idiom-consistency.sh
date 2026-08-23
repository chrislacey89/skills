#!/usr/bin/env bash
# test-selection-idiom-consistency.sh — cross-file contract test for the
# "which slices are takeable" selection idiom.
#
# Five hand-maintained files decide what is unblocked: /prd-to-issues §9,
# /execute's Blocked-slice gate, /help's frontier call, /setup-ralph-loop's two
# FRONTIER copies, and SYSTEM-OVERVIEW.md's Ralph example. They read the same
# graph and are asserted in prose to "agree by construction rather than by
# coincidence" (help/SKILL.md, SYSTEM-OVERVIEW.md).
#
# Before this suite, nothing constructed that agreement. It was maintained by
# hand across all five, and the assertion is what stopped anyone from checking —
# see docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md,
# which was written after a false capability claim propagated to nine sites and
# survived a week.
#
# The suite extracts the real text from the real files rather than restating
# it. A hand-copied assertion drifts alongside the thing it tests; a suite that
# reads every occurrence fails precisely when they stop agreeing.
#
# Deliberately NOT asserted: that all occurrences are byte-identical. They are
# not, and should not be — §9 tests for an empty set, /execute projects
# {number, title}, /help projects .number. Only the parts that must agree are
# pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$label"
    else
        bad "$label" "$(printf 'expected: %q\n       got:      %q' "$expected" "$actual")"
    fi
}

# Files that hand-maintain the selection idiom. Bundled references/ copies are
# excluded on purpose — sync-skill-references.sh already pins those to
# SYSTEM-OVERVIEW.md, and including them here would test that suite instead.
selection_files=(
    prd-to-issues/SKILL.md
    execute/SKILL.md
    help/SKILL.md
    setup-ralph-loop/SKILL.md
    SYSTEM-OVERVIEW.md
)

# -----------------------------------------------------------------------------
section "the three FRONTIER copies are one script"

# ralph-once.sh and ralph.sh in /setup-ralph-loop, plus SYSTEM-OVERVIEW.md's
# worked example, are the same selection block at three indentation levels.
# Normalize leading whitespace and assert one distinct value.
frontier_blocks="$(
    # coverage: enumerated — the two files that restate the frontier-selection
    # idiom. Not derivable for the same reason: membership follows from which
    # documents make the claim, not from a pattern in the tree.
    for f in setup-ralph-loop/SKILL.md SYSTEM-OVERVIEW.md; do
        awk '/FRONTIER=\$\(gh issue list/{c=1}
             c{gsub(/^[ \t]+/,""); print}
             c && /join\(", "\)\x27\)/{print "###"; c=0}' "$f"
    done
)"

block_count="$(grep -c '^###$' <<<"$frontier_blocks" || true)"
assert_eq "3" "$block_count" "three FRONTIER blocks found"

distinct="$(awk 'BEGIN{RS="###\n"} NF{print}' <<<"$frontier_blocks" | sort -u | grep -c 'FRONTIER=' || true)"
assert_eq "1" "$distinct" "all FRONTIER blocks normalize to one value"

# -----------------------------------------------------------------------------
section "the blocker-state predicate is the uppercase GraphQL enum"

# `gh ... --json blockedBy` returns state as OPEN/CLOSED; the REST dependency
# endpoint returns open/closed. A jq filter copied between the two silently
# matches nothing — no error, just an empty result that reads as "unblocked".
lower_state="$(grep -n 'blockedBy' "${selection_files[@]}" | grep 'state == "open"' || true)"
if [[ -z "$lower_state" ]]; then
    ok "no lowercase .state == \"open\" alongside a blockedBy read"
else
    bad "lowercase state compared against a blockedBy read" "$lower_state"
fi

# Every file that filters blockedBy nodes by state must use OPEN.
for f in "${selection_files[@]}"; do
    if grep -q 'blockedBy.nodes' "$f"; then
        if grep -q 'state == "OPEN"' "$f" || grep -q 'blockedBy.totalCount' "$f"; then
            ok "$f filters or counts blockedBy nodes explicitly"
        else
            bad "$f reads blockedBy.nodes without a state filter or totalCount"
        fi
    fi
done

# -----------------------------------------------------------------------------
section "the retired REST-only claims stay retired"

# "gh issue list --json cannot see dependency data" was false when written and
# propagated to nine sites. `isBlocked` is the one field that genuinely does not
# exist, and the only legitimate mention is the sentence explaining that.
# Scoped to the skills and SYSTEM-OVERVIEW — the files that *instruct*. CHANGELOG
# and docs/solutions legitimately narrate the history of the false claim, and
# .context/ is gitignored scratch.
stray_isblocked="$(grep -n 'isBlocked' SYSTEM-OVERVIEW.md ./*/SKILL.md 2>/dev/null \
    | grep -v 'does not exist and is easily mistaken' || true)"
if [[ -z "$stray_isblocked" ]]; then
    ok "no skill asserts a capability limit via isBlocked"
else
    bad "isBlocked resurfaced outside its one explanatory mention" "$stray_isblocked"
fi

# -----------------------------------------------------------------------------
section "cross-skill references point at headings that exist"

# A reference like "/qa Step 4b" couples one skill to another's *numbering*.
# This repo renumbered /qa's Step 4 sequence once already, in the same PR that
# introduced such a reference, so the coupling is not hypothetical.
# The skill name and the step number must be ADJACENT to count as a reference.
# Matching "any /skill on the line + any Step N on the line" produces false
# positives: setup-ralph-loop:207 mentions /execute and, later in the same
# sentence, "(Step 8 below)" — an internal reference to its own Step 8.
bad_refs=""
# shellcheck disable=SC2016  # backticks below are literal markdown, not expansion
while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    skill="$(sed -E 's@^`/([a-z-]+)` Step .*@\1@' <<<"$pair")"
    step="$(sed -E 's@^.* Step ([0-9]+[a-z]?)$@\1@' <<<"$pair")"
    target="$skill/SKILL.md"
    if [ ! -f "$target" ]; then
        bad_refs="$bad_refs  reference to /$skill, but $target does not exist"$'\n'
        continue
    fi
    # Step headings are "### N. Title"; sub-steps are "#### Na. Title".
    if ! grep -qE "^#+ *${step}\." "$target"; then
        bad_refs="$bad_refs  \"/$skill Step $step\" — no such heading in $target"$'\n'
    fi
done < <(grep -rho '`/[a-z-]\+` Step [0-9]\+[a-z]\?' ./*/SKILL.md 2>/dev/null | sort -u || true)

if [[ -z "$bad_refs" ]]; then
    ok "every cross-skill Step reference resolves"
else
    bad "cross-skill Step reference does not resolve" "$bad_refs"
fi

# -----------------------------------------------------------------------------
section "the by-construction claim is backed by this suite"

# The prose assertion and its enforcement must ship together. If a file claims
# the selection sites agree by construction, this suite is what constructs it —
# so the claim's presence implies this file's presence, and vice versa.
claim_files="$(grep -rln 'agree by construction' --include='*.md' . | grep -v '^\./CHANGELOG.md$' || true)"
if [[ -n "$claim_files" ]]; then
    ok "the 'agree by construction' claim is present and enforced by this suite"
else
    bad "no file claims agreement — if the claim was removed, remove this suite too"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
