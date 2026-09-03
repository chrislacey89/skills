#!/usr/bin/env bash
# test-compound-clustering-single-source.sh — single-source contract test for
# /compound Phase 4's defect clustering rule.
#
# THE DRIFT CLASS. /compound Phase 4 owns the rule deciding whether a recurring
# lesson becomes prose or a mechanism. SYSTEM-OVERVIEW.md summarizes every
# skill, and scripts/skill-references.manifest bundles it into four more
# `references/` copies. A restatement of the rule in that summary is a rule
# maintained by hand in six places with nothing constructing the agreement —
# docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md,
# whose Rule Scope invert clause ("the claim is about the repo's own code →
# write the test") is what puts this suite in scope, not its Prevention text.
#
# THE INCIDENTS, all three of which this suite is mutation-tested against:
#   1. PR #259 changed the rule in compound/SKILL.md and left
#      SYSTEM-OVERVIEW.md:207 restating the old threshold. Review caught it.
#   2. The corrective sweep then missed a copy in vite-project/src/data/
#      workflow-data.js. A second review pass caught that.
#   3. The FIRST DRAFT OF THIS FILE was red on a clean tree the moment it was
#      staged: its retired[] array holds the very phrases it forbids, and
#      `git ls-files` sees a tracked file but not an untracked one — so every
#      mutation run before `git add` passed and the suite had never once been
#      run after. A third review pass caught that. It is the seventh instance
#      of the family, inside the mechanism written to stop the sixth.
#
# Incident 3 is why the exclusion below is load-bearing rather than tidy, and
# why `check_self_visible` asserts the file list is real before trusting an
# empty grep. Run this suite AFTER staging, never only before.
#
# WHAT IT PINS, all extracted from the real files rather than restated here:
#   1. The retired phrasings appear in no tracked file (this suite and
#      CHANGELOG.md excepted — both quote them deliberately).
#   2. The rule is DECLARED in exactly one place. Declaration is the bold
#      heading `**Defect clustering check`; a prose mention in any case is a
#      REFERENCE and is allowed anywhere, because a reader cannot rebuild the
#      rule from a name. That is by-construction-…'s referring/restating line.
#   3. Every SYSTEM-OVERVIEW copy names `/compound` Phase 4 as the owner and
#      carries no threshold of its own.
#
# Deliberately NOT pinned: the rule's wording. Pinning prose would force a
# false uniformity and the suite would be deleted the first time someone
# legitimately reworded it. Only single-sourcing is pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

self="scripts/test-compound-clustering-single-source.sh"
compound_skill="compound/SKILL.md"

# The bold heading that constitutes a DECLARATION of the rule.
declaration_marker='**Defect clustering check'
# The anchor opening /compound's description in every SYSTEM-OVERVIEW copy.
overview_anchor='Captures what was learned into'
# What a restated threshold looks like: a number attached to a countable, or a
# "when/at N". Deliberately wording-agnostic — a restatement uses new words.
threshold_re='[0-9]+\+?[[:space:]]+(or more[[:space:]]+)?(solutions|entries|docs|files|records|lessons)|(when|at)[[:space:]]+[0-9]+\+?[[:space:]]'

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }

# Tracked files, minus the two that quote retired text on purpose. This suite
# excludes ITSELF (incident 3) — which means a genuine restatement pasted into
# this file would not be caught here. That is the accepted cost of letting the
# suite name what it forbids.
scan_files() {
    git ls-files -- ':!CHANGELOG.md' ":!$self"
}

# Return the blank-line-delimited PARAGRAPH containing $2, not the physical line
# that happens to hold it.
#
# WHY THIS IS NOT `grep`. The two assertions below are claims about /compound's
# whole description — "it names Phase 4 as the owner" and "it states no threshold
# of its own". `grep -F "$anchor"` returns one line, and this reads as correct
# only because SYSTEM-OVERVIEW.md:207 currently packs all 1,051 characters of
# that description onto one. The anchor sits in its FIRST sentence. Break the
# paragraph anywhere after that sentence and the extract collapses to ~66
# characters while the assertions keep reporting on the whole description.
#
# REPRODUCED, and worse than "one check goes blind". Splitting the paragraph
# after sentence 1, keeping `/compound` Phase 4 inside that first sentence, and
# planting `when 3 solutions share a root cause` in a later sentence produced
# 18 passed, 0 failed — the suite fully green with incident #259 sitting in the
# file it was written to guard. Nothing in the output said the extractor had
# stopped looking. That is the shape test-widened-domain-tell.sh names in its
# own error text: an extractor that finds nothing passes everything it was
# meant to check.
#
# awk's paragraph mode (RS="") is half the fix: records are separated by blank
# lines, so the record IS the markdown paragraph however it is wrapped. `index`
# is a literal substring test, preserving the `grep -F` semantics the anchor was
# written for — an anchor carrying a regex metacharacter must not start matching
# as a pattern. `exit` after the first hit keeps the old `head -1` behavior.
#
# `gsub(/\n/, " ")` is the OTHER half, and it is not cosmetic. Widening the
# window does not help a matcher that still reads one line at a time: `grep -qE`
# is line-wise, and threshold_re spans a gap (`[0-9]+[[:space:]]+solutions`,
# `(when|at)[[:space:]]+[0-9]+`). Also reproduced — wrapping the paragraph so the
# match straddles, as `…check when 3\nsolutions share a root cause`, returned
# 18 passed, 0 failed against the paragraph-aware extractor with no unwrap.
# Neither alternative fit on one line, so neither matched, and the suite was
# green over a live threshold a second time. Unwrapping restores the paragraph
# as the single LOGICAL line every downstream matcher was written against.
#
# THE UNWRAP MUST HAPPEN BEFORE THE MATCH, and the first draft of this function
# got that backwards: it ran `index($0, anchor)` and only unwrapped inside the
# action, so the anchor itself was still matched line-wise. One line break at the
# em-dash inside an anchor — no rewording whatsoever — then produced
# `FATAL: no Q4 mechanism list … Q4 was reworded; update this suite with it`, a
# diagnostic naming a cause that had not occurred. That is precisely the false
# red this whole change exists to prevent, reintroduced by the change itself and
# caught in review rather than by any check. Build the unwrapped record first,
# match against it, print it. scripts/test-review-dimension-partition.sh already
# wrote it this way (`detect_title_rosters`); the idiom was prior art in this
# repo and the first draft did not look for it.
paragraph_at() {  # $1 = file, $2 = literal anchor — returns the paragraph as one logical line
    awk -v anchor="$2" '
        BEGIN { RS = "" }
        { rec = $0; gsub(/\n/, " ", rec) }
        index(rec, anchor) { print rec; exit }
    ' "$1"
}

if [ ! -f "$compound_skill" ]; then
    printf 'FATAL: %s not found. The skill moved, or this suite is stale.\n' "$compound_skill" >&2
    exit 2
fi

# -----------------------------------------------------------------------------
section "the file list is real (guards every empty-grep pass below)"

file_count="$(scan_files | wc -l | tr -d ' ')"
if [ "$file_count" -gt 20 ]; then
    ok "scan covers $file_count tracked files"
else
    bad "scan_files returned only $file_count paths" \
        "an empty or truncated list makes every 'absent' assertion below pass vacuously"
    printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi

# -----------------------------------------------------------------------------
section "the retired phrasings are gone from every scanned file"

# Literal HISTORY — fixed text that will never legitimately reappear. These
# cannot catch a NEW wording; check 3's threshold regex is what covers that.
retired=(
    '3+ solutions share the same root cause'
    '3+ entries in the same category'
    'systemic issue worth noting in the solution'
    'systemic patterns when 3+'
    'Flags systemic defect patterns'
)

for phrase in "${retired[@]}"; do
    hits="$(scan_files | xargs grep -l -F -- "$phrase" 2>/dev/null || true)"
    if [ -z "$hits" ]; then
        ok "retired phrasing absent: \"$phrase\""
    else
        bad "retired phrasing still present: \"$phrase\"" "in: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done

# -----------------------------------------------------------------------------
section "the rule is declared in exactly one file"

if ! grep -qF -- "$declaration_marker" "$compound_skill"; then
    printf 'FATAL: no "%s" heading in %s.\n' "$declaration_marker" "$compound_skill" >&2
    printf '       The rule moved or was renamed; update this suite with it.\n' >&2
    exit 2
fi
ok "compound/SKILL.md declares the rule"

declarers="$(scan_files | xargs grep -l -F -- "$declaration_marker" 2>/dev/null || true)"
extra_declarers="$(printf '%s\n' "$declarers" | grep -v -x -F "$compound_skill" | grep -v '^$' || true)"
if [ -z "$extra_declarers" ]; then
    ok "no other file declares it (prose references by name remain allowed)"
else
    bad "the rule is declared outside compound/SKILL.md" \
        "in: $(printf '%s' "$extra_declarers" | tr '\n' ' ')"
fi

# -----------------------------------------------------------------------------
section "every SYSTEM-OVERVIEW copy refers to the owner and states no threshold"

overviews="$(scan_files | grep 'SYSTEM-OVERVIEW\.md$' || true)"
if [ -z "$overviews" ]; then
    bad "no SYSTEM-OVERVIEW.md found in the scan" "expected the canonical plus four bundled copies"
else
    while IFS= read -r ov; do
        [ -n "$ov" ] || continue
        para="$(paragraph_at "$ov" "$overview_anchor")"
        if [ -z "$para" ]; then
            # Non-vacuous: a missing anchor is a failure, not a silent pass.
            bad "$ov has no /compound description to check" \
                "anchor \"$overview_anchor\" not found — the summary was restructured; update this suite"
            continue
        fi
        # MULTI-SENTENCE FLOOR — the canonical statement of this guard. The
        # sibling in test-q4-mechanism-names.sh points here rather than
        # restating it; the two copies had already drifted in wording by the
        # time review read them, which is the restated-claim defect this repo
        # keeps a doc about (docs/restated-claims.md).
        #
        # /compound's description is multi-sentence and both assertions below
        # claim to scan all of it, so a one-sentence extract cannot support them
        # whatever produced it.
        #
        # WHAT IT CATCHES: paragraph_at regressing to a line read against a
        # wrapped source. Verified by reverting the extractor under a wrapped
        # tree and watching this fire.
        #
        # WHAT IT DOES NOT CATCH, stated rather than implied: a wrap that leaves
        # two sentences on the anchor's own line. The tempting stronger guard —
        # compare the extract's length against the line holding the anchor — is
        # a TAUTOLOGY under exactly the reversion it appears to guard, since a
        # line read and that comparison read the same line. It was written,
        # tested, found to pass silently under a live reversion, and removed
        # rather than shipped. A floor that states a property it does not have
        # is the defect this whole change exists to close.
        #
        # COUNT OCCURRENCES, NOT LINES. `grep -c` counts matching LINES, and
        # paragraph_at returns exactly one, so `grep -c` here can only ever
        # return 0 or 1 — a presence test wearing a count's name. Review caught
        # that; `grep -o | wc -l` is the count the failure text claims.
        # `|| true` is load-bearing: grep exits 1 on no match, and relying on
        # `if`-condition context to suppress `set -e` would make this floor's
        # survival an accident of where it is written rather than a property of
        # how.
        para_sentences="$(printf '%s' "$para" | grep -o -- '\. ' | wc -l | tr -d ' ' || true)"
        if [ "${para_sentences:-0}" -lt 1 ]; then
            bad "$ov's /compound paragraph extracted as a single sentence" \
                "the assertions below claim to scan the whole description; a one-sentence extract makes both of them vacuous"
            continue
        fi
        # shellcheck disable=SC2016  # literal backticks, no expansion intended
        if grep -qF -- '`/compound` Phase 4' <<<"$para"; then
            ok "$ov names /compound Phase 4 as the owner"
        else
            bad "$ov describes /compound without naming Phase 4 as the rule's owner" \
                "reference by name forces a reader to the source; partial enumeration does not"
        fi
        if grep -qE -- "$threshold_re" <<<"$para"; then
            bad "$ov carries a threshold of its own" \
                "matched: $(printf '%s' "$para" | grep -oE -- "$threshold_re" | head -1)"
        else
            ok "$ov states no threshold"
        fi
    done <<< "$overviews"
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
