#!/usr/bin/env bash
# test-escaped-defect-join-claims.sh — contract test for the two claims
# docs/escaped-defect-join.md makes about *other files in this repo*.
#
# THE DRIFT CLASS. A measurement write-up earns its authority by quoting the
# rules it measured against. Those quotes live in one file and the rules live in
# another, with nothing relating the two — the restated-claim class described in
# docs/restated-claims.md, in its plainest form. Edit `qa/SKILL.md`'s
# "No file paths or line numbers" rule and the write-up keeps asserting the old
# wording, at a line number that now points somewhere else. Nothing fails.
#
# THE INCIDENT. #329's own first draft. The doc recommended getting bug reports
# to name a `file:line` "which the issue template already asks for" — the
# opposite of what /qa and /triage-issue say, and there is no issue template.
# The correction inverted the recommendation, so the quoted rules are now
# load-bearing: if they change, the doc's central coverage finding changes with
# them.
#
# WHAT IT PINS, every side extracted from the real files:
#   1. Every `"<quote>" (`<path>:<line>`)` citation in the write-up resolves —
#      the file is tracked, the line exists, and the quoted text is on it.
#   2. Every figure /improve-pipeline restates from the write-up (it summarizes
#      the result inline, so a reader need not open the doc) still appears in
#      the write-up. A summary that outlives its source is the drift.

set -u
cd "$(dirname "$0")/.." || exit 1

DOC="docs/escaped-defect-join.md"
SKILL="improve-pipeline/SKILL.md"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }

[ -f "$DOC" ]   || { printf 'FATAL %s is missing\n' "$DOC"; exit 1; }
[ -f "$SKILL" ] || { printf 'FATAL %s is missing\n' "$SKILL"; exit 1; }

printf '%s: quoted cross-file citations resolve\n' "$DOC"

# Whitespace-normalize first: a citation wraps across lines in the source.
# Extract every `"<quote>" (`<path>:<line>`)` pair as quote<TAB>path<TAB>line.
# shellcheck disable=SC2016  # the backticks are literal markdown, not command substitution
citations="$(tr '\n' ' ' < "$DOC" | grep -o '"[^"]*" *(`[^`]*:[0-9]*`)' \
    | tr -s ' ' \
    | sed -E 's/^"(.*)" *\(`([^`]*):([0-9]+)`\)$/\1\t\2\t\3/')"

[ -n "$citations" ] || { printf 'FATAL found no quoted citations in %s — the parser or the doc changed shape\n' "$DOC"; exit 1; }

n_cit=0
while IFS=$'\t' read -r quote path line; do
    [ -n "$path" ] || continue
    n_cit=$((n_cit + 1))
    label="$path:$line"
    if ! git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
        bad "$label" "cited file is not tracked in this repo"
        continue
    fi
    actual="$(sed -n "${line}p" "$path")"
    if [ -z "$actual" ]; then
        bad "$label" "line $line does not exist in $path"
        continue
    fi
    # The doc collapses the quote to one line; the source may wrap it. Compare
    # against the cited line plus its successor, whitespace-normalized.
    window="$(sed -n "${line},$((line + 1))p" "$path" | tr '\n' ' ' | tr -s ' ')"
    if printf '%s' "$window" | grep -qF -- "$quote"; then
        ok "$label quotes its source"
    else
        bad "$label" "quoted text is not at that line: \"$quote\""
    fi
done <<< "$citations"

[ "$n_cit" -ge 3 ] || bad "citation count" "expected at least 3 quoted citations, parsed $n_cit"

printf '%s: figures restated from %s still appear there\n' "$SKILL" "$DOC"

# The Phase 2 note summarizes the run inline. Every number it states must be a
# number the write-up states, or the summary has outlived its source.
# Paragraphs in this repo are single physical lines (CLAUDE.md, "Reading a prose
# diff"), so the note is exactly the line that opens it -- no multi-line join,
# and no greedy match that runs on into the Skeptic bullet further down.
note="$(grep -F 'Do not price a proposal in rework' "$SKILL")"
[ -n "$note" ] || { printf 'FATAL the Phase 2 rework note is missing from %s\n' "$SKILL"; exit 1; }

n_fig=0
# Extract the figures as whole phrases rather than bare integers, so a year or a
# phase number in the surrounding prose is not mistaken for a claim.
figures="$(printf '%s' "$note" | grep -oE '[0-9]+ merged PRs|[0-9]+ of [0-9]+ bugs' | sort -u)"
[ -n "$figures" ] || { printf 'FATAL parsed no figures out of the Phase 2 note — the note or the parser changed shape\n'; exit 1; }

while read -r fig; do
    [ -n "$fig" ] || continue
    n_fig=$((n_fig + 1))
    if grep -qF -- "$fig" "$DOC"; then
        ok "\"$fig\" is stated in $DOC"
    else
        bad "\"$fig\"" "restated in $SKILL but not present in $DOC"
    fi
done <<< "$figures"

[ "$n_fig" -ge 2 ] || bad "figure count" "expected at least 2 restated figures, parsed $n_fig"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
