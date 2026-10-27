#!/usr/bin/env bash
# test-respond-to-review-contract.sh — /respond-to-review reads a teammate's
# review faithfully, keeps its record where it says, and never speaks for the
# author (#607).
#
# THE DRIFT CLASS. /respond-to-review hands a teammate's comments to a fresh
# evidence reader and, for the threads the human marks fix, to /fix-findings,
# whose Inputs rule forbids fixing a reconstruction. So the read itself is the
# contract: a block that drops a thread, paraphrases a body, or prints a
# truncated list as if it were whole sends every later step to work from a
# review nobody wrote. The failure is silent: a missing thread looks exactly
# like a thread that was never written. The same is true of the record (a
# settled thread re-opened, or a new reply missed) and of the commit trailer
# that ties a fix back to its thread. And the skill's promise never to post,
# resolve, or write into the project tree is made in prose an agent runs in
# someone else's repository.
#
# WHAT IT PINS, every block extracted from the real SKILL.md and run:
#   1. Step 1's fetch block against a stubbed `gh`: resolved threads, threads
#      and reviews the PR author started, and empty review bodies are dropped;
#      outdated threads and bots are kept; items are numbered in time order;
#      every comment body survives byte for byte; and every short or failed
#      read prints `unknown`.
#   2. Step 1's record read against planted records: the latest round wins per
#      thread, and a marker in any other shape is not read.
#   3. Step 1's Review-Thread log read against a scratch repo, and the trailer
#      string agreeing with the one /fix-findings Step 1 tells its fixer to write.
#   4. No fenced block in the skill posts, replies, resolves, or mutates, and
#      the record goes through sidecar.sh rather than an inlined path.
#   5. The routes and bundles the skill depends on exist.
# Every detector is mutation-tested below.

# Every single-quoted `$` below is the skill's literal text or a planted
# fixture, never an expansion this script wants.
# shellcheck disable=SC2016
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
R2R="$repo_root/respond-to-review/SKILL.md"
FF="$repo_root/fix-findings/SKILL.md"
CO="$repo_root/closeout/SKILL.md"
HELP="$repo_root/help/SKILL.md"
MANIFEST="$repo_root/scripts/skill-references.manifest"
for f in "$R2R" "$FF" "$CO" "$HELP" "$MANIFEST"; do [ -f "$f" ] || { printf 'FATAL %s is missing\n' "$f"; exit 1; }; done

tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Review Tester"
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
section "Step 1's fetch block, against a stubbed gh"

FETCH="$(block "$R2R" 'THREADS_JQ=')"
check "the fetch block is found" 1 "$([ -n "$FETCH" ] && echo 1 || echo 0)"
printf '%s' "$FETCH" | sed 's/^PR=<pr-number>$/PR=7/' > "$tmp/fetch.sh"
check "the fetch block's PR placeholder is substituted" 1 "$(grep -cx 'PR=7' "$tmp/fetch.sh")"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Prints $GH_FIXTURE for a graphql call, or fails when it is absent.
printf '%s\n' "$*" >> "$GH_STUB_CALLS"
[ "$1" = api ] && [ "$2" = graphql ] || { echo "stub gh: unexpected call: $*" >&2; exit 1; }
[ -n "${GH_FIXTURE:-}" ] && [ -f "$GH_FIXTURE" ] || { echo "stub gh: 502" >&2; exit 1; }
cat "$GH_FIXTURE"
STUB
chmod +x "$tmp/bin/gh"
export GH_STUB_CALLS="$tmp/gh-calls"

# A body carrying every byte a careless pipeline mangles: a comment terminator,
# backticks, a variable, a quote, a backslash, and a second line.
TRICKY='Can we drop this? It ends the marker --> and `$HOME` is "quoted" \ here
second line'

# fixture <file> <thread-total> <review-total> <comment-total-of-thread-1> [errors]
fixture() {
    jq -n --arg tricky "$TRICKY" --argjson tt "$2" --argjson rt "$3" --argjson ct "$4" --arg err "${5:-}" '
    def c(a; b; t): {author: {login: a}, body: b, url: ("https://github.com/acme/app/pull/7#discussion_" + t), createdAt: t};
    {data: {repository: {pullRequest: {
      number: 7, state: "OPEN", headRefOid: "abc123", headRefName: "feat", author: {login: "me"},
      reviewThreads: {totalCount: $tt, nodes: [
        {id: "PRRT_a", isResolved: false, isOutdated: false, path: "src/a.ts", line: 4,
         comments: {totalCount: $ct, nodes: [c("teammate"; $tricky; "2026-10-02T00:00:00Z"), c("me"; "Fair point."; "2026-10-03T00:00:00Z")]}},
        {id: "PRRT_resolved", isResolved: true, isOutdated: false, path: "src/b.ts", line: 9,
         comments: {totalCount: 1, nodes: [c("teammate"; "settled"; "2026-10-01T00:00:00Z")]}},
        {id: "PRRT_mine", isResolved: false, isOutdated: false, path: "src/c.ts", line: 1,
         comments: {totalCount: 1, nodes: [c("me"; "note to self"; "2026-10-01T01:00:00Z")]}},
        {id: "PRRT_old", isResolved: false, isOutdated: true, path: "src/d.ts", line: null,
         comments: {totalCount: 1, nodes: [c("copilot-pull-request-reviewer"; "stale line, maybe still true"; "2026-10-01T02:00:00Z")]}}
      ]},
      reviews: {totalCount: $rt, nodes: [
        {id: "PRR_empty", state: "COMMENTED", body: "", url: "u1", author: {login: "teammate"}, submittedAt: "2026-10-02T00:00:01Z"},
        {id: "PRR_cr", state: "CHANGES_REQUESTED", body: "Please split the migration out.", url: "u2", author: {login: "teammate"}, submittedAt: "2026-10-04T00:00:00Z"},
        {id: "PRR_mine", state: "COMMENTED", body: "self review", url: "u3", author: {login: "me"}, submittedAt: "2026-10-04T01:00:00Z"}
      ]}
    }}}} + (if $err == "" then {} else {errors: [{message: $err}]} end)' > "$1"
}

runfetch() { GH_FIXTURE="$1" PATH="$tmp/bin:$PATH" bash "$tmp/fetch.sh" 2>/dev/null; }

fixture "$tmp/ok.json" 4 3 2
OUT="$(runfetch "$tmp/ok.json")"
check "a whole read prints JSON, not unknown" 1 "$(jq -e '.items | type == "array"' <<<"$OUT" >/dev/null 2>&1 && echo 1 || echo 0)"
check "it keeps exactly the unresolved, non-author threads and the non-empty, non-author reviews" \
    "PRRT_old PRRT_a PRR_cr" "$(jq -r '[.items[].id] | join(" ")' <<<"$OUT" 2>/dev/null)"
check "items are numbered 1..n in time order" "1 2 3" "$(jq -r '[.items[].n] | map(tostring) | join(" ")' <<<"$OUT" 2>/dev/null)"
check "an outdated thread is kept and says so" "true" "$(jq -r '.items[] | select(.id == "PRRT_old") | .outdated' <<<"$OUT" 2>/dev/null)"
check "a bot's thread is kept" "copilot-pull-request-reviewer" "$(jq -r '.items[] | select(.id == "PRRT_old") | .comments[0].author' <<<"$OUT" 2>/dev/null)"
check "a thread's replies are kept, the author's included" "teammate me" "$(jq -r '.items[] | select(.id == "PRRT_a") | [.comments[].author] | join(" ")' <<<"$OUT" 2>/dev/null)"
check "last_at is the newest comment's time (what a re-run compares)" "2026-10-03T00:00:00Z" "$(jq -r '.items[] | select(.id == "PRRT_a") | .last_at' <<<"$OUT" 2>/dev/null)"
got_body="$(jq -r '.items[] | select(.id == "PRRT_a") | .comments[0].body' <<<"$OUT" 2>/dev/null)"
check "a comment body survives byte for byte" "$TRICKY" "$got_body"
check "the PR's head ref comes back (Step 1 compares it with the branch)" "feat" "$(jq -r '.head_ref' <<<"$OUT" 2>/dev/null)"

fixture "$tmp/short-threads.json" 5 3 2
check "a thread list shorter than its totalCount prints unknown" unknown "$(runfetch "$tmp/short-threads.json")"
fixture "$tmp/short-reviews.json" 4 4 2
check "a review list shorter than its totalCount prints unknown" unknown "$(runfetch "$tmp/short-reviews.json")"
fixture "$tmp/short-comments.json" 4 3 3
check "a thread whose comments came back short prints unknown" unknown "$(runfetch "$tmp/short-comments.json")"
fixture "$tmp/errors.json" 4 3 2 "Something went wrong"
check "a response carrying errors prints unknown" unknown "$(runfetch "$tmp/errors.json")"
jq '.data.repository.pullRequest.number = 8' "$tmp/ok.json" > "$tmp/other-pr.json"
check "a response for another PR prints unknown" unknown "$(runfetch "$tmp/other-pr.json")"
jq '.data.repository.pullRequest = null' "$tmp/ok.json" > "$tmp/null-pr.json"
check "a PR that did not come back prints unknown" unknown "$(runfetch "$tmp/null-pr.json")"
check "a failed gh call prints unknown" unknown "$(runfetch "$tmp/does-not-exist.json")"

# Past the bound: a PR with more than 100 threads or reviews, or a thread with
# more than 50 comments, returns a full page whose length equals the bound, so a
# guard that compares against min(totalCount, bound) passes it silently.
# The fixtures pad each list to the bound, as GitHub would return it.
fixture "$tmp/ok-over.json" 4 3 2
jq '.data.repository.pullRequest.reviewThreads |= (.totalCount = 150 | .nodes = [range(100) as $i | .nodes[0] | .id = "PRRT_\($i)"])' "$tmp/ok-over.json" > "$tmp/over-threads.json"
check "a thread list past the 100 bound prints unknown" unknown "$(runfetch "$tmp/over-threads.json")"
jq '.data.repository.pullRequest.reviews |= (.totalCount = 150 | .nodes = [range(100) as $i | .nodes[1] | .id = "PRR_\($i)"])' "$tmp/ok-over.json" > "$tmp/over-reviews.json"
check "a review list past the 100 bound prints unknown" unknown "$(runfetch "$tmp/over-reviews.json")"
jq '.data.repository.pullRequest.reviewThreads.nodes[0].comments |= (.totalCount = 80 | .nodes = [range(50) as $i | .nodes[0]])' "$tmp/ok-over.json" > "$tmp/over-comments.json"
check "a thread with comments past the 50 bound prints unknown" unknown "$(runfetch "$tmp/over-comments.json")"
jq '.data.repository.pullRequest.reviewThreads |= (.totalCount = 100 | .nodes = [range(100) as $i | .nodes[0] | .id = "PRRT_\($i)"])' "$tmp/ok-over.json" > "$tmp/at-bound.json"
check "a list exactly at the bound is still read whole" 1 "$(runfetch "$tmp/at-bound.json" | jq -e '.items | length == 101' >/dev/null 2>&1 && echo 1 || echo 0)"

# Mutation: the resolved filter is load-bearing — without it a settled thread
# comes back as feedback, and the id assertion above must notice.
sed 's/| select(.isResolved | not)//' "$tmp/fetch.sh" > "$tmp/fetch-mut.sh"
check "M1: the mutation removed the resolved filter" 0 "$(grep -c 'isResolved | not' "$tmp/fetch-mut.sh")"
MUT="$(GH_FIXTURE="$tmp/ok.json" PATH="$tmp/bin:$PATH" bash "$tmp/fetch-mut.sh" 2>/dev/null)"
check "M1: without the resolved filter the id assertion would fail" 1 \
    "$([ "$(jq -r '[.items[].id] | join(" ")' <<<"$MUT" 2>/dev/null)" != "PRRT_old PRRT_a PRR_cr" ] && echo 1 || echo 0)"
# Mutation: the truncation guard is load-bearing.
grep -v 'reviewThreads.nodes | length) != $p.reviewThreads.totalCount' "$tmp/fetch.sh" > "$tmp/fetch-mut2.sh"
check "M2: without the thread-count guard a short read is not unknown" 1 \
    "$([ "$(GH_FIXTURE="$tmp/short-threads.json" PATH="$tmp/bin:$PATH" bash "$tmp/fetch-mut2.sh" 2>/dev/null)" != unknown ] && echo 1 || echo 0)"

# -----------------------------------------------------------------------------
section "Step 1's record read, against planted records"

READ="$(block "$R2R" 'disposition=[^ ]+')"
check "the record-read block is found" 1 "$([ -n "$READ" ] && echo 1 || echo 0)"
mkdir -p "$tmp/sidecar/review-responses"
cat > "$tmp/sc-stub.sh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
    "path review-responses") echo "$tmp/sidecar/review-responses" ;;
    *) echo "stub sidecar: unexpected call: \$*" >&2; exit 1 ;;
esac
STUB
printf '%s' "$READ" \
    | sed "s|^SC=\"<this skill's directory>/references/sidecar.sh\"$|SC=\"$tmp/sc-stub.sh\"|" \
    | sed 's|pr-<pr-number>\.md|pr-7.md|' > "$tmp/read.sh"
check "the record-read block's placeholders are substituted" 0 "$(grep -c "<pr-number>\\|<this skill" "$tmp/read.sh")"

cat > "$tmp/sidecar/review-responses/pr-7.md" <<'REC'
# Review responses — PR 7

## Round 1 — 2026-10-02, head abc1234

<!-- round: k=1 head=abc1234abc1234abc1234abc1234abc1234abcd evidence=sub-agent -->

### 1. src/a.ts:4 — https://github.com/acme/app/pull/7#discussion_r1

<!-- thread: id=PRRT_a last-at=2026-10-02T00:00:00Z disposition=open -->

### 2. review summary — u2

<!-- thread: id=PRR_cr last-at=2026-10-04T00:00:00Z disposition=postpone -->

> Quoting a marker inside a comment: <!-- thread: id=PRRT_fake last-at=x disposition=fix -->

## Round 2 — 2026-10-05, head def5678

<!-- thread: id=PRRT_a last-at=2026-10-03T00:00:00Z disposition=push-back -->
<!-- thread: id=PRRT_bad last-at=2026-10-03T00:00:00Z -->
REC
GOT="$(bash "$tmp/read.sh")"
check "the latest round wins per thread, and only exact markers are read" \
    "PRRT_a 2026-10-03T00:00:00Z push-back
PRR_cr 2026-10-04T00:00:00Z postpone" "$GOT"
rm "$tmp/sidecar/review-responses/pr-7.md"
check "no record prints nothing (a first round)" "" "$(bash "$tmp/read.sh")"

# -----------------------------------------------------------------------------
section "the Review-Thread trailer, written by /fix-findings and read by /respond-to-review"

check "/fix-findings Step 1 tells its fixer to write 'Review-Thread: <url>'" 1 \
    "$(grep -c 'carries `Review-Thread: <url>`' "$FF" | awk '{print ($1 > 0)}')"
check "/fix-findings puts the trailer above Fix-Findings-Run, which stays the last line" 1 \
    "$(grep -c 'the line just above it' "$FF" | awk '{print ($1 > 0)}')"
LOGREAD="$(block "$R2R" '^Review-Thread: ')"
check "the log-read block reads the same trailer string" 1 "$(grep -c "/^Review-Thread: /" <<<"$LOGREAD")"

g="$tmp/repo"
git init -q "$g"
git -C "$g" commit -q --allow-empty -m base
git -C "$g" branch -q basebr
git -C "$g" commit -q --allow-empty -m "Guard the empty list

commit.notasha in a body line must not be read as a commit
Review-Thread: https://github.com/acme/app/pull/7#discussion_r1
Fix-Findings-Run: 20261027T000000Z"
want_sha="$(git -C "$g" log -1 --format=%h)"
git -C "$g" commit -q --allow-empty -m "unrelated"
cat > "$tmp/sc-base.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = base-ref ] && { echo basebr; exit 0; }
echo "stub sidecar: unexpected call: $*" >&2; exit 1
STUB
printf '%s' "$LOGREAD" | sed "s|^SC=\"<this skill's directory>/references/sidecar.sh\"$|SC=\"$tmp/sc-base.sh\"|" > "$tmp/log.sh"
got="$(cd "$g" && bash "$tmp/log.sh")"
# The planted body line starting with "commit." is the case the 47-character
# hex match exists for: a looser match would take it as the commit and
# attribute the trailer to a SHA that does not exist.
check "the log read names the fix commit and its thread" \
    "$want_sha https://github.com/acme/app/pull/7#discussion_r1" \
    "$(awk -v s="$want_sha" '$1 == s' <<<"$got")"

sed 's/length($0) == 47 \&\& \/\^commit\\.\[0-9a-f\]+\$\//\/^commit\\.\//' "$tmp/log.sh" > "$tmp/log-mut.sh"
check "M5: the mutation loosened the commit match" 0 "$(grep -c 'length(\$0) == 47' "$tmp/log-mut.sh")"
check "M5: with a loose match the trailer is attributed to a body line, not the commit" 1 \
    "$([ "$(cd "$g" && bash "$tmp/log-mut.sh" | awk -v s="$want_sha" '$1 == s')" = "" ] && echo 1 || echo 0)"

# -----------------------------------------------------------------------------
section "never posts, never mutates, never writes the record by hand"

# posts <file> — print each forge-writing call in the file's fenced blocks.
posts() {
    awk '/^ *```/ { on = !on; next } on' "$1" \
        | grep -nE 'gh +(pr|issue) +(comment|review|edit|close|merge)|gh +api .*(-X|--method) *(POST|PATCH|PUT|DELETE)|mutation[[:space:]]*[({]|resolveReviewThread|addPullRequestReview' || true
}
check "no fenced block in /respond-to-review writes to the forge" "" "$(posts "$R2R")"
cp "$R2R" "$tmp/planted.md"
printf '\n```bash\ngh pr comment 7 --body-file reply.md\n```\n' >> "$tmp/planted.md"
check "M3: the detector fires on a planted gh pr comment" 1 "$(posts "$tmp/planted.md" | grep -c .)"
cp "$R2R" "$tmp/planted2.md"
printf '\n```bash\ngh api graphql -f query='"'"'mutation { resolveReviewThread(input: {threadId: "x"}) { thread { id } } }'"'"'\n```\n' >> "$tmp/planted2.md"
check "M4: the detector fires on a planted resolve mutation" 1 "$(posts "$tmp/planted2.md" | grep -c . | awk '{print ($1 > 0)}')"

check "no fenced block inlines a sidecar path" 0 \
    "$(awk '/^ *```/ { on = !on; next } on' "$R2R" | grep -c '\.claude/sidecars')"
WRITE="$(block "$R2R" '"$SC" commit')"
check "the record is written to sidecar.sh's review-responses path" 1 "$(grep -c 'path review-responses' <<<"$WRITE")"
check "the record is committed through sidecar.sh commit" 1 "$(grep -c '"\$SC" commit --' <<<"$WRITE")"

# -----------------------------------------------------------------------------
section "routes and bundles"

for b in docs/comment-craft.md docs/next-step-menu.md init-pipeline/scripts/sidecar.sh; do
    check "the manifest bundles $b into respond-to-review" 1 \
        "$(awk -v s="$b" '$1 == s && $2 == "respond-to-review"' "$MANIFEST" | grep -c .)"
done
check "/fix-findings' Inputs name /respond-to-review as a source" 1 \
    "$(awk '/^## Inputs/ { on = 1; next } /^## / { on = 0 } on' "$FF" | grep -c '/respond-to-review' | awk '{print ($1 > 0)}')"
check "/closeout Step 2 routes failed review to /respond-to-review" 1 \
    "$(awk '/^### 2\./ { on = 1; next } /^### 3\./ { on = 0 } on' "$CO" | grep -c '/respond-to-review' | awk '{print ($1 > 0)}')"
check "/help row 1 recommends /respond-to-review on CHANGES_REQUESTED" 1 \
    "$(grep -E '^\| 1 \|' "$HELP" | grep -c 'CHANGES_REQUESTED.*/respond-to-review')"
check "/help gathers reviewDecision, which row 1 reads" 1 \
    "$(grep -c 'gh pr list .*reviewDecision' "$HELP" | awk '{print ($1 > 0)}')"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
