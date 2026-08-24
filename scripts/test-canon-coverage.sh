#!/usr/bin/env bash
# test-canon-coverage.sh — the landing page's canon and the skills' `sources:`
# frontmatter must name the same works, and every attribution the page renders
# must be one the named skill actually makes.
#
# THE DRIFT CLASS. The canon section renders a shelf of books, and its copy in
# `site/src/components/Shelf.astro` tells the reader "each SKILL.md names its
# sources in frontmatter." Click a spine and the opened book names one skill
# (`Into the skill — ts-audit/SKILL.md`) and quotes a `sources:` excerpt beneath
# it. Every part of that is prose in `site/src/lib/data.ts` about a *different*
# file's frontmatter, and nothing relates the two. A spine can be added, or the
# skill backing a spine can lose its `sources:` block, and the page keeps
# asserting provenance the repo cannot produce. The failure emits no signal: the
# page builds, the spine renders, the book opens.
#
# THE INCIDENT (issue #272, 2026-08-23). The shelf carried *Total TypeScript —
# Matt Pocock* as one of eight spines and pointed it at `/ts-audit`. `/ts-audit`
# declared no `sources:` block at all — its frontmatter held only `name` and
# `description`. Every other spine traced to a real entry; that one traced to
# nothing, and had done so for as long as the page existed.
#
# THE PAIRING IS THE PROPERTY, NOT THE SHELF. This suite's first draft asked
# whether *some* skill declared each shelved work, and that is strictly weaker
# than what the page claims. Six of the eight works are declared by two to five
# skills each, so deleting a work from the one skill `bookDetails` names left the
# page asserting a `sources:` block that file no longer had — and the suite fully
# green, because a sibling skill still declared it. Reproduced twice in review,
# both times 11 passed / 0 failed. #272's own reproduction steps are the pairing
# ("the opened book claims the source feeds /ts-audit; read /ts-audit's
# frontmatter"), so the pairing is what has to be pinned.
#
# WHAT IT PINS, every side extracted from the real files rather than restated:
#   1. Every spine in the `shelf` array of `site/src/lib/data.ts`.
#   2. The skill each spine's `bookDetails` entry names in its `file:` field.
#   3. Every quoted entry under a `sources:` key in that skill's frontmatter.
#   4. Each shelved work matches a work THAT skill declares, on title, with the
#      shelf author's surname present in the declared entry.
#   5. No title is declared under two different author spellings anywhere in the
#      repo.
#
# WHY TITLE + SURNAME AND NOT STRING EQUALITY. The shelf and the frontmatter are
# two independently hand-authored sides. Until #273 they spelled the same authors
# four different ways — `/closeout` declared *Continuous Delivery* as "Jez Humble,
# David Farley" where `/pre-merge` and the shelf both said "Jez Humble & David
# Farley". Demanding equality would fail on a formatting difference and teach the
# reader to loosen the check. The surname test is what keeps title-only matching
# from accepting a different author's book that happens to share a title.
#
# THE VARIANTS ARE NOW A FAILURE, NOT A TOLERANCE (issue #273). #273 normalized
# those four spellings at the source, and check 5 is what keeps them normalized.
# It is the opposite move from the tolerance above, and both are load-bearing,
# because they govern different joins. The tolerance governs SHELF-to-SKILL,
# where two independently authored sides may legitimately differ in formatting.
# The collision check governs SKILL-to-SKILL, where a second spelling is never
# legitimate — it silently splits one work into two in any derivation over the
# frontmatter, and a derivation over the frontmatter is the thing #273 builds.
# #273 chose the detector over an alias table on purpose: a table is itself a
# hand-maintained canon list, which is the defect under repair.
#
# WHY THE SHELF POPULATION IS DERIVED AND NOT FLOORED. A floor guards against
# total blindness; it cannot notice the loss of one item, which is the
# granularity this drift arrives at. `MIN_CANON_WORKS=5` against a shelf of eight
# let three spines go unparsed, and a ninth spine written `full: '…'` — single
# quotes, which no formatter in this repo forbids — passed as a shrunken shelf,
# fully green, while the page rendered nine. So the array's own element count is
# read independently of the field regexes and required to equal the number of
# spines parsed. That is `partial-oracle-selfcheck-2026-08-22.md` Prevention #2
# ("derive the coverage instead of restating it") applied to the one population
# where restating it actually bit, and it closes the recurrence of
# `mechanism-generality-lags-the-pattern-2026-08-23.md` that review caught here:
# a detector keying on a language construct rather than on the property.
#
# THE SECOND HALF (issue #273). The paragraph above used to end here saying the
# shelf was hand-maintained and that fixing it was somebody else's issue. It is
# now `site/src/lib/canon.generated.ts`, produced by `scripts/generate-canon.sh`
# from the same `sources:` frontmatter, and the "canon module is derived" section
# below is what keeps the committed copy honest. It pins, each side read
# independently of the generator:
#
#   6. The committed module is byte-for-byte what the generator produces from the
#      frontmatter as it stands right now.
#   7. The canon and the frontmatter name the same set of works, in both
#      directions — no declared work missing, no shelved work undeclared.
#   8. Every entry is typed `book` or `paper`, and `paper` exactly when its own
#      author field is spelled as a paper citation.
#   9. Every citation edge resolves to a skill that declares that work at that
#      tier, AND every declaration in the frontmatter appears as an edge. The
#      reverse direction is not redundant: dropping one citation from a work with
#      other citers leaves the page looking correct and only the citation count
#      — which #274 renders as spine height — silently wrong.
#
# WHAT IT STILL DOES NOT PIN. `bookDetails[key].lesson` is hand-written prose,
# and nothing here checks its content. That is deliberate and load-bearing: the
# lessons are an OPTIONAL enrichment layer keyed by canonical work, so a work
# with no lesson degrades to the derived spread rather than being blocked from
# the page. A coverage check over the lessons would make curation mandatory and
# put the maintenance burden back exactly where #273 removed it from.
#
# The self-tests at the bottom run every extractor and both matchers against
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

# shelf_rows <data.ts> — one "<key>\t<Title — Author>" per spine. The key is
# `${author}-${title}`, which is exactly how Shelf.astro builds each spine's
# `data-key` and how `bookDetails` is keyed — so it is the join, not a guess.
#
# RECORD-BASED, NOT LINE-BASED. An earlier draft read one spine per line, which
# made a semantically null reflow — Prettier's normal output for a 145-character
# object literal — read as a shrunken shelf. Records are delimited by brace
# depth, so a spine may be written on one line or across seven.
shelf_rows() {
    awk '
        /^export const shelf/ { inshelf = 1; next }
        inshelf && /^\];/     { inshelf = 0; next }
        inshelf {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") { depth++; if (depth == 1) rec = ""; continue }
                if (c == "}") {
                    depth--
                    if (depth == 0) {
                        t = ""; a = ""; f = ""
                        if (match(rec, /title: "[^"]*"/))  t = substr(rec, RSTART + 8, RLENGTH - 9)
                        if (match(rec, /author: "[^"]*"/)) a = substr(rec, RSTART + 9, RLENGTH - 10)
                        if (match(rec, /full: "[^"]*"/))   f = substr(rec, RSTART + 7, RLENGTH - 8)
                        if (t != "" && a != "" && f != "") print a "-" t "\t" f
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

# shelf_slots <data.ts> — how many spine objects the array holds, counted by
# brace depth alone. It knows NO field name, which is the entire point: it is
# the one reading capable of disagreeing with shelf_rows above.
#
# THE INDEPENDENCE IS PINNED, NOT ASSERTED. A previous draft counted lines
# beginning with `{`, and a fixture proved that independent of *quote style* —
# not of the field regexes. Rewriting this to key on /title:/ && /author:/ &&
# /full:/ collapsed the oracle onto the extractor and the suite stayed at 17
# passed / 0 failed, whereupon a reflowed spine went silently unchecked. The
# multi-line fixture below separates the two implementations: on a reflowed
# spine no single line carries all three field names, so that collapse now
# fails here instead of passing.
shelf_slots() {
    awk '
        /^export const shelf/ { inshelf = 1; next }
        inshelf && /^\];/     { inshelf = 0; next }
        inshelf {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") { if (depth == 0) n++; depth++ }
                else if (c == "}") depth--
            }
        }
        END { print n + 0 }
    ' "$1"
}

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

# detail_file <data.ts> <key> — the SKILL.md that `bookDetails[key]` names as
# the source of this spine. Empty when the key has no entry, or when its entry
# carries no `file:` field; the caller distinguishes those two with
# detail_has_entry so the failure message can point at the right line.
#
# The key rule does NOT `next`. An earlier draft did, which skipped the `file:`
# of any entry written on a single line — `"Doe-Known Book": { file: "…" },` —
# and the reflow fixture below caught it. Falling through means one line can be
# both the key line and the field line, which is what a formatter that collapses
# a short entry will produce.
detail_file() {
    awk -v want="$2" '
        /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*\{/ {
            if (match($0, /"[^"]*"/)) cur = substr($0, RSTART + 1, RLENGTH - 2)
        }
        cur == want && match($0, /file: "[^"]*"/) {
            print substr($0, RSTART + 7, RLENGTH - 8)
            exit
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

# declares_work <skill.md> <"Title — Author"> — does that skill declare that
# work? Title must match exactly; the shelf author's surname must appear in the
# declared entry.
declares_work() {
    local title="${2%% — *}" surname="${2##* }" candidate
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        [ "${candidate%% — *}" = "$title" ] || continue
        if [[ "$candidate" == *"$surname"* ]]; then return 0; fi
    done <<EOF
$(declared_works "$1")
EOF
    return 1
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

# detail_has_entry <data.ts> <key> — does bookDetails hold this key at all?
# Distinguished from detail_file returning empty, so the failure message can
# tell "the spine opens to nothing" apart from "the entry has no file: field"
# and point the fixer at the right line.
detail_has_entry() {
    awk -v want="$2" '
        /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*\{/ {
            if (match($0, /"[^"]*"/) && substr($0, RSTART + 1, RLENGTH - 2) == want) {
                found = 1
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$1"
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

# unbacked_works <data.ts> <root> — every spine whose named skill does not back
# it, as "<work>\t<why>". Empty output is the passing state.
unbacked_works() {
    local data="$1" root="$2" key work skillfile
    while IFS="$(printf '\t')" read -r key work; do
        [ -n "$work" ] || continue
        skillfile="$(detail_file "$data" "$key")"
        if [ -z "$skillfile" ]; then
            if detail_has_entry "$data" "$key"; then
                printf '%s\tits bookDetails entry (key "%s") has no file: field to attribute the sources: block to\n' "$work" "$key"
            else
                printf '%s\tbookDetails has no entry for key "%s", so the spine opens to nothing\n' "$work" "$key"
            fi
            continue
        fi
        if [ ! -f "$root/$skillfile" ]; then
            printf '%s\tbookDetails names %s, which does not exist\n' "$work" "$skillfile"
            continue
        fi
        declares_work "$root/$skillfile" "$work" \
            || printf '%s\t%s does not declare it in its sources: frontmatter\n' "$work" "$skillfile"
    done <<EOF
$(shelf_rows "$data")
EOF
}

# -----------------------------------------------------------------------------
section "the shelf population is fully parsed"

# A FLOOR, in the shape `test-oracle-table-coverage.sh` established, and a
# DERIVED EQUALITY beside it. They catch different things. The floor catches the
# array vanishing entirely — where slots and rows both read zero and agree. The
# equality catches the array being partly unreadable, which the floor cannot see
# and which is how this drift actually arrives.
MIN_CANON_WORKS=5
MIN_DECLARED_WORKS=20

[ -f "$data_ts" ] || fatal "$data_ts is missing; the canon section moved and this suite has not followed it."

canon_slots="$(shelf_slots "$data_ts")"
canon_count="$(shelf_rows "$data_ts" | grep -c . || true)"
declared_count="$(declared_works "$repo_root"/*/SKILL.md | sort -u | grep -c . || true)"

if [ "$canon_count" -lt "$MIN_CANON_WORKS" ]; then
    fatal "read $canon_count spine(s) off the shelf, expected at least $MIN_CANON_WORKS.
       The extractor is broken, not the page — a shelf that reads as empty passes
       every check below vacuously. If the shelf genuinely shrank, lower
       MIN_CANON_WORKS in this file as a deliberate edit."
fi
ok "read $canon_count spine(s) from site/src/lib/data.ts (floor: $MIN_CANON_WORKS)"

if [ "$canon_slots" -ne "$canon_count" ]; then
    fatal "the shelf array holds $canon_slots entries but only $canon_count parsed.
       $((canon_slots - canon_count)) spine(s) are written in a spelling the extractor does not
       recognize — it reads title:/author:/full: with double quotes. An unparsed
       spine is invisible to every check below while the page renders it, which is
       exactly the drift this suite exists to catch. Fix the extractor or the
       spine; do not lower a floor to hide it."
fi
ok "all $canon_slots shelf entries parsed ($canon_slots slots = $canon_count rows)"

if [ "$declared_count" -lt "$MIN_DECLARED_WORKS" ]; then
    fatal "read $declared_count declared work(s) from skill frontmatter, expected at least $MIN_DECLARED_WORKS.
       The extractor is broken, not the repo — an empty declaration set would fail
       every shelf work at once and read as a page defect. If sources were
       genuinely removed, lower MIN_DECLARED_WORKS in this file as a deliberate edit."
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
section "every spine is declared by the skill the page names"

unbacked="$(unbacked_works "$data_ts" "$repo_root")"
while IFS="$(printf '\t')" read -r offender why; do
    [ -n "$offender" ] || continue
    bad "the canon shelves \"$offender\" — $why" \
        "the opened book attributes a sources: block to that file, so the section's own copy — \"each SKILL.md names its sources in frontmatter\" — asserts provenance the named skill cannot produce. Declare the work in the skill the page names, point the page at the skill that declares it, or take the spine off the shelf."
done <<EOF
$unbacked
EOF

if [ -z "$unbacked" ]; then
    ok "all $canon_count spine(s) are declared by the skill their bookDetails entry names"
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

# fixture_shelf <path> <"Full — Author::skill/SKILL.md">... — a data.ts with a
# shelf and a matching bookDetails, plus decoy `full:` strings outside the array.
fixture_shelf() {
    local out="$1" spec work skillfile title author
    shift
    {
        printf 'export interface Book {\n\t/** Full "Title — Author" shown on hover. */\n\tfull: "Decoy Interface Comment — Nobody";\n}\n\n'
        printf 'export const shelf: Book[] = [\n'
        for spec in "$@"; do
            work="${spec%%::*}"
            title="${work%% — *}"
            author="${work##* }"
            printf '\t{ title: "%s", author: "%s", full: "%s", h: "1px", color: "#000", ink: "#fff" },\n' \
                "$title" "$author" "$work"
        done
        printf '];\n\n'
        printf 'export const bookDetails = {\n'
        for spec in "$@"; do
            work="${spec%%::*}"
            skillfile="${spec##*::}"
            title="${work%% — *}"
            author="${work##* }"
            printf '\t"%s-%s": {\n\t\tlesson: "l",\n\t\tfile: "%s",\n\t\tfm: "f",\n\t\texcerpt: "e",\n\t},\n' \
                "$author" "$title" "$skillfile"
        done
        printf '};\n\n'
        printf 'export const other = { full: "Decoy Outside Shelf — Nobody" };\n'
    } > "$out"
}

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

# --- the shelf extractors, against each other ---

fixture_shelf "$fixtures/three.ts" \
    "Known Book — Jane Doe::alpha/SKILL.md" \
    "Second Book — Ada Byron::alpha/SKILL.md" \
    "Gamma Book — Grace Hopper::gamma/SKILL.md"
rows="$(shelf_rows "$fixtures/three.ts" | grep -c . || true)"
slots="$(shelf_slots "$fixtures/three.ts")"
if [ "$rows" -eq 3 ] && [ "$slots" -eq 3 ]; then
    ok "shelf_rows and shelf_slots agree on a clean 3-spine shelf, ignoring full: strings outside the array"
else
    bad "the shelf extractors disagree on a clean fixture (slots=$slots rows=$rows)" \
        "the decoys sit outside the array on purpose; both readings must see exactly 3"
fi

# The single-quote spine: unparseable by shelf_rows, still a slot. This is the
# gap the old MIN_CANON_WORKS floor could not see.
sed 's/full: "Gamma Book — Grace Hopper"/full: '"'"'Gamma Book — Grace Hopper'"'"'/' \
    "$fixtures/three.ts" > "$fixtures/single-quoted.ts"
if grep -q "full: 'Gamma Book" "$fixtures/single-quoted.ts"; then
    rows="$(shelf_rows "$fixtures/single-quoted.ts" | grep -c . || true)"
    slots="$(shelf_slots "$fixtures/single-quoted.ts")"
    if [ "$slots" -eq 3 ] && [ "$rows" -eq 2 ]; then
        ok "a spine the extractor cannot parse still counts as a slot, so the gap is visible"
    else
        bad "an unparseable spine did not produce a slots/rows gap (slots=$slots rows=$rows)" \
            "without this gap a spine written in an unanticipated spelling is invisible while the page renders it"
    fi
else
    bad "the single-quote fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

# THE MULTI-LINE FIXTURE. This is what pins shelf_slots' independence from the
# field regexes. On a reflowed spine no single line carries title:, author: and
# full: together, so an oracle rewritten to key on those names counts wrong here
# — the collapse that previously left the suite at 17 passed / 0 failed while a
# reflowed shelf went unchecked. It also pins the parser against a semantically
# null `prettier --write`, which must not be a failure at all.
cat > "$fixtures/reflowed.ts" <<'REFLOW'
export const shelf: Book[] = [
	{ title: "Known Book", author: "Doe", full: "Known Book — Jane Doe", h: "1px", color: "#000", ink: "#fff" },
	{
		title: "Second Book",
		author: "Byron",
		full: "Second Book — Ada Byron",
		h: "1px",
		color: "#000",
		ink: "#fff",
	},
	{
		title: "Gamma Book",
		author: "Hopper",
		full: "Gamma Book — Grace Hopper",
		h: "1px",
		color: "#000",
		ink: "#fff",
	},
];

export const bookDetails = {
	"Doe-Known Book": { file: "alpha/SKILL.md" },
	"Byron-Second Book": { file: "alpha/SKILL.md" },
	"Hopper-Gamma Book": { file: "gamma/SKILL.md" },
};
REFLOW
rows="$(shelf_rows "$fixtures/reflowed.ts" | grep -c . || true)"
slots="$(shelf_slots "$fixtures/reflowed.ts")"
if [ "$rows" -eq 3 ] && [ "$slots" -eq 3 ]; then
    ok "both shelf readings see all 3 spines when 2 of them are reflowed across lines"
else
    bad "a reflowed spine is misread (slots=$slots rows=$rows, want 3/3)" \
        "a semantically null reformat must not read as a shrunken shelf, and an oracle that keys on field names cannot count a reflowed record"
fi

if [ -z "$(unbacked_works "$fixtures/reflowed.ts" "$fixtures")" ]; then
    ok "reflowed spines still join to their bookDetails entries"
else
    bad "reflowed spines failed the join" "record-based parsing must survive a reformat end to end"
fi

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

# --- the matcher, in every direction ---

fixture_shelf "$fixtures/backed.ts" "Known Book — Jane Doe::alpha/SKILL.md"
if [ -z "$(unbacked_works "$fixtures/backed.ts" "$fixtures")" ]; then
    ok "a spine whose named skill declares the work passes"
else
    bad "the detector flagged a spine that IS backed by the skill the page names" \
        "it now cries wolf on a clean shelf, which is how a real check gets loosened"
fi

# THE PAIRING FIXTURE. alpha declares the work; the page names gamma. The old
# any-skill check went green here, and this is #272's defect one level in.
fixture_shelf "$fixtures/wrong-skill.ts" "Known Book — Jane Doe::gamma/SKILL.md"
if [ -n "$(unbacked_works "$fixtures/wrong-skill.ts" "$fixtures")" ]; then
    ok "a work declared by SOME skill but not the one the page names is flagged"
else
    bad "the detector accepted a declaration from a skill the page does not name" \
        "the opened book attributes the sources: block to one specific file; a sibling skill's declaration does not make that attribution true"
fi

fixture_shelf "$fixtures/unbacked.ts" "Undeclared Book — Someone Else::alpha/SKILL.md"
if [ -n "$(unbacked_works "$fixtures/unbacked.ts" "$fixtures")" ]; then
    ok "a spine with no declaration anywhere is flagged"
else
    bad "the detector missed an undeclared shelf work" \
        "this is exactly issue #272's defect; the check above would report green on it"
fi

fixture_shelf "$fixtures/wrong-author.ts" "Known Book — Other Person::alpha/SKILL.md"
if [ -n "$(unbacked_works "$fixtures/wrong-author.ts" "$fixtures")" ]; then
    ok "a title that matches under a different author is flagged, not accepted"
else
    bad "the detector matched on title alone" \
        "two different books sharing a title would launder each other's provenance"
fi

fixture_shelf "$fixtures/wrong-title.ts" "Different Title — Jane Doe::alpha/SKILL.md"
if [ -n "$(unbacked_works "$fixtures/wrong-title.ts" "$fixtures")" ]; then
    ok "an author who IS declared, shelved under a different title, is flagged"
else
    bad "the detector matched on surname alone" \
        "a declared author's OTHER book would ride in on their name; deleting the title comparison must not leave this suite green"
fi

fixture_shelf "$fixtures/short-author.ts" "Known Book — J. Doe::alpha/SKILL.md"
if [ -z "$(unbacked_works "$fixtures/short-author.ts" "$fixtures")" ]; then
    ok "an author spelled differently but sharing a surname still matches"
else
    bad "the detector rejected a surname-equal author variant" \
        "the two sides spell multi-author works differently on purpose; see the header"
fi

# --- the join itself ---

fixture_shelf "$fixtures/missing-detail.ts" "Known Book — Jane Doe::alpha/SKILL.md"
sed 's/"Doe-Known Book"/"Nobody-Nothing"/' "$fixtures/missing-detail.ts" > "$fixtures/orphan.ts"
if grep -q '"Nobody-Nothing"' "$fixtures/orphan.ts"; then
    if [ -n "$(unbacked_works "$fixtures/orphan.ts" "$fixtures")" ]; then
        ok "a spine with no bookDetails entry is flagged rather than skipped"
    else
        bad "a spine with no bookDetails entry passed silently" \
            "an unjoinable spine must fail loudly; skipping it is how the population quietly shrinks"
    fi
else
    bad "the orphan fixture did not apply" "the self-test cannot report on a mutation that never landed"
fi

fixture_shelf "$fixtures/ghost-file.ts" "Known Book — Jane Doe::nonexistent/SKILL.md"
if [ -n "$(unbacked_works "$fixtures/ghost-file.ts" "$fixtures")" ]; then
    ok "a bookDetails entry naming a file that does not exist is flagged"
else
    bad "the detector accepted a bookDetails file: path that does not resolve" \
        "the opened book links to that path; a dead link cannot back a provenance claim"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
