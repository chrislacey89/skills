#!/usr/bin/env bash
# test-review-dimension-partition.sh — contract test for /pre-merge Phase 3's
# review-dimension partition.
#
# THE DRIFT CLASS: a guard whose own coverage is a hand-maintained restatement
# of the thing it guards. `pre-merge/review-checklist.md` is the canon — one
# `## N. Title` heading per review dimension. `pre-merge/SKILL.md` Phase 3 used
# to restate that roster as two hand-written bullets assigning dimensions to
# sub-agent A and sub-agent B. The restatement drifted from the canon *at
# birth*: commit ae362eb added Dimension 5 (Coverage Matrix Reconciliation) to
# the canon and never touched SKILL.md, so on any diff large enough to trigger
# the split, the one dimension carrying Blocker authority silently never ran —
# while SKILL.md's loop-mode ledger attested that every dimension had. Not a
# missing check: a false attestation. Reported from a real PR review (#291).
#
# The fix was not to append Dimension 5 to a sub-agent's bullet. Dimension 5's
# procedure reads the PRD issue body, every slice issue's `User Stories
# Addressed` section, and the merged-slice set — none of it reachable under the
# sub-agent context contract ("the diff, review-checklist.md,
# references/writing-for-humans.md, and the PR body's `## Review Notes` block.
# Nothing else."). Appending it would have traded a silent skip for a
# fabricated Blocker, which is strictly worse. Dimension 5 belongs with the
# controller-owned reconciliations in Phase 4, where the PRD is loaded.
#
# So the contract this suite pins is a THREE-bucket total partition:
#
#     {sub-agent A} ∪ {sub-agent B} ∪ {controller} == the canon's roster
#
# with every dimension in exactly one bucket. A two-list assertion would go
# green on exactly the arrangement that caused the incident, because a
# dimension pushed into a sub-agent it cannot execute still satisfies "appears
# on some list."
#
# Ownership is declared ONCE, in the canon, as a `**Runs in:**` line inside each
# dimension's own section — so adding a dimension forces the assignment at the
# same site as the definition, and a dimension added with no consumer fails
# here rather than shipping as invisible dead prose. SKILL.md derives the split
# from those markers instead of restating it.
#
# Lineage: docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md
# ("derive the coverage instead of restating it") and
# docs/restated-claims.md (the restated-claim-in-unchecked-prose class).
# Gilb & Graham, Software Inspection, Ch. 11 (Douglas Aircraft, 1988):
# "it was silly to rewrite a rule into a checklist question."

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
checklist="$repo_root/pre-merge/review-checklist.md"
premerge_skill="$repo_root/pre-merge/SKILL.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

fatal() {
    printf '\nFATAL: %s\n' "$1" >&2
    exit 2
}

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

assert_true() {
    local cond="$1" label="$2"
    if [[ "$cond" == "true" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n' "$label"
        fail=$((fail + 1))
    fi
}

[[ -f "$checklist" ]] || fatal "canon not found: $checklist"
[[ -f "$premerge_skill" ]] || fatal "skill not found: $premerge_skill"

# --- Read the roster out of the canon ---------------------------------------
#
# The roster is the set of numbered dimension headings. Nothing restates it;
# this is the only place it is defined.

mapfile -t roster < <(grep -oE '^## [0-9]+\. ' "$checklist" | grep -oE '[0-9]+')

# Empty-scan floor. Without this the whole suite passes vacuously the moment
# the heading format changes — a guard that reports coverage it does not have
# is the exact failure this file exists to prevent.
if [[ "${#roster[@]}" -lt 5 ]]; then
    fatal "roster scan found ${#roster[@]} dimension heading(s) in $checklist; expected at least 5. The '^## N. ' heading format changed, or the scan is broken. Refusing to report a vacuous pass."
fi

# --- Read the ownership markers out of the canon ----------------------------
#
# One `**Runs in:** <bucket>` line per dimension section. Walk the file
# linearly so each marker is attributed to the heading it sits under; that is
# what makes "exactly one marker per dimension" checkable rather than a count
# comparison that a doubled marker on one dimension and a missing marker on
# another would cancel out.

declare -A owner_of=()
declare -A marker_count=()
current=""
stray_markers=0

while IFS= read -r line; do
    if [[ "$line" =~ ^##\ ([0-9]+)\.\  ]]; then
        current="${BASH_REMATCH[1]}"
        marker_count["$current"]=0
        continue
    fi
    if [[ "$line" =~ ^\*\*Runs\ in:\*\*\ (sub-agent\ A|sub-agent\ B|the\ controller) ]]; then
        bucket="${BASH_REMATCH[1]}"
        if [[ -z "$current" ]]; then
            stray_markers=$((stray_markers + 1))
            continue
        fi
        marker_count["$current"]=$(( ${marker_count["$current"]} + 1 ))
        owner_of["$current"]="$bucket"
    fi
done < "$checklist"

section "Every dimension declares exactly one owner"

assert_eq "0" "$stray_markers" "no '**Runs in:**' marker sits outside a numbered dimension section"

missing=()
duplicated=()
for n in "${roster[@]}"; do
    case "${marker_count[$n]:-0}" in
        0) missing+=("$n") ;;
        1) ;;
        *) duplicated+=("$n") ;;
    esac
done

assert_eq "" "${missing[*]}" "no dimension is missing a '**Runs in:**' marker (this is what ae362eb would have failed)"
assert_eq "" "${duplicated[*]}" "no dimension declares two owners"

section "Three-bucket total partition over the roster"

bucket_a=(); bucket_b=(); bucket_c=()
for n in "${roster[@]}"; do
    case "${owner_of[$n]:-}" in
        "sub-agent A")   bucket_a+=("$n") ;;
        "sub-agent B")   bucket_b+=("$n") ;;
        "the controller") bucket_c+=("$n") ;;
    esac
done

partitioned=$(( ${#bucket_a[@]} + ${#bucket_b[@]} + ${#bucket_c[@]} ))
assert_eq "${#roster[@]}" "$partitioned" "{A} ∪ {B} ∪ {controller} covers the roster exactly (${#roster[@]} dimensions)"

# Each bucket must be inhabited. All-controller or all-sub-agent-A would
# satisfy the union check above while describing an arrangement nobody means.
assert_true "$([[ ${#bucket_a[@]} -gt 0 ]] && echo true || echo false)" "sub-agent A's bucket is non-empty (has ${#bucket_a[@]})"
assert_true "$([[ ${#bucket_b[@]} -gt 0 ]] && echo true || echo false)" "sub-agent B's bucket is non-empty (has ${#bucket_b[@]})"
assert_true "$([[ ${#bucket_c[@]} -gt 0 ]] && echo true || echo false)" "the controller's bucket is non-empty (has ${#bucket_c[@]})"

section "The incident's dimension is controller-owned, not sub-agent-assigned"

# Pin the specific arrangement #291 turned on: Coverage Matrix Reconciliation
# reads GitHub issue state, so no sub-agent can execute it under the context
# contract. This assertion finds the dimension by its title in the canon rather
# than hardcoding the number, so renumbering the roster does not silently
# retarget the check at a different dimension.
coverage_n="$(grep -oE '^## [0-9]+\. Coverage Matrix Reconciliation' "$checklist" | grep -oE '[0-9]+' || true)"
assert_true "$([[ -n "$coverage_n" ]] && echo true || echo false)" "Coverage Matrix Reconciliation is still in the canon"
if [[ -n "$coverage_n" ]]; then
    assert_eq "the controller" "${owner_of[$coverage_n]:-<none>}" "Dimension $coverage_n (Coverage Matrix Reconciliation) is controller-owned"
fi

section "SKILL.md derives the split; it does not restate it"

# The retired shape. These two bullets WERE the defect — a hand-maintained
# restatement of the roster that omitted Dimension 5 from birth.
retired_bullets="$(grep -cE '^- \*\*Sub-agent [AB] \(' "$premerge_skill" || true)"
assert_eq "0" "$retired_bullets" "the hand-enumerated 'Sub-agent A/B:' bullets are gone from pre-merge/SKILL.md"

# The derived rule must be anchored to the canon's actual marker vocabulary,
# not to a paraphrase of it — otherwise the canon could rename the marker and
# SKILL.md would go on pointing at a string that no longer exists.
assert_true "$(grep -qF '**Runs in:**' "$premerge_skill" && echo true || echo false)" "pre-merge/SKILL.md names the canon's '**Runs in:**' marker so the derivation is anchored"

# The controller bucket needs a reader. A dimension marked controller-owned
# with nothing in Phase 4 executing it is the same dead-prose failure in a new
# location.
assert_true "$(grep -qF 'Coverage Matrix' "$premerge_skill" && echo true || echo false)" "pre-merge/SKILL.md still has a consumer for the controller-owned coverage reconciliation"

section "The dimension count is not restated as a literal"

# docs/restated-claims.md: the count is derivable from the canon's headings, so
# any literal restatement of it is a second operative site that can drift. The
# roster's own size is the only place it should be readable.
count_literals="$(grep -nE '\b(11|[Ee]leven)[- ](dimension|architectural review dimension)' "$premerge_skill" "$checklist" || true)"
assert_eq "" "$count_literals" "no literal dimension count survives in pre-merge/SKILL.md or review-checklist.md"

# --- Summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
