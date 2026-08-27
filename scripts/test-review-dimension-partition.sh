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
# Dimension 5 could not simply be appended to a sub-agent's bullet. Its
# procedure needs the PRD and the full set of merged slices held together, a
# cross-slice view only the controller assembles. So ownership now lives in the
# canon as a `**Runs in:**` line inside each dimension's own section, and
# SKILL.md derives the split from those markers.
#
# The contract is a THREE-bucket total partition:
#
#     {sub-agent A} ∪ {sub-agent B} ∪ {controller} == the canon's roster
#
# with every dimension in exactly one bucket. A two-list assertion would go
# green on exactly the arrangement that caused the incident, because a
# dimension pushed into a sub-agent it cannot execute still satisfies "appears
# on some list."
#
# WHAT THE CROSS-FILE ASSERTIONS HAD WRONG, AND WHY IT IS WRITTEN DOWN HERE.
# The first version of this suite checked SKILL.md by searching the whole file
# for the marker string, and checked Phase 4 by searching it for a dimension's
# title. Both went green on mutations that broke the mechanism outright:
#
#   * Deleting Phase 3's derivation rule left the marker string present at
#     three other sites in SKILL.md, so the anchor held.
#   * The only occurrence of "Coverage Matrix Reconciliation" inside Phase 4 is
#     the sentence saying when to SKIP it, so the "Phase 4 runs it" assertion
#     was satisfied by prose asserting the opposite.
#   * The no-restatement check pinned the retired BULLET SYNTAX, so writing the
#     same roster back as a Markdown table walked straight past it.
#
# Each is the same error: asserting that a string exists where the claim was
# that something reads it. The assertions below are scoped to the phase span
# that must contain the instruction, and the no-restatement check keys on the
# PROPERTY (many canon titles listed together on one line) rather than on the
# syntax the retired instance happened to use — per
# docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md.
#
# PORTABILITY: bash 3.2 only. macOS ships /bin/bash 3.2 and lefthook resolves
# `bash` through PATH, so `mapfile` and `declare -A` would make this the one
# suite of the repo's set that dies at exit 127 on the local pre-push gate —
# the gate it exists to run on. No bash-4 builtins below.
#
# Lineage: docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md
# ("derive the coverage instead of restating it") and docs/restated-claims.md.
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
    expected="$1"; actual="$2"; label="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %s\n       got:      %s\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

assert_true() {
    cond="$1"; label="$2"
    if [ "$cond" = "true" ]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n' "$label"
        fail=$((fail + 1))
    fi
}

bool() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }

[ -f "$checklist" ] || fatal "canon not found: $checklist"
[ -f "$premerge_skill" ] || fatal "skill not found: $premerge_skill"

# --- Read the roster out of the canon ---------------------------------------
#
# The roster is the set of numbered dimension headings. Nothing restates it;
# this is the only place it is defined.

roster="$(grep -oE '^## [0-9]+\. ' "$checklist" | grep -oE '[0-9]+' || true)"
roster_count="$(printf '%s\n' "$roster" | grep -c '[0-9]' || true)"

# Empty-scan floor. Without this the whole suite passes vacuously the moment
# the heading format changes — a guard that reports coverage it does not have
# is the exact failure this file exists to prevent.
if [ "$roster_count" -lt 5 ]; then
    fatal "roster scan found $roster_count dimension heading(s) in $checklist; expected at least 5. The '^## N. ' heading format changed, or the scan is broken. Refusing to report a vacuous pass."
fi

# --- Read the ownership markers out of the canon ----------------------------
#
# One `**Runs in:** <bucket>` line per dimension section. Walk the file
# linearly so each marker is attributed to the heading it sits under; that is
# what makes "exactly one marker per dimension" checkable rather than a count
# comparison that a doubled marker on one dimension and a missing marker on
# another would cancel out.
#
# Associative arrays are bash 4, so ownership is accumulated as newline-
# delimited "N<TAB>bucket" records and looked up with grep.

owners=""
marker_counts=""
current=""
stray_markers=0

while IFS= read -r line; do
    case "$line" in
        '## '[0-9]*'. '*)
            current="$(printf '%s' "$line" | sed -E 's/^## ([0-9]+)\..*/\1/')"
            continue
            ;;
        '**Runs in:** sub-agent A'*) bucket="sub-agent A" ;;
        '**Runs in:** sub-agent B'*) bucket="sub-agent B" ;;
        '**Runs in:** the controller'*) bucket="the controller" ;;
        *) continue ;;
    esac
    if [ -z "$current" ]; then
        stray_markers=$((stray_markers + 1))
        continue
    fi
    owners="$owners$current	$bucket
"
    marker_counts="$marker_counts$current
"
done < "$checklist"

owner_of() {
    printf '%s' "$owners" | awk -F'\t' -v n="$1" '$1 == n { print $2 }' | tail -1
}

marker_count_of() {
    printf '%s' "$marker_counts" | grep -cx "$1" || true
}

section "Every dimension declares exactly one owner"

assert_eq "0" "$stray_markers" "no '**Runs in:**' marker sits outside a numbered dimension section"

# A duplicated `## N.` heading would let two dimensions share one number: the
# second resets the first's marker, every bucket total still agrees, and one
# dimension silently has no recorded owner.
unique_count="$(printf '%s\n' "$roster" | grep '[0-9]' | sort -u | grep -c '[0-9]' || true)"
assert_eq "$roster_count" "$unique_count" "no two dimensions share a heading number"

missing=""
duplicated=""
for n in $roster; do
    c="$(marker_count_of "$n")"
    case "$c" in
        0) missing="$missing $n" ;;
        1) ;;
        *) duplicated="$duplicated $n" ;;
    esac
done

assert_eq "" "${missing# }" "no dimension is missing a '**Runs in:**' marker (this is what ae362eb would have failed)"
assert_eq "" "${duplicated# }" "no dimension declares two owners"

section "Three-bucket total partition over the roster"

count_a=0; count_b=0; count_c=0; bucket_c=""
for n in $roster; do
    case "$(owner_of "$n")" in
        "sub-agent A")    count_a=$((count_a + 1)) ;;
        "sub-agent B")    count_b=$((count_b + 1)) ;;
        "the controller") count_c=$((count_c + 1)); bucket_c="$bucket_c $n" ;;
    esac
done

partitioned=$((count_a + count_b + count_c))
assert_eq "$roster_count" "$partitioned" "{A} ∪ {B} ∪ {controller} covers the roster exactly ($roster_count dimensions)"

# Each bucket must be inhabited. All-controller or all-sub-agent-A would
# satisfy the union check above while describing an arrangement nobody means.
assert_true "$([ "$count_a" -gt 0 ] && echo true || echo false)" "sub-agent A's bucket is non-empty (has $count_a)"
assert_true "$([ "$count_b" -gt 0 ] && echo true || echo false)" "sub-agent B's bucket is non-empty (has $count_b)"
assert_true "$([ "$count_c" -gt 0 ] && echo true || echo false)" "the controller's bucket is non-empty (has $count_c)"

section "The incident's dimension is controller-owned, not sub-agent-assigned"

# Pin the specific arrangement #291 turned on. Found by title rather than by
# number, so renumbering the roster cannot silently retarget the check.
coverage_n="$(grep -oE '^## [0-9]+\. Coverage Matrix Reconciliation' "$checklist" | grep -oE '[0-9]+' || true)"
assert_true "$([ -n "$coverage_n" ] && echo true || echo false)" "Coverage Matrix Reconciliation is still in the canon"
if [ -n "$coverage_n" ]; then
    got="$(owner_of "$coverage_n")"
    assert_eq "the controller" "${got:-<none>}" "Dimension $coverage_n (Coverage Matrix Reconciliation) is controller-owned"
fi

# --- Phase spans ------------------------------------------------------------
#
# Every cross-file assertion below is scoped to the phase span that must carry
# the instruction. Whole-file searches are what the first version of this suite
# got wrong: SKILL.md mentions the marker vocabulary in four places, so a
# whole-file search proves the string exists and proves nothing about whether
# the controller is told to act on it.

phase3="$(sed -n '/^### Phase 3/,/^### Phase 4/p' "$premerge_skill")"
phase4="$(sed -n '/^### Phase 4/,/^### Phase 5/p' "$premerge_skill")"

phase3_lines="$(printf '%s\n' "$phase3" | wc -l | tr -d ' ')"
phase4_lines="$(printf '%s\n' "$phase4" | wc -l | tr -d ' ')"
[ "$phase3_lines" -ge 5 ] || fatal "Phase 3 span extraction returned $phase3_lines line(s). The '### Phase N' heading format changed. Refusing to report a vacuous pass."
[ "$phase4_lines" -ge 5 ] || fatal "Phase 4 span extraction returned $phase4_lines line(s). The '### Phase N' heading format changed. Refusing to report a vacuous pass."

section "Phase 3 derives the delegated split from the canon"

# Scoped to Phase 3: deleting the derivation rule must fail here, which a
# whole-file search could not detect.
assert_true "$(printf '%s' "$phase3" | bool grep -qF '**Runs in:**')" \
    "Phase 3 names the canon's '**Runs in:**' marker, so the derivation is anchored to the canon's vocabulary"
assert_true "$(printf '%s' "$phase3" | bool grep -qF 'sub-agent A')" "Phase 3 names the 'sub-agent A' bucket value"
assert_true "$(printf '%s' "$phase3" | bool grep -qF 'sub-agent B')" "Phase 3 names the 'sub-agent B' bucket value"

section "Phase 4 derives the controller-owned dimensions from the canon"

# The controller bucket's marker value appears in SKILL.md only where Phase 4
# is instructed to execute those dimensions. Deleting the run block removes it.
#
# Deliberately NOT asserted: that Phase 4 contains a particular dimension's
# title. The earlier version did that, and Phase 4's only occurrence of the
# title is the sentence saying when to skip the dimension — so the assertion
# was satisfied by prose asserting the opposite of what it certified. Phase 4
# should derive from the marker, not name dimensions, so the check derives too.
assert_true "$(printf '%s' "$phase4" | bool grep -qF 'the controller, in Phase 4')" \
    "Phase 4 names the controller bucket's marker value, so the controller-owned dimensions have a consumer that derives them"

section "No hand-written roster survives in SKILL.md"

# THE PROPERTY, NOT THE SYNTAX. The retired instance was two Markdown bullets,
# and pinning that syntax let the identical roster return as a table. What
# actually characterizes a roster restatement is that several canon dimension
# titles are listed together on one line, whatever markup carries them.
#
# The threshold is calibrated against both ends rather than guessed. The
# retired bullets carried FIVE titles each, and any hand-written split of this
# roster carries at least four in some bucket. The busiest legitimate line in
# SKILL.md carries THREE — the Surgical Scope paragraph, which contrasts that
# dimension against Boundary Map Contracts and Coverage Matrix Reconciliation
# in one sentence. So the bar sits at four: above every observed contrast, at
# or below every reconstruction of the list. If a future legitimate sentence
# needs four, that is the signal to split the sentence, not to raise the bar.
titles="$(grep -oE '^## [0-9]+\. [^(]+' "$checklist" | sed -E 's/^## [0-9]+\. //; s/ +$//')"
title_total="$(printf '%s\n' "$titles" | grep -c . || true)"
[ "$title_total" -ge 5 ] || fatal "title scan found $title_total dimension title(s); expected at least 5. Refusing to report a vacuous pass."

worst_line=""
worst_hits=0
line_no=0
while IFS= read -r line; do
    line_no=$((line_no + 1))
    hits=0
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        case "$line" in *"$t"*) hits=$((hits + 1)) ;; esac
    done <<EOF
$titles
EOF
    if [ "$hits" -gt "$worst_hits" ]; then
        worst_hits="$hits"
        worst_line="$premerge_skill:$line_no"
    fi
done < "$premerge_skill"

assert_true "$([ "$worst_hits" -lt 4 ] && echo true || echo false)" \
    "no single line of pre-merge/SKILL.md lists 4+ canon dimension titles (worst: $worst_hits at ${worst_line:-none}) — a hand-written roster in any markup"

section "The dimension count is not restated as a literal"

# docs/restated-claims.md: the count is derivable from the canon's headings, so
# any literal restatement of it is a second operative site that can drift.
#
# THE FILE LIST AND THE PATTERN BOTH WIDENED AFTER A MISS. The first version
# scanned three named files for `11|eleven`. It reported a complete census and
# missed pre-merge/references/comment-craft.md, which says "10 dimensions" at
# two operative sites and is loaded on every reviewer-mode run — a file one
# directory away that had been wrong since before the roster changed. That is
# the tell docs/restated-claims.md § "The census comes before the remedy"
# predicts verbatim: "a search scoped by the phrasing that surfaced the known
# sites cannot surface a site worded differently."
#
# So the scan now covers the whole population that can state a roster size —
# all of pre-merge/ plus SYSTEM-OVERVIEW.md — with a pattern that matches any
# leading count, digits or spelled, rather than the two spellings that happened
# to surface first. Bundled SYSTEM-OVERVIEW copies are excluded deliberately:
# sync-skill-references.sh generates them and check-skill-references pins them,
# so the canonical file is the only place the claim can be authored.
sysoverview="$repo_root/SYSTEM-OVERVIEW.md"
[ -f "$sysoverview" ] || fatal "SYSTEM-OVERVIEW.md not found at $sysoverview"

# A roster size is always PLURAL ("11 dimensions", "eleven review dimensions"),
# which is what separates it from the many singular uses that are not claims
# about the roster at all — "one dimension carrying Blocker authority", "each
# dimension sits in exactly one bucket". The hyphenated attributive form
# ("11-dimension architectural review") is singular but IS a roster claim, so
# it gets its own branch.
count_pattern='\b((one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+)[- ]([a-z]+[- ]){0,2}dimensions\b|[0-9]+-dimension\b)'

scanned="$(find "$repo_root/pre-merge" -type f -name '*.md' | wc -l | tr -d ' ')"
[ "$scanned" -ge 3 ] || fatal "count-literal scan found only $scanned file(s) under pre-merge/. Refusing to report a vacuous pass."

count_literals="$(grep -rniE "$count_pattern" "$repo_root/pre-merge" --include='*.md' || true)"
sys_literals="$(grep -niE "$count_pattern" "$sysoverview" || true)"

assert_eq "" "$count_literals" "no literal dimension count survives anywhere under pre-merge/ ($scanned files scanned)"
assert_eq "" "$sys_literals" "no literal dimension count survives in SYSTEM-OVERVIEW.md"

# --- Summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
