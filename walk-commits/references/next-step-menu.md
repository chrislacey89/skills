# Next-Step Menu

When a pipeline skill finishes and yields control at a **branch point**, render the next step as a selectable menu instead of leaving the user to recall and retype a command.

Every primary skill already encodes its successor in a `Comes next by default:` line. That answer is computed the moment the skill finishes — but it lives in the skill's prose, not in front of the user. A next-step menu moves that knowledge *into the world* (Norman) and removes the typing friction of the most common action (Nudge's "make it easy"). The recommended next step becomes the pre-surfaced default; the platform's free-text "Other" option is the built-in "ask something else" escape hatch.

This doc defines *when* a handoff becomes a menu and *how* to shape the options. Skills reference it from their `## Handoff` section instead of re-encoding the rules.

## When to render a menu

Render a menu only at:

- **Genuine branch points** — the skill has more than one legitimate next step (e.g. `/shape` → `/research` *or* `/create-milestone`; `/pre-merge` → `/closeout` *or* address-a-finding).
- **High-frequency control-yield seams** — a single dominant next step the user takes over and over, where retyping it is pure friction (e.g. `/execute` exiting to `/pre-merge`).

## When NOT to render a menu

- **Linear single-successor handoffs** — when there is exactly one real answer and no fork (`/research` → `/write-a-prd`, `/write-a-prd` → `/prd-to-issues`, `/prd-to-issues` → `/execute`). A menu with one option is ceremony — Norman's *featuritis*, a cost paid by every future user.
- **When the skill already auto-invokes the next step.** Do not replace an existing auto-invoke with a menu. The menu is for the points where the skill currently *stops* and hands the user a text box. (`/execute` still auto-invokes `/pre-merge` on the confirmed "Ready for PR Review" path — the menu serves only its other exits.)
- **In place of a deliberate checkpoint.** The menu appears *after* a verification gate, never instead of it. It must never let the user skip a pause the skill put there on purpose (e.g. `/execute`'s Step 5 acceptance-criteria confirmation).
- **On AFK / Ralph iterations.** There is no user to answer a menu; autonomous runs exit on their own rules.

## Show the comparison before you take the choice

A menu is a *commit* mechanism. It asks which option, and it never shows the options against
each other. For most branch points that is fine — two successors, one attribute each, and the
labels carry it. But the pipeline also manufactures genuine N-way forks: `/design-an-interface`
emits candidate interface shapes, `/api-design-review` weighs REST/RPC/GraphQL,
`/improve-pipeline` returns a four-way verdict, `/correct-course` chooses supersede/revise/discard,
`/pre-merge` Phase 4 disposes of each finding four ways. Rendered as prose, those arrive one
after another — and the reader is asked to hold every option's every attribute in memory to
compare them.

**Threshold — all three must hold, or it is prose plus the menu as usual:**

1. **≥3 mutually exclusive options.** Picking one rules the others out.
2. **Each carries ≥3 attributes.** What it buys, what it costs, what state it leaves behind, when to pick it.
3. **They are not orderable on one axis.** If one option is simply better, say so in a sentence and recommend it.

Three options × three attributes is nine items; four × five is twenty. Norman puts practical
short-term-memory capacity at 3–5 items — *"systems that require users to hold more than a
handful of items simultaneously will fail routinely — not occasionally."* And Tufte names
sequential display as the comparison anti-pattern outright: *"The viewer cannot compare what
they cannot see at the same time. Memory is not vision."* Above the threshold, prose is not a
weaker presentation of the comparison; it is the absence of one.

**How to render it.** Attributes as rows, options as columns, same attributes in the same order
down every column (Tufte's Constancy of Design — only the content differs). **A markdown table
in chat satisfies this and is the default**: it costs nothing, needs no artifact, and delivers
the eyespan, which is where the work happens. **For every skill that holds this doc, the table
is the whole render** — the HTML skeleton lives in `visual-recap-design.md` §11, which is
bundled only to `/visual-recap` and `/walk-commits`, so those two read it at
`references/visual-recap-design.md` and reach for it when the cells carry code, long resulting
text, or enough bands that a chat table stops being scannable. Naming the two skills rather
than posing a condition is deliberate: an escape hatch stated as "when you have the file" is
one every reader has to go check, and four of the six holders can never satisfy it.
Either way the artifact is transient: gitignored `.context/` or `mktemp`, never committed.

**Grounding is the block's defining constraint, not a refinement.** N identically-weighted
columns claim N equally-evidenced options, and the options do not exist yet, so most cells have
nothing to derive from. Every cell is therefore either **cited** — quoted from something that
already exists (current text at `file:line`, an issue or PR body, a research entry, test
output) and showing that source — or visibly marked **asserted**, the model's judgment about a
state that does not exist. Support asymmetry must show as visual asymmetry, and **every option
carries at least one cited cell**; an option with nothing citable is a finding to state, not a
column to pad. The paragraph above is the whole rule as it applies here; `visual-rendering-core.md`
§1 "Forward-looking blocks" states it once canonically, with the render treatments, for the two
skills that bundle that file.

**Then render the menu.** The comparison shows; `AskUserQuestion` commits. The two compose —
this does not replace the menu, add an option to it, or change how its options are shaped.

> **Reach, priced — in both directions.** This doc is bundled to `/execute`, `/pre-merge`,
> `/shape`, `/closeout`, `/visual-recap`, and `/walk-commits`
> (`scripts/skill-references.manifest`). `/pre-merge` Phase 4's finding disposition is the fork
> that triggered the rule; `/visual-recap` and `/walk-commits` are here because they hold §11's
> markup and its pointers to this threshold would otherwise resolve to nothing post-install.
> That inbound direction cost 101 lines and two rows. The outbound direction — bundling the
> 210-line core and the 779-line design doc so the other four holders could render HTML — was
> priced at 989 lines per run and declined; they render the table, which is why the table is
> the default rather than a fallback.
>
> The fork-producing skills named above (`/design-an-interface`, `/api-design-review`,
> `/improve-pipeline`, `/correct-course`) hold this doc not at all, so they do not see the
> threshold. Giving it to them means bundling this file and pointing their `## Handoff`
> sections at it. That is a separate change, deliberately not made here.
>
> **Falsification.** If, over the next several multi-option forks, this either never fires
> (threshold too high) or fires on forks a sentence would have settled (too low), retune the
> threshold once — then delete this section rather than leave it as ceremony.

## How to shape the options

- **Use the platform's question tool, one question per turn.** In Claude Code, `AskUserQuestion`; in Codex, `request_user_input`; in Gemini, `ask_user`. Otherwise present numbered options in chat and wait. This is one question (the next step), not a form — keep it consistent with the repo's [Conversational Principles](../CLAUDE.md) and the per-skill "use the platform's question tool" note.
- **Recommended step first.** Pre-surface the `Comes next by default:` step as the first/default option — Nudge's "defaults are the master lever," and Krug's *satisficing* (after Herbert Simon): people take the first reasonable option rather than weighing all of them. That is why first position works, and also why it is not a safety net — a badly worded first option gets taken anyway. Ordering never compensates for wording. Label it so the recommendation is obvious (e.g. "→ `/pre-merge` (recommended)").
- **Keep it to ≤4 options.** `AskUserQuestion` caps options. If a handoff has more legitimate paths than fit, group the rare ones under one option or rely on the free-text "Other" hatch.
- **Don't add an "Other / something else" option.** The platform supplies a free-text escape hatch automatically; adding one wastes a slot.
- **Context-specific follow-ups are allowed.** Beyond the pipeline successor, a skill may offer 1–3 options drawn from *this run* — e.g. `/execute` offering "verify acceptance criterion N in the running app" or "show the diff for the riskiest change." This mirrors `/walk-commits` step 3, which advances its loop with `AskUserQuestion` offering "Next commit" plus commit-specific deep-dives.
- **Each option must be an unambiguous choice on its own.** The rules above shape the menu as a *set* — its ordering, its size, its escape hatch, what may go in it. This one shapes the individual option. Krug's Second Law — *"it doesn't matter how many times I have to click, as long as each click is a mindless, unambiguous choice"* — locates the cost of a choice in thought required × uncertainty about correctness, not in count or position. A menu can pass every rule above and still offer options nobody can choose between. Check each option against Krug's three sources of ambiguity:
  - **Insider naming.** A bare skill name is jargon: it names the machinery, not the outcome. Write **`/compound` (capture a lesson)**, not **`/compound`**.
  - **A boundary the user can't resolve.** If someone in a plausible state could reasonably pick either of two options, the boundary lives in the author's head, not in the labels. Name the discriminator ("fix it on this branch first" vs. "merge now, track it as an issue") or merge the two options into one.
  - **A set with no option for the state the user is actually in.** Krug's "Home vs. Office" case, where a home-office user has no right answer. The free-text hatch is for the situations the skill *can't* anticipate; it is not a substitute for a branch the skill already knows about.

  Work within the platform's limits, not against them: where an option has a short label plus a longer description, the label carries the outcome and the description completes it; where it is a single string, that string does both. If the outcome will not fit at all, the option is doing too much — split it or cut it rather than shipping a label only its author can decode.

## Worked example: `/walk-commits` step 3

`/walk-commits` is the existing precedent. After each commit it advances with a single `AskUserQuestion` offering **Next commit** (the default forward step) plus 2–3 commit-specific deep-dives. Branch-point handoffs follow the same shape: the recommended successor as the default, a small set of legitimate alternatives, and the free-text hatch for anything else.

## Relationship to other guidance

- The menu **renders** the `Comes next by default:` line; it does not remove it. The Handoff section still states the default in prose for readers and non-interactive contexts.
- The menu **composes with** existing auto-invokes — it serves the exits an auto-invoke does not cover.
- This convention sits beside the repo's "one question per turn / use the platform's question tool" guidance. Keep the platform-tool note in one canonical place; cross-reference rather than duplicate it.
