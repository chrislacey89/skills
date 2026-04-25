# Review Checklist

Used by `/pre-merge` during Phase 3. Eight dimensions, each independent. For every finding, classify as Observation, Suggestion, or Concern using the severity rules at the bottom.

---

## 1. Deep Modules (Ousterhout)

**Principle:** Modules should have small interfaces hiding deep implementations. A module's interface complexity should be justified by the implementation complexity it hides.

**Violation patterns:**
- Shallow wrappers — a module that exists only to call one other module's method
- Pass-through methods — functions that accept arguments and forward them with little or no transformation
- Excessive export surface — a module exporting many functions/types relative to its implementation size (e.g., 10 exports for 50 lines of implementation)
- Information leakage — two modules that both know about the same internal data structure, protocol detail, or file format

**Out of scope:** Whether specific interfaces are well-designed (that's `/design-an-interface`, invoked during `/write-a-prd`).

---

## 2. Vertical Slice Integrity

**Principle:** Each slice cuts through all layers end-to-end (schema, API, UI, tests). Implementation follows red-green-refactor rhythm, not batch-by-layer.

**Violation patterns:**
- Horizontal layer commits — all schema changes in one commit, all API changes in another, all UI changes in a third
- Batch test-then-implement — a cluster of test-only commits followed by a cluster of implementation-only commits, instead of interleaved red-green pairs
- Slices that touch only one layer (e.g., a "types-only" slice or "tests-only" slice) without a clear infrastructure reason

**Out of scope:** Whether tests are correct or sufficient (that's `/tdd` during implementation).

---

## 3. State Discipline

**Principle:** State lives in GitHub (issues) or in code (`docs/solutions/`, skills). No ad-hoc filesystem state.

**Violation patterns:**
- New state files: `.gsd/`, `STATE.md`, `PLAN.md`, `CONTEXT.md`, `ROADMAP.md`, `SUMMARY.md`, `continue.md`, `UAT.md`
- New state directories: `docs/brainstorms/`, `docs/specs/`
- Any new persistent markdown file that tracks state outside of GitHub issues or `docs/solutions/`

Research files produced by `/research` live in the per-user archive at `~/.claude/research/<repo-slug>/…`, outside the repo. They are not a state-discipline violation because they never enter the working tree.

**Out of scope:** Git history cleanliness (pre-commit hooks handle formatting and linting).

---

## 4. Boundary Map Contracts

**Principle:** Each slice's Produces and Consumes declarations are contracts. The implementation should match them, and upstream slices this PR consumes from must have actually shipped what their Produces claimed.

**Only runs when a PRD with slice issues was provided.**

**Violation patterns:**
- Declared Produces that don't exist — a function, type, or endpoint listed in a slice's Produces section that wasn't implemented, or was implemented at a different path or name
- Undeclared cross-slice imports — code that imports from another slice's module without a corresponding Consumes declaration in the issue body
- Signature drift — a function exists but its signature (parameters, return type) differs from what was declared
- Missing Produces — a slice exports something that downstream slices depend on, but it wasn't listed in Produces
- Phantom dependencies — a package added to `package.json` (or equivalent manifest) in this diff but never imported in any source file. Front-loaded decisions from `research.md` or the PRD that were recommended but never materialized in the implementation. These should be removed from the manifest before subsequent slices inherit them as implicit constraints.
- Upstream-produced but unverified — this PR consumes a symbol from an already-closed upstream slice, but the symbol doesn't exist at the declared path or has a different shape than declared. This is not the reviewee's defect, but it should still be flagged as a Concern with a recommendation to correct the upstream issue.
- Deletion orphans — this PR (or an upstream slice it consumes from) declared a `### Deletes` section and removed the module, but consumer surfaces the module owned remain referenced in the merged tree: DOM data-attributes, CSS class names, global event names, storage keys, route names, or feature-flag names. The DOM and CSS silently ignore dead references, so this slips past imports-only verification. The remedy is to sweep the consumers or restore the module — not to leave inert wiring in place.
- Spec-rot masquerading as drift — the code correctly reflects external reality (the actual npm registry, the actual third-party API, the actual pinned version), but the declared spec in `research.md`, the PRD, or the slice boundary map does not. The code looks "drifted" only because the spec aged. The corrective action is to update the spec via `/correct-course` or a `research.md` amendment — not to change the code. Flag as `Concern (spec-rot)` rather than `Concern (code drift)` so the reviewer's forward route is legible.

**Verification procedure (not eyeballing):**

**Spec-reality check (externally-resolvable declarations only).** Before judging code against the spec, confirm the spec still matches external reality. This scopes to declarations that resolve outside the repo — third-party packages, public API symbols, and pinned versions — not intra-repo paths. The goal is to distinguish *code drift* from *spec rot* so the reviewer's corrective attention points at the right artifact.

1. **Package names.** For each third-party package named in the slice Produces/Consumes, the PRD stack list, or `research.md` that the diff touches, confirm it resolves on the registry (`npm view <pkg> version` or the equivalent for the project's package manager). If the declared package does not exist, the spec is the drifted artifact — classify as `Concern (spec-rot)`, not `Concern (code drift)`, and direct the remedy to `/correct-course` or a `research.md` amendment.
2. **Named public API symbols.** For each Consumes entry that references a third-party symbol (not an intra-repo path), confirm the symbol still exists at the declared import path in the version pinned in the lockfile. A scratch `tsc --noEmit` import or a short docs lookup is sufficient.
3. **Version skew.** Compare `installed_versions_snapshot` in the research archive frontmatter (see `research/SKILL.md`) to the versions resolved in the current lockfile. If a major version has moved, note it in the review and ask the reviewer to confirm the relevant research claims still hold before judging the code.

If all three pass, the spec is trustworthy and the per-entry checks below proceed normally. If any fail, the reviewer is seeing spec rot and should not recommend code changes.

For each `Produces` entry in the PR's slice issue:
1. Parse the declared path + symbol (e.g. `src/pipeline/services/ScraperService.ts → EgovScraper, EgovScraperLive`).
2. Confirm the path exists in the merged tree and exports the named symbols — grep or `rg` for the export.
3. If the declaration includes a shape hint (e.g. "Layer", "interface", "Zod schema", "React component"), confirm the exported symbol matches the shape, not just the name. Run `tsc --noEmit` against the declared import if unclear.

For each `Consumes` entry referencing an already-closed upstream slice, run the same check against the upstream's declared Produces. If the upstream export is missing or shape-drifted, note it and flag the upstream issue for correction.

**For deletion orphan surfaces (only when the diff or any consumed upstream slice contains a `### Deletes` section):** Infer the deleted module's external consumer surfaces from the `Deletes` bullet notes or from `git show` of the deleted path. Grep the merged tree for each surface type across all source-text files — templates, source code, styles, config, docs. Zero matches required to pass. Non-zero matches: flag as Concern with the matched path and line. This mirrors the Tier 1 build-time check in `/execute`; its value here is catching surfaces the author missed at implementation time, now verified against the full merged tree.

**Out of scope:** Whether the interfaces are well-designed or deep (Dimension 1 covers shallowness). Verifying that the upstream slice's *close state* was correct at merge time is handled by the Verification procedure above.

---

## 5. Coverage Matrix Reconciliation (multi-slice PRD PRs only)

**Principle:** Every PRD Must-commitment should be covered by at least one shipped slice. Wants may be consciously cut. ~Tildes are already cut by definition.

**Procedure.** If this PR closes the last slice in a multi-slice PRD, regenerate the Coverage Matrix: read the PRD issue body, classify each user story (Must / Want / ~Tilde), and check each slice issue's `User Stories Addressed` section to see which slice covers which commitment. Compare against the set of *merged* slices.

This is a **reconciliation test, not a gate.** Block only on unmapped Musts. Warn on unmapped Wants. Accept unmapped ~Tildes silently.

**Violation patterns:**
- **Unmapped Must (Blocker):** A Must-commitment in the PRD has no merged slice covering it, and no `Scope Notes` entry explains why. This blocks merge.
- **Unmapped Want (Concern/Warning):** A Want-commitment in the PRD has no merged slice covering it. Surface as a warning — the scope hammer may have cut it consciously; confirm with the user and add a `Scope Notes` entry if so.
- **Renegotiation not recorded:** A commitment was consciously cut or added mid-cycle but the PRD issue body was not edited to reflect the new state. The matrix is a derived view; the PRD is the single source of truth. Flag for update.

**Out of scope:** Single-slice PRDs (no matrix derived). Boundary-map contract checks (Dimension 4). Whether Musts were correctly classified during `/prd-to-issues` (that conversation happens there, not here).

---

## 6. Test Quality

**Principle:** Tests verify behavior through public interfaces, not implementation details. Tests should survive internal refactors unchanged.

**Violation patterns:**
- Mocking internal collaborators — mocking modules that are part of the same system (not external boundaries) to test a unit in isolation
- Testing private methods — reaching into module internals instead of testing through the public API
- Asserting call counts or call order for managed dependencies (non-boundary collaborators)
- Opaque test data — magic numbers or unclear fixtures where evident data would make the test self-documenting
- Implementation-coupled test names — names that describe HOW ("calls database twice") instead of WHAT ("user can checkout with valid cart")

**Out of scope:** Test coverage percentage, whether enough tests exist, whether tests pass (pre-commit hooks verify this).

---

## 7. docs/solutions/ Adherence

**Principle:** Past lessons should inform current work. If the implementation touches areas with documented solutions, it should follow those patterns or consciously update them.

**Violation patterns:**
- Contradicting a documented pattern — implementing something that a `docs/solutions/` entry explicitly warns against, without updating the solution document
- Ignoring a relevant prevention strategy — a solution's Prevention section describes a practice that applies to this code, but the code doesn't follow it
- Stale solution consumption — relying on a `volatile` solution that is older than 90 days or whose Shelf Life condition appears met

**Out of scope:** Whether new lessons should be captured (that's `/compound` after merge).

---

## 8. Runtime Initialization (Schema/Config/CLI PRs only)

**Principle:** Code that builds and passes tests is not necessarily code that runs correctly. When a slice changes database schema, migrations, environment configuration, server initialization, or ships a CLI/orchestration entrypoint with a dry-run mode, the actual production path must work — not just the build, the test suite, or the dry-run shortcut.

**Only runs when the diff includes changes to schema files, migration files, environment config, server startup code, or a CLI/orchestration entrypoint with a dry-run or preview mode.**

**Violation patterns:**
- Missing migration — schema code was changed but no corresponding migration file was generated or committed
- Untested cold boot — new routes or server functions were added but no evidence the dev server was started and the routes loaded (e.g., the `/execute` verification checklist doesn't mention Tier 2.5 runtime checks)
- In-memory test divergence — tests use in-memory databases with their own migration setup, so they pass even when the real dev database is missing tables or columns
- Missing environment variable — code references a new env var that isn't in `.env.example`, `.env.local`, or documented in the PR
- Silent env-var fallback — code reads an optional env var and falls back to a stub or no-op when unset, without logging a warning or failing loudly. Production operators have no discoverable way to learn the var exists until something visibly breaks (or worse, silently does nothing).
- Placeholder wired as production default — a function named or documented as a placeholder, stub, TODO, or follow-up is used as the default binding in a production code path without a fail-fast guard. If a non-dry run would silently produce garbage, **flag it as a Concern, not a Suggestion**.
- Custom wrapper type on a library callback return — the slice defines its own return type for a library-provided callback (agent hooks, middleware, proxy, tool handlers, render props, lifecycle methods) and returns a value typed against the wrapper instead of the library's declared return. TypeScript's excess-property check does not run on returns of typed variables, so any field the library's signature does not declare is silently dropped at runtime. **Verification procedure — not eyeballing.** Grep the installed type definition (`node_modules/<library>/**/*.d.ts`) for the callback's return type. For each field on the wrapper that the call site actually populates, confirm it appears in the library's declared shape. If a research archive entry exists for this feature, prefer its `callback_contracts_snapshot` (see `research/SKILL.md` Phase 1.25) as the pinned source. Cite the `.d.ts` file and line in the finding. Excess fields are a Concern, not a Suggestion — the bug is runtime-invisible and will not be caught by tests that don't assert against the library's post-callback state.

**Out of scope:** Whether the schema design is optimal (that's Dimension 1). Whether tests are sufficient (that's Dimension 6).

---

## 9. Fix Completeness (Bug-Fix PRs only)

**Principle:** A correction removes the defect; a workaround suppresses the failure while the defect remains. Corrections are complete; workarounds are technical debt that must be tracked.

**Only runs when the PR is linked to a bug-fix issue (not a feature).**

**Violation patterns:**
- Workaround-as-correction — a fix that adds a null check, try/catch, or conditional bypass around a failure without removing the code defect that produces the corrupted state
- Missing regression test — a bug fix without a test that would have caught the original failure
- Lone instance fix — the defect pattern exists in multiple locations but only one was fixed; search for structurally similar code

**Out of scope:** Whether the fix is architecturally optimal (that's Dimension 1). Whether tests are well-written (that's Dimension 6).

---

## Severity Classification

- **Observation:** A pattern worth noting but no principle is violated. The reviewer noticed something the developer should be aware of. Example: "The auth module now exports 7 functions — not a violation, but approaching the threshold where consolidation might help."

- **Suggestion:** A principle is partially stressed. Improvement is possible but the current code is defensible. Example: "Two test names describe implementation details ('calls API twice') — renaming to behavior descriptions would improve readability."

- **Concern:** A clear principle violation with specific evidence from the diff. Cite the principle, show the code, explain why it matters. Example: "The `formatResponse` function in `utils/format.ts` is a pass-through that forwards its arguments to `buildResponse` with no transformation — this is a shallow wrapper (Dimension 1)."
