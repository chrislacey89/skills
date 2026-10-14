#!/usr/bin/env bash
# test-excavate-entry-contract.sh — /excavate must write docs/solutions/ entries
# in the format /compound defines, and the fields the /research reader consumes
# must still exist in both.
#
# THE DRIFT CLASS. Two skills write the same artifact. /compound Phase 3
# (compound/SKILL.md, `### Phase 3: Write the Solution Document`) defines the
# docs/solutions/ entry format; /excavate (excavate/SKILL.md, Step 7,
# `### 7. Draft the entries and confirm (HITL, per item)`) documents it a
# second time for the entries it writes. A key added, renamed, or removed in
# /compound's template silently leaves /excavate's entries malformed, and
# nothing fails: /research Phase 3's staleness check reads `volatility` and
# `date` from every entry, so a malformed entry is read wrongly or not at all
# by a skill that never ran the writer. The same applies to the category enum,
# the filename convention, and the fix-commit grep that /excavate shares with
# /triage-issue.
#
# THE INCIDENT. None yet — pre-emptive, per CLAUDE.md § Commands a skill
# documents rule (b), issue #402. The nearest precedent is
# test-compound-clustering-single-source.sh, which pins a rule restated in
# several places after the restatement drifted three times.
#
# WHAT IT PINS, every side extracted from the real files rather than restated:
#   1. Both templates are found (a missing heading or fence is a failure, not
#      a skip) and /compound's key list clears an anti-vacuous floor.
#   2. The frontmatter key list of /excavate's template equals /compound's,
#      in order, in both directions.
#   3. Enum membership: every `category` /excavate offers is a row of
#      /compound's Phase 2 table; /excavate's `volatility` is one of
#      /compound's alternatives; /research names `volatility` and `90 days`.
#   4. /compound's filename convention appears verbatim in /excavate.
#   5. The fix-commit --grep string is identical in /triage-issue and in every
#      /excavate line that uses it, and /excavate uses it at least twice.
#   6. Ethics pin: /excavate Step 7 names no author, owner, contributor, or
#      handle (outside the scrub-list sentences), and Step 5 keeps its
#      "who to ask, not who to blame" framing.
#   7. Self-test: the key comparison fails against a copy of /excavate with a
#      key dropped, renamed, or added.
#
# Deliberately NOT pinned: the wording of the body sections. Pinning prose
# would force a false uniformity and the suite would be deleted the first time
# someone legitimately reworded them. Only the machine-read surface is pinned.

set -u
cd "$(dirname "$0")/.." || exit 1

compound="compound/SKILL.md"
excavate="excavate/SKILL.md"
research="research/SKILL.md"
triage="triage-issue/SKILL.md"

# Anchors. Headings are matched by prefix so a subtitle edit does not break them.
compound_p3='### Phase 3:'
compound_p2='### Phase 2:'
excavate_s5='### 5.'
excavate_s6='### 6.'
excavate_s7='### 7.'
excavate_s8='### 8.'

# Anti-vacuous floors.
MIN_KEYS=5
MIN_CATEGORIES=5

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

for f in "$compound" "$excavate" "$research" "$triage"; do
    [ -f "$f" ] || { printf 'FATAL %s is missing — the skill moved, or this suite is stale\n' "$f"; exit 1; }
done

# section_of FILE START_PREFIX END_PREFIX — the lines from the heading starting
# START_PREFIX up to (not including) the next heading starting END_PREFIX.
section_of() {
    awk -v s="$2" -v e="$3" '
        index($0, s) == 1 { on = 1; next }
        on && index($0, e) == 1 { exit }
        on { print }
    ' "$1"
}

# template_block FILE HEADING_PREFIX — the first ```markdown fenced block after
# the heading, fences excluded. Empty output if the heading or fence is absent.
template_block() {
    awk -v h="$2" '
        state == 0 && index($0, h) == 1 { state = 1; next }
        state == 1 && $0 == "```markdown" { state = 2; next }
        state == 2 && $0 == "```" { exit }
        state == 2 { print }
    ' "$1"
}

# frontmatter_lines FILE HEADING_PREFIX — the lines between the first pair of
# `---` lines of the template block.
frontmatter_lines() {
    template_block "$1" "$2" | awk '
        $0 == "---" { n++; next }
        n == 1 { print }
        n >= 2 { exit }
    '
}

# frontmatter_keys FILE HEADING_PREFIX — text before the first `:` on each line.
frontmatter_keys() {
    frontmatter_lines "$1" "$2" | sed 's/:.*//'
}

# frontmatter_value FILE HEADING_PREFIX KEY — text after `KEY:` on the line.
frontmatter_value() {
    frontmatter_lines "$1" "$2" | awk -v k="$3" 'index($0, k ":") == 1 { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
}

trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# keys_match EXCAVATE_FILE — 0 when its template key list equals /compound's,
# in order, both directions. Prints a diff on mismatch. The self-test calls
# this against mutated copies, so the comparison under test is the real one.
keys_match() {
    local want got
    want="$(frontmatter_keys "$compound" "$compound_p3")"
    got="$(frontmatter_keys "$1" "$excavate_s7")"
    if [ "$want" = "$got" ]; then
        return 0
    fi
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/       /'
    return 1
}

# -----------------------------------------------------------------------------
section "1. both templates are found and non-vacuous"

compound_keys="$(frontmatter_keys "$compound" "$compound_p3")"
excavate_keys="$(frontmatter_keys "$excavate" "$excavate_s7")"

if grep -qF -- "$compound_p3" "$compound"; then
    ok "$compound has a Phase 3 heading"
else
    bad "$compound has no heading starting \"$compound_p3\"" "the section moved or was renamed; update this suite with it"
fi
if grep -qF -- "$excavate_s7" "$excavate"; then
    ok "$excavate has a Step 7 heading"
else
    bad "$excavate has no heading starting \"$excavate_s7\"" "the section moved or was renamed; update this suite with it"
fi
if [ -n "$compound_keys" ]; then
    ok "$compound Phase 3 template yields a key list"
else
    bad "$compound Phase 3 template yields no keys" "no \`\`\`markdown fence or no --- pair after the heading"
fi
if [ -n "$excavate_keys" ]; then
    ok "$excavate Step 7 template yields a key list"
else
    bad "$excavate Step 7 template yields no keys" "no \`\`\`markdown fence or no --- pair after the heading"
fi
n_compound_keys="$(printf '%s\n' "$compound_keys" | grep -c . || true)"
if [ "$n_compound_keys" -ge "$MIN_KEYS" ]; then
    ok "$compound template has $n_compound_keys keys, at or above the floor of $MIN_KEYS"
else
    bad "$compound template has only $n_compound_keys keys, below the floor of $MIN_KEYS" \
        "either keys were removed, or the extraction stopped matching the real template"
fi

# -----------------------------------------------------------------------------
section "2. key list equality, in order, both directions"

if keys_match "$excavate"; then
    ok "$excavate template keys equal $compound Phase 3 keys ($n_compound_keys, same order)"
else
    bad "$excavate template keys differ from $compound Phase 3 keys" \
        "diff above: < is /compound, > is /excavate; /research Phase 3 reads these fields from every entry"
fi

# -----------------------------------------------------------------------------
section "3. enum membership and the reader of the field"

# shellcheck disable=SC2016  # literal backticks in the sed pattern, no expansion intended
table_keys="$(section_of "$compound" "$compound_p2" "$compound_p3" | sed -n 's/^| `\([a-z0-9-]*\)` |.*/\1/p')"
n_table="$(printf '%s\n' "$table_keys" | grep -c . || true)"
if [ "$n_table" -ge "$MIN_CATEGORIES" ]; then
    ok "$compound Phase 2 table yields $n_table categories, at or above the floor of $MIN_CATEGORIES"
else
    bad "$compound Phase 2 table yields only $n_table categories, below the floor of $MIN_CATEGORIES" \
        "the table changed shape or the row extraction stopped matching"
fi

category_line="$(frontmatter_value "$excavate" "$excavate_s7" category)"
categories="$(printf '%s\n' "$category_line" | tr '|' '\n' | trim | grep . || true)"
if [ -z "$categories" ]; then
    bad "$excavate template has no category value" "the category line is missing or empty"
else
    while IFS= read -r c; do
        if grep -qxF -- "$c" <<<"$table_keys"; then
            ok "category \"$c\" is a $compound Phase 2 row"
        else
            bad "category \"$c\" offered by $excavate is not a $compound Phase 2 row" \
                "rows: $(printf '%s' "$table_keys" | tr '\n' ' ')"
        fi
    done <<<"$categories"
fi

alternatives="$(frontmatter_value "$compound" "$compound_p3" volatility | tr '|' '\n' | trim | grep . || true)"
excavate_vol="$(frontmatter_value "$excavate" "$excavate_s7" volatility | trim)"
if [ -z "$alternatives" ] || [ -z "$excavate_vol" ]; then
    bad "could not extract both volatility values" \
        "compound alternatives: \"$(printf '%s' "$alternatives" | tr '\n' ' ')\"; excavate value: \"$excavate_vol\""
elif grep -qxF -- "$excavate_vol" <<<"$alternatives"; then
    ok "volatility \"$excavate_vol\" is one of /compound's alternatives"
else
    bad "volatility \"$excavate_vol\" is not one of /compound's alternatives" \
        "alternatives: $(printf '%s' "$alternatives" | tr '\n' ' ')"
fi

for needle in 'volatility' '90 days'; do
    if grep -qF -- "$needle" "$research"; then
        ok "$research names \"$needle\" (the reader of the field)"
    else
        bad "$research no longer names \"$needle\"" \
            "the staleness check that consumes /excavate's volatile entries moved; revisit what this suite protects"
    fi
done

# -----------------------------------------------------------------------------
section "4. filename convention"

convention_line="$(grep -m1 '^\*\*Filename convention:\*\*' "$compound" || true)"
# shellcheck disable=SC2016  # literal backticks in the sed pattern, no expansion intended
pattern="$(printf '%s' "$convention_line" | sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p')"
if [ -z "$pattern" ]; then
    bad "no backticked filename pattern on $compound's \"Filename convention\" line" \
        "the line moved or lost its backticks; update this suite with it"
elif grep -qF -- "$pattern" "$excavate"; then
    ok "$excavate carries /compound's filename pattern verbatim: $pattern"
else
    bad "$excavate does not carry /compound's filename pattern" "expected verbatim: $pattern"
fi

# -----------------------------------------------------------------------------
section "5. the fix-commit grep has one source"

# The --grep='...' argument on a line, or nothing.
grep_arg() { grep -o -- "--grep='[^']*'" | head -1; }

triage_line="$(grep -m1 -F 'git log --oneline -i -E --grep=' "$triage" || true)"
canonical="$(printf '%s' "$triage_line" | grep_arg)"
if [ -z "$canonical" ]; then
    bad "no fix-grep line in $triage" "the line containing \"git log --oneline -i -E --grep=\" moved; update this suite with it"
else
    ok "$triage fix-grep: $canonical"
    uses=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        uses=$((uses + 1))
        got="$(printf '%s' "$line" | grep_arg)"
        if [ "$got" = "$canonical" ]; then
            ok "$excavate fix-grep use $uses matches"
        else
            bad "$excavate fix-grep use $uses differs from $triage" "excavate: $got; triage: $canonical"
        fi
    done < <(grep -F -- "--grep='fix" "$excavate")
    if [ "$uses" -ge 2 ]; then
        ok "$excavate uses the fix-grep $uses times, at or above the floor of 2"
    else
        bad "$excavate uses the fix-grep only $uses time(s), below the floor of 2" \
            "the convention-rate line and the per-file line are both expected"
    fi
fi

# -----------------------------------------------------------------------------
section "6. ethics pin: entries carry no names"

step7="$(section_of "$excavate" "$excavate_s7" "$excavate_s8")"
if [ -z "$step7" ]; then
    bad "$excavate Step 7 section is empty" "the headings moved; the grep below would pass vacuously"
else
    # The scrub-list sentences legitimately name the concept; strip them.
    hits="$(printf '%s\n' "$step7" | grep -v -e 'names\.txt' -e 'carries a name' | grep -n -i -E 'author|owner|contributor|who to ask|@handle' || true)"
    if [ -z "$hits" ]; then
        ok "$excavate Step 7 names no author, owner, contributor, or handle"
    else
        bad "$excavate Step 7 mentions a person-bearing term" "$hits"
    fi
fi

step5="$(section_of "$excavate" "$excavate_s5" "$excavate_s6" | tr '\n' ' ' | tr -s ' ')"
if grep -qF -- 'who to ask, not who to blame' <<<"$step5"; then
    ok "$excavate Step 5 keeps \"who to ask, not who to blame\""
else
    bad "$excavate Step 5 lost \"who to ask, not who to blame\"" \
        "or the Step 5 / Step 6 headings moved; the knowledge map must keep its framing"
fi

# -----------------------------------------------------------------------------
section "7. self-test: the comparison fails against mutated copies"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# mutate_first_key FILE MODE — edit the first frontmatter line of the Step 7
# template: drop it, rename its key, or add a bogus line before it.
mutate_first_key() {
    awk -v h="$excavate_s7" -v mode="$2" '
        state == 0 && index($0, h) == 1 { state = 1 }
        state == 1 && $0 == "```markdown" { state = 2 }
        state == 2 && $0 == "---" { fm++; print; if (fm == 1 && mode == "add") print "bogus_key: x"; next }
        state == 2 && fm == 1 && !done {
            done = 1
            if (mode == "drop") next
            if (mode == "rename") { print "renamed_" $0; next }
        }
        { print }
    ' "$1"
}

for mode in drop rename add; do
    copy="$tmpdir/excavate-$mode.md"
    mutate_first_key "$excavate" "$mode" > "$copy"
    if cmp -s "$copy" "$excavate"; then
        bad "self-test \"$mode\": the mutation changed nothing" "the mutator no longer matches the template shape"
    elif keys_match "$copy" >/dev/null; then
        bad "self-test \"$mode\": the comparison passed a mutated template" "the key comparison is vacuous"
    else
        ok "self-test \"$mode\": the comparison fails against the mutated copy"
    fi
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
