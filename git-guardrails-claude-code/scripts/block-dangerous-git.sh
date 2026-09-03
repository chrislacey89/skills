#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

DANGEROUS_PATTERNS=(
  "git reset --hard"
  "git clean -fd"
  "git clean -f"
  "git branch -D"
  "git checkout \."
  "git restore \."
  "push --force"
  "reset --hard"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# Review currency: refuse `gh pr merge` when the PR head has moved past the SHA
# /pre-merge stamped into the body.
#
# /closeout Step 2 already performs this read — but only when the merge goes
# through /closeout. A merge typed by hand, or issued by an AFK loop, skips it
# entirely, and that is precisely the unattended case where nobody notices the
# reviewed diff is not the merged diff. The hook makes the read unskippable at
# the one command that matters.
#
# The sed below is byte-identical to /closeout's by contract, not by intent:
# scripts/test-review-currency-marker.sh in chrislacey89/skills extracts this
# line and requires it to equal the one in closeout/SKILL.md, and runs this
# script end to end against a stubbed `gh`.
#
# Fails OPEN everywhere it cannot be certain — no gh, no jq, a failed API call,
# an unstamped PR, a selector it cannot resolve. A gate that refuses wrongly is
# a gate that gets deleted, and the cost of a miss here is one merge that
# /closeout would also have missed.
if echo "$COMMAND" | grep -qE '(^|[;&|(]|[[:space:]])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'; then
  # Named in the refusal message below, so the escape hatch is discoverable at
  # the moment it is needed rather than only in this file.
  if [ -n "${ALLOW_STALE_STAMP_MERGE:-}" ]; then
    exit 0
  fi
  if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  # Which PR would this merge? `gh pr merge [<number> | <url> | <branch>]`
  # takes an optional positional selector and defaults to the current branch.
  # Only two forms are resolvable without re-authoring gh's flag table (which
  # would be a paraphrase of another tool's docs, and a permanent drift
  # liability): the selector immediately after `merge`, or no selector at all.
  # A flag before the positional means a bare token could equally be that
  # flag's value, so the hook declines to guess and lets the command through.
  read -r -a GH_TOK <<< "$COMMAND"
  PR_SELECTOR=""
  SELECTOR_STATE="none"
  for ((i = 0; i + 2 < ${#GH_TOK[@]}; i++)); do
    if [ "${GH_TOK[i]}" = "gh" ] && [ "${GH_TOK[i + 1]}" = "pr" ] && [ "${GH_TOK[i + 2]}" = "merge" ]; then
      for ((j = i + 3; j < ${#GH_TOK[@]}; j++)); do
        tok="${GH_TOK[j]}"
        case "$tok" in
          ';'|'&'|'&&'|'|'|'||'|'>'|'>>'|'<') break ;;
          -*) continue ;;
        esac
        if [ "$j" -eq "$((i + 3))" ]; then
          PR_SELECTOR="${tok%\"}"; PR_SELECTOR="${PR_SELECTOR#\"}"
          PR_SELECTOR="${PR_SELECTOR%\'}"; PR_SELECTOR="${PR_SELECTOR#\'}"
          PR_SELECTOR="${PR_SELECTOR%;}"
          SELECTOR_STATE="explicit"
        else
          SELECTOR_STATE="ambiguous"
        fi
        break
      done
      break
    fi
  done
  if [ "$SELECTOR_STATE" = "ambiguous" ]; then
    exit 0
  fi

  GH_ARGS=(pr view)
  if [ -n "$PR_SELECTOR" ]; then
    GH_ARGS+=("$PR_SELECTOR")
  fi
  # shellcheck disable=SC2054  # gh's --json takes ONE comma-separated field list, not two array elements
  GH_ARGS+=(--json body,headRefOid)
  PR_JSON=$(gh "${GH_ARGS[@]}" 2>/dev/null) || exit 0
  [ -n "$PR_JSON" ] || exit 0

  HEAD_OID=$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // empty' 2>/dev/null)
  REVIEWED_SHA=$(printf '%s' "$PR_JSON" | jq -r '.body // empty' 2>/dev/null | sed -n 's/.*<!-- reviewed-at: \([0-9a-f]\{40\}\) -->.*/\1/p' | tail -1)

  # No stamp is not evidence of an unreviewed diff — hand-authored PRs, external
  # contributions, and PRs predating the stamp all land here. /closeout treats
  # this the same way, and refusing on every unstamped PR is the alarm fatigue
  # that gets a gate reflexively defeated.
  if [ -n "$REVIEWED_SHA" ] && [ -n "$HEAD_OID" ] && [ "$REVIEWED_SHA" != "$HEAD_OID" ]; then
    if git cat-file -e "${REVIEWED_SHA}^{commit}" 2>/dev/null && git cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
      DELTA="$(git rev-list --count "$REVIEWED_SHA".."$HEAD_OID" 2>/dev/null) commit(s) past the stamp;$(git diff --shortstat "$REVIEWED_SHA".."$HEAD_OID" 2>/dev/null)"
    else
      # /closeout says this explicitly and it is worth repeating: an
      # unmeasurable delta means the reviewed commit was rewritten away or was
      # never fetched here. That is a stronger divergence signal than a
      # measurable one, not a weaker one.
      DELTA="delta not measurable in this checkout — the reviewed commit is not present (force-pushed away, or never fetched)"
    fi
    echo "BLOCKED: '$COMMAND' would merge a PR whose head has moved past the SHA /pre-merge reviewed." >&2
    echo "  reviewed-at: $REVIEWED_SHA" >&2
    echo "  PR head:     $HEAD_OID" >&2
    echo "  delta:       $DELTA" >&2
    echo "Re-review the delta with /pre-merge (it re-stamps at the new head), or run the merge again with ALLOW_STALE_STAMP_MERGE=1 to accept it as-is." >&2
    exit 2
  fi
fi

exit 0
