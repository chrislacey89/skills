# Destination Check

A shared reference consumed by `/qa` (lightweight bug intake) and `/triage-issue` (deep diagnosis). Both skills ask the same anchoring question — *name the destination the fix's effect must reach* — and consult the signal table below to decide whether to firmly recommend `/research` Phase 0 before filing.

The check addresses one structural failure mode: a lightweight-intake bug issue proposes a fix at the **source location** of a defect that doesn't deliver the system-level outcome the issue was filed to achieve, because no precondition gate verifies the proposed fix's effect-boundary is reachable in the target codebase. The audit verified the source is wrong; nothing verified that anything downstream actually consumes the corrected source.

## The destination question

Ask, as a single concrete question, after the symptom / reproducer / expected-vs-actual interview:

> **How will we know the fix worked end-to-end? Name the specific destination — a file/function, a log query, a dashboard view, a user-observable behavior, an assertion in a test — where the fix's effect must land.**

Record the answer as a `Verification destination:` line in the filed issue body. Downstream skills (`/execute` Step 4 Tier 3 behavioral verification, `/pre-merge`'s Runtime Initialization & Production-Runtime Parity dimension) can then check the actual destination instead of inferring one from the proposed code change.

## Substantive vs vacuous answers

A **substantive** answer names a destination *distinct from the source of the proposed code change*. Examples:

- "A Langfuse trace named `cite.unknown_id` appears in the dashboard when an unknown citation renders." (Names a runtime destination, distinct from the renderer where the flag is set.)
- "After invalidation, the `posts:home` cache key returns the latest write within one request." (Names a consumer-visible behavior, distinct from the invalidation call site.)
- "A request without the `tenant:write` permission returns 403 from `POST /api/posts` in the integration test." (Names an enforcer-checked outcome, distinct from where the permission row is inserted.)

A **vacuous** answer paraphrases the source-of-change itself, or names no destination at all. Examples:

- "The flag is set to true in `config.ts`." (Restates the source change.)
- "The proposed code change exists in the codebase."
- "It works." / "The bug is fixed." / "Tests pass." (No destination named.)
- "The event is emitted." (Names emission, not consumption — emission to a no-op is still emission.)

When the answer is vacuous **and** two or more signals from the table below fire, firmly recommend `/research` Phase 0 (the producer-consumer / source-effect grep) before filing. When zero or one signal fires, ask the question, accept any non-empty answer, file with it recorded.

## Signal table

| Signal | Indication | Examples |
|---|---|---|
| Proposed fix is a config/flag/option/value change | Audit-shape: source-level correctness verified, system-level reachability not | "set flag X to true", "enable feature Y", "flip boolean Z" |
| Proposed fix is one line, one function call, or "swap the value" | Lightweight-intake shape | One-line diffs, "just call X", "replace Y with Z" |
| Issue body cites an audit, static scan, linter, or external review as the origin | These tools verify source correctness, not system-level outcome | "audit found", "scan revealed", "linter flagged", "static analysis identified" |
| Issue body uses producer-side verbs without naming a consumer | Source-side framing without destination-side framing | "enable", "disable", "set", "flip", "register", "emit" — without "received by", "consumed by", "visible in" |
| Issue body names a cross-boundary surface | Cross-boundary surfaces are where source-vs-destination mismatches live | client/server, producer/consumer, source/sink, emitter/handler, logger/exporter, frontend/backend |
| Issue body mentions a desired outcome at a destination but doesn't name the path | Names the *what* without the *how* | "should show up in the dashboard", "should appear in trace", "logs should include" — without naming the dashboard query, the trace observation, the log filter |

**Two or more signals firing** → firmly recommend `/research` Phase 0 if the destination answer is vacuous.
**Zero or one signal** → ask the question, accept any non-empty answer, file with the answer recorded.

## The nudge to /research Phase 0

When the threshold is hit, the recommendation reads roughly:

> The proposed fix looks audit-shaped (source-level finding, lightweight diff), and the destination answer doesn't name a consumer the fix's effect can land at. Before filing, run `/research` Phase 0 to grep the repo for the corresponding consumer/setup code: find at least one existing case where the pattern you're enabling is already working in this codebase. If Phase 0 returns null, the issue should be reshaped from "set the flag" to "wire the missing consumer" before any code is written.

The nudge is advisory, not gating. The user retains agency to proceed lightweight. The point of the question and the signal table is to make the destination-reachability check **visible structural friction** rather than a constraint that lives only in the developer's head.

## Where this fires

- `/qa` — the destination question is asked as the **last** intake question, after symptom / reproducer / expected-vs-actual. A vacuous answer at `/qa` is acceptable for genuinely lightweight bugs (one-place cosmetic issues, clear null cases). The firm nudge fires only when the signal threshold is met.
- `/triage-issue` — by the time triage is happening, the destination should be answerable with higher rigor. A vacuous answer here is a stronger signal that `/research` Phase 0 is warranted before the TDD fix plan is written.

## What this does not catch

External audit filers, `gh issue create`-from-the-CLI users, and customer-report intakes that don't go through `/qa` bypass this check by construction. The check fires only when the user invokes `/qa` or `/triage-issue`. Closing the external-bypass gap is a future revisit, contingent on whether the `/qa`-side intervention proves insufficient.
