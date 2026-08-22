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
#   5. Its ownership guard is declared exactly once, and Phase 6's two report
#      blocks can represent it. A mechanism the report cannot print is the
#      "Phase 5 was staging the prose and not the mechanism" defect (#257).
#
# Deliberately NOT pinned: the wording of the names. Q4 says "a stronger test"
# where Phase 4 says "a test"; forcing those to match would be a false
# uniformity, and a suite that forbids legitimate rewording gets deleted. Only
# the count, the pack-level member, and the report states are pinned.
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

word_to_int() {
    case "$1" in
        two) echo 2 ;; three) echo 3 ;; four) echo 4 ;; five) echo 5 ;;
        six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;; nine) echo 9 ;;
        ten) echo 10 ;; *) echo "" ;;
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
for expect in two:2 four:4 five:5 ten:10; do
    if [ "$(word_to_int "${expect%%:*}")" != "${expect##*:}" ]; then
        fatal "word_to_int(\"${expect%%:*}\") is not ${expect##*:} — the oracle's number table is wrong or no longer constant."
    fi
done
ok "constant and correct: two/four/five/ten"

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
