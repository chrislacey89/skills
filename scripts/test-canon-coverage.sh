#!/usr/bin/env bash
# test-canon-coverage.sh — the landing page's canon and the skills' `sources:`
# frontmatter must name the same works, and every attribution the page renders
# must be one the named skill actually makes.
#
# THE DRIFT CLASS. The canon section is a router pointing at provenance: it
# shelves a set of works and tells the reader "each SKILL.md names its sources
# in frontmatter." For as long as that set was hand-written, nothing related the
# two, and they drifted in both directions in silence — a spine could be added
# with nothing behind it, and a `sources:` entry could be added and never reach
# the page. Neither failure emits a signal. The page builds, the spine renders,
# the book opens.
#
# THE TWO INCIDENTS.
#   #272 (2026-08-23) — the shelf carried *Total TypeScript — Matt Pocock* and
#     pointed it at `/ts-audit`, whose frontmatter held only `name` and
#     `description`. Every other spine traced to a real entry; that one traced to
#     nothing, and had done so for as long as the page existed.
#   #273 (2026-08-24) — the same shelf held 8 of the 45 works the skills
#     actually cite. 34 declared works never reached the page, and four works
#     were declared under two author spellings each, so even a naive automated
#     extraction would have double-counted them.
#
# THE FIX FOR #273 CHANGED WHAT THIS SUITE HAS TO WATCH. The canon is now
# derived: `scripts/generate-canon.sh` reads the frontmatter and writes
# `site/src/lib/canon.generated.ts`, and `Shelf.astro` renders that. So the
# hand-written array this suite used to parse is gone, and with it the checks
# that guarded it. That is not a loss of coverage — #272's property (a shelved
# work must be declared by the skill the page attributes it to) is now checked on
# EVERY citation edge rather than on the one skill a hand-written entry named,
# which is strictly stronger. What replaces the old checks is the set of
# properties a derivation can still get wrong.
#
# WHAT IT PINS, every side extracted from the real files rather than restated:
#   1. Every quoted entry under a `sources:` key in every skill's frontmatter,
#      bounded to the frontmatter and terminated at the first non-indented line.
#   2. No title is declared under two different author spellings anywhere in the
#      repo.
#   3. The committed canon module is byte-for-byte what the generator produces
#      from the frontmatter as it stands right now.
#   4. The canon and the frontmatter name the same set of works, in both
#      directions — no declared work missing, no shelved work undeclared.
#   5. Every entry is typed `book` or `paper`, and `paper` exactly when its own
#      author field is spelled as a paper citation.
#   6. Every citation edge resolves to a skill that declares that work at that
#      tier, AND every declaration in the frontmatter appears as an edge.
#   7. `data.ts` names a declared work only as a `lessons` key, and every
#      `lessons` key is a work some skill declares.
#   8. The BUILT page renders exactly the canon — no work missing, no spine with
#      nothing behind it.
#   9. Every `mappings` row's cited book is declared by every stage the row names.
#
# WHY 6 IS CHECKED IN BOTH DIRECTIONS. The forward edge catches an invented
# citation. The reverse catches a dropped one — and a dropped citation is the
# quiet failure, because the work stays shelved by its other citers and nothing
# looks broken. Only the citation count is understated, and #274 renders that
# count as spine height.
#
# WHY 8 IS THE ONE THAT ACTUALLY HOLDS THE PROPERTY. Every other check reads
# source files and reasons about what they would produce. Check 8 reads what was
# produced. The difference is the gap between "the component imports the canon"
# and "the reader can see all 45 works", and #273 is a bug report about the
# second. It needs `site/dist/index.html`, so it SKIPS locally unless the site
# has been built, and CI's `canon-render` job builds before invoking this suite
# so it always runs there. The narrowing tripwire beside it (`grep` for
# `.slice(`/`.filter(`) keys on a language construct, which
# `mechanism-generality-lags-the-pattern-2026-08-23.md` is explicit is the weaker
# kind of detector; it is a fast local hint, not the mechanism.
#
# ONE WORK, ONE SPELLING (check 2), AND WHY IT IS A FAILURE RATHER THAN A
# TOLERANCE. Grouping is by the whole declared string, so a second spelling of
# one author splits one work into two entries — the canon over-counts and each
# half's citation count is wrong. #273 normalized the four live pairs at the
# source and this check keeps them normalized. The alternative was an alias table
# beside the extractor, rejected because a table is itself a hand-maintained
# canon list, which is the defect under repair. The `mappings` matcher one
# section down stays deliberately looser — it compares bare titles, because a
# `mappings` row cites no author at all.
#
# WHY THE POPULATIONS ARE DERIVED AND NOT FLOORED. A floor guards against total
# blindness; it cannot notice the loss of one item, which is the granularity this
# drift arrives at. Against the old shelf, `MIN_CANON_WORKS=5` let three spines
# go unparsed, and a spine written `full: '…'` — single quotes, which no
# formatter in this repo forbids — passed as a shrunken shelf, fully green, while
# the page rendered nine. So `canon_slots` reads the array's element count by
# brace depth alone, knowing no field name, and is required to equal what
# `canon_rows` parses. That is `partial-oracle-selfcheck-2026-08-22.md`
# Prevention #2 ("derive the coverage instead of restating it") applied to the
# population where restating it actually bit, and it closes the recurrence of
# `mechanism-generality-lags-the-pattern-2026-08-23.md`: a detector keying on a
# language construct rather than on the property. The floors that remain guard
# only the blunt case where a reading returns nothing at all.
#
# WHAT IT DELIBERATELY DOES NOT PIN. `lessons` is hand-written prose and nothing
# here checks its content or its coverage. That is load-bearing rather than an
# oversight: the lessons are an OPTIONAL enrichment layer keyed by canonical
# work, so a work with no lesson opens to its derived spread instead of being
# kept off the page. A coverage check over the lessons would make curation
# mandatory and put the maintenance burden back exactly where #273 removed it
# from. What IS pinned about them is check 7 — a lesson keyed to a work nobody
# declares is dead prose, which is #272's shape one layer in.
#
# The self-tests at the bottom run every extractor and every detector against
# synthetic fixtures in both directions, because a detector that has stopped
# detecting reports the same full green as a clean repo.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data_ts="$repo_root/site/src/lib/data.ts"
canon_ts="$repo_root/site/src/lib/canon.generated.ts"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ "$#" -gt 1 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}
fatal() { printf '\nFATAL: %s\n' "$1" >&2; exit 2; }

# --- Everything below is derived from a real file; nothing is restated --------

# mapping_rows <data.ts> — "<source title>\t<skill list>" per row of the
# `mappings` array, which Practice.astro renders under "Each stage
# operationalizes a named discipline from the literature". Same provenance claim
# as the shelf, five lines down in the same file, and unpinned until review
# pointed a row at a book nothing declares and got a full green.
mapping_rows() {
    awk '
        /^export const mappings/ { inmap = 1; next }
        inmap && /^\];/          { inmap = 0; next }
        inmap && /source:/ && /skill:/ {
            s = ""; k = ""
            if (match($0, /source: "[^"]*"/)) s = substr($0, RSTART + 9, RLENGTH - 10)
            if (match($0, /skill: "[^"]*"/))  k = substr($0, RSTART + 8, RLENGTH - 9)
            if (s != "" && k != "") print s "\t" k
        }
    ' "$1"
}

# declared_works <skill.md>... — every quoted source string under a `sources:`
# key in each named skill's frontmatter.
#
# Frontmatter only, and terminated at the first non-indented line. Both bounds
# are load-bearing. A SKILL.md body routinely quotes book titles and shows
# example `sources:` blocks, and harvesting those would let the page's claim be
# backed by a skill merely *talking about* a book. Dropping the terminator is
# worse: every quoted string in the rest of the frontmatter becomes a declared
# work, so a `description:` could back a shelf claim. Both bounds have a fixture
# below — the terminator's was missing on the first draft, and deleting the rule
# left this suite at 11 passed / 0 failed.
declared_works() {
    local skill
    for skill in "$@"; do
        [ -f "$skill" ] || continue
        awk '
            /^---[[:space:]]*$/       { fm++; next }
            fm != 1                   { next }
            /^sources:[[:space:]]*$/  { ins = 1; next }
            ins && /^[^[:space:]]/    { ins = 0 }
            ins && match($0, /"[^"]+"/) {
                print substr($0, RSTART + 1, RLENGTH - 2)
            }
        ' "$skill"
    done
}

# alias_collisions <skill.md>... — every title declared under more than one
# author spelling, as "<title>\t<variant> | <variant>". Empty output is the
# passing state.
#
# WHY THIS IS A DEFECT AND NOT A STYLE NIT. Any derivation over the frontmatter
# groups by work, and the only key available is the string. Two spellings of one
# author split one work into two entries — the canon over-counts, the citation
# count under-counts on both halves, and nothing renders wrong enough to notice.
# #273 found four live pairs: *Thinking in Systems* (8 skills vs 1), *The Design
# of Everyday Things* (3 vs 2), *The Pragmatic Programmer* (1 vs 1) and
# *Continuous Delivery* (2 vs 1), with `/closeout` alone carrying three of the
# four minority spellings.
#
# SPLIT ON THE FIRST SEPARATOR, VIA match() AND NOT length(). A title may
# legitimately contain an em dash; an author spelling is whatever follows the
# first " — ". RSTART/RLENGTH are self-consistent inside one awk regardless of
# whether that awk counts bytes or characters, which arithmetic over length()
# of a multi-byte separator is not.
alias_collisions() {
    declared_works "$@" | sort -u | awk '
        match($0, / — /) {
            title  = substr($0, 1, RSTART - 1)
            author = substr($0, RSTART + RLENGTH)
            if (title in seen) { seen[title] = seen[title] " | " author }
            else               { seen[title] = author; order[++n] = title }
            count[title]++
        }
        END {
            for (i = 1; i <= n; i++)
                if (count[order[i]] > 1) print order[i] "\t" seen[order[i]]
        }
    '
}

# canon_rows <canon.generated.ts> — one "<full>\t<title>\t<author>\t<type>" per
# entry of the generated canon, delimited by brace depth so a reflow cannot
# shrink the population the way it once shrank the shelf's.
canon_rows() {
    awk '
        /^export const canon/ { incanon = 1; next }
        incanon && /^\];/     { incanon = 0; next }
        incanon {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") { depth++; if (depth == 1) rec = ""; continue }
                if (c == "}") {
                    depth--
                    if (depth == 0) {
                        f = ""; t = ""; a = ""; y = ""
                        if (match(rec, /full: "[^"]*"/))   f = substr(rec, RSTART + 7,  RLENGTH - 8)
                        if (match(rec, /title: "[^"]*"/))  t = substr(rec, RSTART + 8,  RLENGTH - 9)
                        if (match(rec, /author: "[^"]*"/)) a = substr(rec, RSTART + 9,  RLENGTH - 10)
                        if (match(rec, /type: "[^"]*"/))   y = substr(rec, RSTART + 7,  RLENGTH - 8)
                        if (f != "" && y != "") print f "\t" t "\t" a "\t" y
                        rec = ""
                    }
                    continue
                }
                if (depth >= 1) rec = rec c
            }
            if (depth >= 1) rec = rec " "
        }
    ' "$1"
}

# canon_slots <canon.generated.ts> — how many TOP-LEVEL records the array holds,
# counted by brace depth and knowing no field name. Nested citation objects sit
# at depth 2 and are not counted, which is what makes this reading capable of
# disagreeing with canon_rows above.
canon_slots() {
    awk '
        /^export const canon/ { incanon = 1; next }
        incanon && /^\];/     { incanon = 0; next }
        incanon {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") { if (depth == 0) n++; depth++ }
                else if (c == "}") depth--
            }
        }
        END { print n + 0 }
    ' "$1"
}

# canon_citation_rows <canon.generated.ts> — "<full>\t<skill>\t<tier>" per
# declared citation.
#
# LINE-BASED, AND THAT IS SAFE HERE ONLY BECAUSE OF THE FRESHNESS CHECK. Keying
# on a language construct rather than on the property is the recurrence
# `mechanism-generality-lags-the-pattern-2026-08-23.md` warns about, and it is
# why the two readings above are record-based. This one is exempt for a reason
# that has to hold: the file is generated, and the section below diffs it
# byte-for-byte against a fresh run of the generator. A reflow that would break
# this parser cannot reach the tree without turning that check red first. If the
# freshness check is ever weakened, this parser has to be rewritten with it.
canon_citation_rows() {
    awk '
        /^export const canon/ { incanon = 1; next }
        incanon && /^\];/     { incanon = 0; next }
        !incanon              { next }
        match($0, /full: "[^"]*"/) { cur = substr($0, RSTART + 7, RLENGTH - 8); next }
        cur != "" && match($0, /skill: "[^"]*"/) {
            s = substr($0, RSTART + 8, RLENGTH - 9)
            if (match($0, /tier: "[^"]*"/)) {
                print cur "\t" s "\t" substr($0, RSTART + 7, RLENGTH - 8)
            }
        }
    ' "$1"
}

# mistyped_entries <canon.generated.ts> — every entry whose `type` disagrees
# with what its own author field says, as "<full>\t<why>". Empty output passes.
#
# THE PROPERTY, NOT THE RULE. The classification rule lives in the generator;
# re-implementing it here would give two copies of one opinion and no oracle.
# What this asserts is the property the rule exists to produce: `paper` iff the
# author is spelled as a paper citation — `et al.`, or a trailing parenthesized
# four-digit year — and nothing else is.
mistyped_entries() {
    local full author type tell
    while IFS="$(printf '\t')" read -r full _title author type; do
        [ -n "$full" ] || continue
        tell=0
        case "$author" in *"et al."*) tell=1 ;; esac
        if printf '%s' "$author" | grep -Eq '\([^)]*[0-9]{4}\)$'; then tell=1; fi
        case "$type" in
            book)
                [ "$tell" -eq 0 ] || printf '%s\tit is typed book, but its author "%s" carries "et al." or a trailing year in parentheses\n' "$full" "$author"
                ;;
            paper)
                [ "$tell" -eq 1 ] || printf '%s\tit is typed paper, but its author "%s" has neither "et al." nor a trailing year in parentheses, so nothing in the frontmatter says it is a paper\n' "$full" "$author"
                ;;
            *)
                printf '%s\tit carries type "%s"; the only types the page can render are book and paper\n' "$full" "$type"
                ;;
        esac
    done <<EOF
$(canon_rows "$1")
EOF
}

# unresolved_citations <canon.generated.ts> <root> — every citation edge that
# does not resolve to a skill declaring that exact work at that exact tier.
unresolved_citations() {
    local canon="$1" root="$2" full skill tier
    while IFS="$(printf '\t')" read -r full skill tier; do
        [ -n "$full" ] || continue
        if [ ! -f "$root/$skill/SKILL.md" ]; then
            printf '%s\tthe canon says it is cited by /%s, which is not a skill in this repo\n' "$full" "$skill"
            continue
        fi
        declares_work_at_tier "$root/$skill/SKILL.md" "$full" "$tier" \
            || printf '%s\tthe canon says /%s cites it as %s, and that file'"'"'s frontmatter does not\n' "$full" "$skill" "$tier"
    done <<EOF
$(canon_citation_rows "$canon")
EOF
}

# declared_edges <root> — "<full>\t<skill>\t<tier>" for every declaration in the
# frontmatter, which is the citation set read from the other side.
declared_edges() {
    local skill_md name
    for skill_md in "$1"/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        name="$(basename "$(dirname "$skill_md")")"
        awk -v skill="$name" '
            /^---[[:space:]]*$/       { fm++; next }
            fm != 1                   { next }
            /^sources:[[:space:]]*$/  { ins = 1; cur = "primary"; next }
            ins && /^[^[:space:]]/    { ins = 0 }
            !ins                      { next }
            /^[[:space:]]+primary:[[:space:]]*$/   { cur = "primary";   next }
            /^[[:space:]]+secondary:[[:space:]]*$/ { cur = "secondary"; next }
            match($0, /"[^"]+"/) { print substr($0, RSTART + 1, RLENGTH - 2) "\t" skill "\t" cur }
        ' "$skill_md"
    done | LC_ALL=C sort -u
}

# dropped_citations <canon.generated.ts> <root> — declarations the frontmatter
# makes that the canon does not record. The work stays shelved by its other
# citers, so nothing looks broken; only the citation count is understated, and
# #274 renders that count as spine height.
dropped_citations() {
    comm -23 <(declared_edges "$2") <(canon_citation_rows "$1" | LC_ALL=C sort -u)
}

# declares_work_at_tier <skill.md> <"Title — Author"> <tier> — does that skill
# declare that exact string under that exact `sources:` sub-key? Exact, not
# surname-tolerant: both sides are now the same string read from the same file,
# so any difference is drift rather than formatting.
declares_work_at_tier() {
    awk -v want="$2" -v tier="$3" '
        /^---[[:space:]]*$/       { fm++; next }
        fm != 1                   { next }
        /^sources:[[:space:]]*$/  { ins = 1; cur = "primary"; next }
        ins && /^[^[:space:]]/    { ins = 0 }
        !ins                      { next }
        /^[[:space:]]+primary:[[:space:]]*$/   { cur = "primary";   next }
        /^[[:space:]]+secondary:[[:space:]]*$/ { cur = "secondary"; next }
        match($0, /"[^"]+"/) {
            if (substr($0, RSTART + 1, RLENGTH - 2) == want && cur == tier) { found = 1; exit }
        }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

# lesson_keys <data.ts> — every key of the `lessons` object.
#
# The keys are verbatim `sources:` strings, so a key naming a work no skill
# declares is dead prose: it never renders, and nothing else in the page would
# say so. That is issue #272's shape surviving into the enrichment layer.
lesson_keys() {
    awk '
        /^export const lessons/ { inl = 1; next }
        inl && /^\};/           { inl = 0; next }
        inl && match($0, /^[[:space:]]*"[^"]+"[[:space:]]*:/) {
            s = substr($0, RSTART, RLENGTH)
            if (match(s, /"[^"]+"/)) print substr(s, RSTART + 1, RLENGTH - 2)
        }
    ' "$1"
}

# stray_work_mentions <data.ts> <root> — every declared work named in data.ts
# OUTSIDE the `export const lessons` block, as "<work>\t<line>: <text>".
#
# THIS IS THE REGRESSION CHECK FOR #273. The canon used to be a hand-written
# array in this very file, and re-introducing one is how the derivation gets
# quietly bypassed — a second list would render beside the generated one and
# nothing else here would notice. `lessons` is the single sanctioned place in
# data.ts to name a work, and it is sanctioned precisely because the suite
# asserts nothing about its completeness.
#
# SCOPED BY POSITION, NOT BY MEMBERSHIP. A first draft asked whether each work
# named in data.ts was also a `lessons` key, and a fixture proved that vacuous:
# the eight hand-written lessons are exactly the eight works the old shelf held,
# so restoring that array verbatim named only works that were already keys, and
# the check went green on the precise regression it exists to catch. Asking
# WHERE the string appears rather than WHETHER it appears elsewhere has no such
# hole — a second array is outside the block no matter which works it lists.
stray_work_mentions() {
    local data="$1" root="$2" work outside hit
    outside="$(awk '
        /^export const lessons/ { inl = 1 }
        inl && /^\};/           { inl = 0; next }
        !inl                    { print NR ": " $0 }
    ' "$data")"
    while IFS= read -r work; do
        [ -n "$work" ] || continue
        # `|| true`: no match is the passing case, and this runs under set -e.
        # printf rather than a sed replacement, because `&` is the whole-match
        # backreference there and four declared works carry one in the author.
        hit="$(printf '%s\n' "$outside" | grep -F -m1 -- "$work" || true)"
        [ -n "$hit" ] && printf '%s\t%s\n' "$work" "$hit" || true
    done <<EOF
$(declared_works "$root"/*/SKILL.md | LC_ALL=C sort -u)
EOF
}

# orphan_lessons <data.ts> <root> — every `lessons` key that no skill declares.
orphan_lessons() {
    comm -23 <(lesson_keys "$1" | LC_ALL=C sort -u) \
             <(declared_works "$2"/*/SKILL.md | LC_ALL=C sort -u)
}

# rendered_keys <index.html> — the work each rendered spine carries in its
# `data-key`, with the entity escapes the templating applies undone.
#
# THE ONLY READING THAT SEES THE PAGE. Everything else in this suite reads
# source files and reasons about what they would produce. This one reads what
# was actually produced, which is the difference between "the component imports
# the canon" and "the reader can see all 45 works" — and #273 is a bug report
# about the second.
rendered_keys() {
    grep -o 'data-key="[^"]*"' "$1" \
        | sed -e 's/^data-key="//' -e 's/"$//' \
              -e 's/&#38;/\&/g' -e 's/&amp;/\&/g' \
              -e 's/&#39;/'"'"'/g' -e 's/&quot;/"/g' \
              -e 's/&lt;/</g' -e 's/&gt;/>/g'
}

# declares_title <skill.md> <title> — does that skill declare a work with this
# exact title? The `mappings` array cites a bare title, with no author to check
# a surname against, so this is the weaker of the two matchers by necessity.
declares_title() {
    local candidate
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        [ "${candidate%% — *}" = "$2" ] && return 0
    done <<EOF
$(declared_works "$1")
EOF
    return 1
}

# unmapped_rows <data.ts> <root> — every `mappings` row whose cited book is not
# declared by every skill the row names. Empty output is the passing state.
unmapped_rows() {
    local data="$1" root="$2" source skills skill dir
    while IFS="$(printf '\t')" read -r source skills; do
        [ -n "$source" ] || continue
        # The skill cell may name more than one stage ("/pre-merge · /closeout").
        # The row claims the principle drives each of them, so each must declare it.
        for skill in ${skills//·/ }; do
            dir="${skill#/}"
            [ -n "$dir" ] || continue
            if [ ! -f "$root/$dir/SKILL.md" ]; then
                printf '%s\t%s names /%s, which is not a skill in this repo\n' "$source" "$source" "$dir"
                continue
            fi
            declares_title "$root/$dir/SKILL.md" "$source" \
                || printf '%s\t/%s does not declare it in its sources: frontmatter\n' "$source" "$dir"
        done
    done <<EOF
$(mapping_rows "$data")
EOF
}

# -----------------------------------------------------------------------------
section "the declaration population is fully read"

# A FLOOR, in the shape `test-oracle-table-coverage.sh` established. It catches
# the frontmatter extractor going blind — an empty declaration set would pass
# every comparison below vacuously and read as a page defect rather than a
# broken reading. The derived equalities that catch a PARTLY unreadable
# population live in the canon section further down, where the two independent
# readings of the array are.
MIN_DECLARED_WORKS=20

[ -f "$data_ts" ] || fatal "$data_ts is missing; the canon section moved and this suite has not followed it."

declared_count="$(declared_works "$repo_root"/*/SKILL.md | sort -u | grep -c . || true)"

if [ "$declared_count" -lt "$MIN_DECLARED_WORKS" ]; then
    fatal "read $declared_count declared work(s) from skill frontmatter, expected at least $MIN_DECLARED_WORKS.
       The extractor is broken, not the repo — an empty declaration set would fail
       every check at once and read as a page defect. If sources were genuinely
       removed, lower MIN_DECLARED_WORKS in this file as a deliberate edit."
fi
ok "read $declared_count distinct declared work(s) across all skills (floor: $MIN_DECLARED_WORKS)"

# -----------------------------------------------------------------------------
section "one work, one spelling"

collisions="$(alias_collisions "$repo_root"/*/SKILL.md)"
while IFS="$(printf '\t')" read -r offender variants; do
    [ -n "$offender" ] || continue
    bad "\"$offender\" is declared under more than one author spelling" \
        "the variants are: $variants. Any derivation over the frontmatter keys on the whole string, so a second spelling splits one work into two entries and halves each one's citation count. Pick one spelling and use it in every skill that declares the work — an alias table would be a second hand-maintained canon list, which is the defect issue #273 exists to remove."
done <<EOF
$collisions
EOF

if [ -z "$collisions" ]; then
    ok "all $declared_count declared work(s) use one author spelling per title"
fi

# -----------------------------------------------------------------------------
section "the canon module is derived from the frontmatter, not written by hand"

# ISSUE #273. The shelf used to be a hand-written array, so a source added to a
# skill never reached the page and a spine on the page needed nothing behind it.
# `scripts/generate-canon.sh` derives the whole canon from `sources:` frontmatter
# and this section is what keeps the committed output honest. The freshness check
# is byte-exact; everything after it re-reads both sides with THIS file's own
# extractors, because a diff against the generator proves only that the file
# matches the generator — not that the generator is right.

MIN_CANON_ENTRIES=20

[ -f "$canon_ts" ] || fatal "$canon_ts is missing.
       The canon is generated; run \`bash scripts/generate-canon.sh\` and commit it."

entry_slots="$(canon_slots "$canon_ts")"
entry_count="$(canon_rows "$canon_ts" | grep -c . || true)"

if [ "$entry_count" -lt "$MIN_CANON_ENTRIES" ]; then
    fatal "read $entry_count canon entr(ies), expected at least $MIN_CANON_ENTRIES.
       The extractor is broken, not the page — a canon that reads as empty passes
       every set comparison below vacuously."
fi
if [ "$entry_slots" -ne "$entry_count" ]; then
    fatal "the canon array holds $entry_slots records but only $entry_count parsed.
       $((entry_slots - entry_count)) entr(ies) are written in a spelling the extractor does not
       recognize, which makes them invisible to every check below while the page
       renders them. Fix the extractor or the generator; do not lower a floor."
fi
ok "all $entry_slots canon entr(ies) parsed ($entry_slots slots = $entry_count rows)"

# --- 1. freshness: the committed module is what the generator produces now ---

if generator_diff="$(bash "$repo_root/scripts/generate-canon.sh" --check 2>&1)"; then
    ok "site/src/lib/canon.generated.ts is what scripts/generate-canon.sh produces from the current frontmatter"
else
    bad "site/src/lib/canon.generated.ts is stale" \
        "a skill's sources: block changed and the canon was not regenerated, so the page is back to asserting a set the repo does not produce. Run \`bash scripts/generate-canon.sh\` and commit the result. Generator output:
$generator_diff"
fi

# --- 2. population: the same set, read independently of the generator ---

declared_set="$(declared_works "$repo_root"/*/SKILL.md | LC_ALL=C sort -u)"
canon_set="$(canon_rows "$canon_ts" | cut -f1 | LC_ALL=C sort -u)"

missing_from_canon="$(comm -23 <(printf '%s\n' "$declared_set") <(printf '%s\n' "$canon_set"))"
while IFS= read -r offender; do
    [ -n "$offender" ] || continue
    bad "\"$offender\" is declared by a skill but is absent from the canon" \
        "this is issue #273's headline direction — 34 declared works never reached the page. Adding a source to a skill must be the only action needed to shelve it."
done <<EOF
$missing_from_canon
EOF

extra_in_canon="$(comm -13 <(printf '%s\n' "$declared_set") <(printf '%s\n' "$canon_set"))"
while IFS= read -r offender; do
    [ -n "$offender" ] || continue
    bad "the canon carries \"$offender\", which no skill declares" \
        "this is issue #272's direction — the shelf asserting provenance the repo cannot produce."
done <<EOF
$extra_in_canon
EOF

if [ -z "$missing_from_canon" ] && [ -z "$extra_in_canon" ]; then
    ok "the canon and the frontmatter name the same $entry_count work(s), in both directions"
fi

# --- 3. types: the property, re-derived rather than the rule re-implemented ---

# #274 renders papers as a different object, so a wrong type is a visible defect
# rather than a metadata nit. The rule lives in the generator; what is asserted
# here is the PROPERTY it exists to produce — an author carrying `et al.` or a
# trailing parenthesized year is a paper citation, and nothing else is.
mistyped="$(mistyped_entries "$canon_ts")"
while IFS="$(printf '\t')" read -r offender why; do
    [ -n "$offender" ] || continue
    bad "the canon types \"$offender\" wrongly — $why" \
        "#274 renders papers as a different object than books, so a wrong type is a visible defect rather than a metadata nit."
done <<EOF
$mistyped
EOF

paper_count="$(canon_rows "$canon_ts" | cut -f4 | grep -c '^paper$' || true)"
[ -n "$mistyped" ] || ok "every canon entry is typed book or paper, and the $paper_count paper(s) are exactly those the frontmatter cites as papers"

# --- 4. citations: every edge resolves, in both directions ---

MIN_CITATIONS=60
citation_rows="$(canon_citation_rows "$canon_ts")"
citation_count="$(printf '%s' "$citation_rows" | grep -c . || true)"
if [ "$citation_count" -lt "$MIN_CITATIONS" ]; then
    fatal "read $citation_count citation edge(s), expected at least $MIN_CITATIONS.
       The extractor is broken — an unread citation set passes the checks below
       vacuously, and the citation count is what #274 renders as spine height."
fi

unresolved="$(unresolved_citations "$canon_ts" "$repo_root")"
while IFS="$(printf '\t')" read -r offender why; do
    [ -n "$offender" ] || continue
    bad "the canon cites \"$offender\" unsoundly — $why" \
        "the opened book links to that skill and labels the citation with that tier; both sides are read from the same file, so this is drift rather than a formatting difference."
done <<EOF
$unresolved
EOF
[ -z "$unresolved" ] && ok "all $citation_count citation edge(s) resolve to a skill that declares the work at that tier"

# The reverse edge. Without it the generator could drop a citation and stay
# green: the work would still be shelved by its other citers, and only its
# citation count — the signal #274 renders — would quietly be wrong.
dropped="$(dropped_citations "$canon_ts" "$repo_root")"
while IFS="$(printf '\t')" read -r full skill tier; do
    [ -n "$full" ] || continue
    bad "/$skill declares \"$full\" as $tier and the canon does not record that citation" \
        "the work may still be shelved by another citer, so nothing looks broken — but its citation count is understated, and #274 renders that count."
done <<EOF
$dropped
EOF
[ -z "$dropped" ] && ok "every work/skill/tier declaration in the frontmatter is recorded as a citation"

# -----------------------------------------------------------------------------
section "the page renders the derived canon, not a hand-written list"

shelf_astro="$repo_root/site/src/components/Shelf.astro"
[ -f "$shelf_astro" ] || fatal "$shelf_astro is missing; the canon section moved and this suite has not followed it."

strays="$(stray_work_mentions "$data_ts" "$repo_root")"
while IFS="$(printf '\t')" read -r offender where; do
    [ -n "$offender" ] || continue
    bad "site/src/lib/data.ts names \"$offender\" outside the lessons map, at $where" \
        "the canon is derived into site/src/lib/canon.generated.ts; a second, hand-written list of works in data.ts is issue #273 re-opening. If this is a pull-quote, it belongs in \`lessons\` keyed by the verbatim sources: string."
done <<EOF
$strays
EOF
[ -n "$strays" ] || ok "data.ts names a declared work only as a lessons key"

orphans="$(orphan_lessons "$data_ts" "$repo_root")"
while IFS= read -r key; do
    [ -n "$key" ] || continue
    bad "lessons carries a pull-quote for \"$key\", which no skill declares" \
        "the key must be the verbatim sources: string of a declared work, or the quote never renders and nothing says so — #272's defect one layer in."
done <<EOF
$orphans
EOF
lesson_count="$(lesson_keys "$data_ts" | grep -c . || true)"
[ -n "$orphans" ] || ok "all $lesson_count hand-written lesson(s) are keyed to a work some skill declares"

# THE NARROWING CHECK, and an honest note about what it is worth. This keys on
# a language construct, which `mechanism-generality-lags-the-pattern-2026-08-23.md`
# is explicit is the weaker kind of detector — it catches `.slice(` and misses a
# reader that narrows some other way. It is here as a fast local tripwire; the
# check that actually holds the property is the rendered-output section below,
# which CI always runs because it builds the site first.
if grep -q 'from "../lib/canon.generated"' "$shelf_astro"; then
    ok "Shelf.astro renders from the generated canon"
else
    bad "Shelf.astro does not import the generated canon" \
        "the canon section is fed by site/src/lib/canon.generated.ts; a component reading anything else is rendering a list nothing derives."
fi

if narrowing="$(grep -nE '\b(canon|spines)\b[^;]*\.(slice|filter|splice|shift|pop)\(' "$shelf_astro")"; then
    bad "Shelf.astro narrows the canon before rendering it" \
        "$narrowing
every declared work must reach the page — a curated subset is what issue #273 reported. Ordering and styling are free; dropping entries is not."
else
    ok "Shelf.astro renders the canon without slicing or filtering it"
fi

# -----------------------------------------------------------------------------
section "the rendered canon section carries every declared work"

built_page="$repo_root/site/dist/index.html"
if [ ! -f "$built_page" ]; then
    printf '  SKIP no built page at site/dist/index.html — run "npm run build" in site/ to include this check.\n'
    printf '       CI always runs it: the canon-render job builds the site before invoking this suite.\n'
else
    MIN_RENDERED=20
    rendered="$(rendered_keys "$built_page" | LC_ALL=C sort -u)"
    rendered_count="$(printf '%s' "$rendered" | grep -c . || true)"
    if [ "$rendered_count" -lt "$MIN_RENDERED" ]; then
        fatal "read $rendered_count spine(s) out of the built page, expected at least $MIN_RENDERED.
       The reader is broken, not the page — a page that reads as empty passes the
       comparison below vacuously, which is the failure this whole suite exists
       to make impossible."
    fi

    unrendered="$(comm -23 <(printf '%s\n' "$canon_set") <(printf '%s\n' "$rendered"))"
    while IFS= read -r offender; do
        [ -n "$offender" ] || continue
        bad "\"$offender\" is in the canon and does not reach the rendered page" \
            "issue #273 verbatim: adding a source to a skill must be the only action needed to make it appear on the page."
    done <<EOF
$unrendered
EOF

    unbacked_render="$(comm -13 <(printf '%s\n' "$canon_set") <(printf '%s\n' "$rendered"))"
    while IFS= read -r offender; do
        [ -n "$offender" ] || continue
        bad "the page renders a spine for \"$offender\", which is not in the canon" \
            "issue #272's direction: the shelf asserting a work the repo does not declare."
    done <<EOF
$unbacked_render
EOF

    if [ -z "$unrendered" ] && [ -z "$unbacked_render" ]; then
        ok "all $rendered_count rendered spine(s) are exactly the $entry_count canon work(s)"
    fi
fi

# -----------------------------------------------------------------------------
section "every mapped principle is declared by the stage it names"

MIN_MAPPING_ROWS=4
mapping_count="$(mapping_rows "$data_ts" | grep -c . || true)"
if [ "$mapping_count" -lt "$MIN_MAPPING_ROWS" ]; then
    fatal "read $mapping_count mappings row(s), expected at least $MIN_MAPPING_ROWS.
       The extractor is broken, not the page — an unread mappings array passes the
       check below vacuously, which is how this array went unpinned in the first
       place. If rows were genuinely removed, lower MIN_MAPPING_ROWS here as a
       deliberate edit."
fi

unmapped="$(unmapped_rows "$data_ts" "$repo_root")"
while IFS="$(printf '\t')" read -r offender why; do
    [ -n "$offender" ] || continue
    bad "the practice table cites \"$offender\" — $why" \
        "Practice.astro renders this row under \"Each stage operationalizes a named discipline from the literature\", which is the shelf's claim in a second array. Declare the work in the stage the row names, or cite the stage that declares it."
done <<EOF
$unmapped
EOF

if [ -z "$unmapped" ]; then
    ok "all $mapping_count mappings row(s) are declared by every stage they name (floor: $MIN_MAPPING_ROWS)"
fi

# -----------------------------------------------------------------------------
section "the detector still detects (self-test)"

# VALIDATE THE INSTRUMENT, NOT ONLY THE SUBJECT
# (docs/solutions/testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md).
# The section above passes when the shelf is clean AND when any extractor has
# silently stopped returning something the others can disagree with. The floor
# and the slot equality catch the blunt failures; these fixtures catch a matcher
# that accepts everything, one that rejects everything, and each bound of the
# frontmatter scan.
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

mkdir -p "$fixtures/alpha" "$fixtures/beta" "$fixtures/gamma"

cat > "$fixtures/alpha/SKILL.md" <<'FIXTURE'
---
name: alpha
description: "A fixture skill that declares a source."
sources:
  primary:
    - "Known Book — Jane Doe"
  secondary:
    - "Second Book — Ada Byron"
---

# Alpha
FIXTURE

cat > "$fixtures/beta/SKILL.md" <<'FIXTURE'
---
name: beta
description: "A fixture skill with no sources block."
---

# Beta

Skills declare provenance like this:

sources:
  primary:
    - "Body Only Book — Nobody"
FIXTURE

# gamma exists for the terminator bound: a top-level key AFTER `sources:`, with
# a quoted value. Nothing in this repo enforces key order — CLAUDE.md § Skill
# Structure shows `sources:` last purely as an example — so a skill may legally
# look like this, and the scan must stop at `model:` rather than harvest it.
cat > "$fixtures/gamma/SKILL.md" <<'FIXTURE'
---
name: gamma
description: "A fixture skill with a quoted top-level key after sources:."
sources:
  primary:
    - "Gamma Book — Grace Hopper"
model: "Trailing Key Book — Impostor"
---

# Gamma
FIXTURE

# --- the frontmatter extractor, both bounds ---

extracted="$(declared_works "$fixtures"/*/SKILL.md | sort | tr '\n' '|')"
if [ "$extracted" = "Gamma Book — Grace Hopper|Known Book — Jane Doe|Second Book — Ada Byron|" ]; then
    ok "declared_works reads every sources: entry from frontmatter and nothing else"
else
    bad "declared_works returned an unexpected set" "got: $extracted"
fi

if declared_works "$fixtures/beta/SKILL.md" | grep -q 'Body Only Book'; then
    bad "declared_works harvested a sources: block from a SKILL.md body" \
        "prose that merely shows or discusses a sources: block must not back a shelf claim"
else
    ok "a sources: block in a SKILL.md body is not treated as a declaration"
fi

if declared_works "$fixtures/gamma/SKILL.md" | grep -q 'Trailing Key Book'; then
    bad "declared_works ran past the end of the sources: block" \
        "a quoted top-level key after sources: was harvested as a declaration; deleting the block terminator must not leave this suite green"
else
    ok "a quoted frontmatter key after sources: is not treated as a declaration"
fi

# --- the alias-collision detector, both directions ---
#
# These fixtures live in their own subtree because the exact-set assertion above
# reads "$fixtures"/*/SKILL.md and would break if this check added a skill to it.
#
# Per `../testing-patterns/mutate-the-oracle-not-only-the-subject-2026-08-19.md`,
# both a subject mutation and an oracle mutation are here: `two-spellings`
# proves the detector still detects, and `one-spelling` + `near-title` prove it
# has not degenerated into flagging everything — which is the failure mode that
# would get this check deleted the first week it cried wolf.
mkdir -p "$fixtures/alias/one" "$fixtures/alias/two" "$fixtures/alias/three"

alias_fixture() {
    cat > "$fixtures/alias/$1/SKILL.md" <<FIXTURE
---
name: $1
description: "An alias fixture."
sources:
  primary:
    - "$2"
---

# $1
FIXTURE
}

# THE CLEAN CASE: the same work declared identically by two skills. This is what
# 8 of the repo's skills do with *Thinking in Systems*, so a detector that
# flagged it would be red on every clean tree.
alias_fixture one "Shared Book — Jane Doe"
alias_fixture two "Shared Book — Jane Doe"
alias_fixture three "Different Book — Ada Byron"
clean_collisions="$(alias_collisions "$fixtures"/alias/*/SKILL.md)"
if [ -z "$clean_collisions" ]; then
    ok "one work declared identically by two skills is not a collision"
else
    bad "the collision detector flagged a repo-normal duplicate declaration" \
        "got: $clean_collisions — most works in this repo are declared by several skills, and every one of them would fail"
fi

# THE NEAR-TITLE TRAP: one title is a prefix of the other. A detector matching on
# substrings rather than on the whole title-before-the-separator reports here.
alias_fixture three "Shared Book Two — Jane Doe"
near_collisions="$(alias_collisions "$fixtures"/alias/*/SKILL.md)"
if [ -z "$near_collisions" ]; then
    ok "a title that merely starts with another title is not a collision"
else
    bad "the collision detector matched on a title prefix" "got: $near_collisions"
fi

# THE PLANTED VARIANT: #273's defect exactly — one work, two author spellings.
alias_fixture three "Shared Book — J. Doe"
planted="$(alias_collisions "$fixtures"/alias/*/SKILL.md)"
planted_count="$(printf '%s' "$planted" | grep -c . || true)"
if [ "$planted_count" -eq 1 ] && [ "${planted%%	*}" = "Shared Book" ]; then
    ok "one work declared under two author spellings is flagged, naming the work"
else
    bad "the collision detector missed a planted author-spelling variant" \
        "expected exactly 1 row for \"Shared Book\", got $planted_count row(s): $planted"
fi

# The variants must reach the failure message; a row that names the work but not
# the spellings cannot be acted on without re-running the extraction by hand.
if [ "${planted#*	}" = "Jane Doe | J. Doe" ] || [ "${planted#*	}" = "J. Doe | Jane Doe" ]; then
    ok "the collision row carries both spellings, not just the work"
else
    bad "the collision row did not carry both author spellings" "got: ${planted#*	}"
fi

rm -rf "$fixtures/alias"

# --- the generator, against fixtures ---
#
# The section above proves the committed module matches the generator. These
# fixtures prove the generator matches the frontmatter, which is the half a
# byte-exact diff can never establish.
gen="$fixtures/gen"
mkdir -p "$gen/booky" "$gen/papery" "$gen/yearless" "$gen/parenthetical"

gen_fixture() {
    local name="$1" tier="$2"
    shift 2
    mkdir -p "$gen/$name"
    {
        printf -- '---\nname: %s\ndescription: "A generator fixture."\nsources:\n  %s:\n' "$name" "$tier"
        printf -- '    - "%s"\n' "$@"
        printf -- '---\n\n# %s\n' "$name"
    } > "$gen/$name/SKILL.md"
}

gen_fixture booky         primary   "Plain Book — Jane Doe" "Shared Work — Ada Byron"
gen_fixture papery        secondary "A Debate Paper — Liang et al. (EMNLP 2024)" "Shared Work — Ada Byron"
gen_fixture yearless      primary   "Single-Author Paper — Doe (ICSE 2025)"
gen_fixture parenthetical primary   "A Book With A Subtitle (Second Edition) — Jane Doe"

genout="$fixtures/gen-canon.ts"
if bash "$repo_root/scripts/generate-canon.sh" --root "$gen" --out "$genout" > /dev/null; then
    ok "the generator runs against a fixture tree"
else
    bad "the generator failed on a fixture tree" "nothing below can report on a generator that did not run"
fi

gen_set="$(canon_rows "$genout" | cut -f1 | LC_ALL=C sort | tr '\n' '|')"
want_set='A Book With A Subtitle (Second Edition) — Jane Doe|A Debate Paper — Liang et al. (EMNLP 2024)|Plain Book — Jane Doe|Shared Work — Ada Byron|Single-Author Paper — Doe (ICSE 2025)|'
if [ "$gen_set" = "$want_set" ]; then
    ok "the generator emits one entry per distinct declared work, collapsing a work two skills share"
else
    bad "the generator emitted an unexpected set" "got: $gen_set"
fi

gen_type() { canon_rows "$genout" | awk -F"$(printf '\t')" -v w="$1" '$1 == w { print $4 }'; }

if [ "$(gen_type 'A Debate Paper — Liang et al. (EMNLP 2024)')" = "paper" ]; then
    ok "an author carrying \`et al.\` is typed paper"
else
    bad "an \`et al.\` citation was not typed paper" "#274 renders papers as a different object than books"
fi

if [ "$(gen_type 'Single-Author Paper — Doe (ICSE 2025)')" = "paper" ]; then
    ok "a single author with a trailing venue-and-year is typed paper"
else
    bad "a trailing parenthesized year was not typed paper" "the rule is \`et al.\` OR a trailing year, not \`et al.\` alone"
fi

if [ "$(gen_type 'Plain Book — Jane Doe')" = "book" ]; then
    ok "a plain author is typed book"
else
    bad "a plain author was typed paper" "a rule that types everything as a paper is as wrong as one that types nothing"
fi

# THE TRAP: parentheses without a year. A rule keying on "(...)" alone reports
# here, and edition markers are the likeliest way a book acquires them.
if [ "$(gen_type 'A Book With A Subtitle (Second Edition) — Jane Doe')" = "book" ]; then
    ok "parentheses in the title, with no year in the author, stay a book"
else
    bad "a parenthesized edition marker was typed paper" "the tell is a year in the AUTHOR field, not a bracket anywhere in the string"
fi

gen_tier() {
    canon_citation_rows "$genout" | awk -F"$(printf '\t')" -v w="$1" -v s="$2" '$1 == w && $2 == s { print $3 }'
}
if [ "$(gen_tier 'Shared Work — Ada Byron' booky)" = "primary" ] \
    && [ "$(gen_tier 'Shared Work — Ada Byron' papery)" = "secondary" ]; then
    ok "one work cited by two skills records each skill's own tier"
else
    bad "the generator lost a citation tier" \
        "got booky=$(gen_tier 'Shared Work — Ada Byron' booky) papery=$(gen_tier 'Shared Work — Ada Byron' papery); tier is what the opened book labels each citing skill with"
fi

# ISSUE #273'S LITERAL REPRODUCTION STEP: add a source to a skill, do not
# regenerate, and the check must go red.
if bash "$repo_root/scripts/generate-canon.sh" --root "$gen" --out "$genout" --check > /dev/null 2>&1; then
    ok "--check passes on a canon that was just generated"
else
    bad "--check failed on a freshly generated canon" "it now cries wolf on every clean tree, which is how a real check gets deleted"
fi

gen_fixture latecomer primary "A Work Added After Generation — Grace Hopper"
if bash "$repo_root/scripts/generate-canon.sh" --root "$gen" --out "$genout" --check > /dev/null 2>&1; then
    bad "--check passed after a skill gained a source without regeneration" \
        "this is issue #273's reproduction step verbatim; a green here means the page can silently omit a declared work again"
else
    ok "--check goes red when a skill gains a source and the canon is not regenerated"
fi

# The body-block bound, on the generator this time — the frontmatter extractor
# in this file has its own fixture, and they are two implementations of one rule.
mkdir -p "$gen/prosey"
cat > "$gen/prosey/SKILL.md" <<'FIXTURE'
---
name: prosey
description: "A fixture whose sources: block is prose."
---

# Prosey

Skills declare provenance like this:

sources:
  primary:
    - "Body Only Book — Nobody"
FIXTURE
bash "$repo_root/scripts/generate-canon.sh" --root "$gen" --out "$genout" > /dev/null
if canon_rows "$genout" | cut -f1 | grep -q 'Body Only Book'; then
    bad "the generator shelved a sources: block quoted in a SKILL.md body" \
        "prose that merely shows a sources: block must not put a work on the page"
else
    ok "the generator does not shelve a sources: block quoted in a SKILL.md body"
fi

# --- the canon detectors, against a mutated canon ---
#
# The three checks in the live section above only ever run against a clean tree,
# which is the shape `partial-oracle-selfcheck-2026-08-22.md` warns about: a
# detector that has silently stopped detecting reports the same full green. Each
# one is mutated here in the direction it exists to catch, with a grep guard on
# the mutation itself, because a self-test cannot report on a change that never
# landed.

if [ -n "$(mistyped_entries "$genout")" ] \
    || [ -n "$(unresolved_citations "$genout" "$gen")" ] \
    || [ -n "$(dropped_citations "$genout" "$gen")" ]; then
    bad "a freshly generated fixture canon failed one of the three canon detectors" \
        "each of them cries wolf on a clean canon, so the mutations below prove nothing"
else
    ok "a freshly generated fixture canon passes all three canon detectors"
fi

sed 's/type: "paper"/type: "book"/' "$genout" > "$fixtures/mistyped.ts"
if grep -q 'type: "book"' "$fixtures/mistyped.ts" && ! grep -q 'type: "paper"' "$fixtures/mistyped.ts"; then
    typed_bad="$(mistyped_entries "$fixtures/mistyped.ts" | grep -c . || true)"
    if [ "$typed_bad" -eq 2 ]; then
        ok "a paper retyped as a book is flagged"
    else
        bad "retyping both papers as books produced $typed_bad finding(s), want 2" \
            "#274 renders papers as a different object; a type nobody checks is a type that drifts"
    fi
else
    bad "the mistype fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

sed 's/type: "paper"/type: "offprint"/' "$genout" > "$fixtures/unknown-type.ts"
if grep -q 'type: "offprint"' "$fixtures/unknown-type.ts"; then
    if [ -n "$(mistyped_entries "$fixtures/unknown-type.ts")" ]; then
        ok "a type outside book|paper is flagged rather than passed through"
    else
        bad "an unrenderable type passed the type check" \
            "the page has two objects; a third value silently renders as neither"
    fi
else
    bad "the unknown-type fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

sed 's/{ skill: "booky", tier: "primary" }/{ skill: "booky", tier: "secondary" }/' "$genout" > "$fixtures/wrong-tier.ts"
if ! diff -q "$genout" "$fixtures/wrong-tier.ts" > /dev/null; then
    if [ -n "$(unresolved_citations "$fixtures/wrong-tier.ts" "$gen")" ]; then
        ok "a citation recorded at a tier the skill does not declare is flagged"
    else
        bad "a wrong citation tier passed" "the opened book labels each citing skill primary or secondary; an unchecked label is decoration"
    fi
else
    bad "the wrong-tier fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

sed 's/{ skill: "booky",/{ skill: "no-such-skill",/' "$genout" > "$fixtures/ghost-citer.ts"
if grep -q 'no-such-skill' "$fixtures/ghost-citer.ts"; then
    if [ -n "$(unresolved_citations "$fixtures/ghost-citer.ts" "$gen")" ]; then
        ok "a citation naming a skill that does not exist is flagged"
    else
        bad "a citation to a nonexistent skill passed" "the opened book links to that path; a dead link cannot back a provenance claim"
    fi
else
    bad "the ghost-citer fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

# THE QUIET ONE. Dropping a citation from a work that has another citer leaves
# the work shelved and every forward edge sound — only the count is wrong.
grep -v '{ skill: "papery", tier: "secondary" },' "$genout" > "$fixtures/dropped-edge.ts"
if [ "$(grep -c . "$fixtures/dropped-edge.ts")" -lt "$(grep -c . "$genout")" ]; then
    if [ -n "$(unresolved_citations "$fixtures/dropped-edge.ts" "$gen")" ]; then
        bad "the forward-edge check reported on a DROPPED citation" \
            "it cannot — every remaining edge still resolves. If it fires here the two directions are not independent and the reverse check is untested"
    elif [ -n "$(dropped_citations "$fixtures/dropped-edge.ts" "$gen")" ]; then
        ok "a citation dropped from the canon is flagged by the reverse check, and only by it"
    else
        bad "a dropped citation passed both directions" \
            "the work stays shelved by its other citer, so nothing looks broken — and the citation count #274 renders is silently wrong"
    fi
else
    bad "the dropped-edge fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

rm -rf "$gen" "$genout"

# --- the canon parse, on an entry the extractor cannot read ---
#
# Ported from the fixture that guarded the old hand-written shelf array, because
# the gap it exposes is a property of the parser and not of the array it once
# parsed: an entry written in a spelling `canon_rows` does not recognize is
# invisible to every set comparison while the page renders it. Single quotes are
# the cheap way to produce that, and no formatter in this repo forbids them.
cat > "$fixtures/canon-clean.ts" <<'CANON'
export const canon: CanonWork[] = [
	{
		full: "Known Book — Jane Doe",
		title: "Known Book",
		author: "Jane Doe",
		type: "book",
		citations: [
			{ skill: "alpha", tier: "primary" },
		],
	},
	{
		full: "Gamma Book — Grace Hopper",
		title: "Gamma Book",
		author: "Grace Hopper",
		type: "book",
		citations: [
			{ skill: "gamma", tier: "primary" },
		],
	},
];
CANON
if [ "$(canon_rows "$fixtures/canon-clean.ts" | grep -c . || true)" -eq 2 ] \
    && [ "$(canon_slots "$fixtures/canon-clean.ts")" -eq 2 ]; then
    ok "canon_rows and canon_slots agree on a clean 2-entry canon, ignoring nested citation objects"
else
    bad "the canon extractors disagree on a clean fixture" \
        "slots=$(canon_slots "$fixtures/canon-clean.ts") rows=$(canon_rows "$fixtures/canon-clean.ts" | grep -c . || true), want 2/2 — the nested citations sit at depth 2 and must not be counted as entries"
fi

sed "s/full: \"Gamma Book — Grace Hopper\"/full: 'Gamma Book — Grace Hopper'/" \
    "$fixtures/canon-clean.ts" > "$fixtures/canon-unparsed.ts"
if grep -q "full: 'Gamma Book" "$fixtures/canon-unparsed.ts"; then
    if [ "$(canon_slots "$fixtures/canon-unparsed.ts")" -eq 2 ] \
        && [ "$(canon_rows "$fixtures/canon-unparsed.ts" | grep -c . || true)" -eq 1 ]; then
        ok "an entry the canon extractor cannot parse still counts as a slot, so the gap is visible"
    else
        bad "an unparseable canon entry did not produce a slots/rows gap" \
            "without the gap, an entry written in an unanticipated spelling is invisible to every set comparison while the page renders it"
    fi
else
    bad "the single-quote canon fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

# --- the data.ts detectors, both directions ---

cat > "$fixtures/clean-data.ts" <<'DATA'
export const lessons: Lessons = {
	"Known Book — Jane Doe": "A pull-quote.",
};

export const repoUrl = "https://example.invalid";
DATA
if [ -z "$(stray_work_mentions "$fixtures/clean-data.ts" "$fixtures")" ] \
    && [ -z "$(orphan_lessons "$fixtures/clean-data.ts" "$fixtures")" ]; then
    ok "a data.ts naming a declared work only as a lessons key passes both directions"
else
    bad "a clean data.ts failed a data.ts detector" \
        "both of them cry wolf on the sanctioned shape, so the fixtures below prove nothing"
fi

# THE REGRESSION: a hand-written works array creeps back in beside the derived
# canon. This is #273 re-opening, and it is the reason data.ts is checked at all.
cat > "$fixtures/rehanded-data.ts" <<'DATA'
export const shelf = [
	{ title: "Gamma Book", author: "Hopper", full: "Gamma Book — Grace Hopper" },
];

export const lessons: Lessons = {
	"Known Book — Jane Doe": "A pull-quote.",
};
DATA
if [ -n "$(stray_work_mentions "$fixtures/rehanded-data.ts" "$fixtures")" ]; then
    ok "a hand-written works array re-introduced into data.ts is flagged"
else
    bad "a re-introduced hand-written works array passed" \
        "a second list rendering beside the derived one is exactly the drift issue #273 closed, and nothing else in this suite would see it"
fi

# THE VACUOUS-MEMBERSHIP CASE, which is the one that actually bit. The hand
# lessons are exactly the works the old shelf held, so restoring that shelf
# verbatim lists ONLY works that are already lessons keys. A membership test goes
# green here; a position test does not.
cat > "$fixtures/rehanded-same-works.ts" <<'DATA'
export const shelf = [
	{ title: "Known Book", author: "Doe", full: "Known Book — Jane Doe" },
];

export const lessons: Lessons = {
	"Known Book — Jane Doe": "A pull-quote.",
};
DATA
if [ -n "$(stray_work_mentions "$fixtures/rehanded-same-works.ts" "$fixtures")" ]; then
    ok "a hand-written array listing only works that already have lessons is still flagged"
else
    bad "a re-introduced shelf holding only already-curated works passed" \
        "this is the shape a straight revert of the pre-#273 shelf takes, and it is the one a membership test cannot see"
fi

cat > "$fixtures/orphan-lesson-data.ts" <<'DATA'
export const lessons: Lessons = {
	"Known Book — Jane Doe": "A pull-quote.",
	"A Work Nobody Declares — Ghost": "A pull-quote for nothing.",
};
DATA
orphaned="$(orphan_lessons "$fixtures/orphan-lesson-data.ts" "$fixtures" | grep -c . || true)"
if [ "$orphaned" -eq 1 ]; then
    ok "a lesson keyed to a work no skill declares is flagged"
else
    bad "the orphan-lesson check found $orphaned of 1 planted defect" \
        "a lesson whose key matches nothing never renders, and no other check in this suite would notice"
fi

# --- the rendered-page reader ---

cat > "$fixtures/page.html" <<'HTML'
<button class="spine" data-key="Known Book &#38; Friends — Jane Doe"></button>
<button class="spine" data-key="Gamma Book — Grace Hopper"></button>
<a href="#" data-key-other="not a spine">x</a>
HTML
read_back="$(rendered_keys "$fixtures/page.html" | tr '\n' '|')"
if [ "$read_back" = 'Known Book & Friends — Jane Doe|Gamma Book — Grace Hopper|' ]; then
    ok "rendered_keys reads each spine's work and undoes the templating's entity escapes"
else
    bad "rendered_keys misread the built page" \
        "got: $read_back — an ampersand in a title is escaped by the templating, and a reader that does not undo it reports every such work as unrendered"
fi

rm -f "$fixtures/canon-clean.ts" "$fixtures/canon-unparsed.ts" \
      "$fixtures/clean-data.ts" "$fixtures/rehanded-data.ts" \
      "$fixtures/rehanded-same-works.ts" \
      "$fixtures/orphan-lesson-data.ts" "$fixtures/page.html"

# --- the mappings direction ---

cat > "$fixtures/mapped.ts" <<'MAPPED'
export const mappings: Mapping[] = [
	{ principle: "p", source: "Known Book", skill: "/alpha", what: "w" },
	{ principle: "p", source: "Gamma Book", skill: "/gamma", what: "w" },
];
MAPPED
if [ -z "$(unmapped_rows "$fixtures/mapped.ts" "$fixtures")" ]; then
    ok "a mappings row whose named stage declares the cited book passes"
else
    bad "the detector flagged a truthful mappings row" "it now cries wolf on a clean practice table"
fi

cat > "$fixtures/mismapped.ts" <<'MISMAPPED'
export const mappings: Mapping[] = [
	{ principle: "p", source: "Known Book", skill: "/gamma", what: "w" },
	{ principle: "p", source: "A Book Nobody Declares", skill: "/alpha", what: "w" },
	{ principle: "p", source: "Known Book", skill: "/alpha · /beta", what: "w" },
];
MISMAPPED
mis="$(unmapped_rows "$fixtures/mismapped.ts" "$fixtures" | grep -c . || true)"
if [ "$mis" -eq 3 ]; then
    ok "a mappings row citing the wrong stage, an undeclared book, or a multi-stage cell with one bad stage is flagged"
else
    bad "the mappings detector flagged $mis of 3 planted defects" \
        "each row is a provenance claim; a wrong stage, an undeclared book, and one bad stage in a multi-stage cell must each fail"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
