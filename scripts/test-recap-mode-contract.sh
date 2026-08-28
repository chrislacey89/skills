#!/usr/bin/env bash
# The needles in this suite are markdown, and markdown is full of backticks.
# Single quotes are what keeps `/visual-recap` and `hidden` literal; there is
# nothing here to expand. This directive is file-wide, so it must precede the
# first command.
# shellcheck disable=SC2016
# test-recap-mode-contract.sh — contract test for /visual-recap's two rendering
# modes and its diagram default.
#
# THE DRIFT CLASS: an always-on surface contradicting the doc it points at.
#
# Issue #307 is the incident. `visual-recap/SKILL.md`'s `description:` sits in
# the context window of every session in every downstream repo, and it announced
# "CSS-first flow diagrams (Mermaid opt-in for complex graphs)" — a default the
# field had overridden twice and that this change reverses. The same claim was
# restated in CLAUDE.md, in two places in SYSTEM-OVERVIEW.md, and in README.md.
# Five copies of one operative claim, none of them the canon, and nothing
# relating any of them to `docs/visual-recap-design.md` §5 where the rule lives.
#
# It is also the incident that produced the deck mode: two independent sessions
# rebuilt an artifact the canon does not describe, because nothing in the canon
# described it. A mode that exists only as a field artifact is the pre-#126
# drift condition, so Part II's structure is pinned here rather than trusted.
#
# Every assertion below EXTRACTS the real text from the real file. Nothing is
# restated — a hand-copied claim in a test is the same defect the test exists to
# catch (see docs/restated-claims.md).

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
design="$repo_root/docs/visual-recap-design.md"
core="$repo_root/docs/visual-rendering-core.md"
skill="$repo_root/visual-recap/SKILL.md"
claude_md="$repo_root/CLAUDE.md"
overview="$repo_root/SYSTEM-OVERVIEW.md"
readme="$repo_root/README.md"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# has <haystack> <needle> — the single matcher both assertions call.
#
# The haystack arrives on a here-string, NOT through `printf | grep -q`. That
# pipeline is wrong in a way that only shows up at size: `grep -q` exits at the
# first match, `printf` takes SIGPIPE while still writing, and under
# `set -o pipefail` the pipeline reports 141 instead of 0. On a small file
# printf finishes first and it looks correct; on a large one every `assert_has`
# fails and — far worse — every `assert_lacks` passes *because* the forbidden
# string was found. This suite's first run hit exactly that: two spurious FAILs
# against the 93 KB design doc, with the vacuous-pass half invisible.
has() { grep -qF -- "$2" <<<"$1"; }

# assert_has <haystack> <needle> <label>
assert_has() {
    if has "$1" "$2"; then ok "$3"; else
        bad "$3"
        printf '       expected to find: %s\n' "$2"
    fi
}

# assert_has_re <haystack> <extended-regex> <label> — the regex sibling of
# assert_has. Same here-string discipline, and for the same reason.
assert_has_re() {
    if grep -qE -- "$2" <<<"$1"; then ok "$3"; else
        bad "$3"
        printf '       expected to match: %s\n' "$2"
    fi
}

# assert_lacks <haystack> <needle> <label>
assert_lacks() {
    if has "$1" "$2"; then
        bad "$3"
        printf '       found forbidden:  %s\n' "$2"
    else ok "$3"; fi
}

# extract <file> <start-regex> <end-regex> — the half-open span [start, end)
extract() {
    awk -v s="$2" -v e="$3" '
        $0 ~ s { on = 1 }
        on && NR > 1 && $0 ~ e && seen { on = 0 }
        on { print; seen = 1 }
    ' "$1"
}

fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

for f in "$design" "$core" "$skill" "$claude_md" "$overview" "$readme"; do
    [ -f "$f" ] || fatal "missing file: $f"
done

# Whole-file contents. Passing a *path* where a haystack is expected is a
# vacuous assertion that reports ok forever; the first run of this suite did
# exactly that at six sites, so the contents are bound once, here.
design_txt="$(cat "$design")"
core_txt="$(cat "$core")"
skill_txt="$(cat "$skill")"

# ---------------------------------------------------------------------------
section "1. The canon states one diagram decision rule, and it is the new one"

design_s5="$(extract "$design" '^## 5\. Block: diagram' '^## 6\.')"
[ -n "$design_s5" ] || fatal "§5 extracted to 0 lines from $design — the heading moved."

rule="$(grep -A6 -F '**Decision rule (one line):**' <<<"$design_s5" || true)"
[ -n "$rule" ] || fatal "no 'Decision rule (one line):' paragraph in $design §5."
printf 'decision rule (design §5):\n%s\n\n' "$rule"

# The rule must be conditioned on what the picture has to say, naming both arms.
for needle in 'trivial spine' 'CSS primitive' 'multi-stage' 'behavioral' 'Mermaid'; do
    assert_has "$rule" "$needle" "design §5 decision rule names '$needle'"
done

# The reversal is named, not stepped over (Chesterton's fence).
assert_has "$design_s5" '#131' "design §5 names the fence it reopens (#131)"
assert_has "$design_s5" '#129' "design §5 keeps #129's render-confirm gate in view"

# ---------------------------------------------------------------------------
section "2. No always-on surface still states the reversed default"

# These are the exact two phrases the pre-#307 default was written in. They are
# banned in the surfaces a downstream session actually reads. Prose that must
# discuss the reversal historically belongs in CHANGELOG.md, which is not scanned.
skill_fm="$(sed -n '/^---$/,/^---$/p' "$skill")"
[ -n "$skill_fm" ] || fatal "no YAML frontmatter in $skill."
claude_line="$(grep -F '`/visual-recap` is an optional side-route' "$claude_md" || true)"
[ -n "$claude_line" ] || fatal "no /visual-recap inventory bullet in CLAUDE.md."
overview_row="$(grep -F '| `/visual-recap` |' "$overview" || true)"
[ -n "$overview_row" ] || fatal "no /visual-recap row in the SYSTEM-OVERVIEW handoff table."
overview_bullet="$(grep -F '`/visual-recap` is an optional side-route at the same' "$overview" || true)"
[ -n "$overview_bullet" ] || fatal "no /visual-recap inventory bullet in SYSTEM-OVERVIEW.md."
readme_row="$(grep -F '| [visual-recap](visual-recap/) |' "$readme" || true)"
[ -n "$readme_row" ] || fatal "no visual-recap row in the README skill table."

while IFS='|' read -r label body; do
    [ -n "$label" ] || continue
    case "$label" in
        frontmatter)       hay="$skill_fm" ;;
        claude-bullet)     hay="$claude_line" ;;
        overview-row)      hay="$overview_row" ;;
        overview-bullet)   hay="$overview_bullet" ;;
        readme-row)        hay="$readme_row" ;;
        core-vocabulary)   hay="$(extract "$core" '^## 3\. Component vocabulary' '^## 4\.')" ;;
        *) fatal "unknown surface label: $label" ;;
    esac
    [ -n "$hay" ] || fatal "surface '$label' extracted to nothing."
    assert_lacks "$hay" 'CSS-first'      "$label does not state the reversed 'CSS-first' default"
    assert_lacks "$hay" 'Mermaid opt-in' "$label does not state the reversed 'Mermaid opt-in' default"
    assert_has   "$hay" 'Mermaid'        "$label still names Mermaid ($body)"
done <<'SURFACES'
frontmatter|the always-on description
claude-bullet|CLAUDE.md inventory
overview-row|SYSTEM-OVERVIEW handoff table
overview-bullet|SYSTEM-OVERVIEW inventory
readme-row|README skill table
core-vocabulary|rendering-core §3
SURFACES

# ---------------------------------------------------------------------------
section "3. The offline invariant is scoped, not deleted"

core_s6="$(extract "$core" '^## 6\. ' '^## 7\.')"
[ -n "$core_s6" ] || fatal "§6 extracted to 0 lines from $core."
assert_has "$core_s6" 'read *identically* with no network' \
    "core §6 still requires core blocks to read identically offline"
assert_has "$core_s6" 'never loses the finding' \
    "core §6 requires that a degraded figure never loses a finding"
assert_has "$core_s6" 'degrade note' \
    "core §6 requires the per-figure degrade note"
assert_has "$core_s6" 'known to be offline' \
    "core §6 keeps the CSS primitive required for known-offline review"

# #83's boundary is a declared non-goal of #307 and must survive untouched.
assert_has "$core_txt" '#83' "core still names #83's GitHub-markdown boundary"
assert_has "$design_txt" '#83' "design doc still names #83's GitHub-markdown boundary"

# ---------------------------------------------------------------------------
section "4. #129's render-confirm gate survives, unscoped"

core_s7="$(extract "$core" '^## 7\. ' '^## 8\.')"
[ -n "$core_s7" ] || fatal "§7 extracted to 0 lines from $core."
assert_has "$core_s7" 'Confirm a Mermaid diagram renders before presenting (DO-CONFIRM)' \
    "core §7 still carries the DO-CONFIRM gate verbatim"
assert_lacks "$core_s7" 'only when you took the Mermaid opt-in' \
    "core §7's gate is no longer scoped to an opt-in"
assert_has "$core_s7" 'Every Mermaid figure' \
    "core §7's gate applies to every Mermaid figure"
assert_lacks "$skill_txt" 'Only if you took the Mermaid opt-in' \
    "the skill's Step 5 gate is no longer scoped to an opt-in"

# ---------------------------------------------------------------------------
section "5. The serializer is scoped, not cut"

core_s4="$(extract "$core" '^## 4\. The copy-text feedback loop' '^## 5\.')"
[ -n "$core_s4" ] || fatal "§4 extracted to 0 lines from $core."
assert_has "$core_s4" 'recap-feedback v1' "core §4 still specifies the recap-feedback v1 format"
assert_has "$core_s4" 'function copyFeedback()' "core §4 still ships the copyable serializer"
assert_has "$core_s4" 'data-feedback-id' "core §4 still requires stable feedback ids"
assert_has "$core_s4" 'required whenever the artifact is handed off' \
    "core §4 keeps the loop required on handoff"
assert_has "$core_s4" 'optional final-screen block' \
    "core §4 makes it optional when the author is in the room"

# ---------------------------------------------------------------------------
section "6. Part II specifies the deck rather than leaving it to the field"

part2="$(extract "$design" '^# Part II' '^ZZZ_NO_SUCH_LINE_ZZZ')"
[ -n "$part2" ] || fatal "Part II extracted to 0 lines from $design."

for n in D1 D2 D3 D4 D5 D6 D7 D8 D9; do
    assert_has "$part2" "## §$n." "Part II ships §$n"
done

# The arc, in order — the deck's defining structure.
arc="$(printf '%s' "$part2" | extract /dev/stdin '^## §D5\. ' '^## §D6\.')"
[ -n "$arc" ] || fatal "§D5 (the arc) extracted to 0 lines."
prev=0
for stage in Premise 'The changes' 'The mechanism' Aftermath; do
    n="$(grep -n -F "**$stage**" <<<"$arc" | sed -n '1s/:.*//p')"
    if [ -z "$n" ]; then
        bad "§D5 names the arc stage '$stage'"
    elif [ "$n" -le "$prev" ]; then
        bad "§D5 stage '$stage' is out of order (line $n, after $prev)"
    else
        ok "§D5 names the arc stage '$stage', in order"
        prev="$n"
    fi
done

# The two rules that bound paging (§D2) — Tufte's anti-pattern, answered.
d2="$(printf '%s' "$part2" | extract /dev/stdin '^## §D2\. ' '^## §D3\.')"
assert_has "$d2" 'no comparison may span screens' "§D2 forbids a comparison spanning screens"
assert_has "$d2" 'never page a population'        "§D2 forbids paging a population"
assert_has "$d2" 'Memory is not vision'           "§D2 quotes the Tufte anti-pattern it answers"

# ---------------------------------------------------------------------------
section "7. The deck ships no router"

# §12 (from #304) refuses a store-plus-routing stage. The deck must not
# reintroduce it through a second door: paging is a [hidden] toggle over
# sections that are all in the DOM, which is also what keeps show-all,
# browser find, print, and the §4 serializer working.
#
# The needle is scoped to Part II's fenced blocks, not its prose. A bare
# `innerHTML` search matches the very sentence that forbids it — the same
# self-matching defect #306's mutation pass found in its own suite.
part2_code="$(printf '%s\n' "$part2" | awk '/^```/ { fence = !fence; next } fence { print }')"
[ -n "$part2_code" ] || fatal "Part II contains no fenced code blocks."
assert_lacks "$part2_code" '.innerHTML' "Part II's skeleton makes no innerHTML assignment"
assert_lacks "$part2_code" 'document.write' "Part II's skeleton does not write markup at runtime"
assert_has "$part2" 'toggling `hidden`' "§D3 states that paging toggles [hidden]"
assert_has "$part2" 'present in the markup from the start' \
    "§D3 requires every screen to be in the DOM from the start"
assert_has "$part2" "querySelectorAll('[data-feedback-id]')" \
    "§D3 states why the serializer survives paging"

# The rail must bind by id, not by array position. `data-to` shipped in the §D3
# skeleton while §D8 bound `items.forEach((b, j) => show(j))` — an attribute that
# looks load-bearing, is not read, and hides a real invariant: that the nav list
# and the screen list stay the same length in the same order forever. Both halves
# are asserted, because either one alone is the defect.
assert_has "$part2_code" 'data-to=' "§D3's rail markup carries data-to on every .navitem"
assert_has "$part2_code" 'b.dataset.to' "§D8's script actually reads data-to"
assert_lacks "$part2_code" 'show(j)' "§D8 does not bind the rail by array position"

nav_items="$(grep -c 'class="navitem"' <<<"$part2_code" || true)"
nav_wired="$(grep -c 'class="navitem" data-to=' <<<"$part2_code" || true)"
if [ "$nav_items" -gt 0 ] && [ "$nav_items" = "$nav_wired" ]; then
    ok "every .navitem in the skeleton is wired ($nav_wired/$nav_items)"
else
    bad "§D3 has $nav_items .navitem(s) but only $nav_wired carry data-to"
fi

# ---------------------------------------------------------------------------
section "8. The mode-selection rule is stated in the skill, not only the doc"

d1="$(printf '%s' "$part2" | extract /dev/stdin '^## §D1\. ' '^## §D2\.')"
[ -n "$d1" ] || fatal "§D1 extracted to 0 lines."

# Pull the canonical rule's two clauses out of §D1 and require the skill to
# carry both. A rule stated only in a bundled reference is a rule the always-on
# surface can drift from — which is the defect at the top of this file.
for clause in 'one story the screens advance' 'auditing parallel hunks'; do
    assert_has "$d1"       "$clause" "§D1's selection rule contains '$clause'"
    assert_has "$skill_txt" "$clause" "the skill's Step 1 restates '$clause' from §D1"
done
assert_has "$skill_txt" 'Part II' "the skill routes readers to Part II by name"
assert_has "$skill_txt" 'Part I'  "the skill routes readers to Part I by name"

# /re-pitch pairing: recommend, never invoke.
assert_has "$part2" '/re-pitch' "§D6 records the /re-pitch pairing"
assert_has "$skill_txt" 'recommend `/re-pitch`' "the skill recommends /re-pitch"
assert_lacks "$skill_txt" 'invoke `/re-pitch`' "the skill never invokes /re-pitch"

# ---------------------------------------------------------------------------
section "9. The serializer's scope is stated in both halves, everywhere it is stated"

# This claim was INTRODUCED by the change this suite guards, and it is restated
# at four sites. Section 2 pins the diagram-default claim that way; without the
# same treatment here the change would ship the exact drift shape it exists to
# remove, one claim later.
#
# The failure mode is not omission, it is HALF-restatement. "Required on
# handoff" alone reads as unconditional and silently contradicts the canon; a
# plain presence check on the required half would score that as a pass. So both
# halves are asserted at every site that states the rule.
REQ_RE='required (whenever the artifact is handed off|on handoff|for handoff)'
OPT_RE='optional (final-screen block|in the room|when the author is in the room)'

serializer_canon="$(extract "$core" '^## 4\. The copy-text feedback loop' '^## 5\.')"
[ -n "$serializer_canon" ] || fatal "core §4 extracted to 0 lines."

skill_clause="$(grep -F 'layered-clipboard serializer' "$skill" || true)"
claude_clause="$(grep -oE 'copy-text feedback serializer[^)]*' "$claude_md" || true)"
overview_clause="$(grep -oE 'copy-text feedback serializer[^)]*' "$overview" || true)"

for pair in "canon (core §4)|$serializer_canon" \
            "the skill's Step 4|$skill_clause" \
            "CLAUDE.md's inventory|$claude_clause" \
            "SYSTEM-OVERVIEW's inventory|$overview_clause"; do
    label="${pair%%|*}"
    text="${pair#*|}"
    if [ -z "$text" ]; then
        bad "$label states the serializer scope (clause not found at all)"
        continue
    fi
    assert_has_re "$text" "$REQ_RE" "$label states the required-on-handoff half"
    assert_has_re "$text" "$OPT_RE" "$label states the optional-in-the-room half"
done

# Written down rather than taken silently: SYSTEM-OVERVIEW's handoff-table row
# (`| /visual-recap | … |`) says "copied back where the artifact is handed off"
# and is deliberately NOT in the set above. That column describes what the skill
# *produces*, not when the mechanism is required, so it carries no obligation to
# restate the optional half. Asserting both halves there would force a rule into
# a cell that is answering a different question.
assert_has "$overview_row" 'handed off' \
    "the handoff-table row names the handoff condition (produces-column, rule not required)"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
