#!/usr/bin/env bash
# CONTRACT: `/execute` must tell a session that the repo's commit-time gates can
# be absent, and must make a verification claim say which instrument produced it.
#
# THE DRIFT CLASS. A repo documents pre-commit and pre-push checks, wires them
# into a hook manager, and reasons from then on as though they run. They run only
# where the manager is installed. Git hooks live in `.git/hooks`, which is
# per-worktree and untracked, so a fresh worktree — or a host-provisioned
# workspace, which seeds tracked files and dependencies and not hooks — inherits
# none of them. Nothing reports the absence, because the thing that would report
# it is itself one of the absent hooks. Every commit succeeds and every
# documented guarantee silently did not happen.
#
# THE INCIDENT (PR #278, 2026-08-24). Eight commits in a Conductor workspace with
# `.git/worktrees/<name>/hooks/` empty and `lefthook` not on `PATH`. Among the
# checks that never ran was `scripts/check-shellcheck-version.sh`, which exists
# precisely to stop someone reporting a local shellcheck pass as a merge signal —
# and the session then reported exactly that into the PR body's review notes.
# Local shellcheck was 0.11.0; `.shellcheck-version` pins CI to 0.9.0, which
# flagged SC2015 and would have failed the required check.
#
# WHY THE FIX IS A TELL AND NOT A GATE. Nothing local can detect that local
# checks are absent, because the detector would be another local check with the
# same absence. So the two workable places are the agent's own procedure and the
# artifact the reviewer reads. `/execute` Step 0 gets the checklist item; Step 6
# gets the rule that a claim about a version-pinned tool names its version and
# says whether local gates were active. A branch whose hooks never ran is not
# disqualified — it is differently evidenced, and the reviewer has to be able to
# tell which they are reading.
#
# WHAT IT PINS, extracted from the real file rather than restated:
#   1. The Step 0 worktree checklist has an item about local git hooks, and that
#      item says hooks are per-worktree/untracked — the fact that makes the
#      absence non-obvious.
#   2. The host-provisioned stand-down does not wave the checklist away wholesale;
#      it carves the hooks item out by name.
#   3. Step 6's review-notes section requires a pinned tool's version and a
#      statement about whether local gates ran.
#
# It deliberately pins no wording beyond the load-bearing claims. The self-tests
# at the bottom mutate both the subject and this suite's own readers, because a
# detector that has stopped detecting reports the same green as a clean tree.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
execute_md="$repo_root/execute/SKILL.md"

pass=0
fail=0
section() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n       %s\n' "$1" "$2"; fail=$((fail + 1)); }
fatal() { printf '\nFATAL: %s\n' "$1" >&2; exit 2; }

# checklist_items <skill.md> — the bullet lines of the Step 0 worktree setup
# checklist, delimited by its bolded heading and the next non-list paragraph.
# Range-based rather than a whole-file grep: the point is that the item is IN the
# checklist a session walks, not merely somewhere in a 900-line file.
checklist_items() {
    awk '
        /^\*\*Worktree setup checklist/ { inc = 1; next }
        inc && /^- \[ \]/               { print; next }
        inc && /^[^-[:space:]]/         { inc = 0 }
    ' "$1"
}

# section_body <skill.md> <anchor-regex> — the paragraph beginning at the first
# line matching the anchor, through the next blank line.
section_body() {
    awk -v anchor="$2" '
        $0 ~ anchor { found = 1 }
        found && /^[[:space:]]*$/ { exit }
        found { print }
    ' "$1"
}

[ -f "$execute_md" ] || fatal "$execute_md is missing; /execute moved and this suite has not followed it."

# -----------------------------------------------------------------------------
section "the Step 0 checklist warns that commit-time gates can be absent"

MIN_CHECKLIST_ITEMS=4
item_count="$(checklist_items "$execute_md" | grep -c . || true)"
if [ "$item_count" -lt "$MIN_CHECKLIST_ITEMS" ]; then
    fatal "read $item_count checklist item(s), expected at least $MIN_CHECKLIST_ITEMS.
       The reader is broken, not the skill — an unread checklist passes the
       checks below vacuously, which is the failure mode this suite is about."
fi
ok "read $item_count worktree-checklist item(s) (floor: $MIN_CHECKLIST_ITEMS)"

hooks_item="$(checklist_items "$execute_md" | grep -i 'hook' || true)"
if [ -z "$hooks_item" ]; then
    bad "the worktree setup checklist has no item about local git hooks" \
        "a fresh worktree inherits none, and nothing reports their absence because the reporter would be one of the absent hooks. Without this item a session reasons from lefthook.yml as though it ran."
else
    ok "the checklist has an item about local git hooks"
    if grep -qi 'untracked\|per-worktree' <<<"$hooks_item"; then
        ok "that item says why the absence is invisible (hooks are per-worktree and untracked)"
    else
        bad "the hooks item does not say hooks are per-worktree/untracked" \
            "that fact is the whole reason the absence is non-obvious — an item that just says \"install hooks\" reads as optional setup rather than as a silent gap in every documented guarantee."
    fi
fi

# -----------------------------------------------------------------------------
section "the host-provisioned stand-down does not wave the hooks item away"

standdown="$(section_body "$execute_md" 'When standing down:')"
[ -n "$standdown" ] || fatal "could not read the stand-down paragraph; its anchor moved."

if grep -qi 'hook' <<<"$standdown"; then
    ok "the stand-down names the hooks item as an exception to \"informational only\""
else
    bad "the stand-down dismisses the whole worktree checklist without carving out hooks" \
        "hosts provision tracked files and dependencies, not git hooks — so the host-provisioned path is exactly where the absence is most likely, and this is the paragraph that tells the session to skip looking."
fi

# -----------------------------------------------------------------------------
section "a verification claim names the instrument that produced it"

notes="$(section_body "$execute_md" 'Name the version whenever the repo pins')"
if [ -z "$notes" ]; then
    bad "Step 6's review-notes rules do not require a pinned tool's version" \
        "\"lint clean\" is a claim about whichever binary was on PATH. Linters disagree across releases in both directions, so without a version the reviewer cannot tell whether the row describes the merge gate."
else
    ok "Step 6 requires the version beside a pinned tool's claim"
    if grep -qi 'hook' <<<"$notes"; then
        ok "…and requires saying whether the repo's own local gates ran"
    else
        bad "the review-notes rule names the version but not whether local gates ran" \
            "both halves matter: the version says which instrument, the hooks line says whether the repo's own instruments ran at all. A branch whose hooks never ran is differently evidenced, not disqualified."
    fi
fi

# -----------------------------------------------------------------------------
section "the detector still detects (self-test)"

# VALIDATE THE INSTRUMENT, NOT ONLY THE SUBJECT
# (docs/solutions/testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md).
# Every check above is an absent-result assertion — it concludes from something
# NOT being found. That is the shape that reports green when the reader breaks,
# so each reader is exercised against a fixture in both directions.
fixtures="$(mktemp -d)"
trap 'rm -rf "$fixtures"' EXIT

cat > "$fixtures/good.md" <<'FIXTURE'
**Worktree setup checklist (DO-CONFIRM — perform each step, then verify before proceeding).**

- [ ] Git-ignored config copied
- [ ] Dependencies installed
- [ ] Session is inside the worktree
- [ ] Local git hooks are installed — `.git/hooks` is per-worktree and untracked

Some following paragraph that is not a list item.
FIXTURE

cat > "$fixtures/no-hooks.md" <<'FIXTURE'
**Worktree setup checklist (DO-CONFIRM — perform each step, then verify before proceeding).**

- [ ] Git-ignored config copied
- [ ] Dependencies installed
- [ ] Session is inside the worktree
- [ ] TDD marker absent

Some following paragraph.
FIXTURE

if [ "$(checklist_items "$fixtures/good.md" | grep -c . || true)" -eq 4 ]; then
    ok "checklist_items reads exactly the list items and stops at the next paragraph"
else
    bad "checklist_items misread a clean fixture" \
        "got $(checklist_items "$fixtures/good.md" | grep -c . || true) item(s), want 4 — a reader that runs past the checklist would find a 'hook' anywhere in the file and pass"
fi

if [ -n "$(checklist_items "$fixtures/good.md" | grep -i hook || true)" ] \
    && [ -z "$(checklist_items "$fixtures/no-hooks.md" | grep -i hook || true)" ]; then
    ok "the hooks-item check distinguishes a checklist that has one from a checklist that does not"
else
    bad "the hooks-item check cannot tell the two fixtures apart" \
        "it reports the same answer for a compliant and a non-compliant checklist, so it is measuring nothing"
fi

# THE RANGE BOUND. A 'hook' mention *outside* the checklist must not satisfy it —
# otherwise the prose two paragraphs down launders the item.
cat > "$fixtures/hook-outside.md" <<'FIXTURE'
**Worktree setup checklist (DO-CONFIRM — perform each step, then verify before proceeding).**

- [ ] Git-ignored config copied
- [ ] Dependencies installed
- [ ] Session is inside the worktree
- [ ] TDD marker absent

Elsewhere this skill talks about lefthook hooks at length.
FIXTURE
if [ -z "$(checklist_items "$fixtures/hook-outside.md" | grep -i hook || true)" ]; then
    ok "a 'hook' mention outside the checklist does not satisfy the checklist item"
else
    bad "checklist_items ran past the checklist" \
        "any mention of hooks anywhere below would then pass, and the item a session actually walks could be missing"
fi

cat > "$fixtures/para.md" <<'FIXTURE'
Preamble.

When standing down: skip worktree creation. The hooks item still applies.
Second line of the same paragraph.

A later paragraph that must not be included.
FIXTURE
body="$(section_body "$fixtures/para.md" 'When standing down:')"
if grep -q 'Second line' <<<"$body" && ! grep -q 'later paragraph' <<<"$body"; then
    ok "section_body returns the whole anchored paragraph and stops at the blank line"
else
    bad "section_body misread a clean fixture" \
        "got: $body — a reader that runs to end-of-file would let any later paragraph satisfy the anchored check"
fi

if [ -z "$(section_body "$fixtures/para.md" 'A String That Is Not Present')" ]; then
    ok "section_body returns empty for an anchor that is absent, rather than the whole file"
else
    bad "section_body returned content for a missing anchor" \
        "the live checks conclude from emptiness, so a reader that returns the file on a miss makes every one of them pass"
fi

# -----------------------------------------------------------------------------

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
