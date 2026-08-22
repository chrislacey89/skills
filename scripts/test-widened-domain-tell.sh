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
#   2. Every site that cites the section BY NAME uses the heading's exact text.
#      A § cross-reference is a claim about another file's contents maintained by
#      hand; rename the heading and each citing sentence silently becomes false,
#      still reading fluently, with no reader counting.
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
# THE DISCLOSED CEILING. Replacing the heading extraction with a literal equal to
# the current heading survives, and cannot be killed from inside bash: a constant
# that happens to equal the truth is indistinguishable from a value read from the
# file. What the self-check below does instead is make the laundering fail the
# moment it would matter — hardcode the heading AND rename it in the subject, and
# the suite goes fatal. Verified by mutation. This is the same class of limit
# scripts/test-q4-mechanism-names.sh discloses about its number table, and naming
# it is preferable to a check that implies a guarantee it does not have.
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
section "every site citing the section by name uses the heading's exact text"

# The § idiom is this repo's convention for pointing at another file's section
# (tdd/SKILL.md already uses it for tests.md § The Oracle). Each of these is a
# sentence asserting something about $iface's contents.
citers="$refac $skill"
citer_seen=0
for f in $citers; do
    citer_seen=$((citer_seen + 1))
    n="$(grep -c -F -- "§ *${heading}*" "$f" || true)"
    if [ "$n" -ge 1 ]; then
        ok "$f cites the section by its exact heading ($n site(s))"
    else
        # Distinguish "cites it wrong" from "does not cite it at all" — the two
        # need different fixes, and reporting them the same way sends the reader
        # looking for a typo when the pointer is simply gone.
        if grep -q 'illegal input' "$f"; then
            bad "$f references the rule but not by its current heading" \
                "expected the exact text: § *${heading}*"
        else
            bad "$f no longer points at the type-level rule at all" \
                "the reader arrives at the refactor/planning step with no route to it"
        fi
    fi
done

# A loop over an empty list reports nothing and exits 0 — vacuously green, and
# indistinguishable in the output from a loop that checked everything. Pin the
# count of iterations, not just the result of each.
if [ "$citer_seen" -eq 2 ]; then
    ok "both citing files were checked"
else
    bad "expected to check 2 citing files, checked $citer_seen" \
        "the list of citers changed; update this suite with it rather than letting the loop shrink silently"
fi

# refactoring.md carries TWO pointers serving different readers — the Discipline
# rule (where a type must be closed before the compiler can help) and the
# Candidates entry (primitive obsession). Losing either strands one reader, and
# a whole-file count of 1 cannot tell which one went. Check them where they live.
refac_seen=0
for part in "Discipline:## Discipline:## Candidates" "Candidates:## Candidates:"; do
    refac_seen=$((refac_seen + 1))
    label="${part%%:*}"
    rest="${part#*:}"
    start="${rest%%:*}"
    end="${rest#*:}"
    if [ -n "$end" ]; then
        body="$(sed -n "/^${start}\$/,/^${end}\$/p" "$refac")"
    else
        body="$(sed -n "/^${start}\$/,\$p" "$refac")"
    fi
    [ -n "$body" ] || fatal "could not extract the '$label' section of $refac; its headings changed."
    if printf '%s' "$body" | grep -qF -- "§ *${heading}*"; then
        ok "$refac § $label points at the type-level rule"
    else
        bad "$refac § $label lost its pointer to the type-level rule" \
            "the other section still has one, so a whole-file count would not have caught this"
    fi
done

# Third loop, third counter. Every list-driven assertion in this suite is one
# emptied list away from a full green, and an emptied list is invisible in the
# output — it prints nothing, which reads the same as "nothing was wrong."
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
