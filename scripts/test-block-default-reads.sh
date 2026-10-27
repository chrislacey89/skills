#!/usr/bin/env bash
# test-block-default-reads.sh — a skill's command block may not read
# "${VAR:-...}" for a variable it has not assigned earlier in the same block.
#
# THE DRIFT CLASS. An agent runs each fenced block in a fresh shell, so a
# variable another block set is unset here. "${VAR:-}" turns that into an empty
# value with exit 0: the block carries on and does the wrong thing quietly.
# "${VAR:?...}" fails loudly and is not flagged. The repo's suites hide the
# defect by presetting the variable in the environment when they run the block,
# a path no real run takes, so the test passes on exactly the input that never
# arrives.
#
# THE INCIDENTS. docs/solutions/patterns/skill-command-blocks-run-one-shell-per-call-2026-10-13.md
# (/excavate, #403) recorded the pattern. It recurred at /pre-merge Phase 4's
# sidecar stamp, `--base-ref "${BASE_REF:-}"` (PR #529 finding 6, then #604 S5),
# and in the S5 fix's sibling on #604: `[ -n "${BASE_BRANCH:-}" ] || BASE_BRANCH=...`
# keeps a stacked-PR override that cannot reach the block, and its test passed
# only because it preset BASE_BRANCH. Review caught each one; nothing checked.
# docs/solutions/testing-patterns/a-preset-variable-tests-a-path-no-run-takes-2026-10-26.md
#
# WHAT IT PINS
#   1. The scanner flags the incident shapes and passes the assign-then-read
#      shape, on fixtures (so a scanner that finds nothing is not read as clean).
#   2. Every canonical SKILL.md and docs/*.md block is clean, except the entries
#      in KNOWN, each with its reason. A KNOWN entry that no longer matches fails
#      too, so the list cannot outlive the code it excuses.
#
# NOT COVERED. A plain "$VAR" read of another block's variable is not flagged:
# too many blocks legitimately read placeholders and loop variables that a regex
# cannot tell apart. Nor is a read inside a function body defined in the block.

set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }

# Variables a block may read from the environment it was started in: the
# harness or the user sets them, not another block.
ENV_VARS="HOME PATH TMPDIR PWD USER SHELL IFS CI CLAUDE_PROJECT_DIR CONDUCTOR_WORKSPACE_PATH CODESPACES REMOTE_CONTAINERS SKILL_KIT_SIDECAR_ROOT SKILL_KIT_RESEARCH_ARCHIVE BITBUCKET_TOKEN BITBUCKET_EMAIL"

# file<TAB>var<TAB>reason. Remove an entry in the commit that fixes it.
KNOWN="ts-audit/SKILL.md	CLAUDE_LIBRARY_DIR	a user's own override of the library path, set in their environment"

# scan <file>... — prints file<TAB>line<TAB>var for each read-before-assign default.
scan() {
    awk -v env=" $ENV_VARS " '
        FNR == 1 { infence = 0; inb = 0 }
        # infence tracks every fence; inb only the shell ones. A non-shell
        # fence still has to be closed, or its closing line reads as an opening.
        /^[[:space:]]*```/ {
            if (infence) { infence = 0; inb = 0; next }
            infence = 1
            lang = $0; sub(/^[[:space:]]*```/, "", lang); gsub(/[[:space:]]/, "", lang)
            inb = (lang == "" || lang == "bash" || lang == "sh" || lang == "shell" || lang == "zsh")
            split("", seen); next
        }
        !inb { next }
        {
            line = $0
            # A loop or read variable is bound before the body that reads it.
            rest = line
            while (match(rest, /(for|read( -r)?)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                a = substr(rest, RSTART, RLENGTH); sub(/.*[[:space:]]/, "", a); seen[a] = 1
                rest = substr(rest, RSTART + RLENGTH)
            }
            rest = line
            while (match(rest, /\$\{[A-Za-z_][A-Za-z0-9_]*:-/)) {
                v = substr(rest, RSTART + 2, RLENGTH - 4)
                if (!(v in seen) && index(env, " " v " ") == 0) printf "%s\t%d\t%s\n", FILENAME, FNR, v
                rest = substr(rest, RSTART + RLENGTH)
            }
            rest = line
            while (match(rest, /(^|[[:space:];(&|{])(export[[:space:]]+|local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) {
                a = substr(rest, RSTART, RLENGTH - 1)
                sub(/^[[:space:];(&|{]/, "", a); sub(/^(export|local)[[:space:]]+/, "", a)
                seen[a] = 1
                rest = substr(rest, RSTART + RLENGTH)
            }
        }
    ' "$@"
}

# -----------------------------------------------------------------------------
section "the scanner flags the incident shapes and passes the safe ones"

fx="$(mktemp -d)"
trap 'rm -rf "$fx"' EXIT
cat > "$fx/stamp.md" <<'EOF'
```markdown
a non-shell fence first, so its closing line must not read as an opening
```
```bash
SC="x"
bash "$SC" stamp write b "$SHA" --base-ref "${BASE_REF:-}"
```
EOF
cat > "$fx/preset.md" <<'EOF'
```bash
[ -n "${BASE_BRANCH:-}" ] || BASE_BRANCH=$(bash "$SC" base-ref --name)
```
EOF
cat > "$fx/safe.md" <<'EOF'
```bash
BASE_REF=$(bash "$SC" base-ref) || exit 1
echo "${BASE_REF:-none}" "${HOME:-/}" "${SCOPE_FROM:?derive it first}"
for f in a b; do echo "${f:-}"; done
```
```markdown
${NOT_SHELL:-ignored}
```
EOF
case "$(scan "$fx/stamp.md")" in *"	BASE_REF") ok "flags --base-ref \"\${BASE_REF:-}\" in a block that never sets BASE_REF" ;; *) bad "the stamp-block shape is not flagged" ;; esac
case "$(scan "$fx/preset.md")" in *"	BASE_BRANCH") ok "flags a read that precedes the block's own assignment" ;; *) bad "the keep-a-preset shape is not flagged" ;; esac
got="$(scan "$fx/safe.md")"
if [ -z "$got" ]; then ok "passes assign-then-read, environment variables, :? guards, loop variables, and non-shell fences"; else bad "flags a safe shape" "$got"; fi

# -----------------------------------------------------------------------------
section "skill and docs blocks: no unlisted read-before-assign default"

files=()
for f in ./*/SKILL.md docs/*.md; do files+=("${f#./}"); done
found="$(scan "${files[@]}" | sort -u)"
# Captured, then matched as strings: `grep -q` at the end of a pipe under
# pipefail can report a match as a miss (scripts/test-pipefail-safe-matchers.sh).
known_keys="$(printf '%s\n' "$KNOWN" | cut -f1,2)"
found_keys="$(printf '%s\n' "$found" | cut -f1,3)"
if [ "${#files[@]}" -ge 40 ]; then ok "scanned ${#files[@]} canonical files"; else bad "scanned only ${#files[@]} files; the glob is broken"; fi

while IFS=$'\t' read -r file line var; do
    [ -n "$file" ] || continue
    if [[ $'\n'"$known_keys"$'\n' == *$'\n'"$file	$var"$'\n'* ]]; then
        ok "$file:$line \${$var:-} is listed in KNOWN"
    else
        bad "$file:$line reads \${$var:-} before the block assigns it" \
            "a fresh shell has it unset, so this defaults silently; assign it in this block, or use \${$var:?...} to fail loudly"
    fi
done <<<"$found"

while IFS=$'\t' read -r file var _; do
    [ -n "$file" ] || continue
    if [[ $'\n'"$found_keys"$'\n' == *$'\n'"$file	$var"$'\n'* ]]; then
        ok "KNOWN entry $file $var still matches a block"
    else
        bad "KNOWN entry $file $var matches nothing; remove it"
    fi
done <<<"$KNOWN"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
