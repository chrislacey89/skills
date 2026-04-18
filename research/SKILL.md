---
name: research
description: "Primary pipeline step after /shape and before /write-a-prd. Use to verify current docs, versions, repo patterns, and key unknowns before shaping. Invokes /api-design-review when API contract risk is high. Not for underdefined problems or implementation-ready work."
sources:
  primary:
    - "Software Estimation — Steve McConnell"
---

# Research

Always run this skill after /shape and before /write-a-prd. It auto-calibrates depth: sometimes it's a 2-minute version check that confirms your approach is still valid, sometimes it's a 30-minute deep dive into unfamiliar territory. The point is that it always runs — you don't get to skip it — because the most expensive research failures are the ones where you didn't know you needed to research.

This is also the first anti-anchoring checkpoint in the workflow. If the user or an earlier conversation introduced a date, budget, or confidence claim, clarify whether it is a **target**, an **estimate**, or a **commitment** before carrying it forward into the PRD.

> **One question per turn.** When confirming constraints, reviewing findings, or asking the user anything, ask one question at a time and wait for the answer before asking the next. Never present a batch of questions as a numbered or bulleted list.
>
> **Prefer single-select.** Use single-select multiple choice when the user is choosing one direction, one priority, or one next step.
>
> **Use multi-select rarely.** Reserve it for compatible sets — goals, constraints, non-goals, success criteria — that can all coexist. If prioritization matters, follow up asking which selected item is primary.
>
> **Use the platform's question tool when available.** In Claude Code, use `AskUserQuestion`; in Codex, `request_user_input`; in Gemini, `ask_user`. Otherwise, present numbered options in chat and wait for the user's reply before proceeding.

## Invocation Position

This is a primary pipeline skill, not an optional extra. The default flow is `/shape` → `/research` → `/write-a-prd`.

Use `/research` whenever the work is headed toward shaping or implementation and you need to verify current versions, official docs, existing code patterns, and past solutions before making design commitments.

Do not skip this step just because the approach feels obvious. Do not use it as a replacement for `/shape` when the problem is still underdefined, and do not use it as a replacement for `/execute` once the work is already shaped and ready to implement.

## Why This Is Mandatory

AI models are trained on internet-scale codebases where deprecated patterns outnumber current ones by orders of magnitude. The model will confidently generate `middleware.ts` for a Next.js 16 project where the file was renamed to `proxy.ts`. It will use `getServerSideProps` in an App Router project. It will suggest packages that don't exist. The only defense is to verify against reality before committing to an approach.

## Execution Flow

### Phase 0: Environment & Version Check (MANDATORY — never skip)

This phase takes 30-60 seconds and catches the most dangerous class of errors: stale API patterns from training data.

1. **Read the dependency manifest.** Extract installed versions of all major dependencies:

   ```bash
   # JavaScript/TypeScript projects
   cat package.json | jq '.dependencies, .devDependencies' 2>/dev/null
   
   # Python projects
   cat requirements.txt 2>/dev/null || cat pyproject.toml 2>/dev/null
   
   # Rust projects
   cat Cargo.toml 2>/dev/null
   ```

2. **Identify the key dependencies for this feature.** Based on what /shape established, which dependencies will this feature touch? List them with their installed versions.

3. **Check for breaking changes.** For each key dependency, do a targeted web search:
   
   ```
   "[dependency name] [installed version] breaking changes migration"
   "[dependency name] [installed version] vs [latest version] API changes"
   ```
   
   Look specifically for:
   - API renames (middleware.ts → proxy.ts)
   - Removed or deprecated methods
   - Changed function signatures (sync → async)
   - Changed file conventions (pages/ → app/)
   - Changed import paths

4. **Check CLAUDE.md / AGENTS.md.** Read any existing project context files for version constraints or conventions that override default patterns.

5. **Flag mismatches.** If any dependency has known breaking changes between the installed version and what the model's training data likely contains, flag them immediately:

   ```
   ⚠ VERSION ALERT: Next.js 16.1 installed — middleware.ts was renamed to proxy.ts in v16. Do NOT use middleware.ts patterns.
   ⚠ VERSION ALERT: React 19 installed — forwardRef is no longer needed, ref is a regular prop.
   ⚠ VERSION ALERT: Drizzle ORM 0.35+ — schema definition API changed significantly from 0.28.
   ```

6. **Spec-anchor check (intra-repo claims).** Steps 1–5 verify external dependencies. Step 6 verifies internal ones — concrete repo identifiers carried in from `/shape` that the PRD will treat as ground truth. The same false-confidence failure mode applies: a model can name a file path, table, function, exported symbol, or test file that doesn't exist, and downstream skills will inherit the phantom anchor as a contract.

   Enumerate the identifiers `/shape` referenced — file paths, schema/table names, function or type names, test files, named patterns ("the existing X loader," "the canonical Y format"). For each, confirm it resolves in the current repo:

   ```bash
   # File path or directory
   test -e <path> || echo "MISSING: <path>"

   # Exported symbol (function, type, class, const)
   rg -n --type ts "export (function|const|class|interface|type) <name>\b"

   # Schema table or named structure
   rg -n "<table_name>" drizzle/schema.ts  # or equivalent for the project
   ```

   Flag every identifier that doesn't resolve, and flag every *vague-noun* reference that resists grepping ("the chunks table" without a name, "the existing pipeline tests" without a path, "the same loader path the reranker uses" without a function). Vague nouns are the canonical site of spec-rot — they survive `/execute` Step 0's Consumes-verification gate (which only fires on named symbols) and only surface at `/pre-merge`. Resolve each by either pinning the exact identifier or rewriting the claim in terms that don't pretend an entity exists.

   Format mismatches as spec alerts so they are visually distinct from version alerts:

   ```
   ⚠ SPEC ALERT: PRD references "knowledge_chunks table" — no such table in drizzle/schema.ts. Closest match: knowledgeObjects (chunks generated in-memory by src/scripts/embed-knowledge.ts).
   ⚠ SPEC ALERT: PRD says "mirroring existing pipeline tests" — no test file exists at src/mastra/rag/*.test.ts. Pattern is invented, not extended.
   ```

   Keep this within Phase 0's 30–60s budget — only check identifiers actually surfaced in `/shape`, not every name in the repo.

### Phase 1: Auto-Calibrate Depth

Based on Phase 0 results, determine the research depth:

**TARGETED (2-5 min)** — Use when:
- Phase 0 found no version surprises
- The feature extends existing patterns already in the codebase
- No external APIs or unfamiliar libraries involved
- The approach is clear from the shape session

For TARGETED depth: write a short research document (20-50 lines) containing the version check results, any relevant past solutions from docs/solutions/, and a confirmation that the planned approach is valid for the installed versions. Skip the full template sections (Don't Hand-Roll, Options Evaluated, etc.). Move on to Phase 5.

**STANDARD (10-20 min)** — Use when:
- Integrating with a familiar external service using a new feature
- One dependency has a version mismatch that needs investigation
- A single technical decision needs evaluation (but not a wide-open choice)

**DEEP (20-30 min)** — Use when:
- Phase 0 found significant version mismatches
- The feature involves an external API or service not yet in the codebase
- Multiple valid technical approaches need evaluation
- An unfamiliar library with complex documentation is involved

Tell the user which depth was selected and why. If they disagree, adjust.

### Phase 1.25: Library Callback Contracts

**Only runs when the feature implements a library-provided callback surface.** Triggers include: agent `prepareStep`/`onStepFinish`/`before*`/`after*` hooks, Express/Koa/Next middleware and proxy functions, AI SDK tool `execute` handlers, render props and higher-order components, lifecycle methods, interceptors, or any other shape where the library hands the application a callback to implement.

Phase 0 verifies APIs the feature **calls**. Most features stop there. When the feature also **implements** a callback the library defines, TypeScript's excess-property check does not run on returned values typed against local wrapper interfaces — any field the library's signature does not declare is silently discarded at runtime, even when the build passes. Pin the contract here, once, so `/write-a-prd` cannot codify a non-existent mechanism and `/execute` cannot wrap the return in a superset type.

For each callback the feature will implement:

1. **Open the installed type definition.** Grep `node_modules/<library>/**/*.d.ts` (or the equivalent for the language) for the callback's type name. Note the file path and line number.
2. **Record the accepted return shape verbatim.** Paste the return-type declaration — every field, optional marker, and union arm. Do not paraphrase.
3. **Name the replace-vs-merge semantics.** If the return includes a field that hands the library a collection (system messages, headers, tools, middleware stack), confirm in the library source whether the library **replaces** the existing collection with your return or **merges** into it. Replace semantics are the highest-risk class: the callback must reconstruct whatever it wants preserved.
4. **Flag any wrapper-type plans.** If the shape session imagined a mechanism (e.g. "inject via system override") that doesn't appear in the recorded shape, flag it as a design-time veto for the PRD. Do not downgrade to "we'll figure it out in `/execute`."

This step is gated — it only runs when a callback surface is in play — so Phase 0's 30–60s budget is preserved for features that only call libraries.

### Phase 1.5: API-Shaped Work Check

After selecting depth, determine whether the feature needs focused API contract review.

Invoke `/api-design-review` only if at least one of these is true:

- a new external or partner-facing API is being introduced
- an existing request or response contract is changing
- OAuth, scopes, token model, or webhook verification is involved
- there is real uncertainty about paradigm selection

You may also invoke it for internal APIs with multiple independent consumers when a contract mistake would create broad cleanup cost.

Do not invoke it for ordinary implementation work that merely calls an API without shaping the contract.

If `/api-design-review` runs, incorporate its verdict into the research document rather than duplicating a second full API review.

### Phase 2: Establish Constraints

State the constraints from the shape session. These bound the research and prevent scope drift. Present each constraint one at a time, ask the user to confirm or correct it, then move to the next:

1. What is the feature trying to accomplish? (1-2 sentences from shape)
2. What are the hard constraints? (scale, budget, self-hosted vs managed, latency, auth model, etc.)
3. What decisions are already locked? (framework, language, deployment target, etc.)
4. What version constraints did Phase 0 surface? (list any flags)
5. If timing language exists, what is currently a target, what is currently an estimate, and what is explicitly not yet a commitment?

Do not present these as a batch. State one constraint, get confirmation, then proceed to the next.

### Phase 3: Consult Past Solutions

Search `docs/solutions/` for relevant past solutions:

```bash
grep -rl "relevant-keyword" docs/solutions/ 2>/dev/null
```

If relevant solutions exist, read them and incorporate their lessons. Note which past pitfalls or patterns apply. This is the compounding benefit — past work makes future research faster and more accurate.

**Staleness check:** When reading a `docs/solutions/` file, check its `volatility` YAML field and `date`. If `volatile` and older than 90 days, or if the Shelf Life condition appears to have been met, note it as potentially stale before incorporating its lessons. Flag stale docs to the user — they should be updated or deleted.

### Phase 4: Research

Research the codebase and relevant technologies. Use sub-agents in parallel when investigating multiple options.

1. **Explore relevant existing code** — What patterns exist? What integration points are available? What constraints does the current architecture impose?
2. **Fetch current documentation** — If Context7 MCP is available, use `resolve_library` and `get_library_docs` for the specific installed version. If not, use web search targeting official docs for the installed version — never the "latest" version unless it matches what's installed. Also check for `llms.txt` at the library's documentation site.
3. **Verify every API reference** — Do NOT trust training data for any framework API call. Every API method, import path, file convention, or function signature in your research output must trace back to either: (a) the installed version's official documentation, (b) a verified web search result, or (c) existing working code in the current codebase. If you cannot verify an API reference, mark it explicitly: "⚠ UNVERIFIED — could not confirm this API exists in [version]."
4. **Evaluate each option against constraints** — Score each option against the constraints from Phase 2. Be explicit about which constraints each option satisfies or violates.

For each option investigated, ask:

- What should be proven first?
- What existing patterns should be reused?
- What boundary contracts matter?
- Are there known failure modes that should shape implementation?

Before leaving Phase 4, produce a lightweight estimation-readiness readout:

- What is known now vs still unknown?
- Which unknowns most widen the current estimate range?
- Is the work still best framed by analogy, decomposition, or calibrated actuals?
- Should any timeline statement remain a range or confidence ladder rather than a single-point date?

The goal is not to create a scheduling ceremony. The goal is to prevent research findings from being summarized as false precision.

For API-shaped work, explicitly document:

- the API problem statement and impact statement
- the developer consumers affected by the contract
- the operation inventory the API must support
- the paradigm decision and rejected alternatives
- the auth, scope, or webhook verification model if relevant
- whether the proposed change is additive or breaking

### Phase 5: Write the Research Document

Write the research document to a durable, per-user archive outside the repo working tree:

```
~/.claude/research/<repo-slug>/<feature-slug>-<YYYY-MM-DD>.md
```

Where `<repo-slug>` is `owner-name` derived from the git remote (e.g. `chrislacey89-skills`), `<feature-slug>` is a short kebab-case phrase naming the feature, and `<YYYY-MM-DD>` is today's date. Create intermediate directories if they do not exist.

Start the file with YAML frontmatter so future consumers can judge freshness:

```yaml
---
date: 2026-04-14
repo: <owner/repo>
feature: <short phrase>
installed_versions_snapshot:
  - <package>@<version>   # list only the key dependencies this research pinned against
callback_contracts_snapshot:
  # Only present when Phase 1.25 ran. One entry per library callback this feature implements.
  # - callback: <library>.<callback-name>
  #   file: node_modules/<library>/.../<file>.d.ts
  #   line: <line-number>
  #   accepted_fields: [<field1>, <field2>, ...]
  #   collection_semantics: replace | merge | n/a
---
```

**Why outside the repo:** the archive is per-user working memory, not team-shared artifact. Branch switches, worktree cleanup, and `.gitignore` hygiene cannot accidentally destroy it. It is not committed to the project and is never visible to collaborators.

**Include only sections that have real content.** A TARGETED research doc might be 20 lines. A DEEP one might be 300. This document is the compressed handoff to `/write-a-prd` — once written, the downstream skill works from this file, not from the raw research exploration. If this session is running long, suggest starting `/write-a-prd` in a fresh session using the archive path as input.

#### Emoji Legend

Use these consistently across all research documents so reviewers can scan quickly:

| Emoji | Meaning | When to use |
|-------|---------|-------------|
| 🔒 | Locked decision | Constraint from shape that bounds the research |
| ✅ | Verified | API or pattern confirmed against installed version docs |
| ⚠️ | Warning | Stale pattern, version mismatch, or breaking change |
| 🔄 | Version change | Behavior that changed between versions — old vs new |
| 🚫 | Don't hand-roll | Existing solution available, don't build from scratch |
| 🪤 | Pitfall | Common mistake to avoid |
| 🔗 | Doc link | Link to official documentation for audit |
| 💡 | Recommendation | The suggested approach |
| 📦 | Dependency | Package or library reference with version |

#### Inline Documentation Links

**Every API recommendation must include a direct link to the official documentation** so the developer can click through and audit. Do not just list sources at the bottom — put the link right next to the claim. When web searching or using Context7, capture the exact URL of the documentation page that confirms each API pattern.

Format: `[API or pattern name](URL) 🔗`

Example: "Use [`proxy.ts`](https://nextjs.org/docs/app/api-reference/file-conventions/proxy) 🔗 instead of `middleware.ts`."

If you cannot find a direct documentation link for an API reference, mark it: "⚠️ UNVERIFIED — no doc link found for installed version."

#### Version Change Callouts

When the planned approach relies on behavior that changed between versions, flag it with a `🔄 VERSION CHANGE` callout block. Include what the old behavior was, what the new behavior is, which version introduced the change, and a link to the migration guide. This gives the reviewer full context to decide whether they're comfortable with the new pattern.

Format:
```
🔄 **VERSION CHANGE (v15 → v16):** `middleware.ts` was renamed to `proxy.ts`.
  - **Before (v15):** Root-level `middleware.ts` with `export function middleware()`
  - **After (v16):** Root-level `proxy.ts` with `export function proxy()`
  - **Migration guide:** [nextjs.org/docs/app/guides/upgrading/version-16](URL) 🔗
  - **Why it changed:** CVE-2025-29927 + clarifying that it runs at the network boundary, not as Express-style middleware
```

#### Research Document Template

```markdown
# Research: [Feature Name]

**Date:** YYYY-MM-DD
**Depth:** TARGETED / STANDARD / DEEP
**Domain:** [Primary technology or problem domain]
**Confidence:** HIGH / MEDIUM / LOW
**Constraints from shape:** 🔒 [1-2 sentence summary of locked constraints]

## 📦 Version Check

| Dependency | Installed | Latest | Status |
|-----------|-----------|--------|--------|
| [name] | [version] | [version] | ✅ No issues / ⚠️ Breaking changes |

[If any version alerts were flagged in Phase 0, list them with 🔄 VERSION CHANGE callouts:]

🔄 **VERSION CHANGE (v[old] → v[new]):** [What changed]
  - **Before:** [Old API / pattern / behavior]
  - **After:** [New API / pattern / behavior]
  - **Migration guide:** [link](URL) 🔗
  - **Why it changed:** [Brief rationale]

## 💡 Summary

[2-3 paragraph executive summary. State the primary recommendation and why. Inline-link key documentation references.]

When referencing specific APIs, always link to docs:
- ✅ Use [`functionName()`](URL) 🔗 for [purpose]
- ⚠️ Do NOT use `deprecatedFunction()` — removed in v[X] ([migration guide](URL) 🔗)

## Estimate Readiness

[Include when timeline, budget, or scope confidence is part of the decision. Keep this short.]

- **Target in play:** [Desired budget, event date, or appetite, if any]
- **Current estimate posture:** [Range / confidence ladder / too early to estimate tightly]
- **Commitment posture:** [No commitment yet / conditional after X / safe to commit]
- **Main uncertainty drivers:** [What still widens the range]

## API Review

[Include only when the feature introduces or changes an API contract.]

- **Problem statement:** [What developer problem this API solves]
- **Impact statement:** [What outcome the API enables]
- **Consumers:** [Who integrates with it]
- **Operations:** [The concrete operations the API must support]
- **Compatibility:** Additive / Potentially breaking / Breaking
- **API review verdict:** Proceed / Proceed with constraints / Revise before implementation

## Library Callback Contracts

[Include only when Phase 1.25 ran — this feature implements a library-provided callback.]

For each callback the feature implements:

### `<library>.<callbackName>`

- **Type definition:** `node_modules/<library>/.../<file>.d.ts:<line>`
- **Accepted return shape (verbatim from installed .d.ts):**
  ```ts
  // paste the return-type declaration as written in the installed library
  ```
- **Collection-field semantics:** [replace / merge / n/a — e.g. "`systemMessages` replaces the full system-message list; the callback must concat the library's passed-in `systemMessages` arg to preserve advisor persona"]
- **Fields commonly imagined but not accepted:** [list any fields the shape or PRD draft referenced that don't appear in the accepted shape. If none, omit.]
- **Downstream rule:** Any boundary-map Produces entry in the PRD that references this callback must cite this snapshot by file:line.

## 🚫 Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why | Docs |
|---------|-------------|-------------|-----|------|
| [Problem] | [Naive approach] | [Existing solution] | [Why] | [🔗 link](URL) |

## 🪤 Common Pitfalls

### 🪤 Pitfall: [Name]
**What goes wrong:** [Concrete description]
**Why it happens:** [Root cause]
**How to avoid:** [Specific prevention strategy] ([docs](URL) 🔗)
**Warning signs:** [How to detect this during implementation]

## Options Evaluated

### Option A: [Name]
- **Fits constraints:** 🔒 [Which constraints it satisfies]
- **Violates constraints:** [Which it doesn't, or "None"]
- **Pros:** [Specific advantages]
- **Cons:** [Specific disadvantages]
- **Cost/pricing:** [If relevant]
- **Docs:** [🔗 link](URL)

### Option B: [Name]
[Same format]

## 💡 Recommended Approach

[Which option and why. Reference the 🔒 constraints that drove the decision. Link to key documentation.]

🔄 **Note for reviewer:** [If the recommended approach depends on version-specific behavior, call it out here. Example: "This approach uses the v16 `proxy.ts` convention. If we downgrade to v15 for any reason, this would need to revert to `middleware.ts`."]

## Relevant Existing Code

[Files, patterns, and integration points in the current codebase.]

- `path/to/file.ts` — [What it does and how it's relevant]

## 🔗 Sources

[Every API reference above must trace to one of these. Grouped by confidence.]

**✅ Verified (official docs, matches installed version):**
- [Source title](URL) — [What was learned]

**⚠️ Partially verified (community source, or version not exactly matched):**
- [Source title](URL) — [What was learned, caveat]

**❓ Unverified (blog post, may be outdated, or no doc link found):**
- [Source title](URL) — [What was learned, risk]
```

For TARGETED depth, use only the Version Check and Summary sections, plus any relevant pitfalls or past solutions. Skip Options Evaluated, Don't Hand-Roll, etc. But always include inline doc links and version change callouts — those are the highest-value pieces regardless of depth.

If timeline pressure exists, include the short Estimate Readiness section even in TARGETED mode. Keep it to a few lines rather than forcing a full estimation write-up.

### Phase 6: Review with User

Present the research document to the user. Then walk through these review questions one at a time — ask one, wait for the answer, then ask the next:

1. Does the recommended approach match your instinct?
2. Are there options I missed that you'd like investigated?
3. Any version surprises that change your thinking?
4. Are you comfortable proceeding to PRD with this recommendation?

Do not present all four questions at once. Iterate on each answer until the user is satisfied. The research file is saved to the archive path outside the repo — do not commit it to git.

## Handoff

- **Expected input:** clarified problem framing from `/shape`, including choices, assumptions, impositions, and structural signals
- **Produces:** an archived research file at `~/.claude/research/<repo-slug>/<feature-slug>-<YYYY-MM-DD>.md`, verified version and documentation guidance, and a clearer estimate-readiness posture
- **May invoke:** `/api-design-review` when contract risk is high enough that the API shape needs focused scrutiny before shaping continues
- **Comes next by default:** `/write-a-prd`

## Lifecycle

**The research file is a point-in-time snapshot.** It exists to serve the PRD and Ralph loop during active work, and then persists as durable per-user context for future planning in the same area.

- Reference the archive path in your PRD so Ralph reads it during implementation.
- After the feature ships, the archive entry persists automatically — do not delete it. Branch switches, worktree cleanup, and `/compound`'s closeout step cannot touch it because it lives outside the repo.
- Stale research actively harms agent performance — a research file that recommends Ably v1.2 when v2.0 has breaking changes will steer Ralph in the wrong direction. The frontmatter `date` and `installed_versions_snapshot` let future readers judge whether the snapshot is still trustworthy before they rely on it.
- This skill does not yet auto-consult prior archive entries during Phase 0 — that capability is a separate follow-on. For now, the archive is simply durable storage that won't be lost to ordinary git workflow.
