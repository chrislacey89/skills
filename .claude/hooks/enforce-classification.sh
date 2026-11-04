#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Implementation patterns — populated at install time from the user's answer to
# the /init-pipeline trigger-surface question. Over-gating is intended.
IMPL_PATTERNS=("*.ts" "*.tsx" "*.astro" "*.py" "*.go" "*.rb" "*.java" "*.rs" "*.js" "*.jsx" "*.vue" "*.svelte")

MATCHED=0
for pattern in "${IMPL_PATTERNS[@]}"; do
  # The unquoted right-hand side is the point: each entry is a glob.
  # shellcheck disable=SC2053
  if [[ "$FILE_PATH" == $pattern ]]; then MATCHED=1; break; fi
done
if [ $MATCHED -eq 0 ]; then exit 0; fi

# Skip test files and type declarations (extension-agnostic)
if [[ "$FILE_PATH" == *test* || "$FILE_PATH" == *spec* || "$FILE_PATH" == *.d.ts ]]; then
  exit 0
fi
# Skip config files (drizzle.config, vite.config, etc.)
if [[ "$FILE_PATH" == *.config.* ]]; then
  exit 0
fi
# Check for classification markers — on a file inside this project only. A
# Write to /tmp/scratch.ts or a sibling checkout is no business of either clause
# below, and refusing it sends the agent to /tdd, or to deleting .review-stamped,
# for a file the pipeline does not own. Both sides are resolved through `cd -P`
# first, the file through its nearest existing directory, so neither `..` nor a
# symlink carries a path across the boundary in either direction. A relative
# path is read against the project. The sentinel line below is how /execute
# Step 0 tells this clause apart from a hook that predates it.
# gate: project-scope
if [ -n "$CLAUDE_PROJECT_DIR" ]; then
  root=$(cd -P "$CLAUDE_PROJECT_DIR" 2>/dev/null && pwd -P)
  case "$FILE_PATH" in /*) path=$FILE_PATH ;; *) path="${CLAUDE_PROJECT_DIR%/}/$FILE_PATH" ;; esac
  dir=$(dirname "$path"); rest=$(basename "$path")
  while [ ! -d "$dir" ]; do rest="$(basename "$dir")/$rest"; dir=$(dirname "$dir"); done
  case "$(cd -P "$dir" && pwd -P)/$rest" in "${root%/}"/*) ;; *) exit 0 ;; esac
fi
# Stand down on a stamped branch, so the
# post-review clause below is the one that decides there. /execute Step 6 removes
# EVERY classification marker before it hands off to /pre-merge, so by the time
# .review-stamped exists there is never a marker left for this test to find.
# Without the .review-stamped term, this clause short-circuits every post-review
# write: the /fix-findings fixer is refused outright, and the authoring session is
# refused by the wrong clause, under a message that names /tdd and never names the
# route the lock was built to offer.
if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.review-stamped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-active" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.tdd-skipped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.lfg-active" ]; then
  echo '{"decision":"block","reason":"BLOCKED: classify work in /execute Step 3 before writing implementation files. Either invoke /tdd (backend/behavior-heavy), create .claude/.tdd-skipped (visual frontend), or invoke /lfg (proof-of-concept mode)."}' >&2
  exit 2
fi
# Post-review edit lock. /pre-merge Phase 4 touches .review-stamped beside the
# review-currency stamp; /fix-findings touches .fix-findings-active when it
# loads and removes it when it reports. Between those two, an implementation
# edit is a post-review fix authored by the session the review just went around.
if [ -f "$CLAUDE_PROJECT_DIR/.claude/.review-stamped" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/.fix-findings-active" ]; then
  echo '{"decision":"block","reason":"BLOCKED: this branch has been reviewed and stamped. A post-review fix needs an independent author. Ask the human which findings to fix and run /fix-findings with exactly the numbers they name (never numbers you chose), or delete .claude/.review-stamped to take the edit yourself."}' >&2
  exit 2
fi
exit 0
