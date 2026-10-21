---
name: ubiquitous-language
description: "User-invoked side-route for hardening domain vocabulary. Type it when terminology is fuzzy, competing terms are causing confusion, or a glossary would improve shaping, QA, and refactor conversations. Produces UBIQUITOUS_LANGUAGE.md, then returns to the workflow that needed sharper language."
disable-model-invocation: true
sources:
  primary:
    - "Domain-Driven Design — Eric Evans"
  secondary:
    - "Domain Storytelling — Hofer & Schwentner"
    - "Living Documentation — Cyrille Martraire"
---

# Ubiquitous Language

Define the domain model's vocabulary. Each term in this glossary is a model element — changing a term here means changing the model and the code.

## Invocation Position

This is a side-route skill that sharpens shared language across the rest of the workflow.

Use `/ubiquitous-language` when terminology is fuzzy, stakeholders are using conflicting terms, or you want a glossary that improves shaping, QA, issue writing, and refactor conversations.

Do not use it as a substitute for feature shaping or implementation. Its job is to improve the language of those workflows, not replace them.

> **One question per turn.** When walking a workflow story or proposing canonical terms, ask one question at a time and wait for the user's answer before asking the next. Language work is a conversation, not a questionnaire.
>
> **Prefer single-select.** Use single-select multiple choice when the user is choosing one direction, one priority, or one next step.
>
> **Use multi-select rarely.** Reserve it for compatible sets — goals, constraints, non-goals, success criteria — that can all coexist. If prioritization matters, follow up asking which selected item is primary.
>
> **Use the platform's question tool when available.** In Claude Code, use `AskUserQuestion`; in Codex, `request_user_input`; in Gemini, `ask_user`. Otherwise, present numbered options in chat and wait for the user's reply before proceeding.

## Process

1. **Walk one workflow as a story** before extracting terms. Ask for one concrete story in the form "[who] does [what] using [tool]." Treat the nouns in the story as term candidates and the verbs as behavior candidates.
2. **Scan the conversation** for domain-relevant nouns, verbs, and concepts. Pay special attention when a domain expert corrects a developer's word choice — these corrections are high-value signals.
3. **Surface implicit concepts** — look for domain knowledge that is discussed but never named:
   - Circumlocutions: a concept explained in a full clause because no term exists yet
   - Hidden rules: conditional logic or eligibility checks described procedurally ("if X and Y and Z...") that could be named as a policy or constraint
   - Contradictions: apparent disagreements between participants that would dissolve if a new concept were introduced
4. **Identify problems**:
   - Same word used for different concepts (ambiguity)
   - Different words used for the same concept (synonyms)
   - Vague or overloaded terms
5. **Propose a canonical glossary** with opinionated term choices, and ask the user to confirm each term's name and definition — one term per turn
6. **Check model-code correspondence** (when a codebase is present). Two checks, both recorded under **Model-code fractures**:
   - Names: scan class, module, and function names for terms that diverge from the glossary.
   - Behavior: when the user states a rule about a term ("an Order can be canceled until it ships"), make one search for the code that enforces it and read it. If the code contradicts the rule, say so before the term is written, citing file and line — the glossary must not record a rule the system does not keep. If nothing enforces it, record the rule as *unenforced* rather than searching further. When the code, not the rule, looks wrong, recommend `/triage-issue`; do not edit the glossary to match a bug.
7. **Write each term as it settles.** A term is settled when the user has confirmed its canonical name and definition (step 5) and step 6 has run on any rule the user stated about it — not when it is first mentioned. Create `UBIQUITOUS_LANGUAGE.md` in the working directory on the first settled term and add or revise an entry at each confirmation, so a conversation that stops early still leaves every agreed term on disk. The file follows the format below from the first write; writing inline is not permission to log every answer.
8. **Output a summary** inline in the conversation once the walk is finished

## Output Format

Write a `UBIQUITOUS_LANGUAGE.md` file with this structure:

```md
# Ubiquitous Language

## Order lifecycle

| Term        | Definition                                              | Aliases to avoid      |
| ----------- | ------------------------------------------------------- | --------------------- |
| **Order**   | A customer's request to purchase one or more items      | Purchase, transaction |
| **Invoice** | A request for payment sent to a customer after delivery | Bill, payment request |

## People

| Term         | Definition                                  | Aliases to avoid       |
| ------------ | ------------------------------------------- | ---------------------- |
| **Customer** | A person or organization that places orders | Client, buyer, account |
| **User**     | An authentication identity in the system    | Login, account         |

## Relationships

- An **Invoice** belongs to exactly one **Customer**
- An **Order** produces one or more **Invoices**

## Surfaced implicit concepts

| Proposed term       | Evidence                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------- |
| **Shipping Policy** | Described procedurally three times ("if the total is above $50 and...") but never given a name |

## Flagged ambiguities

- "account" was used to mean both **Customer** and **User** — these are distinct concepts: a **Customer** places orders, while a **User** is an authentication identity that may or may not represent a **Customer**.

## Model-code fractures

_Include only when a codebase was scanned._

| Glossary term   | Code identifier    | Location                        | Recommendation          |
| --------------- | ------------------ | ------------------------------- | ----------------------- |
| **Fulfillment** | `order_processing` | `src/services/order_processing` | Rename to `fulfillment` |

| Stated behavior                                   | Code evidence                                                | Recommendation                                              |
| ------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------- |
| An **Order** can be canceled until it ships       | `src/orders/cancel.ts:42` refuses cancellation after payment | Decide which is right; if the code is wrong, `/triage-issue` |
| A **Customer** has at most one open **Invoice**   | Unenforced — no code found                                   | Confirm the rule belongs in the model, or drop it           |
```

## Handoff

- **Expected input:** domain language ambiguity, competing terminology, or a need to harden vocabulary before downstream work
- **Produces:** `UBIQUITOUS_LANGUAGE.md` and clearer naming for issues, specs, QA, and refactor discussion
- **Read by:** `/qa` (to learn an area's language), `/prd-to-issues` (as a slice anchor), and `/re-pitch` (for glosses) — each only when `UBIQUITOUS_LANGUAGE.md` exists; `/re-pitch` may recommend this skill when the same terms keep needing glosses
- **What comes next:** return to the workflow that needed better language, now using the glossary consistently

## Rules

- **This glossary is the model, not documentation of it.** If a term is renamed or redefined here, treat it as a model change that should be reflected in code. If a term exists in code but not here, the glossary is incomplete.
- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others as aliases to avoid.
- **Flag conflicts explicitly.** If a term is used ambiguously in the conversation, call it out in the "Flagged ambiguities" section with a clear recommendation. If the same word legitimately means different things in different subdomains, note it as cross-context divergence rather than a defect.
- **Name the unnamed.** When a concept appears only as clauses, conditionals, or procedural descriptions ("if X and Y and not Z..."), propose a canonical name for it (e.g., "Free Shipping Eligibility," "Booking Validity"). These are often the highest-value terms in the glossary.
- **Only include domain terms.** The file holds the sections in Output Format and nothing else. Skip generic programming concepts (array, function, endpoint) and module/class names unless they have meaning in the domain language, and keep implementation notes, specs, and scratch out of it.
- **Keep definitions tight.** One sentence max. Define what it IS, not what it does.
- **Show relationships.** Use bold term names and express cardinality where obvious.
- **Group terms into multiple tables** when natural clusters emerge (e.g. by subdomain, lifecycle, or actor). Each group gets its own heading and table. If all terms belong to a single cohesive domain, one table is fine — don't force groupings.
- **Classify when modeling, not when aligning.** If the conversation involves design decisions about identity or lifecycle, add a "Classification" column (Entity, Value Object, or Service). Omit it when the glossary is purely for shared vocabulary between stakeholders.
- **Run a "Modeling Out Loud" diagnostic (do not write it to the file).** Mentally construct a scenario walkthrough (3-5 exchanges) that forces key glossary terms to bear weight in realistic sentences. If a term feels awkward, requires a parenthetical gloss, or gets silently replaced by a different word, the concept it represents is suspect. Record any findings in **Surfaced implicit concepts** (for unnamed concepts) or **Flagged ambiguities** (for term problems) — the dialogue itself is scaffolding that doesn't belong in the output.

## Re-running

When invoked again in the same conversation:

1. Read the existing `UBIQUITOUS_LANGUAGE.md`
2. Incorporate any new terms from subsequent discussion through steps 5–7
3. Surface any newly implicit concepts from subsequent discussion
4. Update definitions if understanding has evolved — each change is a model change, not just a wording fix
5. Re-flag any new ambiguities
6. Re-run the Modeling Out Loud diagnostic with new terms — record findings in Surfaced implicit concepts and Flagged ambiguities
