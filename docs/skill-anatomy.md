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
---
```

## Frontmatter rules

- `name` must match the directory name.
- `description` exists for discovery, not summary.
- `description` should answer three questions when possible:
  - when to invoke the skill
  - when not to invoke the skill
  - whether it is a direct-entry, delegated, side-route, or infrastructure skill
- Do not put process steps in `description`.
- `sources` should be used selectively. Only claim a source the body clearly operationalizes.

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

## Quality bar by skill role

### Primary pipeline skills

Must be strongest on:
- invocation clarity
- handoff clarity
- artifact production
- branch and backtracking conditions
- verification of produced work

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
