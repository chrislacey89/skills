#!/usr/bin/env bash
# test-skill-inventory.sh — contract test for scripts/check-skill-inventory.sh.
#
# The checker reads hand-written lists (README tables, SYSTEM-OVERVIEW tables
# and role lists, CLAUDE.md roles, the site catalog, stated counts, /name
# references) against the skill directories. A checker whose healthy output is
# "nothing to report" looks identical when it parses nothing, so this suite:
#   - runs the checker against FIXTURE COPIES of the real files with one fault
#     planted per check, and requires exit 1 and a message that names the fault;
#   - runs it against near-misses that must stay quiet (a path, a URL, a fenced
#     block, a skill named in a table that is not a skill table);
#   - requires the unplanted fixture and the real tree to pass.
#
# SYSTEM-OVERVIEW.md is read, never edited, by the change that added the
# checker. If the real tree is missing a row there, the fixtures below add it
# to their own copy so each planted fault is the ONLY fault in its fixture, and
# the real-tree assertion still reports the gap.

# shellcheck disable=SC2016  # fixture text is literal markdown with backticks, never an expansion
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
checker="$repo_root/scripts/check-skill-inventory.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

[[ -f "$checker" ]] || fatal "no checker at $checker"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Independent count of the skill directories, not read from the checker.
dir_count=0
for f in "$repo_root"/*/SKILL.md; do [[ -f "$f" ]] && dir_count=$((dir_count + 1)); done
[[ "$dir_count" -gt 0 ]] || fatal "no skill directories under $repo_root"

# make_fixture <dir> — copy exactly the files the checker reads.
make_fixture() {
    local dest="$1" f d
    mkdir -p "$dest/site/src/lib" "$dest/docs"
    cp "$repo_root/README.md" "$repo_root/CLAUDE.md" "$repo_root/SYSTEM-OVERVIEW.md" "$dest/"
    cp "$repo_root/site/src/lib/data.ts" "$dest/site/src/lib/"
    cp -R "$repo_root/site/src/components" "$dest/site/src/components"
    for f in "$repo_root"/docs/*.md; do [[ -f "$f" ]] && cp "$f" "$dest/docs/"; done
    for f in "$repo_root"/*/SKILL.md; do
        d="$(basename "$(dirname "$f")")"
        mkdir -p "$dest/$d"
        cp "$f" "$dest/$d/SKILL.md"
    done
    # A gap the real SYSTEM-OVERVIEW.md has is not what a fixture is testing:
    # take the Handoff Table rows the baseline needed from the one probe below.
    if [[ -n "${overview_fix:-}" ]]; then cp "$overview_fix" "$dest/SYSTEM-OVERVIEW.md"; fi
}

# overview_fix_from <fixture-dir> — add a stand-in Handoff Table row for every
# skill the real file lacks, once, and remember the repaired copy.
overview_fix_from() {
    local dest="$1" missing name
    missing="$(bash "$checker" "$dest" 2>&1 | sed -n "s/^FAULT: SYSTEM-OVERVIEW.md Handoff Table is missing skill '\(.*\)'\$/\1/p")"
    for name in $missing; do
        awk -v row="| \`/$name\` | stand-in | stand-in | stand-in |" '
            /^### Handoff Table/ { on = 1 }
            on && /^\| `\// { last = NR }
            { lines[NR] = $0 }
            END { for (i = 1; i <= NR; i++) { print lines[i]; if (i == last) print row } }
        ' "$dest/SYSTEM-OVERVIEW.md" > "$dest/SYSTEM-OVERVIEW.md.new" && mv "$dest/SYSTEM-OVERVIEW.md.new" "$dest/SYSTEM-OVERVIEW.md"
    done
    overview_fix="$dest/SYSTEM-OVERVIEW.md"
}

# expect_fault <label> <fixture-dir> <message-fragment>
expect_fault() {
    local label="$1" dir="$2" fragment="$3" out rc
    out="$(bash "$checker" "$dir" 2>&1)"
    rc=$?
    if [[ "$rc" -eq 1 && "$out" == *"$fragment"* ]]; then
        ok "$label"
    else
        bad "$label: expected exit 1 and '$fragment', got exit $rc and: $(printf '%s' "$out" | head -3 | tr '\n' '|')"
    fi
}

expect_clean() {
    local label="$1" dir="$2" out rc
    out="$(bash "$checker" "$dir" 2>&1)"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then ok "$label"; else bad "$label: expected exit 0, got $rc: $(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}

# fresh <name> — a new fixture, echoed as its path
fresh() {
    make_fixture "$work/$1"
    printf '%s' "$work/$1"
}

# edit <file> <python-replace-old> <new> — fail the suite when the target text is gone
edit() {
    python3 -I - "$1" "$2" "$3" <<'PY' || fatal "fixture edit target not found in $1: $2"
import sys
path, old, new = sys.argv[1:4]
t = open(path).read()
if old not in t:
    sys.exit(1)
open(path, 'w').write(t.replace(old, new, 1))
PY
}

section "the baseline fixture passes, so every fault below is the only one"
overview_fix=""
make_fixture "$work/base"
overview_fix_from "$work/base"
base="$work/base"
expect_clean "unplanted fixture exits 0" "$base"
out="$(bash "$checker" "$base" 2>&1)"
if [[ "$out" == *"matches the $dir_count skill directories"* ]]; then
    ok "it reports the independently counted $dir_count directories"
else
    bad "the checker did not report $dir_count directories: $out"
fi

section "check 1: membership, in both directions"
d="$(fresh readme-missing)"
sed -i.bak '/^| \[tdd\](tdd\/)/d' "$d/README.md"
expect_fault "a skill missing from the README tables is named" "$d" "README.md skill tables is missing skill 'tdd'"

# The checker's main hazard: setup-ralph-loop is mentioned in README's
# Requirements table, which is not a skill table.
d="$(fresh readme-near-miss)"
sed -i.bak '/^| \[setup-ralph-loop\](setup-ralph-loop\/)/d' "$d/README.md"
grep -q 'setup-ralph-loop' "$d/README.md" || fatal "fixture premise gone: README no longer mentions setup-ralph-loop outside its skill table"
expect_fault "a skill mentioned only outside a skill table is still missing" "$d" "README.md skill tables is missing skill 'setup-ralph-loop'"

d="$(fresh readme-ghost)"
edit "$d/README.md" '| [help](help/) |' '| [ghost](ghost/) | not a skill |
| [help](help/) |'
expect_fault "a README row for a skill with no directory is named" "$d" "README.md skill tables names 'ghost', which is not a skill directory"

d="$(fresh handoff-missing)"
sed -i.bak '/^| `\/shape` |/d' "$d/SYSTEM-OVERVIEW.md"
expect_fault "a skill missing from the Handoff Table is named" "$d" "SYSTEM-OVERVIEW.md Handoff Table is missing skill 'shape'"

d="$(fresh overview-roles-missing)"
edit "$d/SYSTEM-OVERVIEW.md" '`/hackathon`, ' ''
expect_fault "a skill missing from SYSTEM-OVERVIEW's role lists is named" "$d" "SYSTEM-OVERVIEW.md Invocation Roles is missing skill 'hackathon'"

d="$(fresh claude-roles-missing)"
edit "$d/CLAUDE.md" ', `/excavate`' ''
expect_fault "a skill missing from CLAUDE.md's role lists is named" "$d" "CLAUDE.md Invocation Roles is missing skill 'excavate'"

d="$(fresh catalog-missing)"
edit "$d/site/src/lib/data.ts" '"tdd", ' ''
expect_fault "a skill missing from the site catalog is named" "$d" "site/src/lib/data.ts catalog is missing skill 'tdd'"

d="$(fresh catalog-ghost)"
edit "$d/site/src/lib/data.ts" '"tdd", ' '"tdd", "ghost", '
expect_fault "a catalog entry for a skill with no directory is named" "$d" "catalog names 'ghost', which is not a skill directory"

section "check 2: the two role lists agree"
d="$(fresh role-mismatch)"
edit "$d/CLAUDE.md" '`/re-pitch`, ' ''
edit "$d/CLAUDE.md" '`/git-guardrails-claude-code`' '`/git-guardrails-claude-code`, `/re-pitch`'
expect_fault "a skill in different roles in the two lists is named" "$d" "role mismatch for 're-pitch': CLAUDE.md says infrastructure, SYSTEM-OVERVIEW.md says side-route"

d="$(fresh role-twice)"
edit "$d/CLAUDE.md" '`/git-guardrails-claude-code`' '`/git-guardrails-claude-code`, `/tdd`'
expect_fault "a skill in two roles in one list is named" "$d" "CLAUDE.md Invocation Roles puts 'tdd' in more than one role"

section "check 3: stated counts"
d="$(fresh badge)"
edit "$d/README.md" "badge/skills-$dir_count-blue" "badge/skills-99-blue"
expect_fault "a wrong README badge is named" "$d" "README.md badge says 99, but there are $dir_count skill directories"

d="$(fresh prose-count)"
edit "$d/README.md" "$dir_count composable skills" "35 composable skills"
expect_fault "a wrong count in README prose is named with its line" "$d" "says 35, but there are $dir_count skill directories"

d="$(fresh word-count)"
edit "$d/README.md" "$dir_count composable skills" "Thirty composable skills"
expect_fault "a spelled-out wrong count is named" "$d" "says Thirty, but there are $dir_count skill directories"

d="$(fresh count-comment)"
# shellcheck disable=SC2016  # literal source text
printf '\n// An old comment once said "Thirty skills" here.\n' >> "$d/site/src/lib/data.ts"
expect_clean "a source comment quoting an old count is not a stated count" "$d"

d="$(fresh count-citations)"
printf '\nThis book is cited by 9 skills in the canon.\n' >> "$d/README.md"
expect_clean "a citation count is not a skill count" "$d"

section "check 4: /name references resolve"
d="$(fresh ref-ghost)"
printf '\nThen run /ghost-skill to finish.\n' >> "$d/tdd/SKILL.md"
expect_fault "a reference to a skill that does not exist is named with file and name" "$d" "reference: tdd/SKILL.md:"
expect_fault "the message carries the unresolved name" "$d" "names /ghost-skill"

d="$(fresh ref-ghost-backtick)"
# shellcheck disable=SC2016  # literal markdown
printf '\nHand off to `/ghost-skill` when done.\n' >> "$d/tdd/SKILL.md"
expect_fault "a backticked reference is read too" "$d" "names /ghost-skill"

d="$(fresh ref-near-misses)"
{
    printf '\nWrite scratch output under /tmp/example and /dev/null, never to https://example.com/ghost-page.\n'
    # shellcheck disable=SC2016  # literal markdown
    printf 'See `/ghost-file.md` and a path like ~/.claude/ghost-dir/ for context.\n'
    printf '\n```bash\ncd /ghost-in-a-fence && ls /ghost-too\n```\n'
} >> "$d/tdd/SKILL.md"
expect_clean "paths, URLs, file names and fenced blocks are not references" "$d"

d="$(fresh ref-allowlisted)"
# shellcheck disable=SC2016  # literal markdown
printf '\nIf the stack matches, load `/zod` and `/library`.\n' >> "$d/tdd/SKILL.md"
expect_clean "an allowlisted outside skill resolves" "$d"

section "the real tree"
out="$(bash "$checker" "$repo_root" 2>&1)"
rc=$?
if [[ "$rc" -eq 0 ]]; then ok "the real tree passes"; else bad "the real tree has inventory faults: $(printf '%s' "$out" | grep '^FAULT' | head -5 | tr '\n' '|')"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
