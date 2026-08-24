# Good and Bad Tests

## Good Tests

**Integration-style**: Test through real interfaces, not mocks of internal parts.

```typescript
// GOOD: Tests observable behavior
test("user can checkout with valid cart", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Characteristics:

- Tests behavior users/callers care about
- Uses public API only
- Survives internal refactors
- Describes WHAT, not HOW
- One logical assertion per test

## Bad Tests

**Implementation-detail tests**: Coupled to internal structure.

```typescript
// BAD: Tests implementation details
test("checkout calls paymentService.process", async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Red flags:

- Mocking internal collaborators
- Testing private methods
- Asserting on call counts/order
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means instead of interface

**Tautological tests**: The expected value is worked out the same way the code works it out, so the test passes by construction and can never disagree with the code.

```typescript
// BAD: The assertion recomputes the implementation's formula
test("calculates order total with tax", () => {
  const price = 100;
  const taxRate = 0.1;
  expect(calculateTotal({ price, taxRate })).toBe(price + price * taxRate);
});

// GOOD: The expected value comes from outside the code under test
test("calculates order total with tax", () => {
  // 100 + 10% tax = 110
  expect(calculateTotal({ price: 100, taxRate: 0.1 })).toBe(110);
});
```

The bad version is green forever — it *is* the implementation, written twice. If the domain rule is actually "tax applies after the discount," or the rate is a percentage rather than a fraction, the test is wrong in exactly the same way the code is and the bar stays green. It also survives every refactor and runs fast, so every coupling-based check passes it — which is why `SKILL.md` § Checklist Per Cycle carries a dedicated row for where the expected value came from. Expected values must come from an independent source — never from running the same algorithm the code runs. Which independent source is the next section.

## The Oracle

The thing that decides whether a run was correct has a name: the **oracle**. Every test has one, chosen deliberately or not, and each kind fails in its own way. Pick one on purpose.

- **Direct verification** — a known-good literal, a worked example lifted from the spec, or a value a domain expert confirmed. The default and the strongest; it fails only when the spec itself is wrong.
- **Redundant computation** — a reference implementation, a prior release, a second algorithm. Fails silently when the reference shares the fault: if the code is wrong in exactly the way the reference is wrong, the test stays green. A tautological test is this strategy at its worst, with the code under test standing in as its own reference.
- **Consistency check** — assert a property the output must satisfy rather than the output itself. A sort returns a permutation of its input in non-descending order; a parser's output re-serializes to the input it was given. Incomplete by construction — it rules out impossible outputs without proving the right one — but cheap and independent.
- **Data redundancy** — assert an identity relating several outputs. Prefer identities across *different* inputs over identities within one: `sin(a + b) = sin(a)cos(b) + cos(a)sin(b)` catches an implementation that `sin(x)² + cos(x)² = 1` misses, because the single-input form is satisfied by compensating errors in the two functions. An identity over floats needs a stated tolerance — `toBeCloseTo`, never `toBe`. The multi-input form above disagrees with strict equality on roughly 70% of random input pairs, and a test that flakes on arithmetic noise teaches the team to ignore the suite faster than no test at all.

**When no independent literal exists** — the output is opaque, or the arithmetic is too involved to state by inspection — do not fall back to recomputing the formula. Reach for triangulation (§ Evident Data) when the output is numeric and the generalization is what you're pinning down; reach for a consistency check or a multi-input identity when it isn't. Recomputation is not the last resort. It is the one option that is never available.

## A test name is a claim the assertion must be able to falsify

§ *The Oracle* is about where the expected value comes from. This is the same distinction one level up: the name is the **test requirement**, the assertion is the **oracle**, and nothing in the suite makes them agree. A name that claims more than the body checks is a specification that passes forever — and test names are read as specifications, so the overstatement is what gets quoted into docs.

The rule is structural, not attentional. **When a test name claims a *relationship* — below a ceiling, at least N, within the cap, rejects empty, before the deadline — the assertion must reference the other side of that relationship, imported from wherever it is defined. Otherwise narrow the name to what is actually asserted.**

**One carve-out, and it is § *The Oracle* reasserting itself over this rule: when the value under test is itself derived from the bound** — `const DEFAULT_MAX_TOKENS = NON_STREAMING_CEILING - 1` — **importing the bound re-runs the implementation's own formula, and the assertion becomes true by construction.** That is redundant computation with the code standing in as its own reference: green through every ceiling change, including one that breaks the budget. Narrow the name instead. A relationship the code computes cannot be checked by a test that computes it the same way.

```typescript
// BAD: the name claims a relationship to a bound; the body pins one literal
test("max_tokens defaults below the non-streaming ceiling", () => {
  expect(client.maxTokens).toBe(16_000);
});

// GOOD (a): keep the claim, import the bound — the two reconcile themselves
import { NON_STREAMING_CEILING } from "@vendor/client/limits";

test("max_tokens defaults below the non-streaming ceiling", () => {
  expect(client.maxTokens).toBeLessThan(NON_STREAMING_CEILING);
});

// GOOD (b): keep the literal, narrow the name to what it proves
test("max_tokens defaults to 16000", () => {
  expect(client.maxTokens).toBe(16_000);
});

// GOOD (c): make both claims, separately — the pin and the bound each get a test
test("max_tokens defaults to 16000", () => {
  expect(client.maxTokens).toBe(16_000);
});

test("the default max_tokens is below the non-streaming ceiling", () => {
  expect(client.maxTokens).toBeLessThan(NON_STREAMING_CEILING);
});
```

All three are honest. Choosing between them is a trade, not a ranking, and (a) costs something the phrase "keep the claim" hides: **it stops pinning the literal.** `toBeLessThan(CEILING)` passes for `100` as readily as for `16_000`, so a default that silently regresses stays green — and pinning the budget was the entire reason the test was written. (b) keeps the pin and gives up the claim; it is right when the bound has no importable definition. (c) gives up neither and costs one test, which makes it the default whenever the bound *is* importable — one logical assertion per test (§ *Good Tests*), one claim per name. What is never available is the bad version: a name asserting a constraint that no run can violate.

**The operational check, at RED.** A red bar is not enough. Change the value the name is about and confirm the test goes red **for the reason the name gives** — read the failure message and check it describes the relationship the name claims, not some incidental collision. Two failure modes this catches that a bare "did it go red?" does not:

- **The test never ran.** Reachability comes before the oracle: a check switched off by a rename, a skipped block, or a filter that no longer matches reports green while asserting nothing. Confirm the mutated test executed and failed, rather than confirming the suite was not fully green.
- **It reddened for the wrong reason.** A literal-pinning test reds when *any* edit touches the literal, which looks identical to reddening because a bound was crossed. If the failure message names only the literal, the name's claim is still unfalsifiable.

**Scope.** Most test names make no relational claim — `"user can checkout with valid cart"` names an outcome, not a bound, and this rule has nothing to say about it. Apply it when the name asserts a comparative, a limit, or a rejection — the three shapes whose truth depends on something the body may never mention.

## Evident Data

Test values should make the relationship between input and expected output **obvious in the test body**. The reader should see the arithmetic, not reverse-engineer it from magic numbers.

```typescript
// BAD: Where does 42 come from? The inputs are hidden inside `order`.
test("calculates order total", () => {
  expect(calculateTotal(order)).toBe(42);
});

// GOOD: Inputs are visible, expected value is an independent literal
test("calculates order total with tax", () => {
  // 100 + 10% tax = 110
  expect(calculateTotal({ price: 100, taxRate: 0.1 })).toBe(110);
});
```

Evident data means the **inputs and the relationship** are visible — not that the expected value is computed from them. Deriving the expectation from the inputs (`toBe(price + price * taxRate)`) fixes the magic number by writing a tautological test, which is the worse of the two failures: a magic number is merely unreadable, while a recomputed expectation is unfalsifiable.

When no obvious literal exists — the arithmetic is too involved to state by inspection — do not fall back to recomputing the formula. Use Beck's **Triangulation**: add a second case with different values that a single constant cannot satisfy, forcing the implementation to generalize.

If there is no conceptual difference between two values, use the simpler one. A test checking email lowercasing needs `"ALICE@TEST.COM"`, not a realistic 40-character address.

## Cover Both Failure Directions

When a function reduces messy input to a boolean or category — a *classifier* that emits a **fact** ("robots.txt blocks all crawlers," "this page is covered by the sitemap," "this link is broken") — "test through the public interface" is satisfied by a single happy-direction test, and that is not enough. A classifier breaks in the *failure* direction: a `User-agent: BadBot` / `Disallow: /` group read as "blocks *all* crawlers," a trailing-slash URL read as "not covered," a third-party 403 read as "broken." The red phase must include **both** guards before you write the implementation:

- **False-positive guard** — an input that looks like it should trigger the fact but must **not**.
- **False-negative guard** — an input that **should** trigger the fact but in a non-obvious form.

```typescript
// Happy direction only — passes, but the failure direction is unguarded
test("detects robots.txt blocking all crawlers", () => {
  expect(blocksAllCrawlers("User-agent: *\nDisallow: /")).toBe(true);
});

// False-positive guard — a different bot is blocked, * stays permissive
test("does not report block-all when only a non-* agent is blocked", () => {
  expect(blocksAllCrawlers("User-agent: BadBot\nDisallow: /")).toBe(false);
});

// False-negative guard — the fact must still fire in a non-obvious form
test("treats trailing-slash drift as covered", () => {
  expect(coveredBySitemap("https://x.com/page", ["https://x.com/page/"])).toBe(true);
});
```

**High-stakes case — the fact feeds a consumer that trusts it.** When the emitted fact is handed downstream as *ground truth* — most sharply, an LLM judge that treats a mechanical layer's output as trusted facts it will not re-derive — a *wrong* fact is worse than a *missing* one: it actively misleads rather than merely omits. Write the over-claim (false-positive) guard first; it is the path that turns a fault into an error the moment the consumer trusts the fact.

```typescript
// BAD: Bypasses interface to verify
test("createUser saves to database", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// GOOD: Verifies through interface
test("createUser makes user retrievable", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```
