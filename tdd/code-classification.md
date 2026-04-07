# Code Classification

Before writing any test, classify the code under test using these two axes:

|  | Few collaborators | Many collaborators |
|---|---|---|
| **High complexity / domain significance** | **Domain model** → unit test heavily | **Overcomplicated** → refactor first |
| **Low complexity / domain significance** | **Trivial** → skip testing | **Controllers** → integration test only |

## Classification Checklist

1. **Does this code make decisions?** (branching, calculations, state transitions) — If no → trivial or controller.
2. **Does this code talk to out-of-process dependencies?** (database, message bus, HTTP calls) — If yes AND it makes decisions → overcomplicated.
3. **Is the overcomplicated quadrant empty?** — If no → refactor before testing.

## The Overcomplicated Quadrant

Code that mixes domain logic with infrastructure orchestration cannot be tested well. Mocking your way to coverage produces brittle tests that break on every refactor. The fix is structural, not more test scaffolding.

**Diagnostic:** If you need mocks to reach business logic, the code is overcomplicated.

### Humble Object

Extract all decision logic into a pure domain class with no out-of-process dependencies. Leave a thin orchestration shell (the humble object) that coordinates I/O with no business logic.

```typescript
// OVERCOMPLICATED: decisions + I/O fused
async function changeEmail(userId, newEmail, db, messageBus) {
  const user = await db.getUser(userId);
  const company = await db.getCompany(user.companyId);
  if (user.email !== newEmail) {
    user.email = newEmail;
    user.type = newEmail.endsWith(company.domain) ? "employee" : "customer";
    company.numberOfEmployees += user.type === "employee" ? 1 : -1;
    await db.save(user);
    await db.save(company);
    await messageBus.send(`email-changed:${userId}:${newEmail}`);
  }
}

// SPLIT: pure domain (unit-testable) + thin controller (integration-testable)
class User {
  changeEmail(newEmail, companyDomain, companyEmployeeCount) {
    if (this.email === newEmail) return;
    this.email = newEmail;
    this.type = newEmail.endsWith(companyDomain) ? "employee" : "customer";
    // Domain event instead of direct messageBus call
    this.events.push({ type: "email-changed", userId: this.id, newEmail });
    return this.type === "employee" ? 1 : -1; // employee count delta
  }
}
```

The domain class has zero out-of-process collaborators. Test it with plain values.

### CanExecute/Execute

When the domain must validate before acting, move the check into the domain model:

```typescript
class User {
  canChangeEmail(newEmail) {
    if (!newEmail.includes("@")) return "Invalid email format";
    if (this.isDeactivated) return "Deactivated users cannot change email";
    return null; // valid
  }

  changeEmail(newEmail, companyDomain) {
    assert(this.canChangeEmail(newEmail) === null);
    // ... business logic
  }
}
```

The controller calls `canChangeEmail()` and routes on the result. Business-rule edge cases become fast unit tests on the domain class — no integration test needed.

### Domain Events

When a domain operation should trigger an out-of-process side effect, append a domain event (a value object) to a collection instead of calling the dependency directly. The controller dispatches events after saving.

Test the event collection — a plain value comparison — instead of asserting a mock was called. This converts a fragile communication-based test into a robust output-based test.

---

For the full framework including the pick-two tension and precondition testing guidelines, see `~/.claude/library/books/vladimir-khorikov-unit-testing/references/code-classification.md`.
