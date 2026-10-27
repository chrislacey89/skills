---
name: respond-to-review
description: "Side-route for when a teammate's review lands on your open PR and you want to decide what to fix, what to push back on, and what to defer. Each thread's claim is checked against the code by a fresh sub-agent before you decide, threads you mark fix go to /fix-findings, pushback gets a reply draft you post yourself, and a record stays in the project's sidecar so you can come back to it. Not for reviewing someone else's PR (that's /pre-merge --pr), not for the pack's own review findings (that's /fix-findings from the /pre-merge menu), and never on an AFK run."
sources:
  primary:
    - "Best Kept Secrets of Peer Code Review — Jason Cohen"
  secondary:
    - "Peer Review on Open-Source Software Projects — Peter C. Rigby"
    - "Looks Good to Me — Adrienne Braganza Tacke"
    - "The Design of Everyday Things — Don Norman"
---

# Respond to Review

Take a teammate's review of your PR, check each comment's claim against the
code with a reader who did not write it, let the human decide what happens to
each one, hand the fixes to `/fix-findings`, draft the pushback, and leave a
record in the project's sidecar to come back to.

## Why this skill exists

On a team, most PRs get a human review after `/pre-merge` has stamped them.
Before this skill, the pack had no route for that review. `/pre-merge` writes
`.claude/.review-stamped` beside its stamp, the post-review edit lock then
refuses implementation edits unless `/fix-findings` is running, and
`/fix-findings` accepted only findings from a `/pre-merge` run. A teammate's
comment was neither, so the only way to act on it was to delete the lock by
hand and fix in the session that wrote the code.

Sending those comments straight into `/fix-findings` would have been the wrong
repair. Its fixer is briefed to fix, and reports `refuted` only when the tree
flatly contradicts a claim. A comment that is accurate but wrong in judgment, a
preference phrased as a requirement, or a request outside the PR's scope would
all get fixed. Most review comments are not defects in the first place.
Rigby's finding is that contemporary review is discussion, not defect logging.
So this skill puts a step in front of the fix seam: check whether the claim is
true, then let the human decide. Cohen's verification loop says a fix has to be
checked. This skill checks the defect before anyone fixes it.

The check runs in a fresh sub-agent because the session that wrote the code is
the one context with a stake in the answer. A fixer leans toward fixing. An
author leans toward defending. The evidence check leans toward neither.

## Invocation Position

**Side-route, HITL only.** It fires when a human reviewer exists, so solo work
never reaches it. Enter it:

- from `/closeout` Step 2, when the PR's `reviewDecision` is
  `CHANGES_REQUESTED` or it has unresolved review threads;
- from `/help`, which recommends it on the same signal;
- by typing `/respond-to-review` (current branch's PR) or
  `/respond-to-review <pr-number>`.

It is model-invocable so those routes can run it rather than only name it. The
cost is its `description` in every session's context. What gates it is the
input: a PR with review threads, and a human in the session who asked to
respond. Never run it on an AFK iteration. There is nobody to decide the
threads, so there is no valid output.

It reconnects at `/fix-findings` → `/pre-merge` re-run → `/closeout`, the path
`/pre-merge`'s own findings already take.

## What this skill is NOT

- **It does not decide.** The evidence check records what it found, never what
  should happen. A thread marked `refuted` is evidence for the human, and
  pushing back is still the human's call. A thread the human does not name
  stays open. It is never defaulted to any disposition.
- **It does not post, reply, or resolve.** Reply drafts print to the terminal
  for the human to edit and post. Nothing in this skill writes to the PR.
- **It does not fix.** Threads marked **fix** go to `/fix-findings`, which
  keeps its own fresh fixer, breaker, cap, and handoff unchanged.
- **It does not stamp and does not merge.** `/pre-merge` is the stamp's only
  writer and `/closeout` is the only thing that merges.
- **It writes nothing in the project's tree.** Its one durable output is the
  record in the sidecar.

## Workflow

### Step 1. Read the review, word for word

Resolve the PR: the number the human gave, or the current branch's PR
(`gh pr view --json number -q .number`). Then read its unresolved review
threads and its non-empty review summaries in one GraphQL call. The block
numbers them in time order and keeps every comment body exactly as written:

```bash
PR=<pr-number>
THREADS_JQ='
[inputs][0] | if (.errors // [] | length) > 0 then "unknown" else
.data.repository.pullRequest as $p
| if $p == null or $p.number != $n
     or ($p.reviewThreads.nodes | type) != "array"
     or ($p.reviews.nodes | type) != "array"
     or ($p.reviewThreads.nodes | length) != $p.reviewThreads.totalCount
     or ($p.reviews.nodes | length) != $p.reviews.totalCount
     or ([$p.reviewThreads.nodes[] | select((.comments.nodes | length) != .comments.totalCount)] | length) > 0
  then "unknown"
  else
    ($p.author.login // "") as $me
    | ([$p.reviewThreads.nodes[]
        | select(.isResolved | not)
        | select((.comments.nodes[0].author.login // "") != $me)
        | {kind: "thread", id, path, line, outdated: .isOutdated,
           url: .comments.nodes[0].url, at: .comments.nodes[0].createdAt,
           last_at: .comments.nodes[-1].createdAt,
           comments: [.comments.nodes[] | {author: (.author.login // "ghost"), body, url, at: .createdAt}]}]
       + [$p.reviews.nodes[]
        | select((.body // "") != "" and (.author.login // "") != $me)
        | {kind: "review", id, state, url, at: .submittedAt, last_at: .submittedAt,
           comments: [{author: (.author.login // "ghost"), body, url, at: .submittedAt}]}])
    | sort_by(.at)
    | {pr: $p.number, state: $p.state, head: $p.headRefOid, head_ref: $p.headRefName,
       items: (to_entries | map(.value + {n: (.key + 1)}))}
    | tojson
  end
end'
RESP=$(gh api graphql -F owner='{owner}' -F repo='{repo}' -F n="$PR" -f query='
  query($owner: String!, $repo: String!, $n: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $n) {
        number state headRefOid headRefName author { login }
        reviewThreads(first: 100) { totalCount nodes {
          id isResolved isOutdated path line
          comments(first: 50) { totalCount nodes { author { login } body url createdAt } } } }
        reviews(first: 100) { totalCount nodes { id state body url author { login } submittedAt } }
      }
    }
  }') || RESP=null
jq -rn --argjson n "$PR" "$THREADS_JQ" <<<"${RESP:-null}" || echo unknown
```

It prints one JSON object, or the single word `unknown`.

- **`unknown`** means `gh` failed, the response carried errors, the PR did not
  come back, or a list came back shorter than its own `totalCount`. Re-run
  once. If it is still `unknown`, tell the human and stop. Never evaluate a
  short read: a missing thread looks exactly like a thread that was never
  written.
- **What is left out, and why.** Resolved threads are settled. Threads and
  reviews the PR's author started are the author's own notes, not feedback.
  Review summaries with an empty body are only the containers GitHub makes for
  inline comments, which arrive as threads.
- **What is kept.** Outdated threads (the line moved, but the comment may
  still stand, and the evidence check says which) and bot reviewers. The human
  decides what a bot's comment is worth, not this block.
- **Bounds.** It reads up to 100 threads, 100 reviews, and 50 comments per
  thread, and says `unknown` rather than silently truncating past them.
- **On a forge `gh` cannot reach** the call fails and the block prints
  `unknown`. This skill is GitHub-only for now.

If the PR's `state` is not `OPEN`, say so and stop. If `head_ref` is not the
current branch, the evidence check can still run, but say before Step 5 that
fixes need the PR's branch checked out.

**When the record already exists, read it first** (Step 4 says where it
lives). Its thread markers say which items an earlier round already settled:

```bash
SC="<this skill's directory>/references/sidecar.sh"
REC="$(bash "$SC" path review-responses)/pr-<pr-number>.md"
[ -f "$REC" ] && awk '
  match($0, /^<!-- thread: id=[^ ]+ last-at=[^ ]+ disposition=[^ ]+ -->$/) {
    split(substr($0, 6, length($0) - 9), f, " ")
    sub(/^id=/, "", f[2]); sub(/^last-at=/, "", f[3]); sub(/^disposition=/, "", f[4])
    seen[f[2]] = f[3] " " f[4]
  }
  END { for (id in seen) print id, seen[id] }' "$REC" | sort
```

Each line is `<thread-id> <last-at> <disposition>` for the latest round that
recorded that thread. An item whose `id` appears with the same `last_at`, and
whose disposition is not `open`, is **settled**. Show it with its earlier
disposition, and leave it out of the evidence check. An item that is new, or
whose `last_at` moved because someone replied, gets the full check. On a miss
the resolver says why (no sidecar, typically). Carry on without a prior round,
and Step 4 says what happens to the record.

For threads disposed **fix** in an earlier round, read what landed from the
tree, not from memory. `/fix-findings` ends each teammate-sourced fix commit
with a `Review-Thread: <url>` line:

```bash
SC="<this skill's directory>/references/sidecar.sh"
BASE_REF="$(bash "$SC" base-ref)" || { echo "base-ref failed: not guessing a base" >&2; exit 1; }
git log --format=commit.%H%n%B "$BASE_REF..HEAD" \
  | awk 'length($0) == 47 && /^commit\.[0-9a-f]+$/ { sha = substr($0, 8, 7) } /^Review-Thread: / { print sha, $2 }'
```

### Step 2. Check each claim in a fresh sub-agent

Spawn **one** read-only sub-agent on the cheaper tier (`model: "sonnet"`) for
every unsettled item. One for the batch, not one per thread: it gathers
evidence and decides nothing, and threads often refer to each other. A fixer
carrying one fix's reasoning into the next is the risk `/fix-findings` guards
against per finding. An evidence reader seeing two related comments together
is not that risk.

The context contract is `/pre-merge` Phase 3's (read it there, under *The
context contract is about provenance, not permission*), with this skill's
inputs:

- **Handed over:** the items' JSON exactly as Step 1 printed it, the PR diff
  (`gh pr diff <pr-number>`), and `references/comment-craft.md`, especially
  § *Receiving a review*.
- **Reached for itself:** the merged tree, `git log` and `git show`, tests and
  their output, installed types, `docs/solutions/`.
- **Withheld absolutely:** this session's reasoning about the code, and its
  opinion of the comments. That is the stake the sub-agent exists to remove.
  Do not summarize a comment for it. Hand it the comment.

It must not edit, stage, commit, or write anywhere, and it must not post to
the PR. It returns one row per item, in exactly one of these categories:

| Category | Means | Must carry |
|---|---|---|
| `supported` | the claim holds in the tree | the `file:line`, test, or command output that shows it |
| `refuted` | the tree contradicts the claim | the `file:line`, test, or command output that contradicts it |
| `preference` | no objective justification (5P *Ponder*) | what kind of justification would have made it a requirement |
| `out-of-scope` | valid, but not this PR's change (5P *Postpone*) | what the PR's change is, and where the concern lives instead |
| `discussion` | a question or remark with no claim to check | nothing; say what is being asked |

**Check its citations before presenting.** For every `supported` and
`refuted` row, confirm the cited path exists and the cited line range is
within the file. Re-label a row whose citation does not resolve as
`unverified — <the citation>`. A wrong `refuted` sends the author to push back
on a correct comment, and that costs more than any other error this step can
make.

When sub-agents are unavailable, run the check in-session and name it
**degraded mode** in the presentation. The evidence comes from the session
that wrote the code, so read every `refuted` with that in mind.

### Step 3. The human decides each thread

Present one table, settled items included:

| # | Where | Comment (first line) | Evidence | Earlier round |
|---|---|---|---|---|

Write the Evidence cell to the reader bar in `/pre-merge` Phase 4. Name the
thing in domain terms and lead with the claim. When one thread's choice forks
three or more ways with three or more attributes each, compare them first,
following `references/next-step-menu.md` § *Show the comparison before you
take the choice*.

Then ask **one** question: which threads to **fix**, **push back** on,
**postpone**, or **answer** yourself. Take the answer as typed, for example
`fix 1 3; push back 2; postpone 4; answer 5`. Repeat back any number given
twice or not at all. An item not named is recorded as `open`. Never assign it a
disposition.

| Disposition | What this skill does with it |
|---|---|
| **fix** | hands it to `/fix-findings` in Step 5 |
| **push back** | drafts a reply per `references/comment-craft.md` § *Receiving a review*: Triple-R, the evidence as Rationale, the tone rules, a signal prefix if the team uses them |
| **postpone** | drafts a follow-up issue body and a one-line reply saying it was split out. The human files the issue (`/qa` is the pack's intake for it) |
| **answer** | nothing unless asked. The human replies. If asked, draft from the evidence row |

**Reply drafts carry no pack vocabulary.** They are posted under the human's
name on a PR the team reads, and on a guest repo that PR is the client's. No
skill names, no `Fix-Findings-Run` or `Review-Thread` lines, no `W-` ids, no
"the evidence check found". Write as the author, citing code.

### Step 4. Write the record to the sidecar

The record is the author's durable, off-GitHub account of this review, for
coming back to it later. It lives in the project's sidecar, a private
local-only git repository outside the working tree, at the path `sidecar.sh`
computes, and it is committed there. Write it **before** Step 5: `/fix-findings`
ends in its own menu and nothing returns control here, and on a first round
its fallback source, this record, would not exist yet:

```bash
SC="<this skill's directory>/references/sidecar.sh"
REC="$(bash "$SC" path review-responses)/pr-<pr-number>.md" || exit 1
# Append this round to "$REC" (create it with the header on the first round).
bash "$SC" commit -- "$REC" -m "review-responses: PR <pr-number>, round <k>"
```

Append a round, and never rewrite an earlier one:

```markdown
# Review responses — PR <pr-number>

## Round <k> — <YYYY-MM-DD>, head <short-sha>

<!-- round: k=<k> head=<full-sha> evidence=<sub-agent|degraded> -->

### <n>. <path>:<line> (or: review summary, <state>) — <url>

<!-- thread: id=<thread-id> last-at=<last_at> disposition=<fix|push-back|postpone|answer|open> -->

> <each comment, verbatim, quoted, with its author and date>

- **Evidence:** <category> — <citation>
- **Disposition:** <disposition>
- **Reply draft:** <the draft, or "none">
- **Compound candidate:** <yes — what the pack's own review missed | no>
```

**Marker values are literal, with no angle brackets.** A `>` inside an HTML
comment ends the naive `<!-- … -->` read that Step 1's awk performs.
`/pre-merge`'s ledger learned that on its first test run. Thread ids, ISO
timestamps, and the five disposition words never contain one.

**A compound candidate** is a thread that is `supported` and marked **fix**.
A teammate found a real defect that the pack's own review let through, and that
escaped class is exactly what `/compound` captures. Mark it in the record and
name it in the handoff below. Do not run `/compound` from here.

**With no sidecar**, `path` fails and prints the resolver's reason. Print the
round to the terminal, say it was not persisted, and offer `/init-pipeline` to
create a sidecar. Never fall back to a file in the project's tree. On a guest
repo that file would land in the client's repository.

### Step 5. Hand the fixes to `/fix-findings`

If any thread is marked **fix**, invoke `/fix-findings` with exactly those
numbers. Hand it each item's JSON verbatim, which carries the comment bodies
and the thread URL, and the Step 2 evidence row beside it. The human's typed
disposition is the selection `/fix-findings` requires. This skill adds no
number to it, and drops none from it. `/fix-findings` takes it from there: a
fresh fixer per thread, which may still report `refuted`, a breaker, one
`Review-Thread: <url>` line per commit, and its own handoff to a `/pre-merge`
re-run.

If no thread is marked **fix**, skip this step.

## Handoff

- **Expected input:** an open PR on GitHub with a teammate's review, and the
  human who will decide each thread.
- **Produces:** an evidence row per unsettled thread, the human's disposition
  for each, reply drafts for pushback and postponed threads, a `/fix-findings`
  run on the threads marked **fix**, and a review-response round in the
  sidecar.
- **Comes next by default:** when threads went to `/fix-findings`, its own
  handoff (a `/pre-merge` re-run that reviews the fixes and re-stamps), then
  `/compound` when the record names a compound candidate, then `/closeout`
  once the PR is approved. With no fix threads: the human posts the replies,
  and `/closeout` once the PR is approved.

**Next-step menu.** When `/fix-findings` ran, its menu is the handoff, and
this skill adds none. Otherwise offer one `AskUserQuestion` (see
[references/next-step-menu.md](references/next-step-menu.md)), recommended
first: **→ Post the replies yourself, then `/closeout` once approved
(recommended)**, **Show the reply drafts again**, **Stop here — the record is
in the sidecar**. When the record names a compound candidate, add
**`/compound` the escaped defect first**. The platform's free-text "Other" is
the escape hatch. Do not add one.

Print the runtime handoff line:

```
**Next session:** /respond-to-review <pr-number>
**Input:** the teammate's next round on PR <pr-number> — the sidecar record carries the settled threads
```
