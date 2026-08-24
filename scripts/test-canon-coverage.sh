#!/usr/bin/env bash
# test-canon-coverage.sh — every work the landing page shelves must be declared
# by some skill's `sources:` frontmatter.
#
# THE DRIFT CLASS. The canon section of `site/src/lib/data.ts` renders a shelf of
# books and tells the reader, in its own copy, that "each SKILL.md names its
# sources in frontmatter." That sentence is a claim about a *different* file than
# the one making it — the shelf is hand-maintained prose about the repo's
# frontmatter, and nothing relates the two. A spine can be added, or the skill
# backing a spine can lose its `sources:` block, and the page keeps asserting
# provenance the repo cannot produce. The failure emits no signal: the page
# builds, the spine renders, the book opens.
#
# THE INCIDENT (issue #272, 2026-08-23). The shelf carried *Total TypeScript —
# Matt Pocock* as one of eight spines and pointed it at `/ts-audit`. `/ts-audit`
# declared no `sources:` block at all — its frontmatter held only `name` and
# `description`. Extracting every `sources:` entry across all skills returned
# *Total TypeScript* zero times. Every other spine traced to a real entry; that
# one traced to nothing, and had done so for as long as the page existed.
#
# WHAT IT PINS, both sides extracted from the real files rather than restated:
#   1. Every `full:` string in the `shelf` array of `site/src/lib/data.ts`.
#   2. Every quoted entry under a `sources:` key in any `*/SKILL.md` frontmatter.
#   3. Each shelf work matches a declared work on TITLE, and the declared entry
#      names the shelf author's surname.
#
# WHY TITLE + SURNAME AND NOT STRING EQUALITY. The two sides spell authors
# differently on purpose: the shelf shows "Continuous Delivery — Jez Humble &
# David Farley" while `/pre-merge` and `/research` between them declare both
# "Jez Humble & David Farley" and "Jez Humble, David Farley". Demanding equality
# would fail on a formatting difference and teach the reader to loosen the check.
# The surname test is what keeps title-only matching from accepting a different
# author's book that happens to share a title.
#
# The self-tests at the bottom run the detector against synthetic fixtures in
# both directions — a shelf whose work IS declared must pass, one whose work is
# not must fail — because a detector that has stopped detecting reports the same
# full green as a clean repo.

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

# --- The two populations, each derived from its own file --------------------

# canon_works <data.ts> — one "Title — Author" per spine, read out of the shelf
# array itself. Scoped to the array so a `full:` in a doc comment or in an
# unrelated export cannot inflate the population.
canon_works() {
    awk '
        /^export const shelf/ { inshelf = 1; next }
        inshelf && /^\];/     { inshelf = 0 }
        inshelf && match($0, /full: "[^"]*"/) {
            print substr($0, RSTART + 7, RLENGTH - 8)
        }
    ' "$1"
}

# declared_works <root> — every quoted source string under a `sources:` key in
# any skill's frontmatter. Frontmatter only: prose in a SKILL.md body routinely
# quotes book titles and shows example `sources:` blocks, and harvesting those
# would let the page's claim be backed by a skill merely *talking about* a book.
declared_works() {
    local skill
    for skill in "$1"/*/SKILL.md; do
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

# unbacked_works <data.ts> <root> — the shelf works no declared work supports.
# Empty output is the passing state.
unbacked_works() {
    local declared work title surname candidate matched
    declared="$(declared_works "$2")"
    while IFS= read -r work; do
        [ -n "$work" ] || continue
        title="${work%% — *}"
        surname="${work##* }"
        matched=0
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            [ "${candidate%% — *}" = "$title" ] || continue
            if [[ "$candidate" == *"$surname"* ]]; then
                matched=1
                break
            fi
        done <<EOF
$declared
EOF
        [ "$matched" -eq 1 ] || printf '%s\n' "$work"
    done <<EOF
$(canon_works "$1")
EOF
}

# -----------------------------------------------------------------------------
section "both populations are actually populated"

# FLOORS, in the shape `test-oracle-table-coverage.sh` established. A parse that
# returns nothing satisfies "no unbacked work" vacuously and prints full green,
# so an extractor regression is indistinguishable from a clean repo. Lowering
# either constant is possible and is deliberately a visible edit to a named
# number rather than a silent condition.
MIN_CANON_WORKS=5
MIN_DECLARED_WORKS=20

[ -f "$data_ts" ] || fatal "$data_ts is missing; the canon section moved and this suite has not followed it."

canon_count="$(canon_works "$data_ts" | grep -c . || true)"
declared_count="$(declared_works "$repo_root" | sort -u | grep -c . || true)"

if [ "$canon_count" -lt "$MIN_CANON_WORKS" ]; then
    fatal "read $canon_count work(s) off the shelf, expected at least $MIN_CANON_WORKS.
       The extractor is broken, not the page — a shelf that reads as empty passes
       the check below vacuously. If the shelf genuinely shrank, lower
       MIN_CANON_WORKS in this file as a deliberate edit."
fi
ok "read $canon_count shelf work(s) from site/src/lib/data.ts (floor: $MIN_CANON_WORKS)"

if [ "$declared_count" -lt "$MIN_DECLARED_WORKS" ]; then
    fatal "read $declared_count declared work(s) from skill frontmatter, expected at least $MIN_DECLARED_WORKS.
       The extractor is broken, not the repo — an empty declaration set would fail
       every shelf work at once and read as a page defect. If sources were
       genuinely removed, lower MIN_DECLARED_WORKS in this file as a deliberate edit."
fi
ok "read $declared_count distinct declared work(s) from */SKILL.md frontmatter (floor: $MIN_DECLARED_WORKS)"

# -----------------------------------------------------------------------------
section "every shelved work is declared by some skill"

unbacked="$(unbacked_works "$data_ts" "$repo_root")"
while IFS= read -r offender; do
    [ -n "$offender" ] || continue
    bad "the canon shelves \"$offender\"" \
        "no skill's sources: frontmatter declares it, so the section's own copy — \"each SKILL.md names its sources in frontmatter\" — asserts provenance the repo cannot produce. Declare the work in the skill that operationalizes it, or take the spine off the shelf."
done <<EOF
$unbacked
EOF

if [ -z "$unbacked" ]; then
    ok "all $canon_count shelved work(s) trace to a sources: entry"
fi

# -----------------------------------------------------------------------------
section "the detector still detects (self-test)"

# VALIDATE THE INSTRUMENT, NOT ONLY THE SUBJECT
# (docs/solutions/testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md).
# The section above passes when the shelf is clean AND when either extractor has
# silently stopped returning anything the other can disagree with. The floors
# catch total failure; these fixtures catch the subtler regressions — a matcher
# that accepts everything, or one that rejects everything.
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

mkdir -p "$fixtures/alpha" "$fixtures/beta"

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

# fixture_shelf <path> <full-string>... — a data.ts whose shelf holds exactly
# the given works, plus a decoy `full:` outside the array.
fixture_shelf() {
    local out="$1"
    shift
    {
        printf 'export interface Book {\n\t/** Full "Title — Author" shown on hover. */\n\tfull: "Decoy Interface Comment — Nobody";\n}\n\n'
        printf 'export const shelf: Book[] = [\n'
        local work
        for work in "$@"; do
            printf '\t{ title: "T", author: "A", full: "%s", h: "1px", color: "#000", ink: "#fff" },\n' "$work"
        done
        printf '];\n\n'
        printf 'export const other = { full: "Decoy Outside Shelf — Nobody" };\n'
    } > "$out"
}

# --- the frontmatter extractor ---

extracted="$(declared_works "$fixtures" | sort | tr '\n' '|')"
if [ "$extracted" = "Known Book — Jane Doe|Second Book — Ada Byron|" ]; then
    ok "declared_works reads every sources: entry from frontmatter and nothing else"
else
    bad "declared_works returned an unexpected set" "got: $extracted"
fi

if printf '%s\n' "$(declared_works "$fixtures")" | grep -q 'Body Only Book'; then
    bad "declared_works harvested a sources: block from a SKILL.md body" \
        "prose that merely shows or discusses a sources: block must not back a shelf claim"
else
    ok "a sources: block in a SKILL.md body is not treated as a declaration"
fi

# --- the shelf extractor ---

fixture_shelf "$fixtures/three.ts" "Known Book — Jane Doe" "Second Book — Ada Byron" "Third Book — Grace Hopper"
shelf_read="$(canon_works "$fixtures/three.ts" | grep -c . || true)"
if [ "$shelf_read" -eq 3 ]; then
    ok "canon_works reads exactly the shelf array, ignoring full: strings outside it"
else
    bad "canon_works read $shelf_read work(s) from a 3-spine fixture" \
        "it is picking up or dropping full: strings; the decoys sit outside the array on purpose"
fi

# --- the matcher, in both directions ---

fixture_shelf "$fixtures/backed.ts" "Known Book — Jane Doe"
if [ -z "$(unbacked_works "$fixtures/backed.ts" "$fixtures")" ]; then
    ok "a shelf work with a matching declaration passes"
else
    bad "the detector flagged a shelf work that IS declared" \
        "it now cries wolf on a clean shelf, which is how a real check gets loosened"
fi

fixture_shelf "$fixtures/unbacked.ts" "Undeclared Book — Someone Else"
if [ "$(unbacked_works "$fixtures/unbacked.ts" "$fixtures")" = "Undeclared Book — Someone Else" ]; then
    ok "a shelf work with no declaration anywhere is flagged"
else
    bad "the detector missed an undeclared shelf work" \
        "this is exactly issue #272's defect; the check above would report green on it"
fi

fixture_shelf "$fixtures/wrong-author.ts" "Known Book — Other Person"
if [ "$(unbacked_works "$fixtures/wrong-author.ts" "$fixtures")" = "Known Book — Other Person" ]; then
    ok "a title that matches under a different author is flagged, not accepted"
else
    bad "the detector matched on title alone" \
        "two different books sharing a title would launder each other's provenance"
fi

fixture_shelf "$fixtures/wrong-title.ts" "Different Title — Jane Doe"
if [ "$(unbacked_works "$fixtures/wrong-title.ts" "$fixtures")" = "Different Title — Jane Doe" ]; then
    ok "an author who IS declared, shelved under a different title, is flagged"
else
    bad "the detector matched on surname alone" \
        "a declared author's OTHER book would ride in on their name; deleting the title comparison must not leave this suite green"
fi

fixture_shelf "$fixtures/short-author.ts" "Known Book — J. Doe"
if [ -z "$(unbacked_works "$fixtures/short-author.ts" "$fixtures")" ]; then
    ok "an author spelled differently but sharing a surname still matches"
else
    bad "the detector rejected a surname-equal author variant" \
        "the two sides spell multi-author works differently on purpose; see the header"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
