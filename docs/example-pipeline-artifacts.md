# Example Pipeline Artifacts

This document shows what good pipeline artifacts look like in Skill Kit.

It is intentionally small. Use it as a pattern reference, not as a template that must be copied mechanically.

## Example 1: A Good Slice Sequence

This is the kind of decomposition `/prd-to-issues` should produce from a shaped PRD.

### Parent feature

Instructor analytics dashboard

### Example slices

#### Slice 1 — Tracer bullet: analytics service end-to-end

- **Type:** AFK
- **Blocked by:** None
- **Why first:** proves the core architecture from data source to callable service before UI work begins
- **Produces:** analytics service module, core types, first integration test
- **Consumes:** existing database access layer only

#### Slice 2 — Shared dashboard visualization shell

- **Type:** AFK
- **Blocked by:** Slice 1
- **Why now:** builds UI around a proven service contract instead of inventing data shapes in the component layer
- **Produces:** dashboard shell component, loading state, empty state
- **Consumes:** analytics service output and shared analytics types from Slice 1

#### Slice 3 — Instructor route integration

- **Type:** HITL
- **Blocked by:** Slice 2
- **Why HITL:** route-level UX and access rules may still need user judgment
- **Produces:** instructor-facing route, permissions wiring, browser-verifiable flow
- **Consumes:** dashboard shell and analytics service contract

#### Slice 4 — Manual QA and acceptance pass

- **Type:** HITL
- **Blocked by:** Slices 1-3
- **Why last:** verifies the end-to-end flow with human judgment where needed
- **Produces:** QA issue comments, bug follow-ups if needed, acceptance signal
- **Consumes:** all prior slices as shipped behavior

## Why this is a good sequence

- The first slice proves architecture, not just one layer.
- Later slices consume stable outputs instead of inventing contracts mid-flight.
- HITL work is reserved for slices that actually need user judgment.
- QA is a real downstream slice, not an implicit afterthought.

## Example 2: A Good Boundary Map

This is the level of detail that should exist before AFK execution begins.

### Slice 1 — Analytics service end-to-end

#### Produces

- `src/services/analytics/getInstructorAnalytics.ts` → `getInstructorAnalytics(instructorId)`
- `src/services/analytics/types.ts` → `InstructorAnalytics`, `RevenuePoint`
- `src/services/analytics/getInstructorAnalytics.test.ts` → passing service-level test coverage

#### Consumes

- `src/db/client.ts` → database client
- Existing instructor identity lookup from the current auth layer

#### Contract notes

- **Success shape:** returns `InstructorAnalytics` with totals, time-series revenue points, and empty-array defaults where no data exists
- **Error shape:** throws a domain-level error for unauthorized access and a typed infrastructure error for query failure
- **Compatibility posture:** additive; safe for downstream UI work to begin once types are stable

### Slice 2 — Shared dashboard visualization shell

#### Produces

- `src/components/analytics/InstructorAnalyticsDashboard.tsx` → dashboard shell component
- `src/components/analytics/InstructorAnalyticsDashboard.test.tsx` → loading, empty, and happy-path render coverage

#### Consumes

- From Slice 1: `getInstructorAnalytics()`, `InstructorAnalytics`, `RevenuePoint`

#### Contract notes

- **Success shape:** renders totals and chart-ready values from `InstructorAnalytics`
- **Error shape:** renders recoverable error UI rather than swallowing service failures
- **Compatibility posture:** depends on Slice 1 type contract, not database details

## Why this is a good boundary map

- Each shared output has a clear owner.
- Downstream slices depend on contracts, not private implementation details.
- Error shape is named early instead of being invented during implementation.
- The map is detailed enough for AFK execution, but not so detailed that it becomes a spec-by-overprescription.

## Example 3: A Good Handoff

A strong handoff keeps the next skill from re-deriving intent.

### `/write-a-prd` → `/prd-to-issues`

- **Expected input:** a shaped PRD with appetite, rabbit holes, no-gos, user stories, and implementation decisions
- **Produces:** implementation-ready slice issues with dependency order and boundary maps
- **Comes next by default:** `/execute`

### `/prd-to-issues` → `/execute`

- **Expected input:** an unblocked slice issue with a boundary map, dependency context, and any linked research archive entry
- **Produces:** verified implementation work and issue context for the next reviewer or AFK iteration
- **Comes next by default:** `/pre-merge`

## How to use this doc

- Use it when writing or reviewing skill docs.
- Use it when checking whether a slice is ready for AFK execution.
- Use it to calibrate whether a boundary map is concrete enough to prevent interface invention.
- If a real project needs materially more detail than this, prefer improving the specific skill or PRD rather than growing this document into a handbook.
