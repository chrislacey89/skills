#!/usr/bin/env bash
# verify-install.sh — assert that a skills-install directory contains every
# bundled reference file declared in scripts/skill-references.manifest.
#
# Usage:
#   scripts/verify-install.sh <install-dir>
#
# <install-dir> is any directory that contains per-skill folders — typically
# ~/.claude/skills after a global install (`npx skills add ... --global`) or
# ./claude-code/skills after a project-scope install. The script is install-
# mechanism-agnostic: any tool that materializes <dir>/<skill>/ is verified.
#
# Exits 0 when every manifest entry has a corresponding file under
# <install-dir>/<skill>/references/<basename>. Exits 1 on any missing file,
# 2 on a usage / environment error.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <install-dir>" >&2
    exit 2
fi

install_dir="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$repo_root/scripts/skill-references.manifest"

if [[ ! -d "$install_dir" ]]; then
    echo "error: $install_dir is not a directory" >&2
    exit 2
fi

if [[ ! -f "$manifest" ]]; then
    echo "error: manifest not found at $manifest" >&2
    exit 2
fi

missing=0
present=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | awk '{$1=$1};1')"
    [[ -z "$line" ]] && continue

    src="$(printf '%s\n' "$line" | awk '{print $1}')"
    skill="$(printf '%s\n' "$line" | awk '{print $2}')"
    base="$(basename "$src")"
    expected="$install_dir/$skill/references/$base"

    if [[ -f "$expected" ]]; then
        present=$((present + 1))
    else
        echo "missing: $skill/references/$base (expected at $expected)"
        missing=$((missing + 1))
    fi
done < "$manifest"

if [[ $missing -ne 0 ]]; then
    echo ""
    echo "$missing bundled reference(s) missing from $install_dir" >&2
    echo "If the install completed without error, either the CLI did not ship" >&2
    echo "the skill's references/ subdir or the manifest is out of date." >&2
    exit 1
fi

echo "$present reference(s) present under $install_dir"
