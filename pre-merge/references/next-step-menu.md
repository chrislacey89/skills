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
