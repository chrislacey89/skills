# Review Checklist

Used by `/pre-merge` during Phase 3 in all three modes — author-mode, reviewer-mode, and loop-mode. Eleven dimensions, each independent. For every finding, classify as Observation, Suggestion, or Concern using the severity rules at the bottom.

In **loop-mode**, every finding below gets a durable row in the PR's `## Review Disposition Ledger` (`/pre-merge` Phase 5) rather than scrolling past in a terminal. The dimensions and severity rules are unchanged — but each finding is checked against the tree and carries that evidence into the ledger, so the operator reads a claim with proof beside it. Loop-mode records and hands back; it does not act on findings.

In **reviewer-mode** (`/pre-merge --pr <number>`), findings here become PR comment drafts via `references/comment-craft.md` — the severity tier maps onto a Comment Signal prefix (`Concern` → `needs change:` / `needs rework:` / `align:`, `Suggestion` → `levelup:`, `Observation` → drop or `nitpick:`) and each blocking comment is shaped through Triple-R. The dimensions and severity rules below are unchanged across modes; comment-craft only governs how the findings are presented to the author.

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
- Dead parallel shape after lockstep delete — this PR (or an upstream slice it consumes from) declared a `### Deletes` section and retained or added exports on a shared module (context fields, builder return-type fields, interface or type members, schema fields) alongside the deletion. For each such export, grep the merged tree for non-self-reference reads; zero matches → flag as `Concern`. The retained-but-unread export widens the import contract, so a future cleanup becomes a breaking change rather than a silent removal. Dead-export linters (`knip`, `ts-prune`, TypeScript `noUnusedLocals`) miss this case because the export is read by the type itself and looks live to the tool.
- Spec-rot masquerading as drift — the code correctly reflects external reality (the actual npm registry, the actual third-party API, the actual pinned version), but the declared spec in `research.md`, the PRD, or the slice boundary map does not. The code looks "drifted" only because the spec aged. The corrective action is to update the spec via `/correct-course` or a `research.md` amendment — not to change the code. Flag as `Concern (spec-rot)` rather than `Concern (code drift)` so the reviewer's forward route is legible.
- Unverified SMART quality-attribute criterion — a SMART quality-attribute criterion declared in the PRD's §Implementation Decisions or carried into a slice issue's Acceptance Criteria as `[QA-PERF]`, `[QA-RELI]`, `[QA-SEC]`, `[QA-USAB]`, or `[QA-MAINT]` has no corresponding implementation evidence in the diff — no load test, no fault-injection test, no log-capture assertion, no monitoring hook, no assertion the criterion named as its verification mechanism. Either the criterion is reflected in implementation, or the PR description states a clearly-stated reason it's not (deferred to a named follow-up slice, descoped via a No-go addendum on the PRD body). A SMART criterion filed and forgotten defaults to whatever the agent happened to implement, which is the failure mode Wiegers' SMART discipline exists to prevent.

**Verification procedure (not eyeballing):**

**Spec-reality check (externally-resolvable declarations only).** Before judging code against the spec, confirm the spec still matches external reality. This scopes to declarations that resolve outside the repo — third-party packages, public API symbols, and pinned versions — not intra-repo paths. The goal is to distinguish *code drift* from *spec rot* so the reviewer's corrective attention points at the right artifact.

1. **Package names.** For each third-party package named in the slice Produces/Consumes, the PRD stack list, or `research.md` that the diff touches, confirm it resolves on the registry (`npm view <pkg> version` or the equivalent for the project's package manager). If the declared package does not exist, the spec is the drifted artifact — classify as `Concern (spec-rot)`, not `Concern (code drift)`, and direct the remedy to `/correct-course` or a `research.md` amendment.
2. **Named public API symbols.** For each Consumes entry that references a third-party symbol (not an intra-repo path), confirm the symbol still exists at the declared import path in the version pinned in the lockfile. A scratch `tsc --noEmit` import or a short docs lookup is sufficient. Additionally, if a `Consumes` import resolves through a different subpath of the same package than `installed_versions_snapshot` records (e.g. `from "pkg"` → `from "pkg/http"`, or any `pkg/<sub>` → `pkg/<other-sub>`), classify as `Concern (runtime-affecting subpath swap)` even when types still satisfy. Sibling subpaths of multi-runtime packages (`@libsql/client` vs `/http`; `react-dom` vs `/client` vs `/server`; `drizzle-orm/libsql` vs `/better-sqlite3`; `@effect/platform` vs `-node`) are runtime-distinct; a swap that goes green on type-check has not been verified at runtime and needs explicit justification, not a free pass.
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
- Opaque or tautological test data — evident data fails in two directions and both are violations. An **opaque expectation** (`expect(calculateTotal(order)).toBe(42)`) hides the inputs, so no reader can check the number; the fix is to show the inputs, *not* to derive the expectation from them. A **recomputed expectation** (`expect(calculateTotal({ price, taxRate })).toBe(price + price * taxRate)`) works the expected value out the way the code works it out, so the test passes by construction and can never disagree with the implementation — a consistently wrong formula stays green through every refactor. Flag both, and note the asymmetry: an opaque expectation is unreadable, a recomputed one is unfalsifiable. The fix for the second is an expected value from an independent source — see `tdd/tests.md` § The Oracle for the four strategies and the failure mode of each. Do not reflexively recommend Beck's Triangulation: it is the right fallback only when the output is numeric and the generalization is what's being pinned down, and a consistency check or a multi-input identity is the answer when it isn't. **Review-cadence note.** The recomputed-expectation half was added on principle grounds (Khorikov Ch. 11 "leaking domain knowledge") plus an upstream audit (mattpocock/skills v1.1.0) that surfaced the inverted example this bullet previously mirrored — not from a downstream incident. If after a reasonable sample of PRs it fires <10% of the time on diffs that had no other reported issue, remove it rather than leave it as ceremony.
- Implementation-coupled test names — names that describe HOW ("calls database twice") instead of WHAT ("user can checkout with valid cart")
- Fact-emitting heuristic with an untested failure direction — the diff adds or changes a module that reduces input to a boolean/category and whose output is consumed downstream as *trusted ground truth* (most sharply, a mechanical layer feeding an LLM judge in a hybrid mechanical-then-LLM dimension), and its tests cover only the happy direction. Confirm both directions are tested: an input that must **not** trigger the fact (over-claim guard) and one that **should** in a non-obvious form (under-claim guard). **Severity asymmetry** (Nygard fault→error→failure — a wrong fact becomes an error the moment the consumer trusts it): an untested **over-claim** path is a **Concern**; an untested **under-claim** path is a **Suggestion**. Cite the specific untested input class (e.g. "a `User-agent`-scoped block read as block-all"), not "needs more tests." **Review-cadence note.** Added from one triggering incident (mimir SEO mechanical layer — three failure-direction defects shipped green, 2026-06-23) plus principle grounds (Cohen phase-injection economics, Nygard fault→error→failure). If after a reasonable sample of PRs this bullet fires <10% of the time on diffs that had no other reported issue, remove it rather than leave it as ceremony.

**Out of scope:** Test coverage percentage and whether enough tests exist *in general*, whether tests pass (pre-commit hooks and `/qa` own these) — **except** the fact-emitting-heuristic failure-direction case above, whose missing test points at a latent contract defect rather than a coverage gap.

---

## 7. docs/solutions/ Adherence

**Principle:** Past lessons should inform current work. If the implementation touches areas with documented solutions, it should follow those patterns or consciously update them.

**Violation patterns:**
- Contradicting a documented pattern — implementing something that a `docs/solutions/` entry explicitly warns against, without updating the solution document
- Ignoring a relevant prevention strategy — a solution's Prevention section describes a practice that applies to this code, but the code doesn't follow it
- Stale solution consumption — relying on a `volatile` solution that is older than 90 days or whose Shelf Life condition appears met

**Out of scope:** Whether new lessons should be captured (that's `/compound` after merge).

---

## 8. Runtime Initialization & Production-Runtime Parity (Schema/Config/CLI/Deploy-runtime PRs only)

**Principle:** Code that builds and passes tests is not necessarily code that runs correctly. When a slice changes database schema, migrations, environment configuration, server initialization, ships a CLI/orchestration entrypoint with a dry-run mode, or deploys to a runtime that differs from the one its tests run in, the actual production path must work — not just the build, the test suite, the dry-run shortcut, or the test runtime. Green tests certify behavior in the environment the *tests* model; when that environment is more permissive than production, or a seam is mocked away from the real deployed artifact, green is not evidence of working (Twelve-Factor Factor X dev/prod parity; Continuous Delivery's smoke-against-production-like-environment).

**Only runs when the diff includes changes to schema files, migration files, environment config, server startup code, a CLI/orchestration entrypoint with a dry-run or preview mode, OR ships code whose deploy runtime differs from its test runtime / static assets whose paths resolve at deploy time / behavior bounded by a platform limit the test runtime does not enforce.**

**Violation patterns:**
- Missing migration — schema code was changed but no corresponding migration file was generated or committed
- Untested cold boot — new routes or server functions were added but no evidence the dev server was started and the routes loaded (e.g., the `/execute` verification checklist doesn't mention Tier 2.5 runtime checks)
- In-memory test divergence — tests use in-memory databases with their own migration setup, so they pass even when the real dev database is missing tables or columns
- Missing environment variable — code references a new env var that isn't in `.env.example`, `.env.local`, or documented in the PR
- Silent env-var fallback — code reads an optional env var and falls back to a stub or no-op when unset, without logging a warning or failing loudly. Production operators have no discoverable way to learn the var exists until something visibly breaks (or worse, silently does nothing).
- Placeholder wired as production default — a function named or documented as a placeholder, stub, TODO, or follow-up is used as the default binding in a production code path without a fail-fast guard. If a non-dry run would silently produce garbage, **flag it as a Concern, not a Suggestion**.
- Custom wrapper type on a library callback return — the slice defines its own return type for a library-provided callback (agent hooks, middleware, proxy, tool handlers, render props, lifecycle methods) and returns a value typed against the wrapper instead of the library's declared return. TypeScript's excess-property check does not run on returns of typed variables, so any field the library's signature does not declare is silently dropped at runtime. **Verification procedure — not eyeballing.** Grep the installed type definition (`node_modules/<library>/**/*.d.ts`) for the callback's return type. For each field on the wrapper that the call site actually populates, confirm it appears in the library's declared shape. If a research archive entry exists for this feature, prefer its `callback_contracts_snapshot` (see `research/SKILL.md` Phase 1.25) as the pinned source. Cite the `.d.ts` file and line in the finding. Excess fields are a Concern, not a Suggestion — the bug is runtime-invisible and will not be caught by tests that don't assert against the library's post-callback state.
- Client component reaching for a server-only SDK at AC implementation time — the diff contains a `"use client"` file (or any module that resolves into the client bundle) that imports an SDK whose initialization reads server-held credentials (`process.env.<SECRET>`, server-only API keys) or uses a Node-only runtime. The acceptance criterion ships a user-visible half (fallback rendering, the configured value flips) but the observability or side-effect half it declared is unreachable from the boundary it was anchored to. **Verification procedure — not eyeballing.** Grep the imported module's source or its declared package entry point for server-only signals (`process.env.<SECRET>`, the `"server-only"` marker import, Node-only API usage like `fs`/`crypto.createPrivateKey`/`node:` builtins). If found, flag as Concern with a recommendation to relocate the emission point to a server boundary that already has the SDK initialized, or add an explicit client→server route to scope. Common SDK shapes: server-side observability (Langfuse Node, OpenTelemetry server SDK, Sentry server, Datadog APM server libs), server-held analytics keys, anything that must hold a secret to function. **Review-cadence note.** Added on principle grounds plus one triggering incident (fulcrum PR #55, 2026-05-11). If after a reasonable sample of PRs the bullet fires <10% of the time on diffs that had no other reported issue, remove it rather than leave it as ceremony.
- Test-runtime more permissive than deploy runtime — a pinning test passes under the test runtime (miniflare, jsdom, Node) but the production runtime (workerd, the browser, an edge/Lambda runtime) enforces a limit or lacks an API the test never exercised, so the assertion is structurally blind. E.g. a PBKDF2 iteration count asserted `>= 600_000` passes in miniflare but throws `NotSupportedError` at verify time in workerd, which hard-caps iterations at 100,000 — every login 500s in production while the test stays green. **Verification procedure — not eyeballing.** Identify any seam the test mocks or runs under a more permissive runtime than production; re-assert against the production runtime's actual limit (run the released artifact under `wrangler dev` / the platform emulator, or pin the documented platform cap in the test). Flag as Concern — the failure is 100% reproducible in production and invisible to the suite.
- Deploy-layout / absolute-asset divergence — the slice ships a published or static artifact, and a publish/copy step or asset reference resolves paths at deploy time that the test seam mocked away. Absolute-path `<link>`/`<script>`/`<img>` references (`/_astro/*`, `/assets/*`, fonts, favicon) that 404 from the deployed public root render the page unstyled even though the HTML returns 200 and the file-copy unit test (against a mocked filesystem) passed. **Verification procedure — not eyeballing.** Confirm every absolute sub-resource the deployed page requests exists at the deployed layout's public root, not just in the build output — load the real artifact and check the asset requests return 200, or grep the publish/copy step for each referenced asset root. Flag as Concern.
- Mocked owned-seam blindness (root-fix pointer) — a unit passed only because the seam that would fail in production (a platform crypto API, the filesystem, the real deploy copy) was mocked. Per GOOS "only mock types you own," an external library/platform type should be wrapped in a thin owned adapter and integration-tested, not mocked at the call site. Name the over-mock as the upstream root fix; `/execute` Tier 2.7 (Production-Runtime Parity) is the safety net that catches the gap, the owned adapter is the cure. **Review-cadence note (parity patterns).** The three patterns above (test-runtime permissiveness, deploy-layout / absolute-asset divergence, mocked owned-seam blindness) were added on convergent grounds (Continuous Delivery, Twelve-Factor Factor X, Release It! "Design for Deployment", GOOS) plus one triggering incident (mimir audit-publish slices #8/#9, 2026-06-25 — both green, both broke only in the deployed workerd runtime). Same falsification rule: if after a reasonable sample of PRs they fire <10% of the time on diffs that had no other reported issue, remove them rather than leave them as ceremony.

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

## 10. Surgical Scope

**Principle:** Every changed hunk should trace to the stated task. A diff is the answer to a question; the question was not "what else could be improved?"

Beck's *Two Hats* (TDD, refactoring-catalog): refactor and feature-add are two hats; never wear both at once, because if something breaks you can no longer attribute the cause. Hunt & Thomas (Pragmatic Programmer): each pass must have a single purpose — interleaving makes failures unattributable. The check belongs at review time because by then the diff exists and the question "does this hunk belong?" is concrete rather than aspirational.

**Applies to every diff regardless of PRD status.** Boundary Map Contracts (Dimension 4) and Coverage Matrix Reconciliation (Dimension 5) check plan-vs-actual *between slices*, and only fire when a PRD exists. This dimension checks scope drift *inside a single diff* — drive-by reformatting, speculative additions, adjacent fixes that weren't asked for — and runs whether or not the work went through `/prd-to-issues`.

**Stated task source.** The "stated task" is, in priority order: the slice issue body, the PRD issue body, the bug issue or QA report, or — for one-off branches — the commit messages and branch name. If no stated task can be reconstructed, note that and skip the dimension; do not synthesize one.

**Violation patterns:**
- **Drive-by reformatting** — quote-style swaps, whitespace rewrites, brace-style changes in files the task didn't require touching
- **Speculative additions** — type hints, docstrings, new abstractions, or parameter additions that the task didn't ask for and no test demands
- **Adjacent fix-while-here** — patching a different bug or removing unrelated dead code in the same diff (file separately, even if the adjacent fix is correct)
- **Style drift** — applying a personal style preference (preferred quote, preferred test framework idiom, preferred import order) to existing code the task didn't require touching
- **Refactor-and-feature interleave** — Beck's "shame, shame": a behavior change and a structural cleanup in the same commit, so a reviewer cannot tell whether a hunk changed behavior or only moved it. Where the repo preserves individual commits on base, it also leaves any future bisect unable to attribute regressions

**Verification procedure — cited hunks, not yes/no.** A finding under this dimension must cite the file path and the hunk's starting line. *"Looks scope-creepy"* is not a finding; *"`utils/format.ts:42–58` adds type hints and renames `result` to `formatted` — neither is mentioned in the task statement"* is. If the dimension produces zero findings on a non-trivial diff, that is a real outcome — do not invent findings to fill the section, and do not rubber-stamp it (Meadows policy resistance: required sections that go unused get filled with filler; the cited-hunk requirement is the mitigation).

**Out of scope:** Whether the diff is architecturally good (that's Dimension 1). Whether the scope of the *task itself* was right (that's `/shape` and `/write-a-prd`). Whether unmapped commitments exist between slices (that's Dimension 5).

**Review-cadence note.** This dimension was added without a triggering incident, on principle grounds (Beck, Hunt & Thomas). If after a reasonable sample of PRs it produces zero or one finding per PR on average, it is policy-resistant filler and should be removed rather than left as ceremony.

---

## 11. Review-friendly Size

**Principle:** Code review effectiveness is bounded by reviewer engagement, and the variable with the strongest empirical support across independent research streams is diff size. Cohen et al.'s 2,500-review Cisco dataset shows defect detection drops sharply past 100–300 LOC per session and a 60-minute ceiling; Tacke documents engagement degradation past ~500 lines or ~20 files; Rigby's 13-project study (Microsoft, AMD, Android, Chrome OS, Apache, Linux) found medians of 11–78 LOC. Three independent streams converging on one variable.

**Applies to every diff regardless of PRD status.** Tracer-bullet slices (the first slice in a PRD's decomposition that intentionally cuts wide to prove end-to-end architecture) are exempt — the signal does not fire on them. Identify the tracer from the slice issue body or its position in the PRD's `Decomposed into:` comment; if ambiguous, assume non-tracer rather than silently exempting.

**Three-band severity (drawn from convergent literature, not invented):**

- **Observation: >300 LOC.** Cohen's upper bound. Above this, defect-detection rate begins to fall; worth naming so the author knows reviewer attention is being spent.
- **Suggestion: >500 LOC OR >20 files.** Tacke's engagement threshold. Above either, reviewer focus tends to collapse into momentum approval. Recommend splitting into stacked PRs or scheduling reviewer attention across multiple sittings.
- **Concern: >800 LOC AND multi-domain scope.** The catastrophic-engagement zone where all three sources agree review effectiveness degrades severely. "Multi-domain" means three or more conceptually independent areas in the same diff (e.g., schema + API + UI + migration; or backend handler + frontend component + infra config).

**Distinct from Dimension 10 (Surgical Scope).** Dimension 10 asks whether each hunk traces to the task — its remedy is *trim*. Dimension 11 asks whether the diff is reviewable in one session — its remedy is *split into stacked PRs* or *chunk reviewer attention across multiple sittings*. A diff can be tightly scoped (no Dim 10 finding) and still oversize (Dim 11 fires); a diff can be small but scope-creepy (Dim 10 fires, Dim 11 silent). Both can fire on the same diff for different reasons.

**Verification procedure — cited counts, not impressions:**

1. Read the diff stat from Phase 1 — `git diff "$BASE_BRANCH...HEAD" --stat` in author-mode, or the file count and additions/deletions from `gh pr view --json` / `gh pr diff` in reviewer-mode. Cite the actual numbers in the finding.
2. Compare line count and file count against the bands above. Use additions + deletions, not net change — a 600-add / 400-delete diff is a 1,000-line review burden, not a 200-line one.
3. If the Concern band may fire, enumerate the conceptual areas touched (e.g., "schema, API handler, React component, migration script") and confirm three or more independent areas before classifying as Concern. Two-domain >800 LOC diffs land at Suggestion, not Concern.
4. If the slice is the tracer (per the issue body or PRD decomposition order), suppress the finding regardless of band; note in the findings output that the dimension was suppressed under the tracer exemption so the suppression is visible rather than silent.

**Out of scope:** Whether the *task* was right-sized (that's `/shape` and `/write-a-prd`). Whether each hunk traces to the task (that's Dimension 10). Whether the slice was decomposed correctly upstream (that's `/prd-to-issues` Step 6, which carries the mirror size question at planning time). Defect-density metrics or per-reviewer pace tracking — Cohen explicitly warns against weaponizing review metrics for performance evaluation.

**Review-cadence note.** Added on convergent empirical grounds (Cohen 2006, Tacke 2024, Rigby 2013), not from a triggering incident. Same falsification rule as Surgical Scope: if after a reasonable sample of PRs the signal fires <10% of the time on diffs that had no other reported review issue, it is policy-resistant filler and should be removed rather than left as ceremony.

---

## Severity Classification

- **Observation:** A pattern worth noting but no principle is violated. The reviewer noticed something the developer should be aware of. Example: "The auth module now exports 7 functions — not a violation, but approaching the threshold where consolidation might help."

- **Suggestion:** A principle is partially stressed. Improvement is possible but the current code is defensible. Example: "Two test names describe implementation details ('calls API twice') — renaming to behavior descriptions would improve readability."

- **Concern:** A clear principle violation with specific evidence from the diff. Cite the principle, show the code, explain why it matters. Example: "The `formatResponse` function in `utils/format.ts` is a pass-through that forwards its arguments to `buildResponse` with no transformation — this is a shallow wrapper (Dimension 1)."
