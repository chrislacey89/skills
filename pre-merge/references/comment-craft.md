# Comment Craft

Used by `/pre-merge` when running in reviewer-mode (`--pr <number>`). Author-mode `/pre-merge` produces terminal advisories on your own branch; reviewer-mode produces *PR comment text* on someone else's branch. Comment text is read by another developer in the heat of a review thread, so its craft matters separately from the architectural judgment carried by `review-checklist.md`.

This doc captures the convergent comment-craft methodology from three independent sources: Tacke (*Looks Good to Me*, 2024), Rigby et al. (*Convergent Contemporary Software Peer Review Practices*, 2013), and Cohen et al. (*Best Kept Secrets of Peer Code Review*, 2006). Where the books converge, the rule is treated as load-bearing. Where they diverge, the call-out is named.

## The Three-E Standard

Tacke's rubric for whether a review is functioning:

- **Effective** — catches what automation cannot: maintainability, architectural fit, domain convention, intent vs. implementation. The dimensions in `review-checklist.md` cover this axis.
- **Empathetic** — feedback targets the artifact, not the author. Reviews that feel like personal attacks discourage future participation and corrupt the process into theatrical agreement.
- **Effortless** — automation and structure remove mechanical friction (formatting, lint, test pass) before human attention. Reviewer attention is finite; spending it on the computable leaves less for judgment work only humans can do.

`/pre-merge`'s architectural dimensions handle Effective. Pre-commit hooks and CI handle Effortless. **Comment craft is what fills the Empathetic axis.** The rest of this doc is how.

## The 5P pre-comment gate

Before writing any comment, run it through 5P. Skipping this step is how reviewers leak preference-as-requirement into PR threads.

1. **Pause** — do not start typing. Read the hunk one more time.
2. **Ponder** — can you state an objective justification (a fact, convention, principle, prior PR, or measurement)? Or is this a personal preference?
3. **Pass** — if you cannot justify the comment to yourself in one sentence, do not post it. The 5P "Pass" path is the cost of passing through the gate; most preference-as-requirement comments fail here.
4. **Propose** — objective justification exists *and* the concern is in scope for this PR → write the comment using Triple-R.
5. **Postpone** — objective justification exists *but* the concern is out of scope → file a follow-up issue or add to the team backlog. Do not post in this PR.

The Postpone path is the pressure valve for review creep. Without it, reviewers inject scope because they have nowhere else to put the idea. Use it generously.

## Triple-R for action-requiring comments

Every comment that requests a change should carry three properties:

1. **Request** — one sentence with a *transformation verb* stating what to do. Tacke cites research showing transformation verbs (rename, remove, consolidate, expand, fix, rewrite, move, extract, inline) are statistically more prevalent in comments rated as useful; non-state-change verbs dominate nonuseful comments.
2. **Rationale** — one to two sentences of objective justification. Cite the principle, the prior PR, the convention, or the measurement.
3. **Result** — the measurable end state. What the code looks like after, or the metric that should hit. The author should know when the comment is satisfied.

Without Result, comments produce follow-up exchange after follow-up exchange because neither side knows when it is done.

**Example (Triple-R applied):**

> **Request** — Can we move `authenticateUser` into `lib/auth/`? \
> **Rationale** — Similar methods already live there; `pre-merge/review-checklist.md` Dimension 1 (Deep Modules) discourages export surface that grows without colocation, and PRs #134 and #147 set the precedent. \
> **Result** — `authenticateUser` is exported from `lib/auth/index.ts` and the call site here imports from there.

## Comment Signals — blocking semantics

Tacke's signal system for the author. Tacke explicitly recommends this *over* MoSCoW (Must/Should/Could/Would) because Must/Should and Could/Would boundaries blur in practice and produce meta-debates about category choice instead of code substance.

| Signal           | Blocking? | Meaning                          |
| ---------------- | --------- | -------------------------------- |
| `needs change:`  | Yes       | small fix                        |
| `needs rework:`  | Yes       | major refactor                   |
| `align:`         | Yes       | convention violation             |
| `levelup:`       | No        | encouraged for future PR         |
| `nitpick:`       | No        | purely subjective — never blocks |

Rules:

- **Every action-requiring comment carries a signal prefix.** Authors should not have to guess whether a comment blocks merge.
- **`nitpick:` never blocks a PR.** This is pre-agreed; do not debate it in the review.
- **`levelup:` is the natural pair to 5P-Postpone.** If the suggestion is valid but out of scope, prefer Postpone (file a follow-up); use `levelup:` when the suggestion is small and lives well as a non-blocking comment on this PR.

Map back to `review-checklist.md` severity tiers when transcribing terminal findings into PR comments:

- **Concern** → `needs change:` or `needs rework:`, depending on size; `align:` when the violation is convention-rooted
- **Suggestion** → `levelup:`
- **Observation** → either skip the comment entirely (no action implied) or post as `nitpick:` if it warrants noting

## Tone discipline — pronoun swaps and "ask, don't command"

Politeness in code review is not a cultural norm — it is backed by linguistic research. Tacke cites Ferreira et al.'s study on detecting interpersonal conflict in code review: the second-person pronoun "you" is statistically more likely to appear in toxic comments, especially sentence-initial. Technical terms ("test," "files," "pull request") are almost nonexistent in toxic comments.

Two operationalizations:

1. **Replace sentence-initial "you" with "we."** Shifts responsibility from individual to team and reinforces shared codebase ownership. "You should move the `Vehicle` class out of this file" → "Can we move the `Vehicle` class into its own module?"
2. **Ask, don't command.** "Can we consider…" rather than "Change this to…" The question form preserves specificity while removing the directive structure.

The structural commitment underneath both is **"You Are Not Your Code"**: code review feedback targets the artifact, never the author. The same concern can be delivered as direct (specific, objective, artifact-targeted) or blunt (personal, demoralizing, author-targeted) — the 5P gate filters for objectivity, the pronoun swap filters for tone, and both are required.

## MMG Exchange — when reviewer and author disagree

When both sides hold opposing "objective" positions, continuing to exchange comments in the PR produces a public argument with no resolution mechanism. Tacke's **Maintainable Middle Ground (MMG) Exchange** routes the dispute offline:

1. **Acknowledge tone.** Either side can call a pause if the thread is escalating.
2. **Understand each other's reasoning.** A short synchronous conversation (DM, call, or in-person) where each side states what they think the other is optimizing for. Often dissolves the disagreement entirely — the two sides were optimizing for different invariants and didn't know it.
3. **Find middle ground.** A solution both sides can defend, not a compromise that satisfies neither.
4. **Escalate to team if no middle ground exists.** A senior or domain owner adjudicates. The tiebreaker rule: **the solution most readable and maintainable to future developers wins**, not the solution either party prefers.

Skipping offline escalation stalls the PR indefinitely and damages the relationship for future reviews. The PR comment thread is not a dispute resolution channel; it is a public record of the resolution.

## Stance — collaborative problem-solving, not defect counting

Rigby's evidence (across Apache, Linux, AMD, and other large open-source and enterprise projects) is that the goal of review is **shippable code, not a defect tally**. AMD's defect-recording fields collapsed to ~87% zero-defect when the team's posture shifted from "find as many bugs as possible" to "two developers converging on a working change."

Three implications for `/pre-merge` reviewer-mode:

- **No defect counts in comments.** Do not include "found N issues" preambles. Surface the substantive findings.
- **Frame Concerns as collaborative resolution targets.** "We need to address X before merge" beats "this is broken." Both can be objective; only the first preserves the working relationship.
- **Cohen's Big Brother Effect — do not weaponize metrics.** If the project tracks review metrics (response time, comment count, defect classification), do not use those metrics to evaluate individuals. Tracking-as-pressure produces theatrical reviews and corrupts the data being collected.

## Author preparation — when reviewing your own author-mode work

This doc is reviewer-side, but Cohen's Author Preparation principle informs author-mode `/pre-merge` too: before requesting review, the author should annotate the diff (rationale, risky areas, deliberate non-changes) so the reviewer's first read is informed. Author-mode `/pre-merge`'s PR body template (see `SKILL.md`'s "PR body template" section, particularly the "plain-language walkthrough" requirement that defers to `references/writing-for-humans.md`) already operationalizes this — the walkthrough *is* the author preparation.

## Quick reference — the comment loop

```
Spot something in the diff
    │
    ▼
5P gate ──► Pass (do not post)
    │
    ├──► Postpone (file follow-up issue)
    │
    └──► Propose
            │
            ▼
       Triple-R draft
       (Request + Rationale + Result)
            │
            ▼
       Add Comment Signal prefix
       (needs change: | needs rework: | align: | levelup: | nitpick:)
            │
            ▼
       Tone pass
       ("you" → "we", command → ask)
            │
            ▼
       Post comment

Disagreement? → MMG Exchange (offline) → record outcome in PR
```

## Sources

- Tacke, *Looks Good to Me* (Manning, 2024) — Three-E Standard, 5P, Triple-R, Comment Signals, MMG Exchange, pronoun research, "You Are Not Your Code." Primary source for this doc.
- Rigby & Bird, *Convergent Contemporary Software Peer Review Practices* (FSE, 2013) — collaborative problem-solving stance over defect tally; AMD's zero-defect collapse evidence.
- Cohen, Teleki, Brown, *Best Kept Secrets of Peer Code Review* (SmartBear, 2006) — Author Preparation, Big Brother Effect on metrics.

All three are loadable via `/library`.
