#!/usr/bin/env bash
# test-prose-fix-disposition.sh — /fix-findings' after-state vocabulary and the
# report block that prints it must agree, and every citation of a section of
# docs/restated-claims.md must name a section that exists.
#
# THE INCIDENT (chrislacey89/skills#358, child of #357). A /pre-merge finding
# about a sentence was fixed by rewording the sentence. The post-fix /pre-merge
# re-run takes the fix commits as its subject, so it reviewed the new sentence,
# and round two raised more Concerns than round one — three of its four written
# by round one's fixes. #358 gave /fix-findings a closed action set for a
# finding about what a sentence claims (delete it, or point it at the canonical
# statement), an after-state the controller reads off the fix and the Step 3
# report block prints, and a list in docs/restated-claims.md of the kinds of
# text that are not prose contracts, cited by /fix-findings Step 1 and by
# /pre-merge's Severity Classification.
#
# WHAT IT PINS, each side extracted from the real files:
#   1. The first column of fix-findings/SKILL.md's `| After-state |` table
#      against the after-states printed on the `Finding N — ` lines of Step 3's
#      report block. A cell with no `<placeholder>` must equal a printed
#      after-state; a cell ending in one must be printed as its stem, a space,
#      and text. Both directions: every cell is printed, and every printed
#      after-state is a cell.
#   2. Every `restated-claims.md § *X*` citation in the tracked-plus-untracked
#      markdown (CHANGELOG.md and docs/solutions/ excluded as dated history)
#      names a `## ` heading of docs/restated-claims.md, and the two files #358
#      made cite the kinds section still do.
#   3. A detector: no scanned line contains two or more of the kinds section's
#      bullets as case-insensitive fixed strings.
#
# NOT PINNED: the number of kinds. A count here would be a second statement of
# the list.
#
# HELD BY REVIEW, NOT BY THIS SUITE: whether a fixer refrains from rewording,
# whether the controller runs the word-diff check and reverts, whether a
# reviewer applies the Suggestion cap, and a restatement of the list in other
# words. Each is a property of what prose instructs or means, which a string
# comparison cannot decide — see
# docs/solutions/testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md
# and docs/solutions/testing-patterns/a-planted-term-cannot-discriminate-meaning-2026-09-04.md.
#
# PORTABILITY: re-execs under /bin/bash when available, as
# test-restated-review-operatives.sh does, so every macOS run exercises bash
# 3.2. No bash-4 builtins.
if [ -z "${PROSE_FIX_DISPOSITION_REEXEC:-}" ] && [ -x /bin/bash ]; then
    PROSE_FIX_DISPOSITION_REEXEC=1 exec /bin/bash "$0" "$@"
fi

set -euo pipefail
export LC_ALL=C

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fix_findings_skill="$repo_root/fix-findings/SKILL.md"
restated_claims="$repo_root/docs/restated-claims.md"
review_checklist="$repo_root/pre-merge/review-checklist.md"
manifest="$repo_root/scripts/skill-references.manifest"
self_rel="scripts/test-prose-fix-disposition.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ $# -ge 2 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

[ -f "$fix_findings_skill" ] || fatal "not found: $fix_findings_skill"
[ -f "$restated_claims" ] || fatal "not found: $restated_claims"
[ -f "$review_checklist" ] || fatal "not found: $review_checklist"
[ -f "$manifest" ] || fatal "not found: $manifest"

# ============================================================================
# Shared extractors — every one of these is called by BOTH a live check below
# AND a self-test in section 4, on the same real extracted text. Duplicating
# any of these into a second copy for the self-tests is exactly the shape
# scripts/test-duplicate-guard-programs.sh exists to fail.
# ============================================================================

# extract_afterstate_table <file> — the raw markdown table (header, separator,
# and body rows), verbatim, whose header row starts "| After-state |".
extract_afterstate_table() {
    awk '
        /^\| *After-state *\|/ { intable = 1 }
        intable {
            if ($0 !~ /^\|/) exit
            print
        }
    ' "$1"
}

# extract_afterstate_stems <table_text> — one "stem<TAB>mode" record per body
# row (the header and the |---| separator are rows 1 and 2 and are skipped):
# the first column with backticks stripped. A cell ending in " <placeholder>"
# has it stripped and is matched as a prefix; any other cell is matched exactly,
# so a cell renamed to a prefix of the printed word (`delete` for `deleted`)
# still disagrees.
extract_afterstate_stems() {
    # shellcheck disable=SC2016  # the backticks are literal markdown, not a command substitution
    printf '%s\n' "$1" | awk '
        NR <= 2 { next }
        /^\|/ {
            cell = $0
            sub(/^\|[ \t]*/, "", cell)
            sub(/\|.*/, "", cell)
            gsub(/^[ \t]+|[ \t]+$/, "", cell)
            gsub(/^`|`$/, "", cell)
            mode = "exact"
            if (sub(/ <[^>]*>$/, "", cell)) mode = "prefix"
            print cell "\t" mode
        }
    '
}

# extract_step3_block <file> — the plain ``` fenced block (never ```bash)
# inside the "### Step 3" section, up to the next ## or ### heading, whose
# body contains at least one "Finding N — " line. Fence lines excluded from
# the printed text.
extract_step3_block() {
    awk '
        /^### Step 3/ { insection = 1; next }
        insection && !inblock && /^(##|###) / { insection = 0 }
        insection && /^```$/ {
            if (!inblock) { inblock = 1; buf = ""; hasfinding = 0; next }
            if (hasfinding) { printf "%s", buf; exit }
            inblock = 0; next
        }
        insection && inblock {
            buf = buf $0 "\n"
            if ($0 ~ /^Finding [0-9]+ — /) hasfinding = 1
        }
    ' "$1"
}

# extract_used_token_records <block_text> — one "raw_line<TAB>token" record per
# Finding line that contributes a used token, per the rule this suite's header
# states:
#   `fixed at <sha>, X`  -> X
#   `Y at <sha>`, Y != "fixed" -> Y
#   a bare `fixed at <sha>` -> nothing (no record)
# raw_line is the original "Finding N — …" line verbatim — section 4's mutation
# needs the whole line, not just the token, to target the right occurrence
# when the token text also appears elsewhere in the block as ordinary prose.
# Pure bash regex — no awk/sed here, and no pipe into an early-exiting reader.
extract_used_token_records() {
    local block="$1"
    local pat_finding='^Finding [0-9]+ — (.*)$'
    local pat1='^fixed at [0-9a-f]+, (.+)$'
    local pat2='^([^,]+) at [0-9a-f]+'
    local line remainder
    while IFS= read -r line; do
        [[ "$line" =~ $pat_finding ]] || continue
        remainder="${BASH_REMATCH[1]}"
        if [[ "$remainder" =~ $pat1 ]]; then
            printf '%s\t%s\n' "$line" "${BASH_REMATCH[1]}"
        elif [[ "$remainder" =~ $pat2 ]] && [ "${BASH_REMATCH[1]}" != "fixed" ]; then
            printf '%s\t%s\n' "$line" "${BASH_REMATCH[1]}"
        fi
    done <<< "$block"
}

# extract_used_tokens <block_text> — the token column of extract_used_token_records.
extract_used_tokens() {
    extract_used_token_records "$1" | cut -f2
}

# stem_matches <stem> <mode> <token> — exact: the token is the stem. prefix:
# the token is the stem, a space, and at least one more character. Substring
# expansion rather than a case pattern, so a stem is compared as text and never
# read as a glob.
stem_matches() {
    local stem="$1" mode="$2" tok="$3"
    if [ "$mode" = "prefix" ]; then
        [ "${#tok}" -gt "$((${#stem} + 1))" ] && [ "${tok:0:$((${#stem} + 1))}" = "$stem " ]
    else
        [ "$tok" = "$stem" ]
    fi
}

# vocab_mismatches <table_text> <block_text> — one line per direction of
# disagreement between the writer's stems and the reader's used tokens.
# Silent (no output) when they agree. Internally re-derives stems and tokens
# from the two text blobs via the extractors above, so a mutation of either
# blob is read by the SAME parsing the live check uses.
vocab_mismatches() {
    local table_text="$1" block_text="$2"
    local stems tokens stem mode tok matched
    stems="$(extract_afterstate_stems "$table_text")"
    tokens="$(extract_used_tokens "$block_text")"
    while IFS=$'\t' read -r stem mode; do
        [ -n "$stem" ] || continue
        matched=0
        while IFS= read -r tok; do
            [ -n "$tok" ] || continue
            if stem_matches "$stem" "$mode" "$tok"; then matched=1; break; fi
        done <<< "$tokens"
        if [ "$matched" -eq 0 ]; then
            printf 'stem %s (After-state table) has no matching token in the Step 3 report block\n' "$stem"
        fi
    done <<< "$stems"
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        matched=0
        while IFS=$'\t' read -r stem mode; do
            [ -n "$stem" ] || continue
            if stem_matches "$stem" "$mode" "$tok"; then matched=1; break; fi
        done <<< "$stems"
        if [ "$matched" -eq 0 ]; then
            printf 'token %s (Step 3 report block) matches no stem in the After-state table\n' "$tok"
        fi
    done <<< "$tokens"
}

# extract_headings <file> — the "## " heading texts, one per line, verbatim.
extract_headings() {
    grep -E '^## ' "$1" | sed -E 's/^## //'
}

# extract_citations <file> — one "line<TAB>section" record per match of the
# ERE  restated-claims\.md\)? § \*[^*]+\*  found in the file.
extract_citations() {
    grep -noE 'restated-claims\.md\)? § \*[^*]+\*' "$1" \
        | sed -E 's/^([0-9]+):.*§ \*([^*]+)\*.*$/\1\t\2/'
}

# find_unresolved_citations <headings_text> <citations_text> — <citations_text>
# is "loc<TAB>section" records (one per line); prints the ones whose section is
# not an exact match against a heading in <headings_text>.
find_unresolved_citations() {
    local headings="$1" citations="$2"
    local loc sec
    while IFS=$'\t' read -r loc sec; do
        [ -n "$sec" ] || continue
        if ! grep -qxF -- "$sec" <<< "$headings"; then
            printf '%s\t%s\n' "$loc" "$sec"
        fi
    done <<< "$citations"
}

# WIANPC_HEADING names one specific docs/restated-claims.md heading, used both
# to scope section 3's bullet extraction below and to pin section 2's
# set-membership check. It is a literal because nothing else in the tree can
# select "which of several headings" is meant — but it is written exactly
# ONCE, here, and every use below reads this variable rather than re-typing
# the string. If the heading is ever renamed, extract_kind_bullets's own FATAL
# (zero kinds extracted) fires before anything downstream reports a false
# clean run.
WIANPC_HEADING="What is not a prose contract"

# extract_kind_bullets <file> — the "- " bullet texts under
# "## $WIANPC_HEADING", up to the next "## " heading.
extract_kind_bullets() {
    awk -v heading="## $WIANPC_HEADING" '
        $0 == heading { insection = 1; next }
        insection && /^## / { exit }
        insection && /^- / { sub(/^- /, ""); print }
    ' "$1"
}

# bundled_restated_claims_copies <manifest_file> — every skill's bundled copy
# path for docs/restated-claims.md, derived from the manifest rather than
# hand-listed (today: tdd, pre-merge, execute, fix-findings — but this reads
# whatever the manifest currently says).
bundled_restated_claims_copies() {
    awk '!/^#/ && NF == 2 && $1 == "docs/restated-claims.md" { print $2 "/references/restated-claims.md" }' "$1"
}

# kind_restatement_hits <kinds_joined_by_SOH> <file> — "file:line" for every
# physical line in <file> carrying two or more of the joined kind phrases,
# case-insensitive, as fixed strings.
SOH="$(printf '\001')"
kind_restatement_hits() {
    awk -v kinds="$1" -v SOH="$SOH" '
        BEGIN {
            nk = split(kinds, karr, SOH)
            for (i = 1; i <= nk; i++) karr[i] = tolower(karr[i])
        }
        {
            line = tolower($0)
            cnt = 0
            for (i = 1; i <= nk; i++) if (index(line, karr[i]) > 0) cnt++
            if (cnt >= 2) printf "%s:%d\n", FILENAME, FNR
        }
    ' "$2"
}

# ============================================================================
section "1. After-state vocabulary — writer (Step 1 table) vs reader (Step 3 block)"
# ============================================================================

real_table_text="$(extract_afterstate_table "$fix_findings_skill")"
[ -n "$real_table_text" ] || fatal "no markdown table with a header row starting '| After-state |' found in $fix_findings_skill — the table this suite pins is shaped differently than expected; report this rather than editing the subject file to fit."

real_stems="$(extract_afterstate_stems "$real_table_text")"
stem_count="$(printf '%s\n' "$real_stems" | grep -c . || true)"
[ "$stem_count" -ge 1 ] || fatal "extracted 0 after-state stems from the table in $fix_findings_skill. Refusing to report a vacuous pass."
printf 'writer stems (%d): %s\n' "$stem_count" "$(printf '%s\n' "$real_stems" | cut -f1 | tr '\n' '|')"

real_block_text="$(extract_step3_block "$fix_findings_skill")"
[ -n "$real_block_text" ] || fatal "no plain \`\`\` fenced block inside '### Step 3' containing a 'Finding N — ' line found in $fix_findings_skill — the report block this suite pins is shaped differently than expected; report this rather than editing the subject file to fit."

real_tokens="$(extract_used_tokens "$real_block_text")"
token_count="$(printf '%s\n' "$real_tokens" | grep -c . || true)"
[ "$token_count" -ge 1 ] || fatal "extracted 0 used after-state tokens from the Step 3 block in $fix_findings_skill. Refusing to report a vacuous pass."
printf 'reader tokens (%d): %s\n' "$token_count" "$(printf '%s' "$real_tokens" | tr '\n' '|')"

mismatches="$(vocab_mismatches "$real_table_text" "$real_block_text")"
if [ -z "$mismatches" ]; then
    ok "every After-state cell is printed in the Step 3 block, and every after-state printed there is a cell (exact, or stem-space-text for a <placeholder> cell)"
else
    bad "the After-state table and the Step 3 report block disagree on vocabulary" "$mismatches"
fi

# ============================================================================
section "2. Every restated-claims.md § *Section* citation names a real heading"
# ============================================================================

md_population="$(git ls-files --cached --others --exclude-standard -- '*.md' \
    | grep -vxF 'CHANGELOG.md' \
    | grep -v '^docs/solutions/' || true)"
md_pop_count="$(printf '%s\n' "$md_population" | grep -c . || true)"
[ "$md_pop_count" -ge 50 ] || fatal "markdown population is $md_pop_count file(s); expected at least 50. git ls-files or the exclusion filtering broke. Refusing to report a vacuous pass."

real_headings="$(extract_headings "$restated_claims")"
heading_count="$(printf '%s\n' "$real_headings" | grep -c . || true)"
[ "$heading_count" -ge 1 ] || fatal "extracted 0 '## ' headings from $restated_claims. Refusing to report a vacuous pass."

all_citations=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    while IFS=$'\t' read -r ln sec; do
        [ -n "$sec" ] || continue
        all_citations="$all_citations$f:$ln"$'\t'"$sec"$'\n'
    done < <(extract_citations "$f")
done <<< "$md_population"

citation_count="$(printf '%s' "$all_citations" | grep -c . || true)"
[ "$citation_count" -ge 1 ] || fatal "found 0 'restated-claims.md § *Section*' citations across $md_pop_count markdown files. Refusing to report a vacuous pass."
printf 'citations found: %d, across %d markdown files, %d headings in the canon\n' "$citation_count" "$md_pop_count" "$heading_count"

unresolved="$(find_unresolved_citations "$real_headings" "$all_citations")"
if [ -z "$unresolved" ]; then
    ok "every citation of the form restated-claims.md § *Section* names a heading that exists in $restated_claims"
else
    bad "some citations name a heading that does not exist in the canon" "$unresolved"
fi

wianpc_citers="$(printf '%s' "$all_citations" | awk -F'\t' -v sec="$WIANPC_HEADING" '$2 == sec { split($1, a, ":"); print a[1] }' | sort -u)"
# coverage: enumerated — the two files #358 wrote a citation of this section
# into. Not derivable: the set is "the sites that must keep citing it", a
# property of the change, not of the tree. A new citer is checked above.
for required in "fix-findings/SKILL.md" "pre-merge/review-checklist.md"; do
    if grep -qxF -- "$required" <<< "$wianpc_citers"; then
        ok "$required is among the files citing § *$WIANPC_HEADING*"
    else
        bad "$required does not cite § *$WIANPC_HEADING*" "citers found: $(printf '%s' "$wianpc_citers" | tr '\n' ' ')"
    fi
done

# ============================================================================
section "3. Verbatim-restatement detector for the 'what is not a prose contract' kinds"
# ============================================================================

real_kinds="$(extract_kind_bullets "$restated_claims")"
kind_count="$(printf '%s\n' "$real_kinds" | grep -c . || true)"
[ "$kind_count" -ge 1 ] || fatal "extracted 0 kind bullets from '## $WIANPC_HEADING' in $restated_claims. Refusing to report a vacuous pass."
# Deliberately not printed as "$kind_count kinds: ..." anywhere a reader could
# treat it as a pin — this suite states the detector's reach, never the list's
# size, per docs/solutions/testing-patterns/prose-contract-tests-are-restated-claims-2026-08-27.md.

kinds_joined="$(printf '%s' "$real_kinds" | tr '\n' "$SOH")"
kinds_joined="${kinds_joined%"$SOH"}"

exclude_list="$(mktemp)"
trap 'rm -f "$exclude_list"' EXIT
{
    printf 'docs/restated-claims.md\n'
    printf 'CHANGELOG.md\n'
    printf '%s\n' "$self_rel"
    bundled_restated_claims_copies "$manifest"
} > "$exclude_list"

corpus_population="$(git ls-files --cached --others --exclude-standard \
    | grep -v '^docs/solutions/' \
    | grep -vxFf "$exclude_list" || true)"
corpus_pop_count="$(printf '%s\n' "$corpus_population" | grep -c . || true)"
[ "$corpus_pop_count" -ge 50 ] || fatal "corpus population is $corpus_pop_count file(s); expected at least 50. git ls-files or the exclusion filtering broke. Refusing to report a vacuous pass."

restatement_hits=""
scanned_text_files=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    if grep -Iq '' -- "$f" 2>/dev/null; then
        scanned_text_files=$((scanned_text_files + 1))
        h="$(kind_restatement_hits "$kinds_joined" "$f")"
        if [ -n "$h" ]; then
            restatement_hits="$restatement_hits$h"$'\n'
        fi
    fi
done <<< "$corpus_population"

if [ -z "$restatement_hits" ]; then
    ok "no line in $scanned_text_files scanned files contains two or more of the list's bullets verbatim (case-insensitive)"
else
    bad "some lines restate two or more kinds verbatim" "$restatement_hits"
fi

# ============================================================================
section "4. Self-tests — the assertions above can go red"
# ============================================================================

# --- 1. Drop the table row whose stem is the first derived stem ------------
first_stem="$(printf '%s\n' "$real_stems" | head -n1 | cut -f1 || true)"
first_body_row="$(printf '%s\n' "$real_table_text" | awk 'NR==3')"
[ -n "$first_body_row" ] || fatal "self-test setup: could not read the first body row of the After-state table."
mutated_table_text="$(printf '%s\n' "$real_table_text" | grep -vxF -- "$first_body_row")"
[ "$mutated_table_text" != "$real_table_text" ] || fatal "self-test setup: dropping the first body row did not change the table text."
self1="$(vocab_mismatches "$mutated_table_text" "$real_block_text")"
if [ -n "$self1" ]; then
    ok "self-test: dropping the '$first_stem' row from the table makes vocab_mismatches non-empty"
else
    bad "self-test FAILED: dropping the '$first_stem' row left vocab_mismatches empty — the check cannot see a missing table row"
fi

# --- 1b. Rename an exact cell to a prefix of the word the block prints -----
# A prefix comparison passes this (`delete` prefixes `deleted`); exact matching
# must not. The cell is rewritten inside the real table text.
first_exact_stem="$(printf '%s\n' "$real_stems" | awk -F'\t' '$2 == "exact" { print $1; exit }')"
[ "${#first_exact_stem}" -ge 2 ] || fatal "self-test setup: no exact After-state cell of two or more characters to shorten."
bt="$(printf '\140')"
cell_old="$bt$first_exact_stem$bt"
cell_new="$bt${first_exact_stem%?}$bt"
shortened_table_text="${real_table_text/$cell_old/$cell_new}"
[ "$shortened_table_text" != "$real_table_text" ] || fatal "self-test setup: shortening the '$first_exact_stem' cell did not change the table text."
self1b="$(vocab_mismatches "$shortened_table_text" "$real_block_text")"
if [ -n "$self1b" ]; then
    ok "self-test: renaming the '$first_exact_stem' cell to '${first_exact_stem%?}' makes vocab_mismatches non-empty"
else
    bad "self-test FAILED: a cell renamed to a prefix of the printed word left vocab_mismatches empty — the match is a prefix match"
fi

# --- 2. Replace the first used token's text with "removed" -----------------
# Scoped to the specific Finding LINE that produced the first token, not a
# bare whole-block substring swap: the token text can also occur as ordinary
# prose elsewhere in the block (here, "deleted" appears in Finding 3's breaker
# narration before it appears as Finding 4's token), and a naive
# ${block/token/removed} would silently mutate the wrong occurrence.
first_record="$(extract_used_token_records "$real_block_text" | head -n1 || true)"
[ -n "$first_record" ] || fatal "self-test setup: extract_used_token_records produced no record to mutate."
first_token_line="${first_record%%$'\t'*}"
first_token="${first_record#*$'\t'}"
mutated_token_line="${first_token_line/$first_token/removed}"
[ "$mutated_token_line" != "$first_token_line" ] || fatal "self-test setup: replacing '$first_token' inside its own Finding line did not change that line."
mutated_block_text="${real_block_text/$first_token_line/$mutated_token_line}"
[ "$mutated_block_text" != "$real_block_text" ] || fatal "self-test setup: replacing the first used token's Finding line did not change the block text."
self2="$(vocab_mismatches "$real_table_text" "$mutated_block_text")"
if [ -n "$self2" ]; then
    ok "self-test: replacing the first used token ('$first_token' -> 'removed') makes vocab_mismatches non-empty"
else
    bad "self-test FAILED: replacing the first used token left vocab_mismatches empty — the check cannot see a reworded report line"
fi

# --- 3. A citation to a heading with one character changed -----------------
mutated_heading="${WIANPC_HEADING}s"
grep -qxF -- "$mutated_heading" <<< "$real_headings" && fatal "self-test setup: the mutated heading '$mutated_heading' unexpectedly already exists as a real heading."
self3_citations="$(printf 'selftest:0\t%s\n' "$mutated_heading")"
self3="$(find_unresolved_citations "$real_headings" "$self3_citations")"
if [ -n "$self3" ]; then
    ok "self-test: a citation to '$mutated_heading' (one character changed) is flagged unresolved"
else
    bad "self-test FAILED: a citation to a nonexistent heading was not flagged"
fi

# --- 4. Restatement detector: planted positive and near-miss ----------------
kind1="$(printf '%s\n' "$real_kinds" | sed -n '1p')"
kind2="$(printf '%s\n' "$real_kinds" | sed -n '2p')"
if [ -z "$kind1" ] || [ -z "$kind2" ]; then
    fatal "self-test setup: fewer than 2 kinds extracted; cannot plant a two-kind positive."
fi

plant_dir="$(mktemp -d)"
trap 'rm -f "$exclude_list"; rm -rf "$plant_dir"' EXIT

positive_file="$plant_dir/positive.txt"
nearmiss_file="$plant_dir/nearmiss.txt"
printf 'This line joins %s and %s in one restated sentence.\n' "$kind1" "$kind2" > "$positive_file"
printf 'This line mentions only %s, nothing else from the list.\n' "$kind1" > "$nearmiss_file"

self4_hit="$(kind_restatement_hits "$kinds_joined" "$positive_file")"
if [ -n "$self4_hit" ]; then
    ok "self-test: a planted line joining '$kind1' and '$kind2' is flagged by the restatement detector"
else
    bad "self-test FAILED: the planted two-kind line was not flagged"
fi

self4_miss="$(kind_restatement_hits "$kinds_joined" "$nearmiss_file")"
if [ -z "$self4_miss" ]; then
    ok "self-test: a near-miss line carrying only '$kind1' stays silent"
else
    bad "self-test FAILED: the near-miss line (one kind only) was flagged" "$self4_miss"
fi

# ============================================================================

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
