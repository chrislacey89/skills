#!/usr/bin/env bash
# test-review-currency-marker.sh — cross-skill contract test for the
# `<!-- reviewed-at: <sha> -->` review-currency stamp.
#
# /pre-merge Phase 4 WRITES the marker into the PR body. /closeout Step 2 READS
# it back and compares it to `headRefOid` before merging, and the git guardrail
# hook performs the SAME read at `gh pr merge`, so a merge that never goes
# through /closeout cannot skip it (#327, Lock 2). Three files, one string, and
# no shared definition of the string's shape — which is exactly the drift class
# docs/solutions/architecture-decisions/staleness-gate-intermediate-writers-2026-08-06.md
# named under Prevention → Code-level. Two readers make it worse than the
# original two-party case: a change made to one reader and not the other leaves
# the two gates disagreeing about the same PR, and neither of them wrong on its
# own terms.
#
# The contract is: the marker carries a full 40-character OID. `headRefOid` is
# always 40 characters, so a short SHA reaching the marker would parse fine and
# then compare unequal forever — /closeout would report divergence on a PR whose
# head never moved. A gate that cries wolf on an unchanged commit is a gate that
# gets clicked through.
#
# These tests extract the real sed script from closeout/SKILL.md and the real
# marker template from pre-merge/SKILL.md rather than restating either. That is
# the point: the suite fails when either half drifts from the other, which a
# hand-copied regex could not detect.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
closeout_skill="$repo_root/closeout/SKILL.md"
premerge_skill="$repo_root/pre-merge/SKILL.md"
guard_script="$repo_root/git-guardrails-claude-code/scripts/block-dangerous-git.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

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

# --- Pull both halves of the contract out of the skills themselves -----------

# The full reader line from /closeout Step 2, which this suite splits into the
# sed script and the filter applied after it.
reader_line="$(grep "sed -n 's/[^']*reviewed-at" "$closeout_skill" | head -1)"

# The sed script /closeout Step 2 pipes the PR body through.
reader_expr="$(printf '%s' "$reader_line" \
    | grep -o "sed -n 's/[^']*reviewed-at[^']*'" \
    | sed "s/^sed -n '//; s/'\$//")"

# Whatever /closeout pipes the sed output into — everything past the sed
# script's closing quote, minus the trailing ")" of the command substitution.
reader_filter="$(printf '%s' "$reader_line" \
    | sed "s/.*'[[:space:]]*|[[:space:]]*//; s/)[[:space:]]*\$//")"

# The marker template /pre-merge Phase 4 substitutes the reviewed SHA into.
writer_template="$(grep -o '<!-- reviewed-at: [^ ]* -->' "$premerge_skill" | head -1)"

# The second reader: the same extraction, inside the git guardrail hook. Pulled
# out with the same two expressions used on /closeout above, so a reader that
# stops having this shape fails the FATAL below rather than passing vacuously.
guard_line="$(grep "sed -n 's/[^']*reviewed-at" "$guard_script" | head -1)"

guard_expr="$(printf '%s' "$guard_line" \
    | grep -o "sed -n 's/[^']*reviewed-at[^']*'" \
    | sed "s/^sed -n '//; s/'\$//")"

guard_filter="$(printf '%s' "$guard_line" \
    | sed "s/.*'[[:space:]]*|[[:space:]]*//; s/)[[:space:]]*\$//")"

if [[ -z "$reader_expr" ]]; then
    printf 'FATAL: no sed -n reviewed-at extraction found in %s\n' "$closeout_skill" >&2
    printf '       Either the reader moved or its shape changed; update this suite with it.\n' >&2
    exit 2
fi
if [[ -z "$writer_template" ]]; then
    printf 'FATAL: no reviewed-at marker template found in %s\n' "$premerge_skill" >&2
    printf '       Either the writer moved or its shape changed; update this suite with it.\n' >&2
    exit 2
fi
if [[ -z "$guard_expr" ]]; then
    printf 'FATAL: no sed -n reviewed-at extraction found in %s\n' "$guard_script" >&2
    printf '       The guard hook is the second reader of this marker (#327, Lock 2). If the\n' >&2
    printf '       refusal was removed on purpose, delete this section; if not, it has drifted\n' >&2
    printf '       into a shape this suite can no longer compare.\n' >&2
    exit 2
fi

printf 'reader (closeout/SKILL.md):   %s\n' "$reader_expr"
printf 'reader filter:                %s\n' "$reader_filter"
printf 'reader (guardrail hook):      %s\n' "$guard_expr"
printf 'reader filter (guardrail):    %s\n' "$guard_filter"
printf 'writer (pre-merge/SKILL.md):  %s\n' "$writer_template"

# read_marker <<< body — run /closeout's own extraction over a PR body on stdin.
# The `| tail -1` is the one part of the reader not expressible inside the sed
# script, so it is replicated here rather than extracted. That replication is a
# restatement, which is exactly what this suite exists to avoid — so the first
# assertion below pins $reader_filter against it. Without that pin, switching
# the skill to `head -1` would leave the "newer stamp wins" test green while
# describing the opposite reader, and a stale SHA is the dangerous answer.
read_marker() { sed -n "$reader_expr" | tail -1; }

# pr_body <marker-line>... — a realistic PR body with prose either side of the
# stamp, so the reader is exercised against a whole body rather than one line.
# The bare "<!-- -->" on the first line is a deliberate decoy: real PR bodies
# contain other HTML comments, and the reader must not latch onto them.
#
# shellcheck disable=SC2016  # backticks here are literal markdown, not command substitution
pr_body() {
    printf '## Summary\n\nSome PR description with a <!-- --> comment nearby.\n\n## Review Currency\n\n'
    printf '%s\n' "$@"
    printf 'Reviewed by `/pre-merge`.\n\n## Test plan\n\n- ran it\n'
}

full_sha='0123456789abcdef0123456789abcdef01234567'   # 40 hex chars, like headRefOid

# -----------------------------------------------------------------------------

section "the reader is fully accounted for"

assert_eq 'tail -1' "$reader_filter" \
    "the post-sed filter is still 'tail -1', which read_marker replicates"

# -----------------------------------------------------------------------------

section "both readers of the marker extract it the same way"

# The guardrail hook and /closeout read the same stamp on the same PR at
# almost the same moment. If the two expressions diverge, one gate reports a
# stale stamp and the other reports none, on a PR neither of them is wrong
# about in isolation — and the divergence is invisible in both files, because
# each one reads correctly on its own.
#
# Byte equality, not equivalence: this suite cannot decide whether two
# different regexes accept the same language, so it requires the cheaper
# property it can actually check. Every round-trip assertion below then
# covers both readers, because they are the same string.
assert_eq "$reader_expr" "$guard_expr" \
    "the guardrail hook's sed is byte-identical to /closeout's"
assert_eq "$reader_filter" "$guard_filter" \
    "the guardrail hook applies the same post-sed filter"

# -----------------------------------------------------------------------------

section "writer declares a full-SHA placeholder"

# Also covers the substitution itself: an unsubstituted template still contains
# the literal "<full-sha>" and cannot equal the expected marker, so a swapped or
# renamed placeholder fails here rather than surfacing later as a parse miss.
marker="${writer_template//<full-sha>/$full_sha}"
assert_eq "<!-- reviewed-at: $full_sha -->" "$marker" \
    "the <full-sha> placeholder substitutes into a well-formed marker"

# -----------------------------------------------------------------------------

section "round trip: what the writer emits is what the reader extracts"

extracted="$(pr_body "$marker" | read_marker)"
assert_eq "$full_sha" "$extracted" "reader returns exactly the SHA the writer wrote"
assert_eq 40 "${#extracted}" "extracted value is a full 40-character OID"

# -----------------------------------------------------------------------------

section "short SHAs are rejected, not silently accepted"

# A short SHA can never equal a 40-character headRefOid. Rejecting it routes
# /closeout to the graceful "no stamp found" branch instead of the "divergence"
# branch, which interrupts the user over a commit that never moved.
for width in 7 8 12 39; do
    short_marker="${writer_template//<full-sha>/${full_sha:0:$width}}"
    extracted="$(pr_body "$short_marker" | read_marker)"
    assert_eq "" "$extracted" "a ${width}-character SHA is not accepted as a stamp"
done

# -----------------------------------------------------------------------------

section "over-long and non-hex markers are rejected"

long_marker="${writer_template//<full-sha>/${full_sha}f}"   # 41 hex chars
extracted="$(pr_body "$long_marker" | read_marker)"
assert_eq "" "$extracted" "a 41-character value is rejected rather than truncated to 40"

junk_marker="${writer_template//<full-sha>/not-a-sha}"
extracted="$(pr_body "$junk_marker" | read_marker)"
assert_eq "" "$extracted" "a non-hex value is rejected"

extracted="$(pr_body 'No stamp here at all.' | read_marker)"
assert_eq "" "$extracted" "a body with no marker yields the empty 'no stamp found' result"

# -----------------------------------------------------------------------------

section "a duplicated stamp resolves to the newer SHA, never the stale one"

# /pre-merge specifies exactly one stamp per PR, but if a second is ever
# appended the reader must not settle on the earlier — a stale SHA is the
# dangerous answer, because it reports divergence that was already reviewed.
newer_sha='fedcba9876543210fedcba9876543210fedcba98'
stale_marker="$marker"
newer_marker="${writer_template//<full-sha>/$newer_sha}"
extracted="$(pr_body "$stale_marker" "$newer_marker" | read_marker)"
assert_eq "$newer_sha" "$extracted" "the last stamp in the body wins"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
