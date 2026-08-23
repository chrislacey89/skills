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
#   3. (WITHDRAWN.) This suite used to assert that both files carried the tell's
#      wording. Those assertions are cut — see NOT PINNED, below.
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
# NOT PINNED — WORDING, and this is a deliberate subtraction rather than a gap.
# Two assertions used to check that a specific sentence appeared at both the
# implement-time and review-time sites. They are gone. The reasoning, from the
# independent reviewer who called it:
#
#   These assertions pinned the wording of one sentence at two sites. Wording is
#   not a checkable property — every green they produced was a guess about
#   phrasing that happened to hold, and four rounds of tightening the pattern
#   never changed that. They were defeated by a one-word reword at one site and
#   by moving the sentence to a different rule at the other, at every revision
#   including the last. The cross-reference resolver stays: "does this heading
#   exist in that file" is decidable, and it caught every stale-citation
#   mutation four independent passes threw at it. CLAUDE.md rule (a) before
#   rule (b) — the cheapest claim to keep accurate is the one not made.
#
# Do not restore them as a tighter grep. A tighter grep is a narrower guess
# about how the sentence will be phrased next year, which is the same bet at
# worse odds. If the two halves need to stay in sync, the checkable version is a
# reference one file makes to the other that the resolver can decide — not a
# substring of prose.
#
# Also deliberately NOT pinned: the wording of the technique, the table of type
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

# Floors. Named rather than inline, so lowering one is a visible edit to a
# constant instead of a silent condition — the convention
# scripts/test-oracle-table-coverage.sh sets with MIN_TABLES.
MIN_SHAPE1=3   # [t.md](t.md) § *H*  — the dominant idiom
MIN_SHAPE2=2   # [t.md § H](t.md)    — tdd/SKILL.md's older form
MIN_TO_RULE=3  # references aimed at the type-level rule itself

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# coverage: enumerated — the four files this suite asserts against, each bound
# to a named variable above. Not derivable: the set is "the files this suite
# makes claims about", which is a property of the assertions, not of the tree.
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
shape1_total=0
shape2_total=0

# Escape a heading for literal use inside a POSIX ERE. Headings routinely carry
# regex metacharacters (parentheses, dots, `*`), and an unescaped one turns a
# literal match into a pattern match — the same widening this function was fixed
# for, one level down.
# shellcheck disable=SC2329  # invoked below inside resolves(), via command substitution
esc_re() {
    printf '%s' "$1" | sed 's/[][\.^$*+?(){}|/]/\\&/g'
}

resolves() {  # $1 = target file, $2 = heading text
    # ANCHORED, both arms. The first draft used bare `grep -qF`, so a citation
    # only had to be a PREFIX of the real heading: renaming `## The Oracle` to
    # `## The Oracle (deprecated, see below)` left every citation to the old
    # name resolving and the suite at 24/0, while a non-prefix rename was
    # correctly caught. That is this branch's own thesis turned on its own
    # mechanism — a check whose accepted input domain is wider than its name
    # records.
    #
    # `$` anchors the `## ` form to end-of-line. The bold form is anchored by
    # its closing `**`, allowing exactly ONE optional trailing punctuation mark:
    # real rules read `**…call sites.**` while citations omit the period. One
    # mark, not `.*` — anything looser reopens the prefix hole.
    local e
    e="$(esc_re "$2")"
    grep -qE -- "^## ${e}[[:space:]]*$" "$1" \
        || grep -qE -- "[*][*]${e}[[:punct:]]?[*][*]" "$1"
}

# Escape a heading for use inside a POSIX ERE. Headings carry regex
# metacharacters routinely (parentheses, dots, `*`), and an unescaped one turns
# a literal match into a pattern match — which is the same widening this
# function was just fixed for, one level down.
esc_re() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|\/]/\\\\&/g'
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
    [ -n "$tgt" ] && [ -n "$head" ] && { shape1_total=$((shape1_total + 1)); check_ref "$src" "$tgt" "$head"; }
done <<EOF
$(grep -n -- '\.md) § \*' tdd/*.md | sed 's|^\(tdd/[A-Za-z0-9.-]*\):[0-9]*:|\1:|' || true)
EOF

# Shape 2: [target.md § Heading](target.md)
while IFS= read -r line; do
    [ -n "$line" ] || continue
    src="${line%%:*}"; rest="${line#*:}"
    tgt="$(printf '%s' "$rest" | sed -n 's/.*\[\([a-z0-9-]*\.md\) § .*/\1/p')"
    head="$(printf '%s' "$rest" | sed -n 's/.*\.md § \([^]]*\)\].*/\1/p')"
    [ -n "$tgt" ] && [ -n "$head" ] && { shape2_total=$((shape2_total + 1)); check_ref "$src" "$tgt" "$head"; }
done <<EOF
$(grep -n -- '\[[a-z0-9-]*\.md § ' tdd/*.md | sed 's|^\(tdd/[A-Za-z0-9.-]*\):[0-9]*:|\1:|' || true)
EOF

# Each extractor is a separate point of vacuous green: a broken regex finds
# nothing, every loop body is skipped, and the section prints clean. PER-SHAPE
# floors, not one aggregate — the first draft floored the sum at 4, so breaking
# Shape 2 alone left Shape 1's 5 references clearing the bar and a genuinely stale
# Shape-2 reference passed 21/0. Verified before the fix. A shared floor cannot
# distinguish "this shape found nothing" from "the other shape found plenty."
for shape in "1:$shape1_total:$MIN_SHAPE1" "2:$shape2_total:$MIN_SHAPE2"; do
    n="${shape#*:}"; found="${n%%:*}"; floor="${n##*:}"
    [ "$found" -ge "$floor" ] || fatal "extractor for reference shape ${shape%%:*} found $found reference(s), expected at least $floor — that regex no longer matches the idiom. An extractor that finds nothing passes everything it was meant to check."
done
ok "$ref_total cross-references discovered and resolved — shape 1: $shape1_total, shape 2: $shape2_total ($ref_bad unresolved)"

# The resolver proves references RESOLVE. It does not prove the type-level rule is
# still REACHABLE -- delete every pointer and zero broken references remain. Floor
# the count of references aimed at this specific heading.
# `|| true` is load-bearing, not defensive noise. `grep -c` exits 1 when NO file
# matches, and under `set -euo pipefail` (above) that kills the script inside this
# command substitution — on precisely the condition the floor below exists to
# report. Verified before the fix: deleting every pointer produced a bare `exit 1`
# with no FAIL line, no reason, no summary, and four later sections silently
# skipped. Every other grep in this file that can legitimately return zero carries
# the same guard; this one was the omission.
to_rule="$(grep -c -F -- "§ *${heading}*" tdd/*.md 2>/dev/null | awk -F: '{n+=$2} END {print n+0}' || true)"
to_rule="${to_rule:-0}"
if [ "$to_rule" -ge "$MIN_TO_RULE" ]; then
    ok "$to_rule cross-references point at the type-level rule"
else
    bad "only $to_rule cross-reference(s) point at the type-level rule; expected at least $MIN_TO_RULE" \
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
section "the heading resolver still resolves (self-test)"

# Seven assertions above ride on resolves(). Neutering its body to `return 0`
# left the suite at 24 passed, 0 failed with every "resolves in" line still
# printing ok — verified. It had no probe, and the header disclosed two ceilings
# but not this one. Same plant/miss shape scripts/test-oracle-table-coverage.sh
# uses for its detector, and for the same reason: a matcher whose healthy state
# is "everything matches" cannot report its own death.
res_probe="$(mktemp)"
printf '## The Oracle\n\n**Cover Both Failure Directions.** body text\n' > "$res_probe"

if resolves "$res_probe" "The Oracle"; then
    ok "resolver: an exact `## ` heading resolves"
else
    bad "resolver: an exact heading no longer resolves" "every reference check above is now failing for the wrong reason"
fi
if resolves "$res_probe" "Cover Both Failure Directions"; then
    ok "resolver: an exact bold rule resolves"
else
    bad "resolver: an exact bold rule no longer resolves" "the second arm is dead; bold-rule citations cannot be checked"
fi
if resolves "$res_probe" "The Oracle Problem"; then
    bad "resolver: a heading that does NOT exist resolved anyway" \
        "the matcher accepts more than it names — a stale citation would pass"
else
    ok "resolver: a non-existent heading does not resolve"
fi
# The NEW-A regression, pinned directly: the citation is a strict prefix of a
# longer real heading. This is the one that shipped.
printf '## The Oracle (deprecated, see below)\n' > "$res_probe"
if resolves "$res_probe" "The Oracle"; then
    bad "resolver: a citation that is only a PREFIX of the real heading resolved" \
        "an append-rename leaves every citation to the old heading silently valid — the defect this anchor fixes"
else
    ok "resolver: a prefix-only citation does not resolve"
fi
rm -f "$res_probe"

# -----------------------------------------------------------------------------
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
