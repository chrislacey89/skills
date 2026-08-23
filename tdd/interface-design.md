# Interface Design for Testability

Good interfaces make testing natural:

1. **Accept dependencies, don't create them**

   ```typescript
   // Testable
   function processOrder(order, paymentGateway) {}

   // Hard to test
   function processOrder(order) {
     const gateway = new StripeGateway();
   }
   ```

2. **Return results, don't produce side effects**

   ```typescript
   // Testable
   function calculateDiscount(cart): Discount {}

   // Hard to test
   function applyDiscount(cart): void {
     cart.total -= discount;
   }
   ```

3. **Small surface area**
   - Fewer methods = fewer tests needed
   - Fewer params = simpler test setup

4. **Make an illegal input unconstructable, not merely detectable**

   A validity constraint enforced by a runtime check protects exactly one call site. Every other function that receives the same value has to re-check it, or trust a convention nothing enforces — and conventions get forgotten. Move the constraint into the *type* and it holds for the life of the value, for every caller, with no test per call site.

   > "This is an example of the important design guideline: 'make illegal states unrepresentable.'"
   > — Wlaschin, *Domain Modeling Made Functional*, Ch. 6

   The argument behind it, in paraphrase: validating after construction is strictly weaker than making invalid construction impossible, *because a runtime check only protects the one call site it guards*. Every other function that touches the value re-checks it or trusts an unenforced convention.

   **The tell: a widened input domain with no type change.** A parameter starts accepting a second kind of value, and its type does not move, because both kinds were already the same primitive — two `string`s, two `number`s, two `Record`s. The sharpest signal in a diff is a **rename from a domain-specific parameter name to a neutral one** (`pageText` → `haystack`, `userEmail` → `value`, `validatedOrder` → `data`). That rename is not merely a missing comment: it *deletes the only place the precondition was recorded*. When you see it, ask what the function is now allowed to receive that it was not before, and whether anything downstream still assumes the narrower thing.

   This is the trigger to act on. It is narrow, visible in a diff, and does not require judging every primitive in the codebase.

   **The TypeScript translation.** Wlaschin's smart constructor is a branded type plus a constructor that is the only way to make one:

   ```typescript
   declare function extractText(html: string): string;

   // BEFORE — the type lies. Both arguments are `string`, so raw markup can
   // arrive where extracted reading text is required, and nothing says otherwise.
   // (Named `_before` on purpose: two `declare function`s sharing one name are an
   // *overload set*, not a replacement, so the loose signature would keep
   // accepting the raw string and the example would disprove nothing.)
   declare function containsVerbatim_before(needle: string, haystack: string): boolean;

   // Provenance is now part of the type. A second provenance cannot arrive
   // by accident — reaching this parameter without going through the
   // constructor takes a deliberate `as`, which is greppable.
   declare const brand: unique symbol;
   type Brand<T, TBrand> = T & { [brand]: TBrand };
   type ReadingText = Brand<string, "ReadingText">;

   // A *conversion* constructor: extraction cannot fail, so this one has no
   // rejecting path to test. See the table below for the validating shape.
   const toReadingText = (html: string): ReadingText =>
     extractText(html) as ReadingText;

   // AFTER — the only signature. A raw `string` is now a compile error here.
   declare function containsVerbatim(needle: string, haystack: ReadingText): boolean;
   ```

   **Use a `unique symbol` for the brand key, not a string property.** `string & { readonly __brand: "ReadingText" }` is the common shorthand and it is weaker in two checkable ways. `keyof` on it resolves to `number | "__brand" | "anchor" | … ` — the brand key is public, so it reaches autocomplete and any mapped type over the brand. And a *different* module declaring a structurally identical `__brand` type is silently accepted where yours is required, because the shapes match; two independently declared `unique symbol`s do not, and the compiler says so (`Property '[brand]' is missing`). Zod does the same thing: `.brand()` is backed by an exported `unique symbol` (`$brand` in `zod/v4/core/core.d.ts`, `BRAND` in `v3/types.d.ts`), so a zod-branded type leaks no public key either. Its caveat is the opposite one — because every module imports *that same* symbol, two modules independently writing `z.string().brand<"ReadingText">()` produce the **same** type and are mutually assignable. Tag distinctly if you need them kept apart.

   **What branding does and does not buy.** It moves bypassing the constructor from *free* to *one deliberate `as`*. `"raw <script>" as ReadingText` still compiles, on both shapes. That is the honest ceiling: the type stops silent assignment, not determined circumvention — and it makes every bypass a greppable token in review rather than an invisible one.

   Pick the shape by what the callee has to do:

   | The rule you need | Reach for |
   |---|---|
   | One legal kind; everything else is a construction error | Branded type + a single constructor (`toReadingText`) |
   | Several legal kinds, and the callee must handle each | Discriminated union (`{ kind: "reading-text"; value: string } \| { kind: "raw-html"; value: string }`) |
   | The value already crosses a parse boundary | `z.string().brand<"ReadingText">()` — parse once at the edge |
   | "At least one", "exactly one of these combinations" | Reshape so the invalid shape is unbuildable (`[T, ...T[]]` for a non-empty array, an explicit combination union) rather than checking at runtime |
   | The constraint can only be decided at runtime | A **validating** constructor returning a discriminated result (`{ ok: true; value: ReadingText } \| { ok: false; error: string }`), or an assertion function — `function assertIsReadingText(v: string): asserts v is ReadingText`. Prefer the `function` declaration: an arrow assigned to an un-annotated `const` declares fine and then fails at every **call site** with `TS2775`, *"Assertions require every name in the call target to be declared with an explicit type annotation"* |

   **Construct once, at the boundary; never re-validate downstream.** A defensive re-check inside a function that already receives the branded type is not extra safety — it re-teaches every reader that the type cannot be trusted, which is the state this technique exists to leave.

   **What this does to the tests.** A whole category disappears. You do not need a test that this function rejects an out-of-range value, because the type rejects it before the test would run. What you test instead is the constructor — and *which* constructor decides what there is to test. A **validating** constructor has both directions: it accepts what should be accepted and returns an error for what should not. A **conversion** constructor like `toReadingText` has only one, because no input can fail it; the coverage it buys is that every call site now names the converted type. Either way, one test at the boundary replaces N tests at N call sites — which is the same trade the technique makes in the production code.

   **Proportion.** This is not "brand every primitive." Wlaschin calls one maximal form of the trick — F# units of measure, `5.0<kg>` — "probably design overkill" for his own domain, and frames the guideline as proportionate use rather than maximal type ceremony. Reach for it when the constraint is one a *downstream* function depends on and cannot re-derive — provenance, validation status, units, cardinality. A value that never crosses a function boundary does not need a brand, and a rule that reads as "wrap every string" will be ignored or, worse, followed.

   **Changing an existing type is a separate move** with its own discipline — see [refactoring.md](refactoring.md) § *Change the type first, then let the compiler enumerate the call sites*.

   **No automated check backs this section, and that is the honest answer.** `CLAUDE.md` rule (b) says to pin a skill's checkable claims about tool behavior; this section makes none — it is a design judgment about a downstream repo's types, which nothing in this repo can assert. What *is* pinned by `scripts/test-widened-domain-tell.sh` is that the tell above is stated at both the implement-time site (here) and the review-time site (`pre-merge/review-checklist.md` Dimension 6), so deleting it from one does not leave the other's cross-reference quietly false.

   **Review-cadence note.** Added from one triggering incident (a downstream verbatim-quote check widened from extracted page text to raw HTML, with the parameter renamed `pageText` → `haystack` in the same diff — issues #266/#268, 2026-08-22) plus principle grounds (Wlaschin Ch. 6). If after a reasonable sample of slices the tell above fires <10% of the time on diffs that had no other reported issue, cut it back to the quote and the table rather than leaving it as ceremony. **This is the full-retirement case**, and it needs `scripts/test-widened-domain-tell.sh` edited in the same change — the assertions on the tell, the proportionality bound, and this section's cross-reference to the review-time half all go red otherwise. **Edit it; do not delete it.** The suite also pins the § resolver across every `tdd/` cross-reference, including two that predate this rule, and it is invoked by name from `lefthook.yml` and `.github/workflows/validate-skills.yml` — a missing file exits 127 there, so deleting it fails every push and every PR. (Retiring only the *review-time* half is the other case; `pre-merge/review-checklist.md` Dimension 6 carries it.)
