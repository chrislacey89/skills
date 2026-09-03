---
date: 2026-08-23
updated: 2026-09-03
category: testing-patterns
problem_type: a reviewer's own measuring instrument fails while reporting normally, so a false result is read as a finding about the subject
components: [scripts, lefthook, validate-skills, pre-merge, compound]
technologies: [bash, shellcheck, git, contract-tests, mutation-testing, ci, pipefail]
severity: high
volatility: evergreen
---

# Validate the instrument, not only the subject

## Problem

Across four review rounds on one PR, two agents hardened a contract suite against
its subject with mutation testing — and ran five unvalidated instruments between
them. Every one of the five failed while reporting normally. The instruments
failed at a higher rate than anything they were measuring.

## Context

PR #271 added a contract suite to `/tdd` and spent four review rounds on whether
that suite's assertions could actually fail. The discipline being applied was
sound and explicit: mutate the artifact, confirm the mutation landed, then
believe the result. Both reviewers repeated that rule to each other all session.

Neither applied it to the thing performing the measurement.

## Symptoms

A finding that is confidently reported and turns out to describe the harness:

- A mutation "applied" with no observable effect — reported as *the check tolerates this*
- A file read that returns clean — because the read was truncated before the defect
- A suite that goes red in a scratch tree — because the scratch tree lacks a precondition the suite needs
- A linter reporting clean locally while the same linter reports a defect on CI
- A green local gate on a PR whose required check is red

## Root Cause

Five instances, five instruments, one shape:

| # | Instrument | How it failed | Reported as |
|---|---|---|---|
| 1 | `re.subn(..., count=1)` on a constant declared twice | Mutation hit the shadowed copy; the live one reset it | "the probe is blind to a widened window" |
| 2 | `sed -n '96p' \| cut -c1-200` on a 700-character line | The claim sat past the cut | "that stale promise is already gone" |
| 3 | `git archive \| tar -x` for a scratch tree | Produces no `.git`; two suites read git | "two suites are RED at this commit" |
| 4 | `sed` matching `too_far_fixture` when it meant `far_fixture` | Mangled the file into an exit 127 | (caught before reporting) |
| 5 | Local `shellcheck` 0.11.0 vs CI's 0.9.0 | SC2317's reachability analysis narrowed between releases | "shellcheck clean" — three times, while the PR's required check was red |
| 6 | `printf '%s' "$hay" \| grep -q "$needle"` under `pipefail`, on a 94 KB file (2026-08-28, PR #308) | `grep -q` exits at the first match; `printf` takes SIGPIPE mid-write; `pipefail` reports the *producer's* death as the pipeline's result | "needle absent" — for a needle the file contains |

**Instance 6 is the one that changes this entry's prescription**, and it took five
days to arrive. It is the same shape as instance 2 — a size-dependent instrument
losing content past a boundary and answering in the normal format — but with two
properties none of 1–5 had.

First, **it fails asymmetrically, and the silent direction is the dangerous one.**
A matcher built on this pipeline breaks in opposite ways depending on which
question it is asked:

```
assert_has   -> reports FAIL on a needle that IS present   (loud; someone investigates)
assert_lacks -> reports  ok  BECAUSE the needle was found  (silent; a ban passes vacuously)
```

A suite full of `assert_lacks` rows — which is what a *ban* on a phrase, an idiom,
or a restated claim is made of — goes green precisely when the thing it forbids is
present. Instance 2 lost a claim it was looking *for*; this one certifies the
absence of a thing that is *there*.

Second, **it is size-gated, so it is not introduced — it is grown into.** The
identical two-line matcher answered correctly against `docs/visual-rendering-core.md`
(27,888 characters) and wrongly against `docs/visual-recap-design.md` (93,559
characters) in
the same run. Nothing changed in the assertion. The file it scanned got bigger. So
review cannot catch it: the code was correct when written, correct when reviewed,
and became wrong later without being edited.

None of these is a mistake about the code. Each is a measuring device returning a
value the reader had no reason to distrust, because a broken instrument does not
announce itself — it produces output in the normal format.

Instance 5 is the sharpest because every layer worked. ShellCheck detected the
defect. A `# shellcheck disable=SC2329` directive suppressed the message it
happened to emit, and a *second* message (SC2317, the same defect one level in)
got through anyway. CI went red. The red sat on the PR through four rounds. Both
reviewers ran a local binary that disagreed with the gate and believed the local
one.

## Learning Level

- **Level:** Structure
- **Feedback loop or delay:** The missing feedback is that an instrument's
  failures are *indistinguishable in format* from its successes. A mutation that
  did not land and a check that tolerated the mutation produce the same suite
  output. A truncated read and a clean file produce the same empty grep. There is
  no signal to notice, so noticing depends entirely on the reviewer suspecting
  their own tooling — which nothing prompts, and which competence actively
  discourages.

## Rule Scope

This is the branch's own subject one level up. #268 is about a check whose
accepted input domain widened without its type recording it. An unvalidated
instrument is a check whose accepted input domain is *"whatever my harness
happened to produce,"* with nothing recording that either.

- **Applies when:** a result about an artifact is obtained through a
  reviewer-authored or reviewer-selected instrument that is not itself under
  test — an ad-hoc mutation script, a scratch-tree extraction, a `grep`/`sed`
  pipeline over prose, a locally installed version of a tool that also runs in
  CI. Sharpest when the instrument is *discarded after use*, so nothing in the
  repo can ever pin it.
- **Inverts or does not apply when:** the measuring path is itself a committed,
  mutation-tested artifact. A `scripts/test-*.sh` asserting a property of the
  repo IS pinnable, and the sibling entries below are how to pin it. Do not read
  this entry as an argument for a meta-suite over the review harness — a
  throwaway instrument cannot be committed without ceasing to be throwaway.
- **Sibling docs:** [mutate-the-oracle-not-only-the-subject-2026-08-19.md](mutate-the-oracle-not-only-the-subject-2026-08-19.md),
  [partial-oracle-selfcheck-2026-08-22.md](partial-oracle-selfcheck-2026-08-22.md),
  [mechanism-generality-lags-the-pattern-2026-08-23.md](mechanism-generality-lags-the-pattern-2026-08-23.md)

**Why this is not those three.** All three siblings are about the *artifact under
test* — a contract suite's oracle, its self-check's coverage, its detector's
generality. Each says *harden the check*. This entry is about the tooling the
reviewer holds while evaluating the check, which is not an artifact in this repo
at all and which no suite here can reach. Same family, different subject: those
three make a committed mechanism trustworthy; this one is about the uncommitted
path by which its trustworthiness was assessed.

## Solution

Three moves, in decreasing order of how much they buy.

**1. Assert the instrument's precondition, not just the mutation.** "Confirm the
mutation landed" is necessary and was not sufficient — instance 1 satisfied it in
form (a `subn` returned 1) and failed in fact. State what the instrument requires
and check that, too.

**Before:**
```python
s2, n = re.subn(r'DECL_WINDOW=\d+', 'DECL_WINDOW=9999', s, count=1)
assert n == 1, "did not land"          # true, and the value was still 6 at runtime
```

**After:**
```python
s2, n = re.subn(r'DECL_WINDOW=\d+', 'DECL_WINDOW=9999', s)   # ALL occurrences
assert n >= 1, "did not land"
# and: a constant matched more than once is itself the finding
if n > 1:
    print(f"NOTE: {n} declarations — the extra ones shadow each other")
```

**2. Prefer an instrument with fewer preconditions.** `git worktree add --detach`
gives a real repository; `git archive | tar -x` gives a directory that merely
looks like one. Instance 3 cost a near-miss false finding and would have cost a
wrong bug report.

**3. Read the gate, not a local stand-in for it.** When a tool runs both locally
and in CI, the local result is evidence about the local binary. That is the fix
this entry ships.

## Prevention

**Code-level:** `scripts/test-shellcheck-version-parity.sh` pins instance 5's
class — the only one of the five that is mechanizable here. `.shellcheck-version`
is the single source; the workflow derives its install from it and fails the job
if the runner disagrees; `scripts/check-shellcheck-version.sh` runs from lefthook
pre-commit and announces a local/gate mismatch at the moment someone would
otherwise trust a local green. The suite asserts both surfaces *derive* the
version rather than restating it, and probes the warner in both directions so its
failure branch is reachable.

`scripts/test-pipefail-safe-matchers.sh` pins instance 6's class. It bans
`producer | grep -q` in every committed `scripts/*.sh`, and — because a sweep that
swaps one unsafe idiom for another is its own defect class
(`sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md`) — it also
*proves the replacements*, running both `<<<"$var"` and `< <(producer)` against a
200 KB haystack with a front-loaded needle, plus a negative control that
demonstrates the banned form still misreports on the same input. All 33 existing
pipelines across 15 suites were converted in the same commit; a detector that
cannot go green is a detector nobody keeps.

**The original version of this section said the other four "are not mechanizable
in this repo," on the ground that instruments 1–4 "were ad-hoc, authored
in-session, and discarded. Nothing in a repository can assert a property of a
script that was never written to it." Instance 6 falsified the premise, not the
logic.** The reasoning is still right — you genuinely cannot assert a property of
a script nobody committed — but it silently generalized from *the instruments this
entry happened to collect* to *instruments as a class*. The next instance was a
committed suite, and every other suite of that shape was sitting in the repo the
whole time, waiting for a scanned file to cross the pipe buffer. Written as a
scope rule: **an instrument is mechanizable exactly when it is committed**, and
five ad-hoc instruments in a row is a fact about one PR's working style, not
evidence about where instruments live.

**Two things the mechanism caught that the census had not.** First, the detector's
own first regex required a single literal `-` before the flag cluster, so
`grep --quiet` reproduced the bug and the detector reported clean against a repo
containing it — a guardrail a rename walks straight past, which is this entry's
own pattern one level down. It now matches every spelling grep accepts, and the
five spellings are planted into a scratch file and re-detected on every run
rather than asserted in a comment. Second, the sweep went stale before it
landed. PR #313 converted the sites present on 2026-08-28 and then sat behind a
moving `prod`; regenerating it on 2026-09-03 found **eight sites that had not
existed when the census was taken** — five pipelines arriving with #256's
guardrail parser (four in `test-documented-git-commands.sh`, one in the wholly
new `test-git-guardrails.sh`) and three captures arriving with #320's decision
card (`test-decision-card-grounding.sh`). None was a regression; each was
written correctly by its own lights, in the idiom the repo still showed. A
census is a measurement of one moment, and the moment had passed before the
census could merge. The detector is what makes it hold.

**The sibling shape is now mechanized too, and it fails in the opposite
direction.** `var="$(producer | head -1 | cut …)"` under `set -e` + `pipefail`
aborts the script at the assignment the instant the producer finds nothing —
and every one of the nineteen sites found was followed by a hand-written
empty-check (`FAIL Step 1 instruction not found`, `FATAL: no loop-pass marker
template found`) written for exactly that case and unreachable when it happens.
CI still reddens; the crafted reason never prints. `|| true` is the guard,
because the next line already decides what empty means.

Instances 1–4 remain prose, now for the narrower and checkable reason: those four
scripts were never written to the repo. Instance 2's truncating-read shape
(`sed -n 'Np' | cut -c1-200`) stays prose even where it *is* committed — "this cut
is too narrow for its input" is not decidable from the text, and
`test-pipefail-safe-matchers.sh` says so in its header rather than implying it
covers the family (`mechanism-generality-lags-the-pattern-2026-08-23.md`).

**Process-level:** when an entry declines a mechanism, it must name the property
that makes the case unmechanizable — not the sample it was drawn from. "These
instruments were ad-hoc" is a description of five data points; "an instrument is
mechanizable when it is committed" is a rule the next instance can be tested
against, and this one would have been.

`/pre-merge` findings that rest on a reviewer-authored
instrument should say which instrument produced them, so a reader can distrust
the harness and not only the claim. Before reporting a suite as clean or a check
as tolerant, check the PR's actual checks — `gh pr checks <n>` — rather than a
local re-run.

## Planning / Calibration Notes

- **What widened the work:** four review rounds on one PR, three of which found
  defects the previous rounds missed, all in the same 460 lines of bash. Every
  round's findings were real; the rounds did not converge because each fix was
  authored by the agent whose instrument had just misreported.
- **What tightened the work:** independent sub-agent passes with no access to the
  authoring context. Both of this session's blind passes converged on the two
  worst findings, and both caught a claim the parent had gotten wrong from a
  truncated read.
- **Future planning adjustment:** when `/pre-merge` runs more than twice on one
  branch and keeps finding real defects in the same file, that is a signal about
  the *reviewing* loop, not only the code. Treat a third round as a prompt to
  question the harness.

## Defect Classification

**Origin phase:** Design error — the review procedure specified subject
validation and was silent on instrument validation.
**Fix type:** Correction for instance 5 (single-source pin plus an announced
mismatch) and instance 6 (`scripts/test-pipefail-safe-matchers.sh` plus the
repo-wide conversion it reports on). Prose for instances 1–4, with the narrowed
reason stated above.

## Related

- PR #271 — the branch this surfaced on
- #268 — the issue whose thesis this generalizes
- PR #308 / #307 — instance 6; the branch that reproduced it and fixed the two sites in its own scope
- PR #313 — the first repo-wide sweep, closed unmerged: two commits behind `prod` with conflicts in 21 files. Regenerated rather than rebased, which is how the eight post-census sites were found
- `mechanism-generality-lags-the-pattern-2026-08-23.md` — why the new suite states its reach instead of implying it covers instance 2's shape
- `sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` — why the suite proves its own replacements rather than trusting them
- `dead-guards-report-coverage-they-do-not-have-2026-08-27.md` — the sibling failure mode: a guard that cannot fire. Instance 6 is a matcher that fires the wrong way

## Shelf Life

Evergreen — no expiration condition. The specific tools change; a measuring
device that fails in the same output format as it succeeds does not.
