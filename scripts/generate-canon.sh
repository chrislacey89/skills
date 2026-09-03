#!/usr/bin/env bash
# generate-canon.sh — derive the landing page's canon from the `sources:`
# frontmatter of every SKILL.md, so adding a source to a skill is the only
# action needed to put the work on the page.
#
# THE DRIFT CLASS (issue #273). The canon section was fed by a hand-written
# array in `site/src/lib/data.ts`. Nothing related that array to the `sources:`
# blocks it claimed to represent, so the two drifted in both directions and in
# silence: the shelf asserted a work no skill declared (#272), and 34 declared
# works never reached the page at all. Every skill added, re-sourced, or removed
# re-opened the gap, and the page built clean either way. This repo already
# treats a router that lies as worse than no router, and the canon section is a
# router pointing at provenance.
#
# WHAT IT EMITS. One entry per distinct declared work, carrying the exact string
# the frontmatter declares, its parsed title and author, a `type`, and every
# skill that cites it with the tier it cites it under. Nothing is hand-listed:
# the population, the citation counts, and the types are all read off the files.
#
# WHY A COMMITTED GENERATED FILE AND NOT A BUILD-TIME READ. The canon has to be
# importable from `Shelf.astro`'s CLIENT script, which cannot touch the
# filesystem, and the repo's checks are shell suites that must run without
# installing the site's node_modules. A committed module satisfies both, at the
# cost of being able to go stale — which is precisely what
# `scripts/test-canon-coverage.sh` exists to make impossible: it runs this
# script with --check on every push and in CI.
#
# ALIASES ARE NOT COLLAPSED HERE, AND THAT IS DELIBERATE. Grouping is by the
# whole declared string. Two spellings of one author would therefore split one
# work into two entries — so the repo forbids them at the source instead, and
# `test-canon-coverage.sh`'s "one work, one spelling" section fails when a
# second spelling appears. An alias table inside this script would be a second
# hand-maintained canon list, which is the defect #273 exists to remove.

set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: generate-canon.sh [--check] [--root DIR] [--out FILE]

  --check      write nothing; exit 1 if the file on disk differs from what
               this script would emit. Used by scripts/test-canon-coverage.sh.
  --root DIR   read */SKILL.md under DIR (default: the repo root)
  --out FILE   write here (default: <root>/site/src/lib/canon.generated.ts)
USAGE
    exit 2
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$repo_root"
out=""
check=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) check=1; shift ;;
        --root)  [ "$#" -ge 2 ] || usage; root="$2"; shift 2 ;;
        --out)   [ "$#" -ge 2 ] || usage; out="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done
[ -n "$out" ] || out="$root/site/src/lib/canon.generated.ts"

# citations <root> — one "<full>\t<skill>\t<tier>" row per declaration, in
# skill-directory order.
#
# FRONTMATTER ONLY, AND TERMINATED AT THE FIRST NON-INDENTED LINE. Both bounds
# are load-bearing and both are pinned by fixtures in test-canon-coverage.sh. A
# SKILL.md body routinely quotes book titles and shows example `sources:`
# blocks; harvesting those would shelve a work a skill merely talks about.
# Dropping the terminator is worse — every quoted string in the rest of the
# frontmatter becomes a declaration, so a `description:` could put a book on the
# page.
citations() {
    local skill_md name
    for skill_md in "$1"/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        name="$(basename "$(dirname "$skill_md")")"
        awk -v skill="$name" '
            /^---[[:space:]]*$/       { fm++; next }
            fm != 1                   { next }
            /^sources:[[:space:]]*$/  { ins = 1; tier = ""; inp = 0; next }
            ins && /^[^[:space:]]/    { ins = 0 }
            !ins                      { next }
            /^[[:space:]]+primary:[[:space:]]*$/   { tier = "primary";   inp = 0; next }
            /^[[:space:]]+secondary:[[:space:]]*$/ { tier = "secondary"; inp = 0; next }
            # `papers:` is a type marker, not a tier. Its entries name a work
            # already declared under a tier, so emitting them here would give
            # that work a duplicate citation edge and overstate its citation
            # count — the number #274 renders as spine height. Verified: before
            # this guard, Rigby carried two identical walk-commits edges and the
            # repo total read 99 instead of 98.
            /^[[:space:]]+papers:[[:space:]]*$/    { inp = 1; next }
            inp                       { next }
            match($0, /"[^"]+"/) {
                printf "%s\t%s\t%s\n", substr($0, RSTART + 1, RLENGTH - 2), skill,
                       (tier == "" ? "primary" : tier)
            }
        ' "$skill_md"
    done
}

# declared_papers <root> — every work a skill declares under a `papers:` sub-key
# of its `sources:` block.
#
# WHY THIS EXISTS. The type rule below reads the author field's own citation
# convention, which covers a paper cited the way papers are normally cited and
# nothing else. Review found the gap with a live instance: `/walk-commits`
# declares "Peer Review on Open-Source Software Projects — Peter C. Rigby", a
# research paper by a single author with no venue or year in the string. There
# is no truthful tell to read, so the rule typed it `book` and the page labeled
# a paper "From the book".
#
# This is the frontmatter affordance the first draft of this comment named as
# the escape hatch, built because the escape turned out to be needed. The skill
# that cites a work is the thing that knows what the work is, so the declaration
# lives there rather than in a table beside the extractor.
# `scripts/test-canon-coverage.sh` requires every `papers:` entry to also be
# declared under a tier, so a marker cannot point at a work nothing cites.
declared_papers() {
    local skill_md
    for skill_md in "$1"/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        awk '
            /^---[[:space:]]*$/       { fm++; next }
            fm != 1                   { next }
            /^sources:[[:space:]]*$/  { ins = 1; inp = 0; next }
            ins && /^[^[:space:]]/    { ins = 0 }
            !ins                      { next }
            /^[[:space:]]+papers:[[:space:]]*$/              { inp = 1; next }
            /^[[:space:]]+primary:[[:space:]]*$/             { inp = 0; next }
            /^[[:space:]]+secondary:[[:space:]]*$/           { inp = 0; next }
            inp && match($0, /"[^"]+"/) { print substr($0, RSTART + 1, RLENGTH - 2) }
        ' "$skill_md"
    done | LC_ALL=C sort -u
}

# render <root> — the whole module on stdout.
#
# THE TYPE RULE, AND THE ONE THING IT CANNOT SEE. #274 renders papers as a
# different object than books, so a wrong type is a visible defect. It is
# derived from the author field's own citation convention rather than from a
# list of titles: an author carrying `et al.` or ending in a parenthesized
# four-digit year is a paper citation, and no book in this repo is spelled
# either way. A list of titles would drift; a rule fails visibly.
#
# But a single-author paper cited without a year carries no tell, and the rule
# cannot be taught to see one without inventing a venue. Those are declared by
# the citing skill under `papers:`. The two inputs are OR-ed: a tell OR a
# declaration types a work `paper`.
# ONE TAGGED STREAM, NOT TWO awk INPUTS. The obvious spelling is
# `awk 'FNR==NR{...}' <(declared_papers) <(citations)`, and it is wrong here in a
# way that is silent: when the first file is EMPTY — which it is until some skill
# declares a `papers:` entry — awk never reads a record from it, so `FNR == NR`
# is true for every record of the SECOND file and the entire citation stream is
# swallowed as paper declarations. Caught by the type count dropping to zero on
# the first run. Tagging the rows has no such edge.
render() {
    {
        declared_papers "$1"                                          | awk 'NF { print "P\t" $0 }'
        citations "$1" | LC_ALL=C sort -t"$(printf '\t')" -k1,1 -k2,2 | awk 'NF { print "C\t" $0 }'
    } | awk '
        function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
        BEGIN { FS = "\t" }
        $1 == "P" { declared_paper[$2] = 1; next }
        {
            full = $2
            if (!(full in seen)) { seen[full] = 1; order[++n] = full }
            cites[full] = cites[full] sprintf("\t\t\t{ skill: \"%s\", tier: \"%s\" },\n", esc($3), esc($4))
        }
        END {
            print  "// GENERATED FILE — DO NOT EDIT BY HAND."
            print  "//"
            print  "// Produced by `bash scripts/generate-canon.sh` from the `sources:` frontmatter of"
            print  "// every SKILL.md in this repo. To change what the landing page shelves, change a"
            print  "// skill'"'"'s `sources:` block and re-run that script — editing this file instead puts"
            print  "// the page back to asserting provenance nothing in the repo produces, which is the"
            print  "// drift issue #273 closed."
            print  "//"
            print  "// `scripts/test-canon-coverage.sh` re-runs the generator and fails when this file"
            print  "// disagrees with the frontmatter, so a stale copy cannot reach prod."
            print  ""
            print  "export interface CanonCitation {"
            print  "\t/** Skill directory name; its SKILL.md is at `${skill}/SKILL.md`. */"
            print  "\tskill: string;"
            print  "\t/** The `sources:` sub-key the skill declared this work under. */"
            print  "\ttier: \"primary\" | \"secondary\";"
            print  "}"
            print  ""
            print  "export interface CanonWork {"
            print  "\t/** The declared string, verbatim: \"Title — Author\". */"
            print  "\tfull: string;"
            print  "\ttitle: string;"
            print  "\tauthor: string;"
            print  "\t/** Papers cite with `et al.` or a parenthesized year; books do not. */"
            print  "\ttype: \"book\" | \"paper\";"
            print  "\t/** Every skill that declares this work, in skill-directory order. */"
            print  "\tcitations: CanonCitation[];"
            print  "}"
            print  ""
            print  "/** Sorted by title, so the data carries no presentation opinion. */"
            print  "export const canon: CanonWork[] = ["
            for (i = 1; i <= n; i++) {
                full = order[i]
                if (match(full, / — /)) {
                    title  = substr(full, 1, RSTART - 1)
                    author = substr(full, RSTART + RLENGTH)
                } else {
                    title = full; author = ""
                }
                type = (author ~ /et al\./ \
                        || author ~ /\([^)]*[0-9][0-9][0-9][0-9]\)$/ \
                        || (full in declared_paper)) ? "paper" : "book"
                printf "\t{\n"
                printf "\t\tfull: \"%s\",\n", esc(full)
                printf "\t\ttitle: \"%s\",\n", esc(title)
                printf "\t\tauthor: \"%s\",\n", esc(author)
                printf "\t\ttype: \"%s\",\n", type
                printf "\t\tcitations: [\n%s\t\t],\n", cites[full]
                printf "\t},\n"
            }
            print  "];"
        }
    '
}

rendered="$(render "$root")"

if [ "$check" -eq 1 ]; then
    if [ ! -f "$out" ]; then
        # shellcheck disable=SC2016  # the backticks are prose, not a substitution
        printf 'generate-canon: %s does not exist; run `bash scripts/generate-canon.sh`\n' "$out" >&2
        exit 1
    fi
    if ! printf '%s\n' "$rendered" | diff -u "$out" - > /dev/null; then
        printf 'generate-canon: %s is stale.\n' "$out" >&2
        printf '%s\n' "$rendered" | diff -u "$out" - >&2 || true
        # shellcheck disable=SC2016  # the backticks are prose, not a substitution
        printf '\nRun `bash scripts/generate-canon.sh` and commit the result.\n' >&2
        exit 1
    fi
    exit 0
fi

printf '%s\n' "$rendered" > "$out"
printf 'generate-canon: wrote %s\n' "$out"
