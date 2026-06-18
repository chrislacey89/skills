---
name: prd-to-issues
description: "Primary pipeline decomposition step after /write-a-prd. Use when a shaped PRD is ready to become implementation-ready slices with boundary maps and dependency order. Not for unresolved scope, appetite, or solution direction."
sources:
  primary:
    - "The Pragmatic Programmer — Hunt & Thomas"
  secondary:
    - "Designing Web APIs — Jin, Sahni, Shevat"
    - "Software Estimation — Steve McConnell"
    - "Software Requirements — Karl Wiegers & Joy Beatty"
---

# PRD to Issues

Break a PRD into independently-grabbable GitHub issues using vertical slices (tracer bullets).

## Invocation Position

This is a primary pipeline skill that normally follows `/write-a-prd` and precedes `/execute`.

Use `/prd-to-issues` when a PRD is already shaped and you need implementation-ready slices with clear contracts between them.

Do not use it as a substitute for shaping. If the PRD is still changing at the level of solution direction, rabbit holes, or appetite, go back to `/write-a-prd` first.

## Process

### 1. Locate the PRD

Ask the user for the PRD GitHub issue number (or URL).

If the PRD is not already in your context window, fetch it with `gh issue view <number>` (with comments).

**Check for milestone.** After fetching the PRD, check whether it belongs to a GitHub milestone: `gh issue view <number> --json milestone`. If a milestone exists, note the milestone title for use in Step 6 — all slice issues should be attached to the same milestone.

### 2. Explore the Codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code.

### 3. Draft Vertical Slices

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- The first slice is the tracer bullet — it must prove the core architecture connects end-to-end with production-quality code before subsequent slices proceed. Subsequent slices adjust aim based on what the first slice reveals.
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
- Order the first slice to validate architecture, then remaining slices by risk
</vertical-slice-rules>

Always create a final QA issue with a detailed manual QA plan for all items that require human verification. This QA issue should be the last item in the dependency graph, blocked by all other slices. It should be HITL.

### 4. Draft the Boundary Map

Before presenting slices to the user, draft a boundary map showing what each slice produces and what it consumes from upstream slices. This forces interface thinking before implementation and ensures slices actually connect.

Boundary maps are API contracts, not just dependency inventories — if a slice produces something another slice depends on, specify enough contract shape that downstream work will not invent incompatible assumptions.

For each slice, specify:

- **Produces:** The concrete outputs — exported functions, types/interfaces, API endpoints, database tables, UI components. Include file paths and function signatures where possible.
- **Consumes from #N:** What this slice needs from upstream slices — specific imports, API endpoints it calls, types it uses. Reference the producing slice by number. If the parent PRD's research lives in a `research`-labeled spike issue (see `/research` Phase 5d), you may also cite `Refs #<spike-issue-number>` here when the slice's interface decisions are bounded by a specific recommendation, callback contract, or version snapshot recorded in that spike. The `Refs #N` lineage syntax is the same one used elsewhere in the pipeline.
- **Contract notes:** The success shape, error shape, compatibility posture, and any versioning readiness concerns that matter to downstream consumers.

**Contract-shape rendering.** When the parent PRD locks a schema, type alias, function signature, or structured input/output shape in code form (per `/write-a-prd`'s Implementation Decisions guidance), the slice's `Produces` field should reference it by location rather than re-render it. Re-render only when the slice introduces a contract shape the PRD did not lock. This keeps the PRD as the single source of truth for locked contracts and avoids drift between two surface forms of the same artifact.

**On the Consumes side**, the same principle applies in mirror: when a slice consumes a contract shape produced by a sibling slice in a typed language (TypeScript, Rust, Python-with-stubs), the slice's `Consumes` field should **name the symbol and its location** — e.g. "From #N: `RunEvalResult` exported by `src/evals/run-experiment.ts`" — rather than re-render the shape in prose. The implementing agent then derives the consumer-side type via `import type` (or the equivalent), and the type system enforces N=1 between producer and consumer at compile time. The carve-out is cross-language Consumes — when the consumer cannot import the producer's type (e.g. a workflow YAML consuming a TS-defined constant), name the shared identifier and treat the prose as the contract; downstream review (`/pre-merge` Dimension 1) is the safety net there.

Example — when the PRD's Implementation Decisions block locks a Drizzle schema:

```ts
// PRD #<prd-issue-number> §Implementation Decisions
export const dramaAssessments = sqliteTable("drama_assessments", {
  id: integer().primaryKey({ autoIncrement: true }),
  meetingId: integer("meeting_id").notNull().references(() => meetings.id),
  level: text().notNull(), // "routine" | "bumpy" | "heated" | "off-the-rails"
  confidence: real().notNull(),
  promptVersion: text("prompt_version").notNull(),
  model: text().notNull(),
  headline: text().notNull(),
  narrative: text().notNull(),
  evidenceQuotes: text("evidence_quotes", { mode: "json" }).$type<string[]>().notNull(),
  publishedAt: integer("published_at", { mode: "timestamp" }),
  createdAt: integer("created_at", { mode: "timestamp" }).notNull().default(sql`(unixepoch())`),
}, (t) => [uniqueIndex("drama_assessments_meeting_prompt_model_unique").on(t.meetingId, t.promptVersion, t.model)]);
```

…the slice's `Produces` should read:

> - `src/db/schema.ts` — adds `dramaAssessments` and `dramaCategoryScores` tables per PRD #<prd-issue-number> §Implementation Decisions. No re-render here; consume the PRD's contract shape verbatim.

If the slice introduces additional types not locked by the PRD (e.g. an internal `DramaLevel` union the schema's `level` column will be narrowed to in TS), render those in the slice's `Produces` as the slice is the owning home.

The boundary map prevents the most common multi-slice failure: slices that are each internally correct but don't actually wire together because they made incompatible assumptions about interfaces.

**Orthogonality test:** After drafting the boundary map, check each slice: if this slice's internal implementation changed entirely, would any other slice need to change? If yes, the boundary is drawn wrong — either merge the coupled slices, or extract the shared concern into its own slice. Slices that pass this test can be implemented in any order by Ralph without risk of one slice's decisions breaking another.

**Scope completeness check:** After the orthogonality test, verify each slice's Produces list accounts for the full scope of that slice — not just the happy path. For each slice, check:

- Does it include error handling paths (not just success)?
- Does it include loading/empty/partial states (for UI slices)?
- Does it account for edge cases named in the PRD's Rabbit Holes section?
- Does the Produces list include all type exports that downstream slices consume?

If a forgotten deliverable surfaces, either add it to the current slice's Produces or create a new slice for it. Don't leave it as an implicit assumption — unscoped work is invisible to Ralph.

**Consumes plausibility check:** For each `Consumes` entry that references an already-closed upstream slice — not a sibling slice still being planned in this PRD — verify the claimed symbol exists at the declared path *before* finalizing this slice's boundary map. This catches upstream boundary-map drift during planning instead of execution.

For each such Consumes entry:

- Check the declared file path exists.
- Grep for the named export.
- If the declaration includes a shape (e.g. "Layer", "Zod schema", "React component"), confirm the export actually matches that shape, not just the name.

If a gap is found, don't just document it in this slice's `Consumes`. File a post-hoc correction comment on the upstream closed issue and note the correction in this slice's "Assumptions from Parent PRD" section as a verified check.

**Estimate-readiness check:** After the scope completeness check, verify that the decomposition made the work more legible rather than more performative. For each slice, ask:

- Is this slice small enough that its uncertainty can be explained in one or two sentences?
- Does the slice expose observable outputs and interfaces, or is it still hiding unknowns behind vague labels?
- If the decomposition revealed materially more work than the PRD implied, should the plan be reshaped or re-estimated before issue creation?

Do not force detailed schedule estimates into each issue. The goal is to surface slices that are still too ambiguous for credible commitment.

**Shape-sufficiency check.** For each new contract this slice introduces in `Produces` (Zod schema, exported type or interface, function signature, storage method parameter shape, server-function return type), confirm the *shape* is rendered as code in the issue body, not just the *name* listed. If only the name appears, render the shape inline before finalizing the boundary map.

The audit is binary: shape present or absent. Shape correctness is evaluated at the §6 Quiz step; shape presence is the prerequisite that lets the Quiz step do its job.

This check exists because PRDs frequently sketch contract shapes in prose without locking them in code form (e.g., "exports a Zod schema with category_scores keyed by …"). The Contract-shape rendering subsection above covers two cases — PRD locked in code (reference by location) and slice introduces a contract the PRD did not lock (re-render). The third case — PRD sketched in prose without locking in code — is where this check fires when the rule's "did not lock" wording is read narrowly. The slice issue is the durable contract `/execute` and `/pre-merge` inherit; the shape lives in code form in the slice's `Produces` regardless of the PRD's surface form for it.

**Dependency-graph diagram (optional).** Before finalizing the boundary map, if it has ≥2 Produces/Consumes entries across the decomposition, consider invoking `/mermaid` to render the cross-slice dependency graph as a flowchart and embed it alongside the existing lists. The lists stay authoritative — the diagram is a reading aid for reviewers and resumed-session agents who otherwise have to mentally compile the bullet structure back into a graph. Skip the diagram when the boundary map is thin enough that the lists are already the cleanest rendering.

### 5. Derive the Coverage Matrix

**Skip this step when the PRD decomposes into a single slice.** For single-slice PRDs the boundary map + user-stories-covered field already serve as coverage; a matrix would be pure ceremony.

For multi-slice PRDs, derive a requirement-to-slice coverage view from the PRD's existing user stories. This is a **derived view**, not a hand-maintained spec — its single source of truth is the PRD issue body. You regenerate the view from the PRD; you never edit the view directly.

For each user story in the PRD, classify and map it:

| PRD commitment | Classification | Covered by |
|----------------|----------------|------------|
| User story 1 ("As a user, I want X so that Y") | **Must** | Slice #2, Slice #4 |
| User story 2 ("As a user, I want Z so that W") | Want | Slice #3 |
| User story 3 ("As a user, I want Q so that R") | ~Tilde | — (consciously cut) |

- **Must** — comes from the PRD's *Must-haves* section. Every Must needs at least one covering slice before issue creation.
- **Want** — comes from the PRD's *Nice-to-haves (~)* section. Unmapped Wants are acceptable but get surfaced as a warning at the Quiz step.
- **~Tilde** — a Nice-to-have the user is consciously cutting under the appetite. No coverage required; silent.

**Unmapped-Must backpressure.** Before proceeding to the Quiz step, halt if any Must is unmapped. Surface the list of unmapped Musts to the user and ask whether to (a) add a new slice covering them, (b) extend an existing slice to cover them, or (c) demote the commitment in the PRD (edit the PRD issue body, then regenerate this view). Do not create slice issues with unmapped Musts.

**Matrix-generation difficulty is a PRD-quality signal.** If many commitments resist clean classification or mapping — several Musts that could plausibly belong to any of three slices, or several items that feel like they are neither Must nor Want — *report this to the user*, do not push structure back into the PRD. Per Shape Up's roughness discipline, PRDs stay rough; matrix noise is the signal that the PRD is under-specified in one area, and the fix is PRD refinement (or accepting the rough classification), not PRD restructuring to feed the matrix.

### 6. Quiz the User

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses
- **Produces**: key outputs from the boundary map
- **Consumes**: key inputs from upstream slices

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?
- Do the boundary map interfaces look right? (Are these the right function signatures, types, endpoints?)
- Does every shared type, endpoint, or data model have exactly one owning slice in the Produces column?
- For every `Consumes` entry that references an already-closed upstream slice: does the symbol actually exist at the declared path, in the declared shape?
- Does the total decomposition feel proportionate to the stated appetite? A small-batch appetite (1-2 weeks) with 10+ slices or 4+ dependency levels suggests scope grew beyond what was shaped. A big-batch appetite with only 2-3 trivial slices suggests the shaping was too aggressive. If the decomposition feels disproportionate, which slices should be merged, split, or cut?
- Does any non-tracer slice project to **>500 LOC or >20 files** at ship time? If so, can it split without breaking the vertical seam? Tracer bullets are exempt — they intentionally cut wide to prove end-to-end architecture. (Soft signal sourced from convergent code-review research: Tacke's engagement-degradation thresholds (≤500 lines / ≤20 files) and Rigby's 11–78 LOC convergent median across 13 projects (Microsoft, AMD, Android, Chrome OS, Apache, Linux). The mirror size signal at review time is `/pre-merge` Dimension 11.)
- Did decomposition reveal any slice whose uncertainty is still too high for a credible commitment? If so, should it be split further, converted into a tracer bullet, or pushed back into PRD shaping?

- If the decomposition reveals the PRD needs reshaping — total scope materially exceeds the appetite, or a fundamental assumption is wrong — backtrack to `/write-a-prd`. If backtracking, close or comment on any already-created slice issues to mark them as superseded, and note in the PRD issue that it is being reshaped. Do not leave stale slice issues open for `/execute` to trust, whether they are being worked HITL or via Ralph's AFK loop.

Iterate until the user approves the breakdown.

### 7. Create the GitHub Issues

For each approved slice, create a GitHub issue using `gh issue create`. Use the issue body template below.

**Milestone propagation.** If the parent PRD belongs to a GitHub milestone (detected in Step 1), add `--milestone "<Milestone Name>"` to each `gh issue create` command so all slice issues are attached to the same milestone.

Create issues in dependency order (blockers first) so you can reference real issue numbers in the "Blocked by" field.

<issue-template>
## Parent PRD

#<prd-issue-number>

## What to Build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation. Reference specific sections of the parent PRD rather than duplicating content. The plain-language walkthrough of the feature lives in the parent PRD (see `references/writing-for-humans.md`); slice bodies stay contract-focused so they complement the PRD instead of restating it.

## Boundary Map

### Produces

What this slice creates that downstream slices depend on:

- `path/to/file.ts` → `functionName()`, `TypeName` (interface)
- `path/to/api/route.ts` → `POST /api/endpoint` (returns `ResponseType`)

### Consumes

What this slice needs from upstream slices:

- From #<issue-number>: `path/to/file.ts` → `importedFunction()`, `ImportedType`
- Refs #<spike-issue-number>: research spike pinning the recommended approach or library callback contract this slice's interface depends on (cite only when a spike issue exists for this PRD's research and the slice is bounded by a specific recommendation in it)

Or "Nothing — this is a leaf node (no upstream dependencies)." if no dependencies.

## Acceptance Criteria

Mark policy-driven criteria with `[POLICY]` — these encode current business rules that may change independently of the feature logic.

Mark quality-attribute criteria with `[QA-<attribute>]` where `<attribute>` is one of `PERF`, `RELI`, `SEC`, `USAB`, `MAINT`. These criteria carry the SMART quality-attribute discipline forward from the parent PRD's §Implementation Decisions — each must be specific, measurable, attainable, relevant, and time-bounded. Name the verification mechanism (load test, fault-injection test, log-capture assertion, etc.) so `/pre-merge` can verify implementation reflects the declared criterion.

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] `[POLICY]` Criterion that reflects a current business rule rather than a stable requirement
- [ ] `[QA-PERF]` p95 search latency under 200ms with 100 concurrent users, verified by load test in this slice

## Assumptions from Parent PRD

List the 3-5 key assumptions from the parent PRD that this slice depends on. Before starting execution, spend 60 seconds confirming each is still true. If any assumption has changed, this slice gets a targeted `/research` → mini-PRD cycle before proceeding. If all hold, execute directly.

**Caution — spike artifacts vs. spike verdicts.** If an assumption depends on a spike's captured *artifact* (recorded responses, sample payloads, challenge-page HTML, golden files the slice will commit as a fixture) rather than the spike's *verdict*, do not assert it is "still available" — `/prototype` deletes spikes by default, so the artifact is gone unless it was deliberately preserved (committed as a fixture or recorded as a re-capture recipe; see `/prototype` "Preserve reusable captured output"). Confirm the artifact was actually persisted before writing the assumption. If it was not, scope the slice to re-capture the artifact rather than asserting it persists — otherwise the assumption is false the moment it is written and only `/execute`'s Assumptions-validation gate catches it, late and mid-flight.

- [ ] [Assumption 1 — e.g., "Turso free tier still provides 5GB storage"]
- [ ] [Assumption 2 — e.g., "better-sqlite3 is still the Drizzle driver in use"]
- [ ] [Assumption 3 — e.g., "Vercel auto-detects TanStack Start"]

## Blocked by

- Blocked by #<issue-number> (if any)

Or "None — can start immediately" if no blockers.

## User Stories Addressed

Reference by number from the parent PRD:

- User story 3
- User story 7

</issue-template>

Do not close or modify the PRD *body*. A decomposition-linking comment on the parent PRD issue is allowed — and required (see next step).

### 8. Link decomposition on the parent PRD

After all slice issues are created, post a single comment on the parent PRD issue in the form:

```
Decomposed into: #<slice-1>, #<slice-2>, #<slice-3>
```

This comment is the signal downstream skills read to know the PRD has been decomposed. `/execute`'s issue-shape detection gate checks for it before accepting a PRD-shaped issue as a slice task.

If a PRD is re-decomposed later (e.g., after `/correct-course`), post a new `Decomposed into:` comment; readers consume the most recent one. Keeping only one authoritative comment is this skill's responsibility.

### 9. Summary

After all issues are created, present a summary showing:

- Total number of issues created
- Dependency graph (which issues block which)
- Suggested implementation order
- The boundary map across all slices (a quick-reference view of what flows between them)
- The Coverage Matrix (multi-slice PRDs only) — a quick-reference view of which PRD commitments each slice addresses
- If a milestone was used: "All N issues attached to milestone: [milestone name]"

This summary helps the user (and Ralph) understand the full picture before execution begins. The Coverage Matrix remains a derived view — future readers regenerate it from the PRD issue body and the slice issues' `User Stories Addressed` sections rather than reading a stored matrix file.

**At the end of the summary, print the runtime handoff line** naming the first unblocked slice (the slice with no `Blocked by` entry, or the lowest-numbered such slice when several qualify):

```
**Next session:** /execute #<first-unblocked-slice-number>
**Input:** the slice issue body
```

If every slice declares `Blocked by`, surface the dependency cycle to the user before printing — do not pick arbitrarily.

## Handoff

- **Expected input:** a shaped PRD issue with clear user stories, rabbit holes, and no-gos
- **Produces:** implementation-ready GitHub issues with dependency order, boundary maps, and milestone attachment when the parent PRD belongs to a milestone
- **Comes next by default:** `/execute` for implementation, with Ralph optionally running the AFK execution loop for unblocked slices
- **Feeds downstream:** `/pre-merge` uses the slice lineage and boundary maps to review plan-vs-actual code
