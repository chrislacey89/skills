#!/usr/bin/env bash
# test-canon-coverage.sh — every book the landing page shelves must be declared
# by the very skill the page says declares it.
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
#
# WHY TITLE + SURNAME AND NOT STRING EQUALITY. The two sides spell authors
# differently on purpose: the shelf shows "Continuous Delivery — Jez Humble &
# David Farley", `/pre-merge` declares it that way, and `/closeout` declares the
# same work as "Jez Humble, David Farley". Demanding equality would fail on a
# formatting difference and teach the reader to loosen the check. The surname
# test is what keeps title-only matching from accepting a different author's
# book that happens to share a title.
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
# WHAT IT DELIBERATELY DOES NOT PIN. `bookDetails[key].fm` and `.excerpt` are
# hand-copied prose about the named file, and nothing here checks their content:
# an `fm:` naming books that exist nowhere in the repo passes this suite. That is
# issue #273's subject — the shelf is hand-maintained and drifts from frontmatter
# — and it is a deferral, not an oversight. Say so here rather than let the
# opening paragraph read as if the whole rendered attribution is now covered:
# what IS pinned is the `file:` path and the work-to-declaration pairing, which
# is the claim #272 reported.
#
# The self-tests at the bottom run every extractor and both matchers against
# synthetic fixtures in both directions, because a detector that has stopped
# detecting reports the same full green as a clean repo.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data_ts="$repo_root/site/src/lib/data.ts"

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
