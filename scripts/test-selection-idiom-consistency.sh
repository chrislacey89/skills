#!/usr/bin/env bash
# test-selection-idiom-consistency.sh — cross-file contract test for the
# "which slices are takeable" selection idiom.
#
# Five hand-maintained files decide what is unblocked: /prd-to-issues §9,
# /execute's issue-shape and blocker gate, /help's frontier call, /setup-ralph-loop's two
# FRONTIER copies, and SYSTEM-OVERVIEW.md's Ralph example. They read the same
# graph and are asserted in prose to "agree by construction rather than by
# coincidence" (help/SKILL.md, SYSTEM-OVERVIEW.md).
#
# Before this suite, nothing constructed that agreement. It was maintained by
# hand across all five, and the assertion is what stopped anyone from checking —
# see docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md,
# which was written after a false capability claim propagated to nine sites and
# survived a week.
#
# The suite extracts the real text from the real files rather than restating
# it. A hand-copied assertion drifts alongside the thing it tests; a suite that
# reads every occurrence fails precisely when they stop agreeing.
#
# Deliberately NOT asserted: that all occurrences are byte-identical. They are
# not, and should not be — §9 tests for an empty set, /execute projects
# {number, title}, /help projects .number. Only the parts that must agree are
# pinned.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$label"
    else
        bad "$label" "$(printf 'expected: %q\n       got:      %q' "$expected" "$actual")"
    fi
}

# Files that hand-maintain the selection idiom. Bundled references/ copies are
# excluded on purpose — sync-skill-references.sh already pins those to
# SYSTEM-OVERVIEW.md, and including them here would test that suite instead.
selection_files=(
    prd-to-issues/SKILL.md
    execute/SKILL.md
    help/SKILL.md
    setup-ralph-loop/SKILL.md
    SYSTEM-OVERVIEW.md
)

# -----------------------------------------------------------------------------
section "the three FRONTIER copies are one script"

# ralph-once.sh and ralph.sh in /setup-ralph-loop, plus SYSTEM-OVERVIEW.md's
# worked example, are the same selection block at three indentation levels.
# Normalize leading whitespace and assert one distinct value.
frontier_blocks="$(
    # coverage: enumerated — the two files that restate the frontier-selection
    # idiom. Not derivable for the same reason: membership follows from which
    # documents make the claim, not from a pattern in the tree.
    for f in setup-ralph-loop/SKILL.md SYSTEM-OVERVIEW.md; do
        awk '/FRONTIER=\$\(gh issue list/{c=1}
             c{gsub(/^[ \t]+/,""); print}
             c && /join\(", "\)\x27\)/{print "###"; c=0}' "$f"
    done
)"

block_count="$(grep -c '^###$' <<<"$frontier_blocks" || true)"
assert_eq "3" "$block_count" "three FRONTIER blocks found"

distinct="$(awk 'BEGIN{RS="###\n"} NF{print}' <<<"$frontier_blocks" | sort -u | grep -c 'FRONTIER=' || true)"
assert_eq "1" "$distinct" "all FRONTIER blocks normalize to one value"

# -----------------------------------------------------------------------------
section "the blocker-state predicate is the uppercase GraphQL enum"

# `gh ... --json blockedBy` returns state as OPEN/CLOSED; the REST dependency
# endpoint returns open/closed. A jq filter copied between the two silently
# matches nothing — no error, just an empty result that reads as "unblocked".
lower_state="$(grep -n 'blockedBy' "${selection_files[@]}" | grep 'state == "open"' || true)"
if [[ -z "$lower_state" ]]; then
    ok "no lowercase .state == \"open\" alongside a blockedBy read"
else
    bad "lowercase state compared against a blockedBy read" "$lower_state"
fi

# Every file that filters blockedBy nodes by state must use OPEN.
for f in "${selection_files[@]}"; do
    if grep -q 'blockedBy.nodes' "$f"; then
        if grep -q 'state == "OPEN"' "$f" || grep -q 'blockedBy.totalCount' "$f"; then
            ok "$f filters or counts blockedBy nodes explicitly"
        else
            bad "$f reads blockedBy.nodes without a state filter or totalCount"
        fi
    fi
done

# -----------------------------------------------------------------------------
section "the retired REST-only claims stay retired"

# "gh issue list --json cannot see dependency data" was false when written and
# propagated to nine sites. `isBlocked` is the one field that genuinely does not
# exist, and the only legitimate mention is the sentence explaining that.
# Scoped to the skills and SYSTEM-OVERVIEW — the files that *instruct*. CHANGELOG
# and docs/solutions legitimately narrate the history of the false claim, and
# .context/ is gitignored scratch.
stray_isblocked="$(grep -n 'isBlocked' SYSTEM-OVERVIEW.md ./*/SKILL.md 2>/dev/null \
    | grep -v 'does not exist and is easily mistaken' || true)"
if [[ -z "$stray_isblocked" ]]; then
    ok "no skill asserts a capability limit via isBlocked"
else
    bad "isBlocked resurfaced outside its one explanatory mention" "$stray_isblocked"
fi

# -----------------------------------------------------------------------------
section "cross-skill references point at headings that exist"

# A reference like "/qa Step 4b" couples one skill to another's *numbering*.
# This repo renumbered /qa's Step 4 sequence once already, in the same PR that
# introduced such a reference, so the coupling is not hypothetical.
# The skill name and the step number must be ADJACENT to count as a reference.
# Matching "any /skill on the line + any Step N on the line" produces false
# positives: setup-ralph-loop:207 mentions /execute and, later in the same
# sentence, "(Step 8 below)" — an internal reference to its own Step 8.
bad_refs=""
# shellcheck disable=SC2016  # backticks below are literal markdown, not expansion
while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    skill="$(sed -E 's@^`/([a-z-]+)` Step .*@\1@' <<<"$pair")"
    step="$(sed -E 's@^.* Step ([0-9]+[a-z]?)$@\1@' <<<"$pair")"
    target="$skill/SKILL.md"
    if [ ! -f "$target" ]; then
        bad_refs="$bad_refs  reference to /$skill, but $target does not exist"$'\n'
        continue
    fi
    # Step headings are "### N. Title"; sub-steps are "#### Na. Title".
    if ! grep -qE "^#+ *${step}\." "$target"; then
        bad_refs="$bad_refs  \"/$skill Step $step\" — no such heading in $target"$'\n'
    fi
done < <(grep -rho '`/[a-z-]\+` Step [0-9]\+[a-z]\?' ./*/SKILL.md 2>/dev/null | sort -u || true)

if [[ -z "$bad_refs" ]]; then
    ok "every cross-skill Step reference resolves"
else
    bad "cross-skill Step reference does not resolve" "$bad_refs"
fi

# -----------------------------------------------------------------------------
section "/execute's issue-shape and blocker gate decides by running, not reading"

# #488: a session ran /execute on an issue an open PR already closed. Its GitHub
# read came back without the comment that said so, and it judged the PRD-marker
# check by eye and passed a body that carried two of the markers. The gate is
# now one executable block; this section pins its verdict logic against canned
# responses so "empty is not clear" is something the suite checks.
gate_jq="$(awk '
    /^VERDICT_JQ=\x27$/ {c=1; next}
    c && /^end\x27$/    {print "end"; exit}
    c                   {print}
' execute/SKILL.md)"
if [[ -n "$gate_jq" ]]; then
    ok "found VERDICT_JQ in execute/SKILL.md"
else
    bad "VERDICT_JQ block not found in execute/SKILL.md"
fi

gate_block="$(awk '/^N=<n>$/{c=1} c{print} c && /^jq -r/{exit}' execute/SKILL.md)"
for field in 'closedByPullRequestsReferences' 'state headRefName' 'blockedBy(first: 50) { totalCount nodes { number title state } }' 'comments(last: 100) { totalCount nodes { body } }' 'closedByPullRequestsReferences(first: 20) { totalCount nodes { number state headRefName } }' 'number title body'; do
    if grep -qF -- "$field" <<<"$gate_block"; then
        ok "the gate's query requests: $field"
    else
        bad "the gate's query no longer requests: $field"
    fi
done
if grep -qF '|| RESP=null' <<<"$gate_block" && grep -qF '|| echo unknown' <<<"$gate_block" \
    && grep -qF 'jq -rn ' <<<"$gate_block"; then
    ok "a failed gh call or jq run maps to unknown"
else
    bad "the gate no longer maps a failed gh call or jq run to unknown"
fi

# The marker list is stated in prose once and executed once; they must match.
# shellcheck disable=SC2016  # backticks below are literal markdown, not expansion
prose_markers="$(grep -F '**`undecomposed-prd`**' execute/SKILL.md \
    | grep -o '(`[^)]*)' | head -1 | grep -o '`[^`]*`' | tr -d '`' | sort | paste -sd'|' -)"
code_markers="$(grep -o '(Appetite|[^)]*)' <<<"$gate_jq" | tr -d '()' | tr '|' '\n' | sort | paste -sd'|' -)"
assert_eq "$prose_markers" "$code_markers" "prose marker list matches the block's marker regex"
# The regex must also name every pitch-template section that marks a shaped PRD,
# so shrinking it (e.g. dropping No-gos from both the regex and the prose) is
# red (#498). The marker set is pinned here; every other level-2 template
# heading must be listed in pitch_unmarked with its reason, so a heading added
# to the template forces a decision about the gate instead of passing silently.
expected_markers='Appetite|Implementation Decisions|No-gos|Rabbit Holes|User Stories'
assert_eq "$expected_markers" "$code_markers" "the gate's marker regex names exactly the pinned shaped-pitch markers"
# Not markers. The marker set is the one #488 chose; these headings are listed
# so that each is a recorded decision rather than an omission. Problem and
# Solution also head issues that are not PRDs (/triage-issue bugs,
# /create-milestone features, /request-refactor-plan RFCs), so matching them
# would stop work the gate should let through.
pitch_unmarked='Problem|Target / Estimate / Commitment|Uncertainty / Confidence|Solution|API Contract Sketch|Research Reference|Lessons from Past Solutions'
pitch_h2="$(awk '/^<pitch-template>$/{c=1; next} /^<\/pitch-template>$/{c=0} c && /^## /{sub(/^## /, ""); print}' write-a-prd/SKILL.md)"
while IFS= read -r h; do
    [ -n "$h" ] || continue
    if grep -qxF -- "$h" < <(tr '|' '\n' <<<"$expected_markers"; tr '|' '\n' <<<"$pitch_unmarked"); then
        ok "pitch-template section '$h' is classified (marker or stated exclusion)"
    else
        bad "pitch-template section '$h' is neither a gate marker nor a stated exclusion"
    fi
done <<<"$pitch_h2"
while IFS= read -r m; do
    if grep -qxF -- "$m" <<<"$pitch_h2"; then
        ok "pinned marker '$m' is a pitch-template section"
    else
        bad "pinned marker '$m' is not a ## section of write-a-prd's <pitch-template>"
    fi
done < <(tr '|' '\n' <<<"$expected_markers")

# Run the real block, not a retyped copy: gate_block is the fenced bash from
# execute/SKILL.md (N=<n> through the final jq line), evaluated with `gh` and
# `git` stubbed as functions so the canned response flows through the file's own
# jq invocation. Editing that invocation, VERDICT_JQ, or the query's blocker
# fields in the file changes what this runs (guard-and-subject-must-be-one-artifact).
gate_exec="${gate_block/N=<n>/N=7}"
# stderr is kept, not discarded (guard-and-subject-must-be-one-artifact: never
# redirect a reader's stderr to /dev/null): it lands in $gate_err so a fixture
# can assert the gate's own jq error survives. Stdout alone is the verdict.
gate_err="$(mktemp)"
gate_n="$(mktemp)"
gate_fargs="$(mktemp)"
trap 'rm -f "$gate_err" "$gate_n" "$gate_fargs"' EXIT
# shellcheck disable=SC2317,SC2329  # the stubs are called from the eval'd block
run_gate() { # $1 = response JSON ("GHFAIL" makes gh exit 1), $2 = current branch, $3 = script (default: the real block)
    (
        resp="$1"
        branch="${2:-task-branch}"
        # Records the value of the -F n=... argument it receives into $gate_n, and
        # every -F argument (one per line) into $gate_fargs.
        gh() {
            local prev="" a
            : >"$gate_fargs"
            for a in "$@"; do
                [[ "$prev" == -F && "$a" == n=* ]] && printf '%s' "$a" >"$gate_n"
                [[ "$prev" == -F ]] && printf '%s\n' "$a" >>"$gate_fargs"
                prev="$a"
            done
            [[ "$resp" != GHFAIL ]] || return 1
            printf '%s' "$resp"
        }
        git() { printf '%s\n' "$branch"; }
        eval "${3:-$gate_exec}"
    ) 2>"$gate_err" || echo unknown
}
fixture() { # jq expression applied to a healthy, takeable base response
    jq -cn "{data: {repository: {issue: {
        number: 7, title: \"t\", body: \"## Problem\nx\",
        comments: {totalCount: 0, nodes: []},
        blockedBy: {totalCount: 0, nodes: []},
        closedByPullRequestsReferences: {totalCount: 0, nodes: []}}}}} | $1"
}
verdict() { cut -d' ' -f1 <<<"$1"; }

assert_eq "takeable"  "$(verdict "$(run_gate "$(fixture .)")")" "healthy response -> takeable"
assert_eq "n=7" "$(cat "$gate_n")" "the gate passes the issue number it was given as -F n="
# All three -F arguments the query's variables bind to. gh resolves {owner} and
# {repo} itself, so the literal placeholders are the contract; dropping either
# makes `gh api graphql` fail and the gate print unknown on every issue (#498).
assert_eq "n=7|owner={owner}|repo={repo}" "$(sort "$gate_fargs" | paste -sd'|' -)" "the gate passes -F owner, -F repo and -F n to gh api graphql"
# The query header must declare exactly the variables those arguments bind,
# extracted from the real block rather than restated.
# shellcheck disable=SC2016  # the $ names are literal GraphQL variables
assert_eq 'query($owner: String!, $repo: String!, $n: Int!) {' "$(grep -F 'query($' <<<"$gate_block" | sed 's/^ *//')" "the gate's query header declares the owner, repo and n variables"
# A broken program must say so: the verdict is still unknown, and the real
# block's own jq error must reach stderr. Putting 2>/dev/null back on the gate's
# final line leaves stdout identical and empties this, so this goes red.
broken_exec="${gate_exec/\"\$VERDICT_JQ\"/\"\$VERDICT_JQ ) broken ( \"}"
if [[ "$broken_exec" == "$gate_exec" ]]; then
    bad "could not break the gate's jq program (the substitution matched nothing)"
fi
assert_eq "unknown" "$(run_gate "$(fixture .)" task-branch "$broken_exec")" "a broken jq program -> unknown"
if grep -q 'jq: error' "$gate_err"; then
    ok "a broken jq program's error reaches stderr (not swallowed)"
else
    bad "a broken jq program's error was swallowed" "stderr: $(cat "$gate_err")"
fi
assert_eq "unknown"   "$(run_gate 'null')" "null response -> unknown"
assert_eq "unknown"   "$(run_gate GHFAIL)" "failed gh call -> unknown"
assert_eq "unknown"   "$(run_gate '')" "empty response -> unknown"
assert_eq "unknown"   "$(run_gate '{}')" "empty object -> unknown"
assert_eq "unknown"   "$(run_gate "$(fixture '.errors = [{message: "x"}]')")" "GraphQL errors -> unknown"
assert_eq "unknown"   "$(run_gate "$(fixture '.data.repository.issue.number = 8')")" "wrong number echoed -> unknown"
assert_eq "unknown"   "$(run_gate "$(fixture 'del(.data.repository.issue.title)')")" "missing title -> unknown"
assert_eq "unknown"   "$(run_gate "$(fixture 'del(.data.repository.issue.closedByPullRequestsReferences)')")" "missing PR field -> unknown"
assert_eq "unknown"   "$(run_gate "$(fixture '.data.repository.issue.comments.totalCount = 1')")" "comment list shorter than its count -> unknown"
assert_eq "undecomposed-prd" "$(run_gate "$(fixture '.data.repository.issue.body = "## Rabbit Holes\nx"')")" "PRD marker, no decomposition -> undecomposed-prd"
assert_eq "undecomposed-prd" "$(run_gate "$(fixture '.data.repository.issue.body = "## Appetite\r\nx\r\n"')")" "CRLF PRD heading (web-editor line endings) -> undecomposed-prd"
assert_eq "takeable"  "$(verdict "$(run_gate "$(fixture '.data.repository.issue.body = "## No-gos\nx" | .data.repository.issue.comments = {totalCount: 1, nodes: [{body: "Decomposed into: #8, #9"}]}')")")" "decomposed PRD -> falls through to takeable"
# A real slice is not a PRD: its body is the headings /prd-to-issues' own issue
# template writes (extracted from the file, so a heading added there is checked),
# including "## User Stories Addressed", and it never gets a Decomposed comment.
slice_body="$(awk '/^<issue-template>$/{c=1; next} /^<\/issue-template>$/{c=0} c && /^#+ /{print}' prd-to-issues/SKILL.md)"
if grep -qF 'User Stories Addressed' <<<"$slice_body"; then
    ok "extracted the slice template's headings (incl. User Stories Addressed)"
else
    bad "slice template headings not extracted from prd-to-issues/SKILL.md"
fi
slice_resp="$(jq -c --arg b "$slice_body" '.data.repository.issue.body = $b' <<<"$(fixture .)")"
assert_eq "takeable" "$(verdict "$(run_gate "$slice_resp")")" "real slice template headings -> takeable, not undecomposed-prd"
# Mirror image: the real PRD template must still be flagged. For each marker the
# gate's regex names, /write-a-prd's <pitch-template> must carry it as a bare
# heading (a suffix such as "## Appetite (6 weeks)" would let that PRD read
# takeable), and a body of just that template heading must read undecomposed-prd.
# Per marker, because one surviving bare marker would otherwise mask a suffixed one.
prd_headings="$(awk '/^<pitch-template>$/{c=1; next} /^<\/pitch-template>$/{c=0} c && /^#+ /{print}' write-a-prd/SKILL.md)"
if [ -n "$code_markers" ] && grep -qiE '^#+ *Appetite *$' <<<"$prd_headings"; then
    ok "extracted the PRD template's headings (incl. a bare Appetite)"
else
    bad "PRD template headings not extracted from write-a-prd/SKILL.md"
fi
while IFS= read -r m; do
    [ -n "$m" ] || continue
    h="$(grep -iE "^#+ *${m} *\$" <<<"$prd_headings" | head -1 || true)"
    if [ -z "$h" ]; then
        bad "write-a-prd <pitch-template> has no bare '## $m' heading the gate would flag"
        continue
    fi
    assert_eq "undecomposed-prd" "$(run_gate "$(jq -c --arg b "$h" '.data.repository.issue.body = $b' <<<"$(fixture .)")")" "real PRD template heading '$h' -> undecomposed-prd"
done < <(tr '|' '\n' <<<"$code_markers")
assert_eq "blocked"   "$(verdict "$(run_gate "$(fixture '.data.repository.issue.blockedBy = {totalCount: 1, nodes: [{number: 3, title: "b", state: "OPEN"}]}')")")" "open blocker -> blocked"
assert_eq "takeable"  "$(verdict "$(run_gate "$(fixture '.data.repository.issue.blockedBy = {totalCount: 1, nodes: [{number: 3, title: "b", state: "CLOSED"}]}')")")" "closed blocker -> takeable"
assert_eq "unknown"   "$(run_gate "$(fixture '.data.repository.issue.blockedBy = {totalCount: 2, nodes: [{number: 3, title: "b", state: "OPEN"}]}')")" "blocker list shorter than its count -> unknown"
assert_eq "undecomposed-prd" "$(run_gate "$(fixture '.data.repository.issue.body = "## Appetite\nx" | .data.repository.issue.blockedBy = {totalCount: 1, nodes: [{number: 3, title: "b", state: "OPEN"}]}')")" "PRD heading plus open blocker -> undecomposed-prd (order pinned)"
assert_eq "in-flight" "$(verdict "$(run_gate "$(fixture '.data.repository.issue.closedByPullRequestsReferences = {totalCount: 1, nodes: [{number: 5, state: "OPEN", headRefName: "other"}]}')")")" "open PR on another branch -> in-flight"
assert_eq "takeable"  "$(verdict "$(run_gate "$(fixture '.data.repository.issue.closedByPullRequestsReferences = {totalCount: 1, nodes: [{number: 5, state: "OPEN", headRefName: "mine"}]}')" mine)")" "open PR on the current branch -> takeable"
assert_eq "takeable"  "$(verdict "$(run_gate "$(fixture '.data.repository.issue.closedByPullRequestsReferences = {totalCount: 1, nodes: [{number: 5, state: "CLOSED", headRefName: "other"}]}')")")" "closed PR -> takeable"
assert_eq "unknown"   "$(run_gate "$(fixture '.data.repository.issue.closedByPullRequestsReferences = {totalCount: 2, nodes: [{number: 5, state: "OPEN", headRefName: "other"}]}')")" "PR list shorter than its count -> unknown"

# -----------------------------------------------------------------------------
section "the by-construction claim is backed by this suite"

# The prose assertion and its enforcement must ship together. If a file claims
# the selection sites agree by construction, this suite is what constructs it —
# so the claim's presence implies this file's presence, and vice versa.
claim_files="$(grep -rln 'agree by construction' --include='*.md' . | grep -v '^\./CHANGELOG.md$' || true)"
if [[ -n "$claim_files" ]]; then
    ok "the 'agree by construction' claim is present and enforced by this suite"
else
    bad "no file claims agreement — if the claim was removed, remove this suite too"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
