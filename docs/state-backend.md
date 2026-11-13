# State backend

Where the pack writes its own state for a project: to GitHub, or to the project's sidecar. One question decides it, and one command answers it:

```bash
bash "$SC" backend <prds|slices|stamp>   # prints github or sidecar
```

`$SC` is the skill's bundled `references/sidecar.sh`. A skill asks before it writes and follows the answer. It never reads `sidecar.json` to work the answer out itself.

## The routing rule

| Artifact | Goes to GitHub when `forge.write` contains | Otherwise |
|---|---|---|
| `prds`, `slices` | `issues` | sidecar |
| `stamp` | `prs` | sidecar |

`github` also needs `forge.kind` to be `github`. Every consumer of the `github` answer runs `gh`, and `forge.write` is derived from `mode` alone, so an owned GitLab or Bitbucket repo carries the full write list and would otherwise be routed to a CLI that cannot reach it.

**No sidecar means `github`.** That was the behavior before the sidecar existed, so a project that never ran `sidecar.sh init` sees no change. `backend` prints `github` and exits 0 on a `SIDECAR MISS`. Any other failure, such as running outside a repository or a `forge.write` that is not an array, exits nonzero rather than guessing. A corrupt or unreadable `sidecar.json`, a `sidecar.json` symlink whose target is gone, and a sidecar directory the scan cannot enter are such failures for any repo that no readable sidecar claims, since each might be that repo's own; a repo a readable sidecar does claim resolves, and the path is named on stderr. A sidecar root that exists but cannot be listed is always such a failure, because it hides every sidecar; only a root that does not exist is a miss.

**A caller branches on all three outcomes.** A nonzero exit prints nothing, so `if [ "$(backend)" = sidecar ]; then … else <gh> fi` reads a refusal as `github`, and the promise above never reaches the caller. Every call site is a `case` with a `github)` arm, a `sidecar)` arm, and a `*)` arm that aborts. `scripts/test-delta-review-scope.sh` and `scripts/test-review-currency-marker.sh` run each extracted block with a `backend` that refuses.

## What the write lists mean

`forge.write` and `tracker.write` list the kinds of **pack-authored content** the pack may put on that host: pack headings, `#N` references (a `Closes #N` or `Fixes #N` among them, which close the client's issue at merge), `W-` IDs, a review-stamp block. They do not say whether an ordinary PR may exist. A guest repo on GitHub with `forge.write = []` still gets a PR from `/pre-merge`. It gets a plain human description, and the pack's own record of the review lives in the sidecar, as the table below says. Because the stamp needs no PR, `/pre-merge` opens the PR for an unpushed branch after the review instead of before it (its Phase 2). Review fixes can then be folded into the commits they correct before anyone else reads the history. `scripts/test-guest-footprint.sh` runs `/pre-merge`'s PR creation and `/closeout`'s merge on a guest repo and fails on any pack marker they hand the forge.

## Commit messages

On the `sidecar` backend, a commit message names the change and its reason and nothing else. The branch's commits reach the host however it merges: as the PR's commit list, as merge-commit history, or before a fold if the branch was pushed first. So the rule that keeps pack text out of the PR body covers the commits too. A commit on such a branch carries none of these:

- a `fixup!`, `squash!`, or `amend!` subject, which must be folded before the PR opens
- a `Fix-Findings-Run:` or `Review-Thread:` line
- a `W-<n>` work item id
- a skill name written as `/<name>`

`bash "$SC" footprint <rev-range>` prints each one it finds with the commit's short SHA, and exits 1 if there are any, 0 if there are none, and 2 if it could not read the range. `/pre-merge` Phase 2 runs it over the branch's whole range, as `sidecar.sh range` prints it with no work item, before it opens the PR or prints the text for one, and stops on anything but 0. The matcher cannot tell a pack skill from a client's own text (a `/help` route, a `W-9` form), so `--accept "<short sha> ..."` skips the commits the operator names; `/pre-merge` offers it only after the operator confirms the line is the client's own. `scripts/test-guest-footprint.sh` runs that block against planted commits, and pins the skill-name list to the pack's skill directories.

On the `github` backend these lines are the pack's own repo convention and stay.

## Where the review's records live

`backend stamp` decides all four rows. A skill that reads or writes one of them looks it up here rather than assuming the PR.

| Record | `github` backend | `sidecar` backend |
|---|---|---|
| Review stamp | the PR body's `## Review Currency` block | `<sidecar>/reviews/<branch-slug>.json`, through `stamp` |
| PR lineage | the PR body's `## PRD` and `## Slices` sections | the work item's `parent`, `blocked_by`, and `pr` fields |
| `/execute`'s `## Review Notes` | a block in the PR body | the newest comment on the work item whose first line is `## Review Notes` |
| Loop-mode `## Review Disposition Ledger` | a block in the PR body | the newest comment on the work item whose first line is `## Review Disposition Ledger` |

On the `sidecar` backend with no work item (the operator answered "none"), the last three rows have no home. Notes and a ledger are printed to the terminal and named as not persisted, and are never written into the PR instead.

`/fix-findings` records each fix run the same way `backend stamp` routes the stamp. On `github`, each fix commit ends with a `Fix-Findings-Run: <run id>` line, plus a `Review-Thread: <url>` line for a teammate thread. On `sidecar`, the commit carries neither, and `sidecar.sh fixrun record <branch> <run id> <sha> [--thread <url>] [--work <W-n>]` writes one line to `<sidecar>/fix-runs/<branch-slug>.jsonl`. `fixrun list <branch> --range <rev-range>` reads back only records whose commit is in the range, so a fold that rewrites a SHA drops its record the way it drops a trailer. `/fix-findings` § Handoff counts rounds from it, and `/respond-to-review` finds earlier fixes with it. `--work` names the slice the fix belongs to, and `/fix-findings` passes it when it was handed one. The file is keyed by branch and several slices can share a branch, so a record without `--work` belongs to the branch and to no slice. `fixrun list` prints the same line with or without it.

`/respond-to-review`'s record is not in the table, because `backend stamp` does not decide it. It goes to `<sidecar>/review-responses/pr-<n>.md` on either backend, found through `sidecar.sh path review-responses` and committed with `sidecar.sh commit`. It is the author's private account of a teammate's review, never written to the PR, and its directory is separate from `reviews/` so it cannot collide with a stamp. With no sidecar it is printed to the terminal and named as not persisted.

`sidecar.sh init` derives `forge.write` from `mode` and the forge: owned on a known forge gets `["issues","labels","milestones","prs"]`, and everything else gets `[]`. `sidecar.sh config set mode` re-derives it. `tracker.write` is not read by `backend`.

## The review stamp

On the `sidecar` backend, `/pre-merge` Phase 4 records the reviewed head in `<sidecar>/reviews/<branch-slug>.json` instead of the PR body. `/pre-merge` Phase 1 step 4 and `/closeout` Step 2 read it back.

```bash
bash "$SC" stamp write <branch> <sha> [--base-ref <ref>]   # /pre-merge Phase 4 only
bash "$SC" stamp read <branch>                             # the 40-hex SHA, or nothing with exit 0
bash "$SC" stamp clear <branch>                            # /closeout, once the merge is verified
```

The file's shape is locked in the parent PRD, chrislacey89/skills#407, § Implementation Decisions, "Stamp". It is not restated here. Readers compare `stamp read`'s output with the branch head by string equality, the same rule as the PR-body marker. `read` prints nothing for a stamp it cannot trust: a file that does not parse, a `branch` field naming another branch, or a `reviewed_sha` that is not 40 lowercase hex. Each of those takes the reader's "no stamp" path rather than reporting a divergence that never happened.

`stamp clear` leaves no record of what was reviewed, so after a successful `stamp write` `/pre-merge` also copies the SHA to the work item's `reviewed_sha`, when there is a work item. The copy is the item's history. Review currency is still read from the stamp alone: no skill reads `reviewed_sha`, and `scripts/test-review-currency-marker.sh` fails when one does.

Every write commits inside the sidecar and never pushes. No verb writes to the project's tree or its `.git`.

## Work items

On the `sidecar` backend for `prds` or `slices`, a PRD or slice is a work item: a markdown file at `<sidecar>/work/W-<n>.md`, reached only through `sidecar.sh work`. Its frontmatter fields and body are locked in chrislacey89/skills#407, § Implementation Decisions, "Work item", and the fields added since are recorded in chrislacey89/skills#727, § Implementation Decisions. They are not restated here. A work item's id matches this regex, and no skill writes its own:

```
W-[0-9]+
```

An id is never a bare `#N`. A `#N` names a GitHub issue or PR, and on a guest repo that is the client's. Print and cite work items as `W-<n>`, for example `/prd-to-issues W-12`.

| Operation | `github` backend | `sidecar` backend |
|---|---|---|
| Create a PRD or slice | `gh issue create --body-file f` | `work create --kind prd\|slice --body-file f` (prints the id) |
| Attach a milestone | `--milestone "<name>"` on a milestone object | `--milestone "<name>"` on `work create`; a plain string, and no milestone object is created |
| Parent and blockers | sub-issue and `blockedBy` edges | `--parent W-n` and `--blocked-by W-n,...` on `work create` |
| Read | `gh issue view <n> --json …` | `work view W-n --json`: the frontmatter fields, plus `body` and `comments: [{at, body}]` |
| Replace the body | `gh issue edit <n> --body-file f` | `work edit W-n --body-file f` |
| Comment | `gh issue comment <n> --body-file f` | `work comment W-n --body-file f` |
| Record a decomposition | a `Decomposed into: #…` comment | `work set W-n decomposed_into W-2,W-3` |
| Maturity, state, PR, branch, reviewed SHA | labels, `gh issue close`, the PR body and its head branch | `work set W-n <maturity\|state\|pr\|branch\|reviewed_sha> <value>` |
| Close | `gh issue close <n>` | `work close W-n [--superseded-by W-m]` |
| List | `gh issue list …` | `work list [--kind] [--parent W-n] [--branch <name>] [--unblocked] [--state open\|closed\|all]` (ids, one per line; open by default) |

Three rules differ from the GitHub side:

- `work edit` refuses a body shorter than the one it read and leaves the file unchanged. Ticking a checkbox keeps the length the same, so a shorter body means something was dropped. That is the same guard the pipeline's PR-body and issue-body edits run by hand.
- `decomposed_into` is replaced on every `set`, never appended to, so a reader always sees the latest decomposition.
- `work comment` is the only writer of a `## Comment <ISO-8601>` section. A body that contains such a line is refused.

`work list --unblocked` prints items that are open and whose `blocked_by` ids are all closed. An id that does not exist counts as open.

A work item's `branch` is the branch it is being built on. `/execute` writes it when the slice starts and `/pre-merge` Phase 2 writes it again before the PR. `work list --branch <name>` prints the items on a branch, and it can print more than one: slices can share a long-lived branch, and a branch name is reused after a merge. A caller that needs one item checks that it got exactly one.

`sidecar.sh trace W-n [--json]` reads one work item's neighbors in both directions and writes nothing. It prints the items the item's fields name and the items that name it, the research file its body cites (a slice with none gets its parent PRD's), its `review-responses` record, and the dates of its newest `## Review Notes` and `## Review Disposition Ledger` comments. It also prints the item's branch, the head `/pre-merge` last stamped for it, and its fix runs: the records that name it with `--work`, and, listed apart as branch-level, the records on its branch that name no work item. A neighbor that is missing is printed as missing and does not fail the call. `sidecar.sh trace <lesson file>` does the same for a lesson's citations and needs no sidecar, so it works on either backend. `scripts/test-sidecar-trace.sh` pins the output, and reads the text it depends on from `/write-a-prd`'s and `/prd-to-issues`' templates.

## Branch slugs

A branch name is not a safe file name: `feat/x` has a separator, and a branch can carry any UTF-8. The slug keeps `a`–`z`, `0`–`9`, `.`, `_`, and `-`, and writes every other byte as `%XX` in uppercase hex. `feat/x` becomes `feat%2Fx`, and `Feat` becomes `%46eat`.

The slug is reversible, so two branches never share a file. Uppercase is encoded too, so `Feat/X` and `feat/x` stay apart on a case-insensitive filesystem. Readers still match on the JSON `branch` field, never on the filename.

`scripts/test-state-backend.sh` runs the routing truth table, the slug round trips, the `work` verbs, and `/execute`'s work-item gate and writeback against the real script, and reads the id regex out of this file.
