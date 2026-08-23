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
   // The type lies. Both arguments are `string`, so raw markup can arrive
   // where extracted reading text is required, and nothing says otherwise.
   declare function containsVerbatim(needle: string, haystack: string): boolean;

   // Provenance is now part of the type. A second provenance cannot arrive
   // silently — it has to be constructed, and construction is the one place
   // the rule lives.
   type ReadingText = string & { readonly __brand: "ReadingText" };
   const toReadingText = (html: string): ReadingText =>
     extractText(html) as ReadingText;

   declare function containsVerbatim(needle: string, haystack: ReadingText): boolean;
   ```

   Pick the shape by what the callee has to do:

   | The rule you need | Reach for |
   |---|---|
   | One legal kind; everything else is a construction error | Branded type + a single constructor (`toReadingText`) |
   | Several legal kinds, and the callee must handle each | Discriminated union (`{ kind: "reading-text"; value: string } \| { kind: "raw-html"; value: string }`) |
   | The value already crosses a parse boundary | `z.string().brand<"ReadingText">()` — parse once at the edge |
   | "At least one", "exactly one of these combinations" | Reshape so the invalid shape is unbuildable (`[T, ...T[]]`, an explicit combination union) rather than checking at runtime |

   **Construct once, at the boundary; never re-validate downstream.** A defensive re-check inside a function that already receives the branded type is not extra safety — it re-teaches every reader that the type cannot be trusted, which is the state this technique exists to leave.

   **What this does to the tests.** A whole category disappears. You do not need a test that this function rejects an out-of-range value, because the type rejects it before the test would run. What you test instead is the constructor: it accepts what should be accepted and returns an error for what should not. One test at the boundary replaces N tests at N call sites — which is the same trade the technique makes in the production code.

   **Proportion.** This is not "brand every primitive." Wlaschin calls one maximal form of the trick — F# units of measure, `5.0<kg>` — "probably design overkill" for his own domain, and frames the guideline as proportionate use rather than maximal type ceremony. Reach for it when the constraint is one a *downstream* function depends on and cannot re-derive — provenance, validation status, units, cardinality. A value that never crosses a function boundary does not need a brand, and a rule that reads as "wrap every string" will be ignored or, worse, followed.

   **Changing an existing type is a separate move** with its own discipline — see [refactoring.md](refactoring.md) § *Change the type first, then let the compiler enumerate the call sites*.

   **No automated check backs this section, and that is the honest answer.** `CLAUDE.md` rule (b) says to pin a skill's checkable claims about tool behavior; this section makes none — it is a design judgment about a downstream repo's types, which nothing in this repo can assert. What *is* pinned by `scripts/test-widened-domain-tell.sh` is that the tell above is stated at both the implement-time site (here) and the review-time site (`pre-merge/review-checklist.md` Dimension 6), so deleting it from one does not leave the other's cross-reference quietly false.

   **Review-cadence note.** Added from one triggering incident (a downstream verbatim-quote check widened from extracted page text to raw HTML, with the parameter renamed `pageText` → `haystack` in the same diff — issues #266/#268, 2026-08-22) plus principle grounds (Wlaschin Ch. 6). If after a reasonable sample of slices the tell above fires <10% of the time on diffs that had no other reported issue, cut it back to the quote and the table rather than leaving it as ceremony — and delete `scripts/test-widened-domain-tell.sh` in the same change, which pins the tell, the proportionality bound, and this section's cross-reference to the review-time half. Retiring the prose without the suite turns the retirement red.
