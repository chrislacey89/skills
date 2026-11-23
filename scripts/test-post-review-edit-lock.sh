#!/usr/bin/env bash
# test-post-review-edit-lock.sh — contract test for the post-review edit lock:
# the second clause of `.claude/hooks/enforce-classification.sh` and the five
# runnable blocks, spread across five skills, that drive it.
#
# THE DRIFT CLASS. #327 built a lock out of one hook clause and four commands
# that live in four different files. `/pre-merge` Phase 4 touches the stamp
# flag; `/fix-findings`' harness line touches the fixer flag and its Step 3
# removes it; `/closeout` Step 3 removes the stamp flag at merge; and the hook —
# documented in `/init-pipeline`, installed into somebody else's repo — is the
# only thing that reads either. Nothing pinned any of it: `rg -l review-stamped
# scripts/` and `rg -l "enforce-classification|IMPL_PATTERNS" scripts/` both
# returned empty, so no suite had ever run the hook body at all.
#
# The two failure directions are not symmetric, which is why prose was the wrong
# medium for it. A lock that refuses too much is loud — somebody hits it within
# a minute and says so. A lock that never engages is silent: a flag written to a
# path the hook does not read, or a condition that can no longer be true, looks
# from the outside exactly like a branch nobody edited after review. That is the
# state the mechanism exists to make impossible, reported as success.
#
# CLAUDE.md § "Commands a skill documents" rule (b) is the standing response —
# a checkable claim about tool behavior is routed to a mechanism, not to careful
# reading. #243 is the incident behind that rule: six successive drafts of one
# passage each shipped a wrong claim, every wrong draft was caught by a human or
# a review sub-agent, and none by a check.
#
# SO THIS SUITE RUNS THE THING. It extracts the hook body and all five commands
# verbatim from the skills that document them and executes them against real
# files in a scratch project. It types no flag path of its own: the flag paths
# are read out of `/pre-merge`'s `touch` and `/fix-findings`' harness line, and
# section 5 drives the whole lifecycle — classified, cleared, stamped, opened,
# shut, released — using only text the skills supply. A rename in one file that
# the other four do not mirror fails here, rather than in a downstream repo at
# merge time.
#
# THE CLASSIFICATION CONTEXT IS PART OF THE SUBJECT, not scenery. The first
# version of this suite set `.tdd-active` in every lock fixture and drove the
# round trip without `/execute` Step 6's removal — so it never once observed the
# state the lock actually operates in, which is a STAMPED and MARKERLESS branch.
# In that state a strictly ordered pair of clauses never reaches the second one:
# the `/fix-findings` fixer is refused despite holding the flag written for it,
# and the human is refused by a message naming `/tdd` that never names the route
# the lock exists to offer. Every assertion was green. Section 3 now drives both
# contexts, section 5 runs Step 6's removal in sequence, and section 9's second
# control rebuilds that exact hook and requires both halves to come back.
#
# NOT COVERED, stated so nobody over-trusts it. Whether Claude Code actually
# invokes the hook on Write/Edit, and whether the harness sets
# `$CLAUDE_PROJECT_DIR` at all, are properties of the harness and not of any
# text in this repo — no suite here can reach them. Section 6 covers only the
# fallback the skills themselves wrote for that variable's absence. And the
# hook is documented prose, not an installed file: this proves the block a
# downstream agent copies is correct, not that any given project copied it.
#
# WHAT SECTION 11 ADDS TO THAT LIMIT, because the limit had nothing behind it.
# Sections 1-10 all assume the current hook is installed. In every project that
# ran /init-pipeline before #327 it is not, and /execute Step 0's gate was
# existence-only — the file is there, /init-pipeline is never re-invoked, and
# the shipped lock is inert in exactly the silent direction named above. Section
# 11 runs Step 0's gate against three installs (none, pre-lock, current) and
# requires it to separate them. It still cannot prove a downstream project runs
# the gate; it does prove the gate can tell the two installs apart, which is the
# half that lives in this repo's text.
#
# AND WHAT SECTION 11 DECLARES, because a gate named for currency does not have
# it. The gate's matcher is one literal, the lock's own flag path, so it knows
# exactly one version boundary: the term is absent on every pre-lock install and
# present on every install from the lock onward, forever. A hook change made
# AFTER that boundary — clause ordering, a message, a new skip pattern — leaves
# the term in place, so the gate reports the same verdict for it as for a hook
# that is genuinely current, and the change is never distributed. That is root
# cause #2 of
# docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md:
# zero hits is the mechanism's healthy state, so its silence carries no signal.
# /execute Step 0's third verdict is named for the term it found rather than
# for currency and states this limit in prose. See "WHAT THIS SUITE
# DELIBERATELY DOES NOT PIN" below for what used to self-test that limit here
# and no longer does.
#
# -----------------------------------------------------------------------------
#
# WHAT THIS SUITE DELIBERATELY DOES NOT PIN, AND WHY THE GAP IS HONEST.
#
# Everything below executes something: it runs the hook body, drives the five
# documented commands, or runs /execute Step 0's gate against a real install.
# An earlier revision also carried four sections asserting what a PARAGRAPH
# MEANS -- that Path C skips the sections that ask a human, that no loose
# IMPL_PATTERNS instruction sits in section 2, that every site states both
# halves of the auto-invoke condition, that Path C's surgery span starts where
# it says. Fourteen independent breaker passes ran one corpus-drawn mutation
# each against this branch. All fourteen returned `survived`, and four of them
# did it by restoring the exact defect the fix had removed:
#
#   "skip section 4"            -> "run section 4 in full"      127 passed, 0 failed
#   loose paragraph above paths -> same paragraph below them    127 passed, 0 failed
#   surgery start anchor        -> a different real comment     127 passed, 0 failed
#   "predates the lock"         -> "already carries the lock"   127 passed, 0 failed
#
# The cause is structural, not carelessness. A grep over prose decides whether
# a TERM is present. The properties above are about what the sentence SAYS of
# that term, and "skip" and "run in full" contain the same term. So the check
# passed for a reason unrelated to its own label -- which is the class
# scripts/test-guards-can-fire.sh exists for, and which this repo treats as
# worse than no check, because the label is what a future reader trusts.
#
# So those sections were deleted rather than patched. The prose they guarded is
# correct as written; it is guarded by review, not by this file. That absence is
# declared here so a later reader does not mistake silence for coverage.
#
# ALSO DELETED, AND NOT A PROSE-MEANING CHECK: four properties that executed or
# compared values by string identity -- the same standard the kept material
# meets -- removed anyway because they lived in the same sections as the
# prose-meaning checks above:
#
#   - section 11's required non-match, which ran /execute Step 0's gate against
#     a fourth installed hook (the post-lock control) and compared the verdict
#     token it returned;
#   - section 11's sha256 digest of the shipped hook body;
#   - section 12's counts of marker-check clauses over the pre-lock and shipped
#     hook bodies;
#   - section 14c's string-absence check of "once per project" against
#     /init-pipeline's frontmatter.
#
# 8f260dc's commit message said "Kept: everything that executes" -- that
# overstated. These four executed or compared by identity, the line the rest
# of this file draws to justify what it keeps, and were removed with the rest.
#
# The line worth keeping: pin a claim here when the subject can be EXECUTED or
# compared by STRING IDENTITY. Do not pin one whose subject is what a sentence
# means.
#
# -----------------------------------------------------------------------------

set -euo pipefail

# A caller that reached this suite via a git hook (pre-push, run from a
# worktree) has GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE set in its environment.
# The scratch-repo `git init` below would inherit them and re-initialize the
# real repository instead, writing `core.bare=true` into its shared config.
# Unset before any git call.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# `stamp release` writes and removes flags under $CLAUDE_PROJECT_DIR. A run
# started from a Claude Code session inherits that session's project, so every
# case here names its own fixture and none may inherit one.
unset CLAUDE_PROJECT_DIR

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       expected: %q\n       got:      %q\n' "$label" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

command -v jq >/dev/null || fatal "jq is not installed — the hook body parses its stdin with it, so this suite cannot run the subject"

# --- One reader, used by every extraction and by the apparatus check ----------
#
# Emits the one ```bash fenced block in <file> whose body matches <regex>;
# exits 1 when there is none, and exits 2 with a line on stderr, emitting
# nothing, when more than one matches (#387): an anchor that also matches a
# later-added block must fail here, not four assertions away. It does not call fatal: a helper that aborts from
# inside a command substitution exits only the subshell (test-guards-can-fire.sh
# detector C), so the caller in the main shell decides what an empty capture
# means.
fenced_bash_block() {  # $1 = file, $2 = ERE matched against the block body
    awk -v re="$2" -v file="$1" '
        /^```bash$/        { buf = ""; inblock = 1; next }
        inblock && /^```$/ { if (buf ~ re) { found++; if (found == 1) hit = buf }
                             inblock = 0; next }
        inblock            { buf = buf $0 "\n" }
        END                { if (found > 1) { printf "fenced_bash_block: %d fenced bash blocks in %s match /%s/; narrow the anchor\n", found, file, re > "/dev/stderr"; exit 2 }
                             if (found == 1) { printf "%s", hit; exit 0 }
                             exit 1 }
    ' "$1"
}

# The reader's own contract (#387): an anchor that matches two blocks is a bet
# lost, and the first-match reader used to pick the earlier one in silence. It
# must refuse loudly, with a status distinct from "no block matches", so the
# failure is named at the point of selection. Planted files, not the skills.
reader_probe="$(mktemp -d)"
# shellcheck disable=SC2016  # the backticks are markdown fences being planted, not command substitution
printf '```bash\necho one anchor\n```\n\ntext\n\n```bash\necho another anchor\n```\n' > "$reader_probe/two.md"
# shellcheck disable=SC2016  # as above
printf '```bash\necho one anchor\n```\n\n```bash\necho other\n```\n' > "$reader_probe/one.md"
probe_rc=0; probe_out="$(fenced_bash_block "$reader_probe/two.md" 'anchor' 2>"$reader_probe/err")" || probe_rc=$?
reader_two="$probe_rc|$probe_out"
reader_two_err="$(cat "$reader_probe/err")"
probe_rc=0; probe_out="$(fenced_bash_block "$reader_probe/one.md" 'anchor' 2>"$reader_probe/err")" || probe_rc=$?
reader_one="$probe_rc|$probe_out"
probe_rc=0; probe_out="$(fenced_bash_block "$reader_probe/one.md" 'nowhere' 2>"$reader_probe/err")" || probe_rc=$?
reader_none="$probe_rc|$probe_out|$(cat "$reader_probe/err")"
rm -rf "$reader_probe"

# --- Pull the subject out of the skills that document it ---------------------

# The hook body /init-pipeline tells a downstream agent to write to
# .claude/hooks/enforce-classification.sh.
# The same reader for the ```json fence, used below to read the hook's own
# registration — which tool calls the harness presents it with — out of the
# settings block /init-pipeline tells a downstream agent to write.
fenced_json_block() {  # $1 = file, $2 = ERE matched against the block body
    awk -v re="$2" '
        /^```json$/        { buf = ""; inblock = 1; next }
        inblock && /^```$/ { if (buf ~ re) { printf "%s", buf; found = 1; exit }
                             inblock = 0; next }
        inblock            { buf = buf $0 "\n" }
        END                { exit(found ? 0 : 1) }
    ' "$1"
}

hook_body="$(fenced_bash_block init-pipeline/SKILL.md 'IMPL_PATTERNS' || true)"
[ -n "$hook_body" ] || fatal "no IMPL_PATTERNS hook body found in init-pipeline/SKILL.md — either the hook moved or its fence changed; update this suite with it"

# The stamp flag's writer (/pre-merge Phase 4) and remover (/closeout Step 3).
# Both sit at the tail of a larger fenced block, so the slice is anchored on the
# PROJECT_DIR assignment that opens them rather than on their content.
# Phase 4 has two writers since #521, one per stamp backend; this is the PR-body
# one, picked by its `gh pr edit`. The sidecar one is section 7b's.
stamp_block="$(fenced_bash_block pre-merge/SKILL.md 'gh pr edit.*review-stamped' || true)"
[ -n "$stamp_block" ] || fatal "no stamp block found in pre-merge/SKILL.md"
# Anchored on the call, not the words: the PR-body block's comments say "the
# stamp write succeeded" too, and the reader refuses an anchor two blocks match.
sidecar_stamp_block="$(fenced_bash_block pre-merge/SKILL.md 'SC" stamp write.*review-stamped' || true)"
[ -n "$sidecar_stamp_block" ] || fatal "no sidecar stamp block found in pre-merge/SKILL.md"
# Both take the reviewed SHA Phase 3 printed as a filled-in literal (#292).
# fill_reviewed <block> <sha> — the block with that placeholder filled.
reviewed_placeholder='REVIEWED_SHA="<the full SHA Phase 3 printed>"'
for blk in "$stamp_block" "$sidecar_stamp_block"; do
    [[ "$blk" == *"$reviewed_placeholder"* ]] || fatal "a Phase 4 stamp block has no $reviewed_placeholder line"
done
fill_reviewed() { printf '%s' "${1//"$reviewed_placeholder"/REVIEWED_SHA=\"$2\"}"; }

stamp_write="$(sed -n '/^PROJECT_DIR=/,$p' <<<"$stamp_block")"
[ -n "$stamp_write" ] || fatal "no PROJECT_DIR-anchored stamp-flag write found in pre-merge/SKILL.md"

# Through the flag's rm only: the sidecar stamp clear after it asks `backend`,
# which aborts outside a fixture that builds a sidecar root, and is run by
# test-review-currency-marker.sh instead.
stamp_remove="$(fenced_bash_block closeout/SKILL.md 'review-stamped' | sed -n '/^PROJECT_DIR=/,/^rm -f .*review-stamped"$/p' || true)"
[ -n "$stamp_remove" ] || fatal "no PROJECT_DIR-anchored stamp-flag removal found in closeout/SKILL.md"

# The fixer flag's writer is /fix-findings' harness line — `!`…`` at the top of
# the file, not a fenced block — and its remover is Step 3's fenced rm.
# shellcheck disable=SC2016  # the `$` and backticks are markdown/sed literals being matched, not shell expansions
fixer_write="$(sed -n 's/^!`\(.*\)`$/\1/p' fix-findings/SKILL.md || true)"
[ -n "$fixer_write" ] || fatal "no harness line found in fix-findings/SKILL.md"

fixer_remove="$(fenced_bash_block fix-findings/SKILL.md 'fix-findings-active' || true)"
[ -n "$fixer_remove" ] || fatal "no fixer-flag removal found in fix-findings/SKILL.md"

# /fix-findings Step 2's throwaway copy for the breaker.
archive_block="$(fenced_bash_block fix-findings/SKILL.md 'git archive' || true)"
[ -n "$archive_block" ] || fatal "no git archive block found in fix-findings/SKILL.md"

# /execute Step 6's removal of both classification markers. This is the
# lifecycle step that makes the post-review state MARKERLESS, and leaving it out
# of section 5 is what let the two clauses' ordering defect ship green: the round
# trip stamped a branch that still carried .tdd-active, a state /execute has
# already destroyed by the time /pre-merge runs.
#
# Anchored on the `rm -f` and not on the marker name alone: Step 0's staleness
# gate names every marker too, in an earlier fenced block, and a bare
# `tdd-active` anchor selects THAT one — silently running the gate here instead
# of the removal, which leaves every marker in place and fails four rows below
# with no hint that the extractor picked the wrong block. The sibling suite
# scripts/test-lfg-marker.sh anchors the same block the same way.
tdd_marker_remove="$(fenced_bash_block execute/SKILL.md 'rm -f.*tdd-active' || true)"
[ -n "$tdd_marker_remove" ] || fatal "no classification-marker removal found in execute/SKILL.md Step 6"

# --- The flag paths, read out of the writers rather than typed here ----------

# Each flag is written with a redirect (#811), so its path is the target of the
# last `> "…"` on the writing line.
stamp_arg="$(sed -n 's|.*> "\([^"]*\)".*|\1|p' <<<"$stamp_write")"
stamp_rel="${stamp_arg#*/}"                      # strip the $PROJECT_DIR/ prefix
# `if [ -z … ] || [ -z … ]` rather than `[ -n … ] && [ … ] || fatal`: the second
# form is SC2015, which local shellcheck 0.11.0 accepts and the pinned CI 0.9.0
# rejects. test-markdown-diff-attribute.sh:132 states the same house idiom for
# the same reason.
if [ -z "$stamp_rel" ] || [ "$stamp_rel" = "$stamp_arg" ]; then
    fatal "could not read a project-relative stamp-flag path out of /pre-merge's flag write"
fi

fixer_arg="$(sed -n 's|.*> "\([^"]*\)".*|\1|p' <<<"$fixer_write")"
fixer_rel="${fixer_arg#*/}"                      # strip the $PROJECT_DIR/ prefix
if [ -z "$fixer_rel" ] || [ "$fixer_rel" = "$fixer_arg" ]; then
    fatal "could not read a project-relative fixer-flag path out of /fix-findings' harness line"
fi

# The fixer flag's THIRD site: the path Step 3's removal aims at. Read, not
# typed, for the same reason the other two are — the flag had three different
# path resolutions when this suite first went green, and nothing compared them.
# shellcheck disable=SC2016  # `$PROJECT_DIR` is the literal text being searched for in the extracted block, not an expansion
fixer_remove_rel="$(grep -o '\$PROJECT_DIR/[^" ]*' <<<"$fixer_remove" | sed 's|^\$PROJECT_DIR/||' | sort -u || true)"

# Every "$CLAUDE_PROJECT_DIR/…" path the hook tests, project-relative.
# shellcheck disable=SC2016  # `$CLAUDE_PROJECT_DIR` is the literal text being searched for in the hook, not an expansion
hook_paths="$(grep -o '\$CLAUDE_PROJECT_DIR/[^"]*' <<<"$hook_body" | sed 's|^\$CLAUDE_PROJECT_DIR/||' | sort -u || true)"
[ -n "$hook_paths" ] || fatal "the extracted hook body tests no \$CLAUDE_PROJECT_DIR paths at all"

printf 'hook body:      %s lines from init-pipeline/SKILL.md\n' "$(grep -c '' <<<"$hook_body")"
printf 'stamp flag:     %s   (written by /pre-merge, removed by /closeout)\n' "$stamp_rel"
printf 'fixer flag:     %s   (written and removed by /fix-findings)\n' "$fixer_rel"

# The classification gate's own markers: whatever the hook tests that is not one
# of the lock's two flags. Derived so that renaming a marker does not require
# editing this suite, and counted so that a derivation returning the wrong set
# is loud rather than quietly reducing the fixture to nothing.
tdd_flags="$(grep -vxF "$stamp_rel" <<<"$hook_paths" | grep -vxF "$fixer_rel" || true)"

# The same set as an array, so every fixture below scales with the hook instead
# of with a hand-maintained list of names. `some_marker` is one arbitrary member,
# for the fixtures that need a single representative classification marker rather
# than the whole set; WHICH member it is carries no meaning, because the hook
# treats them interchangeably and section 2 is what measures that. It is named
# for its role rather than for a marker because a name bound by sort position is
# a name a new marker can silently reassign.
markers=()
while read -r marker; do
    if [ -n "$marker" ]; then markers+=("$marker"); fi
done <<<"$tdd_flags"
[ "${#markers[@]}" -gt 0 ] || fatal "the hook tests no classification markers at all — the derivation above no longer matches its terms"
some_marker="${markers[0]}"

printf 'markers:        %s(created in /execute Step 3, removed in Step 6)\n' "$(printf '%s ' "${markers[@]}")"

# --- Scratch project the hook and the four commands act on -------------------

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
proj="$scratch/project"
mkdir -p "$proj/.claude"

hook_file="$scratch/enforce-classification.sh"
printf '%s' "$hook_body" > "$hook_file"

hook_status=0
hook_err=""
# Feed the hook the PreToolUse payload shape it reads with jq, and capture the
# refusal it writes to stderr. $hook_file is a variable because section 9 points
# it at a mutant and re-runs these same assertions through this same reader.
run_hook() {  # $1 = the file path the harness would present
    hook_status=0
    hook_err="$(printf '{"tool_input":{"file_path":"%s"}}' "$1" \
        | CLAUDE_PROJECT_DIR="$proj" bash "$hook_file" 2>&1 >/dev/null)" || hook_status=$?
}

set_flags() {  # each argument is a project-relative flag path to create
    find "$proj/.claude" -mindepth 1 -delete
    local flag
    for flag in "$@"; do
        mkdir -p "$proj/$(dirname "$flag")"
        touch "$proj/$flag"
    done
}

# The one runner for all four documented commands. An empty $3 means "run with
# CLAUDE_PROJECT_DIR unset", which is the case the skills' `${CLAUDE_PROJECT_DIR
# :-$(git rev-parse --show-toplevel)}` fallback was written for.
run_documented() {  # $1 = directory, $2 = command text, $3 = CLAUDE_PROJECT_DIR
    if [ -n "$3" ]; then
        ( cd "$1" && CLAUDE_PROJECT_DIR="$3" bash -c "$2" ) >/dev/null
    else
        ( cd "$1" && env -u CLAUDE_PROJECT_DIR bash -c "$2" ) >/dev/null
    fi
}

# -----------------------------------------------------------------------------


section "0. the block reader refuses an anchor that matches more than one block (#387)"
assert_eq "2|" "$reader_two" "two blocks match the anchor: exit 2, and no block is emitted"
case "$reader_two_err" in
    *"2 fenced bash blocks"*"anchor"*) assert_eq ok ok "…and stderr names the count and the anchor" ;;
    *) assert_eq "2 fenced bash blocks ... anchor" "$reader_two_err" "…and stderr names the count and the anchor" ;;
esac
assert_eq "0|echo one anchor" "$reader_one" "one block matches: it is emitted, exit 0"
assert_eq "1||" "$reader_none" "no block matches: exit 1, silent, as before"

section "1. the hook is a runnable script, and the five files agree on two paths"

status=0
bash -n "$hook_file" || status=$?
assert_eq 0 "$status" "the hook body /init-pipeline documents parses as bash"

assert_eq 4 "$(grep -c '' <<<"$tdd_flags")" \
    "the hook tests exactly four classification markers besides the lock's two flags"

if grep -qxF "$stamp_rel" <<<"$hook_paths"; then
    assert_eq "$stamp_rel" "$stamp_rel" "the hook reads the same stamp-flag path /pre-merge writes"
else
    assert_eq "$stamp_rel" "(absent from the hook)" "the hook reads the same stamp-flag path /pre-merge writes"
fi

if grep -qxF "$fixer_rel" <<<"$hook_paths"; then
    assert_eq "$fixer_rel" "$fixer_rel" "the hook reads the same fixer-flag path /fix-findings writes"
else
    assert_eq "$fixer_rel" "(absent from the hook)" "the hook reads the same fixer-flag path /fix-findings writes"
fi

# Three sites, one path. The harness line's `touch`, the hook's `-f` test, and
# Step 3's `rm` each resolve the fixer flag independently, and the first version
# of this lock had them resolving to three different files: a cwd-relative
# create, a `$CLAUDE_PROJECT_DIR` read, and an unguarded `$CLAUDE_PROJECT_DIR`
# removal. Either end of that spread is a silent failure — the flag lands where
# the hook does not look and the lock refuses its own fixer, or the removal
# misses and the lock stands open with nothing to say so.
assert_eq "$fixer_rel" "$fixer_remove_rel" \
    "/fix-findings' Step 3 removal aims at the same fixer-flag path its harness line writes"

# -----------------------------------------------------------------------------

section "2. the classification gate still fires (clause 1)"

# Nothing executed this clause before this suite existed either. It is pinned
# here so the lock's arrival on the same trigger surface cannot break it
# silently — the two clauses share IMPL_PATTERNS and the skip logic by design.

set_flags
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "an unclassified implementation write is refused"

for marker in "${markers[@]}"; do
    set_flags "$marker"
    run_hook "src/service.ts"
    assert_eq 0 "$hook_status" "a write under $marker is allowed"
done

# -----------------------------------------------------------------------------

section "3. the lock's truth table (clause 2), in both classification contexts"

# Driven TWICE, because the classification context is not incidental to it.
#
# Every row here used to run with a classification marker present, and that
# state cannot occur: /execute Step 6 removes both classification markers before it hands off
# to /pre-merge, so a stamped branch is always markerless. Under a strictly
# ordered pair of clauses that is the whole defect — clause 1 short-circuits, the
# /fix-findings fixer is refused despite holding the flag written for it, and the
# human is refused by a message that names /tdd and never names /fix-findings.
# Green rows with a marker in place could not see any of it.
#
# So the outcomes below must be IDENTICAL in both contexts. That is the property
# the `.review-stamped` term in clause 1 establishes: on a stamped branch the
# classification clause stands down, and this clause is the sole decider.

# The two refusal messages, read out of the hook rather than typed here, so that
# "which clause refused this" is a measurement and not a guess. Clause 1's echo
# precedes clause 2's in the body.
#
# WHAT THESE TWO CANNOT ANSWER, and the reason the route below is read from
# somewhere else. Both are copies of the strings under test, so matching a
# refusal against them measures only WHICH clause spoke — never WHAT it said.
# Deleting `Either invoke /fix-findings <numbers>, or ` from clause 2's message
# leaves a hook that still refuses, still refuses with clause 2's remaining
# bytes, and no longer names the one route out; every row here stayed green
# through exactly that edit. So the route is derived from /fix-findings' own
# frontmatter name, which is not the text under test and which a rename of the
# skill moves in lockstep with every other inventory surface.
# A reason is a JSON string and may hold an escaped quote, so it ends at the
# first quote that is not escaped.
reasons="$(grep -oE '"reason":"BLOCKED:([^"\\]|\\.)*"' <<<"$hook_body" || true)"
class_msg="$(sed -n 1p <<<"$reasons")"
lock_msg="$(sed -n 2p <<<"$reasons")"
if [ -z "$class_msg" ] || [ -z "$lock_msg" ]; then
    fatal "could not read two BLOCKED reasons out of the hook body"
fi
[ "$class_msg" != "$lock_msg" ] || fatal "the hook's two refusals are byte-identical — 'which clause refused' is unmeasurable"

fixer_route="/$(sed -n 's/^name: *//p' fix-findings/SKILL.md | sed -n 1p)"
if [ "$fixer_route" = "/" ]; then
    fatal "could not read a skill name out of fix-findings/SKILL.md frontmatter"
fi

set_context() {  # $1 = classification marker, or "" for none; rest = extra flags
    local marker="$1"; shift
    if [ -n "$marker" ]; then set_flags "$marker" "$@"; else set_flags "$@"; fi
}

# The lock's second route (#807). The refusal is what a blocked session reads,
# so it is checked as the string it prints: it names the verb, it is still the
# JSON the harness parses, and it no longer offers deleting the flag, which
# left the branch markerless and refused by clause 1.
assert_eq 1 "$(grep -cF 'stamp release' <<<"$lock_msg" || true)" "the lock's refusal names stamp release"
assert_eq 0 "$(grep -ciF 'delete' <<<"$lock_msg" || true)" "the lock's refusal does not tell the reader to delete the stamp flag"
set_flags "$stamp_rel"
run_hook "src/service.ts"
assert_eq block "$(jq -r .decision <<<"$hook_err" 2>/dev/null || echo unparsable)" "the lock's refusal parses as JSON"

for context in "${markers[@]}" ""; do
    if [ -n "$context" ]; then
        where="under $context"
    else
        where="with no classification marker (the state /execute Step 6 leaves)"
    fi

    set_context "$context"
    run_hook "src/service.ts"
    if [ -n "$context" ]; then
        assert_eq 0 "$hook_status" "unstamped, $where: the write lands"
    else
        # Unstamped and unclassified is clause 1's own case, and it must keep
        # refusing — the stand-down is scoped to stamped branches only.
        assert_eq 2 "$hook_status" "unstamped, $where: the classification gate still refuses"
    fi

    set_context "$context" "$stamp_rel"
    run_hook "src/service.ts"
    assert_eq 2 "$hook_status" "stamped, no fixer flag, $where: the write is refused"

    # The label claims two things and both are checked: the LOCK is what
    # refused (matched against $lock_msg), and the refusal names the route the
    # human is supposed to take (matched against $fixer_route, which comes from
    # the skill rather than from the message). Dropping the second term is what
    # made this row vacuous once — see the note beside $lock_msg above.
    if grep -qF "$lock_msg" <<<"$hook_err" && grep -qF "$fixer_route" <<<"$hook_err"; then
        assert_eq "the lock refused it, naming $fixer_route" \
            "the lock refused it, naming $fixer_route" \
            "the refusal routes the human to $fixer_route, $where"
    else
        assert_eq "the lock refused it, naming $fixer_route" "$hook_err" \
            "the refusal routes the human to $fixer_route, $where"
    fi

    if grep -qF "$class_msg" <<<"$hook_err"; then
        assert_eq "not the classification clause" "the classification clause refused it" \
            "clause 1 does not preempt the lock, $where"
    else
        assert_eq "not the classification clause" "not the classification clause" \
            "clause 1 does not preempt the lock, $where"
    fi

    set_context "$context" "$stamp_rel" "$fixer_rel"
    run_hook "src/service.ts"
    assert_eq 0 "$hook_status" "stamped with the fixer flag present, $where: the fixer's write lands"

    set_context "$context" "$fixer_rel"
    run_hook "src/service.ts"
    if [ -n "$context" ]; then
        assert_eq 0 "$hook_status" "fixer flag alone, nothing stamped, $where: the write lands"
    else
        # The fixer flag is not a classification marker and must not act as one
        # off a stamped branch — otherwise a leaked flag opens the TDD gate too.
        assert_eq 2 "$hook_status" "fixer flag alone, nothing stamped, $where: still unclassified, still refused"
    fi
done

# The trigger surface itself, not just the two clauses. Every row above drives
# "src/service.ts" — one extension — so a mutation to /init-pipeline's hook
# body that only changes WHICH files IMPL_PATTERNS or the skip clause reach
# could pass every row above unchanged. The PR body's own hand-run fixture
# table already claims these two REFUSE (stamped, no fix-active); pinned here
# so the file backs the claim instead of a table nobody re-runs.
set_flags "$stamp_rel"
run_hook "src/component.tsx"
assert_eq 2 "$hook_status" "stamped, no fixer flag, markerless: src/component.tsx is refused"

set_flags "$stamp_rel"
run_hook "src/main.py"
assert_eq 2 "$hook_status" "stamped, no fixer flag, markerless: src/main.py is refused"

# -----------------------------------------------------------------------------

section "4. what the lock does not refuse, which is more than the prose used to say"

# Both skills say, in prose, what the lock does NOT refuse. Everything below is
# a measurement of that claim rather than a restatement of it, and the section
# is cited by name from both skills, so the two halves stay attached: what the
# skip logic lets through, what the substring matching lets through that a
# reader of "a test file" would not predict, and which writes the armed lock
# permits outright. #327's review found the prose wrong on the last two.

set_context "" "$stamp_rel"

run_hook "src/service.test.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a test file"

run_hook "src/service.spec.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a spec file"

run_hook "src/types.d.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a type declaration"

run_hook "vite.config.ts"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a config file"

run_hook "README.md"
assert_eq 0 "$hook_status" "a stamped branch does not refuse a file off the pattern list"

# --- The skip patterns match a SUBSTRING OF THE PATH, not a file's role ------
#
# #327's own review found both skills describing this surface in intent
# vocabulary — "a test file", "a type declaration", "a config file" — while the
# matcher does `[[ "$FILE_PATH" == *test* ]]` against whatever path the harness
# hands it, which Claude Code makes ABSOLUTE. A reader of those sentences would
# not predict any of the rows below, and the five assertions above could not
# tell the two readings apart: every fixture in them was a file whose role
# matched its name. These are the same clause, measured where the two readings
# diverge.
run_hook "src/latest-news.ts"
assert_eq 0 "$hook_status" "…nor src/latest-news.ts, whose name contains 'test'"

run_hook "src/respectful.ts"
assert_eq 0 "$hook_status" "…nor src/respectful.ts, whose name contains 'spec'"

run_hook "src/testimonials/Card.tsx"
assert_eq 0 "$hook_status" "…nor a file under a testimonials/ directory"

run_hook "src/app.config.local.ts"
assert_eq 0 "$hook_status" "…nor src/app.config.local.ts, which carries '.config.' mid-name"

# A project checked out under a directory named "tester". The hook only gates
# files inside $CLAUDE_PROJECT_DIR (#578), so the fixture moves the project there
# rather than handing the hook a path outside it.
home_proj="$proj"
proj="$scratch/tester/proj"
mkdir -p "$proj"
cp -R "$home_proj/.claude" "$proj/"
run_hook "$proj/src/app.ts"
assert_eq 0 "$hook_status" "…nor ANY file in a project checked out under a path containing 'test'"
proj="$home_proj"

# The control that makes the row above a measurement of the substring rather
# than of absoluteness: the same absolute shape, without "test" in the path.
run_hook "$proj/src/app.ts"
assert_eq 2 "$hook_status" "…while the same absolute path in a project without 'test' in it is refused"

# --- Only files inside $CLAUDE_PROJECT_DIR are gated (#578) -------------------
#
# Neither clause is about a scratch file or a sibling checkout, and refusing one
# sends the agent to delete .review-stamped for a write that never needed the
# lock. The armed lock is the state these rows run in, so a scope check that
# stopped working shows as a refusal here. The path is resolved before the
# comparison: a `..` or a symlink that lands back inside is still gated, and one
# that leads out is not.
outside="$scratch/elsewhere"
mkdir -p "$outside/src" "$proj/src"
ln -s "$outside" "$proj/linked-out"
ln -s "$proj" "$scratch/linked-in"

run_hook "$outside/src/scratch.ts"
assert_eq 0 "$hook_status" "a write outside the project is not gated, even with the lock armed"

run_hook "$outside/new/dir/scratch.ts"
assert_eq 0 "$hook_status" "…nor one into a directory outside the project that does not exist yet"

run_hook "$proj/../elsewhere/src/scratch.ts"
assert_eq 0 "$hook_status" "…nor a path that starts in the project and leaves it through .."

run_hook "$proj/linked-out/src/scratch.ts"
assert_eq 0 "$hook_status" "…nor a path that leaves the project through a symlink"

run_hook "$outside/../project/src/app.ts"
assert_eq 2 "$hook_status" "a path that starts outside and resolves back inside through .. is gated"

run_hook "$scratch/linked-in/src/app.ts"
assert_eq 2 "$hook_status" "…and so is one that reaches the project through a symlink"

run_hook "$proj/src/not-yet/app.ts"
assert_eq 2 "$hook_status" "…and so is a new file in a project directory that does not exist yet"

rm "$proj/linked-out" "$scratch/linked-in"

# --- Routes past the lock, three of which leave no trace ---------------------
#
# The prose in both skills used to say the lock had "two exits," "both
# deliberate acts." It has more, because it is a PreToolUse hook on Write|Edit
# over an implementation-pattern list, not an enclosure. Each row is a write
# that the armed lock permits; the paths are derived, not typed, so a rename
# that closes one of these routes fails here and the prose gets revisited.
hook_command="$(fenced_json_block init-pipeline/SKILL.md 'enforce-classification' \
    | jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("enforce-classification")) | .hooks[].command')"
[ -n "$hook_command" ] || fatal "no enforce-classification hook registration found in /init-pipeline § 3"

hook_rel="${hook_command#*\"/}"                       # strip the "$CLAUDE_PROJECT_DIR"/ prefix
settings_rel="$(dirname "$(dirname "$hook_rel")")/settings.json"
if [ -z "$hook_rel" ] || [ "$hook_rel" = "$hook_command" ]; then
    fatal "could not read a project-relative hook path out of /init-pipeline's settings block"
fi

run_hook "$fixer_rel"
assert_eq 0 "$hook_status" "the armed lock permits a write to $fixer_rel, which opens it with no sub-agent behind it"

run_hook "$hook_rel"
assert_eq 0 "$hook_status" "…and a write to $hook_rel, so the session can rewrite its own gate"

run_hook "$settings_rel"
assert_eq 0 "$hook_status" "…and a write to $settings_rel, which deregisters the hook"

# The fourth route is not a path at all: the hook is only ever consulted for the
# tool calls its matcher names, so anything done from Bash — `sed -i`, `tee`, a
# heredoc, `printf >`, or `rm` on the stamp flag itself — is never presented to
# it. That is a property of the registration, so the registration is what is
# read.
hook_matcher="$(fenced_json_block init-pipeline/SKILL.md 'enforce-classification' \
    | jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("enforce-classification")) | .matcher')"
assert_eq "Write|Edit" "$hook_matcher" \
    "the hook is registered on Write|Edit only, so no Bash write is presented to it"

# -----------------------------------------------------------------------------

section "5. round trip: the five documented commands drive the hook"

# The load-bearing section. Every state change below is made by running text
# extracted from a skill, and every observation is made by running the hook.
# No flag path appears as a literal anywhere in it, so the five files can only
# stay green by continuing to agree with each other.
#
# /execute Step 6's removal is the fifth command and was the missing one. Without
# it this walk stamped a branch that still carried `.tdd-active` — a state the
# real pipeline destroys one step before /pre-merge runs — and every assertion
# after the stamp was answered by a marker that would not have been there. The
# sequence below is now the sequence the pipeline actually performs.

# Every marker at once, which is the state Step 6's removal has to clear. One
# marker here would only measure the removal line against whichever name the
# fixture happened to pick, and the drift this whole slice exists to close is a
# marker the hook accepts that the removal line has never heard of.
set_flags "${markers[@]}"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "classified, before anything else: open"

run_documented "$proj" "$tdd_marker_remove" "$proj"
leftover=""
for marker in "${markers[@]}"; do
    if [ -e "$proj/$marker" ]; then leftover="$leftover$marker "; fi
done
assert_eq "" "$leftover" "/execute Step 6's rm names every classification marker the hook tests"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /execute Step 6's rm: the branch is markerless, so the classification gate refuses"

run_documented "$proj" "$stamp_write" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /pre-merge Phase 4's touch: shut"

# On a markerless stamped branch, WHICH clause refuses is the whole finding. If
# clause 1 answers here, the lock's designed affordance never prints and the
# fixer below is refused too.
if grep -qF "$lock_msg" <<<"$hook_err"; then
    assert_eq "the lock" "the lock" "…and it is the lock that refuses, not the classification gate"
else
    assert_eq "the lock" "$hook_err" "…and it is the lock that refuses, not the classification gate"
fi

run_documented "$proj" "$fixer_write" "$proj"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "after /fix-findings' harness line: open for the fixer, with no classification marker in reach"

run_documented "$proj" "$fixer_remove" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /fix-findings Step 3's rm: shut again"

run_documented "$proj" "$stamp_remove" "$proj"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "after /closeout Step 3's rm at merge: still refused, because the branch is markerless"

# Released means the LOCK stopped refusing, not that everything is permitted —
# the classification gate is a separate question and answers this one now.
if grep -qF "$class_msg" <<<"$hook_err"; then
    assert_eq "the classification gate" "the classification gate" \
        "…and the lock is released: the refusal is clause 1's, not the lock's"
else
    assert_eq "the classification gate" "$hook_err" \
        "…and the lock is released: the refusal is clause 1's, not the lock's"
fi

touch "$proj/$some_marker"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "…and re-classifying the next slice's work reopens the gate with no stamp left to fight"

# -----------------------------------------------------------------------------

section "6. the \$CLAUDE_PROJECT_DIR fallback both skills wrote"

# /pre-merge's comment states the reason for the `:-` form outright: the
# variable is unset outside a Claude Code session, and an unguarded expansion
# would resolve to "/.claude" — a silent no-write that leaves the lock
# disengaged while everything above reports success. That is a claim about what
# a command does, so it is run rather than read. The run happens from a
# SUBDIRECTORY, because $PWD and `--show-toplevel` only differ there, and the
# difference is the whole reason `--show-toplevel` is in the line.

gitrepo="$scratch/gitrepo"
mkdir -p "$gitrepo/src"
printf 'export const x = 1\n' > "$gitrepo/src/service.ts"
if ! git -C "$gitrepo" init -q; then fatal "could not git init the scratch repo"; fi
if ! git -C "$gitrepo" add -A; then fatal "could not stage the scratch repo"; fi
if ! git -C "$gitrepo" -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
        commit -q --no-verify -m "fixture"; then
    fatal "could not commit in the scratch repo"
fi

status=0
run_documented "$gitrepo/src" "$stamp_write" "" || status=$?
assert_eq 0 "$status" "/pre-merge's write runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$stamp_rel" ]; then
    assert_eq "at the repo root" "at the repo root" "the fallback lands the flag where the hook would look, not beside \$PWD"
else
    assert_eq "at the repo root" "not written" "the fallback lands the flag where the hook would look, not beside \$PWD"
fi

status=0
run_documented "$gitrepo/src" "$stamp_remove" "" || status=$?
assert_eq 0 "$status" "/closeout's removal runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$stamp_rel" ]; then
    assert_eq "gone" "still present" "/closeout's removal reaches the same path /pre-merge's write created"
else
    assert_eq "gone" "gone" "/closeout's removal reaches the same path /pre-merge's write created"
fi

# The fixer flag runs the same gauntlet, and it is the one that failed it. Its
# harness line used to be cwd-relative (`mkdir -p .claude && touch
# .claude/.fix-findings-active`), so run from a subdirectory it wrote a flag the
# hook — which only ever looks under $CLAUDE_PROJECT_DIR — could not see. Every
# assertion in sections 3 and 5 stayed green, because both run with the variable
# set and the cwd already at the project root. Only the fallback case, from a
# subdirectory, can tell the two resolutions apart.

status=0
run_documented "$gitrepo/src" "$fixer_write" "" || status=$?
assert_eq 0 "$status" "/fix-findings' harness line runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$fixer_rel" ]; then
    assert_eq "at the repo root" "at the repo root" "the harness line lands the fixer flag where the hook would look, not beside \$PWD"
else
    assert_eq "at the repo root" "not written there" "the harness line lands the fixer flag where the hook would look, not beside \$PWD"
fi

status=0
remove_out="$( cd "$gitrepo/src" && env -u CLAUDE_PROJECT_DIR bash -c "$fixer_remove" 2>&1 >/dev/null )" || status=$?
assert_eq 0 "$status" "/fix-findings' Step 3 removal runs with CLAUDE_PROJECT_DIR unset"

if [ -f "$gitrepo/$fixer_rel" ]; then
    assert_eq "gone" "still present" "/fix-findings' removal reaches the same path its harness line created"
else
    assert_eq "gone" "gone" "/fix-findings' removal reaches the same path its harness line created"
fi

assert_eq "" "$remove_out" "…and says nothing on stderr when the flag was really there"

# A miss must be sayable. `rm -f` reports success on a removal that removed
# nothing, which reads identically to a removal that worked — and the state it
# hides is the open lock, the silent direction this whole mechanism exists to
# close. Run the same removal a second time, with the flag already gone.
status=0
miss_out="$( cd "$gitrepo/src" && env -u CLAUDE_PROJECT_DIR bash -c "$fixer_remove" 2>&1 >/dev/null )" || status=$?

if [ -n "$miss_out" ] && grep -qF "$fixer_rel" <<<"$miss_out"; then
    assert_eq "reported" "reported" "removing a fixer flag that is not there reports the miss, naming the path it looked at"
else
    assert_eq "reported" "silent (exit $status, stderr: ${miss_out:-empty})" \
        "removing a fixer flag that is not there reports the miss, naming the path it looked at"
fi

# -----------------------------------------------------------------------------

section "7. the stamp flag is written only if the PR body write succeeded"

# The comment beside /pre-merge's touch says the flag is written only after the
# stamp write succeeded, because "a flag written beside a stamp that aborted
# would lock the branch on the strength of a review nothing recorded." That
# sentence was half true. The READ half was guarded — `if ! gh pr view … ; then
# … exit 1; fi` — and the write half was a bare `gh pr edit` whose exit status
# nothing looked at, so a failing edit left no stamp in the PR body and a
# .review-stamped flag on disk. From outside, a branch locked by that flag is
# indistinguishable from one locked by a review that actually happened.
#
# So the block is RUN, whole and extracted verbatim, against a `gh` stub — once
# with an edit that fails and once with an edit that succeeds. `gh pr view`
# always answers with a non-empty body, so the read half's two guards pass and
# both runs reach the write half, which is the only half under test here.

stamprepo="$scratch/stamprepo"
mkdir -p "$stamprepo"
if ! git -C "$stamprepo" init -q; then fatal "could not git init the stamp scratch repo"; fi
printf 'export const x = 1\n' > "$stamprepo/service.ts"
if ! git -C "$stamprepo" add -A; then fatal "could not stage the stamp scratch repo"; fi
if ! git -C "$stamprepo" -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
        commit -q --no-verify -m "fixture"; then
    fatal "could not commit in the stamp scratch repo"
fi

ghbin="$scratch/ghbin"
mkdir -p "$ghbin"

stamp_block_status=0
run_stamp_block() {  # $1 = the exit status the stub's `pr edit` reports; $2 = the reviewed SHA filled in (default: HEAD)
    cat > "$ghbin/gh" <<STUB
#!/usr/bin/env bash
case "\$2" in
  view) printf '## Summary\n\nfixture body\n' ;;
  edit) echo edited >> "$ghbin/edits"; exit $1 ;;
  *)    exit 9 ;;
esac
STUB
    chmod +x "$ghbin/gh"
    rm -f "$stamprepo/$stamp_rel"
    stamp_block_status=0
    ( cd "$stamprepo" \
        && PATH="$ghbin:$PATH" CLAUDE_PROJECT_DIR="$stamprepo" \
           bash -c "$(fill_reviewed "${stamp_block//<pr-number>/1}" "${2:-$(git -C "$stamprepo" rev-parse HEAD)}")" ) >/dev/null 2>&1 || stamp_block_status=$?
}

run_stamp_block 1
assert_eq 1 "$stamp_block_status" "a failing \`gh pr edit\` aborts the block instead of running on"

if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "no flag" "flag written" "…and leaves no $stamp_rel behind, so nothing locks the branch on a stamp the PR never received"
else
    assert_eq "no flag" "no flag" "…and leaves no $stamp_rel behind, so nothing locks the branch on a stamp the PR never received"
fi

# The control. "No flag was written" would pass just as well for a block that
# never writes one, or for a run that died before it got there for some unrelated
# reason — so the same block, same fixture, with the edit succeeding, must write
# the flag. Without this run the assertion above measures nothing.
run_stamp_block 0
assert_eq 0 "$stamp_block_status" "a succeeding \`gh pr edit\` runs the block through to the flag"

if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "flag written" "flag written" "…and the flag is written on that path, which is what makes the abort above a measurement"
else
    assert_eq "flag written" "no flag" "…and the flag is written on that path, which is what makes the abort above a measurement"
fi

# #292: the PR-body block takes the reviewed SHA as a filled-in literal. Left
# unfilled, it is not a SHA, and the block stops before it edits the PR body:
# a marker the reader rejects would read as "no stamp" at /closeout.
rm -f "$ghbin/edits"
run_stamp_block 0 "<the full SHA Phase 3 printed>"
assert_eq 1 "$stamp_block_status" "REVIEWED_SHA left unfilled: the PR-body stamp block aborts"
assert_eq "" "$(cat "$ghbin/edits" 2>/dev/null || true)" "…before it edits the PR body"
if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "no flag" "flag written" "…and leaves no $stamp_rel behind"
else
    assert_eq "no flag" "no flag" "…and leaves no $stamp_rel behind"
fi
# An abbreviated SHA of a real commit resolves as a commit but is not the full
# SHA Phase 3 printed: a short marker reads as "no stamp" at /closeout.
rm -f "$ghbin/edits"
run_stamp_block 0 "$(git -C "$stamprepo" rev-parse --short=7 HEAD)"
assert_eq 1 "$stamp_block_status" "REVIEWED_SHA filled with a short SHA of a real commit: the PR-body stamp block aborts"
assert_eq "" "$(cat "$ghbin/edits" 2>/dev/null || true)" "…before it edits the PR body"

# -----------------------------------------------------------------------------

section "7b. on the sidecar backend, the flag is written only if the stamp commit succeeded"

# The same property as section 7, for the writer that commits the stamp to
# <sidecar>/reviews/ instead of the PR body (#521). The block is run verbatim
# with its bundled sidecar.sh pointed at the canonical script: once with no
# sidecar resolving, where `stamp write` refuses, and once with one, where it
# commits. The second run is the control that makes the first a measurement,
# and it also checks the stamp it left reads back as the head.

sidecar_sh="$repo_root/init-pipeline/scripts/sidecar.sh"
sc_root="$scratch/sidecars"
sc_gitconfig="$scratch/sidecar-gitconfig"
git config --file "$sc_gitconfig" user.name "Lock Tester"
git config --file "$sc_gitconfig" user.email "lock@example.invalid"

sidecar_block_status=0
sidecar_stacked_base=""
sidecar_stamp_w=""
sidecar_reviewed=""   # the SHA filled into REVIEWED_SHA; empty means the current HEAD
run_sidecar_stamp_block() {
    rm -f "$stamprepo/$stamp_rel"
    sidecar_block_status=0
    local blk="${sidecar_stamp_block//BASE_BRANCH=\"<sibling slice branch for a stacked PR, else empty>\"/BASE_BRANCH=\"$sidecar_stacked_base\"}"
    blk="$(fill_reviewed "$blk" "${sidecar_reviewed:-$(git -C "$stamprepo" rev-parse HEAD)}")"
    blk="${blk//W=\"W-<n>\"/W=\"$sidecar_stamp_w\"}"
    ( cd "$stamprepo" \
        && GIT_CONFIG_GLOBAL="$sc_gitconfig" SKILL_KIT_SIDECAR_ROOT="$sc_root" \
           SKILL_KIT_RESEARCH_ARCHIVE="$scratch/archive" CLAUDE_PROJECT_DIR="$stamprepo" \
           bash -c "${blk//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}" ) \
        >/dev/null 2>&1 || sidecar_block_status=$?
}

run_sidecar_stamp_block
assert_eq 1 "$sidecar_block_status" "with no sidecar to commit to, the sidecar stamp block aborts"
if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "no flag" "flag written" "…and leaves no $stamp_rel behind"
else
    assert_eq "no flag" "no flag" "…and leaves no $stamp_rel behind"
fi

if ! ( cd "$stamprepo" && GIT_CONFIG_GLOBAL="$sc_gitconfig" SKILL_KIT_SIDECAR_ROOT="$sc_root" \
        SKILL_KIT_RESEARCH_ARCHIVE="$scratch/archive" \
        bash "$sidecar_sh" init --name lock --mode guest --write sidecar --in-tree-path none --no-migrate-archive ) >/dev/null 2>&1; then
    fatal "could not init a sidecar for the stamp scratch repo"
fi
# A declared base no fallback would guess (#605): a block that wrote a literal
# BASE_REF=main instead of asking base-ref would then record the wrong base.
git -C "$stamprepo" branch -f lock-base HEAD >/dev/null 2>&1
( cd "$stamprepo" && GIT_CONFIG_GLOBAL="$sc_gitconfig" SKILL_KIT_SIDECAR_ROOT="$sc_root" \
    bash "$sidecar_sh" config set base_ref lock-base ) >/dev/null 2>&1 \
    || fatal "could not declare base_ref lock-base in the stamp scratch sidecar"
run_sidecar_stamp_block
assert_eq 0 "$sidecar_block_status" "with a sidecar, the sidecar stamp block runs through to the flag"
if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "flag written" "flag written" "…and the flag is written on that path, which makes the abort above a measurement"
else
    assert_eq "flag written" "no flag" "…and the flag is written on that path, which makes the abort above a measurement"
fi
sidecar_read="$(cd "$stamprepo" && SKILL_KIT_SIDECAR_ROOT="$sc_root" bash "$sidecar_sh" stamp read "$(git -C "$stamprepo" branch --show-current)" 2>/dev/null)"
assert_eq "$(git -C "$stamprepo" rev-parse HEAD)" "$sidecar_read" "…and the stamp it committed reads back as the head it reviewed"
# The block runs in its own shell, so it must ask base-ref itself (#597): a stamp that
# records an empty base_ref is the failure this pins.
# #605: equal to what base-ref prints in the same fixture, not merely non-empty.
sidecar_stamp_base="$(jq -r '.base_ref // empty' "$sc_root"/lock/reviews/*.json 2>/dev/null | head -n1 || true)"
sidecar_base_ref="$(cd "$stamprepo" && SKILL_KIT_SIDECAR_ROOT="$sc_root" bash "$sidecar_sh" base-ref 2>/dev/null)" || sidecar_base_ref=""
[ -n "$sidecar_base_ref" ] || fatal "sidecar.sh base-ref printed nothing in the stamp scratch repo"
assert_eq "$sidecar_base_ref" "$sidecar_stamp_base" "…and the stamp records the base_ref sidecar.sh base-ref prints"
rm -f "$stamprepo/$stamp_rel"

# #605: with the placeholder empty and base-ref failing, the block must stop
# before the stamp: a swallowed failure (`|| true`) would write a stamp with an
# empty base and set the flag. base-ref fails for real here: an empty declared
# base_ref is refused.
rm -f "$sc_root"/lock/reviews/*.json
jq '.base_ref = ""' "$sc_root/lock/sidecar.json" > "$scratch/lock-sidecar.json" && mv "$scratch/lock-sidecar.json" "$sc_root/lock/sidecar.json"
if ( cd "$stamprepo" && SKILL_KIT_SIDECAR_ROOT="$sc_root" bash "$sidecar_sh" base-ref ) >/dev/null 2>&1; then
    fatal "fixture precondition: base-ref should fail on an empty declared base_ref"
fi
run_sidecar_stamp_block
assert_eq 1 "$sidecar_block_status" "with base-ref failing, the sidecar stamp block aborts"
assert_eq "" "$(ls "$sc_root"/lock/reviews/*.json 2>/dev/null || true)" "…and writes no reviews/*.json"
if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "no flag" "flag written" "…and leaves no $stamp_rel behind"
else
    assert_eq "no flag" "no flag" "…and leaves no $stamp_rel behind"
fi
git -C "$sc_root/lock" checkout -q -- sidecar.json
rm -f "$stamprepo/$stamp_rel"

# A stacked PR's sibling branch, filled into the placeholder, is what the stamp records (#604).
git -C "$stamprepo" branch -f slice-1-branch HEAD >/dev/null 2>&1
rm -f "$sc_root"/lock/reviews/*.json
sidecar_stacked_base="slice-1-branch"
run_sidecar_stamp_block
sidecar_stacked_recorded="$(jq -r '.base_ref // empty' "$sc_root"/lock/reviews/*.json 2>/dev/null | head -n1 || true)"
assert_eq "slice-1-branch" "$sidecar_stacked_recorded" "a filled stacked base is what the stamp records"
sidecar_stacked_base=""
rm -f "$stamprepo/$stamp_rel"

# With a work item, the block copies the reviewed head onto it. The copy is the
# item's history and gates nothing, so a work item that cannot be written leaves
# the stamp and the flag standing.
stamp_sc() { ( cd "$stamprepo" && GIT_CONFIG_GLOBAL="$sc_gitconfig" SKILL_KIT_SIDECAR_ROOT="$sc_root" bash "$sidecar_sh" "$@" ); }
printf '## Parent PRD\n\nnone\n' > "$scratch/stamp-slice.md"
stamp_w="$(stamp_sc work create --kind slice --body-file "$scratch/stamp-slice.md" 2>/dev/null || true)"
assert_eq "W-1" "$stamp_w" "a work item exists in the stamp scratch sidecar"
sidecar_stamp_w="W-1"
run_sidecar_stamp_block
assert_eq 0 "$sidecar_block_status" "with a work item, the sidecar stamp block exits 0"
assert_eq "$(git -C "$stamprepo" rev-parse HEAD)" "$(stamp_sc work view W-1 --json 2>/dev/null | jq -r '.reviewed_sha // empty')" \
    "…and the work item's reviewed_sha is the head it stamped"
rm -f "$stamprepo/$stamp_rel" "$sc_root"/lock/reviews/*.json
sidecar_stamp_w="W-99"
run_sidecar_stamp_block
assert_eq 0 "$sidecar_block_status" "a work item that does not exist does not fail the sidecar stamp block"
assert_eq "$(git -C "$stamprepo" rev-parse HEAD)" "$(stamp_sc stamp read "$(git -C "$stamprepo" branch --show-current)" 2>/dev/null)" \
    "…and the stamp is still written"
if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "flag written" "flag written" "…and so is the flag"
else
    assert_eq "flag written" "no flag" "…and so is the flag"
fi
sidecar_stamp_w=""
rm -f "$stamprepo/$stamp_rel"

# #292: a commit made after the review is not what the stamp names. The block is
# filled with the SHA Phase 3 printed, then a fix lands on top, then it runs.
rm -f "$sc_root"/lock/reviews/*.json
sidecar_reviewed="$(git -C "$stamprepo" rev-parse HEAD)"
printf 'export const x = 2\n' > "$stamprepo/service.ts"
git -C "$stamprepo" -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
    commit -q --no-verify -am "a fix after the review" || fatal "could not commit a fix after the review"
[ "$sidecar_reviewed" != "$(git -C "$stamprepo" rev-parse HEAD)" ] || fatal "fixture: the fix did not move HEAD"
run_sidecar_stamp_block
assert_eq 0 "$sidecar_block_status" "a fix landed after the review: the sidecar stamp block exits 0"
assert_eq "$sidecar_reviewed" "$(stamp_sc stamp read "$(git -C "$stamprepo" branch --show-current)" 2>/dev/null)" \
    "…and the stamp names the SHA the review read, not the newer HEAD"
rm -f "$stamprepo/$stamp_rel" "$sc_root"/lock/reviews/*.json
# An unfilled placeholder is not a SHA: the block stops before any stamp or flag.
sidecar_reviewed="<the full SHA Phase 3 printed>"
run_sidecar_stamp_block
assert_eq 1 "$sidecar_block_status" "REVIEWED_SHA left unfilled: the sidecar stamp block aborts"
assert_eq "" "$(ls "$sc_root"/lock/reviews/*.json 2>/dev/null || true)" "…and writes no reviews/*.json"
if [ -f "$stamprepo/$stamp_rel" ]; then
    assert_eq "no flag" "flag written" "…and leaves no $stamp_rel behind"
else
    assert_eq "no flag" "no flag" "…and leaves no $stamp_rel behind"
fi
# An abbreviated SHA of a real commit is not the full SHA either.
sidecar_reviewed="$(git -C "$stamprepo" rev-parse --short=7 HEAD)"
run_sidecar_stamp_block
assert_eq 1 "$sidecar_block_status" "REVIEWED_SHA filled with a short SHA of a real commit: the sidecar stamp block aborts"
assert_eq "" "$(ls "$sc_root"/lock/reviews/*.json 2>/dev/null || true)" "…and writes no reviews/*.json"
sidecar_reviewed=""

# -----------------------------------------------------------------------------

section "8. the breaker's copy cannot be committed to, and announces where it is"

# /fix-findings chooses `git archive` over `git worktree add` on the stated
# ground that it writes a plain directory with no .git inside it. Structural is
# a checkable word, and #344 is the incident that says which half of the claim
# it can carry: absent .git makes *committing to the branch* impossible, and
# does nothing about a write that lands in the original working tree by another
# route — a bare relative path, a lost $BREAKER_DIR, a wrong `-C`. In the field
# a breaker's `sed` reached the real repo exactly that way, because $BREAKER_DIR
# was bound in one shell and the breaker mutated from a later one.
#
# So this section measures two different things. The .git assertion below is the
# structural half. The path assertions are the mechanism under the discipline
# half: the block must hand the breaker an ABSOLUTE path and must PRINT it, so
# a breaker in a fresh shell has a literal to cd into rather than a variable
# that did not survive. Neither assertion can see whether the breaker obeys the
# rule — that is prose, and it stays prose; what is pinned is that the block
# still supplies what the rule depends on.

# The block archives the SHA the controller hands it in $FIX_SHA, not HEAD (#341).
# That distinction only exists once the two differ, so give the fixture a second
# commit standing in for a later fix that landed while this breaker was working,
# and archive the FIRST one. A block that went back to `git rev-parse HEAD` would
# extract the later tree and fail the content assertion below — which is why this
# section needs no separate guard against that regression.
fix_sha="$(git -C "$gitrepo" rev-parse HEAD)"
printf 'export const x = 2\n' > "$gitrepo/src/service.ts"
if ! git -C "$gitrepo" -c user.email=t@example.invalid -c user.name=Test -c commit.gpgsign=false \
        commit -aq --no-verify -m "a later fix, landed while the breaker ran"; then
    fatal "could not add a second commit to the scratch repo"
fi
if [ "$fix_sha" = "$(git -C "$gitrepo" rev-parse HEAD)" ]; then
    fatal "the fixture's two commits share a SHA — the HEAD-vs-FIX_SHA distinction is untestable"
fi

# US (0x1f) separates what the block printed from the value it bound, so one run
# yields both. A literal the block never emits is the right separator here: any
# byte the announcement could plausibly contain would split it in the wrong place.
archive_out="$( cd "$gitrepo" && FIX_SHA="$fix_sha" bash -c "$archive_block"$'\n''printf "\037%s" "$BREAKER_DIR"' )"
archive_announced="${archive_out%%$'\037'*}"
breaker_dir="${archive_out##*$'\037'}"

case "$breaker_dir" in
    /*) assert_eq "absolute" "absolute" "the block binds \$BREAKER_DIR to an absolute path" ;;
    *)  assert_eq "absolute" "relative: $breaker_dir" "the block binds \$BREAKER_DIR to an absolute path" ;;
esac

# The announcement is what a breaker in a later shell reads the path off. Assert
# the block prints the very directory it bound — a block that printed some other
# path, or nothing, would leave the breaker with a variable that is empty by the
# time it mutates, which is the #344 failure.
case "$archive_announced" in
    *"$breaker_dir"*) assert_eq "announced" "announced" \
        "the block prints the absolute path it created, so a fresh shell has a literal to cd into" ;;
    *) assert_eq "announced" "silent (printed: ${archive_announced:-nothing})" \
        "the block prints the absolute path it created, so a fresh shell has a literal to cd into" ;;
esac

if [ -f "$breaker_dir/src/service.ts" ]; then
    assert_eq "extracted" "extracted" "the archive block extracts the committed tree"
else
    assert_eq "extracted" "empty" "the archive block extracts the committed tree"
fi

assert_eq "export const x = 1" "$(cat "$breaker_dir/src/service.ts" 2>/dev/null)" \
    "the copy carries the tree at \$FIX_SHA, not the later commit at HEAD"

if [ -e "$breaker_dir/.git" ]; then
    assert_eq "no .git" "a .git is present" "the copy has no .git, so the breaker has no branch to write to"
else
    assert_eq "no .git" "no .git" "the copy has no .git, so the breaker has no branch to write to"
fi

rm -rf "$breaker_dir"

# …and it fails CLOSED. `git archive <unresolvable-rev> | tar -x` prints its
# `fatal:` to stderr and exits 0: without `pipefail` the pipeline reports tar's
# status, and tar succeeded at unpacking nothing. The block then hands the
# breaker an empty directory and a success, and a breaker that ran its mutation
# there could report a verdict on no tree at all — a green result that is green
# for a reason nobody checked, in the one skill whose thesis is that such a
# result is not self-validating.
#
# Since #341 the revision arrives in $FIX_SHA, so the control needs no textual
# mutation of the block at all: hand the SHIPPED text a revision that cannot
# resolve. That is strictly better than the substitution this control used to
# make — there is no edited copy to drift from the subject, and nothing to
# re-point when the block's wording changes.
status=0
bogus_out="$( cd "$gitrepo" && FIX_SHA=deadbeef bash -c "$archive_block"$'\n''printf "%s" "$BREAKER_DIR"' 2>/dev/null )" || status=$?
assert_eq 1 "$status" "an unresolvable revision aborts the extraction rather than reporting success"
assert_eq "" "$bogus_out" "…and no directory path reaches the breaker, so there is no empty tree to run a mutation in"

# The other way to arrive with no revision, which #341 introduced: a controller
# that spawned a breaker and never wired the fixer's SHA through. /fix-findings
# claims the existing guard already covers it — that an unset $FIX_SHA expands to
# the empty string and `git archive ""` rejects it, reaching the same fail-closed
# path as the unresolvable-revision case above. That is a claim about what a
# command does under a condition nobody will reproduce by hand, so it is run
# rather than believed. What the assertion below measures, and no more: the
# unset case aborts with the same status (1) as the unresolvable case, so the
# fail-closed path is reached with nothing wired through for it. It cannot see
# whether a separate check exists in the block — a guard written in the
# block's own `exit 1` idiom would abort with that same status and pass here
# unnoticed.
status=0
# shellcheck disable=SC2016  # `$BREAKER_DIR` must expand in the inner `bash -c`, not here — same
# single-quoting as the two runs above, which shellcheck reads as a nested script only because
# `bash -c` is the first word there and `env -u FIX_SHA` displaces it here.
unset_out="$( cd "$gitrepo" && env -u FIX_SHA bash -c "$archive_block"$'\n''printf "%s" "$BREAKER_DIR"' 2>/dev/null )" || status=$?
assert_eq 1 "$status" "an unset \$FIX_SHA aborts with the same status as an unresolvable revision"
assert_eq "" "$unset_out" "…and likewise reaches the breaker with no directory to run a mutation in"

# -----------------------------------------------------------------------------

section "9. apparatus: the refusal in section 3 measures the clause"

# A green suite proves nothing until a known-killable control has gone red
# through it. Point the lock's condition at a path that cannot exist — by
# substituting the flag's own name, taken from /pre-merge's touch — and the
# stamped write in section 3 must flip from refused to allowed. If it does not,
# every assertion above is passing for some other reason.

mutant="$scratch/mutant-hook.sh"
stamp_basename="${stamp_rel##*/}"
printf '%s' "${hook_body//$stamp_basename/$stamp_basename-absent}" > "$mutant"

status=0
bash -n "$mutant" || status=$?
assert_eq 0 "$status" "the control is still a valid script (a syntax error would fail for the wrong reason)"

set_flags "$some_marker" "$stamp_rel"
if [ -f "$proj/$stamp_rel" ]; then
    assert_eq "stamped" "stamped" "the fixture reaches the state the control is about to be run against"
else
    assert_eq "stamped" "not stamped" "the fixture reaches the state the control is about to be run against"
fi

real_hook="$hook_file"
hook_file="$mutant"
run_hook "src/service.ts"
hook_file="$real_hook"
assert_eq 0 "$hook_status" "with the lock's condition pointed at a path that cannot exist, the same stamped write is allowed"

run_hook "src/service.ts"
assert_eq 2 "$hook_status" "and the unmutated hook refuses it again on the very next run"

# --- Control 2: the shipped defect, rebuilt and re-killed --------------------
#
# The control above proves clause 2's CONDITION is live. It cannot see the defect
# this section was extended for, because that defect was in the clauses' ORDER,
# and order is invisible to any fixture that leaves a classification marker lying
# around. So: strip the `.review-stamped` stand-down term out of clause 1 — built
# from /pre-merge's own flag path, not typed — and the hook becomes the version
# that shipped. Both halves of the finding must come back.

stand_down="[ ! -f \"\$CLAUDE_PROJECT_DIR/$stamp_rel\" ] && "
ordering_mutant="$scratch/ordering-mutant-hook.sh"
printf '%s' "${hook_body/"$stand_down"/}" > "$ordering_mutant"

if [ "$(grep -c '' <"$ordering_mutant")" -lt "$(grep -c '' <<<"$hook_body")" ] \
   || [ "$(wc -c <"$ordering_mutant")" -lt "$(printf '%s' "$hook_body" | wc -c)" ]; then
    assert_eq "removed" "removed" "the stand-down term was found in clause 1 and taken out"
else
    assert_eq "removed" "not found — clause 1 no longer carries the term in this shape" \
        "the stand-down term was found in clause 1 and taken out"
fi

status=0
bash -n "$ordering_mutant" || status=$?
assert_eq 0 "$status" "the ordering control is still a valid script"

real_hook="$hook_file"
hook_file="$ordering_mutant"

set_context "" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
assert_eq 2 "$hook_status" "without the stand-down: the /fix-findings fixer is refused despite holding its flag"

set_context "" "$stamp_rel"
run_hook "src/service.ts"
# Same two halves as section 3's row, in the negative: clause 1 is what answers,
# and the route never appears. The second term is checked for the same reason it
# is checked there — a $class_msg match alone says which clause spoke, not what
# the human was left holding, and "never named" is the half of this label that
# describes the harm.
if grep -qF "$class_msg" <<<"$hook_err" && ! grep -qF "$fixer_route" <<<"$hook_err"; then
    assert_eq "clause 1's message, naming no route" "clause 1's message, naming no route" \
        "without the stand-down: the human is refused by the wrong clause, and $fixer_route is never named"
else
    assert_eq "clause 1's message, naming no route" "$hook_err" \
        "without the stand-down: the human is refused by the wrong clause, and $fixer_route is never named"
fi

hook_file="$real_hook"

set_context "" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
assert_eq 0 "$hook_status" "and the shipped hook lets that same fixer write on the very next run"

# -----------------------------------------------------------------------------

section "10. neither flag can be committed into this repo"

# Both flags are transient by construction, which is the condition under which
# this pack tolerates filesystem state at all. A committed copy would hold the
# lock shut, or hold it open, across every future branch — so this is measured
# with git's own matcher rather than by reading .gitignore.
#
# The repo's .gitignore text is copied into a FRESH scratch repo created with an
# EMPTY template, and git is asked there, so nothing else on the machine can
# answer for a deleted entry: not the real repo's `.git/info/exclude` (#375),
# not a git template directory's `info/exclude`, and, with
# `-c core.excludesFile=/dev/null`, not a global excludes file naming
# `.claude/`. Asking the real repo would pass here while failing on a clean clone.

empty_template="$scratch/empty-template-10"
ignore_probe="$scratch/ignore-probe-10"
mkdir -p "$empty_template" "$ignore_probe"
git init -q --template="$empty_template" "$ignore_probe" || fatal "could not git init a scratch repo for section 10"
cp "$repo_root/.gitignore" "$ignore_probe/.gitignore" || fatal "could not copy .gitignore into the scratch repo"

for flag in "$stamp_rel" "$fixer_rel"; do
    if git -C "$ignore_probe" -c core.excludesFile=/dev/null check-ignore -q -- "$flag"; then
        assert_eq "ignored" "ignored" "$flag is ignored by this repo"
    else
        assert_eq "ignored" "tracked" "$flag is ignored by this repo"
    fi
done

# -----------------------------------------------------------------------------

section "11. /execute Step 0's gate separates a pre-lock install from a current one"

# THE GAP THIS CLOSES. #327 shipped the lock as a hook clause and left /execute
# Step 0's gate existence-only: "if .claude/hooks/enforce-classification.sh does
# not exist, invoke /init-pipeline". In a project that ran /init-pipeline before
# the lock, the file exists, so /init-pipeline is never re-invoked and the hook
# keeps only clause 1. /pre-merge still writes the stamp flag and /fix-findings
# still writes the fixer flag; the pre-lock hook reads neither. The fixer is then
# refused by clause 1 under a message naming /tdd — the defect commit 93f5453
# fixed INSIDE the hook, reproduced verbatim in every repo that does not receive
# the new hook. Nothing above reaches it, because everything above installs the
# current hook by construction.
#
# The fixture is BUILT FROM THE SHIPPED HOOK, not typed: take clause 1's
# stand-down term back out (the surgery section 9's second control performs),
# then delete clause 2's if…fi block and the comment lines that named the two
# flags. What comes out is not required to be byte-identical to the hook on
# prod — it is required to be a hook with no stamp-flag term in it that still
# reproduces the refusal, and both of those are asserted before the gate is
# pointed at it.

hooks_gate="$(fenced_bash_block execute/SKILL.md 'hooks-stale' || true)"
[ -n "$hooks_gate" ] || fatal "no hook-staleness gate found in execute/SKILL.md Step 0 — either the gate moved or its fence changed; update this suite with it"

status=0
bash -n <<<"$hooks_gate" || status=$?
assert_eq 0 "$status" "the gate /execute Step 0 documents parses as bash"

# Two derived paths the gate has to agree with, so a rename in either writer
# fails here rather than turning the gate into a check that can never fire:
# the stamp flag (read out of /pre-merge's touch, above) and the hook script
# (read out of /init-pipeline's own settings registration, in section 4).
# Backslashes are stripped because the gate carries the path as a grep BRE.
gate_plain="${hooks_gate//\\/}"

if grep -qF "$stamp_rel" <<<"$gate_plain"; then
    assert_eq "$stamp_rel" "$stamp_rel" "the gate tests for the same stamp-flag path /pre-merge writes"
else
    assert_eq "$stamp_rel" "(absent from the gate)" "the gate tests for the same stamp-flag path /pre-merge writes"
fi

if grep -qF "$hook_rel" <<<"$gate_plain"; then
    assert_eq "$hook_rel" "$hook_rel" "the gate looks at the same hook path /init-pipeline registers"
else
    assert_eq "$hook_rel" "(absent from the gate)" "the gate looks at the same hook path /init-pipeline registers"
fi

# --- The pre-lock install, rebuilt from the shipped hook ---------------------

prelock_standdown="[ ! -f \"\$CLAUDE_PROJECT_DIR/$stamp_rel\" ] && "
prelock_body="${hook_body/"$prelock_standdown"/}"

if [ "$(printf '%s' "$prelock_body" | wc -c)" -lt "$(printf '%s' "$hook_body" | wc -c)" ]; then
    assert_eq "removed" "removed" "clause 1's stand-down term was found and taken back out"
else
    assert_eq "removed" "not found — clause 1 no longer carries the term in this shape" \
        "clause 1's stand-down term was found and taken back out"
fi

prelock_body="$(awk -v needle="-f \"\$CLAUDE_PROJECT_DIR/$stamp_rel\"" \
                    -v sb="${stamp_rel##*/}" -v fb="${fixer_rel##*/}" '
    index($0, needle)                                   { skip = 1 }
    skip                                                { if ($0 == "fi") skip = 0; next }
    /^[[:space:]]*#/ && (index($0, sb) || index($0, fb)) { next }
                                                        { print }
' <<<"$prelock_body")"

prelock="$scratch/prelock-hook.sh"
printf '%s\n' "$prelock_body" > "$prelock"

assert_eq 0 "$(grep -c -- "${stamp_rel##*/}" "$prelock" || true)" \
    "the rebuilt pre-lock hook mentions the stamp flag nowhere at all"

status=0
bash -n "$prelock" || status=$?
assert_eq 0 "$status" "the rebuilt pre-lock hook is still a valid script"

# The apparatus check for this section: the fixture must actually exhibit the
# finding, or the gate below is being asked to detect nothing. Drive it in the
# state the pipeline reaches — markerless (/execute Step 6 has run), stamped
# (/pre-merge Phase 4), fixer flag held (/fix-findings) — and require the two
# halves back: refused, by clause 1, with the fixer's route never named.
real_hook="$hook_file"
hook_file="$prelock"
set_context "" "$stamp_rel" "$fixer_rel"
run_hook "src/service.ts"
hook_file="$real_hook"

assert_eq 2 "$hook_status" "the pre-lock hook refuses the /fix-findings fixer that holds its own flag"
if grep -qF "$class_msg" <<<"$hook_err" && ! grep -qF "$fixer_route" <<<"$hook_err"; then
    assert_eq "clause 1's message, naming no route" "clause 1's message, naming no route" \
        "…by the classification clause, and $fixer_route is never named — the state every pre-lock project is in"
else
    assert_eq "clause 1's message, naming no route" "$hook_err" \
        "…by the classification clause, and $fixer_route is never named — the state every pre-lock project is in"
fi

# --- The gate, run against all three installs -------------------------------

gate_proj="$scratch/gate-project"
mkdir -p "$gate_proj/$(dirname "$hook_rel")"
git init -q "$gate_proj" >/dev/null 2>&1 || fatal "could not init a scratch git repo for the gate's fallback row"

# Agents run this block in the harness shell, which on macOS is zsh, and zsh
# does not word-split an unquoted expansion (#393: a `for term in $GATE_TERMS`
# loop ran once there and reported every hook stale). So every row runs under
# each shell. A missing zsh skips that arm locally and fails when CI is set.
run_gate() {  # $1 = shell, $2 = CLAUDE_PROJECT_DIR, or "" to exercise the git-toplevel fallback
    if [ -n "$2" ]; then
        ( cd "$gate_proj" && CLAUDE_PROJECT_DIR="$2" "$1" -c "$hooks_gate" )
    else
        ( cd "$gate_proj" && env -u CLAUDE_PROJECT_DIR "$1" -c "$hooks_gate" )
    fi
}

gate_rows() {  # $1 = shell
    rm -f "$gate_proj/$hook_rel"
    assert_eq "hooks-absent" "$(run_gate "$1" "$gate_proj")" \
        "[$1] no hook installed: the gate reports it, and /init-pipeline scaffolds"

    cp "$prelock" "$gate_proj/$hook_rel"
    assert_eq "hooks-stale" "$(run_gate "$1" "$gate_proj")" \
        "[$1] the pre-lock hook installed: the gate fires, and /init-pipeline re-scaffolds"

    cp "$hook_file" "$gate_proj/$hook_rel"
    assert_eq "hooks-lock-present" "$(run_gate "$1" "$gate_proj")" \
        "[$1] the shipped hook installed: the gate stays silent"

    # Same three-way separation with the variable the harness may not set, since the
    # gate wrote the same ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}
    # fallback section 6 measures for /pre-merge and /fix-findings.
    assert_eq "hooks-lock-present" "$(run_gate "$1" "")" \
        "[$1] …and with \$CLAUDE_PROJECT_DIR unset, the gate resolves the project by git toplevel"

    cp "$prelock" "$gate_proj/$hook_rel"
    assert_eq "hooks-stale" "$(run_gate "$1" "")" \
        "[$1] …and still fires on the pre-lock hook through that same fallback"
}

gate_rows bash
if command -v zsh >/dev/null 2>&1; then
    gate_rows zsh
elif [ -n "${CI:-}" ]; then
    assert_eq "zsh on PATH" "zsh absent" "the hooks gate rows ran under zsh (CI is set, so a missing zsh fails)"
else
    printf '  SKIP zsh is not on PATH, so the hooks gate rows ran under bash only\n'
fi

# --- Every verdict the gate emits is a verdict Step 0's prose defines --------
#
# The verdicts are DERIVED from the block rather than listed here, so renaming
# one in the code fence and leaving the paragraph describing the old name fails
# here. This is the routing surface: an agent reads a token out of the gate and
# looks for what to do with it, and a token the prose never mentions routes
# nowhere.

gate_verdicts="$(grep -oE 'echo "[a-z-]+"' <<<"$hooks_gate" | sed -E 's/^echo "(.*)"$/\1/' | sort -u)"
[ "$(grep -c '' <<<"$gate_verdicts")" -ge 3 ] || fatal "read fewer than three verdicts out of Step 0's gate — the gate has three branches, so that extractor no longer matches its echoes"

execute_prose="$(awk '/^```/ { inblock = ! inblock; next } ! inblock' execute/SKILL.md)"

while read -r verdict; do
    [ -n "$verdict" ] || continue
    if grep -qF -- "\`$verdict\`" <<<"$execute_prose"; then
        assert_eq "documented" "documented" "Step 0's prose says what to do with $verdict, which its gate emits"
    else
        assert_eq "documented" "unmentioned" "Step 0's prose says what to do with $verdict, which its gate emits"
    fi
done <<<"$gate_verdicts"

# -----------------------------------------------------------------------------

section "12. release, edit, re-review, re-stamp (#807)"

# The whole route past the lock, on both stamp backends and in both shells an
# agent uses: /pre-merge's stamp block, the hook, `stamp release`, the edit,
# /pre-merge's scope block, the stamp block again. The marker's path is read out
# of what the verb wrote, not typed, so a verb and a hook that disagree about it
# fail here.

scope_step="$(awk '
    /^4\. \*\*Decide the scope/ { step = 1 }
    step && /^   SC=/           { on = 1 }
    on && /^   ```$/            { exit }
    on                          { print substr($0, 4) }
' pre-merge/SKILL.md)"
[ -n "$scope_step" ] || fatal "no scope block found in pre-merge/SKILL.md Phase 1 step 4"

# fill_block <block> — a documented block with the placeholders an agent fills
# on an unstacked branch with no work item, and the bundled script's path.
fill_block() {
    local b="$1"
    b="${b//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
    b="${b//W=\"W-<n>\"/W=\"\"}"
    b="${b//W=\"<the W-<n> step 2 named, or empty on the github backend>\"/W=\"\"}"
    b="${b//BASE_BRANCH=\"<sibling slice branch for a stacked PR, else empty>\"/BASE_BRANCH=\"\"}"
    printf '%s' "${b//<pr-number>/1}"
}

release_bin="$scratch/release-bin"
mkdir -p "$release_bin"
# A gh that serves one PR body out of a file, and takes an edit of it.
cat > "$release_bin/gh" <<'STUB'
#!/usr/bin/env bash
[ -z "${GH_FAIL:-}" ] || exit 1
case "$1 $2" in
    "pr list"|"pr view") cat "${GH_BODY:?}" ;;
    "pr edit")
        prev=""
        for a in "$@"; do
            if [ "$prev" = --body-file ]; then cat "$a" > "${GH_BODY:?}"; fi
            prev="$a"
        done ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$release_bin/gh"

release_round_trip() {  # $1 = shell, $2 = backend
    local sh="$1" backend="$2" at="[$1, $2]" r root body stamped rel_out before rc released_rel edited m left
    r="$scratch/release-$sh-$backend"
    root="$r.sidecars"
    body="$r.body"
    mkdir -p "$r/src"
    : > "$body"
    # shellcheck disable=SC2329,SC2317  # both are called by name below
    r_git() { GIT_CONFIG_GLOBAL="$sc_gitconfig" git -C "$r" "$@"; }
    r_run() {
        ( cd "$r" && PATH="$release_bin:$PATH" GH_BODY="$body" GIT_CONFIG_GLOBAL="$sc_gitconfig" \
            SKILL_KIT_SIDECAR_ROOT="$root" SKILL_KIT_RESEARCH_ARCHIVE="$scratch/archive" \
            CLAUDE_PROJECT_DIR="$r" CLAUDE_CODE_SESSION_ID="session-$sh-$backend" "$@" )
    }
    # Everything a refused release must leave as it was.
    r_state() {
        find "$r/.claude" -type f 2>/dev/null | LC_ALL=C sort
        cat "$body"
        if [ -d "$root/release" ]; then git -C "$root/release" rev-parse HEAD; fi
    }
    # r_stamp <sha> — /pre-merge's stamp block for this backend, with the body
    # edit its comment asks the agent for already made.
    r_stamp() {
        local blk="$sidecar_stamp_block"
        if [ "$backend" = github ]; then
            blk="$stamp_block"
            printf '## Summary\n\nbody\n\n<!-- reviewed-at: %s -->\n' "$1" > "$body"
        fi
        r_run "$sh" -c "$(fill_block "$(fill_reviewed "$blk" "$1")")" >/dev/null 2>&1
    }
    r_hook() {
        local home="$proj"
        proj="$r"
        run_hook "src/service.ts"
        proj="$home"
    }

    r_git init -q -b main
    printf '.claude/\n' > "$r/.git/info/exclude"
    printf 'base %s\n' "$r" > "$r/base.txt"
    r_git add base.txt
    r_git commit -q --no-verify -m "base $r"
    r_git switch -q -c feature
    printf 'export const x = 1\n' > "$r/src/service.ts"
    r_git add src/service.ts
    r_git commit -q --no-verify -m "feature"
    stamped="$(r_git rev-parse HEAD)"
    if [ "$backend" = sidecar ]; then
        r_run bash "$sidecar_sh" init --name release --mode guest --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1 \
            || fatal "could not init the release fixture's sidecar"
    fi
    assert_eq "$backend" "$(r_run bash "$sidecar_sh" backend stamp 2>/dev/null || true)" "$at fixture: backend stamp answers $backend"

    before="$(r_state)"
    rc=0; r_run bash "$sidecar_sh" stamp release feature --reason "copy" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "$at no stamp: release refuses"
    assert_eq "$before" "$(r_state)" "$at no stamp: …and changes nothing"

    rc=0; r_stamp "$stamped" || rc=$?
    assert_eq 0 "$rc" "$at the stamp block runs"
    # #811: the flag says who stamped and when, and which commit the review read.
    assert_eq "by=session-$sh-$backend|head=$stamped" \
        "$(grep '^by=' "$r/$stamp_rel" 2>/dev/null || true)|$(grep '^head=' "$r/$stamp_rel" 2>/dev/null || true)" \
        "$at the stamp flag names this session and the reviewed head"
    assert_eq 1 "$(grep -cE '^at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$r/$stamp_rel" 2>/dev/null || true)" \
        "$at the stamp flag carries the time, in UTC"
    r_hook
    assert_eq 2 "$hook_status" "$at stamped: the hook refuses"

    before="$(r_state)"
    rc=0; r_run bash "$sidecar_sh" stamp release feature >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc" "$at no --reason: release exits nonzero"
    assert_eq "$before" "$(r_state)" "$at no --reason: …and changes nothing"
    rc=0; r_run bash "$sidecar_sh" stamp release feature --reason "" >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc" "$at empty --reason: release exits nonzero"
    rc=0; r_run bash "$sidecar_sh" stamp release feature --reason "   " >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc" "$at blank --reason: release exits nonzero"
    rc=0; r_run bash "$sidecar_sh" stamp release other --reason "copy" >/dev/null 2>&1 || rc=$?
    assert_eq 1 "$rc" "$at a branch that is not checked out: release refuses"
    assert_eq "$before" "$(r_state)" "$at empty, blank, other branch: …and none changes anything"
    if [ "$backend" = github ]; then
        rc=0; r_run env GH_FAIL=1 bash "$sidecar_sh" stamp release feature --reason "copy" >/dev/null 2>&1 || rc=$?
        assert_eq 1 "$rc" "$at gh cannot read the PR: release refuses rather than guessing"
        assert_eq "$before" "$(r_state)" "$at gh cannot read the PR: …and changes nothing"
    fi

    rc=0
    rel_out="$(r_run bash "$sidecar_sh" stamp release feature --reason 'the user asked for a "copy" change' 2>/dev/null)" || rc=$?
    assert_eq 0 "$rc" "$at release exits 0"
    assert_eq "lock released: make the edit, then re-run /pre-merge to review $stamped..HEAD and re-stamp" "$rel_out" \
        "$at release prints the next step"
    if [ -e "$r/$stamp_rel" ]; then left=present; else left=gone; fi
    assert_eq gone "$left" "$at release removes the stamp flag"
    released_rel="$(find "$r/.claude" -type f | sed "s|^$r/||")"
    assert_eq "$released_rel" "$(grep -xF -- "$released_rel" <<<"$tdd_flags" || true)" \
        "$at the one file release leaves is a marker the hook's first clause reads"
    assert_eq 'reason=the user asked for a "copy" change' "$(grep '^reason=' "$r/$released_rel" 2>/dev/null || true)" \
        "$at the marker holds the reason"
    assert_eq "head=$stamped" "$(grep '^head=' "$r/$released_rel" 2>/dev/null || true)" "$at the marker holds the released head"
    assert_eq 1 "$(grep -cE '^released_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$r/$released_rel" 2>/dev/null || true)" \
        "$at the marker holds the time, in UTC"
    assert_eq "$stamped" "$(r_run bash "$sidecar_sh" stamp read feature --released 2>/dev/null || true)" \
        "$at stamp read --released prints the released head"
    if [ "$backend" = sidecar ]; then
        assert_eq "feature $stamped the user asked for a \"copy\" change" \
            "$(jq -r '"\(.branch) \(.head) \(.reason)"' "$root/release/reviews/released/feature.json" 2>/dev/null || true)" \
            "$at the record beside the stamp holds branch, head and reason"
        assert_eq "" "$(git -C "$root/release" status --porcelain)" "$at the record is committed"
        assert_eq "$stamped" "$(r_run bash "$sidecar_sh" stamp read feature 2>/dev/null || true)" "$at release wrote no stamp: it still names the reviewed head"
    else
        assert_eq 1 "$(grep -cF "reviewed-at: $stamped" "$body" || true)" "$at release wrote no stamp: the PR body still names the reviewed head"
    fi

    r_hook
    assert_eq 0 "$hook_status" "$at released: the hook allows the edit"
    printf 'export const x = 2\n' > "$r/src/service.ts"
    r_git commit -q --no-verify -am "the requested edit"
    edited="$(r_git rev-parse HEAD)"
    assert_eq "review scope: post-stamp delta, from $stamped" \
        "$(r_run "$sh" -c "$(fill_block "$scope_step")" 2>/dev/null | grep '^review scope:' || true)" \
        "$at the next review starts at the released head"

    rc=0; r_stamp "$edited" || rc=$?
    assert_eq 0 "$rc" "$at the re-stamp runs"
    left=""
    for m in "${markers[@]}"; do
        if [ -e "$r/$m" ]; then left="$left$m "; fi
    done
    assert_eq "" "$left" "$at the re-stamp removes the release marker"
    r_hook
    assert_eq 2 "$hook_status" "$at re-stamped: the hook refuses again"
    assert_eq "" "$(r_run bash "$sidecar_sh" stamp read feature --released 2>/dev/null || echo failed)" \
        "$at the re-stamp spends the release record"
    if [ "$backend" = sidecar ]; then
        assert_eq "" "$(git -C "$root/release" status --porcelain)" "$at …and commits that in the sidecar"
        r_run bash "$sidecar_sh" stamp release feature --reason "again" >/dev/null 2>&1 || true
        r_run bash "$sidecar_sh" stamp clear feature >/dev/null 2>&1 || true
        assert_eq "" "$(find "$root/release/reviews" -type f)" "$at stamp clear takes the release record with the stamp"
    fi
}

# -----------------------------------------------------------------------------

section "13. a flag says who made it and when, and a second session is told (#811)"

# /fix-findings' harness line writes its flag once and never over another
# session's, and /pre-merge's owner block names a stamp flag this session did
# not write. Both run as written, in both shells. The session id is the one
# Claude Code sets for Bash commands, CLAUDE_CODE_SESSION_ID.
owner_block="$(awk '
    /^   # Who left the review lock on this checkout\?/ { on = 1 }
    on && /^   ```$/                                    { exit }
    on                                                  { print substr($0, 4) }
' pre-merge/SKILL.md)"
[ -n "$owner_block" ] || fatal "no owner block found in pre-merge/SKILL.md Phase 1 step 4"

owner_case() {  # $1 = shell
    local sh="$1" o="$scratch/owner-$1" out first
    mkdir -p "$o"
    git init -q "$o"
    GIT_CONFIG_GLOBAL="$sc_gitconfig" git -C "$o" commit -q --allow-empty --no-verify -m "owner $o"
    # shellcheck disable=SC2329,SC2317  # called by name below
    o_run() {  # $1 = session id, $2 = command text
        ( cd "$o" && CLAUDE_PROJECT_DIR="$o" CLAUDE_CODE_SESSION_ID="$1" "$sh" -c "$2" 2>&1 )
    }

    out="$(o_run session-a "$fixer_write")"
    first="$(cat "$o/$fixer_rel" 2>/dev/null || true)"
    assert_eq "by=session-a|head=$(git -C "$o" rev-parse HEAD)" \
        "$(grep '^by=' <<<"$first" || true)|$(grep '^head=' <<<"$first" || true)" \
        "[$sh] the harness line writes the fixer flag with this session and HEAD"
    assert_eq 1 "$(grep -cE '^at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$first" || true)" \
        "[$sh] …and the time, in UTC"
    out="$(o_run session-b "$fixer_write")"
    assert_eq "$first" "$(cat "$o/$fixer_rel" 2>/dev/null || true)" \
        "[$sh] a second session's load leaves the first session's flag as it was"
    case "$out" in
        *"by=session-a"*) assert_eq ok ok "[$sh] …and prints it, so the second session can see whose lock it is" ;;
        *) assert_eq "the flag's by=session-a line" "$out" "[$sh] …and prints it, so the second session can see whose lock it is" ;;
    esac

    rm -f "$o/$stamp_rel"
    assert_eq "" "$(o_run session-a "$owner_block")" "[$sh] no stamp flag: the owner block prints nothing"
    mkdir -p "$o/.claude"
    printf 'by=session-a\nat=2026-11-20T10:00:00Z\nhead=0\n' > "$o/$stamp_rel"
    assert_eq "" "$(o_run session-a "$owner_block")" "[$sh] this session's stamp flag: the owner block prints nothing"
    out="$(o_run session-b "$owner_block")"
    case "$out" in
        *"session-a"*"2026-11-20T10:00:00Z"*) assert_eq ok ok "[$sh] another session's stamp flag: the owner block names who and when" ;;
        *) assert_eq "a line naming session-a and its time" "$out" "[$sh] another session's stamp flag: the owner block names who and when" ;;
    esac
    : > "$o/$stamp_rel"
    out="$(o_run session-a "$owner_block")"
    case "$out" in
        *unknown*) assert_eq ok ok "[$sh] an empty flag from before #811: the owner block says it cannot tell" ;;
        *) assert_eq "a line saying the maker is unknown" "$out" "[$sh] an empty flag from before #811: the owner block says it cannot tell" ;;
    esac
}
owner_case bash
if command -v zsh >/dev/null 2>&1; then
    owner_case zsh
elif [ -n "${CI:-}" ]; then
    assert_eq "zsh on PATH" "zsh absent" "the owner rows ran under zsh (CI is set, so a missing zsh fails)"
else
    printf '  SKIP zsh is not on PATH, so the owner rows ran under bash only\n'
fi

release_round_trip bash github
release_round_trip bash sidecar
if command -v zsh >/dev/null 2>&1; then
    release_round_trip zsh github
    release_round_trip zsh sidecar
elif [ -n "${CI:-}" ]; then
    assert_eq "zsh on PATH" "zsh absent" "the release round trip ran under zsh (CI is set, so a missing zsh fails)"
else
    printf '  SKIP zsh is not on PATH, so the release round trip ran under bash only\n'
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
