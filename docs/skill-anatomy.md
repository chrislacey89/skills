# Skill Anatomy

This document defines the structure and quality bar for `SKILL.md` files in this repository.

The goal is consistency without flattening the repo's strongest ideas. Skills should be easy to trigger, easy to follow, and explicit about what they hand to the next skill.

## Frontmatter

Every skill must begin with YAML frontmatter:

```yaml
---
name: skill-name
description: "When to invoke this skill and when not to."
---
```

Optional provenance metadata is allowed when the skill makes substantive methodological claims:

```yaml
---
name: skill-name
description: "When to invoke this skill and when not to."
sources:
  primary:
    - "Book Title — Author"
  secondary:
    - "Book Title — Author"
  papers:
    - "Paper Title — Author"
---
```

`papers:` is optional and rarely needed. It is a *type marker*, not a third tier:
each entry must also appear under `primary:` or `secondary:`, and a check fails
if it does not. Use it only when a work is a paper rather than a book **and its
author field carries no citation convention to read** — no `et al.`, no trailing
`(Venue Year)`. Papers cited the normal way are detected without it. The landing
page renders papers as a different object than books, so the marker is what stops
a paper being shelved as a bound volume.

## Frontmatter rules

- `name` must match the directory name.
- `description` exists for discovery, not summary.
- `description` should answer three questions when possible:
  - when to invoke the skill
  - when not to invoke the skill
  - whether it is a direct-entry, delegated, side-route, or infrastructure skill
- Do not put process steps in `description`.
- `sources` should be used selectively. Only claim a source the body clearly operationalizes.
- Invocation mechanics are a **cost axis orthogonal to pipeline role**: a *model-invoked* skill's `description` rides in the context window every turn of every session (context load), while a *user-invoked* skill (`disable-model-invocation: true` in Claude Code) costs nothing until a human types `/name` (cognitive load). Which load a skill should spend informs whether it self-triggers and whether to split or merge it. The canonical treatment lives in `CLAUDE.md` § Invocation Roles; the standing per-skill audit — and the hard gate holding flag flips until CLI field-preservation and every auto-invoke chain are verified — is tracked in issue #157.

## Required sections

These sections are required for every skill unless there is a strong reason not to use the exact heading.

### `# Skill Title`

Use a human-readable title.

### `## Invocation Position`

This is the repo's replacement for a generic "When to Use" section.

It should state:
- where the skill normally sits in the workflow
- when to start with it
- when not to use it
- how it reconnects to the main pipeline if it is a side-route

### `## Process` or `## Workflow`

The main operating steps.

Requirements:
- Use numbered phases or clearly named stages when order matters.
- Be specific enough that an agent can follow the workflow without improvising the core behavior.
- Prefer concrete checks and examples over generic advice.
- If the skill branches, make the branch conditions explicit.

### `## Handoff`

Every skill must end with a handoff section.

At minimum, include:
- **Expected input**
- **Produces**
- **Comes next by default**

Include these when relevant:
- **May invoke**
- **Returns control to**
- **Feeds downstream**
- **May redirect**

## Strongly recommended sections

These sections should appear when they materially improve agent behavior.

### `## Overview`

Use when the skill benefits from a short explanation of why it exists before process details begin.

### `## Common Rationalizations`

Use when agents are likely to skip the workflow or rationalize shortcuts.

Format:

```markdown
## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Shortcut an agent might take" | Why that shortcut is wrong |
```

This section is especially valuable for:
- planning skills
- verification-heavy skills
- review skills
- any skill with a common failure mode of "I can skip this because it seems obvious"

### `## Red Flags`

Use when there are observable signs the skill is being violated.

Examples:
- prose drift instead of workflow execution
- writing code before shaping is complete
- changing unrelated files while implementing
- declaring work done without evidence

### `## Verification`

Use when the skill has meaningful exit criteria that should be checked explicitly.

Examples:
- artifact created and linked correctly
- tests or commands run
- issue or PR created
- diff reviewed against stated criteria

Not every skill needs a heavy verification checklist, but every skill should make "done" legible.

## Supporting files

Keep supporting material close to the skill when it is primarily for that skill.

Examples:
- `tdd/tests.md`
- `pre-merge/review-checklist.md`
- `improve-codebase-architecture/REFERENCE.md`

Move material into shared docs or references only when multiple skills actively use it.

## Writing principles

- Prefer process over prose.
- Keep trigger quality high — the first screen of the skill should help an agent decide whether it applies.
- Preserve repo-specific language like `Invocation Position` and `Handoff`.
- Use explicit cross-skill references in `/skill-name` form.
- Make branch conditions concrete.
- Avoid duplicating system-overview prose inside every skill.
- Keep utility skills lighter than core pipeline skills.
- Keep provenance asymmetric — core methodology-bearing skills can justify richer source metadata than narrow utility skills.

## Prose economy and steering

Structure keeps skills consistent; steering keeps them *effective*. Every sentence in a skill either changes what the model does or is dead weight it reads on every relevant turn. This section is the editing-time discipline for keeping skill prose load-bearing. It is a **per-sentence diagnostic, not a length target** — a long skill whose every line changes behavior is a deep module (Ousterhout), and cutting it to hit a line count deletes behavior. Apply these to prose you *changed*, not as a mandate to shorten skills that already work.

- **No-op test.** For each sentence you added or changed, ask whether the model already does this by default. If deleting the sentence would not change the model's behavior, delete it — do not trim it. Instructions the model already obeys spend context and dilute the ones that actually steer.
- **Prompt the positive, not the negative.** Naming a forbidden behavior makes it *more* available to the model, not less — the words are now in the window. Replace "do not do X" with a concrete statement of the behavior you want. Reserve explicit prohibitions for genuine, high-cost failure modes where positive framing alone is not enough.
- **Leading words.** Anchor behavior with pretrained concepts the model already carries — *seam*, *frontier*, *tracer bullet*, *deep module*, *sediment*. One right word invokes a whole schema in a few tokens; a paragraph explaining the same idea from scratch spends more and lands softer.
- **Checkable, exhaustive completion criteria.** Every step that produces or verifies something must end on a criterion the model can *check* — a file exists, a command exits 0, a grep returns zero matches, an issue is created — not a vague "done when it looks right." Where the check must cover a set (all consumer surfaces, all deleted exports), say the set is exhaustive so the model does not stop at the first hit.
- **Every field names its reader.** A field a skill writes into an issue or PR body — a section, a checklist, an HTML-comment stamp — names the later step that *branches on it or writes it back*, by skill and step: `/closeout` Step 2 refuses to merge past `/pre-merge`'s review-currency stamp; `/execute` Step 5 ticks the acceptance-criteria boxes `/prd-to-issues` wrote. Where no such step exists, the field is **informational** and says whose eyes it is for — a human reader is a reader, and `Blocked by` and `User Stories Addressed` are the worked examples. A field that is a **forcing function**, one a later step refuses to proceed without, also names its `scripts/test-*.sh` pin; that is `CLAUDE.md` § Commands a skill documents applied to the fields skills write for each other rather than to third-party tool claims. One question settles it: *what later step reads this, and what does it do when it does?* A valid answer names a step and the act it takes — *`/closeout` Step 2, refuses the merge* — or names the human audience. The `### Deletes` gate is the incident behind the rule (#326): it had readers that branched and no step that wrote it, so the rung it guarded waited on a field nothing produced.
- **Single source of truth per meaning.** Each concept lives in exactly one canonical place; other skills link to it rather than restating it. Two copies of a rule drift, and the drift stays silent until they contradict each other.

**Named failure modes to edit against:**

- **Sediment** — stale layers that settle because adding a sentence feels safe and removing one feels risky. Left unchecked, every enhancement thickens the skill by one no-op line. The no-op test is the pruning discipline that fights it.
- **Sprawl** — one meaning restated across many surfaces, so a change must land in several places or the copies diverge. The single-source-of-truth rule is the fix.

## Quality bar by skill role

### Primary pipeline skills

Must be strongest on:
- invocation clarity
- handoff clarity
- artifact production
- branch and backtracking conditions
- verification of produced work
- artifact bodies that stand on their own for a reader unfamiliar with the codebase (see `writing-for-humans.md`)

### Invoked helper skills

Must be strongest on:
- who calls them
- why they are delegated
- when not to call them directly
- what they return to the caller

### Side-route skills

Must be strongest on:
- where they reconnect to the main flow
- whether they produce durable work items or just diagnosis

### Infrastructure skills

Must be strongest on:
- setup scope
- what they change
- why they are not normal feature-delivery steps

## Minimum author checklist

Before considering a skill revision done, check:

- [ ] `description` is optimized for triggering, not summary
- [ ] `Invocation Position` makes the skill's role obvious
- [ ] process steps are actionable and ordered where necessary
- [ ] handoff is explicit
- [ ] any claimed sources are truly visible in the body
- [ ] optional sections like `Common Rationalizations`, `Red Flags`, or `Verification` are included when they would prevent likely agent failure
- [ ] the skill does not duplicate large amounts of repo-level philosophy that belongs in `SYSTEM-OVERVIEW.md`
- [ ] each step that produces or verifies something ends on a checkable completion criterion (see `Prose economy and steering`)
- [ ] every field this skill writes into an issue or PR body names its reader — the later step that branches on it or writes it back, or an explicit human audience (see `Prose economy and steering`)
- [ ] the no-op hunt was run on changed prose — every added or edited sentence changes model behavior, or it was deleted
