---
name: fix-findings
description: "Invoked helper skill for fixing the /pre-merge findings a human has already chosen, with a fresh sub-agent writing each fix and a second fresh sub-agent trying to break it. User-invoked only — type /fix-findings <numbers> after picking findings from a review. Not for choosing which findings to act on, not for stamping review currency, and not for merging."
disable-model-invocation: true
sources:
  primary:
    - "Engineering a Safer World — Nancy Leveson"
  secondary:
    - "Best Kept Secrets of Peer Code Review — Jason Cohen"
    - "Introduction to Software Testing — Ammann & Offutt"
    - "Thinking in Systems — Donella Meadows"
    - "The Design of Everyday Things — Don Norman"
---

# Fix Findings

!`PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" && mkdir -p "$PROJECT_DIR/.claude" && touch "$PROJECT_DIR/.claude/.fix-findings-active" && echo "fix-findings marker created at $PROJECT_DIR/.claude/.fix-findings-active — post-review edit lock open for this run"`

Take the review findings a human has already chosen, have a **fresh** sub-agent
write each fix, have a **second** fresh sub-agent try to break it, and report
both back. Hand off to a `/pre-merge` re-run, which is the only thing that
re-stamps.

## Why this skill exists

`/pre-merge` delegates the review to a sub-agent that did not write the code,
because the session that wrote it has already demonstrated it cannot see these
particular defects. Then the human picks findings, and the pipeline hands the
*fix* back to that same blind session. The responsive commit is the most
defect-dense code on the branch and the one commit with no independent reader.

Cohen's rule is that an author's job is to *annotate for* a reviewer, not to be
one. This skill applies it one link later: the fix's author must not be its only
reader. Leveson's is that a controller may not treat "sent" as "executed" without
feedback — a fixer's own green test run is exactly that unearned inference, which
is why a second agent attacks the fix rather than the fixer re-checking it.

## Invocation Position

**Invoked helper, and user-invoked only.** It fires when a human types
`/fix-findings <numbers>`; it never self-triggers. `disable-model-invocation:
true` is what enforces that, and it is the reason this skill costs nothing in a
downstream session's context window until it is actually wanted (`CLAUDE.md`
§ *Invocation mechanics*). If a future install strips that key the skill becomes
model-invocable — a context cost, not a correctness failure; nothing below
depends on the key being honored.

Enter it from `/pre-merge` Phase 4's next-step menu — the option **Fix a finding
on this branch first** — or by typing it directly after reading a review.

Do **not** enter it to decide what to fix, to review a diff (that is
`/pre-merge`), to merge (that is `/closeout`), or on an AFK run — there is no
human to dispose of findings, so there is no valid input.

## What this skill is NOT

- **It does not select findings.** The human's numbers are its only input. It
  never ranks, filters, batches, defers, or drops a finding, and it never adds
  one it noticed on the way. #190 draws that line deliberately: disposition is
  the human's. If a finding you were handed looks wrong, the fixer reports it
  **refuted** with evidence and stops — it does not decide the finding away.
- **It does not stamp.** `/pre-merge` is the only writer of the
  `<!-- reviewed-at: … -->` marker, and this skill's commits deliberately move
  the head *past* the stamp. That divergence is the mechanism working, and the
  handoff below is what closes it. `scripts/test-review-currency-marker.sh` pins
  the single-writer rule.
- **It does not merge**, open PRs, or edit PR bodies.
- **It does not re-fix.** One fixer pass and one breaker pass per finding, then
  stop. A surviving mutation is reported to the human, never fed back to the
  fixer. If the human wants another round they invoke `/fix-findings` again.
- **It does not review the branch.** It touches only what the chosen findings
  name. The `/pre-merge` re-run is the review.

## Inputs

- **The finding numbers**, as typed: `/fix-findings 1 3 4`.
- **The findings themselves.** In author-mode they are terminal output from the
  `/pre-merge` run still in this session. If that session is gone, read the
  `## Review Disposition Ledger` on the PR, which loop-mode wrote for exactly
  this case. If neither is available, stop and say so — do not reconstruct a
  finding from memory and fix your reconstruction.
- **A branch with a `/pre-merge` review behind it.** Working tree clean.

If a number the human gave does not correspond to a finding, say which numbers
exist and stop. Do not guess at intent, and do not silently fix the neighbors.

## Workflow

### Step 0. Preconditions

- [ ] `git status` is clean — uncommitted work would land inside a fix commit.
- [ ] The findings are in hand, by number, from one of the two sources above.
- [ ] `.claude/.fix-findings-active` exists (the harness line at the top of this
      file created it; see § *The two flags* for who reads it).
- [ ] The project's test command is known and currently green. If it is already
      red, say so and stop — a fixer cannot tell its own regression from the
      pre-existing failure, and a breaker cannot distinguish `killed` from
      "already broken."

### Step 1. Per finding, spawn a fresh fixer

**Spawn both sub-agents on the cheaper tier — `model: "sonnet"` on the `Agent` call.** What this skill buys is independence, not capability: the defect it exists to close is that the authoring session cannot see its own work, and a fresh Sonnet context removes that as completely as a fresh Opus one. Escalate to the session's own tier only on a signal — a fixer that returns `blocked`, or a finding that turns on a contract spanning several files. Per finding this skill spends two sub-agent runs, so the tier is where its cost actually lives. This is a default, not a rule anything enforces; issue #339 carries the hypothesis and the three signals that would refute it.

**One sub-agent per finding, never one for all of them.** A single fixer holding
every finding carries fix 1's reasoning into fix 2, which re-creates across
findings the correlated blindness this skill exists to remove. Per-finding
fixers are independent of each other as well as of the authoring session.

**What the fixer is handed, and what is withheld, is `/pre-merge` Phase 3's
contract, unchanged.** Read it there (`pre-merge/SKILL.md` § *The context
contract is about provenance, not permission*) rather than from a paraphrase
here; the same three parts apply:

- **Handed over** — the finding's text verbatim, the branch diff, this project's
  test command, and the PR body's `## Review Notes` block when one exists.
- **Reached for itself** — durable state, read at its source: the merged tree,
  `git log` and `git show`, the slice or PRD issue, `docs/solutions/`, the
  research artifact, installed types.
- **Withheld absolutely** — the authoring session's reasoning: why it wrote the
  code that way, what it considered and discarded, and any narration or summary
  of the finding standing in for the finding's own words.

The fixer's instructions, in order:

1. **Verify the finding against the tree first.** Reproduce the defect the
   finding describes — a failing case, a read of the code path, whatever the
   finding's own claim requires. If it cannot be reproduced, report
   **`refuted`** with the evidence and make **no commit**. A refuted finding is
   reported to the human, not argued into existence and not fixed anyway.
2. **Grep `docs/solutions/` for the class of thing you are about to write** — the same
   move `/execute` Step 1 makes before implementation — and read any entry that
   matches before touching the tree. The corpus is a list of shapes that have
   already failed here; on this skill's own PR, four fixers wrote grep-based
   assertions over prose eight days after an entry named that exact shape and
   said not to. A fixer that reads the entry first does not write the pin.
3. **Write the smallest fix that closes the finding**, following the project's
   conventions. Do not fix anything the finding does not name; scope creep in a
   post-review commit is invisible to the review that has already run.
4. **Run the project's test command** and report the exit status verbatim.
5. **Commit exactly one commit**, whose message says what the finding was and
   what the fix does. One commit per fix — a fix squashed together with another
   is a fix nobody can read separately.

The fixer reports back: `fixed` (with the commit SHA), or `refuted` (with
evidence), or `blocked` (with what it needed and did not have). Nothing else.

### Step 2. Spawn a fresh breaker against the fix

A second sub-agent, fresh, **read-only**, and working in a throwaway copy of the
tree. Spawn it on the same cheaper tier as the fixer, for the same reason and with the same escalation signal (Step 1). Its procedure is a checklist and its mutation is drawn from the corpus rather than composed, and the apparatus check gates the verdict — a breaker that cannot make its control go red reports `not-run` rather than false confidence. Neither sub-agent may drop below Sonnet: both read a real tree and run a real suite, and a breaker that misreports `killed` is worse than no breaker at all. It never edits the branch, never commits, never stamps, and never fixes
what it finds — #249 is the incident that rule comes from: a review sub-agent
mutated the tree it was reviewing. **It also never *reads* the original tree for
evidence about the fix** — not `git status`, not the working files, not for
orientation. Its subject is the extracted copy and nothing else for that
purpose; § *Cap* explains why that restriction is what makes a breaker safe to
overlap with the next fixer. That is narrower than "never touches the original
tree at all": the `git archive` extraction below has to run against it to stand
the copy up, and carrying dependencies into the copy — symlinking a read-only
dependency tree, copying `.env.local` and its siblings — is bringing over what
the test command needs, not gathering evidence about the fix, so neither is
banned by this sentence.

**Where the copy lives: `git archive`, not a second worktree — and it archives
the fix, not `HEAD`.** `FIX_SHA` below is the commit the fixer reported in Step
1, handed to the breaker along with the finding. It is not `HEAD`, because by
the time a breaker extracts, § *Cap* permits the next fixer to have already
committed — and a verdict about the accumulated branch is not the verdict
anybody asked for. The block does not bind `FIX_SHA` itself — export it before
running the block below: `export FIX_SHA=<the SHA the fixer reported>`.

```bash
# pipefail is load-bearing: without it the pipeline reports tar's status, and a
# `git archive` that resolved nothing exits 0 having extracted an empty tree.
set -o pipefail
BREAKER_DIR="$(mktemp -d)"
if ! git archive "$FIX_SHA" | tar -x -C "$BREAKER_DIR"; then
  rm -rf "$BREAKER_DIR"
  echo "breaker aborted: could not extract $FIX_SHA into a throwaway copy" >&2
  exit 1
fi
```

A `git worktree add` would register an entry in a git directory that other
sessions read and that survives a crashed breaker as a prunable stub — two
controllers over one stock, which is the coordination hazard Leveson names and
which is real here, because parallel-workspace hosts share one git directory
across sessions. `git archive` writes a plain directory with no `.git` inside it,
so "the breaker cannot write to the branch" is structural rather than promised.
Clean up with `rm -rf "$BREAKER_DIR"` when the breaker reports.

**The extraction fails closed, and the guard is not decoration.** An unguarded
`git archive <bad-rev> | tar -x` prints its `fatal:` to stderr and exits **0**,
leaving an empty directory behind — so a breaker that trusted the exit status
would run its mutation against no tree at all and could still report a verdict.
That is the exact failure this skill is built to refuse: a green result that is
green for a reason nobody checked. If the block aborts, the breaker reports
**`not-run`** with the abort message and no verdict.

The same guard covers the new way to get this wrong: a controller that forgot to
hand the breaker a SHA. An unset `FIX_SHA` expands to the empty string, `git
archive ""` rejects it as `fatal: not a valid object name`, and under `pipefail`
the pipeline exits 128 — so the missing SHA aborts the extraction rather than
producing a verdict about nothing. No separate check is needed for it, and one
should not be added on the assumption that unset behaves differently from
unresolvable here; it does not.

The cost is that the copy has no git history and none of the repo's ignored
files. Bring over what the test command needs — symlink a read-only dependency
tree, copy `.env.local` and its siblings — or run the project's install command
inside the copy. If neither is affordable here, the breaker reports **`not-run`**
with the reason. It does not report `survived` on a mutation it could not run.

**What the breaker does**, once per finding and then stop:

1. **Validate its own apparatus before anything else** — apply a known-killable
   control and confirm the named check goes red on it.
2. **Apply one corpus-drawn mutation at the point of consumption** of the
   property the fix claims to hold.
3. **Report one of four verdicts** — `killed`, `survived`, `not-run`, or
   `not-applicable` — naming the check, the command, and its exit status.

All three steps, the four verdicts, what a known-killable control is for a shell
or prose change, and why a green result is not self-validating are stated once in
[references/mutation-at-consumption.md](references/mutation-at-consumption.md).
Read it there; it is not restated here.

**The verdict is advisory.** `survived` is reported to the human as a line item
and to the `/pre-merge` re-run as evidence. It is never auto-re-fixed (that is
the re-fix loop #253 recorded), and it never earns or withholds a stamp — a
`survived` verdict that nothing executed reads identically to one that did,
which is why the apparatus check gates the verdict and why the verdict gates
nothing.

### Step 3. Report, then release the lock

Print one block per finding — number, the fixer's verdict and commit SHA, the
breaker's verdict **and the SHA it archived**, and the command behind each. No
conclusions the human cannot re-run.

```
Finding 3 — fixed at a1b2c3d
  fixer:   `pnpm run test` → 0
  breaker: survived, against a1b2c3d — `pnpm run test -- guards.test.ts` → 0 with
           OVER_FETCH_MULTIPLIER left at 4 and the use site edited to `topK * 137`
           (control went red first: same file, deleted assertion → exit 1)
```

The archived SHA is on the breaker's line because it is the one thing that says
what the verdict is *about*. With overlap permitted, a report that names only the
verdict leaves a `survived` attributable to whatever the branch had accumulated
by then — and a `survived` misattributed to the wrong fix sends the human back to
code that was never the subject. When the two SHAs match, as they do above, the
line is redundant and should still be printed: a reader cannot tell a match from
an omission.

Then remove `.claude/.fix-findings-active`, resolving it through the same
fallback the harness line above used, so the removal reaches the file that line
actually created:

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
if [ -e "$PROJECT_DIR/.claude/.fix-findings-active" ]; then
  rm "$PROJECT_DIR/.claude/.fix-findings-active"
  echo "fix-findings marker removed — post-review edit lock shut"
else
  echo "fix-findings marker NOT FOUND at $PROJECT_DIR/.claude/.fix-findings-active — the lock may still be standing open somewhere else; report this rather than assuming it is shut" >&2
fi
```

Remove it on every exit path, including an abort — a leaked flag leaves the
post-review edit lock silently open, which is the failure this whole mechanism
exists to close. **Report the not-found line if it prints.** `rm -f` would have
been shorter and would have reported success on a removal that removed nothing,
which is indistinguishable from the failure above; the branch is what makes a
miss sayable. All three sites — the harness line's `touch`, the hook's test, and
this `rm` — resolve `$CLAUDE_PROJECT_DIR` the same way for the same reason: a
flag written under `$PWD` in a subdirectory is a flag the hook never reads, so
the fixer would be refused by the lock written for it. Leave `.claude/.review-stamped` alone; `/closeout` removes it at
merge. The asymmetry is deliberate and is the fail-safe direction: a leaked
`.fix-findings-active` is an open lock nobody can see, while a leaked
`.review-stamped` is a closed lock that announces itself the moment someone tries
to edit.

## The two flags

Lock 1 is a writer, a refusing reader, and a lifecycle, on the same pattern as
`/tdd`'s `.claude/.tdd-active`. Both flags are transient by construction, which
is the condition under which this pack tolerates filesystem state at all. Every
row below names the step that reads the flag, because a flag no later step reads
is not load-bearing (#326).

| Flag | Written by | Read by | Removed by |
|---|---|---|---|
| `.claude/.review-stamped` | `/pre-merge` Phase 4, beside the review-currency stamp, under the same fallback | `.claude/hooks/enforce-classification.sh` — refuses Write/Edit on implementation files while it exists and `.fix-findings-active` does not | `/closeout` Step 3 at merge; `/execute` Step 0's fresh-slate checklist |
| `.claude/.fix-findings-active` | this skill, by the harness line at the top of this file, when it loads, under `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}` | the same hook clause, at `$CLAUDE_PROJECT_DIR/.claude/.fix-findings-active` — its presence is what re-opens the lock | Step 3 above, on every exit path, resolving the same fallback and reporting a miss rather than swallowing one; `/execute` Step 0's fresh-slate checklist |

**`.review-stamped` also stands the classification clause down, which is what lets this skill's fixer write at all.** The same hook carries an earlier clause refusing implementation writes unless `.claude/.tdd-active` or `.claude/.tdd-skipped` exists — and `/execute` Step 6 removes both of those *before* `/pre-merge` stamps, so no fixer ever arrives holding one. Were the two clauses genuinely independent in that order, the flag the harness line writes above would be read too late to matter: every fixer would be refused by the classification clause, under a message naming `/tdd`. So on a stamped branch the classification clause does not fire and this lock is the sole decider. Do not remove that coupling on the grounds that it looks like a leak between two unrelated gates — `scripts/test-post-review-edit-lock.sh` § 5 drives the real lifecycle, Step 6's removal included, and fails if it goes.

**Two routes the refusal names — which is not the same as two ways out.** The
refusal message names invoking this skill, and deleting `.claude/.review-stamped`
by hand. That second choice is made silently today, and the message is what makes
it visible (Norman — prospective memory fails silently, and "re-run the review
after fixing" is exactly the prospective act the field record shows being
skipped). Read that as a stop on the *default* post-review edit, not as an
enclosure: the hook is registered on `PreToolUse` `"matcher": "Write|Edit"` and
refuses only a path that matches `IMPL_PATTERNS` and survives the skip logic, so
several routes are already past it and leave no trace at all. Writing
`.claude/.fix-findings-active` opens the lock with no sub-agent behind it;
writing `.claude/hooks/enforce-classification.sh` rewrites the gate (`.sh` is not
an implementation pattern); writing `.claude/settings.json` deregisters it; and
no `Bash` write reaches this hook, `rm .claude/.review-stamped` included.
`scripts/test-post-review-edit-lock.sh` § 4 runs the three writes and records
their exit statuses, and reads the registration for the fourth, so the list is
measured rather than believed.

**What the lock does not cover, in the matcher's terms rather than a file's
role.** The hook reuses the classification gate's `IMPL_PATTERNS` list and its
`*test*` / `*spec*` / `*.d.ts` / `*.config.*` skip logic unchanged, and those
patterns match a *substring of the whole path*. Claude Code hands the hook an
absolute path, so the skips reach much further than "a test file, a type
declaration, a config file": `src/latest-news.ts` and `src/respectful.ts` are
skipped for containing `test` and `spec`, so is anything under a `testimonials/`
directory, so is `src/app.config.local.ts`, and so is every file in any repo
checked out beneath a path like `/Users/tester/`. Widening the patterns here
would make the two gates disagree about what "implementation file" means, so
they stay as they are and the consequence is stated: none of those edits is
refused after a review, and a `/pre-merge` re-run, not this hook, is what
covers them.

## Cap

**One fixer pass and one breaker pass per finding, then stop.** Stated here so it
is a property of the skill rather than a habit of the session. The fixer does not
respond to the breaker; the breaker does not re-run against a revised fix. If a
mutation survived and the human wants it addressed, that is a new invocation with
the human's decision behind it. Without the cap this is the fix-review-fix cycle
#253 recorded, with the loop half now also committing.

**Order and concurrency.** The cap says how many times each sub-agent runs; this
says in what order, because leaving that to the session is the same silence the
lock exists to close, one level down. Process the numbers in the order the human
typed them. **Fixers run one at a time, never in parallel** — each edits one
working tree and commits to one branch, so two at once is a race on both, and
"exactly one commit per fix" stops being something either can guarantee. Giving
each fixer its own worktree would trade that race for merge conflicts on exactly
the findings most likely to collide, since findings routinely land in one file
(three of five in one round of #338 landed in `/init-pipeline` § 2); at three to
eight findings that is not a trade worth making. **Breakers may run in parallel**
with each other, and a breaker may run while the next fixer works. The two
conditions that make that safe are stated in Step 2 and are deliberately not
restated here — the `$FIX_SHA` the extraction archives, and the restriction on
reading the original tree — because a rule written at two sites is a rule that
will later be changed at one. Neither is a tidiness rule. On #338 a breaker was
backgrounded while the next fixer was still committing, read the real repo, and
had to disclaim edits that were not its subject; nothing was corrupted, because
breakers write nothing, but the report was confused by state it had never been
told to stay out of. And the overlap is the only concurrency worth having here:
wall clock is dominated by the fixers, so a breaker that waits for them buys
nothing.

## Handoff

- **Expected input:** the finding numbers a human chose from a `/pre-merge`
  review, plus the findings themselves (terminal output or the PR's ledger), on a
  clean branch that has been reviewed.
- **Produces:** one commit per accepted finding, each authored by a context that
  did not write the code under repair; a per-finding breaker verdict, the SHA it
  archived, and the command behind it; and `refuted` reports for findings the
  tree did not confirm. It produces no stamp, no PR edit, and no merge.
- **Comes next by default:** a re-run of `/pre-merge` in author-mode, which
  re-runs the review dimensions and replaces the existing stamp. Hand it the
  breaker verdicts as evidence. There is nothing to hand it a *range*:
  author-mode reviews `git diff "$BASE_REF...HEAD"` — the whole branch — and
  `/pre-merge` defines no mode that takes a range or scopes itself to what is
  past the stamp (`pre-merge/SKILL.md` § *Modes*). These fix commits are covered
  because everything is, so no step has to work out where the stamp fell. Then
  `/compound` if a lesson emerged, then `/closeout`.

**Next-step menu.** This is a branch point, so offer it as a single
`AskUserQuestion` rather than leaving the user to retype a command (see
[references/next-step-menu.md](references/next-step-menu.md)), recommended option
first: **→ Re-run `/pre-merge` (recommended — review the fixes and re-stamp)**,
**Fix another finding — `/fix-findings <numbers>`**,
**Stop here — leave the fixes unreviewed on the branch**. Include a run-specific
follow-up when the breaker returned `survived` or `not-run`: **Show the surviving
mutation for finding N**. The platform's free-text "Other" option is the escape
hatch — don't add one.

Print the runtime handoff line either way:

```
**Next session:** /pre-merge
**Input:** branch <branch-name>, carrying the fix commits past the stamp — re-review and re-stamp
```
