#!/usr/bin/env bash
# test-q4-mechanism-names.sh — contract test for /compound's Q4 mechanism list
# and the two other sites that count it.
#
# THE DRIFT CLASS. Phase 1's Q4 declares the list of things a lesson is allowed
# to become. Phase 4's promote-to-mechanism rule re-enumerates that list AND
# cross-references it *by count* — "one of the five Q4 names", "if none of the
# five". A count is a claim about another file's contents maintained by hand,
# which is the shape `CLAUDE.md` rule (b) says to pin and which
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md
# names outright: a cross-reference with nothing constructing the agreement.
# Add or remove a name at one site and the other site's sentence silently
# becomes false — it still reads fluently, and no reader counts.
#
# THE INCIDENT. Issue #266 added the fifth name (a filed issue in
# chrislacey89/skills, for lessons whose preventing change belongs to the pack
# rather than the downstream repo). Its own Recommended Changes table had to
# say "Both sites or they drift — `:273` cross-references 'the four Q4 names'
# by count" — i.e. the drift was foreseen in prose and, before this suite,
# guarded by nothing but the author remembering. Under the rule #257 shipped
# and #266 extends, that is not a valid outcome.
#
# WHAT IT PINS, all extracted from the real file rather than restated here:
#   1. Both enumerations are findable at their anchors (a rename fails LOUD,
#      never vacuously green).
#   2. The two lists hold the SAME NUMBER of names.
#   3. Both number-words in Phase 4's sentence equal that number.
#   4. The pack-level name (the one that points at another repo) appears in
#      both lists — it is the member most likely to be dropped from one site,
#      being the only one with no downstream artifact behind it.
#   5. Its POSITION in the list matches every ordinal the prose spends on it —
#      the guard heading and Phase 5's staging exemption. Pinning the count
#      alone left those hand-maintained: adding a sixth name and updating both
#      number-words kept the suite green while the ordinals silently began
#      naming a different member, which would scope the ownership guard to the
#      wrong mechanism and exempt one that does need staging.
#   6. Its ownership guard is declared exactly once, and Phase 6's two report
#      blocks can represent it. A mechanism the report cannot print is the
#      "Phase 5 was staging the prose and not the mechanism" defect (#257).
#   7. Phase 5 still carries the DO-CONFIRM that verifies a cited pack-level
#      issue actually exists. See that section for why this is a weaker pin
#      than the rest and why it is the honest ceiling here.
#   8. The filing-owner gate and the anonymization contract are both present.
#      These are the confidentiality half: the fifth mechanism is the only one
#      that moves words OUT of the repo that learned the lesson, a local gh
#      account guard routes identity rather than content and so does not stop
#      it, and the body is a narrative about the work rather than a copy of
#      its code. Both are prose an agent applies — pinning their presence is
#      what stops a future edit from quietly deleting the boundary.
#
# Deliberately NOT pinned: the wording of the names. Q4 says "a stronger test"
# where Phase 4 says "a test"; forcing those to match would be a false
# uniformity, and a suite that forbids legitimate rewording gets deleted. Nor is
# WHICH name sits at a non-pack position — swapping "an assertion" for "a
# fixture" at one site while the count holds stays green. That is a disclosed
# limit, not an oversight: pinning it means pinning the wording.
#
# PARSING NOTE. Each list is read to its sentence terminator — "?" for Q4, the
# first ". " for Phase 4 — and split on ", ". A name containing ", " or ". "
# would miscount. That is accepted: these are short noun phrases, and the
# alternative (a regex over the prose) is the restatement this suite exists to
# forbid.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

compound_skill="compound/SKILL.md"

# Anchors. Each opens an enumeration; a miss is FATAL, not a failed assertion,
# because a moved anchor means this suite is stale rather than the file wrong.
q4_anchor='from entering the codebase again — '
phase4_anchor='Q4 names: '
guard_marker='**The fifth name is scoped by ownership'
# The name that points outside this repo. Matched by the repo slug, not by the
# phrasing around it, so a reworded bullet still counts.
pack_name_token='chrislacey89/skills'

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }

fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# Two tables, because the prose uses two registers: Phase 4 counts the list with
# a CARDINAL ("the five Q4 names"), while the guard heading and Phase 5's staging
# exemption pick a member with an ORDINAL ("The fifth name is scoped by...").
# Feeding an ordinal to the cardinal table returns empty, which reads as "could
# not parse" rather than "mismatch" — a false red that hides the real assertion.
word_to_int() {
    case "$1" in
        two) echo 2 ;; three) echo 3 ;; four) echo 4 ;; five) echo 5 ;;
        six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;;
        ten) echo 10 ;; *) echo "" ;;
    esac
}

ordinal_to_int() {
    case "$1" in
        second) echo 2 ;; third) echo 3 ;; fourth) echo 4 ;; fifth) echo 5 ;;
        sixth) echo 6 ;; seventh) echo 7 ;; eighth) echo 8 ;; ninth) echo 9 ;;
        tenth) echo 10 ;; *) echo "" ;;
    esac
}

# -----------------------------------------------------------------------------
# Oracle self-check. word_to_int is the only place this suite holds a value NOT
# read out of the subject file, so it is the only thing that can disagree with
# it. If it ever derived its answer from the parsed count instead of a fixed
# table, the number-word assertion below would pass by construction and this
# suite would be decoration. Pin the table against literals before trusting it.
#
# This block sits ABOVE every read of the subject, deliberately: run it after
# parsing and a table entry rewritten as `$p4_count` still matches whenever the
# real list happens to be that long — which is exactly when nobody would look.
# Up here there is no parsed count in scope for it to launder.
section "the oracle's number table (self-check)"
# EVERY entry, not a sample. A loop over four of the nine left five reachable
# labels unpinned, and laundering one of those turned a genuine 10-passed/1-failed
# drift into a full 11-passed green — verified, not theorized. A self-check that
# covers part of its table states a property it does not have.
for expect in two:2 three:3 four:4 five:5 six:6 seven:7 eight:8 nine:9 ten:10; do
    if [ "$(word_to_int "${expect%%:*}")" != "${expect##*:}" ]; then
        fatal "word_to_int(\"${expect%%:*}\") is not ${expect##*:} — the oracle's number table is wrong or no longer constant."
    fi
done
for expect in second:2 third:3 fourth:4 fifth:5 sixth:6 seventh:7 eighth:8 ninth:9 tenth:10; do
    if [ "$(ordinal_to_int "${expect%%:*}")" != "${expect##*:}" ]; then
        fatal "ordinal_to_int(\"${expect%%:*}\") is not ${expect##*:} — the oracle's ordinal table is wrong or no longer constant."
    fi
done
ok "constant and correct: cardinals two..ten and ordinals second..tenth"

[ -f "$compound_skill" ] || fatal "$compound_skill not found. The skill moved, or this suite is stale."

# Turn "a, b, c, or d" into one name per line. Strips a leading "or ".
# The trailing newline is load-bearing: without it `wc -l` drops the last name
# and every count below is short by one — silently, and in the same direction
# at both sites, so the equality check would still pass.
split_names() {
    printf '%s\n' "$1" \
        | sed 's/, /\n/g' \
        | sed 's/^or //' \
        | sed '/^[[:space:]]*$/d'
}

# -----------------------------------------------------------------------------
section "both enumerations are findable"

q4_line="$(grep -F -- "$q4_anchor" "$compound_skill" | head -1 || true)"
[ -n "$q4_line" ] || fatal "no Q4 mechanism list in $compound_skill (anchor: \"$q4_anchor\"). Q4 was reworded; update this suite with it."
# Everything between the anchor and the question mark that ends Q4's question.
q4_list="${q4_line#*"$q4_anchor"}"
q4_list="${q4_list%%\?*}"
[ -n "$q4_list" ] || fatal "Q4 anchor found but the list after it is empty."
ok "Q4 declares a mechanism list"

p4_line="$(grep -F -- "$phase4_anchor" "$compound_skill" | head -1 || true)"
[ -n "$p4_line" ] || fatal "no Phase 4 mechanism list in $compound_skill (anchor: \"$phase4_anchor\"). The promote-to-mechanism sentence was reworded; update this suite with it."
p4_list="${p4_line#*"$phase4_anchor"}"
p4_list="${p4_list%%. *}"
[ -n "$p4_list" ] || fatal "Phase 4 anchor found but the list after it is empty."
ok "Phase 4 re-enumerates the mechanism list"

# -----------------------------------------------------------------------------
section "the two lists hold the same number of names"

q4_count="$(split_names "$q4_list" | wc -l | tr -d ' ')"
p4_count="$(split_names "$p4_list" | wc -l | tr -d ' ')"

if [ "$q4_count" -lt 2 ]; then
    fatal "parsed only $q4_count name(s) out of Q4 — the separator convention changed; update this suite."
fi

if [ "$q4_count" -eq "$p4_count" ]; then
    ok "both lists enumerate $q4_count names"
else
    bad "the two mechanism lists disagree on how many names there are" \
        "Q4 enumerates $q4_count ($(split_names "$q4_list" | tr '\n' '|')); Phase 4 enumerates $p4_count ($(split_names "$p4_list" | tr '\n' '|'))"
fi

# -----------------------------------------------------------------------------
section "Phase 4's number-words match the list it enumerates"

named_word="$(printf '%s' "$p4_line" | sed -n 's/.*the \([a-z]*\) Q4 names.*/\1/p')"
none_word="$(printf '%s' "$p4_line" | sed -n 's/.*none of the \([a-z]*\) can be built.*/\1/p')"

for pair in "the N Q4 names:$named_word" "none of the N:$none_word"; do
    label="${pair%%:*}"
    word="${pair##*:}"
    if [ -z "$word" ]; then
        bad "could not read the number-word in \"$label\"" \
            "the cross-reference was reworded; either restore a spelled number or update this suite"
        continue
    fi
    n="$(word_to_int "$word")"
    if [ -z "$n" ]; then
        bad "\"$label\" uses an unrecognized number-word: \"$word\"" "extend word_to_int, or fix the prose"
    elif [ "$n" -eq "$p4_count" ]; then
        ok "\"$label\" says $word and the list has $p4_count"
    else
        bad "\"$label\" says $word but the list enumerates $p4_count" \
            "the cross-reference is now false; a name was added or removed at one site only"
    fi
done

# -----------------------------------------------------------------------------
section "the pack-level name is present at both sites"

for pair in "Q4:$q4_list" "Phase 4:$p4_list"; do
    site="${pair%%:*}"
    body="${pair#*:}"
    if printf '%s' "$body" | grep -qF -- "$pack_name_token"; then
        ok "$site's list includes the pack-level name ($pack_name_token)"
    else
        bad "$site's list dropped the pack-level name" \
            "a lesson whose preventing change belongs to the pack has nothing legal to become again — the #266 defect"
    fi
done

# -----------------------------------------------------------------------------
section "the pack-level name's ordinal is constructed, not hand-maintained"

# The count agreement above says HOW MANY names there are and nothing about WHICH
# one is the pack-level member. Six ordinal claims elsewhere ("The fifth name is
# scoped by ownership", "The fifth Q4 name has nothing to stage", plus CLAUDE.md,
# SYSTEM-OVERVIEW.md and its four synced copies) all name a position. Adding a
# sixth mechanism and updating both number-words leaves every one of those stale
# while this suite stays green — verified. Deriving the ordinal from the list is
# what turns those claims from a hand-maintained cross-reference into a
# constructed one, which is the whole point of the file.
pack_index() {
    split_names "$1" | grep -n -F -- "$pack_name_token" | head -1 | cut -d: -f1
}

q4_idx="$(pack_index "$q4_list")"
p4_idx="$(pack_index "$p4_list")"

if [ -z "$q4_idx" ] || [ -z "$p4_idx" ]; then
    bad "the pack-level name has no position in one of the lists" "Q4:'$q4_idx' Phase 4:'$p4_idx'"
elif [ "$q4_idx" = "$p4_idx" ]; then
    ok "the pack-level name is at position $q4_idx in both lists"
else
    bad "the pack-level name sits at different positions in the two lists" \
        "Q4 position $q4_idx, Phase 4 position $p4_idx — the ordinal prose below can only match one"
fi

# The ordinal word used in the guard heading must be that position.
guard_line="$(grep -F -- "$guard_marker" "$compound_skill" | head -1 || true)"
guard_ord="$(printf '%s' "$guard_line" | sed -n 's/.*\*\*The \([a-z]*\) name is scoped.*/\1/p')"
guard_n="$(ordinal_to_int "$guard_ord")"
if [ -z "$guard_n" ]; then
    bad "could not read the ordinal in the ownership guard heading" "got: \"$guard_ord\""
elif [ "$guard_n" = "$q4_idx" ]; then
    ok "the guard heading says \"$guard_ord\" and the pack-level name is at position $q4_idx"
else
    bad "the guard heading says \"$guard_ord\" but the pack-level name is at position $q4_idx" \
        "the guard now scopes whichever name landed there instead of the pack-level one"
fi

# Phase 5's staging exemption carries the same ordinal and the same failure mode:
# attached to the wrong name it exempts a mechanism that DOES need staging.
stage_line="$(grep -F -- 'Q4 name has nothing to stage' "$compound_skill" | head -1 || true)"
if [ -z "$stage_line" ]; then
    bad "Phase 5's staging exemption for the pack-level name is missing" \
        "without it, the fifth name has no stated equivalent of staging"
else
    stage_ord="$(printf '%s' "$stage_line" | sed -n 's/.*The \([a-z]*\) Q4 name has nothing to stage.*/\1/p')"
    stage_n="$(ordinal_to_int "$stage_ord")"
    if [ -z "$stage_n" ]; then
        bad "could not read the ordinal in Phase 5's staging exemption" "got: \"$stage_ord\""
    elif [ "$stage_n" = "$q4_idx" ]; then
        ok "Phase 5's staging exemption says \"$stage_ord\" and matches position $q4_idx"
    else
        bad "Phase 5's staging exemption says \"$stage_ord\" but the pack-level name is at position $q4_idx" \
            "it would exempt a mechanism that does need staging — an inversion of Phase 5's rule"
    fi
fi

# -----------------------------------------------------------------------------
section "filing cannot cross a repo boundary it was not permitted to cross"

# WHY THIS IS PINNED. Four of the five mechanisms stay inside the repo that
# learned the lesson. The fifth moves words OUT of it, into a public repo. A
# local `gh` account guard does not stop that and is not meant to: it routes
# IDENTITY, so a filing from a work repo resolves correctly to the personal
# account and therefore SUCCEEDS. Verified against this machine's guard from
# three work checkouts — all three resolved to the personal account rather
# than refusing. The guard doing its job is what makes the write land.
#
# So the confidentiality boundary has to live here, in the skill, and it has to
# be an ALLOWLIST. The tempting inversion — block the owners known to be work —
# admits a client org onboarded last week, which is precisely the repo whose
# confidentiality posture is least established. Fail closed on unknown.

if grep -qF -- 'Filing-owner gate (DO-CONFIRM' "$compound_skill"; then
    ok "the filing-owner gate is present and marked DO-CONFIRM"
else
    bad "no filing-owner gate before the outbound filing step" \
        "the fifth mechanism would file from any repo it happens to run in, including a client's"
fi

# The gate must resolve the owner from the repo, not trust an assertion about it.
if grep -qF -- 'git remote get-url origin' "$compound_skill"; then
    ok "the gate derives the owner from origin"
else
    bad "the gate names no command that resolves the current repo's owner" \
        "an unresolved gate is a gate an agent satisfies by assuming it passed"
fi

# The allowlist must be a fenced list, and it must fail closed. Pin the
# fail-closed sentence rather than the list's contents — owners are expected to
# be added over time, and pinning them would make a legitimate edit turn the
# suite red.
if grep -qF -- 'Fail closed on unknown.' "$compound_skill"; then
    ok "the gate states the fail-closed direction explicitly"
else
    bad "the gate does not say what happens for an unrecognized owner" \
        "silence there reads as permission, which is the wrong default for an outbound write"
fi

if grep -qF -- 'the fifth name is unavailable' "$compound_skill"; then
    ok "a non-allowlisted owner has a stated fallback"
else
    bad "no stated fallback when the owner is not permitted" \
        "without one, a blocked filing has no defined outcome and the lesson is silently dropped"
fi

# The allowlist must be MACHINE-EXTRACTABLE, which is not the same as present.
# The gate subsection holds several fenced blocks, so "the list is the code
# block below" is ambiguous — an extractor that guesses by position pulls prose
# instead, and then every owner fails the check including the permitted ones.
# That is a fail-OPEN direction for the human reading the result ("the gate
# seems broken, skip it"), so the markers are pinned rather than assumed.
# This suite mis-parsed it exactly that way on first run, which is why it is here.
# Both markers are asserted independently. `sed -n '/start/,/end/p'` runs to
# EOF when the END pattern is missing, so the extraction stays NON-EMPTY and a
# presence-only check passes while silently returning the rest of the file.
# That mutation survived the first version of this assertion — the same
# partial-coverage shape recorded in
# docs/solutions/testing-patterns/partial-oracle-selfcheck-2026-08-22.md,
# reproduced inside the check written after it. Hence: both ends, and a
# sanity bound on the size of what came back.
allow_start="$(grep -c 'filing-allowlist:start' "$compound_skill" || true)"
allow_end="$(grep -c 'filing-allowlist:end' "$compound_skill" || true)"
allow_block="$(sed -n '/filing-allowlist:start/,/filing-allowlist:end/p' "$compound_skill" \
    | sed '/```/d;/filing-allowlist/d' | awk 'NF' || true)"
allow_lines="$(printf '%s' "$allow_block" | grep -c . || true)"

if [ "$allow_start" != "1" ] || [ "$allow_end" != "1" ]; then
    bad "the allowlist markers are not a matched pair (start=$allow_start end=$allow_end)" \
        "an unterminated range extracts to EOF and still looks non-empty — the failure this check exists to catch"
elif [ -z "$allow_block" ]; then
    bad "the filing allowlist is empty between its markers" \
        "expected a fenced list of permitted owners"
elif [ "$allow_lines" -gt 20 ]; then
    bad "the allowlist extraction returned $allow_lines lines — that is prose, not a list of owners" \
        "the markers are probably mispositioned; a gate that extracts prose fails every owner including the permitted ones"
else
    ok "the allowlist extracts cleanly between matched markers ($allow_lines owner(s))"
fi


# -----------------------------------------------------------------------------
section "what crosses is anonymized"

# The gate decides WHETHER a filing may happen; this decides WHAT travels. Both
# are needed: a permitted repo can still carry a client's identifiers, and the
# issue body is a narrative about the work rather than a copy of its code.
if grep -qF -- 'Write the body anonymized' "$compound_skill"; then
    ok "the body contract requires anonymization"
else
    bad "the filing procedure does not require an anonymized body" \
        "the body describes what was being built and why the pipeline missed it — that is the leak surface, not the code"
fi

if grep -qF -- 'Do not name' "$compound_skill"; then
    ok "the contract enumerates what must not be named"
else
    bad "the anonymization rule names no specifics" \
        "\"be careful\" is not a contract; the list of what to strip is what makes it checkable by a reader"
fi

# The evidence-pointer rule is the one most likely to be dropped as pedantry,
# and it is the one that leaks by construction: a docs/solutions/ path is a
# filename from a repo the reader cannot open.
if grep -qF -- "Do not cite this entry's path as the evidence" "$compound_skill"; then
    ok "the contract forbids citing the local entry path as evidence"
else
    bad "the contract still allows citing this entry's path in the filed issue" \
        "that path proves nothing to a reader without access and identifies the work to everyone else"
fi

# -----------------------------------------------------------------------------
section "Phase 5 verifies the filing instead of asserting it"

# The one claim this whole change rests on — "the pack-level issue was filed" —
# is the one the suite cannot assert directly: the citation lives in a DOWNSTREAM
# repo's docs/solutions/ entry, which this repo's CI has no way to read. So the
# check runs where the claim is made (a DO-CONFIRM in Phase 5) and what is pinned
# here is that the check is still there. That is a weaker guarantee than the
# assertions above, and naming the weakness is the point: an unpinned DO-CONFIRM
# is one deletion away from the prose-only outcome the rule forbids.
filing_check_cmd='gh issue view -R chrislacey89/skills'
if grep -qF -- "$filing_check_cmd" "$compound_skill"; then
    ok "Phase 5 carries the filing-verification command"
else
    bad "Phase 5 has no command verifying the cited pack-level issue exists" \
        "\"the issue was filed\" is then a sentence, which is what this mechanism exists to stop being"
fi

if grep -qF -- 'Pack-level filing check (DO-CONFIRM' "$compound_skill"; then
    ok "the filing check is marked DO-CONFIRM"
else
    bad "the filing check is not marked DO-CONFIRM" \
        "the repo's other verify-before-commit rules carry the marker; an unmarked one reads as advisory"
fi

# -----------------------------------------------------------------------------
section "the ownership guard is declared once and the report can print it"

guard_hits="$(grep -c -F -- "$guard_marker" "$compound_skill" || true)"
case "$guard_hits" in
    1) ok "the ownership guard is declared exactly once" ;;
    0) bad "no ownership guard for the pack-level name" \
           "without it the fifth name is the general compliance exit #257 deliberately left closed" ;;
    *) bad "the ownership guard is declared $guard_hits times" "it is a rule; declare it once and refer to it" ;;
esac

report_lines="$(grep -c '^Mechanism: ' "$compound_skill" || true)"
if [ "$report_lines" -lt 2 ]; then
    bad "expected Phase 6's two report blocks to each carry a 'Mechanism:' line, found $report_lines" \
        "the report shape changed; update this suite with it"
else
    ok "Phase 6 carries $report_lines Mechanism report lines"
    missing="$(grep '^Mechanism: ' "$compound_skill" | grep -v -F -- "$pack_name_token" || true)"
    if [ -z "$missing" ]; then
        ok "every Mechanism report line can represent a pack-level filing"
    else
        bad "a Phase 6 report line cannot represent a pack-level filing" \
            "a mechanism the report cannot print is the unenforced-claim shape Phase 5/6 exist to close: $missing"
    fi
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
