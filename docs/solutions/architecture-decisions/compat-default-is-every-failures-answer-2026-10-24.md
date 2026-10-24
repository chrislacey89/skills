---
date: 2026-10-24
category: architecture-decisions
problem_type: a backward-compatible default for "nothing configured" is also the answer every failure to read the configuration produces, so a lookup that breaks re-enables the behavior the new mode exists to prevent
components: [init-pipeline/scripts/sidecar.sh, pre-merge, closeout, docs/state-backend.md]
technologies: [bash, jq, git]
severity: high
volatility: stable
---

# A compatibility default is every failure's answer

## Problem

`sidecar.sh backend stamp` answers `github` when no sidecar resolves, so that repos without a sidecar keep their old behavior. That same `github` is also what you get whenever the sidecar *cannot be read*. On a guest repo, `github` is the one answer that does harm: it writes pack text into a client's PR body. That is exactly what the sidecar backend exists to prevent.

## Context

PRD #407 adds a sidecar backend for repos where the pack may not write to GitHub. Its first invariant is "no sidecar resolved means `github`. That is today's behavior, so owned repos see no change." The tracer slice (#521, PR #529) implemented it faithfully. Review then found three separate sites where a *failed* lookup produces the same answer as an *absent* sidecar:

1. **No `jq`.** `owners_of` runs `jq -e … 2>/dev/null`. With `jq` off the PATH, no `sidecar.json` ever matches, `do_resolve` reports `SIDECAR MISS`, and `backend` prints `github` with exit 0. This was reproduced on a guest sidecar whose normal answer is `sidecar`.
2. **The miss branch.** `cmd_backend` turns any `SIDECAR MISS:` line into `github`. It can't tell "this repo has no sidecar" apart from "nothing could be matched".
3. **The call sites.** `/pre-merge` and `/closeout` branch with `if [ "$(bash "$SC" backend stamp)" = sidecar ]; then … else <gh path>`. A nonzero exit prints nothing, and nothing lands in `else`.

None of the three is wrong in isolation. Each is the obvious way to write its own line. Put together, they mean the doc's promise ("any other failure exits nonzero rather than guessing") holds only inside the one function that writes it.

## Symptoms

- A guest repo's PR body gains a `## Review Currency` block, or other pack text, with no error anywhere.
- `backend` prints the compatibility answer with exit 0 in an environment that is missing a dependency the script's header says it requires.
- Every test passes, because every test environment has the dependency.

## Root Cause

The default was chosen to answer *"is this repo configured?"*, and its direction was picked for the compatibility case (owned repos must not change). But a lookup has three outcomes, not two: **found**, **not found**, and **could not look**. "Could not look" was never given an answer of its own, so it shares the one assigned to "not found". In the guest case that is the unsafe answer.

The asymmetry is the trap. For owned repos a misroute to `github` costs nothing, because that was their behavior anyway. For guest repos, the population the feature exists for, the same misroute is the leak. A compatibility default fails safe for the old population and unsafe for the new one.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** none until a client sees the text. The failure is silent in both directions that matter. The script exits 0, tests run where `jq` is installed, and the misrouted write succeeds. The only observer is a guest repo's reviewer, outside the pack's feedback loop.

## Rule Scope

- **Applies when:** a new mode is detected by looking something up (a config file, a marker, an env var, a remote call), and the fallback when it isn't found is the *old* behavior, which the new mode exists to suppress for some population.
- **Inverts or does not apply when:** the fallback is the restrictive one. The git guardrail's "cannot resolve → allow the merge" (PRD #407 Rabbit Holes) deliberately fails open on a *check*. There, "could not look" sharing "not found"'s answer is the stated design, because a wrong refusal blocks work and a missed refusal is still caught by `/closeout`'s visible delta. The question is not whether to fail open. It is which population pays when the lookup breaks, and whether that population is the one the feature protects.
- **Sibling docs:** `testing-patterns/validate-the-instrument-not-only-the-subject-2026-08-23.md` is the reviewer-harness form, where an instrument fails while reporting normally. This entry is the shipped-code form, where the "normal" report is a routing decision.

## Solution

Give "could not look" its own exit at every layer, and make each consumer handle it:

- **Resolver:** before resolving, check every dependency the lookup needs (`command -v jq`), and refuse with exit 1 when one is missing, rather than letting the lookup "find nothing".
- **Verb:** translate only a genuine `SIDECAR MISS` into the default. Every other failure exits nonzero.
- **Call sites:** branch on all three outcomes, so a failure aborts instead of falling through.

```bash
case "$(bash "$SC" backend stamp)" in
  github)  … ;;
  sidecar) … ;;
  *) echo "stamp aborted: cannot decide the stamp backend" >&2; exit 1 ;;
esac
```

Then test the dependency-missing direction in an environment that really lacks it. A `PATH` built from symlinks without `jq` is enough.

At the time of writing these are review findings 1 and 5 on PR #529. They are not yet applied.

## Prevention

**Code-level:** `scripts/test-state-backend.sh` should get a no-`jq` arm asserting `backend` exits nonzero on a guest sidecar. The PR #529 call sites should move to the three-way `case` above. Until then, the doc's "exits nonzero rather than guessing" claim is true of `cmd_backend`'s own body and false of the system.

**Process-level:** the remaining #407 slices each add a consumer of `backend`: #522 (the guard), #523, #525, and #526. Each slice's boundary map should name the third outcome, and each consumer's contract test should include a "backend failed" arm. When shaping any feature whose invariant reads "absent means today's behavior", `/write-a-prd`'s Rabbit Holes should ask: *which population pays when the lookup itself breaks?* PRD #407 asked this for the guard and not for the stamp writer.

## Planning / Calibration Notes

- **What widened the work:** every SKILL.md block a contract suite extracts by a first-match anchor is a hidden consumer of that block's shape. Putting the backend question in front of `/pre-merge`'s stamp and scope blocks forced re-anchoring in three suites. One of them, `test-post-review-edit-lock.sh`, was not in the slice's Produces list. Before editing a fenced block, grep `scripts/` for the phrases near it.
- **What tightened the work:** running each extracted block in a fixture on both backends, with the `gh` stub armed to give a *different* answer, made any misrouting show up in the output rather than only in an argv log.
- **Future planning adjustment:** for each remaining #407 slice, list the suites that extract the blocks it edits (`test-git-guardrails.sh` for #522, `test-compound-restamp-handoff.sh` and `test-review-currency-marker.sh` for #526) as part of its Produces.

## Key Decision

**Decision:** keep "no sidecar → `github`" as the compatibility default, but stop letting it be the answer for anything except a genuine miss.
**Rationale:** owned repos must not change (PRD #407 No-gos), and a genuine miss is the only case where the default is known to be right.
**Alternatives considered:** defaulting to `sidecar` on any doubt. Rejected: on an owned repo with no sidecar, `stamp write` refuses, and the review would go unstamped where it used to be stamped.
**Revisable:** yes, if the pack ever requires a sidecar on every repo. Then a miss is itself an error, and the default disappears.

## Defect clustering

Nearest existing entries: `validate-the-instrument-not-only-the-subject` (an instrument failing while reporting normally). It is a different pattern: that entry is about a reviewer misreading its own harness, and this one is about shipped routing whose failure output coincides with a legitimate answer. `staleness-gate-intermediate-writers` is about writers between a stamp and its check, not about lookup failure. So this is the first recording, and no mechanism is mandated. The no-`jq` test arm above is still the right one to build.

A separate recurrence surfaced in the same review: `pre-merge/SKILL.md` Phase 4 passes `--base-ref "${BASE_REF:-}"` from a block that runs in its own shell, so the field is always empty (PR #529 finding 6). That is the pattern in `patterns/skill-command-blocks-run-one-shell-per-call-2026-10-13.md`, recurring in the same PR whose Key Decisions note says "because Phase 4 runs in its own shell". It is recorded here so the next compound on that pattern counts it.

## Related

- PRD #407, slice #521, PR #529 (review findings 1, 2, 5, and 6)
- `docs/state-backend.md`, which states the routing rule and the nonzero-exit promise

## Shelf Life

This entry can retire once `backend` and all of its call sites distinguish the three outcomes, each has a "lookup failed" test arm, and the remaining #407 slices have shipped against that contract.
