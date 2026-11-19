#!/usr/bin/env bash
# Check that every skill directory's SKILL.md frontmatter `name:` is present
# and equals the directory name. The skill installer keys on that name, so a
# mismatch installs the skill under a name nothing else in the repo uses.
#
# Usage: scripts/check-skill-names.sh [repo-root]   (default: the repo this
# script lives in). Exits 1 when any skill is wrong. Runs on macOS bash 3.2
# and on CI: the frontmatter is read with awk, not GNU-only `head -n -1`.
set -u

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
errors=0
count=0

for skill_file in "$root"/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  count=$((count + 1))
  dir_name="$(basename "$(dirname "$skill_file")")"
  rel="$dir_name/SKILL.md"

  # Frontmatter is the text between the first two `---` lines.
  name="$(awk 'NR == 1 { next } /^---$/ { exit } /^name:/ { sub(/^name: */, ""); print; exit }' "$skill_file")"

  if [ -z "$name" ]; then
    echo "ERROR: $rel missing 'name' field"
    errors=$((errors + 1))
  elif [ "$name" != "$dir_name" ]; then
    echo "ERROR: $rel name '$name' does not match directory '$dir_name'"
    errors=$((errors + 1))
  fi
done

echo ""
echo "Validated $count skills, $errors errors"
[ "$errors" -eq 0 ]
