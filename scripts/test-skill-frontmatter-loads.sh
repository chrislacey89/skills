#!/usr/bin/env bash
# test-skill-frontmatter-loads.sh — every skill's frontmatter loads in Claude
# Code, judged by Claude Code's own validator rather than by a grep.
#
# THE INCIDENT (#575). Commit 803e4b9 rewrote /fix-findings' description to
# quote a menu label inside a string that was already double-quoted. That is
# invalid YAML, and Claude Code loads such a skill "with empty metadata": no
# description in the skill listing, no `sources:`. It sat on prod for six days.
# Every frontmatter check passed it, because every one of them read the file as
# text: the CI job grepped for a `^description:` line, which the broken file has.
#
# WHY THE VALIDATOR AND NOT A YAML PARSER. The loader is the oracle. yq and
# Ruby's Psych both reject `description: Use when: x`, which Claude Code loads,
# so a generic parse would fail a skill that works. `claude plugin validate
# --strict` checks the file against the reader that will load it.
#
# THE LAYOUT. The validator inspects skills only under a directory literally
# named `skills/`, and skips symlinked entries. So every */SKILL.md is copied
# (real copies) into a scratch `skills/<name>/`, and the copied count must
# equal the source count: an empty or half-built scratch tree is a pass that
# validated nothing.
#
# THE PLANTED FAULTS. Each is a copy of a real skill with one edit, and each
# must fail under --strict. The first is the incident itself, and it must also
# pass the old grep, or it would not show what the grep missed. The other two
# are the cases the deleted CI greps used to catch (no frontmatter, no
# description), so their deletion stays justified only while these stay red.
#
# THE PIN. CI installs the version in .claude-code-version. Locally, a missing
# `claude` prints a SKIP line; with `CI` set it fails, so the suite cannot drop
# out of CI without notice. A local `claude` at another version still runs, and
# says so.

set -u
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

if ! command -v claude >/dev/null 2>&1; then
    if [ -n "${CI:-}" ]; then
        printf 'FAIL claude is not on PATH and CI is set, so no skill frontmatter was validated\n'
        exit 1
    fi
    printf 'SKIP claude is not on PATH, so no skill frontmatter was validated (install @anthropic-ai/claude-code@%s)\n' \
        "$(tr -d '[:space:]' < .claude-code-version)"
    exit 0
fi

want="$(tr -d '[:space:]' < .claude-code-version)"
got="$(claude --version 2>/dev/null | awk '{print $1}')"
[ "$got" = "$want" ] || printf 'note: claude %s is on PATH; .claude-code-version pins %s\n' "$got" "$want"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# build <dest>: copy every */SKILL.md to <dest>/skills/<name>/SKILL.md.
build() {
    for f in */SKILL.md; do
        n="${f%/SKILL.md}"
        mkdir -p "$1/skills/$n"
        cp "$f" "$1/skills/$n/SKILL.md"
    done
}
validate() { claude plugin validate --strict "$1" >"$scratch/out" 2>&1; }

printf '\n=== every skill in the repo loads ===\n'
real="$scratch/skill-kit"
build "$real"
src_count="$(find . -mindepth 2 -maxdepth 2 -name SKILL.md -not -path './.*' | wc -l | tr -d ' ')"
copied="$(find "$real/skills" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')"
if [ "$src_count" -gt 0 ] && [ "$copied" = "$src_count" ]; then
    ok "copied all $src_count skills into the scratch skills/ tree"
else
    bad "scratch skills/ tree holds $copied of $src_count skills" "the validator would pass a tree that is missing skills"
fi
if validate "$real"; then
    ok "claude plugin validate --strict passes every skill"
else
    bad "claude plugin validate --strict fails on the repo's skills" "$(grep -E '^Validating skill:|❯ frontmatter|✘' "$scratch/out" | head -20)"
fi

# plant <name> <perl-edit>: a scratch tree whose fix-findings copy has one edit.
plant() {
    dest="$scratch/$1/skill-kit"
    build "$dest"
    perl -0pi -e "$2" "$dest/skills/fix-findings/SKILL.md"
    if cmp -s fix-findings/SKILL.md "$dest/skills/fix-findings/SKILL.md"; then
        bad "fixture $1: the edit changed nothing" "the planted fault is not in the file, so a pass here would prove nothing"
        return 1
    fi
    printf '%s' "$dest"
}

printf '\n=== planted faults fail ===\n'
# The incident: an inner double-quoted phrase inside a double-quoted description.
# shellcheck disable=SC2016  # $1 is perl's capture group, not a shell expansion
if dest="$(plant incident 's/^(description: "[^"\\ ]+) /$1 "quoted phrase" /m')"; then
    if validate "$dest"; then
        bad "an unescaped inner quote in a description passed the validator"
    else
        ok "an unescaped inner quote in a description fails (the #575 incident)"
    fi
    if sed -n '2,/^---$/p' "$dest/skills/fix-findings/SKILL.md" | grep -q '^description:'; then
        ok "…and the old CI grep for ^description: passes that same file"
    else
        bad "the incident fixture no longer has a ^description: line" "it would not show what the grep missed"
    fi
fi
if dest="$(plant no-frontmatter 's/\A---\n//')"; then
    if validate "$dest"; then bad "a skill with no opening --- passed the validator"
    else ok "a skill with no opening --- fails"; fi
fi
if dest="$(plant no-description 's/^description: .*\n//m')"; then
    if validate "$dest"; then bad "a skill with no description passed the validator"
    else ok "a skill with no description fails"; fi
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
