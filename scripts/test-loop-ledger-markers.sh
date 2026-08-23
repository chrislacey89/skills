#!/usr/bin/env bash
# test-loop-ledger-markers.sh — contract test for the disposition ledger's
# `<!-- loop-pass: -->` and `<!-- loop-judge: -->` markers.
#
# These differ from the `reviewed-at` stamp: /pre-merge loop-mode both writes and
# reads them, so there is no second skill to drift against. The drift class here
# is between the marker TEMPLATE and the PROSE RULES that depend on its fields —
# both in pre-merge/SKILL.md, far enough apart to be edited independently.
#
# Two rules depend on the markers, and both fail silently if a field goes missing:
#
#   1. "A change to model, review-checklist.md revision, or prompt shape starts a
#      NEW loop rather than continuing the current one." That comparison is only
#      possible if all three are actually recorded. Drop one from the template and
#      the rule cannot fire — a judge swap between invocations then goes
#      undetected, and cross-pass comparisons silently compare two passes that
#      were never measured the same way.
#
#   2. "Loop-mode runs no autonomous passes." The marker counts invocations and
#      must stay a bare integer. An "N of M" shape, or a pass-bound sentence in
#      the skill, would advertise a limit the loop does not enforce — the loop
#      makes no commits, so it has no cycle of its own to bound.
#
# Tests read both halves out of the skill rather than restating them, so the suite
# fails when either drifts — which a hand-copied literal could not detect.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
premerge_skill="$repo_root/pre-merge/SKILL.md"

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
        printf '  FAIL %s\n       looked for: %q\n       in:         %q\n' "$label" "$needle" "$haystack"
        fail=$((fail + 1))
    fi
}

# --- Pull the markers out of the skill ---------------------------------------

pass_template="$(grep -o '<!-- loop-pass:[^>]*>' "$premerge_skill" | head -1)"
judge_template="$(grep -o '<!-- loop-judge:[^>]*>' "$premerge_skill" | head -1)"

if [[ -z "$pass_template" ]]; then
    printf 'FATAL: no loop-pass marker template found in %s\n' "$premerge_skill" >&2
    printf '       Either the ledger moved or the marker was renamed; update this suite with it.\n' >&2
    exit 2
fi
if [[ -z "$judge_template" ]]; then
    printf 'FATAL: no loop-judge marker template found in %s\n' "$premerge_skill" >&2
    printf '       Either the ledger moved or the marker was renamed; update this suite with it.\n' >&2
    exit 2
fi

printf 'loop-pass  template: %s\n' "$pass_template"
printf 'loop-judge template: %s\n' "$judge_template"

# -----------------------------------------------------------------------------

section "the judge marker records every field the new-loop rule compares"

# /pre-merge: "a judge is a system — model + prompt + sampling parameters — not a
# model", and loop-mode "records the reviewer's model, the review-checklist.md
# revision, and the prompt shape". All three must be in the template, or the
# "starts a new loop" rule has nothing to compare.
for field in model= checklist= prompt=; do
    assert_contains "$judge_template" "$field" \
        "loop-judge carries '${field%=}', which the new-loop rule compares across passes"
done

# -----------------------------------------------------------------------------

section "marker values carry no angle brackets"

# A '>' inside an HTML comment ends the naive `<!-- ... -->` extraction that reads
# these markers, truncating at the first offender and silently dropping every
# field after it. This suite's first run caught exactly that: the template used
# `model=<model-id>`, and the loop-judge marker parsed as `<!-- loop-judge:
# model=<model-id>` with checklist and prompt gone. Both assertions above would
# have failed for a reason that looks like a missing field rather than a broken
# parse, so pin the cause directly.
for template in "$pass_template" "$judge_template"; do
    body="${template#<!-- }"
    body="${body%-->}"
    marker_name="${body%%:*}"
    if [[ "$body" == *"<"* || "${body%?}" == *">"* ]]; then
        printf '  FAIL %s value contains an angle bracket: %q\n' "$marker_name" "$body"
        fail=$((fail + 1))
    else
        printf '  ok   %s carries literal values, not <placeholder> syntax\n' "$marker_name"
        pass=$((pass + 1))
    fi
done

# -----------------------------------------------------------------------------

section "the prose rule and the marker name the same three fields"

# Pull the sentence stating what loop-mode records, and confirm it still names
# the three things the template carries. If the prose grows a fourth pinned
# input, the template needs the field before the rule can enforce it.
# Take the whole line: the sentence contains "review-checklist.md", so stopping
# at the first period would truncate it mid-filename and drop the later fields.
judge_prose="$(grep 'records the reviewer' "$premerge_skill" | head -1)"

if [[ -z "$judge_prose" ]]; then
    printf 'FATAL: no "records the reviewer..." rule found in %s\n' "$premerge_skill" >&2
    printf '       The judge-pin rule moved or was reworded; update this suite with it.\n' >&2
    exit 2
fi

printf 'judge-pin prose:     %s\n' "$judge_prose"

assert_contains "$judge_prose" "model" "the rule names the model"
assert_contains "$judge_prose" "review-checklist.md" "the rule names the checklist revision"
assert_contains "$judge_prose" "prompt" "the rule names the prompt shape"

# -----------------------------------------------------------------------------

section "the pass marker carries a bare counter, not a bound"

# Loop-mode makes no commits and runs no autonomous passes, so there is no pass
# bound to advertise. The marker counts invocations. A reintroduced "N of M"
# would advertise a limit the loop does not enforce, which is the drift this
# assertion catches.
pass_value="$(printf '%s' "$pass_template" | sed -n 's/<!-- loop-pass:[[:space:]]*\(.*\)[[:space:]]*-->/\1/p' | sed 's/[[:space:]]*$//')"

printf 'loop-pass value:     %q\n' "$pass_value"

if [[ "$pass_value" =~ ^[0-9]+$ ]]; then
    printf '  ok   loop-pass is a bare invocation counter\n'
    pass=$((pass + 1))
else
    printf '  FAIL loop-pass is not a bare counter: %q\n' "$pass_value"
    printf '       Loop-mode has no pass bound; an "N of M" shape advertises one it does not enforce.\n'
    fail=$((fail + 1))
fi

# The skill must not carry a pass-bound claim either.
if grep -q 'At most \*\*[a-z]\{1,\}\*\* passes' "$premerge_skill"; then
    printf '  FAIL pre-merge/SKILL.md still states a pass bound, but loop-mode runs no autonomous passes\n'
    fail=$((fail + 1))
else
    printf '  ok   the skill states no pass bound\n'
    pass=$((pass + 1))
fi

# -----------------------------------------------------------------------------

section "round trip: the markers are extractable from a realistic PR body"

# A ledger block sitting in a body alongside the review-currency stamp and other
# HTML comments — the reader must pick out its own markers and not a neighbor's.
#
# shellcheck disable=SC2016  # backticks here are literal markdown
ledger_body() {
    printf '## Summary\n\nA PR with a <!-- --> decoy comment.\n\n'
    printf '## Review Currency\n\n<!-- reviewed-at: %s -->\n\n' \
        '0123456789abcdef0123456789abcdef01234567'
    printf '## Review Disposition Ledger\n\n'
    printf '%s\n' "$pass_template"
    printf '%s\n' "$judge_template"
    printf '\nDispositioned by `/pre-merge` loop-mode.\n'
}

extracted_pass="$(ledger_body | grep -o '<!-- loop-pass:[^>]*>' | tail -1)"
extracted_judge="$(ledger_body | grep -o '<!-- loop-judge:[^>]*>' | tail -1)"

assert_eq "$pass_template" "$extracted_pass" \
    "loop-pass survives a round trip through a full PR body"
assert_eq "$judge_template" "$extracted_judge" \
    "loop-judge survives a round trip through a full PR body"

# The reviewed-at stamp must not be captured by either loop-marker pattern —
# three markers share the body and the ledger writer must not clobber the stamp.
stamp_caught="$(ledger_body | grep -c 'loop-pass: 0123456789' || true)"
assert_eq 0 "$stamp_caught" "the review-currency stamp is not mistaken for a loop marker"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
