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
#
# THE SECOND CONTRACT: ONE WRITER. /pre-merge is the only skill licensed to
# write the marker. /fix-findings (#327) commits fixes that deliberately move
# the head past the stamp and must hand off to a /pre-merge re-run to
# re-stamp; a skill that stamped its own fixes would certify as reviewed the one
# commit nothing independent read, and #292's provenance fix — the stamp records
# the SHA a review actually read — would be bypassed in silence. Nothing else in
# the repo would notice a second writer appearing, so the last section below
# greps every other SKILL.md for the writer template.

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
reader_line="$(grep "sed -n 's/[^']*reviewed-at" "$closeout_skill" | head -1 || true)"

# The sed script /closeout Step 2 pipes the PR body through.
reader_expr="$(printf '%s' "$reader_line" \
    | grep -o "sed -n 's/[^']*reviewed-at[^']*'" \
    | sed "s/^sed -n '//; s/'\$//" || true)"

# /pre-merge Phase 1 step 4 reads the same marker to decide its scope (#347).
# Two readers of one marker are a drift pair; this pulls the second one out the
# same way and § below asserts the two sed scripts are byte-identical.
premerge_reader_line="$(grep "sed -n 's/[^']*reviewed-at" "$premerge_skill" | head -1 || true)"
premerge_reader_expr="$(printf '%s' "$premerge_reader_line" \
    | grep -o "sed -n 's/[^']*reviewed-at[^']*'" \
    | sed "s/^sed -n '//; s/'\$//" || true)"

# Whatever /closeout pipes the sed output into — everything past the sed
# script's closing quote, minus the trailing ")" of the command substitution.
reader_filter="$(printf '%s' "$reader_line" \
    | sed "s/.*'[[:space:]]*|[[:space:]]*//; s/)[[:space:]]*\$//")"

# The marker template /pre-merge Phase 4 substitutes the reviewed SHA into.
# Scoped to Phase 4, where the writer lives. Since #347 the skill also carries a
# READER of the marker in Phase 1 step 4 — the same sed as /closeout's — and an
# unscoped first-match grep picked that regex up as the template, which made
# every round-trip check below run the reader against itself.
writer_template="$(awk '/^### Phase 4/ { on = 1 } on' "$premerge_skill" | grep -o '<!-- reviewed-at: [^ ]* -->' | head -1 || true)"

# The second reader: the same extraction, inside the git guardrail hook. Pulled
# out with the same two expressions used on /closeout above, so a reader that
# stops having this shape fails the FATAL below rather than passing vacuously.
guard_line="$(grep "sed -n 's/[^']*reviewed-at" "$guard_script" | head -1 || true)"

guard_expr="$(printf '%s' "$guard_line" \
    | grep -o "sed -n 's/[^']*reviewed-at[^']*'" \
    | sed "s/^sed -n '//; s/'\$//" || true)"

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

section "exactly one skill writes the stamp"

# The template is extracted above from pre-merge/SKILL.md, so this searches for
# whatever that file actually declares rather than for a restated literal. A
# fixed-string search (-F) because the template contains no regex metacharacters
# by design and a future one should not silently become a pattern.
#
# Scoped to */SKILL.md: a skill's reference files are prose about the marker
# (closeout/SKILL.md's own reader line lives in the skill body and is matched by
# the reader extraction above, not here). What must stay unique is the WRITER —
# the substituted template with a real 40-character SHA in it, and the
# unsubstituted template it comes from.
writers="$(grep -lF "$writer_template" -- */SKILL.md | sort || true)"
assert_eq "pre-merge/SKILL.md" "$writers" \
    "the writer template appears in pre-merge/SKILL.md and no other SKILL.md"

# The same check one level down: no skill emits a *substituted* marker either,
# which is what a second writer would most plausibly look like — a literal
# 40-hex stamp pasted into a skill body rather than the placeholder form.
substituted="$(grep -lE '<!-- reviewed-at: [0-9a-f]{40} -->' -- */SKILL.md | sort || true)"
assert_eq "" "$substituted" \
    "no SKILL.md carries a substituted 40-character marker"

# The sidecar stamp backend (#521) has its own writer, `sidecar.sh stamp
# write`, and the same rule holds for it: /pre-merge is the only skill whose
# body invokes it. Matched as an invocation — the verb after a sidecar.sh path
# or a variable holding one, braced or not, quoted or not (#533: `"${SC}"` and
# a bare `$SC` slipped past a quoted-only match) — so prose that names "the
# stamp write" in passing does not count, and a second writer does whatever it
# calls and spells its variable.
sidecar_writers="$(grep -lE '(sidecar\.sh"?|"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?)[[:space:]]+stamp[[:space:]]+write' -- */SKILL.md | sort || true)"
assert_eq "pre-merge/SKILL.md" "$sidecar_writers" \
    "sidecar.sh stamp write is invoked in pre-merge/SKILL.md and no other SKILL.md"

# -----------------------------------------------------------------------------

section "the step that re-stamps names a mode /pre-merge actually defines"

# THE DRIFT THIS CATCHES. /fix-findings (#327) shipped its entire handoff — five
# sentences in its own body, two rows in SYSTEM-OVERVIEW, a clause in
# /init-pipeline's hook rationale, this file's own header, and both of
# /pre-merge's own next-step menu labels — terminating in a "/pre-merge delta
# pass over everything past the stamp." No such thing existed. § Modes defines
# three modes; none takes a range, none scopes itself to what is past a stamp,
# and `git grep "delta pass"` at the branch point was empty, so the term was
# invented by the same change that depended on it. The single-writer contract
# above is only worth what the handoff that closes it is worth, and a handoff
# terminating in a mode nobody implemented closes nothing — which is what makes
# this suite's business.
#
# Both halves of the vocabulary are derived, never typed here: the mode names
# come out of /pre-merge § Modes, and the two pass-qualifiers /fix-findings is
# entitled to use for its OWN passes come out of its § Cap sentence.

premerge_modes="$(sed -n '/^## Modes$/,/^## When to Use$/p' "$premerge_skill" \
    | sed -n 's/^- \*\*\([A-Za-z][A-Za-z-]*\)-mode.*/\1/p' \
    | tr '[:upper:]' '[:lower:]' | sort -u)"
if [[ -z "$premerge_modes" ]]; then
    printf 'FATAL: no "- **X-mode**" bullets found under %s § Modes\n' "$premerge_skill" >&2
    exit 2
fi

fixfindings_skill="$repo_root/fix-findings/SKILL.md"
# /fix-findings' § Cap sentence is the one place its own two passes are named.
own_passes="$(sed -n 's/.*One \([a-z]*\) pass and one \([a-z]*\) pass per finding.*/\1\n\2/p' "$fixfindings_skill" | sort -u)"
if [[ -z "$own_passes" ]]; then
    printf 'FATAL: no "One <x> pass and one <y> pass per finding" sentence found in %s\n' "$fixfindings_skill" >&2
    exit 2
fi

allowed_qualifiers="$(printf '%s\n%s\n' "$premerge_modes" "$own_passes" | sort -u)"
printf 'modes (pre-merge/SKILL.md):   %s\n' "$(tr '\n' ' ' <<<"$premerge_modes")"
printf 'own passes (fix-findings):    %s\n' "$(tr '\n' ' ' <<<"$own_passes")"

# unresolved <noun-alternation> <text> — every "<qualifier> pass" (and, where
# the caller asks for it, "<qualifier>-mode") in <text> that is neither a
# /pre-merge mode nor one of /fix-findings' own passes. Both boundary classes
# are load-bearing: without the trailing one "disable-model-invocation" reads as
# a "-mode" and "password" as a "pass", and without the leading one
# "**Reviewer-mode**" yields the qualifier "eviewer". The text is lowercased and
# space-padded first so both boundaries can be plain character classes.
unresolved() {
    local nouns="$1" qualifier out=""
    while IFS= read -r qualifier; do
        [[ -n "$qualifier" ]] || continue
        grep -qxF "$qualifier" <<<"$allowed_qualifiers" || out+="$qualifier"$'\n'
    done < <(printf ' %s ' "$2" | tr '[:upper:]' '[:lower:]' \
        | grep -oE "[^a-z-][a-z][a-z-]*[ -]($nouns)[^a-z-]" \
        | sed -E "s/^.//; s/[ -]($nouns)[^a-z-]\$//" | sort -u)
    printf '%s' "$out"
}

# The three files the drift has to pass through to reach a reader, folded to one
# line each: these paragraphs are hard-wrapped, and the phrase straddles line
# breaks. A trailing space keeps the boundary class satisfied at end of text.
fold() { tr '\n' ' ' < "$1"; }

# Detector 1 — a pass or mode hung directly off a skill mention, which is the
# form the invented term took in every file but /fix-findings' own body:
# "`/pre-merge` delta pass". Immediate adjacency only; "/pre-merge runs in one
# of three modes" and "acting on the previous pass" are ordinary prose and must
# not fire.
attributed=""
for f in "$repo_root"/SYSTEM-OVERVIEW.md "$repo_root"/*/SKILL.md; do
    hits="$(fold "$f" | grep -oE '/(pre-merge|fix-findings)`? +[a-z][a-z-]*[ -](pass|mode)[^a-z-]' || true)"
    [[ -n "$hits" ]] || continue
    bad="$(unresolved 'pass|mode' "$hits")"
    [[ -z "$bad" ]] || attributed+="${f#"$repo_root"/}: $(tr '\n' ' ' <<<"$bad")"$'\n'
done
assert_eq "" "$attributed" \
    "no skill hangs a pass or mode off /pre-merge or /fix-findings that neither defines"

# Detector 2 — /fix-findings' own body, where the term also appears with no
# skill name beside it ("The delta pass is the review."). Scoped to that one
# file because "<word> pass" is ordinary English elsewhere — pre-merge/SKILL.md
# alone carries "second pass", "focused pass", "previous pass", none of which
# names a mode. In this file every such noun is a procedure step, so the
# vocabulary is closed and checkable. Detectors 2 and 3 ask about "pass" only:
# "<determiner> mode" is unavoidable English ("no mode takes a range", "which
# mode you are in"), and mode names are already covered by detector 1, where the
# skill mention beside them makes the window tight enough to be decidable.
assert_eq "" "$(unresolved 'pass' "$(fold "$fixfindings_skill")" | tr '\n' ' ' | sed 's/ $//')" \
    "/fix-findings names no pass but the two it defines"

# Detector 3 — the paragraphs elsewhere that route a reader INTO /fix-findings:
# SYSTEM-OVERVIEW's handoff row and default-map bullet, and /pre-merge's own two
# next-step menu labels. Those labels are where the reader meets the term first,
# and they name /fix-findings without naming /pre-merge beside the pass, so
# detector 1 cannot see them. Paragraph-scoped (awk RS="") to keep the window
# tight enough that ordinary "second pass" prose stays out of it.
routing=""
for f in "$repo_root"/SYSTEM-OVERVIEW.md "$repo_root"/*/SKILL.md; do
    paras="$(awk 'BEGIN { RS = "" } /\/fix-findings/ { gsub(/\n/, " "); print }' "$f")"
    [[ -n "$paras" ]] || continue
    bad="$(unresolved 'pass' "$paras")"
    [[ -z "$bad" ]] || routing+="${f#"$repo_root"/}: $(tr '\n' ' ' <<<"$bad")"$'\n'
done
assert_eq "" "$routing" \
    "no paragraph routing a reader into /fix-findings names an unresolvable pass"

# Detector 4 — the positive claim the handoff rests on, as of #347: author-mode
# reads `$SCOPE_FROM...HEAD`, where Phase 1 step 4 sets `$SCOPE_FROM` from the
# stamp. Before #347 this detector pinned the opposite ("author-mode still
# reviews the whole branch, so the re-run needs no range"), and that pin was
# correct for the text it guarded: /fix-findings' handoff said no range existed,
# and it did not. #347 built the scope, so the pin follows the text. Read out of
# Phase 3's author-mode bullet rather than restated.
# shellcheck disable=SC2016  # both the pattern and the expected value are the skill's literal text — `$SCOPE_FROM` and the backticks are markdown being matched, not expansions
author_diff="$(grep -oE '^- \*\*Author-mode\*\* — the local `git diff "[^"]*"`' "$premerge_skill" | head -1 || true)"
# shellcheck disable=SC2016
assert_eq '- **Author-mode** — the local `git diff "$SCOPE_FROM...HEAD"`' "$author_diff" \
    "author-mode reads \$SCOPE_FROM...HEAD — the stamp decides the scope, so the re-run needs no range handed to it"

# The variable the bullet names has to be the one Phase 1 step 4 assigns, and it
# may take exactly three values: the base ref (whole branch), the stamped SHA
# (delta), and HEAD (a history-only rewrite of the reviewed tree, nothing to
# review — #566). Any fourth assignment is a scope nobody specified. The match
# takes unquoted values too: #566's first draft wrote `SCOPE_FROM=HEAD`, which a
# quotes-only pattern could not see.
scope_assignments="$(grep -oE '^ *SCOPE_FROM=("[^"]*"|[^ ;]+)' "$premerge_skill" | sed 's/^ *//' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
# shellcheck disable=SC2016
assert_eq 'SCOPE_FROM="$BASE_REF" SCOPE_FROM="$REVIEWED_SHA" SCOPE_FROM="HEAD"' "$scope_assignments" \
    "SCOPE_FROM is assigned from exactly the base ref, the stamped SHA, and HEAD"

# Two readers, one marker. /pre-merge's Phase 1 reader and /closeout's Step 2
# reader must be the same sed script, or the scope decision and the merge gate
# can disagree about which SHA was reviewed.
assert_eq "$reader_expr" "$premerge_reader_expr" \
    "pre-merge Phase 1 step 4 reads the stamp with closeout's exact sed script (two readers, byte-identical)"

# -----------------------------------------------------------------------------

section "/closeout Step 2 shows the same delta on either stamp backend"

# #521: on the sidecar backend /closeout reads the stamp with `stamp read` and
# the head from the branch's upstream, then runs the same delta commands and
# the same prompt. The claim is that nothing below the read can tell the
# backends apart. So the read block and the delta block are both extracted from
# closeout/SKILL.md and run twice against one fixture: once with no sidecar and
# a `gh` stub serving the PR-body marker and headRefOid, once with a sidecar
# stamp and no `gh` at all. The two delta readouts must be identical, and must
# name the post-stamp commits.

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
sidecar_sh="$repo_root/init-pipeline/scripts/sidecar.sh"
read_block="$(awk '
    /^```bash$/ { buf = ""; inblock = 1; next }
    inblock && /^```$/ { if (buf ~ /stamp read/ && buf ~ /headRefOid/) { printf "%s", buf; exit } inblock = 0; next }
    inblock { buf = buf $0 "\n" }
' "$closeout_skill")"
delta_block="$(awk '
    /^  ```bash$/ { buf = ""; inblock = 1; next }
    inblock && /^  ```$/ { if (buf ~ /git diff --stat "\$REVIEWED_SHA"/) { printf "%s", buf; exit } inblock = 0; next }
    inblock { sub(/^  /, ""); buf = buf $0 "\n" }
' "$closeout_skill")"
if [[ -z "$read_block" || -z "$delta_block" ]]; then
    printf 'FATAL: no stamp read block or no delta block found in %s\n' "$closeout_skill" >&2
    exit 2
fi
read_block="${read_block//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
read_block="${read_block//<number>/1}"

fx="$(mktemp -d)"
trap 'rm -rf "$fx"' EXIT
export GIT_CONFIG_GLOBAL="$fx/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$GIT_CONFIG_GLOBAL" user.name "Currency Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "currency@example.com"
export SKILL_KIT_RESEARCH_ARCHIVE="$fx/archive"
(
    set -e
    git init -q -b main "$fx/origin.git" --bare
    git init -q -b main "$fx/proj"
    cd "$fx/proj"
    git commit -q --allow-empty -m base
    git switch -q -c feature
    printf 'reviewed\n' > reviewed.txt && git add reviewed.txt && git commit -q -m 'reviewed work'
    git rev-parse HEAD > "$fx/stamp_sha"
    printf 'late\n' > late.txt && git add late.txt && git commit -q -m 'fix-up after the review'
    git remote add origin "$fx/origin.git"
    git push -q -u origin feature 2>/dev/null
)
# The subshell's status is not checked: `set -e` is suppressed under `||`, so
# the fixture's RESULT is checked instead — three commits, the stamp two back
# from the head, and an upstream that names the head.
stamp_sha="$(cat "$fx/stamp_sha" 2>/dev/null || true)"
fx_head="$(git -C "$fx/proj" rev-parse HEAD 2>/dev/null || true)"
if [[ "$(git -C "$fx/proj" rev-list --count HEAD 2>/dev/null)" != 3 \
      || "$stamp_sha" != "$(git -C "$fx/proj" rev-parse HEAD~1 2>/dev/null)" \
      || "$fx_head" != "$(git -C "$fx/proj" rev-parse '@{u}' 2>/dev/null)" ]]; then
    printf 'FATAL: could not build the closeout fixture\n' >&2
    exit 2
fi

mkdir -p "$fx/bin"
cat > "$fx/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$fx/gh.log"
case "\$*" in
    "pr view 1 --json body -q .body") printf '## Summary\n\n<!-- reviewed-at: $stamp_sha -->\n' ;;
    "pr view 1 --json headRefOid -q .headRefOid") printf '%s\n' "$fx_head" ;;
    *) exit 9 ;;
esac
STUB
chmod +x "$fx/bin/gh"

# closeout_readout <sidecar-root> — run the read block, then the delta block,
# in the fixture; print the two SHAs and the delta readout.
closeout_readout() {
    (cd "$fx/proj" && PATH="$fx/bin:$PATH" SKILL_KIT_SIDECAR_ROOT="$1" bash -c "
        $read_block
        printf 'reviewed=%s head=%s\n' \"\$REVIEWED_SHA\" \"\$HEAD_SHA\"
        $delta_block" 2>&1)
}

: > "$fx/gh.log"
github_readout="$(closeout_readout "$fx/no-sidecars")"
(cd "$fx/proj" && SKILL_KIT_SIDECAR_ROOT="$fx/sidecars" bash "$sidecar_sh" init --name currency --mode guest \
    --write sidecar --in-tree-path none --no-migrate-archive >/dev/null 2>&1 \
    && SKILL_KIT_SIDECAR_ROOT="$fx/sidecars" bash "$sidecar_sh" stamp write feature "$stamp_sha" >/dev/null 2>&1) \
    || { printf 'FATAL: could not stamp the closeout fixture in a sidecar\n' >&2; exit 2; }
: > "$fx/gh.log"
sidecar_readout="$(closeout_readout "$fx/sidecars")"

assert_eq "reviewed=$stamp_sha head=$fx_head" "$(head -1 <<<"$github_readout")" \
    "PR-body backend: the read block yields the stamped SHA and the PR head"
assert_eq "$github_readout" "$sidecar_readout" \
    "sidecar backend: the read and delta readout are identical to the PR-body backend's"
case "$sidecar_readout" in
    *late.txt*"fix-up after the review"*) assert_eq ok ok "the delta readout names the post-review commit and its file" ;;
    *) assert_eq "names late.txt and the fix-up commit" "$sidecar_readout" "the delta readout names the post-review commit and its file" ;;
esac
assert_eq "" "$(cat "$fx/gh.log")" "sidecar backend: the read never called gh"
assert_eq "" "$(git -C "$fx/proj" status --porcelain)" "sidecar backend: the project tree is untouched"

section "/closeout Step 3 clears the merged PR's stamp, not the current checkout's"

# `gh pr merge --delete-branch` deletes the local branch and, in a plain
# checkout, switches to the base first, so `git branch --show-current` names
# the base by the time the clear runs and the merged branch's stamp survives to
# be read by a later branch reusing the name. The block is extracted from
# closeout/SKILL.md and run AFTER the fixture has switched to base and dropped
# the feature branch, with a `gh` stub that serves the PR's head ref. The
# stamp written above for `feature` must be there before and gone after.
clear_block="$(awk '
    /^```bash$/ { buf = ""; inblock = 1; next }
    inblock && /^```$/ { if (buf ~ /stamp clear/) { printf "%s", buf; exit } inblock = 0; next }
    inblock { buf = buf $0 "\n" }
' "$closeout_skill")"
if [[ -z "$clear_block" ]]; then
    printf 'FATAL: no stamp clear block found in %s\n' "$closeout_skill" >&2
    exit 2
fi
clear_block="${clear_block//<this skill\'s directory>\/references\/sidecar.sh/$sidecar_sh}"
clear_block="${clear_block//<number>/1}"

cat > "$fx/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$*" in
    "pr view 1 --json headRefName -q .headRefName") printf 'feature\n' ;;
    *) exit 9 ;;
esac
STUB
(cd "$fx/proj" && git switch -q main && git branch -q -D feature) \
    || { printf 'FATAL: could not switch the closeout fixture to base\n' >&2; exit 2; }
assert_eq main "$(git -C "$fx/proj" branch --show-current)" "fixture: the checkout is on base, as after gh pr merge --delete-branch"
assert_eq "$stamp_sha" "$(cd "$fx/proj" && SKILL_KIT_SIDECAR_ROOT="$fx/sidecars" bash "$sidecar_sh" stamp read feature)" \
    "control: the merged branch's stamp exists before the clear block runs"
(cd "$fx/proj" && PATH="$fx/bin:$PATH" SKILL_KIT_SIDECAR_ROOT="$fx/sidecars" CLAUDE_PROJECT_DIR="$fx/proj" bash -c "$clear_block" >/dev/null 2>&1)
assert_eq "" "$(cd "$fx/proj" && SKILL_KIT_SIDECAR_ROOT="$fx/sidecars" bash "$sidecar_sh" stamp read feature)" \
    "after the clear block, run on base, the merged branch's stamp is gone"

section "/closeout Steps 2 and 3 abort on a failed backend rather than taking the gh path"

# #530: `backend stamp` that exits nonzero prints nothing, and a block written
# as `if [ "$(backend)" = sidecar ]; then … else <gh> fi` reads that as github.
# Both blocks run under a sidecar root whose only sidecar.json is corrupt, so
# `backend` really refuses; each must exit 1 without calling gh at all.
mkdir -p "$fx/broken/broken"
printf '{"keys": [' > "$fx/broken/broken/sidecar.json"
cat > "$fx/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$fx/gh.log"
case "\$*" in
    "pr view 1 --json body -q .body") printf '<!-- reviewed-at: $stamp_sha -->\n' ;;
    "pr view 1 --json headRefOid -q .headRefOid") printf '%s\n' "$fx_head" ;;
    "pr view 1 --json headRefName -q .headRefName") printf 'feature\n' ;;
    *) exit 9 ;;
esac
STUB
assert_eq 1 "$(cd "$fx/proj" && SKILL_KIT_SIDECAR_ROOT="$fx/broken" bash "$sidecar_sh" backend stamp >/dev/null 2>&1; echo $?)" \
    "fixture precondition: backend stamp exits 1 under the broken root"
# shellcheck disable=SC2016  # the appended line runs inside `bash -c`, where $REVIEWED_SHA is the block's own
reviewed_probe='printf "reviewed=%s\n" "$REVIEWED_SHA"'
for blk in read clear; do
    if [[ "$blk" == read ]]; then body="$read_block"$'\n'"$reviewed_probe"; else body="$clear_block"; fi
    : > "$fx/gh.log"
    blk_rc=0
    blk_out="$(cd "$fx/proj" && PATH="$fx/bin:$PATH" SKILL_KIT_SIDECAR_ROOT="$fx/broken" CLAUDE_PROJECT_DIR="$fx/proj" \
        bash -c "$body" 2>&1)" || blk_rc=$?
    assert_eq 1 "$blk_rc" "failed backend: the $blk block exits 1"
    assert_eq "" "$(cat "$fx/gh.log")" "failed backend: the $blk block never called gh"
    case "$blk_out" in
        *reviewed=*) assert_eq "no reviewed= line" "$blk_out" "failed backend: the $blk block stopped before its caller's next line" ;;
        *"backend stamp failed"*) assert_eq ok ok "failed backend: the $blk block names the failure on stderr" ;;
        *) assert_eq "backend stamp failed ..." "$blk_out" "failed backend: the $blk block names the failure on stderr" ;;
    esac
done

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
