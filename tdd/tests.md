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

The bad version is green forever — it *is* the implementation, written twice. If the domain rule is actually "tax applies after the discount," or the rate is a percentage rather than a fraction, the test is wrong in exactly the same way the code is and the bar stays green. It also survives every refactor and runs fast, so no other check in this skill will catch it. Expected values must come from an independent source: a known-good literal, a worked example from the spec, a domain expert, or a reference implementation. Never from running the same algorithm the code runs.

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
