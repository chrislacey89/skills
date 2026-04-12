---
name: improve-pipeline
description: "Optional meta-skill for improving `chrislacey89/skills` from real-world friction or breakdowns discovered while using the pipeline in another repo. Use when the main lesson is about the pipeline itself, not the downstream project. Produces a GitHub issue in `chrislacey89/skills` and only moves to implementation after review."
sources:
  primary:
    - "Thinking in Systems — Donella Meadows"
  secondary:
    - "Thinking in Bets — Annie Duke"
    - "The Fifth Discipline — Peter Senge"
    - "Release It! — Michael Nygard"
---

# Improve Pipeline

Use this skill when real-world usage of the pipeline reveals a weakness in the pipeline itself. The triggering incident may happen in another repository, but the improvement target is always `chrislacey89/skills`: the skills, docs, checklists, and workflow guidance that shape future agentic development.

This is not automatic self-modification. Default output is a GitHub issue in `chrislacey89/skills`. The issue should explain what happened, why it is a pipeline problem rather than only a project problem, what change is recommended, what repo-wide effects the change could have, and which files in `chrislacey89/skills` would need to change if the recommendation is approved.

If the user asks for implementation after reviewing the proposal, implementation can follow as a separate step. Do not skip the proposal.

> **One question per turn.** If key facts are missing, ask one question at a time and wait for the user's answer before asking the next. Never turn incident intake or review into a questionnaire.

## Invocation Position

This is an optional meta-skill, not a default pipeline stage.

Use `/improve-pipeline` when the main lesson is about the pipeline itself:

- a skill boundary was unclear enough to cause rework
- a handoff artifact was missing, weak, or misleading
- a guardrail or checklist should have prevented an avoidable failure
- a repeated failure mode suggests the pipeline is under-specified
- a prompt, workflow, or repo convention encouraged overfitting or shallow review
- `/compound` or `/pre-merge` surfaced a lesson that belongs in the pipeline repo rather than in the downstream app repo

Do not use it when the lesson is primarily about the downstream repository:

- project-specific architecture decisions
- app-specific bug fixes
- library integration quirks that do not reveal a pipeline weakness
- reusable product or domain knowledge that belongs in that repo's `docs/solutions/`

`/compound` and `/pre-merge` may recommend `/improve-pipeline`, but only if the skill is present and the main lesson is clearly pipeline-level. Do not auto-invoke it.

## Why This Exists

A delivery pipeline that never learns from field use eventually optimizes for the imagined environment in its prompts rather than the real environment in which it operates. The most dangerous pipeline failures are not always obvious syntax mistakes — they are shallow boundaries, missing feedback loops, duplicated guidance, and workflow steps that look coherent in isolation but break down when run end-to-end.

This skill exists to close that loop deliberately. It converts a field incident into a repo-wide proposal rather than a local patch. Its job is not to defend the current pipeline or to change it impulsively. Its job is to understand what happened, test whether the proposed change generalizes, and produce the smallest coherent improvement that strengthens the whole repository.

## Execution Flow

### Phase 0: Confirm Target Repo and Load Canonical Context

The GitHub issue target is always `chrislacey89/skills`. Never infer a different target from the current workspace, the downstream project's git remote, or whichever repository the incident happened in.

Before analyzing the incident or filing anything, load the minimum canonical context for `chrislacey89/skills`:
- `README.md` — quick orientation to what this pack is
- `SYSTEM-OVERVIEW.md` — pipeline philosophy, state model, and handoffs
- `CLAUDE.md` — rules for editing this repo itself
- `docs/skill-anatomy.md` — the quality bar for skill changes

Then read:
- the skill most closely related to the incident
- adjacent skills with overlapping boundaries
- any shared checklist, template, or repo doc that encodes the same guidance

Build a short context snapshot before proceeding:
- what this repo is for
- where state lives in this workflow
- which repo areas are most likely affected by the proposed change
- what should remain stable if the change lands

Use explicit GitHub commands that pin the target repository:
```bash
gh repo view chrislacey89/skills
gh issue list -R chrislacey89/skills --limit 1
```

If you cannot confirm GitHub access to `chrislacey89/skills`, or cannot load enough of the canonical context to reason about the repository as a whole, stop and ask. Do not file against the downstream repo as a fallback.

### Phase 1: Capture the Field Incident

Start from the real incident, not from a preferred fix.

Capture:

1. **Where the incident happened** — repository, branch, feature, or phase of work
2. **Which pipeline path ran** — for example `/shape` → `/research` → `/write-a-prd` → `/execute` → `/pre-merge` → `/compound`
3. **What was expected** — what the pipeline should have enabled or prevented
4. **What actually happened** — confusion, rework, misclassification, missing artifact, weak review, contradictory guidance, etc.
5. **What downstream evidence exists** — PRs, issues, failed runs, repeated questions, or concrete examples

Build a concise run breakdown:

- which step introduced the problem
- which step failed to catch it
- which step amplified it
- what the real cost was: rework, bad guidance, scope drift, false confidence, missed edge case, or user confusion

Do not assume the nearest visible failure is the true pipeline cause. Separate the event from the structure producing it.

### Phase 2: Prove It Is a Pipeline Problem

Before proposing any repo change, test whether the incident truly belongs here.

Ask:

- Is this mainly a project-specific problem wearing pipeline clothes?
- Would improving the downstream repo alone solve it?
- Did the pipeline provide wrong guidance, missing guidance, weak sequencing, or no meaningful defense at all?
- Is this a one-off anomaly or part of a recurring pattern?

Classify the finding:

- **Local event** — belongs in the downstream repo, not here
- **Pipeline pattern** — this repo should change because the same class of issue is likely to recur
- **Pipeline structure** — the problem comes from a missing feedback loop, ambiguous ownership, overlapping skill boundaries, or contradictory repository guidance

If the issue is only a Local event, stop and redirect to the downstream repo's normal documentation or `/compound` flow.

### Phase 3: Expand Scope to the Whole Repository

Never evaluate a proposed pipeline change in isolation.

Before recommending edits, inspect the full repository surface area that could be affected:

- `SYSTEM-OVERVIEW.md`
- the skill that appears closest to the incident
- adjacent skills with overlapping responsibilities
- any checklists, docs, or templates that encode the same guidance elsewhere
- the README or other discovery docs if the change alters how users should find or invoke the workflow

Explicitly search for:

- duplicated guidance that would become inconsistent
- adjacent skills whose boundaries would shift if this change lands
- prompts or templates that would need synchronized updates
- repo-level terminology that the change would affect
- downstream consequences of making the pipeline more prescriptive, more complex, or more opinionated

A proposal that only improves one file but weakens repository coherence is not ready.

### Phase 4: Run the Three-Agent Dialectic

Use a structured tension pattern before writing the proposal. If sub-agents are available, use them. If not, simulate the three roles sequentially with clear separation.

#### Agent 1: Advocate

The Advocate makes the strongest good-faith case for the change.

The Advocate should answer:

- What pipeline problem is being solved?
- Why does the current repository fail to address it?
- What improvement would reduce future failures?
- Why is the proposed change better than leaving the pipeline alone?
- What exact files or skills likely need to change?

The Advocate should optimize for better real-world outcomes, not for defending current structure.

#### Agent 2: Skeptic

The Skeptic makes the strongest good-faith case against the change.

The Skeptic should look for:

- overfitting the pipeline to one incident
- duplication of guidance that already exists elsewhere
- boundary erosion between skills
- accidental complexity or extra ceremony
- recommendations that would burden ordinary users who are not trying to improve the pipeline
- evidence that the issue was downstream and not structural here

The Skeptic should assume the cost of a bad pipeline change compounds across future usage.

#### Agent 3: Mediator

The Mediator synthesizes the two positions and decides what best serves the whole repository.

The Mediator should produce one of four verdicts:

- **Reject** — not a pipeline problem or the proposed fix would harm coherence
- **Defer** — promising, but needs more evidence or wider repo review
- **Proceed narrowly** — make a small targeted change with limited blast radius
- **Proceed broadly** — a cross-repo update is warranted because multiple artifacts must stay in sync

The Mediator must name:

- the minimal coherent change set
- repo-wide risks
- what should explicitly remain unchanged
- what evidence would later justify revisiting the decision

### Phase 5: Search for Related Issues, Then File the GitHub Issue

Search for related issues in `chrislacey89/skills` before filing anything new.

```bash
gh issue list -R chrislacey89/skills --search "<keywords>" --state all
```

- Search open and closed issues using the pipeline area, skill names, and the clearest failure-mode keywords from the incident.
- If an existing issue already covers the same problem, update or comment on it instead of filing a duplicate.
- If an existing issue is related but distinct, file the new issue and cross-link both.

Only after the overlap check, file the proposal as a GitHub issue in `chrislacey89/skills`.

```bash
gh issue create -R chrislacey89/skills
```

Use a concise issue title that names the pipeline area and the improvement opportunity.

Suggested title convention:

`[improve-pipeline] <short summary of pipeline change>`

Example:

`[improve-pipeline] Clarify execute skill boundary for behavior-heavy frontend work`

Use this issue body template:

```markdown
**Target repo:** chrislacey89/skills
**Date:** YYYY-MM-DD
**Status:** proposed
**Triggering repo:** <repo-name>
**Triggering context:** <feature, issue, or branch>
**Pipeline area:** <skill, doc, checklist, or repo-wide>
**Change type:** prompt | workflow | checklist | artifact | terminology | boundary | other
**Confidence:** low | medium | high

## Field Incident

[What happened in the downstream repo. Keep this factual and concrete.]

## Pipeline Run Breakdown

- **Path run:** [/shape → /research → ...]
- **Expected behavior:** [What the pipeline should have enabled or prevented]
- **Actual behavior:** [What actually happened]
- **Introduced at:** [Where the weakness entered]
- **Missed by:** [Which step failed to catch it]
- **Cost:** [Rework, confusion, false confidence, missed edge case, etc.]

## Why This Is a Pipeline Problem

[Explain why this belongs in the pipeline repo rather than only in the downstream app repo.]

## Repo-Wide Context

[List the repository areas reviewed and what each implies for the proposal. Include the canonical docs plus the closest affected and adjacent skills.]

- `path/to/file` — [Why it matters]
- `path/to/other-file` — [Why it matters]

## Advocate Case

[The strongest argument for making the change.]

## Skeptic Case

[The strongest argument against making the change.]

## Mediator Verdict

**Verdict:** Reject / Defer / Proceed narrowly / Proceed broadly

[The synthesis. State the minimal coherent change set and the key repo-wide tradeoffs.]

## Recommended Changes

| Target file | Change | Why | Risk if skipped |
|-------------|--------|-----|-----------------|
| `path/to/file` | [Specific recommendation] | [Rationale] | [Consequence] |

## Non-Goals

[What this proposal intentionally does not change.]

## Follow-On Options

- **Proposal only:** stop here and review the issue
- **If approved:** implement the recommended file changes in a separate step in `chrislacey89/skills`

## Related Evidence

- [Link to issue, PR, transcript excerpt, or prior proposal]
```

Do not pad sections. If a section has no substance, tighten the proposal rather than writing filler.

If labels exist in the repository for maintenance or pipeline work, apply them. If they do not exist, do not block on label management.

### Phase 6: Review Before Any Implementation

Present the proposal and review it with the user one question at a time.

Minimum review sequence:

1. Is the incident framing accurate?
2. Is the Mediator verdict the right one?
3. Does the recommended change set respect repo-wide coherence?
4. Should this remain an issue for later triage, or do you want approved follow-on implementation now?

Do not begin editing pipeline files until the user has reviewed the proposal and explicitly asked for implementation.

### Phase 7: Optional Follow-On Implementation

Implementation is optional and never the default.

If the user approves implementation:

- update the minimal coherent set of files named in the proposal
- search for overlapping guidance before editing any central skill
- keep terminology aligned across touched artifacts
- prefer the smallest repository change that fixes the structural problem
- if the proposal affects invocation boundaries, update every relevant skill that encodes those boundaries

After implementation, report:

- what files changed
- what intentionally did not change
- what future incidents would validate or falsify the improvement

## Verification

A run of `/improve-pipeline` is not complete until all of the following are true:

- the target repo was explicitly treated as `chrislacey89/skills`
- the canonical context was loaded from `README.md`, `SYSTEM-OVERVIEW.md`, `CLAUDE.md`, and `docs/skill-anatomy.md`
- the nearest affected skill and adjacent overlapping skills were reviewed
- related issues in `chrislacey89/skills` were searched before filing or updating
- an issue was filed or updated in `chrislacey89/skills`, or filing was intentionally deferred with a stated reason

## Repo-Wide Guardrails

- **Proposal first.** Do not jump from incident to repo edits.
- **Do not overfit.** One painful incident is evidence, not proof.
- **Protect ordinary users.** Most pipeline users are trying to ship work, not evolve the pipeline.
- **Search before editing.** If a recommendation touches one skill, inspect adjacent skills and shared docs before changing anything.
- **Name the blast radius.** Every proposal should say which files, skills, or conventions are affected.
- **Prefer the smallest coherent fix.** Resist sprawling “while we are here” pipeline rewrites.
- **Keep project knowledge in the project.** If the lesson belongs in the downstream app repo, use that repo’s normal documentation flow instead.
- **Capture findings in GitHub.** The default artifact is a GitHub issue in `chrislacey89/skills`, not a local proposal file.
- **Do not trust the current workspace remote.** A downstream repo may be where the incident happened, but it is never the issue target for `/improve-pipeline`.
- **Require canonical context.** Do not file a pipeline-improvement issue until the core repo docs and overlapping skills have been reviewed.
- **If canonical context or GitHub access is unavailable, stop and ask.** Do not guess, and do not file elsewhere as a fallback.

## What This Skill Is Not

- **Not `/compound`.** `/compound` captures durable knowledge for the downstream project. `/improve-pipeline` captures improvements for this pipeline repo.
- **Not automatic self-healing.** It recommends and optionally implements reviewed changes; it does not silently modify the pipeline.
- **Not a blame exercise.** It analyzes structural causes and repo-wide implications, not who made the mistake.
- **Not a local patch machine.** It should not “fix” one skill without checking the coherence of the repository around it.

## Handoff

- **Expected input:** a real incident or repeated friction encountered while using the pipeline, often discovered during `/compound` or `/pre-merge`
- **Produces:** a GitHub issue in `chrislacey89/skills` capturing the improvement proposal and supporting analysis
- **May follow with:** approved implementation of the proposal in `chrislacey89/skills`
- **Should be recommended by:** `/compound` or `/pre-merge` when present and when the main lesson is pipeline-level
