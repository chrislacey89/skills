#!/usr/bin/env bash
# test-duplicate-guard-programs.sh — inside one contract suite, the live check
# and its self-test must run the SAME reader, not two copies of it.
#
# THE DRIFT CLASS. A contract suite's self-test exists to prove its reader works.
# That proof is worth nothing if the self-test exercises a *copy* of the reader
# rather than the reader itself: mutate the real one and the self-test stays
# green, because it is still checking its duplicate. The suite then reports a
# validated instrument while shipping a broken one — the same
# two-readings-of-one-rule defect these suites already warn about when an oracle
# restates its subject, turned inward on the guard.
#
# THE INCIDENT (PR #279, 2026-08-25). `scripts/test-canon-coverage.sh` grades the
# landing page's claim that a conference paper renders as a different object than
# a bound book. The check began as two calls to a min/max reader whose direction
# lived in a flag at each call site; inverting those flags compared every paper
# against the TALLEST book instead of the shortest, and a page with a paper
# rendered at bound-volume height passed with the assertion printing the property
# as satisfied. The first fix pinned the reader's semantics with a fixture and did
# not help — a self-test on a function cannot reach the arguments its callers
# pass. The second fix removed the parameter by making the comparison a pairwise
# scan, but INLINED that scan in the live check while giving the self-test its own
# copy; mutating the real scan left the self-test green. Only the third fix — one
# function, called by both — was actually pinned.
#
# WHAT THIS SCANS FOR. Embedded awk and sed programs are where a bash contract
# suite keeps its readers, and a duplicated one is the machine-visible tell of the
# shape above. Any non-trivial program text appearing more than once in the same
# suite fails: if the live check and the self-test both need it, it belongs in one
# function that both call.
#
# WHY THE EXISTING MECHANISM COULD NOT FIRE. scripts/test-oracle-table-coverage.sh
# covers the sibling shape — a self-check that enumerates part of its lookup
# table. It keys on a case statement, and test-canon-coverage.sh holds no case
# table, so it was silent here. That is exactly the recurrence
# docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md
# describes: a mechanism inherits the syntax of the instance that produced it.
#
# WHAT THIS DOES NOT CATCH, stated so the next reader does not over-trust it. The
# original defect — a reader whose *direction* is chosen by a literal argument at
# each call site — is not detected here. A self-test can enumerate every
# combination of a reader's own parameters and still say nothing about which
# combination its callers pass. The durable fix for that shape is to remove the
# parameter rather than to test it, which is a design rule no scanner can enforce.
# See guard-and-subject-must-be-one-artifact-2026-08-25.md for the full rule.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ "$#" -gt 1 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}
fatal() { printf '\nFATAL: %s\n' "$1" >&2; exit 2; }

# A program shorter than this is an idiom, not a reader. A two-line print
# written twice is not the defect; a multi-line extractor written twice is.
MIN_PROGRAM_LINES=4

SQ="'"
SOH="$(printf '\001')"

# embedded_programs <file> — every multi-line awk/sed program in the file, one
# per output RECORD, as "<start-line><TAB><body>".
#
# THE BODY IS SOH-JOINED, NOT NEWLINE-JOINED. A program spans lines and the
# consumer below is a tab-delimited awk pipeline; emitting raw newlines turns one
# program into many records and every field read lands on the wrong program. The
# first draft of this scanner did that and reported nonsense excerpts.
#
# NORMALIZED BEFORE COMPARING. The two copies that matter are rarely
# byte-identical — one is indented as a function body, the other for a live check,
# and re-indentation is precisely the edit that happens when a reader is pasted
# into a second place. Leading and trailing whitespace goes, blank lines go.
embedded_programs() {
    awk -v MINLINES="$MIN_PROGRAM_LINES" -v Q="$SQ" -v SOH="$SOH" '
        function flush() {
            if (nlines >= MINLINES) printf "%d\t%s\n", start, body
            inprog = 0; body = ""; nlines = 0
        }
        # HEREDOC BODIES ARE TEST DATA, NOT READERS. Suites build fixtures that
        # legitimately contain awk, and this file own self-test fixture holds a
        # deliberate duplicate. Scanning inside them would fail every such suite
        # on its own fixtures, starting with this one.
        # The quote class is built from Q rather than written as a literal: a
        # heredoc tag may be bare, single-quoted, or double-quoted, and a class
        # covering only double quotes silently leaks every <<QUOTEDTAG fixture in
        # the repo back into the scan. That is how the first run read 18 programs
        # where the suites hold far more.
        !inprog && !inheredoc && match($0, "<<-?[[:space:]]*[" Q "\"]?[A-Za-z_][A-Za-z0-9_]*") {
            tag = substr($0, RSTART, RLENGTH)
            sub(/^<<-?[[:space:]]*/, "", tag)
            gsub("[" Q "\"]", "", tag)
            inheredoc = 1; heretag = tag; next
        }
        inheredoc {
            probe = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", probe)
            if (probe == heretag) inheredoc = 0
            next
        }
        # Comment lines are prose, and prose contains apostrophes. Counting those
        # as quotes is what made the first draft open a program on a sentence and
        # swallow the next forty lines of commentary.
        !inprog && /^[[:space:]]*#/ { next }
        # Open only on a line that invokes awk or sed AND opens a quote after the
        # invocation. A quote before the tool name belongs to another argument.
        !inprog {
            tail = $0
            if (!match(tail, /(^|[^[:alnum:]_])(awk|sed)([[:space:]]|$)/)) next
            tail = substr(tail, RSTART + RLENGTH)
            # PARITY, NOT THE FIRST QUOTE. `awk -F'"'"'\t'"'"' -v X="$Y" '"'"'` opens a program,
            # and its first quote belongs to the field separator. Taking that
            # first quote as the opener made every -F-flagged reader read as a
            # closed one-liner and vanish from the scan. An ODD number of quotes
            # after the tool name means one is left open; the last of them is the
            # one that opens the program.
            nq = gsub(Q, Q, tail)
            if (nq == 0 || nq % 2 == 0) next
            while (index(tail, Q) > 0) tail = substr(tail, index(tail, Q) + 1)
            inprog = 1; start = FNR; body = ""; nlines = 0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", tail)
            if (tail != "") { body = tail; nlines = 1 }
            next
        }
        {
            line = $0
            closing = (index(line, Q) > 0)
            if (closing) line = substr(line, 1, index(line, Q) - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line != "") { body = (body == "" ? line : body SOH line); nlines++ }
            if (closing) flush()
        }
        END { if (inprog) flush() }
    ' "$1"
}

# duplicate_programs <file> — "<count><TAB><first><TAB><later><TAB><excerpt>" for
# every program text appearing more than once. Empty output is the passing state.
duplicate_programs() {
    embedded_programs "$1" | awk -F'\t' -v SOH="$SOH" '
        {
            key = $2
            count[key]++
            if (count[key] == 1) first[key] = $1
            else where[key] = where[key] " " $1
        }
        END {
            for (k in count)
                if (count[k] > 1) {
                    excerpt = k
                    i = index(excerpt, SOH)
                    if (i > 0) excerpt = substr(excerpt, 1, i - 1)
                    printf "%d\t%s\t%s\t%s\n", count[k], first[k], where[k], excerpt
                }
        }
    '
}

# -----------------------------------------------------------------------------
section "every contract suite defines each of its readers once"

# A FLOOR, in the shape test-oracle-table-coverage.sh established, and for the
# reason partial-oracle-selfcheck-2026-08-22.md records: that mechanism reported
# full green when its own detector was blinded, because "found nothing" and
# "found nothing wrong" are the same output. A scan that reads zero programs
# across every suite in the repo is a broken scan, so it is FATAL rather than a
# clean pass.
MIN_PROGRAMS=12

total_programs=0
for suite in "$repo_root"/scripts/test-*.sh; do
    [ -f "$suite" ] || continue
    n="$(embedded_programs "$suite" | grep -c . || true)"
    total_programs=$((total_programs + n))
done

if [ "$total_programs" -lt "$MIN_PROGRAMS" ]; then
    fatal "read $total_programs embedded program(s) across every suite, expected at least $MIN_PROGRAMS.
       The extractor is broken, not the suites — a scan that reads nothing reports
       every file clean, which is the vacuous pass this family exists to abolish.
       If the suites genuinely shed their awk readers, lower MIN_PROGRAMS in this
       file as a deliberate edit."
fi
ok "read $total_programs multi-line awk/sed reader(s) across the contract suites (floor: $MIN_PROGRAMS)"

found_dupe=0
for suite in "$repo_root"/scripts/test-*.sh; do
    [ -f "$suite" ] || continue
    rel="${suite#"$repo_root"/}"
    while IFS="$(printf '\t')" read -r count first later excerpt; do
        [ -n "${count:-}" ] || continue
        found_dupe=1
        bad "$rel writes the same reader $count times (lines $first$later)" \
            "it starts: $excerpt
If the live check and its self-test both need this, it belongs in ONE function that both call. A self-test exercising its own copy proves nothing about the reader the suite actually runs — mutate the real one and the self-test stays green."
    done <<EOF
$(duplicate_programs "$suite")
EOF
done

[ "$found_dupe" -eq 1 ] || ok "no contract suite writes the same reader twice"

# -----------------------------------------------------------------------------
section "the detector still detects (self-test)"

# VALIDATE THE INSTRUMENT, NOT ONLY THE SUBJECT. Every check above runs against a
# tree that is currently clean, so nothing there distinguishes a working scanner
# from a blind one. See validate-the-instrument-not-only-the-subject-2026-08-23.md.
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

# shellcheck disable=SC2016  # the $1/$2 below are fixture TEXT, not
# expansions — these lines are the file this scanner is about to read.
printf '%s\n' \
    'live_check() {' \
    '    printf "%s\\n" "$1" | awk -F"\\t" '"'"'' \
    '        $2 == "paper" { p[++np] = $3 + 0 }' \
    '        $2 == "book"  { b[++nb] = $3 + 0 }' \
    '        $2 == "other" { next }' \
    '        END { for (i in p) for (j in b) if (p[i] >= b[j]) print "violation" }' \
    '    '"'"'' \
    '}' \
    'self_test() {' \
    '    printf "%s\\n" "$1" | awk -F"\\t" '"'"'' \
    '            $2 == "paper" { p[++np] = $3 + 0 }' \
    '            $2 == "book"  { b[++nb] = $3 + 0 }' \
    '            $2 == "other" { next }' \
    '            END { for (i in p) for (j in b) if (p[i] >= b[j]) print "violation" }' \
    '    '"'"'' \
    '}' \
    > "$fixtures/dupe.sh"

fixture_programs="$(embedded_programs "$fixtures/dupe.sh" | grep -c . || true)"
if [ "$fixture_programs" -ne 2 ]; then
    fatal "the duplicate fixture yielded $fixture_programs program(s), expected 2.
       The FIXTURE is below MIN_PROGRAM_LINES ($MIN_PROGRAM_LINES), not the scanner
       broken — a fixture the detector is designed to ignore makes the assertion
       below pass whether the scanner works or not. Lengthen the fixture rather
       than lowering the threshold."
fi

if [ -n "$(duplicate_programs "$fixtures/dupe.sh")" ]; then
    ok "a reader pasted into a self-test alongside the live check is reported, re-indented copy and all"
else
    bad "the scanner missed a reader written twice in one file" \
        "this is the PR #279 shape verbatim — the live check inlined a scan and the self-test held its own copy, so mutating the real scan left the self-test green."
fi

# shellcheck disable=SC2016  # the $1/$2 below are fixture TEXT, not
# expansions — these lines are the file this scanner is about to read.
printf '%s\n' \
    'scan() {' \
    '    printf "%s\\n" "$1" | awk -F"\\t" '"'"'' \
    '        $2 == "paper" { p[++np] = $3 + 0 }' \
    '        $2 == "book"  { b[++nb] = $3 + 0 }' \
    '        $2 == "other" { next }' \
    '        END { for (i in p) for (j in b) if (p[i] >= b[j]) print "violation" }' \
    '    '"'"'' \
    '}' \
    'live_check() { scan "$1"; }' \
    'self_test()  { scan "$2"; }' \
    > "$fixtures/shared.sh"

if [ -z "$(duplicate_programs "$fixtures/shared.sh")" ]; then
    ok "one definition called from both the live check and the self-test passes"
else
    bad "the scanner reported a file whose reader is defined once" \
        "got: $(duplicate_programs "$fixtures/shared.sh") — a detector that fires on the fixed shape makes the fix look like the defect, which teaches the next author to route around it."
fi

# shellcheck disable=SC2016  # the $1/$2 below are fixture TEXT, not
# expansions — these lines are the file this scanner is about to read.
printf '%s\n' \
    'a() { awk '"'"'{ print $2 }'"'"' "$1"; }' \
    'b() { awk '"'"'{ print $2 }'"'"' "$1"; }' \
    > "$fixtures/oneliners.sh"

if [ -z "$(duplicate_programs "$fixtures/oneliners.sh")" ]; then
    ok "a repeated one-line idiom is not reported as a duplicated reader"
else
    bad "the scanner reported a repeated one-liner" \
        "a one-line print written twice is an idiom, not a copied reader. Reporting it buries the real signal under noise the author cannot act on."
fi

# shellcheck disable=SC2016  # the $1/$2 below are fixture TEXT, not
# expansions — these lines are the file this scanner is about to read.
printf '%s\n' \
    'cat > "$f" <<INNER' \
    '    awk -F"\\t" '"'"'' \
    '        $2 == "paper" { p[++np] = $3 + 0 }' \
    '        $2 == "book"  { b[++nb] = $3 + 0 }' \
    '        $2 == "other" { next }' \
    '        END { print "fixture data, not a reader" }' \
    '    '"'"'' \
    '    awk -F"\\t" '"'"'' \
    '        $2 == "paper" { p[++np] = $3 + 0 }' \
    '        $2 == "book"  { b[++nb] = $3 + 0 }' \
    '        $2 == "other" { next }' \
    '        END { print "fixture data, not a reader" }' \
    '    '"'"'' \
    'INNER' \
    > "$fixtures/heredoc.sh"

if [ -z "$(duplicate_programs "$fixtures/heredoc.sh")" ]; then
    ok "duplicated programs inside a fixture heredoc are test data, not readers, and are skipped"
else
    bad "the scanner read inside a heredoc fixture" \
        "got: $(duplicate_programs "$fixtures/heredoc.sh") — suites build fixtures containing awk on purpose, and this file's own self-test fixtures do too. A scanner that reads them fails every suite on its own test data."
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
