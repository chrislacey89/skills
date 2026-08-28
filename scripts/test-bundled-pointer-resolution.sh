#!/usr/bin/env bash
# test-bundled-pointer-resolution.sh — a skill that points at a bundled
# reference must point at a path that exists, from that file's own directory,
# both in-repo and after install.
#
# THE DRIFT CLASS. The `skills` CLI installs each skill as a self-contained
# directory. A shared doc reaches a skill only through
# scripts/skill-references.manifest, which copies it to <skill>/references/.
# So a pointer written from a file at the skill root must read
# `references/<file>.md`, and a pointer written from a file already inside
# references/ must read `<file>.md` — the bare sibling form. Get the two
# confused and the link resolves to references/references/<file>.md, which
# exists nowhere. Nothing in the repo checked this.
#
# THE INCIDENT. #246 shipped exactly that bug:
# docs/solutions/architecture-decisions/sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md:23
# records `references/visual-recap-design.md` written into visual-recap/SKILL.md
# — a file itself bundled into references/ — "so it would resolve to
# references/references/". Two review passes caught it. No check did.
#
# WHAT IT PINS, every side extracted from the real files:
#   1. Every markdown link of the form `](references/<name>.md)` in a tracked
#      skill file resolves to a real file, from that file's own directory.
#   2. No tracked file inside a references/ directory writes a
#      `](references/...)` link — from there the sibling form is the correct
#      one and the references/ prefix is the recorded bug.
#   3. Every <skill>/references/ file whose content matches a docs/ or
#      repo-root file has a manifest row. A hand-copied duplicate with no row
#      is not synced and not checked, so it drifts silently — which is the
#      failure the manifest exists to prevent. Skill-local references with no
#      counterpart upstream (mermaid/references/*.md, tdd/tests.md) are not
#      copies of anything and are deliberately out of scope.

set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }

manifest="scripts/skill-references.manifest"
[ -f "$manifest" ] || { printf 'FATAL %s is missing\n' "$manifest"; exit 1; }

# The set of <skill>/references/<file> paths the manifest is contracted to produce.
produced="$(awk '!/^[[:space:]]*#/ && NF >= 2 { n = $1; sub(/^.*\//, "", n); print $2 "/references/" n }' "$manifest" | sort -u)"
[ -n "$produced" ] || { printf 'FATAL the manifest produced no rows — parser or file changed shape\n'; exit 1; }

# Every tracked markdown file that is part of a skill (top-level dir holding a SKILL.md).
skill_md_files="$(git ls-files '*.md' | awk -F/ 'NF > 1 { print }' | while read -r f; do
    [ -f "${f%%/*}/SKILL.md" ] && printf '%s\n' "$f"
done)"
[ -n "$skill_md_files" ] || { printf 'FATAL found no skill markdown files — the discovery step changed shape\n'; exit 1; }

checked=0
for f in $skill_md_files; do
    dir="$(dirname "$f")"
    # Whitespace-normalize: a link split across a wrapped line is still a link.
    links="$(tr '\n' ' ' < "$f" | grep -o '](references/[A-Za-z0-9._-]*\.md)' | tr -d '](' | sed 's/)$//' | sort -u)"
    for rel in $links; do
        checked=$((checked + 1))
        target="$dir/$rel"
        case "$f" in
            */references/*)
                bad "$f writes a \`$rel\` link from inside references/" \
                    "from there the correct form is the bare sibling; this resolves to references/references/." ;;
            *)
                if [ -f "$target" ]; then
                    ok "$f -> $target"
                else
                    bad "$f points at $rel, which does not resolve" \
                        "expected $target to exist; run scripts/sync-skill-references.sh or fix the path."
                fi ;;
        esac
    done
done

# 3. An un-synced hand copy drifts in silence. Any file under a skill's
# references/ that duplicates a docs/ or repo-root file must be manifest-driven.
upstreams="$(git ls-files 'docs/*.md' '*.md' | awk -F/ 'NF == 1 || $1 == "docs"')"
copies=0
for bundled in $(git ls-files '*/references/*.md'); do
    for up in $upstreams; do
        if cmp -s "$bundled" "$up"; then
            copies=$((copies + 1))
            if grep -qxF "$bundled" <<<"$produced"; then
                ok "$bundled is a synced copy of $up, and the manifest says so"
            else
                bad "$bundled is byte-identical to $up with no manifest row" \
                    "add \"$up  ${bundled%%/*}\" to $manifest, or the copy drifts unchecked."
            fi
            break
        fi
    done
done
[ "$copies" -gt 0 ] || bad "found no bundled copies of any docs/ or root file" \
    "the manifest lists rows, so zero matches means this comparison stopped working."

# A floor. With zero links found, every loop above is skipped and the suite
# passes vacuously — the one state this check cannot distinguish from success.
MIN_POINTERS=6
if [ "$checked" -ge "$MIN_POINTERS" ]; then
    ok "found $checked bundled-reference pointer(s), at or above the floor of $MIN_POINTERS"
else
    bad "found only $checked bundled-reference pointer(s), below the floor of $MIN_POINTERS" \
        "either pointers were removed, or the extraction stopped matching the real link syntax."
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
