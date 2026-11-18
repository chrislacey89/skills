#!/usr/bin/env bash
# test-compound-citation-anchors.sh — contract test for /compound's rule that an
# entry cites anchors that survive a rewrite (#697).
#
# THE DRIFT CLASS. /compound's in-PR default writes the entry while the branch
# can still be rewritten: /pre-merge Phase 4's fold, the `fixup!` commits
# /fix-findings writes for it, and the squash merge each replace commit SHAs. An
# entry that cites the commit that taught the lesson by SHA is wrong after any
# of those steps, and a reader who runs `git show <sha>` gets "unknown revision"
# or, after a short-SHA collision, an unrelated commit. The failure is silent:
# the entry reads fluently and nothing resolves the citation.
#
# WHAT IT PINS, all extracted from the real file rather than restated here:
#   1. Phase 3 carries the rule next to the template's `## Related` section.
#   2. Phase 5 carries a DO-CONFIRM citation check, with the fenced block that
#      runs it.
#   3. That block, extracted and RUN against a fixture repo (under bash and
#      under zsh, the shell an agent runs it in), passes an entry that cites
#      only commits on the base and flags a commit that is not on the base, a
#      token that names nothing, and leaves a hex-looking word alone.
#   4. Mutation: with the ancestor test removed from the block, the flagging
#      assertions go red.
#
# Deliberately NOT pinned: the rule's wording. Phase 3 and Phase 5 may be
# reworded; the markers below are the bold lead-ins an edit would have to delete.

set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SK="$repo_root/compound/SKILL.md"
[ -f "$SK" ] || { printf 'FATAL %s is missing\n' "$SK"; exit 2; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Anchor Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

# block <file> <literal> — the first fenced bash block containing <literal>.
block() {
    awk -v want="$2" '
        /^ *```bash$/ { buf = ""; on = 1; ind = index($0, "`") - 1; next }
        on && /^ *```$/ { on = 0; if (index(buf, want)) { printf "%s", buf; exit } next }
        on { buf = buf substr($0, ind + 1) "\n" }
    ' "$1"
}

# -----------------------------------------------------------------------------
section "the rule and its check are in the skill"

rule_marker='**Cite what survives a rewrite.**'
check_marker='**Citation check (DO-CONFIRM'
rule_hits="$(grep -cF -- "$rule_marker" "$SK" || true)"
check_hits="$(grep -cF -- "$check_marker" "$SK" || true)"
check "Phase 3 states the rule once" 1 "$rule_hits"
check "Phase 5 carries the DO-CONFIRM once" 1 "$check_hits"

# The rule sits in Phase 3's template region, after `## Related` and before Phase 4.
rule_line="$(grep -nF -- "$rule_marker" "$SK" | head -1 | cut -d: -f1)"
related_line="$(grep -n '^## Related$' "$SK" | head -1 | cut -d: -f1)"
phase4_line="$(grep -n '^### Phase 4' "$SK" | head -1 | cut -d: -f1)"
if [ -n "$rule_line" ] && [ -n "$related_line" ] && [ -n "$phase4_line" ] \
    && [ "$rule_line" -gt "$related_line" ] && [ "$rule_line" -lt "$phase4_line" ]; then
    ok "the rule sits between the template's ## Related and Phase 4"
else
    bad "the rule is not between ## Related and Phase 4" "rule=$rule_line related=$related_line phase4=$phase4_line"
fi

check_line="$(grep -nF -- "$check_marker" "$SK" | head -1 | cut -d: -f1)"
phase5_line="$(grep -n '^### Phase 5' "$SK" | head -1 | cut -d: -f1)"
phase6_line="$(grep -n '^### Phase 6' "$SK" | head -1 | cut -d: -f1)"
if [ -n "$check_line" ] && [ -n "$phase5_line" ] && [ -n "$phase6_line" ] \
    && [ "$check_line" -gt "$phase5_line" ] && [ "$check_line" -lt "$phase6_line" ]; then
    ok "the DO-CONFIRM sits inside Phase 5"
else
    bad "the DO-CONFIRM is not inside Phase 5" "check=$check_line phase5=$phase5_line phase6=$phase6_line"
fi

# -----------------------------------------------------------------------------
section "the citation-check block, run"

# shellcheck disable=SC2016  # the needle is the skill's literal text
blk="$(block "$SK" 'git merge-base --is-ancestor "$tok" "$BASE_REF"')"
if [ -z "$blk" ]; then
    bad "Phase 5's citation check carries a fenced block that tests each hex token against the base" "not found"
    printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi
ok "Phase 5's citation check carries a fenced block"

R="$tmp/repo"
git init -q "$R"
git -C "$R" commit -q --allow-empty -m "root"
git -C "$R" commit -q --allow-empty -m "on base"
ON_BASE="$(git -C "$R" rev-parse HEAD)"
git -C "$R" switch -q -c feature
git -C "$R" commit -q --allow-empty -m "feature only"
OFF_BASE="$(git -C "$R" rev-parse HEAD)"
GONE="0123456789abcdef0123456789abcdef01234567"

run_block() {  # $1 = entry file, $2 = shell, $3 = block text
    local b="${3//<path\/to\/entry.md>/$1}"
    out="$(cd "$R" && BASE_REF=main "$2" -c "$b" 2>"$tmp/stderr")"; rc=$?
}

printf 'The lesson came from %s, merged in PR #12.\nA word that only looks like hex: defaced, and decade.\n' "${ON_BASE:0:10}" > "$tmp/clean.md"
printf 'The lesson came from %s.\nAnd from %s.\n' "${OFF_BASE:0:10}" "$GONE" > "$tmp/stale.md"

for sh in bash zsh; do
    if ! command -v "$sh" >/dev/null 2>&1; then printf '  SKIP %s not installed\n' "$sh"; continue; fi
    run_block "$tmp/clean.md" "$sh" "$blk"
    check "$sh: an entry citing only the base's commits exits 0" 0 "$rc"
    check "$sh: it flags nothing" "" "$out"
    run_block "$tmp/stale.md" "$sh" "$blk"
    check "$sh: an entry citing a commit off the base exits 1" 1 "$rc"
    check "$sh: it names the off-base SHA" 1 "$(grep -c -- "${OFF_BASE:0:10}" <<<"$out")"
    check "$sh: it names the SHA that resolves to nothing" 1 "$(grep -c -- "$GONE" <<<"$out")"
done

# -----------------------------------------------------------------------------
section "mutation: the check sees a block that flags nothing"

# shellcheck disable=SC2016
mut="${blk//git merge-base --is-ancestor \"\$tok\" \"\$BASE_REF\"/true}"
run_block "$tmp/stale.md" bash "$mut"
check "with the ancestor test replaced by true, the stale entry passes (the assertions above would go red)" 0 "$rc"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
