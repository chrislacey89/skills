#!/usr/bin/env bash
# test-context-block-contract.sh — cross-skill contract test for the
# `### Context` block on AFK slice issues.
#
# /prd-to-issues §4's context completeness check DEFINES the slots an AFK slice
# must carry. The same skill's issue template RENDERS those slots as the block
# an author fills in. /execute Step 1 READS the block back before its
# docs/solutions/ grep. Three sites, one structure, and no shared definition of
# it — the same drift class scripts/test-review-currency-marker.sh was written
# for, one seam over.
#
# The failure this prevents is quiet on both sides. A slot added to the check
# but not the template asks authors for a field the artifact has no room for;
# a slot renamed in the template but not the check leaves /execute reading for
# a heading nobody writes. Neither breaks a parser, because there is no parser
# — the block is read by an agent, which will cheerfully proceed on a partial
# match and produce a plausible wrong answer.
#
# /prd-to-issues §7 already carries the rule this test implements, citing
# Martraire (Living Documentation Ch. 3) on unavoidably redundant knowledge:
# establish a reconciliation mechanism rather than declaring one copy
# authoritative. This is that mechanism for the Context block.
#
# The assertions EXTRACT both lists from prd-to-issues/SKILL.md rather than
# restating either. A hand-copied list here would be a fourth copy of the thing
# under test, and would drift in exactly the way the test exists to catch.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
prd_skill="$repo_root/prd-to-issues/SKILL.md"
execute_skill="$repo_root/execute/SKILL.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %q\n       got:      %q\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       missing: %q\n' "$label" "$needle"
        fail=$((fail + 1))
    fi
}

# --- extraction -------------------------------------------------------------
#
# Check slots: the bold labels on the bullet list that follows the check's
# "must contain, or explicitly declare empty:" lead-in. Stop at the first blank
# line after the list starts, so later prose cannot leak in.
extract_check_slots() {
    awk '
        /must contain, or explicitly declare empty:/ { collecting = 1; next }
        collecting && /^- \*\*/ {
            started = 1
            line = $0
            sub(/^- \*\*/, "", line)
            sub(/\*\*.*$/, "", line)
            print line
            next
        }
        started && !/^- \*\*/ { exit }
    ' "$prd_skill"
}

# Template slots: the bold labels inside the issue template's `### Context`
# block. Deduplicated — the template deliberately shows two Anchors bullets to
# demonstrate that the slot repeats.
extract_template_slots() {
    awk '
        /^### Context$/ { collecting = 1; next }
        collecting && /^## / { exit }
        collecting && /^- \*\*/ {
            line = $0
            sub(/^- \*\*/, "", line)
            sub(/:?\*\*.*$/, "", line)
            print line
        }
    ' "$prd_skill" | awk '!seen[$0]++'
}

section "check and template define the same slots"

check_slots="$(extract_check_slots)"
template_slots="$(extract_template_slots)"

assert_eq "Anchors
Gotchas
Research" "$check_slots" "§4 check defines the expected three slots"

assert_eq "$check_slots" "$template_slots" \
    "issue template renders exactly the slots the check requires"

section "the empty declarations match on both sides"

# A slot the author has nothing for must be declared, not dropped. The exact
# strings matter: the check tells the author what to write, the template shows
# it, and a mismatch means the check asks for a line the template never models.
prd_body="$(cat "$prd_skill")"

for declaration in 'Greenfield — no existing pattern to follow.' 'None known.'; do
    occurrences="$(grep -c -- "$declaration" "$prd_skill" || true)"
    if [[ "$occurrences" -ge 2 ]]; then
        printf '  ok   %q appears in both the check and the template\n' "$declaration"
        pass=$((pass + 1))
    else
        printf '  FAIL %q appears %s time(s); expected it in both the check and the template\n' \
            "$declaration" "$occurrences"
        fail=$((fail + 1))
    fi
done

section "the reader knows the heading the writer emits"

assert_contains "$prd_body" '### Context' \
    "prd-to-issues names the block heading"
assert_contains "$(cat "$execute_skill")" '### Context' \
    "execute Step 1 reads the same heading"

# /execute must read the block BEFORE the general docs/solutions/ grep — that
# ordering is the whole reason the block is worth writing, and it is the row
# issue #200 promoted from optional to required.
#
# Anchor on the Step 1 instruction itself, not on any mention of the heading.
# /execute also names `### Context` in its Invocation Position, which sits far
# above the grep and would satisfy a naive first-match comparison no matter
# where the real instruction moved to.
step1_lead="Read the slice's \`### Context\` block before the grep below"
context_line="$(grep -n -- "$step1_lead" "$execute_skill" | head -1 | cut -d: -f1 || true)"
# shellcheck disable=SC2016  # the backticks are literal markdown, not a subshell
grep_line="$(grep -n 'Consult `docs/solutions/`' "$execute_skill" | head -1 | cut -d: -f1 || true)"

if [[ -z "$context_line" ]]; then
    printf '  FAIL Step 1 instruction not found (looked for: %q)\n' "$step1_lead"
    fail=$((fail + 1))
elif [[ -n "$grep_line" && "$context_line" -lt "$grep_line" ]]; then
    printf '  ok   Step 1 reads the Context block before the docs/solutions/ grep (%s < %s)\n' \
        "$context_line" "$grep_line"
    pass=$((pass + 1))
else
    printf '  FAIL Step 1 must read the Context block before the docs/solutions/ grep (got %s vs %s)\n' \
        "$context_line" "${grep_line:-none}"
    fail=$((fail + 1))
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
