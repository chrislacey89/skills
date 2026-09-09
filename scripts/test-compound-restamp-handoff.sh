#!/usr/bin/env bash
# test-compound-restamp-handoff.sh — the in-PR /compound commit must be routed
# back through /pre-merge, and the two steps that judge it must judge it by its
# paths rather than by its subject line.
#
# THE INCIDENT (#336, measured on chrislacey89/fulcrum). /pre-merge Phase 4
# stamps the SHA its review covered. /compound's in-PR default then commits the
# docs/solutions/ entry onto the same branch, pushed, and handed straight to
# /closeout. Nothing re-stamped, because /pre-merge is the stamp's only writer
# (scripts/test-review-currency-marker.sh pins that). Of 17 merged PRs carrying
# a stamp, 10 merged past it; 4 of the 10 were `docs: compound` commits, and 2
# of those 4 shipped code — a contract test rewritten to derive its coverage
# from the schema, and a new test file — both under a subject beginning
# `docs: compound`. The in-PR path's whole justification is that the entry is
# "reviewed and merged with the code that taught it"; as ordered, it was merged
# with that code and read by nobody.
#
# TWO CLAIMS, AND WHY EACH NEEDS A MECHANISM RATHER THAN PROSE.
#
#   1. THE HANDOFF TARGET. `**Next session:** /closeout` is the sentence a
#      future prose edit most plausibly restores — it was correct for years, it
#      reads naturally, and restoring it reintroduces the whole defect in one
#      line with nothing else in the repo noticing. So the target is extracted
#      from /compound's own Phase 6 in-PR block and asserted.
#
#   2. THE DISCRIMINATOR. /pre-merge (do not re-recommend /compound on the
#      re-run /compound handed back) and /closeout Step 2 (name a docs-only
#      compound commit, and refuse the discount to one that ships code) each
#      document a runnable block that decides the case. CLAUDE.md § "Commands a
#      skill documents" rule (b) routes a checkable claim about tool behavior to
#      a mechanism, and this one earned it during authoring: the first draft of
#      /pre-merge's block asked `grep -qv` for the verdict, and running it
#      against a fixture returned the INVERSE answer. `grep` on PATH in a Claude
#      Code shell is a function wrapping ugrep, whose `-q -v` exits 1 on input
#      that does contain a non-matching line — so the block suppressed the
#      recommendation on a delta carrying code, which is the silent direction.
#      Careful reading had already passed it twice. So these tests do not read
#      the blocks; they extract them verbatim and RUN them, in both directions,
#      against a fixture that carries one compound commit of each kind.
#
# THE LIMIT OF THAT, FOUND BY MUTATING THIS SUITE'S OWN SUBJECT. Restoring the
# `grep -qv` draft into /pre-merge/SKILL.md and re-running leaves this suite
# GREEN. The blocks execute under `bash -c`, and the ugrep wrapper is an
# interactive-shell function that does not reach a non-interactive bash — so the
# runner sees real grep, where `-q -v` is correct. The behavioral tests verify
# the blocks' LOGIC; they cannot see the environment the defect actually fires
# in, and reproducing that environment on a GitHub runner is not possible
# because the wrapper is not there either. So the shape is BANNED rather than
# its behavior tested (the same move scripts/test-pipefail-safe-matchers.sh
# makes, and for the overlapping reason — `grep -q` is also an early-exiting
# reader that gives `pipefail` a second exit status to misreport). That
# assertion is decidable from the text and runs anywhere. Without it this
# suite would have reported a validated instrument over the exact draft that
# shipped the bug.
#
# WHY A FIXTURE OF EACH KIND. #298's lesson 4 — a fixture that cannot express
# the fault proves nothing about it. The fault here is a code-carrying commit
# being waved through on the strength of its `docs: compound` subject, so the
# fixture has to contain one, and every assertion below that matters is about
# that commit rather than the docs-only one.
#
# WHAT THIS DOES NOT CATCH, stated so nobody over-trusts it. It runs the two
# blocks and checks the handoff target. It says nothing about whether an agent
# following the surrounding prose actually invokes /pre-merge, which is not
# decidable from the text — and nothing about the post-merge fallback path,
# which never moves a head past a stamp and so has no delta to judge.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compound_skill="$repo_root/compound/SKILL.md"
premerge_skill="$repo_root/pre-merge/SKILL.md"
closeout_skill="$repo_root/closeout/SKILL.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    [[ $# -lt 2 ]] || printf '       expected: %s\n' "$2"
    [[ $# -lt 3 ]] || printf '       got:      %s\n' "$3"
    fail=$((fail + 1))
}
assert_eq() {
    if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3" "$1" "$2"; fi
}
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# ONE extractor, called with a needle, rather than one per skill — a reader
# duplicated between two call sites is what scripts/test-duplicate-guard-programs.sh
# bans, and a parameterized single copy is the shape that suite asks for.
# Returns the ```bash fence in $1 whose body contains the fixed string $2.
#
# Fences are matched with leading whitespace allowed, and the block's own indent
# is stripped, because /closeout's block sits inside a nested bullet and is
# indented two spaces. An anchored `^```bash` found nothing there and the FATAL
# above fired — which is the guard working, but the extractor has to handle the
# real file rather than the convenient one.
extract_block() {
    awk -v needle="$2" '
        /^[[:space:]]*```bash$/ {
            inblock = 1; buf = ""; hit = 0
            match($0, /^[[:space:]]*/); indent = RLENGTH
            next
        }
        /^[[:space:]]*```$/ { if (inblock && hit) { printf "%s", buf; exit } ; inblock = 0; next }
        inblock {
            line = substr($0, indent + 1)
            buf = buf line "\n"
            if (index($0, needle)) hit = 1
        }
    ' "$1"
}

# extract_section <file> <exact heading line> — everything between that
# heading and the next `#`-prefixed line (any level), exclusive of both. Used
# below to scope the "only writer" assertion to Phase 5 specifically, rather
# than the whole file — see the comment at that assertion for why a file-wide
# match is the wrong shape here.
extract_section() {
    awk -v heading="$2" '
        $0 == heading { inside = 1; next }
        inside && /^#/ { exit }
        inside { print }
    ' "$1"
}

# -----------------------------------------------------------------------------

section "the in-PR path hands to /pre-merge, not /closeout"

# Read the handoff target out of /compound Phase 6's in-PR closing block. Both
# closing blocks are fenced plain (```), and only the in-PR one carries a
# `**Next session:**` line — the post-merge fallback prints "Loop closed."
# instead — so a single grep over the file cannot pick the wrong one, and the
# assertion below on the fallback's line is what keeps that true.
next_session="$(grep -oE '^\*\*Next session:\*\* /[a-z-]+' "$compound_skill" | head -1 || true)"
[[ -n "$next_session" ]] || fatal "no '**Next session:** /<skill>' line in $compound_skill"
assert_eq '**Next session:** /pre-merge' "$next_session" \
    "/compound's in-PR closing block hands to /pre-merge (the re-run that reviews the commit and re-stamps)"

# Exactly one such line: the post-merge fallback must NOT gain one, because on
# that path there is no open PR, no stamp, and nothing to re-review. A second
# line would also make the grep above ambiguous.
next_session_count="$(grep -cE '^\*\*Next session:\*\* /[a-z-]+' "$compound_skill" || true)"
assert_eq "1" "$next_session_count" \
    "/compound carries exactly one Next-session line — the post-merge fallback still prints 'Loop closed.'"

# The claim the handoff rests on: /compound is not licensed to re-stamp, so the
# only way the stamp moves is by handing back. test-review-currency-marker.sh
# owns the single-writer contract itself; this asserts the reason is written
# down where the handoff is read, so a future editor deleting the handoff has to
# confront why it exists.
#
# Scoped to Phase 5, not grep -qF over the whole file. "only writer" also
# appears in the Invocation Position paragraph (a summary of the same fact,
# written before Phase 5 exists to state it operationally) — a file-wide grep
# is satisfied by that summary alone and stays green with the Phase 5 hand-back
# sentence deleted outright. That is root cause 4 of
# docs/solutions/testing-patterns/battery-that-only-perturbs-what-is-present-2026-08-28.md,
# "a needle too generic to die with its sentence": the phrase survives its own
# sentence being deleted because a decorative copy lives elsewhere in the file.
# Extracting the Phase 5 section first and matching only inside it makes the
# assertion die with the sentence it is meant to pin.
phase5="$(extract_section "$compound_skill" "### Phase 5: Commit")"
[[ -n "$phase5" ]] || fatal "no '### Phase 5: Commit' section in $compound_skill"
if grep -qF "only writer" <<<"$phase5"; then
    ok "/compound's Phase 5 states that it is not the stamp's writer, which is why it hands back"
else
    bad "/compound's Phase 5 no longer says why it cannot re-stamp itself" \
        "the phrase 'only writer' inside ### Phase 5: Commit" "absent"
fi

# -----------------------------------------------------------------------------

section "the documented discriminators run, in both directions"

premerge_block="$(extract_block "$premerge_skill" 'do not re-recommend /compound')"
[[ -n "$premerge_block" ]] || fatal "no bash block in $premerge_skill containing 'do not re-recommend /compound'"
closeout_block="$(extract_block "$closeout_skill" 'docs: compound')"
[[ -n "$closeout_block" ]] || fatal "no bash block in $closeout_skill containing 'docs: compound'"

# The fixture. Four commits: a base to stamp at, a docs-only compound entry, a
# compound commit that ALSO ships code (the #336 fault, and the only commit here
# any assertion turns on), and an unrelated commit so the delta is not composed
# entirely of compound commits.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
build_fixture() {
    git init -q "$scratch/repo"
    cd "$scratch/repo"
    git config user.email fixture@example.com
    git config user.name fixture
    # A repo-local hooksPath so a global pre-commit hook cannot reject these
    # commits — #296's dead-guard incident reproduced exactly that way.
    git config core.hooksPath "$scratch/no-hooks"
    mkdir -p src docs/solutions/testing-patterns
    printf 'a\n' > src/a.txt
    git add -A && git commit -q -m "feat: base"
    REVIEWED_SHA="$(git rev-parse HEAD)"
    printf 'lesson\n' > docs/solutions/testing-patterns/docs-only.md
    git add -A && git commit -q -m "docs: compound — a docs-only entry"
    DOCS_ONLY_SHA="$(git rev-parse HEAD)"
    printf 'lesson\n' > docs/solutions/testing-patterns/with-mechanism.md
    printf 'export const guard = 1\n' > src/guard.test.ts
    git add -A && git commit -q -m "docs: compound — entry plus its mechanism"
    WITH_CODE_SHA="$(git rev-parse HEAD)"
    printf 'b\n' >> src/a.txt
    git add -A && git commit -q -m "fix: something unrelated"
    HEAD_SHA="$(git rev-parse HEAD)"
}
build_fixture
# Non-vacuity: four distinct commits, or the ranges below degenerate and every
# assertion passes against nothing.
[[ "$REVIEWED_SHA" != "$HEAD_SHA" && "$DOCS_ONLY_SHA" != "$WITH_CODE_SHA" ]] \
    || fatal "fixture did not build four distinct commits"

# run_closeout <reviewed> <head> — the extracted /closeout block, nothing else.
run_closeout() {
    ( cd "$scratch/repo" && REVIEWED_SHA="$1" HEAD_SHA="$2" bash -c "$closeout_block" )
}
# run_premerge <checkout-at> <scope-from> [block] — the extracted /pre-merge
# block, run from a checkout at <checkout-at> so the delta ends where the test
# wants it to. The optional third argument is for the mutation self-test at the
# bottom; the live checks pass none and get the real block.
run_premerge() {
    ( cd "$scratch/repo" \
        && git -c advice.detachedHead=false checkout -q "$1" \
        && SCOPE_FROM="$2" bash -c "${3:-$premerge_block}" )
}

out="$(run_closeout "$REVIEWED_SHA" "$HEAD_SHA")"

# The docs-only commit is named as such — one line, no path list.
assert_eq "$DOCS_ONLY_SHA  docs-only /compound entry" \
    "$(grep -F "$DOCS_ONLY_SHA" <<<"$out" || true)" \
    "/closeout names the docs-only compound commit as the expected post-stamp delta"

# The code-carrying one is NOT named that, and its offending path is shown. This
# is the assertion the whole suite is for: the commit whose subject says docs and
# whose content says code.
assert_eq "$WITH_CODE_SHA  'docs: compound' subject, but also touches:" \
    "$(grep -F "$WITH_CODE_SHA" <<<"$out" || true)" \
    "/closeout refuses the docs-only label to a compound commit that ships code"
assert_eq "    src/guard.test.ts" \
    "$(grep -F 'src/guard.test.ts' <<<"$out" || true)" \
    "/closeout shows the path that makes it a code delta, so the menu is answered on the diff"

# The unrelated commit has no `docs: compound` subject and must not be reported
# at all — a classifier that labels every post-stamp commit says nothing.
assert_eq "" "$(grep -cF "$HEAD_SHA" <<<"$out" | grep -v '^0$' || true)" \
    "/closeout reports only compound commits, not every commit in the delta"

# An empty delta produces no output rather than a spurious label.
assert_eq "" "$(run_closeout "$HEAD_SHA" "$HEAD_SHA")" \
    "/closeout prints nothing when the post-stamp delta holds no compound commit"

# --- /pre-merge, both directions --------------------------------------------

# Delta = the docs-only entry alone: this is the re-run /compound handed back,
# and the recommendation must be suppressed so the cycle terminates.
assert_eq "delta is a /compound entry — do not re-recommend /compound; the exit is /closeout" \
    "$(run_premerge "$DOCS_ONLY_SHA" "$REVIEWED_SHA")" \
    "/pre-merge suppresses the /compound recommendation when the delta holds only docs/solutions/ paths"

# Delta reaching the code-carrying commit: the recommendation is NOT suppressed.
# This is the direction the `grep -qv` draft inverted, and it is the silent one —
# a wrong answer here hides a code commit behind a docs-shaped subject.
assert_eq "" "$(run_premerge "$WITH_CODE_SHA" "$REVIEWED_SHA")" \
    "/pre-merge does NOT suppress it when the delta carries a path outside docs/solutions/"

# --- the guard, EXECUTED rather than matched ---------------------------------
#
# The two assertions above always hand the block a good $SCOPE_FROM, so neither
# can tell a working fail-fast guard from a neutered one. Measured: deleting the
# `: "${SCOPE_FROM:?...}"` line outright, or weakening `:?` to `:-`, leaves this
# suite at 14/14 green. That is the third occurrence of the class in
# docs/solutions/testing-patterns/a-planted-term-cannot-discriminate-meaning-2026-09-04.md
# — a contract test asserting what prose MEANS by matching a string in a region.
#
# This assertion is different in kind, and the difference is the whole point.
# The guard makes a checkable claim about TOOL BEHAVIOR: an empty left endpoint
# makes `git diff` compare HEAD against itself, print nothing, and exit 0, so
# every emptiness test downstream reads as a clean pass. CLAUDE.md rule (b)
# routes exactly that to a mechanism, and a subject that can be EXECUTED does
# not need a term planted in it to be checked. So run the block with the
# variable genuinely unset in its own shell and require it to abort.
#
# `env -u` rather than a bare assignment: the block's whole failure mode is that
# a fresh shell never received the Phase 1 assignment, so the test has to
# reproduce absence, not emptiness.
unset_exit=0
unset_out="$( cd "$scratch/repo" \
    && git -c advice.detachedHead=false checkout -q "$WITH_CODE_SHA" \
    && env -u SCOPE_FROM bash -c "$premerge_block" 2>&1 )" || unset_exit=$?
if [[ "$unset_exit" -ne 0 ]]; then
    ok "/pre-merge's block aborts when \$SCOPE_FROM is absent from its own shell"
else
    bad "/pre-merge's block produced a verdict with \$SCOPE_FROM absent" \
        "non-zero exit" "exit 0, output: ${unset_out:-<empty>}"
fi

# Non-vacuity: the abort must come from the guard, not from any other failure.
# Without this, a block that aborted for an unrelated reason would satisfy the
# assertion above and report a guard that is not there (#296's dead-guard shape).
if grep -q 'SCOPE_FROM' <<<"$unset_out"; then
    ok "the abort names \$SCOPE_FROM, so it is the guard firing and not an unrelated failure"
else
    bad "the block aborted without naming \$SCOPE_FROM" \
        "a message naming the variable" "${unset_out:-<empty>}"
fi

# Exit-nonzero-and-names-SCOPE_FROM is not the property either. Move the guard
# line from the top of this block to just after the `fi` that closes the
# verdict, and the block — run with $SCOPE_FROM genuinely absent — prints the
# verdict FIRST (the empty range reads as "nothing outside docs/solutions/") and
# only then reaches the relocated guard and aborts, naming SCOPE_FROM in the
# same breath. Both assertions above go green on that output. #336 was never
# about the exit code; it is that a verdict gets produced from a delta nobody
# read. Match scripts/test-documented-git-commands.sh's sibling $BASE_REF guard
# (its non-vacuity assertion at ~line 1177, "reports no deletions it could not
# have measured") and require the captured output to carry none of the verdict
# text, not only a nonzero exit with the right name in it.
assert_eq "" "$(grep -F 'do not re-recommend /compound' <<<"$unset_out" || true)" \
    "with \$SCOPE_FROM absent the block's output carries no verdict it could not have measured"

# --- the banned shape ---------------------------------------------------------

# Neither block may ask an early-exiting reader for its verdict. Two independent
# reasons, and the ban covers both at once: under `pipefail` the producer dies of
# SIGPIPE and the pipeline reports "no match" from a pipeline that matched; and
# under the ugrep wrapper on a Claude Code shell's PATH, `-q -v` returns the
# inverse answer outright. The behavioral tests above cannot see either — they
# run the blocks under `bash -c`, with real grep and no `pipefail` — which is
# precisely why this one is a text assertion and not another fixture run.
#
# Every spelling GNU and BSD grep accept, taken from test-pipefail-safe-matchers.sh's
# own reach note: clustered short flags in either order, and the long forms.
banned_reader='grep +(-[a-zA-Z]*q[a-zA-Z]*|--quiet|--silent)'
for pair in "pre-merge:$premerge_block" "closeout:$closeout_block"; do
    who="${pair%%:*}"
    body="${pair#*:}"
    # Drop comment lines first: both blocks explain in prose why they avoid the
    # banned form, and a scanner that reads the explanation as the offense would
    # make the explanation unwritable. Full-line comments only, which is all
    # either block carries — a future block with a trailing `# …` on a code line
    # would need this widened.
    code="$(grep -v '^[[:space:]]*#' <<<"$body" || true)"
    hits="$(grep -oE "$banned_reader" <<<"$code" | tr '\n' ' ' | sed 's/ $//' || true)"
    assert_eq "" "$hits" \
        "/$who's block asks no early-exiting reader for its verdict (pipefail-safe, and ugrep-safe)"
done

# Non-vacuity: the pattern must actually match the shape it bans, or the two
# assertions above are a pair of guards that cannot fire (#296). The sample is
# assembled around a printf'd pipe rather than written as one literal, because
# scripts/test-pipefail-safe-matchers.sh scans committed suites for the text
# `| grep -q` and cannot tell a fixture string from a live pipeline — a sample
# that trips a sibling detector is a sample nobody can keep.
# shellcheck disable=SC2016  # the format string is the fixture's literal text, not an expansion
banned_sample="$(printf 'outside=$(git diff --name-only %s grep -qv "^docs/")' '|')"
assert_eq "grep -qv" \
    "$(grep -oE "$banned_reader" <<<"$banned_sample" || true)" \
    "the banned-reader pattern matches the draft that shipped the bug"

# -----------------------------------------------------------------------------

section "self-test: the assertions above can go red"

# #296's lesson — a guard nobody has watched fire is not known to fire. Mutate
# the path literal inside the EXTRACTED block (not a copy of it) so that the
# code path `src/` also counts as a compound path, and confirm the direction
# that matters flips. If this prints "did not flip", the two assertions above
# are passing on something other than the skill's own literal.
mutated="${premerge_block//\^docs\/solutions\/}"
[[ "$mutated" != "$premerge_block" ]] || fatal "the /pre-merge block no longer contains '^docs/solutions/' to mutate"
mutated_verdict="$(run_premerge "$WITH_CODE_SHA" "$REVIEWED_SHA" "$mutated")"
if [[ -n "$mutated_verdict" ]]; then
    ok "widening the path literal flips the code-carrying case to suppressed — the assertion reads the real literal"
else
    bad "mutating the /pre-merge block's path literal changed nothing" \
        "the suppression line" "did not flip"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
