# Differential check

This file is the canonical statement of the differential check. `/execute` Step 4
points at it for the author-time move, and `/tdd`'s partition step points at it
for the inputs. Neither restates it.

## When it applies

Only when the slice is meant to keep behavior the same: a refactor, a
performance change, a dependency swap. `/execute` Step 1 reads the slice that way
and says so in one line; the check fires on that line, and on nothing else. A
slice that adds or changes behavior skips it, and the skip is stated rather than
left silent.

A green suite does not settle a behavior-preserving change. It shows the new code
agrees with the old on the cases someone already wrote, and those cases come from
the old design's failure modes. A new mechanism brings new seams, and its new
failure modes are exactly the inputs no existing test builds.

## The check

Run the base version and the branch version on the same inputs, and compare
four things for each input: stdout, stderr, exit status, and side effects (the
files written or changed, and anything else the code touches that a later step
reads).

The inputs:

- the cases the suite already covers, which should agree trivially;
- **at least one input built to break the new mechanism**: ask what the new code
  does that the old did not (a cache, a batch, a shared handle, a reordered
  loop), and build the input that mechanism gets wrong;
- **when the change alters the unit of processing** (per item to batched, per
  request to pooled, per file to one call over all files), **one input that
  straddles two units**: a value split across two files, a record on the boundary
  of two batches.

A disagreement is one of two things, and the author says which: the bug, or a
behavior change the slice intends. An intended change is stated in the commit
message and the Step 6 review notes; it is never left for a reviewer to find.

## The base copy

The base version is the commit the slice started from: the work item's
`start_sha` when one is recorded, otherwise the merge-base of `HEAD` and the ref
`sidecar.sh base-ref` prints. Export it as `BASE_SHA` before running the block,
which extracts it into a throwaway directory. It uses the same `git archive`
form as `/fix-findings`' breaker copy, and for the same reason: a plain
directory with no `.git`, so no worktree is registered in a git directory other
sessions share.

```bash
# pipefail is load-bearing: without it the pipeline reports tar's status, and a
# `git archive` that resolved nothing exits 0 having extracted an empty tree.
set -o pipefail
BASE_DIR="$(mktemp -d)"
if ! git archive "$BASE_SHA" | tar -x -C "$BASE_DIR"; then
  rm -rf "$BASE_DIR"
  echo "differential check aborted: could not extract $BASE_SHA into a throwaway copy" >&2
  exit 1
fi
echo "base copy: $BASE_DIR"
```

Run each input once against `$BASE_DIR` and once against the working tree, each
from its own fresh scratch directory, so a side effect of one run cannot become
the other's input. Ignored files (`.env.local`, dependencies) are not in the
archive; copy or link what the code under test needs, as the breaker's copy
does. Remove `$BASE_DIR` when the comparison is done.

## How it differs from the mutation rung

The mutation rung (`mutation-at-consumption.md`) asks whether the checks can see
a change; this check asks whether the change is visible at all.
