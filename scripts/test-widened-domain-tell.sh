#!/usr/bin/env bash
# test-widened-domain-tell.sh — contract test for the type-level-invariants
# material added to /tdd by issue #268, and the three other sites that point at
# it or restate its trigger.
#
# THE DRIFT CLASS. Issue #268 asked outright whether a mechanism exists here at
# all, and answered "probably not — this is a design technique, not a checkable
# claim about tool behavior." That answer is correct about the *technique*: no
# check in this repo can assert anything about a downstream repo's types. It is
# wrong about the *change*, which creates four hand-maintained cross-references
# and nothing constructing their agreement — the exact shape named in
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md
# and pinned for /compound by scripts/test-q4-mechanism-names.sh. This suite is
# the pinnable residue after that distinction is drawn, and no more.
#
# THE INCIDENT. A downstream verbatim-quote checker — the guard against a model
# inventing a quote it claims to have found on a page — was widened from the
# page's extracted reading text to its raw HTML. Both values are plain `string`,
# so the contract never widened with the behavior, and a fabricated quote
# colliding with a script body or an attribute now passes the check whose entire
# job is catching fabrications. The parameter was renamed `pageText` → `haystack`
# in the same diff, deleting the only place the precondition was recorded.
# #266 shipped the review-time half; #268 ships the implement-time half. The two
# halves are useless apart, and each one's text says so about the other.
#
# WHAT IT PINS, all extracted from the real files rather than restated here:
#   1. The section heading exists in tdd/interface-design.md. A rename fails
#      LOUD (fatal), never vacuously green — every other assertion depends on it.
#   2. Every § cross-reference in tdd/ resolves to a heading that exists in the
#      file it names — the reference SET discovered by scanning, not restated
#      here. A § cross-reference is a claim about another file's contents
#      maintained by hand; rename the heading and each citing sentence silently
#      becomes false, still reading fluently, with no reader counting. Two floors
#      sit under it: a fatal minimum on references DISCOVERED (a broken extractor
#      finds nothing, skips every loop body, and prints clean), and a minimum on
#      references aimed at the type-level rule (resolving is not reaching — delete
#      every pointer and zero broken references remain).
#   3. Both files carry the tell — the widened-input-domain trigger and the
#      neutral-rename signal — at the implement-time site (tdd/interface-design.md)
#      and the review-time site (pre-merge/review-checklist.md). Each file's
#      prose asserts the other half exists; delete one and the survivor lies.
#   4. tdd/SKILL.md declares Wlaschin under `sources:`. CLAUDE.md § Editing
#      Skills says only to claim a source the body operationalizes; the inverse
#      drift — operationalizing one and never declaring it — is what a body
#      quoting him twice while the frontmatter omits him would be.
#   5. The compiler-worklist rule carries its total-function precondition. #268
#      named this as the thing that must be stated "or the rule gets cargo-culted
#      into codebases where it does nothing" — the precondition is the only part
#      of that rule whose absence is silently harmful rather than merely absent.
#   6. The proportionality bound survives. #268's Non-Goals forbid a rule that
#      reads as "wrap every string"; that bound is one sentence and is the single
#      most deletable thing in the section.
#
# THE DISCLOSED CEILING, in two instances of one shape. A constant that happens to
# equal the truth is indistinguishable from a value read from the file, and a
# belt-and-braces pair removed together leaves nothing to catch the removal. So:
#   (a) replacing the heading extraction with a literal equal to the current
#       heading survives on its own;
#   (b) breaking the awk section range AND deleting its overrun guard in the same
#       edit survives, though either alone is caught.
# Neither is killable from inside bash. What the checks do instead is make each
# laundering fail the moment it would matter — hardcode the heading AND rename it
# in the subject, and the suite goes fatal. Both verified by mutation. This is the
# limit scripts/test-q4-mechanism-names.sh discloses about its number table, and
# naming it is preferable to a check that implies a guarantee it does not have.
#
# HOW THE MUTATION BATTERY MUST BE RUN. Do not `git checkout --` a file whose fix
# is still uncommitted — that reverts the working tree to the last COMMIT, so the
# mutation and every test after it run against the old file. Three "survivors"
# during this suite's own review were that mistake, not real holes. Copy the tree
# to a scratch directory per mutation, and assert the mutation actually landed
# before believing the result.
#
# Deliberately NOT pinned: the wording of the technique, the table of type
# shapes, the code examples, or the review-cadence note's threshold. Forcing
# those to hold still would forbid legitimate rewriting, and a suite that
# reddens on good edits gets deleted. Also not pinned: that the technique is
# *correctly applied* anywhere — that is the judgment this repo cannot check,
# and saying so plainly is the point of the section's own closing paragraph.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

iface="tdd/interface-design.md"
refac="tdd/refactoring.md"
skill="tdd/SKILL.md"
checklist="pre-merge/review-checklist.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

for f in "$iface" "$refac" "$skill" "$checklist"; do
    [ -f "$f" ] || fatal "$f not found. The file moved, or this suite is stale."
done

# -----------------------------------------------------------------------------
section "the section heading exists and is read from the file, not restated"

# The numbered-rule prefix ("4. ") is deliberately excluded from what gets
# matched downstream: renumbering the list is a legitimate edit that must not
# redden this suite, while renaming the rule must.
heading_line="$(grep -n '^[0-9]\+\. \*\*Make an illegal input' "$iface" | head -1 || true)"
[ -n "$heading_line" ] || fatal "no 'Make an illegal input …' rule in $iface. It was renamed or removed; update this suite with it."

# Strip "N. " and the surrounding ** to get the bare heading text every citing
# site must reproduce. This is THE value the rest of the suite compares against,
# and it is extracted rather than hardcoded — hardcoding it here would make a
# renamed heading pass by construction at exactly the moment it should fail.
heading="$(printf '%s' "${heading_line#*:}" | sed 's/^[0-9]*\. //; s/^\*\*//; s/\*\*$//')"
[ -n "$heading" ] || fatal "the rule heading parsed to an empty string; the numbering or bold convention changed."
case "$heading" in
    *"illegal input"*) : ;;
    *) fatal "parsed a heading that does not look like the rule: \"$heading\"" ;;
esac

# ORACLE SELF-CHECK. $heading is the one value every assertion below compares
# against, so it is the one thing that can quietly stop being read from the
# subject. Rewriting the line above as a literal makes the citer checks pass by
# construction — and passes at exactly the moment the heading is renamed, which
# is when nobody looks. Verified: that mutation survived the first draft.
# Requiring the extracted text to be a substring of the line it came from is
# what a literal cannot satisfy once the subject moves away from it.
case "$heading_line" in
    *"$heading"*) ok "the rule heading is findable, and was extracted from $iface: \"$heading\"" ;;
    *) fatal "\"$heading\" does not appear in the line it was supposedly parsed from — the extraction was replaced by a literal." ;;
esac

# -----------------------------------------------------------------------------
section "every cross-reference in tdd/ resolves to a heading that exists"

# C2 FIX (derived, not restated). The first draft hand-listed the two citing files.
# Appending a THIRD citer carrying a stale heading passed 17/17 — the count guarded
# the list shrinking and nothing guarded the repo growing a citer the list did not
# know about. That is the shape docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md
# names ("a guard whose own coverage is a hand-maintained subset of the thing it
# guards"), whose Prevention #2 is "derive the coverage instead of restating it,
# where the language allows." It does here: the § idiom survives a heading rename,
# so the reference SET is discoverable while the heading TEXT stays the extracted
# value being compared.
#
# Scope note: this now checks every § cross-reference in tdd/, not only the ones
# this change introduced. That is deliberate — a resolver keyed to one heading
# would need editing the next time a heading is added, which is the drift over
# again. Three reference shapes are in use:
#     [target.md](target.md) § *Heading*     -> the dominant form
#     [target.md § Heading](target.md)       -> tdd/SKILL.md's older form
#     `target.md` § Heading                  -> unlinked, tdd/tests.md
# A heading resolves if the target file carries it as "## H", "**H", or "N. **H".

ref_total=0
ref_bad=0

resolves() {  # $1 = target file, $2 = heading text
    grep -qF -- "## $2" "$1" || grep -qF -- "**$2" "$1"
}

check_ref() {  # $1 = source file, $2 = target basename, $3 = heading
    local src="$1" tgt="tdd/$2" head="$3"
    ref_total=$((ref_total + 1))
    if [ ! -f "$tgt" ]; then
        bad "$src references $2, which does not exist" "the § reference points at a missing file"
        ref_bad=$((ref_bad + 1)); return
    fi
    if resolves "$tgt" "$head"; then
        ok "$src § *$head* resolves in $2"
    else
        bad "$src cites \"$head\" in $2, which has no such heading" \
            "the § reference is now false; it still reads fluently and no reader counts"
        ref_bad=$((ref_bad + 1))
    fi
}

# Shape 1: [target.md](target.md) § *Heading*
while IFS= read -r line; do
    [ -n "$line" ] || continue
    src="${line%%:*}"; rest="${line#*:}"
    tgt="$(printf '%s' "$rest" | sed -n 's/.*\](\([a-z0-9-]*\.md\)) § \*.*/\1/p')"
    head="$(printf '%s' "$rest" | sed -n 's/.*\.md) § \*\([^*]*\)\*.*/\1/p')"
    [ -n "$tgt" ] && [ -n "$head" ] && check_ref "$src" "$tgt" "$head"
done <<EOF
$(grep -n -- '\.md) § \*' tdd/*.md | sed 's|^\(tdd/[A-Za-z0-9.-]*\):[0-9]*:|\1:|' || true)
EOF

# Shape 2: [target.md § Heading](target.md)
while IFS= read -r line; do
    [ -n "$line" ] || continue
    src="${line%%:*}"; rest="${line#*:}"
    tgt="$(printf '%s' "$rest" | sed -n 's/.*\[\([a-z0-9-]*\.md\) § .*/\1/p')"
    head="$(printf '%s' "$rest" | sed -n 's/.*\.md § \([^]]*\)\].*/\1/p')"
    [ -n "$tgt" ] && [ -n "$head" ] && check_ref "$src" "$tgt" "$head"
done <<EOF
$(grep -n -- '\[[a-z0-9-]*\.md § ' tdd/*.md | sed 's|^\(tdd/[A-Za-z0-9.-]*\):[0-9]*:|\1:|' || true)
EOF

# The extractor is the single point of vacuous green here: a broken regex finds
# nothing, every loop body is skipped, and the section prints clean. Floor it.
if [ "$ref_total" -ge 4 ]; then
    ok "$ref_total cross-references discovered and resolved ($ref_bad unresolved)"
else
    fatal "only $ref_total § cross-references discovered in tdd/ — the reference idiom changed and the extractor no longer finds them. A resolver that finds nothing passes everything."
fi

# The resolver proves references RESOLVE. It does not prove the type-level rule is
# still REACHABLE -- delete every pointer and zero broken references remain. Floor
# the count of references aimed at this specific heading.
to_rule="$(grep -c -F -- "§ *${heading}*" tdd/*.md | awk -F: '{n+=$2} END {print n+0}')"
if [ "$to_rule" -ge 3 ]; then
    ok "$to_rule cross-references point at the type-level rule"
else
    bad "only $to_rule cross-reference(s) point at the type-level rule; expected at least 3" \
        "the reader arrives at the planning and refactor steps with no route to it"
fi

# refactoring.md carries TWO pointers serving different readers -- the Discipline
# rule (a type must be closed before the compiler can help) and the Candidates
# entry (primitive obsession). Losing either strands one reader, and a whole-file
# count cannot tell which one went.
#
# C3 FIX (bounded ranges). The first draft used sed ranges of the form
# /^## Discipline$/,/^## Candidates$/ and /^## Candidates$/,$p. Both overrun:
# moving the Discipline pointer into a new section inserted before ## Candidates
# passed 17/17 with "Discipline points at the type-level rule" printed ok, and so
# did moving the Candidates pointer into a new trailing section. Both reproduced.
# Each range now stops at the NEXT "## " heading, and a body that still contains
# one means the terminator failed.
section_body() {  # $1 = file, $2 = heading text
    awk -v want="## $2" '
        $0 == want { inside = 1; next }
        inside && /^## / { exit }
        inside { print }
    ' "$1"
}

refac_seen=0
for label in Discipline Candidates; do
    refac_seen=$((refac_seen + 1))
    body="$(section_body "$refac" "$label")"
    [ -n "$body" ] || fatal "could not extract the '$label' section of $refac; its headings changed."
    if printf '%s' "$body" | grep -q '^## '; then
        fatal "the '$label' extraction from $refac still contains a '## ' heading — the range overran its section, which is the defect this fix exists to close."
    fi
    if printf '%s' "$body" | grep -qF -- "§ *${heading}*"; then
        ok "$refac § $label points at the type-level rule"
    else
        bad "$refac § $label lost its pointer to the type-level rule" \
            "the other section still has one, so a whole-file count would not have caught this"
    fi
done

if [ "$refac_seen" -eq 2 ]; then
    ok "both $refac sections were checked"
else
    bad "expected to check 2 sections of $refac, checked $refac_seen" \
        "the section list was shortened; a per-section check that skips a section is a whole-file check wearing its name"
fi

# -----------------------------------------------------------------------------
section "the tell is stated at both the implement-time and review-time sites"

# The trigger #268 settled on: a parameter's accepted input domain widens while
# its type does not, most visibly a rename from a domain/provenance-specific
# name to a neutral one. Two tokens per site, because the widening alone is the
# condition and the rename alone is the signal — a site keeping one and losing
# the other keeps a rule nobody can spot in a diff.
tell_seen=0
for pair in "implement-time:$iface" "review-time:$checklist"; do
    label="${pair%%:*}"
    f="${pair#*:}"
    tell_seen=$((tell_seen + 1))
    if grep -qi -- 'widened input domain' "$f"; then
        ok "$label site ($f) states the widened-input-domain condition"
    else
        bad "$label site ($f) no longer states the widened-input-domain condition" \
            "the other site's prose claims this half exists; it now says something false"
    fi
    if grep -qi -- 'neutral one' "$f"; then
        ok "$label site ($f) states the neutral-rename signal"
    else
        bad "$label site ($f) no longer states the neutral-rename signal" \
            "the condition survives with nothing to spot it by, which is the pre-#266 state"
    fi
done

# Same vacuous-green hazard as the citer loop, and worse here: the whole point
# of this section is that BOTH halves carry the tell, so a loop silently reduced
# to one site asserts the exact opposite of what it is named for.
if [ "$tell_seen" -eq 2 ]; then
    ok "both halves were checked"
else
    bad "expected to check 2 sites, checked $tell_seen" \
        "a one-site check cannot show the two halves agree, which is this section's only claim"
fi

# Each half claims the other exists. Pin the claim, so deleting the far half
# turns the surviving cross-reference red instead of quietly false.
if grep -qF -- 'review-checklist.md' "$iface"; then
    ok "$iface names the review-time site it is the other half of"
else
    bad "$iface no longer names its review-time counterpart" \
        "the two halves become independent restatements, which is how they drift apart"
fi

# -----------------------------------------------------------------------------
section "the source is declared where it is operationalized"

# CLAUDE.md § Editing Skills: only claim a source the body operationalizes. The
# body now quotes Wlaschin in two reference files; the frontmatter must say so.
frontmatter="$(sed -n '2,/^---$/p' "$skill")"
if printf '%s' "$frontmatter" | grep -qF -- 'Domain Modeling Made Functional'; then
    ok "$skill declares Wlaschin under sources:"
else
    bad "$skill does not declare Wlaschin under sources:" \
        "two of its reference files quote him; an undeclared source is the inverse of an unearned one"
fi

# And the reverse direction: a declared source with nothing operationalizing it
# is the drift CLAUDE.md actually forbids. At least one file OTHER THAN the one
# holding the declaration must cite him.
#
# SKILL.md is excluded deliberately, and this is an oracle fix rather than a
# style choice. The first draft globbed tdd/*.md, which includes the very file
# whose frontmatter carries the claim — so the assertion matched its own subject
# and passed by construction. It would have stayed green with every reference
# file stripped of Wlaschin, i.e. green in exactly the state it exists to catch.
# Same shape as the number-table tautology recorded in
# docs/solutions/testing-patterns/mutate-the-oracle-not-only-the-subject-2026-08-19.md.
wlaschin_files="$(grep -l -F -- 'Wlaschin' tdd/*.md | grep -v -x -- "$skill" | tr '\n' ' ' || true)"
case " $wlaschin_files " in
    *" $skill "*) fatal "$skill is in the operationalized set — the exclusion was removed, so this assertion now matches its own subject and passes by construction." ;;
esac
if [ -n "$wlaschin_files" ]; then
    ok "the declared source is operationalized outside the declaration, in: $wlaschin_files"
else
    bad "no tdd/ reference file cites Wlaschin, but sources: declares him" \
        "an unearned source claim — CLAUDE.md § Editing Skills forbids exactly this"
fi

# -----------------------------------------------------------------------------
section "the two most deletable sentences are still there"

# Both are load-bearing negatives: prose that constrains where the rule applies
# rather than asserting anything. Negatives read as hedging and get cut first,
# and each one's absence is silently harmful rather than merely absent.

# #268: "that precondition needs stating, or the rule gets cargo-culted into
# codebases where it does nothing."
if grep -qi -- 'total functions over closed types' "$refac"; then
    ok "$refac states the total-function precondition on the compiler-worklist rule"
else
    bad "$refac dropped the total-function precondition" \
        "the compiler-worklist rule gives no worklist over open types; unstated, it is applied where it does nothing"
fi

# #268 Non-Goals: "Not a mandate to brand every primitive… A rule that reads as
# 'wrap every string' will be ignored or, worse, followed."
if grep -qi -- 'brand every primitive' "$iface"; then
    ok "$iface keeps the proportionality bound"
else
    bad "$iface dropped the proportionality bound" \
        "without it the rule reads as 'wrap every string', which #268 named as its own failure mode"
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
