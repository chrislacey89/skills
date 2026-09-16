#!/usr/bin/env bash
# test-lfg-marker.sh — the classification-marker set is declared in four places,
# and until this suite nothing made the four agree.
#
# THE DRIFT CLASS. `/execute` Step 3 creates one classification marker, the
# hook's first clause accepts any of them, Step 6 removes them, and two
# `.gitignore` surfaces keep them out of a commit. Four independent lists of the
# same set, none derived from another. Add a marker to the hook and miss one of
# the other three and the failure is silent in both directions that matter:
#
#   missed in Step 6's `rm -f`  -> the marker outlives the branch's review stamp,
#                                  so the state the post-review edit lock is
#                                  built for — stamped AND markerless — never
#                                  occurs, and clause 1 answers every post-review
#                                  write under a message naming the wrong route.
#   missed in a `.gitignore`    -> the marker is committable, and a committed one
#                                  holds the classification gate open across
#                                  every future branch in that repo.
#
# THE INCIDENT BEHIND IT. Research for `/lfg` (2026-09-16,
# ~/.claude/research/chrislacey89-skills/lfg-skill-2026-09-16.md, § Summary
# "The marker is the expensive part of the small batch") enumerated the touch
# points a third marker would need and found that **nothing today asserts the
# count of markers Step 6 removes**. `scripts/test-post-review-edit-lock.sh` runs
# the hook and the removal line against each other, which closes the first
# direction above; it says nothing about either reserved list, which is the
# second. This suite is the reserved lists' half, plus the exact-equality edge
# the lock suite drives only as a side effect of its round trip.
#
# WHAT IS EQUALITY HERE AND WHAT IS CONTAINMENT, stated because a reader who
# assumes "all four sets are equal" would be assuming something false about two
# of them. The subject is M, the CLASSIFICATION-MARKER set: the `.claude/` paths
# the hook's first clause tests, less the post-review lock's stamp flag, which
# sits in that clause as a stand-down term and is not a marker.
#
#   M == Step 6's `rm -f`            exact, both directions. A marker the hook
#                                    accepts and the removal misses breaks the
#                                    lock; a marker the removal names and the
#                                    hook never tests is dead text.
#   M subset of /init-pipeline § 6   containment only. That block legitimately
#                                    reserves more than M — the lock's two flags
#                                    and `.claude/.ralph-checked`, none of which
#                                    is a classification marker.
#   M subset of this repo's .gitignore   same reason.
#   this repo's .claude/ entries subset of /init-pipeline § 6
#                                    the edge that keeps the two containments
#                                    from being satisfiable by one over-broad
#                                    list: anything this repo learned to ignore
#                                    must also be taught to downstream projects.
#
# WHAT THIS DOES NOT PIN, so nobody over-trusts it. It reads the text four
# skills document; it cannot see whether any downstream project installed that
# text, which is a property of that project and not of this repo. And it says
# nothing about WHICH skill creates which marker — `/tdd` writes one by harness
# preprocessing and `/lfg` will write another, and neither creation site is
# reachable from a marker's name.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() {
    printf '  FAIL %s\n' "$1"
    if [ "$#" -gt 1 ]; then printf '       %s\n' "$2"; fi
    fail=$((fail + 1))
}
fatal() { printf '\nFATAL: %s\n' "$1" >&2; exit 2; }

# --- One reader per shape, called by the live checks and by section 7 --------
#
# Both are pure filters over a file path: they print, and they never abort. A
# helper that calls `fatal` from inside a command substitution exits only the
# subshell and leaves the caller holding an empty string with a summary line
# that still says everything passed (scripts/test-guards-can-fire.sh detector
# C), so emptiness is a value the CALLER decides the meaning of.

# Every fenced block in <file> whose opening fence is ```<lang> and whose body
# matches <regex>, concatenated. An empty <lang> matches a bare ``` fence.
#
# It tracks EVERY fence rather than only the ones it wants. A reader that opened
# on `$0 == "```" lang` alone never enters a ```bash block, so that block's
# CLOSING fence — a bare ``` — reads as the opening of a bare-fenced one, and
# every subsequent block is captured inverted. Toggling on all fences and
# filtering by the recorded info string is what makes an empty <lang> mean
# "a fence with no language" instead of "any ``` line at all".
fenced_blocks() {  # $1 = file, $2 = fence language (may be empty), $3 = ERE
    awk -v lang="$2" -v re="$3" '
        /^```/ {
            if (inblock) { if (info == lang && buf ~ re) printf "%s", buf; inblock = 0 }
            else         { info = substr($0, 4); gsub(/[[:space:]]/, "", info)
                           buf = ""; inblock = 1 }
            next
        }
        inblock { buf = buf $0 "\n" }
    ' "$1"
}

# Every `.claude/<name>` path in stdin, in source order, duplicates kept. Reads
# `"$CLAUDE_PROJECT_DIR/.claude/.tdd-active"` and a bare `.claude/.tdd-active`
# alike, because the four sources write it both ways. Order is preserved because
# section 2 asks which path comes FIRST; callers wanting a set use path_set.
claude_paths() {
    { grep -o '\.claude/\.[A-Za-z0-9._-]*' || true; }
}

path_set() { claude_paths | sort -u; }

# --- Set algebra, one implementation, used live and in the self-test ---------
#
# Both operands are newline-separated and already sorted by claude_paths.
set_equal()  { [ "$1" = "$2" ]; }
# Every line of $1 that is absent from $2; empty output means $1 is a subset.
# Blank lines are dropped so that an empty operand is the empty SET rather than
# a set holding one empty string, which `comm` would otherwise report as a
# difference and which would make an empty-vs-empty comparison say "differs".
set_minus() { comm -23 <(printf '%s\n' "$1" | awk 'NF') <(printf '%s\n' "$2" | awk 'NF'); }
# The members $1 and $2 share.
set_intersect() { comm -12 <(printf '%s\n' "$1" | awk 'NF') <(printf '%s\n' "$2" | awk 'NF'); }

# Lines in <file> that name two or more members of the marker set but not all of
# it. A sentence describing the set is a prose contract with an operative reader,
# and an additive edit to the set leaves every such sentence quietly false — see
# docs/restated-claims.md. Prints `<lineno>:<named…>` per offender, and nothing
# for a line that names one marker (a legitimate reference to a single one) or
# all of them.
partial_enumerations() {  # $1 = file. $markers must already be bound.
    local numbered lineno text named
    while IFS= read -r numbered; do
        [ -n "$numbered" ] || continue
        lineno="${numbered%%:*}"
        text="${numbered#*:}"
        named="$(set_intersect "$(path_set <<<"$text")" "$markers")"
        if [ "$(grep -c . <<<"$named" || true)" -ge 2 ] && ! set_equal "$named" "$markers"; then
            printf '%s:%s\n' "$lineno" "$(tr '\n' ' ' <<<"$named")"
        fi
    done < <(grep -n '\.claude/\.' "$1" || true)
}

# --- The four sources -------------------------------------------------------

hook_block="$(fenced_blocks init-pipeline/SKILL.md bash 'IMPL_PATTERNS')"
[ -n "$hook_block" ] || fatal "no IMPL_PATTERNS hook body found in init-pipeline/SKILL.md — the hook moved or its fence changed"

# Clause 1 is the classification gate: the only `if [ ! -f` line in the body.
# Clause 2, the lock, opens `if [ -f` and is deliberately out of scope here.
clause_one="$(grep -n '^if \[ ! -f' <<<"$hook_block" || true)"
[ -n "$clause_one" ] || fatal "no classification clause (\`if [ ! -f\`) found in the hook body"
[ "$(grep -c '' <<<"$clause_one")" -eq 1 ] || fatal "the hook body holds more than one \`if [ ! -f\` line — clause 1 is no longer identifiable by that anchor"
clause_one="${clause_one#*:}"

# The stand-down flag, read out of /pre-merge's own `touch` rather than typed,
# so a rename there moves this suite's idea of "not a marker" in lockstep.
stamp_block="$(fenced_blocks pre-merge/SKILL.md bash 'review-stamped')"
[ -n "$stamp_block" ] || fatal "no stamp block found in pre-merge/SKILL.md"
stamp_rel="$(path_set <<<"$(sed -n 's|.*touch "\([^"]*\)".*|\1|p' <<<"$stamp_block")")"
[ -n "$stamp_rel" ] || fatal "could not read a .claude/ stamp-flag path out of /pre-merge's touch"
[ "$(grep -c '' <<<"$stamp_rel")" -eq 1 ] || fatal "/pre-merge's block touches more than one .claude/ path — the stand-down flag is ambiguous"

clause_paths="$(path_set <<<"$clause_one")"
markers="$(set_minus "$clause_paths" "$stamp_rel")"

step6_block="$(fenced_blocks execute/SKILL.md bash 'rm -f.*tdd-active')"
[ -n "$step6_block" ] || fatal "no marker-removal block found in execute/SKILL.md Step 6"
step6_markers="$(path_set <<<"$step6_block")"

reserved_block="$(fenced_blocks init-pipeline/SKILL.md '' '\.claude/\.tdd-active')"
[ -n "$reserved_block" ] || fatal "no reserved-marker block found in init-pipeline/SKILL.md § 6"
reserved="$(path_set <<<"$reserved_block")"

[ -f .gitignore ] || fatal "this repo has no .gitignore"
repo_ignored="$(path_set < .gitignore)"

printf 'markers (hook clause 1, less the stand-down flag):\n%s\n' "$markers"
printf 'stand-down flag: %s\n' "$stamp_rel"

# -----------------------------------------------------------------------------

section "1. the four sources are findable and none of them is empty"

# Each FATAL above turns a moved anchor into a loud stop. These rows are the
# other half: an anchor that still matches but yields nothing would sail past
# every comparison below, because two empty sets are equal and the empty set is
# a subset of everything. That is the vacuous pass this family exists to abolish.

for named in "hook clause 1:$markers" \
             "/execute Step 6's rm -f:$step6_markers" \
             "/init-pipeline § 6's reserved list:$reserved" \
             "this repo's .gitignore:$repo_ignored"; do
    label="${named%%:*}"
    value="${named#*:}"
    if [ -n "$value" ]; then
        ok "$label names $(grep -c '' <<<"$value") .claude/ path(s)"
    else
        bad "$label yielded no .claude/ paths" \
            "the extractor still matched its anchor but read nothing out of it."
    fi
done

# -----------------------------------------------------------------------------

section "2. clause 1 still leads with the stand-down flag"

# A convention, not a semantic: the clause is a conjunction of negated tests, so
# reordering it cannot change what the hook decides. It is pinned because the
# term's POSITION is what a reader adding the next marker looks at to decide
# where to put it, and because PRD #369 § Rabbit Holes ("Hook ordering") makes
# leaving it first an explicit condition of this work. This row says the
# condition still holds; it makes no claim that violating it would break the hook.

first_path="$(claude_paths <<<"$clause_one" | sed -n 1p)"
if [ "$first_path" = "$stamp_rel" ]; then
    ok "the first .claude/ path in clause 1 is the stand-down flag $stamp_rel"
else
    bad "clause 1 leads with $first_path, not the stand-down flag $stamp_rel" \
        "PRD #369 § Rabbit Holes requires the stamp flag to stay clause 1's first term."
fi

# -----------------------------------------------------------------------------

section "3. Step 6 removes exactly the markers the hook accepts"

if set_equal "$markers" "$step6_markers"; then
    ok "/execute Step 6's \`rm -f\` names exactly the hook's classification markers"
else
    bad "the hook's marker set and /execute Step 6's \`rm -f\` disagree" \
        "accepted but not removed: $(set_minus "$markers" "$step6_markers" | tr '\n' ' ')
removed but not accepted: $(set_minus "$step6_markers" "$markers" | tr '\n' ' ')"
fi

# -----------------------------------------------------------------------------

section "4. every marker is reserved, downstream and here"

missing_downstream="$(set_minus "$markers" "$reserved")"
if [ -z "$missing_downstream" ]; then
    ok "/init-pipeline § 6 reserves every classification marker"
else
    bad "/init-pipeline § 6 does not reserve every classification marker" \
        "unreserved: $(tr '\n' ' ' <<<"$missing_downstream")
a downstream project scaffolded from that block can commit the marker, which holds the gate open on every future branch there."
fi

missing_here="$(set_minus "$markers" "$repo_ignored")"
if [ -z "$missing_here" ]; then
    ok "this repo's .gitignore ignores every classification marker"
else
    bad "this repo's .gitignore does not ignore every classification marker" \
        "unignored: $(tr '\n' ' ' <<<"$missing_here")"
fi

# The edge that keeps the two containments above from being satisfiable by one
# over-broad reserved list. Without it, `.claude/*` in § 6 would pass both.
untaught="$(set_minus "$repo_ignored" "$reserved")"
if [ -z "$untaught" ]; then
    ok "every .claude/ path this repo ignores is also reserved by /init-pipeline § 6"
else
    bad "this repo ignores .claude/ paths /init-pipeline never teaches a downstream project about" \
        "untaught: $(tr '\n' ' ' <<<"$untaught")"
fi

# -----------------------------------------------------------------------------

section "5. no prose describes the marker set as a proper subset of itself"

# The sites above are LISTS a mechanism reads. These are SENTENCES a person
# reads, and they go stale the same way: "Step 6 removes both markers", "the
# hook checks for either X or Y", a worktree checklist item naming the two
# markers that must be absent. Each is an operative site — a reader acts on it —
# and an additive edit to the set leaves every one of them false while it still
# reads fluently. Nothing counts.
#
# WHAT IS SCANNED, and what is excluded and why, since a scan that silently
# skips a file reports a coverage it does not have:
#
#   scanned    every tracked .md outside the exclusions below, bundled copies
#              included — a stale copy is as readable as a stale source. No
#              bundled copy holds a multi-marker line today, so that half of the
#              selection is untested against the corpus; what actually keeps the
#              copies honest is scripts/sync-skill-references.sh --check.
#   CHANGELOG.md          excluded. A past entry describing the set as it was is
#                         correct as written; rewriting it would be a lie.
#   docs/solutions/       excluded. Incident records, same reason.
#   scripts/              excluded. These suites quote marker names as fixtures
#                         and as controls, deliberately in partial sets.
#
# A line naming exactly one marker is not an offender: a reference to one member
# is not a claim about the set. Only two-or-more-but-not-all is.

prose_files="$(git ls-files '*.md' | grep -v -e '^scripts/' -e '^CHANGELOG\.md$' -e '^docs/solutions/' || true)"
[ -n "$prose_files" ] || fatal "the prose-file scan selected no files at all — the exclusion list or git ls-files changed shape"

scanned=0
offenders=""
while IFS= read -r prose_file; do
    [ -f "$prose_file" ] || continue
    scanned=$((scanned + 1))
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        offenders="$offenders$prose_file:$hit"$'\n'
    done <<<"$(partial_enumerations "$prose_file")"
done <<<"$prose_files"

MIN_PROSE_FILES=20
if [ "$scanned" -ge "$MIN_PROSE_FILES" ]; then
    ok "scanned $scanned markdown file(s) for partial enumerations (floor: $MIN_PROSE_FILES)"
else
    bad "scanned only $scanned markdown file(s), below the floor of $MIN_PROSE_FILES" \
        "the selection stopped matching the repo, so a clean result here means nothing."
fi

if [ -z "$(awk 'NF' <<<"$offenders")" ]; then
    ok "no sentence names part of the marker set as though it were the whole"
else
    bad "prose names some of the classification markers where it means all of them" \
        "$(awk 'NF' <<<"$offenders")
each line names two or more markers but not every one; adding a marker made it false."
fi

# -----------------------------------------------------------------------------

section "6. extra sources name no marker the set does not hold"

# The extension point. `/lfg` does not exist yet; when #371 writes it, this suite
# is invoked with `lfg/SKILL.md` and every `.claude/` path in that skill's fenced
# bash blocks has to be one the four sources above already know about — which is
# how a typo'd `.lfg-actve`, or a marker invented in a skill and registered
# nowhere, becomes a red run instead of a gate that silently never engages.
#
# Known = the markers, the stand-down flag, and everything § 6 reserves; a skill
# may legitimately touch the lock's flags or `.ralph-checked` as well as a marker.
known="$(printf '%s\n%s\n%s\n' "$markers" "$stamp_rel" "$reserved" | sort -u)"

if [ "$#" -eq 0 ]; then
    ok "no extra sources given (invoke as \`$0 <file>…\` to scan one)"
else
    for extra in "$@"; do
        [ -f "$extra" ] || fatal "extra source $extra does not exist"
        found="$(path_set <<<"$(fenced_blocks "$extra" bash '.')")"
        # A file passed here is a claim that it participates in the marker
        # protocol. Zero paths means the claim is false or the fences moved,
        # and either way a silent pass would be the wrong answer.
        if [ -z "$found" ]; then
            bad "$extra names no .claude/ path in any fenced bash block" \
                "it was passed to this suite as a marker-protocol source; if it is not one, stop passing it."
            continue
        fi
        unknown="$(set_minus "$found" "$known")"
        if [ -z "$unknown" ]; then
            ok "$extra names only known markers ($(tr '\n' ' ' <<<"$found"))"
        else
            bad "$extra names .claude/ paths no source declares" \
                "unknown: $(tr '\n' ' ' <<<"$unknown")"
        fi
    done
fi

# -----------------------------------------------------------------------------

section "7. apparatus: the readers read, and the comparisons can fail"

# Every check above is a comparison between two derived sets, and its healthy
# state is silence. scripts/test-guards-can-fire.sh's Prevention #2 is the rule
# followed here: a detector whose healthy state is zero hits needs a self-test
# rather than a floor. So the SAME two readers and the SAME two set operators
# run against planted fixtures whose answers are known — not copies of them,
# because a self-test exercising its own copy proves nothing about the reader the
# suite runs (scripts/test-duplicate-guard-programs.sh).

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

cat > "$scratch/fixture.md" <<'FIXTURE'
Prose that mentions .claude/.decoy-in-prose and must not be read.

```bash
IMPL_PATTERNS=("*.ts")
if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.alpha" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.beta" ]; then
  exit 2
fi
```

```
.claude/.alpha
.claude/.beta
.claude/.gamma
```
FIXTURE

fixture_hook="$(fenced_blocks "$scratch/fixture.md" bash 'IMPL_PATTERNS')"
fixture_clause="$(path_set <<<"$fixture_hook")"
if [ "$fixture_clause" = ".claude/.alpha
.claude/.beta" ]; then
    ok "fenced_blocks + claude_paths read a bash fence and nothing around it"
else
    bad "the bash-fence reader did not read the planted fixture" \
        "expected .alpha and .beta, got: $(tr '\n' ' ' <<<"$fixture_clause")"
fi

fixture_reserved="$(path_set <<<"$(fenced_blocks "$scratch/fixture.md" '' '\.claude/\.gamma')")"
if [ "$fixture_reserved" = ".claude/.alpha
.claude/.beta
.claude/.gamma" ]; then
    ok "…and a fence with no language, selected by its own content"
else
    bad "the bare-fence reader did not read the planted fixture" \
        "expected .alpha .beta .gamma, got: $(tr '\n' ' ' <<<"$fixture_reserved")"
fi

# The prose decoy is the control for both rows above: a reader that scanned the
# whole file rather than the fences would have picked it up and both would still
# have looked plausible.
if [ -z "$(set_minus '.claude/.decoy-in-prose' "$fixture_reserved")" ]; then
    bad "the readers picked up a .claude/ path written outside any fence" \
        "the fixture plants .claude/.decoy-in-prose in prose; a whole-file grep would read it."
else
    ok "…and neither reader picks up a .claude/ path written in prose"
fi

if set_equal "$fixture_clause" "$fixture_clause"; then
    ok "set_equal holds on two identical sets"
else
    bad "set_equal reported two identical sets unequal" "the comparison in section 3 cannot pass."
fi

if set_equal "$fixture_clause" "$fixture_reserved"; then
    bad "set_equal reported a two-member set equal to a three-member superset" \
        "section 3's equality check cannot fail, so it is not checking anything."
else
    ok "…and fails on a set missing a member, which is section 3's failure"
fi

if [ -n "$(set_minus "$fixture_reserved" "$fixture_clause")" ]; then
    ok "set_minus reports the member a containment check is missing"
else
    bad "set_minus found nothing missing from a strict subset" \
        "section 4's containment checks cannot fail."
fi

if [ -z "$(set_minus "$fixture_clause" "$fixture_reserved")" ]; then
    ok "…and reports nothing when containment holds"
else
    bad "set_minus reported a member missing from a superset that holds it" \
        "section 4's containment checks cannot pass."
fi

# --- the partial-enumeration detector, on a set whose answers are known ------
#
# Section 5's healthy state is an empty offender list, which is also what a
# detector reading nothing produces. `$markers` is rebound to a fixture set and
# the SAME function is called, so what is validated is the reader the suite runs
# rather than a copy of it (scripts/test-duplicate-guard-programs.sh).

real_markers="$markers"
markers=".claude/.alpha
.claude/.beta
.claude/.gamma"
cat > "$scratch/prose.md" <<'PROSE'
one member only, which is a reference and not a claim: .claude/.alpha
all three, which is the whole set: .claude/.alpha .claude/.beta .claude/.gamma
two of the three: .claude/.alpha and .claude/.beta
a path that is not a marker at all: .claude/.delta
PROSE
fixture_offenders="$(partial_enumerations "$scratch/prose.md")"
markers="$real_markers"

if [ "$fixture_offenders" = "3:.claude/.alpha .claude/.beta " ]; then
    ok "partial_enumerations flags the two-of-three line and only that line"
else
    bad "partial_enumerations did not read the planted prose fixture" \
        "expected line 3 alone; got: ${fixture_offenders:-nothing}
a single-marker line, a whole-set line, and a non-marker path are all controls here."
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
