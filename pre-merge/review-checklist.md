# Review Checklist

Used by `/pre-merge` during Phase 3. Seven dimensions, each independent. For every finding, classify as Observation, Suggestion, or Concern using the severity rules at the bottom.

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
- New state directories: `docs/brainstorms/`, `docs/plans/`, `docs/specs/`
- Leftover `research.md` that should be deleted after ship (or flagged for deletion if the feature hasn't shipped yet)
- Any new persistent markdown file that tracks state outside of GitHub issues or `docs/solutions/`

**Out of scope:** Git history cleanliness (pre-commit hooks handle formatting and linting).

---

## 4. Boundary Map Contracts

**Principle:** Each slice's Produces and Consumes declarations are contracts. The implementation should match them.

**Only runs when a PRD with slice issues was provided.**

**Violation patterns:**
- Declared Produces that don't exist — a function, type, or endpoint listed in a slice's Produces section that wasn't implemented, or was implemented at a different path or name
- Undeclared cross-slice imports — code that imports from another slice's module without a corresponding Consumes declaration in the issue body
- Signature drift — a function exists but its signature (parameters, return type) differs from what was declared
- Missing Produces — a slice exports something that downstream slices depend on, but it wasn't listed in Produces

**Out of scope:** Whether the interfaces are well-designed or deep (Dimension 1 covers shallowness).

---

## 5. Test Quality

**Principle:** Tests verify behavior through public interfaces, not implementation details. Tests should survive internal refactors unchanged.

**Violation patterns:**
- Mocking internal collaborators — mocking modules that are part of the same system (not external boundaries) to test a unit in isolation
- Testing private methods — reaching into module internals instead of testing through the public API
- Asserting call counts or call order for managed dependencies (non-boundary collaborators)
- Opaque test data — magic numbers or unclear fixtures where evident data would make the test self-documenting
- Implementation-coupled test names — names that describe HOW ("calls database twice") instead of WHAT ("user can checkout with valid cart")

**Out of scope:** Test coverage percentage, whether enough tests exist, whether tests pass (pre-commit hooks verify this).

---

## 6. docs/solutions/ Adherence

**Principle:** Past lessons should inform current work. If the implementation touches areas with documented solutions, it should follow those patterns or consciously update them.

**Violation patterns:**
- Contradicting a documented pattern — implementing something that a `docs/solutions/` entry explicitly warns against, without updating the solution document
- Ignoring a relevant prevention strategy — a solution's Prevention section describes a practice that applies to this code, but the code doesn't follow it
- Stale solution consumption — relying on a `volatile` solution that is older than 90 days or whose Shelf Life condition appears met

**Out of scope:** Whether new lessons should be captured (that's `/compound` after merge).

---

## 7. Fix Completeness (Bug-Fix PRs only)

**Principle:** A correction removes the defect; a workaround suppresses the failure while the defect remains. Corrections are complete; workarounds are technical debt that must be tracked.

**Only runs when the PR is linked to a bug-fix issue (not a feature).**

**Violation patterns:**
- Workaround-as-correction — a fix that adds a null check, try/catch, or conditional bypass around a failure without removing the code defect that produces the corrupted state
- Missing regression test — a bug fix without a test that would have caught the original failure
- Lone instance fix — the defect pattern exists in multiple locations but only one was fixed; search for structurally similar code

**Out of scope:** Whether the fix is architecturally optimal (that's Dimension 1). Whether tests are well-written (that's Dimension 5).

---

## Severity Classification

- **Observation:** A pattern worth noting but no principle is violated. The reviewer noticed something the developer should be aware of. Example: "The auth module now exports 7 functions — not a violation, but approaching the threshold where consolidation might help."

- **Suggestion:** A principle is partially stressed. Improvement is possible but the current code is defensible. Example: "Two test names describe implementation details ('calls API twice') — renaming to behavior descriptions would improve readability."

- **Concern:** A clear principle violation with specific evidence from the diff. Cite the principle, show the code, explain why it matters. Example: "The `formatResponse` function in `utils/format.ts` is a pass-through that forwards its arguments to `buildResponse` with no transformation — this is a shallow wrapper (Dimension 1)."
