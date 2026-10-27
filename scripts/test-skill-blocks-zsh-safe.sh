#!/usr/bin/env bash
# test-skill-blocks-zsh-safe.sh — fails on the two shell shapes that work in
# bash and break in zsh, wherever a skill documents a fenced bash/sh block.
#
# THE DRIFT CLASS. An agent copies a skill's fenced block and runs it in the
# harness shell, which on macOS is the login shell: zsh. zsh does not word-split
# an unquoted expansion, so
#   - `for x in $LIST` runs once, with the whole list as one word, and
#   - `${VAR:+--flag "$VAR"}` reaches the command as ONE argument.
#   - `"$REF:refs/x"` applies the history modifier `:r` to $REF, because zsh
#     reads `$NAME:<letter>` as a modifier even inside double quotes, and
#     prints `mainefs/x` for REF=main.
# A contract suite that executes blocks with `bash -c` alone does not see it. #393 found the first case in
# /execute's hooks gate; PR #561 shipped two more in /prd-to-issues three weeks
# later, caught only by a reviewer. See
# docs/solutions/patterns/skill-blocks-run-in-zsh-not-the-suites-bash-2026-10-25.md.
#
# The third shape is PR #612's: a Bitbucket refspec, `"+refs/heads/$DEST:refs/
# remotes/origin/$DEST"`, failed every zsh run while the suite ran it in bash.
#
# WHAT THIS DOES NOT SEE. It matches three shapes textually. Other bash/zsh
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
respond-to-review/SKILL.md	git fetch -q origin "+refs/heads/$DEST:refs/remotes/origin/$DEST" "+refs/heads/$SRC:refs/remotes/origin/$SRC" || { echo "fetch failed: no diff" >&2; exit 1; }	PR #612 re-review, Concern 1
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
# Shape 3: an unbraced `$VAR:` followed by a zsh history-modifier letter
#   (a A c e g h l P q Q r s t u x &), quoted or not. Other letters are literal in zsh.
unsafe() {
    awk -F'\t' '
        { l = $2 }
        l ~ /for [A-Za-z_][A-Za-z0-9_]* in \$\{?[A-Za-z_][A-Za-z0-9_]*\}?[[:space:]]*(;|$)/ { print; next }
        l ~ /\$[A-Za-z_][A-Za-z0-9_]*:[aAceghlPqQrstux&]/ { print; next }
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
expect 1 "flags an unbraced \$VAR:r in a refspec"   'git fetch origin "+refs/heads/$D:refs/remotes/origin/$D"'
expect 1 "flags an unbraced \$VAR:h"                 'cd $DIR:h'
expect 0 "passes a braced \${VAR}:r"                 'git fetch origin "+refs/heads/${D}:refs/remotes/origin/${D}"'
expect 0 "passes \$VAR:\$VAR (no modifier letter)"   'printf "%s" "$USER:$TOKEN"'
expect 0 "passes \$VAR:b (not a modifier)"           'echo "$A:b"'
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
