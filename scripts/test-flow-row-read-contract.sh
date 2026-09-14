#!/usr/bin/env bash
# test-flow-row-read-contract.sh — cross-skill contract test for the flow rows
# that /write-a-prd writes and /prd-to-issues Step 5 reads.
#
# The drift class this pins is a WRITE WITH NO READ. /write-a-prd used to
# mandate a standalone `## Flow Sketch` section exactly when a Must's delivery
# mechanism would be described there rather than in the story — and nothing
# downstream ever read it. `rg 'Flow Sketch'` over prd-to-issues/SKILL.md
# returned zero hits for the whole life of the section. Issue #362 relocated
# the rows under the Must each realizes so Step 5's existing derivation reads
# them, and amended Step 5 to test the whole user story rather than its want
# clause alone.
#
# Nothing about that arrangement is self-evident from either file on its own,
# which is how it broke the first time. Four sites now have to agree:
#
#   1. write-a-prd's interview rule   — tells the author to attach rows
#   2. write-a-prd's pitch template   — gives the rows somewhere to live
#   3. prd-to-issues Step 5           — reads them, at row granularity
#   4. SYSTEM-OVERVIEW Coverage Matrix — declares what coverage is tested against
#
# Site 4 is the one the #362 Mediator called out by name as a repo-wide risk:
# two skills key off that sentence, and it was false as written. A later edit
# that "tidies" any one of the four can silently restore the original defect,
# and the restoration emits no signal, because no parser reads a PRD — an agent
# does, and an agent proceeds cheerfully on a partial match.
#
# Two allowances are asserted as well, because dropping either one reproduces
# the failure by a different route (Gause & Weinberg's overconstraint): a row
# may sit under more than one Must, and rows that sit under none get an
# explicit residue heading rather than being forced somewhere.
#
# The assertions EXTRACT the real text from the real files and scope each one
# to the region it is about. A restated copy here would be a fifth site.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
prd_skill="$repo_root/write-a-prd/SKILL.md"
issues_skill="$repo_root/prd-to-issues/SKILL.md"
overview="$repo_root/SYSTEM-OVERVIEW.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

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

assert_absent() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       present but must not be: %q\n' "$label" "$needle"
        fail=$((fail + 1))
    fi
}

# --- extraction -------------------------------------------------------------

# The pitch template only. Scoped, because the skill's prose legitimately talks
# ABOUT flow rows outside it and the template is what an author copies.
extract_template() {
    awk '/^<pitch-template>$/ { collecting = 1; next }
         /^<\/pitch-template>$/ { exit }
         collecting { print }' "$prd_skill"
}

# Step 5 only. Scoped, because /prd-to-issues names the same vocabulary in its
# issue template further down, and a hit there would not prove the READ exists.
extract_step5() {
    awk '/^### 5\. / { collecting = 1; next }
         collecting && /^### 6\. / { exit }
         collecting { print }' "$issues_skill"
}

# The Coverage Matrix section of SYSTEM-OVERVIEW, up to the next H2.
extract_coverage_section() {
    awk '/^## Coverage Matrix/ { collecting = 1; next }
         collecting && /^## / { exit }
         collecting { print }' "$overview"
}

template="$(extract_template)"
step5="$(extract_step5)"
coverage="$(extract_coverage_section)"

# A silently-empty extraction would make every assert_absent below pass for the
# wrong reason. Fail loudly instead.
for pair in "template:$template" "step5:$step5" "coverage:$coverage"; do
    name="${pair%%:*}"
    body="${pair#*:}"
    if [[ -z "${body// /}" ]]; then
        printf 'FATAL: extraction %q came back empty — the anchor it keys on moved.\n' "$name" >&2
        exit 1
    fi
done

section "the write-only artifact is gone from the template"

assert_absent "$template" '## Flow Sketch' \
    "pitch template has no standalone Flow Sketch section"

section "the rows have somewhere to live, and an escape hatch"

assert_contains "$template" '### Must-haves' \
    "template still carries the Must-haves heading the rows hang off"
# The indented row form under a Must. This is the relocation target; without it
# the section was deleted and the rows went nowhere.
assert_contains "$template" '   - **[Place Name]**' \
    "template shows a flow row indented under a Must-have story"
assert_contains "$template" '### Shared affordances (unattributed)' \
    "template gives unattributed rows an explicit residue heading"

section "the read exists, at row granularity"

assert_contains "$step5" 'flow rows' \
    "Step 5 names flow rows — the read that the old Flow Sketch section never had"
assert_contains "$step5" 'affordance granularity' \
    "Step 5 maps at affordance granularity where rows exist"

section "Step 5 tests the whole story, not the want clause"

for clause in 'Actor clause' 'Want clause' 'So-that clause'; do
    assert_contains "$step5" "$clause" "Step 5 tests the $clause"
done
assert_contains "$step5" 'precondition' \
    "Step 5 names the precondition the actor clause carries"

section "the two allowances survive in both the writer and the reader"

assert_contains "$template" 'Repeat a row under each Must it realizes' \
    "template permits a row under more than one Must"
assert_contains "$step5" 'may sit under several Musts' \
    "Step 5 expects a row under more than one Must"
assert_contains "$step5" 'not a commitment' \
    "Step 5 declines to read unattributed residue as an unmapped Must"

section "in-flight PRDs still parse"

assert_contains "$step5" '## Flow Sketch' \
    "Step 5 still recognizes a PRD authored against the standalone section"

section "SYSTEM-OVERVIEW declares what Step 5 actually does"

assert_contains "$coverage" 'whole' \
    "Coverage Matrix says the story is read/tested whole"
assert_contains "$coverage" 'affordance granularity' \
    "Coverage Matrix names the same granularity Step 5 maps at"
assert_contains "$coverage" 'prd-to-issues` Step 5' \
    "Coverage Matrix points at the operative test rather than restating it"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
