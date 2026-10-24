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

`forge.write` and `tracker.write` list the kinds of **pack-authored content** the pack may put on that host: pack headings, `Closes #` lines, `W-` IDs, a review-stamp block. They do not say whether an ordinary PR may exist. A guest repo on GitHub with `forge.write = []` still gets a PR from `/pre-merge`. It gets a plain human description, and the pack's own record of the review lives in the sidecar.

`sidecar.sh init` derives `forge.write` from `mode` and the forge: owned on a known forge gets `["issues","labels","milestones","prs"]`, and everything else gets `[]`. `sidecar.sh config set mode` re-derives it. `tracker.write` is not read by `backend`.

## The review stamp

On the `sidecar` backend, `/pre-merge` Phase 4 records the reviewed head in `<sidecar>/reviews/<branch-slug>.json` instead of the PR body. `/pre-merge` Phase 1 step 4 and `/closeout` Step 2 read it back.

```bash
bash "$SC" stamp write <branch> <sha> [--base-ref <ref>]   # /pre-merge Phase 4 only
bash "$SC" stamp read <branch>                             # the 40-hex SHA, or nothing with exit 0
bash "$SC" stamp clear <branch>                            # /closeout, once the merge is verified
```

The file's shape is locked in the parent PRD, chrislacey89/skills#407, § Implementation Decisions, "Stamp". It is not restated here. Readers compare `stamp read`'s output with the branch head by string equality, the same rule as the PR-body marker. `read` prints nothing for a stamp it cannot trust: a file that does not parse, a `branch` field naming another branch, or a `reviewed_sha` that is not 40 lowercase hex. Each of those takes the reader's "no stamp" path rather than reporting a divergence that never happened.

Every verb commits inside the sidecar and never pushes. None of them writes to the project's tree or its `.git`.

## Branch slugs

A branch name is not a safe file name: `feat/x` has a separator, and a branch can carry any UTF-8. The slug keeps `a`–`z`, `0`–`9`, `.`, `_`, and `-`, and writes every other byte as `%XX` in uppercase hex. `feat/x` becomes `feat%2Fx`, and `Feat` becomes `%46eat`.

The slug is reversible, so two branches never share a file. Uppercase is encoded too, so `Feat/X` and `feat/x` stay apart on a case-insensitive filesystem. Readers still match on the JSON `branch` field, never on the filename.

`scripts/test-state-backend.sh` runs both the routing truth table and the slug round trips against the real script.
