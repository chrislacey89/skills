#!/usr/bin/env bash
# test-skill-blocks-zsh-safe.sh — fails on the two shell shapes that work in
# bash and break in zsh, wherever a skill documents a fenced bash/sh block.
#
# THE DRIFT CLASS. An agent copies a skill's fenced block and runs it in the
# harness shell, which on macOS is the login shell: zsh. zsh does not word-split
# an unquoted expansion, so
#   - `for x in $LIST` runs once, with the whole list as one word, and
#   - `${VAR:+--flag "$VAR"}` reaches the command as ONE argument.
# The contract suites that execute blocks run them with `bash -c`, and CI's
# ubuntu runners have no zsh, so neither sees it. #393 found the first case in
# /execute's hooks gate; PR #561 shipped two more in /prd-to-issues three weeks
# later, caught only by a reviewer. See
# docs/solutions/patterns/skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md.
#
# WHAT THIS DOES NOT SEE. It matches two shapes textually. Other bash/zsh
# differences (an unquoted `$FLAGS` meant to split into arguments, unmatched
# globs, array indexing, `read -a`) pass. Running a skill's blocks under zsh,
# as scripts/test-prd-to-issues-sidecar-branch.sh does, is the stronger check.
#
# KNOWN SITES. Pre-existing occurrences are listed below as `file<TAB>line text`
# with the issue that owns the fix. An entry that no longer matches fails, so
# fixing a site forces its entry out (the list only shrinks).

set -u
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; fail=$((fail + 1)); }

known="$(cat <<'EOF'
execute/SKILL.md	  for term in $GATE_TERMS; do	#393
write-a-prd/SKILL.md	bash "$SC" work create --kind prd --body-file "$f" ${MILESTONE:+--milestone "$MILESTONE"}	#393
EOF
)"

# Every fenced bash/sh line in hand-authored skill prose, as `file<TAB>line`.
# Bundled references/ copies are excluded: sync-skill-references.sh pins them
# to these sources.
lines() {
    for f in */SKILL.md SYSTEM-OVERVIEW.md docs/*.md; do
        [ -f "$f" ] || continue
        awk -v F="$f" '/^```(bash|sh)$/{on=1; next} /^```$/{on=0} on{print F "\t" $0}' "$f"
    done
}

# Shape 1: `for NAME in $VAR` or `${VAR}`, unquoted, nothing else in the list.
# Shape 2: an unquoted `${VAR:+word}` / `${VAR:-word}` whose word has a space.
unsafe() {
    awk -F'\t' '
        { l = $2 }
        l ~ /for [A-Za-z_][A-Za-z0-9_]* in \$\{?[A-Za-z_][A-Za-z0-9_]*\}?[[:space:]]*(;|$)/ { print; next }
        {
            s = l
            while (match(s, /\$\{[A-Za-z_][A-Za-z0-9_]*:[-+][^}]* [^}]*\}/)) {
                pre = substr(s, 1, RSTART - 1)
                if (substr(pre, length(pre), 1) != "\"") { print; next }
                s = substr(s, RSTART + RLENGTH)
            }
        }'
}

printf '\n=== self-test: the matcher sees both shapes and passes the safe forms ===\n'
probe() { printf 'x.md\t%s\n' "$1" | unsafe | wc -l | tr -d ' '; }
# expect <0|1> <label> <line>: the matcher flags the line (1) or passes it (0).
expect() { if [ "$(probe "$3")" = "$1" ]; then ok "$2"; else bad "$2" "line: $3"; fi; }
# shellcheck disable=SC2016  # the probe lines are literal shell text, not expansions
{
expect 1 "flags for-in over an unquoted var"       'for id in $UNBLOCKED; do'
expect 1 "flags for-in over a braced var"          'for t in ${TERMS}'
expect 1 "flags unquoted multi-word :+ expansion"  'cmd ${M:+--milestone "$M"}'
expect 0 "passes while-read"                       'while IFS= read -r id; do'
expect 0 "passes a literal word list"              'for f in a b c; do'
expect 0 "passes a quoted \"\$@\""                   'for f in "$@"; do'
expect 0 "passes a quoted :+ expansion"            'x="${M:+--milestone $M}"'
expect 0 "passes a one-word :- default"            'echo ${M:-default}'
}

printf '\n=== skill blocks: no zsh-unsafe shape outside the known sites ===\n'
found="$(lines | unsafe)"
[ -n "$(lines)" ] || bad "no fenced bash blocks extracted" "the extraction found nothing; the scan would pass vacuously"
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    if grep -qxF -- "$hit" <<<"$(cut -f1,2 <<<"$known")"; then
        ok "known site, owned by $(printf '%s\n' "$known" | grep -F -- "$hit" | cut -f3): ${hit%%	*}"
    else
        bad "zsh-unsafe shape in a skill block" "$hit"
    fi
done <<<"$found"

printf '\n=== known sites still exist (the list only shrinks) ===\n'
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    site="$(printf '%s' "$entry" | cut -f1,2)"
    if grep -qxF -- "$site" <<<"$found"; then
        ok "still present: ${site%%	*}"
    else
        bad "known site no longer matches; remove its entry" "$site"
    fi
done <<<"$known"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
