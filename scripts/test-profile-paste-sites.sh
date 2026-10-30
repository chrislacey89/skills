#!/usr/bin/env bash
# test-profile-paste-sites.sh — every sub-agent brief carries the repo profile,
# and no skill restates what the profile holds.
#
# `sidecar.sh profile` is the one place repo facts enter a brief. A skill that
# stops naming the verb sends its sub-agents out with no hazards and no verify
# commands, and nothing errors: the brief just reads shorter. A skill that lists
# the profile's fields in prose has a second copy that drifts when a field is
# added, and a partial list reads as a complete one
# (docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md).
#
# Two limits. The site check reads text: it shows a brief instructs the paste,
# not that a controller obeyed. The list check catches the list shapes below,
# inline runs of three or more field names and three stacked lines that each
# lead with one, and a paraphrase in other words gets past it. Two names are
# allowed because /execute Step 4 has to say which two fields it runs.
#
# The site table below is this test's inventory of brief sites. A new skill that
# spawns a sub-agent needing repo facts is added here by hand; nothing detects
# one. The field names are read from sidecar.sh, plus the two that are not
# verify commands.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# label|file|the text that opens the brief's paragraph
SITES=(
    "pre-merge Phase 3 context contract|pre-merge/SKILL.md|**Handed over — the same in all three modes.**"
    "pre-merge delta re-run brief|pre-merge/SKILL.md|**On a delta re-run, the delta is the subject"
    "pre-merge second-pass brief|pre-merge/SKILL.md|**Minimum-findings guard.**"
    "fix-findings fixer brief|fix-findings/SKILL.md|- **Handed over** —"
    "fix-findings breaker brief|fix-findings/SKILL.md|**What the breaker is handed.**"
)
RALPH_BLOCKS=("ralph-once.sh prompt" "ralph.sh prompt")
PRODUCERS=(pre-merge/SKILL.md fix-findings/SKILL.md)

# shellcheck disable=SC2016  # the literal text a skill must carry
VERB='"$SC" profile'

# "start end" of the paragraph opening with $2: to the next blank line or the
# next bold bullet, so a sibling bullet's text cannot satisfy this one.
para_range() {
    awk -v lead="$2" '
        !start && index($0, lead) { start = NR; end = NR; next }
        start {
            if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*- \*\*/) exit
            end = NR
        }
        END { if (start) print start, end }
    ' "$1"
}

# "start end" of each fenced block holding a generated Ralph invocation.
ralph_ranges() {
    awk '
        /^```/ {
            if (!open) { open = 1; start = NR; has = 0 }
            else { open = 0; if (has) print start, NR }
            next
        }
        open && /claude --message/ { has = 1 }
    ' "$1"
}

# Prints one line per violation, naming the site or the file.
check_tree() {
    local root="$1" entry label file lead range text
    for entry in "${SITES[@]}"; do
        IFS='|' read -r label file lead <<<"$entry"
        range="$(para_range "$root/$file" "$lead")"
        if [[ -z "$range" ]]; then
            echo "$label: site not found in $file (looked for: $lead)"
            continue
        fi
        text="$(sed -n "${range% *},${range#* }p" "$root/$file")"
        [[ "$text" == *"$VERB"* ]] || echo "$label: does not name $VERB"
        [[ "$text" == *verbatim* ]] || echo "$label: does not say verbatim"
    done

    for file in "${PRODUCERS[@]}"; do
        grep -Fxq "bash $VERB" "$root/$file" || echo "$file: no block runs bash $VERB"
    done

    local ralph="$root/setup-ralph-loop/SKILL.md" count=0 block
    while read -r start end; do
        count=$((count + 1))
        label="${RALPH_BLOCKS[$((count - 1))]:-unlisted Ralph block $count}"
        block="$(sed -n "${start},${end}p" "$ralph")"
        grep -Fq "bash $VERB" < <(awk '/claude --message/ { exit } { print }' <<<"$block") \
            || echo "$label: profile is not computed before the prompt"
        # shellcheck disable=SC2016  # the literal variable the prompt expands
        grep -Fq '$PROFILE' < <(awk '/claude --message/ { on = 1 } on { print }' <<<"$block") \
            || echo "$label: the prompt does not carry \$PROFILE"
    done < <(ralph_ranges "$ralph")
    [[ "$count" -eq "${#RALPH_BLOCKS[@]}" ]] \
        || echo "Ralph prompt blocks: expected ${#RALPH_BLOCKS[@]}, found $count"

    # The breaker may read the pasted text and must not reach for the resolver.
    local fix="$root/fix-findings/SKILL.md" paste_range step2
    paste_range="$(para_range "$fix" "**What the breaker is handed.**")"
    if [[ -n "$paste_range" ]]; then
        grep -Fq 'never runs' < <(sed -n "${paste_range% *},${paste_range#* }p" "$fix") \
            || echo "fix-findings breaker brief: does not say the breaker never runs it"
        step2="$(awk -v skip_from="${paste_range% *}" -v skip_to="${paste_range#* }" '
            /^### Step 2\./ { on = 1; next }
            on && /^### / { exit }
            on && NR >= skip_from && NR <= skip_to { next }
            on && (/sidecar\.sh/ || /\$SC/) { print NR ": " $0 }
        ' "$fix")"
        [[ -z "$step2" ]] || echo "fix-findings breaker section reaches for sidecar.sh: $step2"
    fi

    # Field names come from the verb's own list.
    local names alts item sep inline skill rel
    names="$(sed -n 's/^VERIFY_FIELD_NAMES=(\(.*\))$/\1/p' "$root/init-pipeline/scripts/sidecar.sh")"
    if [[ -z "$names" ]]; then
        echo "VERIFY_FIELD_NAMES not found in sidecar.sh: no field list to check against"
        return 0
    fi
    alts="$(tr ' ' '|' <<<"$names hazards conventions")"
    item="[\`*]*($alts)[\`*]*"
    sep='[[:space:]]*(,[[:space:]]*(and|or)|,|/|\+|&|;|[[:space:]](and|or))[[:space:]]*'
    inline="(^|[^[:alnum:]_-])$item$sep$item$sep$item([^[:alnum:]_-]|\$)"
    for skill in "$root"/*/SKILL.md; do
        rel="${skill#"$root"/}"
        [[ "$rel" != init-pipeline/SKILL.md ]] || continue
        grep -Ein -- "$inline" "$skill" | cut -c1-160 | sed "s#^#$rel restates the profile's fields: #" || true
        awk -v alts="$alts" -v rel="$rel" '
            BEGIN { re = "^[[:space:]]*([-*|][[:space:]]*)?[`*]*(" alts ")[`*]*[[:space:]]*(:|\\||—|$)" }
            tolower($0) ~ re {
                if (++run == 3) print rel " restates the profile'"'"'s fields: stacked list ending at line " NR
                next
            }
            { run = 0 }
        ' "$skill"
    done
}

section "the tree"

violations="$(check_tree "$repo_root")"
if [[ -z "$violations" ]]; then
    ok "${#SITES[@]} brief sites and ${#RALPH_BLOCKS[@]} Ralph prompts paste the profile; no skill restates its fields"
else
    while IFS= read -r line; do bad "$line"; done <<<"$violations"
fi

# Every plant below would pass trivially against a tree already failing.
if [[ -n "$violations" ]]; then
    printf '\n---\n%d passed, %d failed (self-check skipped: the tree must be clean first)\n' "$pass" "$fail"
    exit 1
fi

section "self-check: planted defects fail, and name what they broke"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fresh_fixture() {
    rm -rf "${fixture:?}"/*
    local skill rel
    for skill in "$repo_root"/*/SKILL.md; do
        rel="${skill#"$repo_root"/}"
        mkdir -p "$fixture/${rel%/*}"
        cp "$skill" "$fixture/$rel"
    done
    mkdir -p "$fixture/init-pipeline/scripts"
    cp "$repo_root/init-pipeline/scripts/sidecar.sh" "$fixture/init-pipeline/scripts/"
}

expect_violation() {
    local label="$1" needle="$2" out
    out="$(check_tree "$fixture")"
    if [[ "$out" == *"$needle"* ]]; then
        ok "$label"
    else
        bad "$label (wanted a violation naming: $needle)"
    fi
}

edit_lines() {
    local file="$1" range="$2" script="$3"
    sed "${range% *},${range#* }$script" "$file" >"$file.new"
    mv "$file.new" "$file"
}

fresh_fixture
if [[ -z "$(check_tree "$fixture")" ]]; then
    ok "the fixture copy starts clean"
else
    bad "the fixture copy is not clean, so nothing below proves anything"
fi

for entry in "${SITES[@]}"; do
    IFS='|' read -r label file lead <<<"$entry"
    for word in profile verbatim; do
        fresh_fixture
        edit_lines "$fixture/$file" "$(para_range "$fixture/$file" "$lead")" "s/$word/Xword/g"
        expect_violation "$label loses \"$word\"" "$label:"
    done
done

index=0
while read -r start end; do
    label="${RALPH_BLOCKS[$index]}"
    index=$((index + 1))
    fresh_fixture
    # shellcheck disable=SC2016  # sed scripts over literal shell text
    edit_lines "$fixture/setup-ralph-loop/SKILL.md" "$start $end" 's/"$SC" profile/"$SC" Xword/'
    expect_violation "$label stops computing it" "$label: profile is not computed"
    fresh_fixture
    # shellcheck disable=SC2016  # sed scripts over literal shell text
    edit_lines "$fixture/setup-ralph-loop/SKILL.md" "$start $end" 's/\$PROFILE/Xword/'
    expect_violation "$label stops carrying it" "$label: the prompt does not carry"
done < <(ralph_ranges "$repo_root/setup-ralph-loop/SKILL.md")

for file in "${PRODUCERS[@]}"; do
    fresh_fixture
    grep -Fxv "bash $VERB" "$fixture/$file" >"$fixture/$file.new"
    mv "$fixture/$file.new" "$fixture/$file"
    expect_violation "$file loses the block that produces the text" "$file: no block runs"
done

fresh_fixture
step2_line="$(grep -n '^### Step 2\.' "$fixture/fix-findings/SKILL.md" | cut -d: -f1)"
sed "${step2_line}a\\
\\
Run \`bash \"\$SC\" profile\` from the breaker copy.
" "$fixture/fix-findings/SKILL.md" >"$fixture/new" && mv "$fixture/new" "$fixture/fix-findings/SKILL.md"
expect_violation "the breaker is told to run sidecar.sh" "fix-findings breaker section reaches for sidecar.sh"

# shellcheck disable=SC2016  # literal markdown backticks
planted_list='Repo facts live in `typecheck`, `lint`, and `hazards`.'

fresh_fixture
echo "$planted_list" >>"$fixture/tdd/SKILL.md"
expect_violation "an inline list in a skill" "tdd/SKILL.md restates the profile's fields"

fresh_fixture
# shellcheck disable=SC2016  # literal markdown backticks
printf -- '- lint\n- `test`: the suite\n- Hazards\n' >>"$fixture/qa/SKILL.md"
expect_violation "a stacked list in a skill" "qa/SKILL.md restates the profile's fields"

fresh_fixture
echo "$planted_list" >>"$fixture/init-pipeline/SKILL.md"
if [[ -z "$(check_tree "$fixture")" ]]; then
    ok "init-pipeline may list them: it is where they are asked"
else
    bad "init-pipeline was flagged, and it is the one skill exempt"
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
