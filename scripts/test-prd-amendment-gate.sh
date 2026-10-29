#!/usr/bin/env bash
# test-prd-amendment-gate.sh — contract test for /execute Step 0's parent-PRD
# amendment gate (#617).
#
# The incident: a parent PRD was amended after /prd-to-issues cut its slices,
# tightening a rule. The slice's acceptance criterion kept the older, looser
# wording, and the implementation, its test, the author's verification and
# every /pre-merge pass followed the slice text. Nothing in the pack compared a
# PRD body edited after decomposition with the slices already cut from it, so
# /correct-course, the route that reconciles them, never ran.
#
# The gate is executable prose in execute/SKILL.md: a bash block that reads the
# slice's `## Parent PRD` number, asks GitHub when the PRD body was last edited
# (`lastEditedAt`, which comments do not move) and when the latest
# `Decomposed into:` comment was posted, and prints one verdict. This suite
# extracts that block verbatim, runs it against a stubbed `gh`, and asserts the
# verdict for every state the prose names — including the two fail-open
# shapes: a read that came back short, and a slice body that could not be read.
#
# It also pins the gate's `Decomposed into:` matcher to the issue-shape gate's,
# so the two readers of /prd-to-issues §8's comment cannot drift apart.

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec_skill="$repo_root/execute/SKILL.md"

pass=0
fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
assert_eq() {
    if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3" "expected: $1 | got: $2"; fi
}

# The fenced bash block in execute/SKILL.md that defines AMEND_JQ.
block="$(awk '
    /^```bash$/ { buf = ""; on = 1; next }
    on && /^```$/ { on = 0; if (index(buf, "AMEND_JQ=")) { printf "%s", buf; exit } next }
    on { buf = buf $0 "\n" }
' "$exec_skill")"

printf '\n== the gate block exists\n'
if [[ -n "$block" ]]; then ok "execute/SKILL.md carries the AMEND_JQ block"; else
    bad "execute/SKILL.md carries the AMEND_JQ block" "not found"
    printf '\n%d passed, %d failed\n' "$pass" "$fail"; exit 1
fi
case "$block" in *'N=<n>'*) ok "block takes the slice number as N=<n>" ;; *) bad "block takes the slice number as N=<n>" "placeholder missing" ;; esac

printf '\n== the two Decomposed-into matchers agree\n'
# shellcheck disable=SC2016  # the needle is the skill's literal text
shape_re="$(grep -o 'test("^Decomposed into: #\[0-9\]+")' "$exec_skill" | sort -u)"
count="$(grep -c 'test("^Decomposed into: #\[0-9\]+")' "$exec_skill")"
if [[ "$(wc -l <<<"$shape_re" | tr -d ' ')" == 1 && "$count" -ge 2 ]]; then
    ok "issue-shape gate and amendment gate use one matcher ($count sites)"
else
    bad "issue-shape gate and amendment gate use one matcher" "found $count sites: $shape_re"
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"

# Stub gh: `gh issue view` prints $SLICE_BODY (or fails when SLICE_FAIL=1);
# `gh api graphql` prints $GQL (or fails when GQL_FAIL=1).
cat >"$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "issue view") [[ "${SLICE_FAIL:-0}" == 1 ]] && exit 1; printf '%s\n' "$SLICE_BODY" ;;
    "api graphql") [[ "${GQL_FAIL:-0}" == 1 ]] && exit 1; printf '%s\n' "$GQL" ;;
    *) echo "unexpected gh call: $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$scratch/bin/gh"

run_gate() {
    local script="$scratch/gate.sh"
    printf '%s' "${block//N=<n>/N=42}" >"$script"
    PATH="$scratch/bin:$PATH" bash "$script" 2>/dev/null | tail -n 1
}

slice_with_parent=$'## Parent PRD\n\n#7\n\n## What to Build\n\nThing.\n\n## Acceptance Criteria\n\n- [ ] limit is 10'
slice_no_parent=$'## What to Build\n\nA one-off.\n\n## Acceptance Criteria\n\n- [ ] done'

gql() {
    # gql <lastEditedAt|null> <comments-json> [totalCount]
    local edited="$1" comments="$2" total="${3:-}"
    [[ -n "$total" ]] || total="$(jq 'length' <<<"$comments")"
    jq -cn --argjson e "$edited" --argjson c "$comments" --argjson t "$total" \
        '{data:{repository:{issue:{number:7, lastEditedAt:$e, comments:{totalCount:$t, nodes:$c}}}}}'
}
decomp() { jq -cn --arg at "$1" --arg b "${2:-Decomposed into: #41, #42}" '{body:$b, createdAt:$at}'; }

printf '\n== verdicts\n'
export SLICE_BODY GQL SLICE_FAIL GQL_FAIL
SLICE_FAIL=0 GQL_FAIL=0

SLICE_BODY="$slice_with_parent"
GQL="$(gql null "[$(decomp 2026-10-01T00:00:00Z)]")"
assert_eq "prd-unchanged" "$(run_gate)" "PRD never edited → prd-unchanged"

GQL="$(gql '"2026-09-30T12:00:00Z"' "[$(decomp 2026-10-01T00:00:00Z)]")"
assert_eq "prd-unchanged" "$(run_gate)" "PRD edited before decomposition → prd-unchanged"

GQL="$(gql '"2026-10-01T00:00:00Z"' "[$(decomp 2026-10-01T00:00:00Z)]")"
assert_eq "prd-unchanged" "$(run_gate)" "edit at the decomposition's own second → prd-unchanged (strictly later fires)"

GQL="$(gql '"2026-10-05T09:00:00Z"' "[$(decomp 2026-10-01T00:00:00Z)]")"
assert_eq "prd-edited-after-decomposition edited=2026-10-05T09:00:00Z decomposed=2026-10-01T00:00:00Z" \
    "$(run_gate)" "PRD edited after decomposition → prd-edited-after-decomposition"

GQL="$(gql '"2026-10-05T09:00:00Z"' "[$(decomp 2026-10-01T00:00:00Z),{\"body\":\"looks good\",\"createdAt\":\"2026-10-06T00:00:00Z\"},$(decomp 2026-10-07T00:00:00Z)]")"
assert_eq "prd-unchanged" "$(run_gate)" "edit between two decompositions → the latest comment wins"

GQL="$(gql '"2026-10-05T09:00:00Z"' "[$(decomp 2026-10-01T00:00:00Z $'Re-cut after review.\nDecomposed into: #50')]")"
assert_eq "prd-edited-after-decomposition edited=2026-10-05T09:00:00Z decomposed=2026-10-01T00:00:00Z" \
    "$(run_gate)" "Decomposed-into line on a later line of the comment still counts"

GQL="$(gql '"2026-10-05T09:00:00Z"' '[{"body":"Not Decomposed into: #3","createdAt":"2026-10-09T00:00:00Z"}]')"
assert_eq "no-decomposition-record" "$(run_gate)" "matcher is anchored: a mid-line mention is not a decomposition"

GQL="$(gql null '[]')"
assert_eq "no-decomposition-record" "$(run_gate)" "no Decomposed-into comment → no-decomposition-record"

GQL="$(gql null "[$(decomp 2026-10-01T00:00:00Z)]" 150)"
assert_eq "unknown" "$(run_gate)" "comment list shorter than its totalCount → unknown"

GQL='{"errors":[{"message":"rate limited"}]}'
assert_eq "unknown" "$(run_gate)" "GraphQL errors → unknown"

GQL="$(jq -c '.data.repository.issue.number = 8' <<<"$(gql null '[]')")"
assert_eq "unknown" "$(run_gate)" "response for a different issue → unknown"

GQL_FAIL=1
assert_eq "unknown" "$(run_gate)" "gh api failure → unknown"
GQL_FAIL=0

SLICE_FAIL=1
assert_eq "unknown" "$(run_gate)" "slice body read failure → unknown, not no-parent-prd"
SLICE_FAIL=0

SLICE_BODY="$slice_no_parent"
assert_eq "no-parent-prd" "$(run_gate)" "slice without a Parent PRD section → no-parent-prd"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
