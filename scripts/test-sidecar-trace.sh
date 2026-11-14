#!/usr/bin/env bash
# test-sidecar-trace.sh — runs the real init-pipeline/scripts/sidecar.sh
# `trace` verb against scratch repos and against this repo's own lessons
# (chrislacey89/skills#727).
#
# THE DRIFT CLASS. trace derives edges from text other skills write: the
# "## Research Reference" section /write-a-prd puts in a PRD body, the
# "- **Research:**" slot /prd-to-issues gives a slice, the
# "## Review Notes" and "## Review Disposition Ledger" comments, a lesson's
# "## Related" section and "Sibling docs:" list. A reader built on another
# writer's text goes silently empty when that text changes: no error, no
# missing edge reported, just fewer neighbors. So the research section below
# extracts its template lines from write-a-prd/SKILL.md itself and fails loudly
# when they are gone, and the corpus section traces every lesson in
# docs/solutions/ and requires the total citation count to be above zero, so
# an extraction that returns nothing cannot pass.
#
# THE READ-ONLY CONTRACT. trace never writes a file and never commits: after
# every call the fixture project's tree is clean and the sidecar's HEAD has
# not moved. A neighbor that is missing is reported, never an error; exit 1 is
# kept for a subject that is missing.
#
# THE SHARED LOOKUP. trace resolves a lesson's citations with the helper that
# `require` uses, so the last section re-asserts require's hit and miss output.
#
# Fixtures are built after unsetting the inherited git environment, with a
# private global config, so a hook's GIT_DIR or the runner's identity cannot
# leak in (scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md). Every
# fixture root commit carries its own path, so two fixtures made in the same
# second are not one project (scripts/test-fixture-root-collision.sh).

# shellcheck disable=SC2016  # backticks in fixture markdown are literal text
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
SC="$repo_root/init-pipeline/scripts/sidecar.sh"
PRD_SKILL="$repo_root/write-a-prd/SKILL.md"
SLICE_SKILL="$repo_root/prd-to-issues/SKILL.md"
[ -f "$SC" ] || { printf 'FATAL %s is missing\n' "$SC"; exit 1; }
[ -f "$PRD_SKILL" ] || { printf 'FATAL %s is missing\n' "$PRD_SKILL"; exit 1; }
[ -f "$SLICE_SKILL" ] || { printf 'FATAL %s is missing\n' "$SLICE_SKILL"; exit 1; }

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Trace Tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
export SKILL_KIT_SIDECAR_ROOT="$tmp/sidecars"
export SKILL_KIT_RESEARCH_ARCHIVE="$tmp/archive"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
fatal() { printf 'FATAL %s\n' "$1"; printf '\n---\n%d passed, %d failed\n' "$pass" "$((fail + 1))"; exit 1; }

# runo <dir> <args...> — run sidecar.sh from <dir>; stdout in $out, exit in $rc,
# stderr in $err. "$BASH" so a /bin/bash run of this suite runs the script
# under the same bash.
runo() {
    local d="$1"; shift
    out="$(cd "$d" && "$BASH" "$SC" "$@" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}
# jqo <filter> — apply a jq filter to the last $out.
jqo() { printf '%s' "$out" | jq -c "$1"; }

n=0
# mkproj — a scratch project with its own root commit, in $P.
mkproj() {
    n=$((n + 1))
    P="$tmp/proj$n"
    git init -q "$P"
    git -C "$P" commit -q --allow-empty -m "root $P"
}

# -----------------------------------------------------------------------------
section "usage and exits"

mkproj
nosc="$P"
runo "$nosc" trace
check "no argument exits 2" 2 "$rc"
runo "$nosc" trace W-1 --bogus
check "an unknown flag exits 2" 2 "$rc"
runo "$nosc" trace W-1
check "a work id with no sidecar exits 1" 1 "$rc"
runo "$nosc" trace no-such-file.md
check "a file that does not exist exits 1" 1 "$rc"

mkproj
runo "$P" init --name trace --mode guest --write sidecar --in-tree-path none --no-migrate-archive
S="$out"
TP="$P"
[ -d "$S" ] || fatal "init did not create a sidecar: $err"
runo "$P" trace W-99
check "a work id the store does not hold exits 1" 1 "$rc"

# -----------------------------------------------------------------------------
section "work edges, both directions"

printf '## Problem\n\nA thing.\n' > "$tmp/body.md"
runo "$P" work create --kind prd --body-file "$tmp/body.md"; prd="$out"
runo "$P" work create --kind slice --parent "$prd" --body-file "$tmp/body.md"; s1="$out"
runo "$P" work create --kind slice --parent "$prd" --body-file "$tmp/body.md"; s2="$out"
runo "$P" work create --kind slice --parent "$prd" --blocked-by "$s2" --body-file "$tmp/body.md"; s3="$out"
runo "$P" work set "$prd" decomposed_into "$s1,$s2,$s3"
runo "$P" work close "$s1" --superseded-by "$s3"

runo "$P" trace "$prd" --json
check "trace --json exits 0" 0 "$rc"
check "kind and id" '["work","'"$prd"'"]' "$(jqo '[.kind, .id]')"
check "item carries the frontmatter" '"prd"' "$(jqo '.item.kind')"
check "item carries no body or comments" '[false,false]' "$(jqo '.item | [has("body"), has("comments")]')"
check "children, in id order, with kind, state, pr and lessons" \
    '[{"id":"'"$s1"'","kind":"slice","state":"closed","pr":null,"lessons":[]},{"id":"'"$s2"'","kind":"slice","state":"open","pr":null,"lessons":[]},{"id":"'"$s3"'","kind":"slice","state":"open","pr":null,"lessons":[]}]' \
    "$(jqo '.children')"
check "decomposed_into, with states" \
    '[{"id":"'"$s1"'","state":"closed"},{"id":"'"$s2"'","state":"open"},{"id":"'"$s3"'","state":"open"}]' \
    "$(jqo '.decomposed_into')"
check "a prd has no parent" null "$(jqo '.parent')"

runo "$P" trace "$s3" --json
check "parent, with state" '{"id":"'"$prd"'","state":"open"}' "$(jqo '.parent')"
check "blocked_by, with state" '[{"id":"'"$s2"'","state":"open"}]' "$(jqo '.blocked_by')"
check "supersedes" '[{"id":"'"$s1"'","state":"closed"}]' "$(jqo '.supersedes')"
runo "$P" trace "$s2" --json
check "blocks, read from the other item's blocked_by" '[{"id":"'"$s3"'","state":"open"}]' "$(jqo '.blocks')"
runo "$P" trace "$s1" --json
check "superseded_by, with state" '{"id":"'"$s3"'","state":"open"}' "$(jqo '.superseded_by')"

# A hand-written blocker id that names no file is a missing neighbor, not an error.
sed -i.bak "s/^blocked_by: .*/blocked_by: [$s2, W-77]/" "$S/work/$s3.md" && rm -f "$S/work/$s3.md.bak"
runo "$P" trace "$s3" --json
check "a blocker with no file exits 0" 0 "$rc"
check "a blocker with no file is state missing" '{"id":"W-77","state":"missing"}' "$(jqo '.blocked_by[1]')"
runo "$P" trace "$s3"
case "$out" in *"  blocked by  W-77 (missing)"*) ok "text mode names the missing blocker" ;; *) bad "text mode names the missing blocker" "$out" ;; esac
git -C "$S" checkout -q -- "work/$s3.md"

# -----------------------------------------------------------------------------
section "review_responses"

runo "$P" work set "$s2" pr "https://github.com/acme/trace/pull/56"
runo "$P" trace "$s2" --json
check "no record for the pr yet: null" null "$(jqo '.review_responses')"
mkdir -p "$S/review-responses"
printf 'record\n' > "$S/review-responses/pr-56.md"
runo "$P" trace "$s2" --json
check "a GitHub pr URL finds review-responses/pr-56.md" "\"$S/review-responses/pr-56.md\"" "$(jqo '.review_responses')"
check "children report a set pr" '"https://github.com/acme/trace/pull/56"' "$(runo "$P" trace "$prd" --json; jqo ".children[] | select(.id == \"$s2\") | .pr")"
runo "$P" work set "$s3" pr "https://bitbucket.org/acme/trace/pull-requests/7/"
printf 'record\n' > "$S/review-responses/pr-7.md"
runo "$P" trace "$s3" --json
check "a Bitbucket pr URL (trailing /) finds pr-7.md" "\"$S/review-responses/pr-7.md\"" "$(jqo '.review_responses')"

# -----------------------------------------------------------------------------
section "review notes and disposition ledger"

printf '## Review Notes\n\nfirst\n' > "$tmp/n1.md"
printf '## Review Disposition Ledger\n\n| # | decision |\n' > "$tmp/l1.md"
printf '## Review Notes\n\nsecond\n' > "$tmp/n2.md"
printf 'a plain comment\n' > "$tmp/plain.md"
runo "$P" trace "$s2" --json
check "no comments: review_notes null" null "$(jqo '.review_notes')"
runo "$P" work comment "$s2" --body-file "$tmp/n1.md"
sleep 1
runo "$P" work comment "$s2" --body-file "$tmp/l1.md"
sleep 1
runo "$P" work comment "$s2" --body-file "$tmp/n2.md"
runo "$P" work comment "$s2" --body-file "$tmp/plain.md"
runo "$P" work view "$s2" --json
ats="$(jqo '[.comments[].at]')"
runo "$P" trace "$s2" --json
check "review_notes is the newest Review Notes comment" "$(printf '%s' "$ats" | jq -c '.[2]')" "$(jqo '.review_notes')"
check "disposition_ledger is the ledger comment" "$(printf '%s' "$ats" | jq -c '.[1]')" "$(jqo '.disposition_ledger')"

# -----------------------------------------------------------------------------
section "research, pinned to /write-a-prd's template"

archive_line="$(grep -F 'documented at `<absolute path to the research entry>`' "$PRD_SKILL" | head -n 1)"
[ -n "$archive_line" ] || fatal "write-a-prd/SKILL.md has no archive-mode line 'documented at \`<absolute path to the research entry>\`': trace's research reader has lost its writer"
spike_line="$(grep -F 'Refs #<spike-issue-number>' "$PRD_SKILL" | head -n 1)"
[ -n "$spike_line" ] || fatal "write-a-prd/SKILL.md has no spike-issue line 'Refs #<spike-issue-number>': trace's spike reader has lost its writer"
grep -qx '## Research Reference' "$PRD_SKILL" || fatal "write-a-prd/SKILL.md has no '## Research Reference' heading"

R="$S/research"
mkdir -p "$R"
for f in tracer-2026-01-01 tracer-2026-03-01 tracer-2026-02-01 tracer-2025-12-01 tracer-x-2026-04-01; do printf 'r\n' > "$R/$f.md"; done
entry="$R/tracer-2026-02-01.md"
{
    printf '## Problem\n\nA thing.\n\n## Research Reference\n\n'
    printf '%s\n' "${archive_line/<absolute path to the research entry>/$entry}"
    printf '%s\n' "${spike_line/<spike-issue-number>/314}"
    printf '\nAlso `%s`.\n\n## Lessons from Past Solutions\n\n`%s`\n' "$tmp/gone-2026-01-01.md" "$R/tracer-2026-01-01.md"
} > "$tmp/rprd.md"
runo "$P" work create --kind prd --body-file "$tmp/rprd.md"; rprd="$out"
runo "$P" work create --kind slice --parent "$rprd" --body-file "$tmp/body.md"; rs="$out"

runo "$P" trace "$rprd" --json
check "research exits 0 with an unresolved path" 0 "$rc"
check "the template's path resolves" "\"$entry\"" "$(jqo '.research[0].resolved')"
check "cited is the path as written" "\"$entry\"" "$(jqo '.research[0].cited')"
check "a prd's own research has no via" null "$(jqo '.research[0].via')"
check "newer lists the later same-slug entry only" "[\"$R/tracer-2026-03-01.md\"]" "$(jqo '.research[0].newer')"
check "a path that does not exist resolves to null" null "$(jqo '.research[1].resolved')"
check "the section ends at the next ## heading" 2 "$(jqo '.research | length')"
check "spike_issues from the template's Refs line" '[314]' "$(jqo '.spike_issues')"
runo "$P" trace "$rprd"
case "$out" in *"  research  MISSING: $tmp/gone-2026-01-01.md"*) ok "text mode prints MISSING: for an unresolved path" ;; *) bad "text mode prints MISSING: for an unresolved path" "$out" ;; esac
runo "$P" trace "$rs" --json
check "a slice with no section reports the parent's research" "\"$entry\"" "$(jqo '.research[0].resolved')"
check "and names the parent in via" "\"$rprd\"" "$(jqo '.research[0].via')"
runo "$P" trace "$rs"
case "$out" in *"  research  $entry (via $rprd)"*) ok "text mode names the parent the research came through" ;; *) bad "text mode names the parent the research came through" "$out" ;; esac
runo "$P" trace "$rs" --json
check "and the parent's spike issues" '[314]' "$(jqo '.spike_issues')"
runo "$P" trace "$s2" --json
check "no section anywhere: research is empty" '[]' "$(jqo '.research')"
check "no section anywhere: spike_issues is empty" '[]' "$(jqo '.spike_issues')"

# A slice's own Context slot, pinned to /prd-to-issues' issue template: the
# slot's label is read from the template line, never restated here.
slot_line="$(grep -E '^- \*\*Research:\*\* ' "$SLICE_SKILL" | head -n 1)"
[ -n "$slot_line" ] || fatal "prd-to-issues/SKILL.md has no '- **Research:**' template line: trace's slice reader has lost its writer"
slot_label="${slot_line%%\`*}"
{
    printf '## What to Build\n\nA thing.\n\n### Context\n\n'
    printf '%s`%s`\n' "$slot_label" "$R/tracer-2026-01-01.md"
} > "$tmp/slot.md"
runo "$P" work create --kind slice --parent "$rprd" --body-file "$tmp/slot.md"; slot="$out"
runo "$P" trace "$slot" --json
check "a slice's own Research slot is read" "\"$R/tracer-2026-01-01.md\"" "$(jqo '.research[0].resolved')"
check "and wins over the parent's section: no via, one entry" '[null,1]' "$(jqo '[.research[0].via, (.research | length)]')"
printf '## What to Build\n\nA thing.\n\n### Context\n\n%s\n' "${slot_line/<spike-issue-number>/271}" > "$tmp/slot2.md"
runo "$P" work create --kind slice --parent "$rprd" --body-file "$tmp/slot2.md"; slot2="$out"
runo "$P" trace "$slot2" --json
check "the template's own Refs form yields the spike issue" '[271]' "$(jqo '.spike_issues')"

# -----------------------------------------------------------------------------
section "lesson edges"

L="$S/solutions"
mkdir -p "$L/patterns" "$L/testing"
printf '# Project rules\n' > "$P/CLAUDE.md"
cat > "$L/patterns/alpha-2026-01-01.md" <<'EOF'
# Alpha

- **Sibling docs:**
  - `bravo-2026-01-02.md` — a bare name in a sibling category

## Related

- `../testing/charlie-2026-01-03.md` — relative to this folder
- See [delta](../testing/delta-2026-01-04.md#why) for the anchor case
- `nope-2026-01-09.md` — cites nothing that exists
- `CLAUDE.md` — not a lesson
- [web](https://example.com/x.md)

## Shelf Life

`../testing/echo-2026-01-05.md` is outside Related and not a citation.
EOF
printf '# Bravo\n\n## Related\n\n- `../patterns/alpha-2026-01-01.md`\n' > "$L/testing/bravo-2026-01-02.md"
printf '# Charlie\n\n## Related\n\n- [alpha](../patterns/alpha-2026-01-01.md)\n' > "$L/testing/charlie-2026-01-03.md"
printf '# Delta\n\nProse names alpha-2026-01-01.md outside Related.\n' > "$L/testing/delta-2026-01-04.md"
printf '# Echo\n' > "$L/testing/echo-2026-01-05.md"

mkdir -p "$P/docs/solutions/devops" "$P/sub"
printf '# Foxtrot\n\n## Related\n\n- `bravo-2026-01-02.md` — lives in the sidecar, a different store\n' > "$P/docs/solutions/devops/foxtrot-2026-01-06.md"
printf '# Golf\n\n## Related\n\n- `docs/solutions/devops/foxtrot-2026-01-06.md`\n' > "$P/docs/solutions/devops/golf-2026-01-07.md"
git -C "$P" add -A && git -C "$P" commit -q -m "fixture lessons"

runo "$P" trace "$L/patterns/alpha-2026-01-01.md" --json
check "lesson trace exits 0 with a missing citation" 0 "$rc"
check "kind and path" "[\"lesson\",\"$L/patterns/alpha-2026-01-01.md\"]" "$(jqo '[.kind, .path]')"
check "cites: sibling-docs bare name, ../ path, markdown link, in file order" \
    "[\"$L/testing/bravo-2026-01-02.md\",\"$L/testing/charlie-2026-01-03.md\",\"$L/testing/delta-2026-01-04.md\"]" \
    "$(jqo '[.cites[].resolved]')"
check "cites keeps the path as written" '"../testing/delta-2026-01-04.md#why"' "$(jqo '.cites[2].cited')"
check "other: a resolved file outside every solutions dir" "[\"$P/CLAUDE.md\"]" "$(jqo '[.other[].resolved]')"
check "missing: the citation that resolves nowhere" '["nope-2026-01-09.md"]' "$(jqo '.missing')"
check "cited_by: the lessons whose citations resolve here, not a prose mention" \
    "[\"$L/testing/bravo-2026-01-02.md\",\"$L/testing/charlie-2026-01-03.md\"]" "$(jqo '.cited_by')"
runo "$P" trace "$L/patterns/alpha-2026-01-01.md"
check "lesson text mode first line" "lesson  $L/patterns/alpha-2026-01-01.md" "$(printf '%s\n' "$out" | head -n 1)"
case "$out" in *"  MISSING: nope-2026-01-09.md"*) ok "lesson text mode prints MISSING:" ;; *) bad "lesson text mode prints MISSING:" "$out" ;; esac

runo "$P" trace docs/solutions/devops/foxtrot-2026-01-06.md --json
check "an in-tree bare name does not reach the sidecar store" '["bravo-2026-01-02.md"]' "$(jqo '.missing')"
runo "$P/sub" trace ../docs/solutions/devops/golf-2026-01-07.md --json
check "from a subdirectory, a docs/solutions/ path resolves via the top level, as a lesson" \
    "[\"$P/docs/solutions/devops/foxtrot-2026-01-06.md\"]" "$(jqo '[.cites[].resolved]')"
check "from a subdirectory, nothing is missing" '[]' "$(jqo '.missing')"
runo "$P/sub" trace ../docs/solutions/devops/foxtrot-2026-01-06.md --json
check "from a subdirectory, cited_by still finds the in-tree lesson" \
    "[\"$P/docs/solutions/devops/golf-2026-01-07.md\"]" "$(jqo '.cited_by')"

# <category>/<name>.md, written from the store root, is a form lessons use and
# require's lookup does not cover.
printf '# Hotel\n\n## Related\n\n- `testing/echo-2026-01-05.md` — from the store root\n' > "$L/patterns/hotel-2026-01-08.md"
runo "$P" trace "$L/patterns/hotel-2026-01-08.md" --json
check "a <category>/<name>.md citation resolves from the lesson's store root" \
    "[\"$L/testing/echo-2026-01-05.md\"]" "$(jqo '[.cites[].resolved]')"
check "and is not reported missing" '[]' "$(jqo '.missing')"

# A lesson trace needs no sidecar.
mkproj
mkdir -p "$P/docs/solutions/a"
printf '# H\n\n## Related\n\n- `i-2026-01-01.md`\n' > "$P/docs/solutions/a/h-2026-01-01.md"
printf '# I\n' > "$P/docs/solutions/a/i-2026-01-01.md"
runo "$P" trace docs/solutions/a/h-2026-01-01.md --json
check "lesson trace with no sidecar exits 0" 0 "$rc"
check "lesson trace with no sidecar resolves in docs/solutions" "[\"$P/docs/solutions/a/i-2026-01-01.md\"]" "$(jqo '[.cites[].resolved]')"
case "$err" in *"SIDECAR MISS"*) bad "no SIDECAR MISS on a lesson trace" "$err" ;; *) ok "no SIDECAR MISS on a lesson trace" ;; esac

# -----------------------------------------------------------------------------
section "the real corpus: this repo's docs/solutions"

mkdir -p "$tmp/empty-sidecars"
total=0 runs=0 nonzero="" dangling=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    runs=$((runs + 1))
    o="$(cd "$repo_root" && SKILL_KIT_SIDECAR_ROOT="$tmp/empty-sidecars" "$BASH" "$SC" trace "$f" --json 2>/dev/null)" \
        || { nonzero="$nonzero $f"; continue; }
    total=$((total + $(printf '%s' "$o" | jq '.cites | length')))
    m="$(printf '%s' "$o" | jq -c '.missing')"
    [ "$m" = "[]" ] || dangling="$dangling"$'\n'"       $f: $m"
done <<<"$(cd "$repo_root" && find docs/solutions -type f -name '*.md' | LC_ALL=C sort)"
[ "$runs" -gt 0 ] || fatal "found no docs/solutions/**/*.md under $repo_root"
check "every lesson traces with exit 0 ($runs files)" "" "$nonzero"
if [ "$total" -gt 0 ]; then ok "the corpus yields citations ($total cites)"; else bad "the corpus yields citations" "0 cites across $runs files: the extraction found nothing"; fi
if [ -z "$dangling" ]; then ok "no lesson has a citation that resolves nowhere"; else bad "no lesson has a citation that resolves nowhere" "${dangling#?}"; fi

# -----------------------------------------------------------------------------
section "read-only"

P="$TP"
head_before="$(git -C "$S" rev-parse HEAD)"
for args in "$prd" "$prd --json" "$s2" "$s3 --json" "$rprd" "$rs --json" "$L/patterns/alpha-2026-01-01.md" "$L/testing/bravo-2026-01-02.md --json"; do
    # shellcheck disable=SC2086  # word-splitting the argument pair is the point
    (IFS=' '; cd "$P" && "$BASH" "$SC" trace $args >/dev/null 2>&1)
done
check "trace leaves the fixture project clean" "" "$(git -C "$P" status --porcelain)"
check "trace makes no sidecar commit" "$head_before" "$(git -C "$S" rev-parse HEAD)"
check "trace leaves the work store unmodified" "" "$(git -C "$S" status --porcelain -- work)"
runo "$P" trace "$s2"
check "text mode first line is <id>  <kind>  <state>" "$s2  slice  open" "$(printf '%s\n' "$out" | head -n 1)"

# -----------------------------------------------------------------------------
section "branch, last reviewed commit, and fix runs"

P="$TP"
sha1="0123456789abcdef0123456789abcdef01234567"
sha2="fedcba9876543210fedcba9876543210fedcba98"
runo "$P" work create --kind slice --parent "$prd" --body-file "$tmp/body.md"; fa="$out"
runo "$P" work create --kind slice --parent "$prd" --body-file "$tmp/body.md"; fb="$out"

# Before any fix run exists there is no fix-runs/ directory at all.
runo "$P" work set "$fa" branch feat-a
runo "$P" trace "$fa" --json
check "no fix-runs directory: trace exits 0" 0 "$rc"
check "no fix-runs directory: both lists are empty" '[[],[]]' "$(jqo '[.fix_runs, .branch_fix_runs]')"

runo "$P" work set "$fa" pr "https://github.com/acme/guestwork/pull/12"
runo "$P" work set "$fa" reviewed_sha "$sha1"
runo "$P" trace "$fa"
check "text: branch and last reviewed follow the pr line" \
    "  pr  https://github.com/acme/guestwork/pull/12
  branch  feat-a
  last reviewed  $sha1" "$(printf '%s\n' "$out" | grep -A2 '^  pr  ')"
runo "$P" trace "$fb"
check "text: no branch or last reviewed line when the item has neither" 0 "$(printf '%s\n' "$out" | grep -cE '^  (branch|last reviewed)  ')"
runo "$P" trace "$fa" --json
check "json: item carries branch and reviewed_sha" "[\"feat-a\",\"$sha1\"]" "$(jqo '[.item.branch, .item.reviewed_sha]')"

# Attributed fix runs. The later run is recorded first, in the other branch's
# file, so the sort is doing the ordering and the branch is the record's own.
r1="20260101T000000Z"; r2="20260102T000000Z"; r3="20260103T000000Z"; r4="20260104T000000Z"; r5="20260105T000000Z"
runo "$P" fixrun record feat-b "$r3" "$sha2" --work "$fa" --thread "https://example.com/t/9"
runo "$P" fixrun record feat-a "$r1" "$sha1" --work "$fa"
runo "$P" trace "$fa" --json
check "fix_runs: attributed records from any branch file, run ascending, thread null when absent" \
    '[{"run":"'"$r1"'","sha":"'"$sha1"'","branch":"feat-a","thread":null},{"run":"'"$r3"'","sha":"'"$sha2"'","branch":"feat-b","thread":"https://example.com/t/9"}]' \
    "$(jqo '.fix_runs')"
runo "$P" trace "$fa"
check "text: one fix run line each, thread appended when there is one" \
    "  fix run  $r1 $sha1 on feat-a
  fix run  $r3 $sha2 on feat-b thread https://example.com/t/9" "$(printf '%s\n' "$out" | grep '^  fix run  ')"
runo "$P" fixrun record feat-a "$r4" "$sha1" --work "$fb"
runo "$P" trace "$fb" --json
check "fix_runs works for an item with no branch field" '["'"$r4"'"]' "$(jqo '[.fix_runs[].run]')"
check "an item with no branch has no branch-level fix runs" '[]' "$(jqo '.branch_fix_runs')"

# Branch-level fix runs: the branch's own records that name no item. A run
# attributed to another item, or recorded on another branch, is not shown.
runo "$P" fixrun record feat-a "$r2" "$sha2"
runo "$P" fixrun record feat-b "$r5" "$sha2" --thread "https://example.com/t/5"
runo "$P" trace "$fa" --json
check "branch_fix_runs: unattributed records of the item's branch only" \
    '[{"run":"'"$r2"'","sha":"'"$sha2"'","branch":"feat-a","thread":null}]' "$(jqo '.branch_fix_runs')"
check "an unattributed run is never placed in fix_runs" '["'"$r1"'","'"$r3"'"]' "$(jqo '[.fix_runs[].run]')"
runo "$P" trace "$fa"
check "text: a branch-level fix run line" "  branch-level fix run  $r2 $sha2 on feat-a" "$(printf '%s\n' "$out" | grep '^  branch-level fix run  ')"

# A record naming a different item is in neither list, even in this item's
# branch file; lines that cannot be trusted are skipped without a word.
FA="$S/fix-runs/feat-a.jsonl"
{
    printf 'this is not json\n'
    printf '{"branch":"feat-a","run":"%s","sha":"abc1234","work":"%s"}\n' "$r5" "$fa"
    printf '{"branch":"feat-a","run":"yesterday","sha":"%s","work":"%s"}\n' "$sha1" "$fa"
    printf '{"branch":"feat-a","run":"%s","sha":"abc1234"}\n' "$r5"
    printf '{"branch":"feat-a","run":"%s","sha":12345,"work":"%s"}\n' "$r5" "$fa"
    printf '{"branch":"feat-aa","run":"%s","sha":"%s"}\n' "$r5" "$sha1"
} >> "$FA"
runo "$P" trace "$fa" --json
check "untrusted lines and another branch's records are skipped: exit 0" 0 "$rc"
check "untrusted lines are skipped in fix_runs" '["'"$r1"'","'"$r3"'"]' "$(jqo '[.fix_runs[].run]')"
check "untrusted lines and a same-slug-prefix branch are skipped in branch_fix_runs" '["'"$r2"'"]' "$(jqo '[.branch_fix_runs[].run]')"
check "a run naming a different item is in neither list" 0 "$(jqo '[.fix_runs[], .branch_fix_runs[] | select(.run == "'"$r4"'")] | length')"
runo "$P" trace "$fb" --json
check "the other item still holds its own run" '["'"$r4"'"]' "$(jqo '[.fix_runs[].run]')"

# Read-only with fix runs present.
head_before="$(git -C "$S" rev-parse HEAD)"
status_before="$(git -C "$S" status --porcelain)"
(cd "$P" && "$BASH" "$SC" trace "$fa" >/dev/null 2>&1)
(cd "$P" && "$BASH" "$SC" trace "$fa" --json >/dev/null 2>&1)
check "trace with fix runs makes no sidecar commit" "$head_before" "$(git -C "$S" rev-parse HEAD)"
check "trace with fix runs changes no file in the sidecar" "$status_before" "$(git -C "$S" status --porcelain)"
clean_fr="$(git -C "$P" status --porcelain)"
check "trace with fix runs leaves the project clean" "" "$clean_fr"

# -----------------------------------------------------------------------------
section "require is unchanged by the shared lookup"

runo "$P" require ../testing/charlie-2026-01-03.md --from "$L/patterns/alpha-2026-01-01.md"
check "require hit exits 0" 0 "$rc"
check "require hit prints the absolute path" "$L/testing/charlie-2026-01-03.md" "$out"
runo "$P" require nope-2026-01-09.md --from "$L/patterns/alpha-2026-01-01.md"
check "require miss exits 1" 1 "$rc"
check "require miss prints MISSING on stderr" "MISSING: nope-2026-01-09.md (referenced by $L/patterns/alpha-2026-01-01.md)" "$err"
check "require miss prints nothing on stdout" "" "$out"

# -----------------------------------------------------------------------------
section "lessons on work items"

# work lesson writes the edge and trace reads it from both ends. The stored
# path is top-level relative for an in-tree lesson, so it survives a worktree's
# removal: trace resolves it from the current checkout, then from the main one.
mkproj
LP="$P"
runo "$LP" init --name lessons --mode guest --write sidecar --in-tree-path none --no-migrate-archive
LS="$out"
mkdir -p "$LP/docs/solutions/testing" "$LP/sub"
printf '# One\n' > "$LP/docs/solutions/testing/one-2026-02-01.md"
printf '# Two\n' > "$LP/docs/solutions/testing/two-2026-02-02.md"
printf '# Three\n' > "$LP/docs/solutions/testing/three-2026-02-03.md"
git -C "$LP" add -A && git -C "$LP" commit -q -m "fixture lessons"
runo "$LP" work create --kind prd --body-file "$tmp/body.md"; lprd="$out"
runo "$LP" work create --kind slice --parent "$lprd" --body-file "$tmp/body.md"; la="$out"
runo "$LP" work create --kind slice --parent "$lprd" --body-file "$tmp/body.md"; lb="$out"
runo "$LP" work lesson "$la" docs/solutions/testing/one-2026-02-01.md
runo "$LP" work lesson "$la" docs/solutions/testing/two-2026-02-02.md
runo "$LP" work lesson "$lb" docs/solutions/testing/one-2026-02-01.md
runo "$LP" work close "$lb"

lhead="$(git -C "$LS" rev-parse HEAD)"
runo "$LP" trace "$la" --json
check "trace --json exits 0" 0 "$rc"
check "json lessons: stored path and resolved absolute path" \
    '[{"path":"docs/solutions/testing/one-2026-02-01.md","resolved":"'"$LP"'/docs/solutions/testing/one-2026-02-01.md"},{"path":"docs/solutions/testing/two-2026-02-02.md","resolved":"'"$LP"'/docs/solutions/testing/two-2026-02-02.md"}]' \
    "$(jqo '.lessons')"
runo "$LP" trace "$la"
check "text: one lesson line per lesson, resolved" \
    "  lesson  $LP/docs/solutions/testing/one-2026-02-01.md
  lesson  $LP/docs/solutions/testing/two-2026-02-02.md" "$(printf '%s\n' "$out" | grep '^  lesson  ')"
runo "$LP" trace "$lprd" --json
check "a PRD's children carry each slice's lessons" \
    '[["docs/solutions/testing/one-2026-02-01.md","docs/solutions/testing/two-2026-02-02.md"],["docs/solutions/testing/one-2026-02-01.md"]]' \
    "$(jqo '[.children[] | [.lessons[].path]]')"
check "the PRD itself lists no lessons" '[]' "$(jqo '.lessons')"
runo "$LP" trace "$lprd"
check "a PRD's text lists each child's lessons right after the child line, indented" \
    "  child  $la (open)
    lesson  $LP/docs/solutions/testing/one-2026-02-01.md
    lesson  $LP/docs/solutions/testing/two-2026-02-02.md
  child  $lb (closed)
    lesson  $LP/docs/solutions/testing/one-2026-02-01.md" "$(printf '%s\n' "$out" | grep -E '^  child  |^    lesson  ')"

# A lesson file that is gone is reported, never an error.
rm -f "$LP/docs/solutions/testing/two-2026-02-02.md"
runo "$LP" trace "$la"
check "a deleted lesson: trace still exits 0" 0 "$rc"
check "a deleted lesson is reported MISSING with its stored path" "  lesson  MISSING: docs/solutions/testing/two-2026-02-02.md" "$(printf '%s\n' "$out" | grep 'MISSING')"
runo "$LP" trace "$la" --json
check "a deleted lesson has resolved null" 'null' "$(jqo '.lessons[1].resolved')"
runo "$LP" trace "$lprd"
check "a deleted lesson is MISSING under its child too" "    lesson  MISSING: docs/solutions/testing/two-2026-02-02.md" "$(printf '%s\n' "$out" | grep 'MISSING')"
git -C "$LP" checkout -q -- docs/solutions/testing/two-2026-02-02.md

# trace on the lesson: the items that name it, by id number.
runo "$LP" trace docs/solutions/testing/one-2026-02-01.md --json
check "taught_by: both items, with kind and state, in id order" \
    '[{"id":"'"$la"'","kind":"slice","state":"open"},{"id":"'"$lb"'","kind":"slice","state":"closed"}]' "$(jqo '.taught_by')"
runo "$LP" trace docs/solutions/testing/one-2026-02-01.md
check "text: a taught by line per item, after the cited-by lines" \
    "  taught by  $la (open)
  taught by  $lb (closed)" "$(printf '%s\n' "$out" | grep '^  taught by  ')"
runo "$LP/sub" trace ../docs/solutions/testing/two-2026-02-02.md --json
check "from a subdirectory, taught_by still matches" '["'"$la"'"]' "$(jqo '[.taught_by[].id]')"
runo "$LP" trace docs/solutions/testing/three-2026-02-03.md --json
check "a lesson no item names has taught_by []" '[]' "$(jqo '.taught_by')"

# Read-only: trace commits nothing and leaves both trees clean.
check "trace makes no sidecar commit" "$lhead" "$(git -C "$LS" rev-parse HEAD)"
check "trace leaves the sidecar clean" "" "$(git -C "$LS" status --porcelain)"
check "trace leaves the project clean" "" "$(git -C "$LP" status --porcelain)"

# A lesson committed on a worktree's branch is stored relative; trace finds it
# from the worktree, and from the main checkout once the branch is merged and
# the worktree removed.
git -C "$LP" worktree add -q -b wt-lesson "$tmp/lwt" >/dev/null 2>&1
printf '# Wt\n' > "$tmp/lwt/docs/solutions/testing/wt-2026-02-04.md"
git -C "$tmp/lwt" add -A && git -C "$tmp/lwt" commit -q -m "wt lesson"
runo "$tmp/lwt" work lesson "$lb" docs/solutions/testing/wt-2026-02-04.md
check "work lesson from a worktree exits 0" 0 "$rc"
runo "$tmp/lwt" trace "$lb" --json
check "from the worktree the lesson resolves to the worktree copy" '"'"$tmp"'/lwt/docs/solutions/testing/wt-2026-02-04.md"' "$(jqo '.lessons[1].resolved')"
runo "$LP" trace "$lb" --json
check "from main before the merge the lesson is null" 'null' "$(jqo '.lessons[1].resolved')"
runo "$tmp/lwt" trace docs/solutions/testing/wt-2026-02-04.md --json
check "trace of the worktree's lesson file finds the item by its relative path" '["'"$lb"'"]' "$(jqo '[.taught_by[].id]')"
# A second worktree, cut before the merge, never holds the lesson file: only the
# main checkout fallback can find it from there.
git -C "$LP" worktree add -q -b wt-other "$tmp/lwt2" >/dev/null 2>&1
git -C "$LP" merge -q wt-lesson >/dev/null 2>&1
git -C "$LP" worktree remove --force "$tmp/lwt"
runo "$LP" trace "$lb" --json
check "after the merge and the removal the lesson resolves from the main checkout" '"'"$LP"'/docs/solutions/testing/wt-2026-02-04.md"' "$(jqo '.lessons[1].resolved')"
runo "$tmp/lwt2" trace "$lb" --json
check "from a worktree that lacks the file, the lesson resolves from the main checkout" '"'"$LP"'/docs/solutions/testing/wt-2026-02-04.md"' "$(jqo '.lessons[1].resolved')"
git -C "$LP" worktree remove --force "$tmp/lwt2"

# A repo with no sidecar: trace on a lesson keeps working, quietly.
mkproj
NP="$P"
mkdir -p "$NP/docs/solutions/testing"
printf '# Solo\n' > "$NP/docs/solutions/testing/solo-2026-02-05.md"
runo "$NP" trace docs/solutions/testing/solo-2026-02-05.md --json
check "no sidecar: trace of a lesson exits 0" 0 "$rc"
check "no sidecar: taught_by is []" '[]' "$(jqo '.taught_by')"
check "no sidecar: nothing on stderr (no SIDECAR MISS)" "" "$err"
runo "$NP" trace docs/solutions/testing/solo-2026-02-05.md
check "no sidecar: text mode has no taught by line" 0 "$(printf '%s\n' "$out" | grep -c 'taught by')"
runo "$tmp" trace "$NP/docs/solutions/testing/solo-2026-02-05.md" --json
check "outside any repo: trace of a lesson exits 0 with taught_by []" '[0,[]]' "$(printf '[%s,%s]' "$rc" "$(jqo '.taught_by')")"

# -----------------------------------------------------------------------------
section "/compound's work-item block, run for real"

COMPOUND="$repo_root/compound/SKILL.md"
cblock="$(awk '/^<!-- work-lesson: compound -->$/ { on = 1; next }
               on && /^```bash$/ { inb = 1; next }
               inb && /^```$/ { exit }
               inb { print }' "$COMPOUND")"
if [ -z "$cblock" ]; then
    fatal "compound/SKILL.md has no \`\`\`bash block after <!-- work-lesson: compound -->"
fi
ok "compound/SKILL.md carries the work-lesson block"
# cblock_run <dir> <lesson> <W or empty>: the block with its three assignments filled in.
cblock_run() {
    local script
    script="$(printf '%s\n' "$cblock" | sed -e "s|^SC=.*|SC=\"$SC\"|" -e "s|^LESSON=.*|LESSON=\"$2\"|" -e "s|^W=.*|W=\"$3\"|")"
    out="$(cd "$1" && "$BASH" -c "$script" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}
lessons_of() { (cd "$LP" && "$BASH" "$SC" work view "$1" --json | jq -c .lessons); }

L3="$LP/docs/solutions/testing/three-2026-02-03.md"
runo "$LP" work create --kind slice --body-file "$tmp/body.md"; ca="$out"
cblock_run "$LP" "$L3" "$ca"
check "(a) a named item: exits 0" 0 "$rc"
check "(a) a named item: prints its id" "work item: $ca" "$out"
check "(a) a named item: the lesson is recorded, top-level relative" '["docs/solutions/testing/three-2026-02-03.md"]' "$(lessons_of "$ca")"

# (b) one item, closed, on the current branch; another item on another branch.
git -C "$LP" checkout -q -b feat-compound
runo "$LP" work create --kind slice --body-file "$tmp/body.md"; cb="$out"
runo "$LP" work set "$cb" branch feat-compound
runo "$LP" work close "$cb"
runo "$LP" work create --kind slice --body-file "$tmp/body.md"; cother="$out"
runo "$LP" work set "$cother" branch some-other-branch
cblock_run "$LP" "$L3" ""
check "(b) one closed item on the branch: exits 0" 0 "$rc"
check "(b) one closed item on the branch: prints its id" "work item: $cb" "$out"
check "(b) one closed item on the branch: recorded on that item only" '[["docs/solutions/testing/three-2026-02-03.md"],"null"]' \
    "$(printf '[%s,"%s"]' "$(lessons_of "$cb")" "$(lessons_of "$cother")")"
bhead="$(git -C "$LS" rev-parse HEAD)"
cblock_run "$LP" "$L3" ""
check "(b) a second run exits 0 and says the path is already listed" "0:work lesson: $cb already lists docs/solutions/testing/three-2026-02-03.md
work item: $cb" "$rc:$out"
check "(b) a second run makes no sidecar commit" "$bhead" "$(git -C "$LS" rev-parse HEAD)"

# (c) two items on the branch: nothing recorded, nothing committed.
runo "$LP" work create --kind slice --body-file "$tmp/body.md"; cc="$out"
runo "$LP" work set "$cc" branch feat-compound
chead="$(git -C "$LS" rev-parse HEAD)"
cblock_run "$LP" "$LP/docs/solutions/testing/one-2026-02-01.md" ""
check "(c) two items on the branch: exits 0" 0 "$rc"
case "$out" in "work item: not recorded"*) ok "(c) two items on the branch: prints not recorded" ;; *) bad "(c) two items on the branch: prints not recorded" "$out" ;; esac
check "(c) two items on the branch: no sidecar commit" "$chead" "$(git -C "$LS" rev-parse HEAD)"
check "(c) two items on the branch: neither gained a lesson" '[null,["docs/solutions/testing/three-2026-02-03.md"]]' "$(printf '[%s,%s]' "$(lessons_of "$cc")" "$(lessons_of "$cb")")"

# (d) detached HEAD.
git -C "$LP" checkout -q --detach
cblock_run "$LP" "$L3" ""
check "(d) detached HEAD: exits 0" 0 "$rc"
case "$out" in "work item: not recorded"*) ok "(d) detached HEAD: prints not recorded" ;; *) bad "(d) detached HEAD: prints not recorded" "$out" ;; esac
check "(d) detached HEAD: no sidecar commit" "$chead" "$(git -C "$LS" rev-parse HEAD)"

# (e) a repo whose slices live on the forge.
mkproj
cblock_run "$P" "$P/none.md" ""
check "(e) no sidecar: exits 0" 0 "$rc"
case "$out" in "work item: n/a"*) ok "(e) no sidecar: prints n/a" ;; *) bad "(e) no sidecar: prints n/a" "$out" ;; esac

# (f) a failed work lesson fails the block.
git -C "$LP" checkout -q feat-compound
printf '# Sp\n' > "$LP/docs/solutions/testing/has space.md"
cblock_run "$LP" "$LP/docs/solutions/testing/has space.md" "$ca"
check "(f) a lesson path work lesson refuses: the block exits nonzero" 1 "$rc"
check "(f) and prints no work item line" 0 "$(printf '%s\n' "$out" | grep -c '^work item: W-')"
rm -f "$LP/docs/solutions/testing/has space.md"

# (g) run from the base branch: an old closed slice that once built there is not a match.
runo "$LP" base-ref --name; basebr="$out"
git -C "$LP" checkout -q "$basebr"
runo "$LP" work create --kind slice --body-file "$tmp/body.md"; cold="$out"
runo "$LP" work set "$cold" branch "$basebr"
runo "$LP" work close "$cold"
ghead="$(git -C "$LS" rev-parse HEAD)"
cblock_run "$LP" "$L3" ""
check "(g) on the base branch: exits 0" 0 "$rc"
case "$out" in "work item: not recorded"*) ok "(g) on the base branch: prints not recorded" ;; *) bad "(g) on the base branch: prints not recorded" "$out" ;; esac
check "(g) on the base branch: no sidecar commit" "$ghead" "$(git -C "$LS" rev-parse HEAD)"
check "(g) on the base branch: the old item gained no lesson" null "$(lessons_of "$cold")"

# -----------------------------------------------------------------------------
section "/help's work-item block, run for real"

# /help Phase 1b reads the work store on the sidecar backend (#696): the
# frontier is work list --unblocked, each open PRD is traced, and so is the
# current branch's work item. Run the block as written, with only SC filled in.
HELP="$repo_root/help/SKILL.md"
hblock="$(awk '/^<!-- sidecar-read: help-work -->$/ { on = 1; next }
               on && /^```bash$/ { inb = 1; next }
               inb && /^```$/ { exit }
               inb { print }' "$HELP")"
[ -n "$hblock" ] || fatal "help/SKILL.md has no \`\`\`bash block after <!-- sidecar-read: help-work -->"
ok "help/SKILL.md carries the work-item block"
hblock_run() {
    local script
    script="$(printf '%s\n' "$hblock" | sed -e "s|^SC=.*|SC=\"$SC\"|")"
    out="$(cd "$1" && "$BASH" -c "$script" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "no [$2] in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2] in: $3" ;; *) ok "$1" ;; esac; }

# (a) The fixture #696 names: one open PRD, two slices, one of them blocked.
mkproj
HP="$P"
runo "$HP" init --name helpwork --mode guest --write sidecar --in-tree-path none --no-migrate-archive
HS="$out"
[ -d "$HS" ] || fatal "init did not create the /help fixture sidecar: $err"
hblock_run "$HP"
has "an empty store: no open PRDs" "open PRDs: none" "$out"
has "an empty store: no unblocked slices" "unblocked slices: none" "$out"
runo "$HP" work create --kind prd --body-file "$tmp/body.md"; hprd="$out"
runo "$HP" work create --kind slice --parent "$hprd" --body-file "$tmp/body.md"; ha="$out"
runo "$HP" work create --kind slice --parent "$hprd" --blocked-by "$ha" --body-file "$tmp/body.md"; hb="$out"
runo "$HP" work set "$hprd" decomposed_into "$ha,$hb"
hhead="$(git -C "$HS" rev-parse HEAD)"
hblock_run "$HP"
check "(a) exits 0" 0 "$rc"
has "(a) lists the open PRD" "open PRDs: $hprd" "$out"
has "(a) lists both open slices" "open slices: $ha $hb" "$out"
has "(a) lists only the unblocked slice as unblocked" "unblocked slices: $ha"$'\n' "$out"
has "(a) traces the open PRD" "$hprd  prd  open" "$out"
has "(a) the PRD's trace lists the unblocked slice as a child" "  child  $ha (open)" "$out"
has "(a) the PRD's trace lists the blocked slice as a child" "  child  $hb (open)" "$out"
has "(a) on the base branch, no branch item is looked up" "branch work item: none, on the base branch main" "$out"
check "(a) the block commits nothing in the sidecar" "$hhead" "$(git -C "$HS" rev-parse HEAD)"
check "(a) the block leaves the project tree clean" "" "$(git -C "$HP" status --porcelain)"

# (b) A feature branch with one work item: its trace, PR included, is printed.
git -C "$HP" checkout -q -b feat-help
runo "$HP" work set "$ha" branch feat-help
runo "$HP" work set "$ha" pr "https://github.com/acme/helpwork/pull/9"
hblock_run "$HP"
check "(b) exits 0" 0 "$rc"
has "(b) names the branch's work item" "branch work item: $ha"$'\n' "$out"
has "(b) traces it" "$ha  slice  open" "$out"
has "(b) the trace carries the PR row 1 reads" "  pr  https://github.com/acme/helpwork/pull/9" "$out"
has "(b) the trace carries its parent" "  parent  $hprd (open)" "$out"

# (c) A closed item on the same branch counts: the branch has two items now.
runo "$HP" work create --kind slice --parent "$hprd" --body-file "$tmp/body.md"; hc="$out"
runo "$HP" work set "$hc" branch feat-help
runo "$HP" work close "$hc"
hblock_run "$HP"
has "(c) two items on one branch are reported as several" "branch work items: several on feat-help: $ha $hc" "$out"
hasnt "(c) and neither is traced as the branch's" "branch work item: " "$out"

# (d) A branch nothing records.
git -C "$HP" checkout -q -b feat-other
hblock_run "$HP"
has "(d) a branch with no item says so" "branch work item: none recorded on feat-other" "$out"

# (e) Detached HEAD.
git -C "$HP" checkout -q --detach
hblock_run "$HP"
has "(e) a detached HEAD says so" "branch work item: none, HEAD is detached" "$out"
git -C "$HP" checkout -q main

# (f) An unparseable work file: one line, exit 0, so the parallel batch survives.
printf -- '---\nnot: [closed\n' > "$HS/work/W-90.md"
hblock_run "$HP"
check "(f) an unreadable store still exits 0" 0 "$rc"
has "(f) and says so" "work items: unreadable" "$out"
hasnt "(f) and prints no frontier" "unblocked slices:" "$out"
rm -f "$HS/work/W-90.md"

# (g) A backend refusal: unavailable, exit 0, never a gh fallback.
cp "$HS/sidecar.json" "$tmp/sidecar.json.bak"
jq '.forge.write = "issues"' "$tmp/sidecar.json.bak" > "$HS/sidecar.json"
hblock_run "$HP"
check "(g) a backend refusal still exits 0" 0 "$rc"
has "(g) and reports the work items as unavailable" "work items: unavailable" "$out"
cp "$tmp/sidecar.json.bak" "$HS/sidecar.json"

# (h) No sidecar: the forge holds the slices.
mkproj
hblock_run "$P"
check "(h) no sidecar: exits 0" 0 "$rc"
has "(h) no sidecar: prints n/a" "work items: n/a" "$out"

# -----------------------------------------------------------------------------
section "/execute Step 1's trace block, run for real"

# /execute Step 1 traces the slice and its parent PRD, so a lesson an earlier
# slice of the feature taught is read before the keyword grep (#727 story 2).
EXECUTE="$repo_root/execute/SKILL.md"
eblock="$(awk '/^<!-- sidecar-read: execute-trace -->$/ { on = 1; next }
               on && /^```bash$/ { inb = 1; next }
               inb && /^```$/ { exit }
               inb { print }' "$EXECUTE")"
[ -n "$eblock" ] || fatal "execute/SKILL.md has no \`\`\`bash block after <!-- sidecar-read: execute-trace -->"
ok "execute/SKILL.md carries the trace block"
eblock_run() {
    local script
    script="$(printf '%s\n' "$eblock" | sed -e "s|^SC=.*|SC=\"$SC\"|" -e "s|^W=.*|W=\"$2\"|")"
    out="$(cd "$1" && "$BASH" -c "$script" 2>"$tmp/stderr")"; rc=$?
    err="$(cat "$tmp/stderr")"
}

# The /help fixture: $hc is a closed sibling of $hb under $hprd. Give it a lesson.
mkdir -p "$HP/docs/solutions/testing"
printf '# Taught\n' > "$HP/docs/solutions/testing/taught-2026-03-01.md"
runo "$HP" work lesson "$hc" "$HP/docs/solutions/testing/taught-2026-03-01.md"
check "fixture: the sibling's lesson is recorded" 0 "$rc"
ehead="$(git -C "$HS" rev-parse HEAD)"
eblock_run "$HP" "$hb"
check "a slice with a parent: exits 0" 0 "$rc"
has "the slice's own trace is printed" "$hb  slice  open" "$out"
has "the slice's trace names its blocker" "  blocked by  $ha (open)" "$out"
has "the parent PRD's trace is printed" "$hprd  prd  open" "$out"
has "the PRD's trace names the closed sibling" "  child  $hc (closed)" "$out"
has "and the lesson that sibling taught, resolved" "    lesson  $HP/docs/solutions/testing/taught-2026-03-01.md" "$out"
check "the block commits nothing in the sidecar" "$ehead" "$(git -C "$HS" rev-parse HEAD)"

# A lesson file that is gone is reported, never fatal.
mv "$HP/docs/solutions/testing/taught-2026-03-01.md" "$tmp/taught.md"
eblock_run "$HP" "$hb"
check "a missing sibling lesson: still exits 0" 0 "$rc"
has "a missing sibling lesson prints MISSING:" "lesson  MISSING: docs/solutions/testing/taught-2026-03-01.md" "$out"
mv "$tmp/taught.md" "$HP/docs/solutions/testing/taught-2026-03-01.md"

# A PRD has no parent: one trace.
eblock_run "$HP" "$hprd"
check "an item with no parent: exits 0" 0 "$rc"
check "an item with no parent: traced once" 1 "$(printf '%s\n' "$out" | grep -c "^$hprd  prd  open$")"

# A work item the store does not hold fails the block.
eblock_run "$HP" W-404
check "a work item the store does not hold: exits 1" 1 "$rc"

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
