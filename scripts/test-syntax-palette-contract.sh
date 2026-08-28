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

# The per-token loops below iterate the UNION, not the light theme. The recorded
# field defect was a token existing in one place and not another (header, item
# 2), so a dark-only token must reach the demonstration and mapping checks and
# not merely trip the symmetry assertion on its way past them. Iterating one
# theme reports one failure where three are true.
all_tokens="$(printf '%s\n%s\n' "$light_tokens" "$dark_tokens" | sort -u)"

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
#
# The matcher is deliberately NOT the bare name. Prose that *names* the deleted
# token is what you want — this suite's own header explains why it went, and
# CHANGELOG.md records it. A bare-name check reddens on its own documentation,
# which trains the reader to stop writing the documentation. So it matches the
# two shapes that would resurrect the token: a definition (`--sx-t:`) and an
# application (`var(--sx-t)`). The label below states that reach rather than
# claiming the broader property, per docs/restated-claims.md.
#
# This suite is excluded from its own scan: the comment above quotes both
# matcher shapes to explain them, which is documentation, not a resurrection.
# scripts/test-guards-can-fire.sh excludes itself for the same reason. The
# exclusion is exactly one path, so it cannot quietly widen.
self="scripts/test-syntax-palette-contract.sh"
straggler_pattern='--sx-t:|var\(--sx-t\)'

# scan_stragglers <dir> — run the detector and print the paths it names.
#
# `git grep` is the reader, so a run outside a work tree makes it fail. That
# failure MUST NOT reach the `|| true`: it would print the detector's normal
# `ok` on stdout, put `fatal: not a git repository` on stderr where no assertion
# reads it, and exit 0. Verified before this guard existed — `git archive HEAD |
# tar -x` into a plain directory produced a clean 24/0. So exit status 0 (hits)
# and 1 (no hits) are the only accepted outcomes; anything else is a dead
# instrument and stops the run.
# It sets $scan_out rather than printing, and the caller calls fatal — NOT this
# function. `fatal` runs `exit`, and an `exit` inside `$( … )` kills only the
# subshell: the first draft of this guard printed its FATAL to stderr, left
# $stragglers empty, satisfied the assertion below against that emptiness, and
# exited 0 with "27 passed, 0 failed". A guard that cannot stop the run is the
# very class scripts/test-guards-can-fire.sh exists for, so it is structured to
# put the exit in the main shell.
scan_out=""
scan_stragglers() {
    local status=0
    scan_out="$(cd "$1" && git grep -lE -- "$straggler_pattern" -- '*' 2>/dev/null)" || status=$?
    [[ "$status" -le 1 ]] || return 2
    return 0
}

# --- Self-test the detector before trusting its silence ----------------------
#
# This assertion's healthy state is zero hits, so a broken matcher and a clean
# tree are indistinguishable from the outside — and both print `ok`. Verified:
# swapping the pattern for one that cannot match left the run at 24/0. So plant
# the shape it exists to find and require a hit, plant a near-miss and require
# silence. docs/solutions/testing-patterns/
# mechanism-generality-lags-the-pattern-2026-08-23.md § Prevention #2 is the
# rule; validate-the-instrument-not-only-the-subject-2026-08-23.md is the family.

section "the --sx-t detector can fire (instrument self-test)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Built with `git -C` rather than `( cd … ) || fatal`: `set -e` is suppressed in
# the left operand of `||`, so a subshell guarded that way runs past a failed
# command and exits 0 — the fixture would be half-built and the guard silent.
# scripts/test-guards-can-fire.sh detects that shape and caught this exact line
# in an earlier draft of this file. Each step is checked on its own result.
git init -q "$scratch" || fatal "git init failed in $scratch"
git -C "$scratch" config user.email fixture@example.invalid || fatal "git config failed in $scratch"
git -C "$scratch" config user.name fixture || fatal "git config failed in $scratch"
printf -- '  --sx-t:hsl(32 72%% 42%%);\n' > "$scratch/planted-definition.md"
printf -- '<span style="color:var(--sx-t)">x</span>\n' > "$scratch/planted-usage.md"
printf -- 'Prose that merely names --sx-t and explains why it went.\n' > "$scratch/near-miss.md"
git -C "$scratch" add -A || fatal "git add failed in $scratch"
git -C "$scratch" commit -qm fixture || fatal "git commit failed in $scratch — a global core.hooksPath whose pre-commit rejects will do this"

# The fixture is only useful if git actually tracks all three files: the scan
# below is `git grep`, which reads tracked content, so an empty index would make
# every assertion pass vacuously.
tracked="$(git -C "$scratch" ls-files | grep -c . || true)"
[[ "$tracked" -eq 3 ]] || fatal "self-test fixture has $tracked tracked file(s), expected 3; git grep would report on a tree that was never built."

scan_stragglers "$scratch" \
    || fatal "the --sx-t straggler scan could not read its own fixture (git grep failed in $scratch). The instrument is dead; refusing to report on it."
planted="$scan_out"
assert_contains "$planted" 'planted-definition.md' "the detector finds a planted '--sx-t:' definition"
assert_contains "$planted" 'planted-usage.md' "the detector finds a planted 'var(--sx-t)' usage"

if printf '%s\n' "$planted" | grep -q -x 'near-miss.md'; then
    printf '  FAIL the detector fires on prose that only names --sx-t\n'
    printf '       That is the false positive the matcher was narrowed to avoid — it would\n'
    printf '       redden on CHANGELOG.md and on this suite\x27s own header.\n'
    fail=$((fail + 1))
else
    printf '  ok   the detector stays silent on prose that only names --sx-t\n'
    pass=$((pass + 1))
fi

rm -rf "$scratch"; trap - EXIT

# --- Now run it against the real tree ----------------------------------------
#
# Repo-wide, not just the canonical file: --sx-t lived in three tracked files
# (canonical + two bundled copies), so a canonical-only check would miss a
# bundled copy that failed to sync.
#
# This suite is excluded from its own scan: the comments above quote both
# matcher shapes and the regex itself is assigned as a literal, so the file
# matches by construction. scripts/test-guards-can-fire.sh excludes itself for
# the same reason. The exclusion is exactly one path, so it cannot quietly widen.
scan_stragglers "$repo_root" \
    || fatal "the --sx-t straggler scan could not read the tree (git grep failed in $repo_root). A detector whose healthy state is zero hits cannot tell 'nothing found' from 'nothing looked'; refusing to report either."
stragglers="$(printf '%s' "$scan_out" | grep -v -x -- "$self" || true)"
assert_eq "" "$stragglers" "no tracked file defines '--sx-t:' or applies 'var(--sx-t)' (prose naming the deleted token is fine)"

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
    # Anchored to the applied form, not the bare name. Counting `var(--sx-X)`
    # anywhere in the file lets a sentence that merely *names* the token satisfy
    # the assertion this suite calls load-bearing — verified: replacing the
    # worked example with prose naming all six kept the run at 24/0 while no
    # span rendered. "Shown in use" has to mean a span that colors something.
    uses="$(grep -c -F "style=\"color:var($token)" "$design" || true)"
    if [[ "$uses" -gt 0 ]]; then
        printf '  ok   %s is applied (%s span(s) carry style="color:var(%s))\n' "$token" "$uses" "$token"
        pass=$((pass + 1))
    else
        printf '  FAIL %s is defined but never applied — no span carries style="color:var(%s)" in %s\n' "$token" "$token" "$design"
        printf '       Prose naming the token does not count. An undemonstrated token is a stub;\n'
        printf '       show it coloring something in the copyable markup, or delete it.\n'
        fail=$((fail + 1))
    fi
done <<< "$all_tokens"

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
done <<< "$all_tokens"

# The mapping must actually name shell, since a shell PR is what exposed the gap.
# shellcheck disable=SC2016  # the backticks are literal markdown table cells, not command substitution
mapping_row="$(grep -F '| `--sx-v` |' "$design" || true)"
mapping_row="$(printf '%s' "$mapping_row" | head -1)"
# `$` alone is met by "costs US$5" — verified green under that mutation. The
# row has to carry a variable, so require the sigil followed by a name or brace.
# shellcheck disable=SC2016  # the $NAME forms below are literal prose about shell syntax
if printf '%s' "$mapping_row" | grep -qE '\$[A-Za-z_{]'; then
    printf '  ok   the --sx-v row carries a shell variable form ($NAME or ${NAME})\n'
    pass=$((pass + 1))
else
    printf '  FAIL the --sx-v row has no $NAME / ${NAME} example\n'
    printf '       This row is the only place the palette shows how to color $BASE_REF.\n'
    fail=$((fail + 1))
fi

# -----------------------------------------------------------------------------

section "the CDN highlighter is not the primary path"

# `:186` permits highlight.js, and #305 deliberately kept that permission. What
# it must not become is the path an agent reaches for first, leaving the offline
# render unspecified — the gap that made hand-rolling a lexer look reasonable.
# Anchored on the clause's own opening words rather than on the first mention of
# `highlight.js` in the file: an added cross-reference earlier in the doc would
# otherwise silently retarget both assertions below at the wrong sentence.
hl_line="$(grep -F 'Reach for a CDN library' "$core" || true)"
hl_line="$(printf '%s' "$hl_line" | head -1)"
[[ -n "$hl_line" ]] || fatal "no 'Reach for a CDN library' clause found in $core — :186 was deleted, which #305 explicitly rejected (the CDN clause is sharpened, not removed)."

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
# five files. If a future change adds one, this fails and names the sweep —
# which is exactly what happened: #304 added the per-unit series (§12), ran the
# sweep across every enumeration surface, and updated this pin in the same
# change. test-options-comparison-contract.sh separately derives the count from
# §3's own table rows, so the two checks disagree loudly if a block lands
# without its sweep.
block_sentence="$(grep -o 'blocks cover the surface' "$core" || true)"
[[ -n "$block_sentence" ]] || fatal "the '… blocks cover the surface' sentence is gone from $core — §3's opening moved; update this suite with it."

count_word="$(grep -o '[A-Z][a-z]* blocks cover the surface' "$core" || true)"
count_word="$(printf '%s' "$count_word" | head -1 | awk '{print $1}')"
assert_eq "Eleven" "$count_word" "§3 still opens 'Eleven blocks cover the surface'"

# -----------------------------------------------------------------------------
#
# The three assertions below measure the palette's *properties*, not its names.
# Membership pins that `--sx-t` does not come back as `--sx-t`; it says nothing
# about the two facts that actually condemned it — a seventh name in a six-name
# vocabulary, and a color indistinguishable from a sibling. Verified: planting
# `--sx-y` with `--sx-t`'s exact deleted values, a role row, and one applied
# span passed the name-based suite at 26/0. A contract that pins the instance
# and not the property is the shape docs/solutions/testing-patterns/
# mechanism-generality-lags-the-pattern-2026-08-23.md names.

# palette_metrics <theme-block> — resolve every color the theme defines to sRGB,
# compositing any alpha over that theme's own --bg (which is how a wash actually
# renders), then emit one line per --sx-* token:
#
#   <token> <min-rgb-distance-to-a-sibling> <closest-sibling> <worst-contrast> <worst-surface>
#
# Checked against Chromium: --sx-v hsl(310 58% 42%) resolves here to
# (169.2, 45.0, 148.5); getComputedStyle reported rgb(169, 45, 149).
palette_metrics() {
    printf '%s\n' "$1" | awk '
    function h2rgb(h,s,l,  c,x,m,t,r,g,b) {
        s/=100; l/=100
        t=2*l-1; if(t<0) t=-t
        c=(1-t)*s
        t=h/60; while(t>=2) t-=2; t=t-1; if(t<0) t=-t
        x=c*(1-t); m=l-c/2
        if(h<60){r=c;g=x;b=0} else if(h<120){r=x;g=c;b=0} else if(h<180){r=0;g=c;b=x}
        else if(h<240){r=0;g=x;b=c} else if(h<300){r=x;g=0;b=c} else {r=c;g=0;b=x}
        RR=(r+m)*255; GG=(g+m)*255; BB=(b+m)*255
    }
    function srgb(v){ v/=255; return (v<=0.03928)? v/12.92 : ((v+0.055)/1.055)^2.4 }
    function lum(r,g,b){ return 0.2126*srgb(r)+0.7152*srgb(g)+0.0722*srgb(b) }
    function ratio(l1,l2,  hi,lo){ hi=(l1>l2)?l1:l2; lo=(l1>l2)?l2:l1; return (hi+0.05)/(lo+0.05) }
    /--[a-z-]+:hsla?\(/ {
        line=$0
        name=line; sub(/^[[:space:]]*/,"",name); sub(/:.*$/,"",name)
        val=line; sub(/^[^(]*\(/,"",val); sub(/\).*$/,"",val)
        a=1; if (val ~ /\//) { al=val; sub(/^.*\/[[:space:]]*/,"",al); a=al+0; sub(/\/.*$/,"",val) }
        gsub(/%/,"",val); n=split(val,f,/[[:space:]]+/)
        if (n<3) next
        h2rgb(f[1]+0,f[2]+0,f[3]+0)
        R[name]=RR; G[name]=GG; B[name]=BB; A[name]=a; order[++cnt]=name
    }
    END {
        # composite every alpha color over this theme own --bg
        for (i=1;i<=cnt;i++) { n=order[i]
            if (A[n]<1) { R[n]=R[n]*A[n]+R["--bg"]*(1-A[n]); G[n]=G[n]*A[n]+G["--bg"]*(1-A[n]); B[n]=B[n]*A[n]+B["--bg"]*(1-A[n]) } }
        ns=0; nf=0
        for (i=1;i<=cnt;i++) { n=order[i]
            if (n ~ /^--sx-/) sx[++ns]=n
            else if (n=="--bg"||n=="--bg-subtle"||n=="--bg-inset"||n=="--bg-elev"||n=="--add-bg"||n=="--del-bg") surf[++nf]=n }
        for (i=1;i<=ns;i++) { t=sx[i]
            md=1e9; mp="none"
            for (j=1;j<=ns;j++) { if (i==j) continue; o=sx[j]
                d=sqrt((R[t]-R[o])^2+(G[t]-G[o])^2+(B[t]-B[o])^2)
                if (d<md) { md=d; mp=o } }
            wc=1e9; ws="none"
            for (j=1;j<=nf;j++) { o=surf[j]
                c=ratio(lum(R[t],G[t],B[t]), lum(R[o],G[o],B[o]))
                if (c<wc) { wc=c; ws=o } }
            printf "%s %.1f %s %.2f %s\n", t, md, mp, wc, ws } }
    '
}

light_metrics="$(palette_metrics "$light_block")"
dark_metrics="$(palette_metrics "$dark_block")"
[[ -n "$light_metrics" && -n "$dark_metrics" ]] \
    || fatal "palette_metrics resolved no --sx-* colors; the token core changed shape and every measurement below would pass vacuously."

# palette_metrics parses `hsl()` / `hsla()` and nothing else, so a token written
# as a hex literal, a `color-mix()`, or `hsl(210deg …)` drops out of its output
# and is silently exempted from every measurement below. Verified: rewriting
# --sx-s as `#a1a1a1` left five light tokens measured for distinctness instead of
# six, with no line saying one had gone missing. A token that escapes the checks
# is the same hole as a check that cannot fire, so a value shape this cannot read
# stops the run rather than quietly narrowing the population.
declared_n="$(printf '%s\n' "$all_tokens" | { grep -c . || true; } )"
for theme_name in light dark; do
    m="$light_metrics"; [[ "$theme_name" == dark ]] && m="$dark_metrics"
    resolved_n="$(printf '%s\n' "$m" | { grep -c . || true; } )"
    [[ "$resolved_n" -eq "$declared_n" ]] || fatal "the $theme_name theme declares $declared_n --sx-* token(s) but palette_metrics resolved $resolved_n. A token whose value is not hsl()/hsla() is skipped by every measurement below, so it would clear the distinctness floor and the AA check by being invisible to them. Teach palette_metrics that value shape, or write the token as hsl()."
done

section "the vocabulary is closed at the size the prose claims"

# The prose one screen below the token core says "These six are the whole
# vocabulary. Do not invent a seventh." That is a countable claim of exactly the
# type this suite already pins for "Ten blocks cover the surface" — and it was
# shipped unpinned: planting a seventh token with a role row and an applied span
# passed at 26/0 while the sentence forbidding it silently became false.
vocab_sentence="$(grep -oE '[A-Za-z]+ (are|is) the whole vocabulary' "$design" || true)"
[[ -n "$vocab_sentence" ]] \
    || fatal "the '<numeral> are the whole vocabulary' sentence is gone from $design — §1's closure claim moved; update this suite with it."
vocab_word="$(printf '%s' "$vocab_sentence" | awk '{print tolower($1)}')"
case "$vocab_word" in
    four) vocab_n=4 ;; five) vocab_n=5 ;; six) vocab_n=6 ;; seven) vocab_n=7 ;; eight) vocab_n=8 ;;
    *) fatal "unrecognized numeral '$vocab_word' in the vocabulary-size claim; add it to this case statement rather than leaving the claim unchecked." ;;
esac
actual_n="$(printf '%s\n' "$all_tokens" | { grep -c . || true; } )"
assert_eq "$vocab_n" "$actual_n" "§1 claims '$vocab_word' tokens and defines $actual_n"

section "no two tokens are the same color (the other half of why --sx-t went)"

# --sx-t sat 20.6 (light) / 13.9 (dark) from --sx-n — same hue in dark, 4% apart
# in saturation. The floor is 40: comfortably above that pair and every one like
# it, comfortably below the current minimum, so it rejects a re-added duplicate
# without reddening on the palette as it stands.
DISTINCT_FLOOR=40
for theme_name in light dark; do
    m="$light_metrics"; [[ "$theme_name" == dark ]] && m="$dark_metrics"
    while read -r token dist closest _ _; do
        [[ -n "$token" ]] || continue
        if awk -v d="$dist" -v f="$DISTINCT_FLOOR" 'BEGIN{exit !(d>=f)}'; then
            printf '  ok   %s %s is %s from its nearest sibling (%s)\n' "$theme_name" "$token" "$dist" "$closest"
            pass=$((pass + 1))
        else
            printf '  FAIL %s %s is only %s RGB from %s (floor %s)\n' "$theme_name" "$token" "$dist" "$closest" "$DISTINCT_FLOOR"
            printf '       Two names for one color is what agents silently repurpose — it is half\n'
            printf '       the reason --sx-t was deleted. Retune it or drop one of the pair.\n'
            fail=$((fail + 1))
        fi
    done <<< "$m"
done

section "the AA exception list in §1 is exact"

# §1 claims AA "with one documented exception" and names it. A blanket claim
# would be false (three tokens are sub-AA and this doc's own worked example is
# the first place two of them color anything), and a narrowed claim nothing
# checks is just a quieter version of the same thing.
AA_BAR=4.5
exception_sentence="$(grep -F 'body-text bar' "$design" | head -1 || true)"
[[ -n "$exception_sentence" ]] \
    || fatal "the AA exception sentence ('… body-text bar: …') is gone from $design; the AA claim's scope is unreadable and this check cannot run."

# The sentence names its light exceptions before "in light" and its dark ones after.
#
# Each half is `|| true`-guarded and then required to be non-empty. Without the
# guard, `grep -oE` matching nothing returns 1, and under `set -o pipefail`
# inside `$( … )` that trips `set -e`: verified — rewording the sentence to name
# no tokens printed the section header and then nothing at all, no summary line,
# no message, exit 1. A check that dies silently is worse than one that fails,
# because the run looks truncated rather than wrong.
claimed_light="$(printf '%s' "$exception_sentence" | sed 's/ in light.*//'   | grep -oE -- '--sx-[a-z]' | sort -u || true)"
claimed_dark="$( printf '%s' "$exception_sentence" | sed 's/^.* in light,//' | grep -oE -- '--sx-[a-z]' | sort -u || true)"
[[ -n "$claimed_light" && -n "$claimed_dark" ]] \
    || fatal "the AA exception sentence in $design names no --sx-* tokens on one or both sides of 'in light' (light: '${claimed_light:-none}', dark: '${claimed_dark:-none}'). The claim's scope cannot be read, so comparing it against the measured set would compare two empty sets and pass vacuously. State the exception list as backticked token names, or delete the sentence and re-broaden the claim deliberately."

for theme_name in light dark; do
    m="$light_metrics"; claimed="$claimed_light"
    if [[ "$theme_name" == dark ]]; then m="$dark_metrics"; claimed="$claimed_dark"; fi
    measured="$(printf '%s\n' "$m" | awk -v bar="$AA_BAR" '$4+0 < bar {print $1}' | sort -u)"
    detail="$(printf '%s\n' "$m" | awk -v bar="$AA_BAR" '$4+0 < bar {printf "%s=%s on %s ", $1, $4, $5}')"
    if [[ "$claimed" == "$measured" ]]; then
        printf '  ok   %s: the sub-AA set §1 names is exactly the set measured (%s)\n' \
            "$theme_name" "${detail:-none}"
        pass=$((pass + 1))
    else
        printf '  FAIL %s: §1 names a different sub-AA set than the palette actually has\n' "$theme_name"
        printf '       §1 names:  %s\n' "$(printf '%s' "$claimed" | tr "\n" " ")"
        printf '       measured:  %s\n' "$(printf '%s' "$measured" | tr "\n" " ")"
        printf '       %s\n' "${detail:-all tokens meet the bar}"
        printf '       Recoloring a token means editing §1 sentence too — that is the point of\n'
        printf '       naming an exact exception list instead of claiming "every color".\n'
        fail=$((fail + 1))
    fi
done

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]] || exit 1
