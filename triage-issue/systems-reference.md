# Systems Reference for Bug Diagnosis

## System Archetypes

Read failures at three levels before matching an archetype:

- **Event** — What just happened?
- **Pattern** — What has been happening repeatedly or over time?
- **Structure** — What rules, delays, incentives, handoffs, or missing feedback loops make the pattern likely?

If you can only describe the event, you have not yet reached the leverage point.

Match the failure pattern to one of these recurring structures. If a match is found, the fix should address the structure, not just the symptom.

### Shifting the Burden

**Pattern:** A workaround eased the symptom, reducing pressure to implement the fundamental fix. Over time, the fundamental solution atrophied — became harder to implement, lost organizational knowledge. The symptom returned in a different form.

**In code:** A try/catch that swallows errors. A retry loop that masks a connection leak. A cache that hides a slow query instead of fixing the query. A feature flag that permanently bypasses broken logic.

**Diagnostic question:** Has a workaround been in place so long that the original problem is now harder to fix than when the workaround was introduced?

**Fix direction:** Remove the workaround and implement the fundamental fix. If the fundamental fix is too expensive now, document the debt explicitly.

### Drift to Low Performance

**Pattern:** A standard eroded gradually because each small deviation was individually acceptable. Over time, the accumulated drift crossed a threshold.

**In code:** Test coverage that declined from 90% to 40% one skip at a time. Response times that crept from 200ms to 2s as features were added. Error handling that became inconsistent as different developers added different patterns.

**Diagnostic question:** Was there a standard or threshold that used to be met but isn't anymore? When did the drift start?

**Fix direction:** Re-establish the standard as an enforced constraint (test, linter rule, monitoring alert), not just a convention.

### Fixes That Fail

**Pattern:** A previous fix had a delayed side effect that caused the current bug. The delay between cause and effect made the connection invisible.

**In code:** A performance optimization that introduced a race condition. A security fix that broke a downstream integration. A refactor that changed behavior in an edge case nobody tested.

**Diagnostic question:** What changed in the last 2–4 weeks that could have caused this? Check `git log` for the affected code path.

**Fix direction:** Address both the original problem and the side effect. If they conflict, the fix needs a design that satisfies both constraints simultaneously.

### Tragedy of the Commons

**Pattern:** Multiple callers share a resource, each individually rational, but collectively they exhaust it.

**In code:** Multiple services writing to the same database table without coordination. Multiple features consuming the same rate-limited API. Shared mutable state accessed from multiple code paths without synchronization.

**Diagnostic question:** Is this resource shared? How many consumers does it have? Do they coordinate?

**Fix direction:** Add coordination (quotas, locks, queuing) or partition the resource so consumers don't compete.

### Escalation

**Pattern:** Two subsystems compete, each responding to the other's actions by intensifying its own. The system oscillates or grows unbounded.

**In code:** Retry storms between services. Cache invalidation cascades. Auto-scaling that triggers more load which triggers more scaling.

**Diagnostic question:** Are two parts of the system reacting to each other in a way that amplifies rather than dampens?

**Fix direction:** Break the escalation loop with a circuit breaker, backoff, or shared state that makes both sides aware of the system-wide situation.

---

## Leverage Points

When choosing a fix, prefer higher-leverage interventions. Lower numbers = stronger leverage.

| Level | Type | Code Example | When to Use |
|-------|------|-------------|-------------|
| #12 | Parameters | Change a timeout, adjust a threshold | Isolated incident, no structural pattern |
| #11 | Buffers | Increase queue depth, add capacity | Resource exhaustion without structural cause |
| #8 | Balancing feedback | Health check, circuit breaker, rate limiter | System lacks self-correction |
| #7 | Reinforcing feedback | Break retry storm, stop cascade | System amplifies its own failures |
| #6 | Information flows | Add logging/monitoring to blind spot | System couldn't observe its own failure |
| #5 | System rules | Linter rule, invariant assertion, constraint | Same bug class keeps recurring |
| #4 | Self-organization | Extract deep module, create boundary | Code structure makes bug class inevitable |
| #3 | System goals | Redefine what "correct" means | Subsystem optimizes for wrong thing |

Most bug fixes default to #12 (tweak a parameter) or #11 (add capacity). When the structural diagnosis identifies an archetype, the appropriate fix is usually #8–#4.

---

## 5-Phase Diagnostic

1. **Observe** — Describe the failure as a causal chain: event A triggered B which caused C
2. **Map** — Identify stocks (accumulated state), flows (rates of change), feedback loops (self-reinforcing or self-correcting chains), and delays (where cause and effect are separated in time)
3. **Diagnose** — Match to an archetype above. If no match, the bug may be genuinely isolated.
4. **Intervene** — Choose a leverage level. Design the fix at that level.
5. **Adapt** — After fixing, check: did the fix create a new feedback loop? Could it have delayed side effects? (If yes, note it — this prevents the next Fixes That Fail cycle.)
