# When to Mock

Mock at **system boundaries** only — but not all boundaries are equal.

### Managed vs. Unmanaged Dependencies

**Managed dependencies** (your database, your file store) — use real test instances, never mock. Your schema is an implementation detail; no external system observes your table structure. Mocking the database hides real integration failures.

**Unmanaged dependencies** (message bus, SMTP, third-party APIs) — mock at the system edge. The communication pattern is externally observable by other systems, so you verify the interaction contract.

**Diagnostic:** Can another system observe this interaction? If yes → mock it. If no → use the real thing.

Other system boundaries:
- Time/randomness — inject as values at the operation boundary, not via static fields
- File system — use real instances unless the operation is destructive or non-deterministic

### CQS and Test Doubles

Commands (outgoing interactions that change state) → mocks are appropriate. Verify the interaction.
Queries (incoming data the SUT consumes) → stubs only. **Never assert on stubs** — that is overspecification.

### Don't mock

- Your own classes/modules
- Internal collaborators
- Anything you control
- Managed dependencies (your database)

## Designing for Mockability

At system boundaries, design interfaces that are easy to mock:

**1. Use dependency injection**

Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over generic fetchers**

Create specific functions for each external operation instead of one generic function with conditional logic:

```typescript
// GOOD: Each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: Mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach means:
- Each mock returns one specific shape
- No conditional logic in test setup
- Easier to see which endpoints a test exercises
- Type safety per endpoint
