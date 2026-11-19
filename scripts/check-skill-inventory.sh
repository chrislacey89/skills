#!/usr/bin/env bash
# check-skill-inventory.sh — the skill directories are the one inventory that
# cannot be wrong; this checks every hand-written list about them against it.
#
# Usage:
#   scripts/check-skill-inventory.sh [repo-root]    (default: this repo)
#
# Exits 1 and prints one line per fault when any list disagrees. Shape and tone
# follow scripts/sync-skill-references.sh --check.
#
# THE SOURCE OF TRUTH. Every top-level directory that contains a SKILL.md is a
# skill. Nothing below restates that set.
#
# FOUR CHECKS
#   1. Membership. Every skill appears in README.md's skill tables, in
#      SYSTEM-OVERVIEW.md's Handoff Table and its Invocation Roles, in
#      CLAUDE.md's Invocation Roles, and in the `catalog` array of
#      site/src/lib/data.ts; and none of those names a skill that has no
#      directory. README rows are read only from the `| [name](name/) |` link
#      form under `## Skills`: a skill mentioned in the Requirements table or in
#      prose is not a skill-table row, and a bare grep for the name would pass
#      on exactly that mention.
#   2. Roles agree. CLAUDE.md and SYSTEM-OVERVIEW.md each put every skill in
#      exactly one role, and the two put it in the same one. A role list reads
#      only the unbroken run of `/name` items after the bullet's colon, so a
#      parenthetical that mentions another skill is not a member.
#   3. Counts. Every stated skill count equals the directory count: the README
#      badge, and "<N> skills" or a spelled-out count in the prose surfaces
#      (README.md, CLAUDE.md, SYSTEM-OVERVIEW.md, docs/*.md, */SKILL.md,
#      site/src outside generated files). CHANGELOG.md and docs/solutions/
#      are dated records and are not read. A line about book citations
#      ("Cited by N skills") counts books, not the pack, and a source comment
#      (a line starting `//`, `/*` or `*`) can quote an old count while
#      explaining it; both are skipped.
#   4. References resolve. Every `/name` that is a skill mention in a
#      top-level */SKILL.md is a pack skill or is in the allowlist below.
#
# WHERE THE LINE FALLS in check 4: a mention is `/name` outside a fenced code
# block, where the character before the slash is the start of the line, a
# space, a backtick, a parenthesis, a bracket, a quote, an asterisk or a comma,
# and the name is lowercase letters, digits and hyphens that is not followed by
# another `/` or by `.` and a letter or digit. That drops paths (`/tmp/x`,
# `/dev/null`, `~/.claude/...`), URL segments (`github.com/org/repo`), file
# names (`/x.md`) and everything inside fenced blocks (shell, mermaid, CSS).
# What still gets through and is not a skill is listed in NOT_A_SKILL below.
#
# NO check that every skill has a row in /help: its ladder is state-driven, and
# a skill with no repo-state signal correctly has no row.
#
# Not checked here, on purpose: SYSTEM-OVERVIEW.md's file tree. Another change
# owns it, and it is not one of the four checks.

set -uo pipefail

# Skills that live outside this pack but are named in its skills, and tokens that
# pass check 4's line and are not skills. One entry per line, each with the
# reason; a name that is in neither list and is not a directory is a fault. No
# built-in Claude Code command, such as /clear or /compact, is named in any skill
# today; add one here with its reason if that changes.
OUTSIDE_RAW="
excalidraw-diagram            # free-form diagramming; mermaid and visual-recap route to it
library                       # the book library; improve-pipeline grounds proposals in it
next-cache-components-adoption  # Next.js skill that execute names for matching stacks
next-cache-components-optimizer # Next.js skill that execute names for matching stacks
vercel-composition-patterns   # React skill that execute names for matching stacks
vercel-react-best-practices   # React skill that execute names for matching stacks
worktrunk                     # the worktree CLI's skill; execute names it
zod                           # the Zod skill ts-audit loads when a file imports zod
zod-testing                   # the Zod testing skill ts-audit loads alongside zod
"
NOT_A_SKILL_RAW="
deps                          # .env.local/deps in prose: a slash between two nouns
login                         # a route in an example manual-verification checklist
visual-plan                   # named only to say no such skill exists (visual-recap/SKILL.md)
"
OUTSIDE_SKILLS="$(printf '%s\n' "$OUTSIDE_RAW" | sed 's/[[:space:]]*#.*$//' | grep . || true)"
NOT_A_SKILL="$(printf '%s\n' "$NOT_A_SKILL_RAW" | sed 's/[[:space:]]*#.*$//' | grep . || true)"

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
faults=0

fault() {
    printf 'FAULT: %s\n' "$1"
    faults=$((faults + 1))
}

# in_list <list> <word>
in_list() {
    case "
$1
" in
        *"
$2
"*) return 0 ;;
    esac
    return 1
}

skills="$(for f in "$root"/*/SKILL.md; do [ -f "$f" ] && basename "$(dirname "$f")"; done | sort)"
skill_count="$(printf '%s\n' "$skills" | grep -c .)"
[ "$skill_count" -gt 0 ] || { echo "error: no skill directories under $root" >&2; exit 2; }

for f in README.md CLAUDE.md SYSTEM-OVERVIEW.md site/src/lib/data.ts; do
    [ -f "$root/$f" ] || { echo "error: $f not found under $root" >&2; exit 2; }
done

# --- readers: each prints one skill name per line ----------------------------

readme_names() {
    awk '/^## Skills/ { on = 1; next } /^## / { on = 0 } on' "$root/README.md" \
        | sed -n 's/^| \[\([a-z0-9-]*\)\]([a-z0-9-]*\/).*/\1/p'
}

# shellcheck disable=SC2016  # the backticks are literal markdown
handoff_names() {
    awk '/^### Handoff Table/ { on = 1; next } /^##/ { on = 0 } on' "$root/SYSTEM-OVERVIEW.md" \
        | sed -n 's/^| `\/\([a-z0-9-]*\)`.*/\1/p'
}

catalog_names() {
    awk '/export const catalog/ { on = 1; next } on && /^\];/ { on = 0 } on' "$root/site/src/lib/data.ts" \
        | sed -n 's/.*skills: \[\(.*\)\].*/\1/p' | tr ',' '\n' | sed -n 's/^ *"\([a-z0-9-]*\)" *$/\1/p'
}

# shellcheck disable=SC2016  # the backticks are literal markdown
# role_pairs <file> <heading-regex> — "role name" lines. The role is the first
# word of the bold bullet title. The members are the unbroken run of
# `/name` items, separated by ", ", right after the bullet's first ": `/".
role_pairs() {
    awk -v heading="$2" '
        $0 ~ heading { on = 1; next }
        on && /^#/ { on = 0 }
        on && /^- \*\*/ { print }
    ' "$1" | while IFS= read -r bullet; do
        role="$(printf '%s' "$bullet" | sed -n 's/^- \*\*\([A-Za-z-]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')"
        rest="${bullet#*: \`/}"
        [ "$rest" != "$bullet" ] || continue
        rest="\`/$rest"
        # peel `/name` items while the next item follows a ", "
        while :; do
            name="$(printf '%s' "$rest" | sed -n 's/^`\/\([a-z0-9-]*\)`.*/\1/p')"
            [ -n "$name" ] || break
            printf '%s %s\n' "$role" "$name"
            rest="${rest#\`/"$name"\`}"
            case "$rest" in
                ", "*) rest="${rest#, }" ;;
                *) break ;;
            esac
        done
    done
}

# --- check 1: membership ------------------------------------------------------

check_membership() {
    local label="$1" names="$2" name
    [ -n "$names" ] || { fault "$label lists no skills at all; its table or heading changed shape"; return; }
    for name in $skills; do
        in_list "$names" "$name" || fault "$label is missing skill '$name'"
    done
    for name in $names; do
        in_list "$skills" "$name" || fault "$label names '$name', which is not a skill directory"
    done
}

readme="$(readme_names | sort -u)"
handoff="$(handoff_names | sort -u)"
catalog="$(catalog_names | sort -u)"
claude_roles="$(role_pairs "$root/CLAUDE.md" '^## Invocation Roles')"
overview_roles="$(role_pairs "$root/SYSTEM-OVERVIEW.md" '^### Invocation Roles')"
claude_names="$(printf '%s\n' "$claude_roles" | awk 'NF { print $2 }' | sort -u)"
overview_names="$(printf '%s\n' "$overview_roles" | awk 'NF { print $2 }' | sort -u)"

check_membership "README.md skill tables" "$readme"
check_membership "SYSTEM-OVERVIEW.md Handoff Table" "$handoff"
check_membership "SYSTEM-OVERVIEW.md Invocation Roles" "$overview_names"
check_membership "CLAUDE.md Invocation Roles" "$claude_names"
check_membership "site/src/lib/data.ts catalog" "$catalog"

# --- check 2: roles agree ------------------------------------------------------

check_one_role() {
    local label="$1" pairs="$2" name roles
    for name in $skills; do
        roles="$(printf '%s\n' "$pairs" | awk -v n="$name" '$2 == n { print $1 }' | sort -u | tr '\n' ' ')"
        case "$roles" in
            *" "*" "*) fault "$label puts '$name' in more than one role (${roles% })" ;;
        esac
    done
}

check_one_role "CLAUDE.md Invocation Roles" "$claude_roles"
check_one_role "SYSTEM-OVERVIEW.md Invocation Roles" "$overview_roles"

for name in $skills; do
    c="$(printf '%s\n' "$claude_roles" | awk -v n="$name" '$2 == n { print $1; exit }')"
    o="$(printf '%s\n' "$overview_roles" | awk -v n="$name" '$2 == n { print $1; exit }')"
    if [ -n "$c" ] && [ -n "$o" ] && [ "$c" != "$o" ]; then
        fault "role mismatch for '$name': CLAUDE.md says $c, SYSTEM-OVERVIEW.md says $o"
    fi
done

# --- check 3: stated counts ----------------------------------------------------

check_count() {
    local where="$1" stated="$2"
    [ "$stated" = "$skill_count" ] || fault "skill count: $where says $stated, but there are $skill_count skill directories"
}

badge="$(sed -n 's/.*img\.shields\.io\/badge\/skills-\([0-9]*\)-.*/\1/p' "$root/README.md" | head -1 || true)"
if [ -n "$badge" ]; then check_count "README.md badge" "$badge"; else fault "README.md has no skills badge, so its stated count cannot be read"; fi

count_scan_files() {
    local f
    for f in README.md CLAUDE.md SYSTEM-OVERVIEW.md; do [ -f "$root/$f" ] && echo "$f"; done
    for f in "$root"/docs/*.md "$root"/*/SKILL.md; do [ -f "$f" ] && echo "${f#"$root"/}"; done
    if [ -d "$root/site/src" ]; then
        find "$root/site/src" -type f ! -name '*.generated.*' ! -path '*/node_modules/*' 2>/dev/null | sed "s|^$root/||"
    fi
}

# count_faults — one "message" line per stated count that disagrees
count_faults() {
    local hit f rest ln text num lower base ones val
    # one grep over every file; each hit is "file:line:text"
    count_scan_files | (cd "$root" && xargs grep -HinE '(^|[^A-Za-z0-9-])([0-9]+|twenty|thirty|forty|fifty)[ -]?(one|two|three|four|five|six|seven|eight|nine)? (composable |pipeline )?skills?([^A-Za-z]|$)' 2>/dev/null) \
        | grep -viE 'cited by' \
        | while IFS= read -r hit; do
            f="${hit%%:*}"
            rest="${hit#*:}"
            ln="${rest%%:*}"
            text="${rest#*:}"
            # A source comment may quote an old count; a markdown line that
            # starts with `*` (bold, bullet) is prose and is checked.
            case "$f" in
                */site/src/*|site/src/*)
                    if printf '%s' "$text" | grep -qE '^[[:space:]]*(//|/\*|\*)'; then continue; fi
                    ;;
            esac
            num="$(printf '%s' "$text" | grep -oiE '([0-9]+|twenty|thirty|forty|fifty)[ -]?(one|two|three|four|five|six|seven|eight|nine)? (composable |pipeline )?skills?' | head -1 | sed -E 's/ (composable |pipeline )?skills?$//' || true)"
            case "$num" in
                [0-9]*) val="$num" ;;
                *)
                    lower="$(printf '%s' "$num" | tr '[:upper:]' '[:lower:]' | tr -d ' -')"
                    base=0
                    case "$lower" in
                        twenty*) base=20 ;; thirty*) base=30 ;; forty*) base=40 ;; fifty*) base=50 ;;
                    esac
                    ones=0
                    case "$lower" in
                        *one) ones=1 ;; *two) ones=2 ;; *three) ones=3 ;; *four) ones=4 ;; *five) ones=5 ;;
                        *six) ones=6 ;; *seven) ones=7 ;; *eight) ones=8 ;; *nine) ones=9 ;;
                    esac
                    val=$((base + ones))
                    ;;
            esac
            if [ "$val" != "$skill_count" ]; then
                printf 'skill count: %s:%s says %s, but there are %s skill directories\n' "$f" "$ln" "$num" "$skill_count"
            fi
        done
}

while IFS= read -r msg; do
    [ -n "$msg" ] && fault "$msg"
done < <(count_faults)

# --- check 4: references resolve -------------------------------------------------

mentions() {
    awk '
        FNR == 1 { fence = 0 }
        /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
        fence { next }
        {
            line = $0
            while (match(line, /(^|[ `(\["*,])\/[a-z][a-z0-9-]*/)) {
                tok = substr(line, RSTART, RLENGTH)
                sub(/^[^\/]*\//, "", tok)
                nxt = substr(line, RSTART + RLENGTH, 1)
                nxt2 = substr(line, RSTART + RLENGTH + 1, 1)
                if (nxt != "/" && !(nxt == "." && nxt2 ~ /[A-Za-z0-9]/)) print FILENAME ":" FNR ":" tok
                # keep a non-matching character in front of the rest, so a path
                # tail like the `null` of /dev/null is not read as line start
                line = "\001" substr(line, RSTART + RLENGTH)
            }
        }
    ' "$root"/*/SKILL.md
}

while IFS=: read -r file ln name; do
    [ -n "$name" ] || continue
    in_list "$skills" "$name" && continue
    in_list "$OUTSIDE_SKILLS" "$name" && continue
    in_list "$NOT_A_SKILL" "$name" && continue
    fault "reference: ${file#"$root"/}:$ln names /$name, which is not a pack skill and is not in the allowlist"
done < <(mentions)

if [ "$faults" -gt 0 ]; then
    echo ""
    echo "$faults inventory fault(s) across $skill_count skills."
    exit 1
fi
echo "Skill inventory matches the $skill_count skill directories."
