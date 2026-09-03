#!/usr/bin/env bash
# test-markdown-diff-attribute.sh — contract test for the two claims CLAUDE.md
# § "Reading a prose diff" makes about `*.md diff=markdown`.
#
# THE DRIFT CLASS. CLAUDE.md § "Commands a skill documents" rule (a) says not to
# paraphrase a third-party tool's behavior from memory, and rule (b) says to pin
# any checkable claim about tool behavior with an executable contract. This file
# is rule (b) applied to a git attribute, and the reason it exists is that the
# claim was already wrong once in this repo.
#
# THE INCIDENT. Issue #295's Recommended Changes table proposed `.gitattributes`
# with the rationale: "Gives git a markdown-aware word regex so `--word-diff`
# splits on prose tokens, not whitespace runs." That is false. Git's built-in
# `markdown` userdiff driver supplies an xfuncname and no wordRegex; running
# `--word-diff` with and without the attribute produces byte-identical output.
# The proposal survived an Advocate, a Skeptic, and a Mediator who verified
# three other claims by hand — nobody ran this one. It was caught only by
# running it during implementation, which is #243's lesson restated: careful
# reading is not the mechanism.
#
# WHAT IT PINS, both measured against the installed git in a scratch repo rather
# than restated here:
#   1. POSITIVE — with `*.md diff=markdown`, a hunk header carries the enclosing
#      markdown heading. This is the real benefit, and the reason the attribute
#      is in the tree at all.
#   2. NEGATIVE — `--word-diff` output is identical with and without the
#      attribute. This is the claim CLAUDE.md now states explicitly, and the one
#      a future reader is most likely to "correct" back into the falsehood.
#   3. The repo's own `.gitattributes` actually carries the line, and CLAUDE.md
#      actually states the negative. Either one going missing makes the other
#      two assertions true but pointless.
#
# A failure here is not necessarily a defect in this repo: a future git could
# add a wordRegex to the markdown driver. That is precisely what this suite is
# for — the prose would then need updating, and nothing else would say so.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# -----------------------------------------------------------------------------
section "the repo states both halves of the claim"

[ -f .gitattributes ] || fatal ".gitattributes not found — the attribute this suite describes is not in the tree."

if grep -qE '^\*\.md[[:space:]]+diff=markdown[[:space:]]*$' .gitattributes; then
    ok ".gitattributes selects the markdown driver for *.md"
else
    bad ".gitattributes does not carry '*.md diff=markdown'" \
        "the assertions below would still pass against a scratch repo while describing a setting this repo does not have"
fi

# Pinned as a phrase, not a sentence: the wording is free to change, the claim
# is not. Without this, deleting the negative from CLAUDE.md leaves the suite
# green while the documentation stops saying the thing it guards.
# shellcheck disable=SC2016  # literal markdown backticks, no expansion intended
# Matched with the emphasis optional. Pinning the literal `**` made a pure
# formatting edit — same claim, no bold — turn this red, which is a suite
# forbidding a legitimate change rather than guarding a real one.
if grep -qE -- 'supplies \*{0,2}no\*{0,2} `wordRegex`' CLAUDE.md; then
    ok "CLAUDE.md states the negative explicitly"
else
    bad "CLAUDE.md no longer states that the driver supplies no wordRegex" \
        "that negative is the half a reader gets backwards; #295's proposal did"
fi

# -----------------------------------------------------------------------------
section "measured against the installed git ($(git --version))"

# A scratch repo, so nothing here depends on this repo's history or config.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The `-c` flags neutralize inherited global config that would otherwise make
# this commit fail on someone else's machine: a signing requirement, or a
# core.hooksPath pointing at hooks that reject the commit. An earlier draft
# named both in its comment and passed only commit.gpgsign.
(
    cd "$scratch"
    git init -q .
    git config user.email contract@test
    git config user.name contract
    printf '# Doc\n\n## Pre-merge\n\nA paragraph about review that is long and unremarkable.\n' > a.md
    git add -A
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm base
    printf '# Doc\n\n## Pre-merge\n\nA paragraph about review that is long and notable.\n' > a.md
)

# Check the RESULT, not the subshell's exit status. `set -e` is suppressed inside
# the left operand of `||`, so the earlier `( … ) || fatal` form could not fire:
# the subshell ran past a failed commit and exited 0. Reproduced under a global
# core.hooksPath whose pre-commit exits 1 — the commit failed, the guard stayed
# silent, and the suite passed only because `git diff` fell back to
# index-vs-worktree and happened to produce the same answer.
git -C "$scratch" rev-parse --verify HEAD >/dev/null 2>&1 \
    || fatal "could not build the scratch repo — no commit exists in $scratch, so every diff below would be measuring an unborn branch."

# `-c core.attributesFile=/dev/null` on the BASELINE reads. Without it, a user
# who liked this change enough to set `*.md diff=markdown` machine-wide — which
# the --global alias in CLAUDE.md invites — gets that attribute applied to the
# "without" measurement too, both sides come back identical, and claim 1 reports
# "diff=markdown changed nothing about the hunk header" while printing a hunk
# header that plainly carries the heading. The earlier draft isolated the commit
# from inherited config and left the measurement exposed.
git_baseline() { git -C "$scratch" -c core.attributesFile=/dev/null "$@"; }

header_without="$(git_baseline diff -U1 -- a.md | grep '^@@' | head -1 || true)"
# Content lines only. The hunk header legitimately DOES change — that is claim 1
# — so leaving it in makes this comparison test claim 1 twice and claim 2 never.
# The first draft did exactly that and reported a wordRegex that does not exist.
wd_body()          { git -C "$scratch" diff --word-diff -- a.md | grep -vE '^(diff |index |--- |\+\+\+ |@@)'; }
wd_body_baseline() { git_baseline      diff --word-diff -- a.md | grep -vE '^(diff |index |--- |\+\+\+ |@@)'; }

wd_without="$(wd_body_baseline)"

printf '*.md diff=markdown\n' > "$scratch/.gitattributes"

header_with="$(git -C "$scratch" diff -U1 -- a.md | grep '^@@' | head -1 || true)"
wd_with="$(wd_body)"

# Non-vacuity: every comparison below is between two strings pulled from git. If
# git printed nothing, "identical" and "differs" both become meaningless.
# Written as `if [ -z … ] || [ -z … ]` rather than `[ -n … ] && [ -n … ] || fatal`.
# The && || form is SC2015, which local shellcheck 0.11.0 accepts and the pinned
# CI 0.9.0 rejects — the version gap .shellcheck-version exists to flag, met in
# the same change that documented it.
if [ -z "$header_without" ] || [ -z "$header_with" ]; then
    fatal "git produced no hunk header — the scratch diff is empty, so every comparison below would compare nothing to nothing."
fi
if [ -z "$wd_without" ] || [ -z "$wd_with" ]; then
    fatal "git produced no --word-diff output — same vacuity."
fi
case "$wd_without" in
    *'[-'*'-]'*) : ;;
    *) fatal "the scratch --word-diff carries no [-old-] run, so it is not exercising word-diff at all: $wd_without" ;;
esac

# Claim 1 (positive): the attribute puts the enclosing heading on the hunk header.
if [ "$header_with" = "$header_without" ]; then
    bad "diff=markdown changed nothing about the hunk header" \
        "expected the enclosing '## Pre-merge' heading; got: $header_with"
elif grep -qF -- '## Pre-merge' <<<"$header_with"; then
    ok "diff=markdown puts the enclosing heading on the hunk header: $header_with"
else
    bad "diff=markdown changed the hunk header but not to the enclosing heading" \
        "got: $header_with"
fi

# Claim 2 (negative): the attribute does not change --word-diff splitting.
if [ "$wd_with" = "$wd_without" ]; then
    ok "--word-diff output is identical with and without the attribute"
else
    bad "diff=markdown DID change --word-diff output on this git" \
        "CLAUDE.md § 'Reading a prose diff' says it supplies no wordRegex; this git disagrees, so the prose needs updating"
fi

# -----------------------------------------------------------------------------
printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
