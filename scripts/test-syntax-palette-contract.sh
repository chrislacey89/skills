#!/usr/bin/env bash
# test-syntax-palette-contract.sh — the `--sx-*` syntax palette is a fixed,
# demonstrated vocabulary, not a stub an agent completes at render time.
#
# THE DRIFT CLASS. docs/visual-recap-design.md §1 ships a fixed palette that
# /visual-recap and /walk-commits copy verbatim, under an explicit rule in
# docs/visual-rendering-core.md §6: "Keep the variable names; do not re-derive a
# fresh palette per run." A palette is only copyable if it covers the code being
# rendered. Where it does not, the agent does not stop — it invents a name and
# repurposes a nearby one, which is exactly the run-to-run drift the rule exists
# to prevent, arrived at by an agent that read the rule.
#
# THE INCIDENT (issue #305, 2026-08-28). Building a walkthrough of PR #299 — a
# change living entirely in shell scripts — the agent hit a palette named for a
# typed C-family language the pack never writes. There was no token for a shell
# variable, none for a flag, and none separating a command from its subcommand.
# So it invented `--sx-v` and silently repurposed `--sx-t` (type) to mean flag,
# and described the result to the user as house style. Neither act was noticed.
#
# At the time, `--sx-t` had zero applied usages anywhere in the repo, and was an
# RGB distance of 20.6 (light) / 13.9 (dark) from `--sx-n` — two names, one
# color, both undemonstrated. Half the palette had never colored anything.
#
# WHAT THIS PINS, and why each half is needed:
#
#   1. MEMBERSHIP — `--sx-v` is defined, `--sx-t` is gone, and no tracked file
#      still carries `--sx-t`. Catches the resurrection and the half-add.
#   2. SYMMETRY — the light and dark themes define the same token set. The
#      field defect was a token existing in one place and not another.
#   3. DEMONSTRATION — every token the palette defines is applied at least once
#      as `var(--sx-X)` in the same document. This is the actual defect: a token
#      that is defined but never shown in use is a slot an agent fills with its
#      own guess. A membership check alone would have passed the whole time
#      `--sx-t` sat at zero uses.
#   4. MAPPING — every defined token has a row in §1's role table naming what it
#      colors. Without the mapping, "keep the variable names" tells an agent
#      which names to keep and nothing about what to put in them.
#   5. THE TOKENIZER BAN and the named offline fallback in §6, plus the block
#      count §3 restates. All three are one-line claims a future edit could
#      quietly reverse.
#
# These assertions extract the real text from the real files rather than
# restating it, so an edit to either doc that breaks the contract fails here
# rather than passing review on careful reading (CLAUDE.md § "Commands a skill
# documents", rule (b); the #243 failure mode).
#
# WHAT THIS DOES NOT CATCH, stated so nobody over-trusts it. It cannot tell that
# an applied usage is *correctly* applied — `var(--sx-k)` wrapped around a
# string satisfies assertion 3. It checks that the vocabulary is complete and
# demonstrated, not that any particular render used it well.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

design="docs/visual-recap-design.md"
core="docs/visual-rendering-core.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

fatal() {
    printf 'FATAL: %s\n' "$1" >&2
    exit 2
}

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

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok   %s\n' "$label"
        pass=$((pass + 1))
    else
        printf '  FAIL %s\n       missing: %q\n' "$label" "$needle"
        fail=$((fail + 1))
    fi
}

[[ -f "$design" ]] || fatal "$design not found — this suite reads the canonical skeleton."
[[ -f "$core" ]] || fatal "$core not found — this suite reads the rendering core."

# --- Extract the two theme blocks from the real §1 token core -----------------
#
# The light theme is the `:root{` block; dark is `[data-theme="dark"]{`. Both
# end at the first line that is a bare closing brace at that indent. Reading the
# blocks separately (rather than grepping the whole file) is what makes the
# symmetry assertion possible.

theme_block() {
    local opener="$1"
    awk -v opener="$opener" '
        index($0, opener) { inblock = 1; next }
        inblock && $0 ~ /^[[:space:]]*}[[:space:]]*$/ { exit }
        inblock { print }
    ' "$design"
}

# tokens_defined <block-text> — the `--sx-*` names a theme block defines, sorted.
tokens_defined() {
    printf '%s\n' "$1" | grep -o -- '--sx-[a-z]\+:' | sed 's/:$//' | sort -u
}

light_block="$(theme_block ':root{')"
dark_block="$(theme_block '[data-theme="dark"]{')"

[[ -n "$light_block" ]] || fatal "extracted an empty :root{ block from $design — the token core moved or changed shape; update this suite with it."
[[ -n "$dark_block" ]] || fatal "extracted an empty [data-theme=\"dark\"]{ block from $design — the dark theme moved or changed shape; update this suite with it."

light_tokens="$(tokens_defined "$light_block")"
dark_tokens="$(tokens_defined "$dark_block")"

[[ -n "$light_tokens" ]] || fatal "the :root{ block defines no --sx-* tokens at all; the palette is gone, not merely changed."

printf 'light theme tokens: %s\n' "$(printf '%s' "$light_tokens" | tr '\n' ' ')"
printf 'dark theme tokens:  %s\n' "$(printf '%s' "$dark_tokens" | tr '\n' ' ')"

# -----------------------------------------------------------------------------

section "membership: --sx-v is defined, --sx-t is gone"

assert_contains "$light_tokens" '--sx-v' "light theme defines --sx-v (the variable/interpolation slot)"
assert_contains "$dark_tokens" '--sx-v' "dark theme defines --sx-v"

for theme_name in light dark; do
    block_tokens="light_tokens"
    [[ "$theme_name" == dark ]] && block_tokens="dark_tokens"
    if printf '%s\n' "${!block_tokens}" | grep -q -x -- '--sx-t'; then
        printf '  FAIL %s theme still defines --sx-t\n' "$theme_name"
        printf '       It was deleted in #305: zero applied usages, and an RGB distance of\n'
        printf '       20.6 (light) / 13.9 (dark) from --sx-n. Two names for one color is what\n'
        printf '       agents silently repurpose. Do not reintroduce it.\n'
        fail=$((fail + 1))
    else
        printf '  ok   %s theme does not define --sx-t\n' "$theme_name"
        pass=$((pass + 1))
    fi
done

# Repo-wide, not just the canonical file: --sx-t lived in three tracked files
# (canonical + two bundled copies), so a canonical-only check would miss a
# bundled copy that failed to sync.
stragglers="$(git grep -l -- '--sx-t' -- '*' || true)"
assert_eq "" "$stragglers" "no tracked file anywhere still mentions --sx-t"

# -----------------------------------------------------------------------------

section "symmetry: both themes define the same token set"

# The field defect began as a token that existed in one place and not another.
assert_eq "$light_tokens" "$dark_tokens" "light and dark define an identical --sx-* set"

# -----------------------------------------------------------------------------

section "demonstration: every defined token is applied somewhere in the doc"

# This is the assertion that would have caught the original defect. A token
# defined but never shown in use is a slot the next agent fills with a guess —
# which is what happened to --sx-t (repurposed to mean "flag") and why --sx-v
# was invented rather than found.
while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    uses="$(grep -c -F "var($token)" "$design" || true)"
    if [[ "$uses" -gt 0 ]]; then
        printf '  ok   %s is applied (%s use(s) of var(%s))\n' "$token" "$uses" "$token"
        pass=$((pass + 1))
    else
        printf '  FAIL %s is defined but never applied — zero occurrences of var(%s) in %s\n' "$token" "$token" "$design"
        printf '       An undemonstrated token is a stub. Show it in use or delete it.\n'
        fail=$((fail + 1))
    fi
done <<< "$light_tokens"

# -----------------------------------------------------------------------------

section "mapping: every defined token has a role row in §1"

# The role table is what turns "keep the variable names" into something an agent
# can act on for a language the examples do not cover.
while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    if grep -q -F "| \`$token\` |" "$design"; then
        printf '  ok   %s has a role row\n' "$token"
        pass=$((pass + 1))
    else
        printf '  FAIL %s is defined but has no row in the §1 role table\n' "$token"
        printf '       Add a row naming what it colors, in both the language-agnostic and shell columns.\n'
        fail=$((fail + 1))
    fi
done <<< "$light_tokens"

# The mapping must actually name shell, since a shell PR is what exposed the gap.
# shellcheck disable=SC2016  # the backticks are literal markdown table cells, not command substitution
mapping_row="$(grep -F '| `--sx-v` |' "$design" || true)"
mapping_row="$(printf '%s' "$mapping_row" | head -1)"
assert_contains "$mapping_row" '$' "the --sx-v row names a shell variable form"

# -----------------------------------------------------------------------------

section "the CDN highlighter is not the primary path"

# `:186` permits highlight.js, and #305 deliberately kept that permission. What
# it must not become is the path an agent reaches for first, leaving the offline
# render unspecified — the gap that made hand-rolling a lexer look reasonable.
hl_line="$(grep -n 'highlight\.js' "$core" || true)"
hl_line="$(printf '%s' "$hl_line" | head -1 | cut -d: -f2-)"
[[ -n "$hl_line" ]] || fatal "no highlight.js mention found in $core — :186 was deleted, which #305 explicitly rejected (the CDN clause is sharpened, not removed)."

assert_contains "$hl_line" 'no-CDN fallback' "the highlight.js clause still requires a no-CDN fallback"
assert_contains "$hl_line" 'only where it earns its place' "the highlight.js clause is still gated, not a default"

# The fallback must be named concretely, not left as "some fallback".
fallback_named="$(grep -c -- '--sx-\*' "$core" || true)"
if [[ "$fallback_named" -gt 0 ]]; then
    printf '  ok   the core names the --sx-* tokens as the concrete offline fallback\n'
    pass=$((pass + 1))
else
    printf '  FAIL the core never names --sx-* as the offline fallback\n'
    printf '       An unnamed fallback is what made hand-rolling a tokenizer look reasonable.\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "the tokenizer ban is present"

tokenizer_line="$(grep -i -- 'hand-roll a tokenizer' "$core" || true)"
if [[ -n "$tokenizer_line" ]]; then
    printf '  ok   the core forbids hand-rolling a tokenizer\n'
    pass=$((pass + 1))
else
    printf '  FAIL no "hand-roll a tokenizer" directive found in %s\n' "$core"
    printf '       Measured in #305: 13/13 adversarial inputs passed a losslessness gate, 11 were mis-colored.\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "the block count §3 restates is unchanged"

# #305 rejected an eleventh block precisely because the count is restated across
# five files. If a future change adds one, this fails and names the sweep.
block_sentence="$(grep -o 'blocks cover the surface' "$core" || true)"
[[ -n "$block_sentence" ]] || fatal "the '… blocks cover the surface' sentence is gone from $core — §3's opening moved; update this suite with it."

count_word="$(grep -o '[A-Z][a-z]* blocks cover the surface' "$core" || true)"
count_word="$(printf '%s' "$count_word" | head -1 | awk '{print $1}')"
assert_eq "Ten" "$count_word" "§3 still opens 'Ten blocks cover the surface'"

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
