#!/usr/bin/env bash
# sync-skill-references.sh — mirror shared docs into each consuming skill's references/
#
# The `skills` npm CLI ships only files inside a skill directory. Any
# SYSTEM-OVERVIEW.md or docs/*.md a skill references at runtime must be
# copied into that skill's references/ subdirectory so the install carries it.
#
# Usage:
#   scripts/sync-skill-references.sh           # copy sources → destinations
#   scripts/sync-skill-references.sh --check   # exit non-zero if any destination drifts
#
# Mapping lives in scripts/skill-references.manifest.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$repo_root/scripts/skill-references.manifest"
mode="sync"

if [[ "${1:-}" == "--check" ]]; then
    mode="check"
elif [[ $# -gt 0 ]]; then
    echo "usage: $0 [--check]" >&2
    exit 2
fi

if [[ ! -f "$manifest" ]]; then
    echo "error: manifest not found at $manifest" >&2
    exit 2
fi

drift=0
synced=0

while IFS= read -r line || [[ -n "$line" ]]; do
    # strip comments and trim
    line="${line%%#*}"
    line="$(printf '%s' "$line" | awk '{$1=$1};1')"
    [[ -z "$line" ]] && continue

    # split on first whitespace run
    src="$(printf '%s\n' "$line" | awk '{print $1}')"
    skill="$(printf '%s\n' "$line" | awk '{print $2}')"

    if [[ -z "$src" || -z "$skill" ]]; then
        echo "error: malformed manifest line: $line" >&2
        exit 2
    fi

    src_path="$repo_root/$src"
    dst_dir="$repo_root/$skill/references"
    dst_path="$dst_dir/$(basename "$src")"

    if [[ ! -f "$src_path" ]]; then
        echo "error: source missing: $src (referenced by $skill)" >&2
        exit 2
    fi

    if [[ ! -d "$repo_root/$skill" ]]; then
        echo "error: skill dir missing: $skill" >&2
        exit 2
    fi

    if [[ "$mode" == "check" ]]; then
        if [[ ! -f "$dst_path" ]] || ! cmp -s "$src_path" "$dst_path"; then
            echo "drift: $skill/references/$(basename "$src") differs from $src"
            drift=1
        fi
    else
        mkdir -p "$dst_dir"
        cp "$src_path" "$dst_path"
        synced=$((synced + 1))
    fi
done < "$manifest"

if [[ "$mode" == "check" ]]; then
    if [[ $drift -ne 0 ]]; then
        echo "" >&2
        echo "Run scripts/sync-skill-references.sh to update bundled copies." >&2
        exit 1
    fi
    echo "All bundled references match their canonical sources."
else
    echo "Synced $synced bundled reference(s)."
fi
