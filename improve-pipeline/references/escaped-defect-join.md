# Joining escaped defects to the PRs that shipped them

Every rework number this pipeline can measure from its own artifacts — review
rounds, fix-up commits, findings per pass — is a cost paid *inside* the
pipeline. None of them says what the cost buys. This file is the method for
measuring the other side of the ledger: **bugs filed after a merge, against the
code that merge shipped.**

It exists because the pack's improvement backlog is ranked by argument. A
proposal that removes a review pass and a proposal that adds one both sound
prudent, and nothing measured so far can tell them apart. An escaped-defect
rate can.

The method belongs here; the script does not. Run it in the repo being
measured, keep it under that repo's `scripts/`, and leave the pack holding the
definitions.

## The join

A bug counts against a merged PR when all three hold:

1. the bug was filed **after** the PR merged,
2. within a **window** (30 days by default), and
3. it **names a file the PR touched**.

That is a coincidence rule, not a causal one. A bug filed three weeks after a
PR that happened to touch the same file is not evidence that PR caused it. What
the join produces is a *rate*, comparable across PRs — never a verdict on any
one of them. Write that sentence into any report built from this method.

## Inputs

Two per repository, both from `gh`.

Merged PRs with their changed-file lists. `--slurp` wraps each page in an outer
array, so the result is a list of pages you flatten — see
[`gh api`](https://cli.github.com/manual/gh_api) for the pagination flags:

```
gh api --paginate --slurp "repos/<owner>/<repo>/pulls/<n>/files?per_page=100"
```

Bug-labeled issues with bodies and creation dates:

```
gh issue list --repo <owner>/<repo> --label bug --state all --limit 500 \
  --json number,title,body,createdAt,labels
```

Sanity-check the file lists against the API's own count before joining: the
number of filenames fetched for a PR must equal its `changedFiles`. A
short list means a page was dropped, and a dropped page silently *lowers* the
escape count — a failure that reads as good news.

## Extracting the files a bug names

This is the step that decides the result, and the step where a naive regex
quietly ruins it. Bug bodies in this pipeline are long and cite paths for
several different reasons: the defect's location, a prior `docs/solutions/`
lesson, a file explicitly ruled *out* of scope, a file the fix plan proposes to
create. Only the first is a defect site.

Three rules, in increasing recall and decreasing precision:

- **`line`** — only paths carrying a `file.ext:123` suffix. Highest precision,
  and the form the issue template encourages.
- **`region`** — every path-shaped token, but only within sections that
  describe where the defect lives, plus never `docs/solutions/**`, which is
  cited as prior art and is never a defect site. The section set used here, and
  the preamble before the first header: `Problem`, `What happened`, `What's
  wrong`, `Symptom`, `Root Cause Analysis`, `Root cause`, `Cause`, `Structural
  Diagnosis`, `Where it lives today`, `Steps to reproduce`, `Reproduction`,
  `Blast radius`, `Evidence`, `Summary`, `What I expected`, `Seam note`. Derive
  it from the corpus you are measuring rather than copying this list — it was
  read off the headers these three repos actually use.
- **`loose`** — every path-shaped token anywhere in the body.

Resolve each extracted token against a **known-file set** — the union of every
file any merged PR touched and the repo's current tree — by exact path, unique
path-suffix, or unique basename. A token that resolves to nothing is dropped.
This is what keeps prose like `package.json` from matching when the body
mentions it only to exclude it, and it is cheap: two `gh` calls.

**Report all three rules.** The choice of rule is the largest researcher degree
of freedom in the method, so a result that survives only one of them is not a
result.

## What to compute per PR

- `bugs_after` — the join count.
- `changed_files` and `additions + deletions` — the exposure controls. A PR
  touching 27 files has roughly 27 times the chance of catching a citation as a
  one-file PR. **Any comparison that omits this is measuring size.**
- `fixup_share` — non-first commits whose subject reads as rework (`fix…`,
  `revert…`, `address…`, `correct…`, `review finding`, `pre-merge review`),
  over total commits.
- review rounds, *where a durable record exists*.

Then the one question: **does `bugs_after` fall as rework rises, once size is
held constant?**

Hold size constant by stratifying — terciles of `changed_files`, then compare
rework bands within each tercile — or by a rank-partial correlation. The raw
correlation is not interpretable, because rework and size are themselves
correlated.

## The 2026-09-03 run

Three repositories: `chrislacey89/fulcrum`, `NewEra-Alliances/matlock`,
`NewEra-Alliances/mimir`. 212 merged PRs with complete file lists, 117
bug-labeled issues.

**The answer is no.** Rework does not predict fewer escaped bugs.

Within each size tercile (fulcrum + matlock, `mimir` excluded for coverage
reasons below), bugs filed per PR in the 30 days after merge:

| size tercile | no fix-ups | 1–25% fix-ups | >25% fix-ups |
|---|---|---|---|
| small (1–4 files) | 0.11 (n=64) | — | 0.00 (n=4) |
| mid (4–9 files) | 0.39 (n=44) | 0.29 (n=7) | 0.29 (n=17) |
| large (9–481 files) | 0.50 (n=36) | 1.61 (n=18) | 0.88 (n=16) |

Small and mid are flat. Large runs the *wrong* way: the PRs that took the most
in-pipeline rework escaped the most bugs afterward.

The rank correlations say the same thing. Across all nine combinations of the
three extraction rules and three windows (7 / 30 / 90 days), the raw
`rho(fixup_share, bugs_after)` is positive in every one (+0.08 to +0.25) and the
partial controlling `changed_files` collapses to noise (−0.07 to +0.13). No
setting produces the negative correlation that "rework buys fewer escapes"
predicts. What does predict escapes is size: `rho(changed_files, bugs_after) =
+0.36`, `rho(churn, bugs_after) = +0.33`.

Baseline for later comparison: **24% of merged PRs (50 / 212) had at least one
bug filed within 30 days against a file they touched.** Median time from merge
to the bug report was 8 days; 16% arrived within 24 hours.

### What this does and does not settle

It does not vindicate cutting review. A null result on an instrument this
coarse is consistent with rework being effective and with rework being
ceremony; what it rules out is *citing in-pipeline rework as evidence of
quality*, which several open proposals do.

It does rank one thing decisively. Size is the only variable here with a clear
relationship to escaped defects, so proposals that shrink slices have an
outcome measure behind them and proposals that re-tune review passes do not.

### Coverage, which is the real limit

Only 28 of 117 bugs joined to any PR. The losses, in order:

- **50 of 117 name a file that resolves at all.** The rest describe the defect
  in behavioral terms with no path. A bug that names no file cannot be joined
  by any version of this method. This is not an authoring lapse — it is the
  pack working as designed. `/qa` instructs the issue to "NOT reference
  specific files, line numbers, or internal implementation details"
  (`qa/SKILL.md:58`), and states the rule outright: "**No file paths or line
  numbers** — these go stale" (`qa/SKILL.md:244`). `/triage-issue` repeats it:
  "Do NOT include specific file paths, line numbers, or implementation details"
  (`triage-issue/SKILL.md:202`). The reasoning is sound and unrelated to this
  measurement: a bug written in domain language survives a refactor, and one
  written in `file:line` does not.
- **`mimir` is unjoinable.** It has 6 merged PRs against 46 bug issues — the
  work did not land through pull requests, so there is nothing to join to. Its
  one hit is not a sample.
- **Review rounds are not recorded anywhere durable.** Five of 212 PRs carry a
  comment identifiable as a review round. The round counts quoted elsewhere in
  the 2026-09-02 audit were reconstructed, and the reconstruction was
  contaminated; this run did not repeat it. `fixup_share` is the only rework
  instrument the artifacts actually support.

The first and third are both pack-level, and they are the same shape: the
pipeline does not write down the two fields its own outcome measurement would
need. For review rounds nothing records the count at all. For defect sites the
pack records the opposite on purpose. Until one of those changes, "how much did
review cost this PR" is a heuristic over commit subjects, and "what did it buy"
is answerable for a quarter of the bug corpus.

## Re-running it

Raise the coverage before re-running, or the next run answers the same question
with the same 28 bugs. Two changes would do it, in this order:

1. Get review-round counts recorded on the PR at merge time, so rework has a
   real instrument rather than a commit-subject proxy.
2. Decide what to do about the defect-site field, which is a design question
   and not a hygiene one. 57% of bugs (67 of 117) name no path that resolves,
   and 69% name no `file:line` — and that is what `/qa` and `/triage-issue`
   *tell* authors to do. The remaining 43% are the rule being broken, which is
   the only reason this join runs at all.

   Two ways out, and they are not equivalent. Loosening the prose rule trades
   away the refactor-proof issue the rule was written to protect. The other is
   to keep the prose exactly as it is and add the defect site as a separate
   machine-readable field — a trailer, a label, a fenced block the reader is
   not asked to read — so the human-facing issue stays refactor-proof and the
   join gets a key. That is a pack change, and it is the one this measurement
   argues for; the prose rule should not be relaxed to buy a metric.
