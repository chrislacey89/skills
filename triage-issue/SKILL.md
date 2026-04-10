---
name: triage-issue
description: "Invoked helper skill for deep bug diagnosis, usually delegated from /qa when a reported issue needs root-cause analysis and a TDD fix plan before implementation. Use when the cause is unclear, the bug is a regression, or the user explicitly wants diagnosis. Not for lightweight QA intake (use /qa) or already-clear implementation tasks (use /execute)."
sources:
  primary:
    - "Thinking in Systems — Donella Meadows"
  secondary:
    - "Why Programs Fail — Andreas Zeller"
    - "Domain-Driven Design — Eric Evans"
---

# Triage Issue

Investigate a reported problem, find its root cause, and create a GitHub issue with a TDD fix plan. This is a mostly hands-off workflow - minimize questions to the user.

## Invocation Position

This is an invoked helper skill, not a normal first stop for bug work. It normally runs from `/qa` when the per-issue depth check decides a specific reported bug needs root-cause analysis before it can be filed as a lightweight issue.

Use `/triage-issue` when the cause is unclear after lightweight exploration, the bug is a regression, reproduction is intermittent, multiple symptoms may share an upstream cause, or the user explicitly asks for diagnosis.

Do not use it directly as the entry point for bug conversations — start with `/qa`, which delegates here per issue when depth is warranted. Do not use it once the fix task is already clear enough for `/execute` either.

## Process

### 1. Capture the problem

Get a brief description of the issue from the user. If they haven't provided one, ask ONE question: "What's the problem you're seeing?"

Do NOT ask follow-up questions yet. Start investigating immediately.

### 2. Explore and diagnose

**Reproduce first.** Before analyzing code, attempt to trigger the failure directly — run the relevant test, hit the endpoint, execute the failing command. If you can reproduce it, this reproduction is your ground truth for all subsequent analysis. If you cannot reproduce within 2 minutes, note what you tried and proceed to code analysis, but flag that the root cause is unconfirmed.

Before reading code in detail, form a hypothesis about the cause and let that hypothesis guide exploration rather than wandering. If the evidence contradicts your hypothesis, revise it explicitly and keep narrowing.

Use the Agent tool with subagent_type=Explore to deeply investigate the codebase. Your goal is to find:

- **Where** the bug manifests (entry points, UI, API responses)
- **What** code path is involved (trace the flow)
- **Why** it fails — trace backward from the failure point through the dependency chain rather than forward from the entry point. The root cause is often several layers upstream from the visible symptom.
- **What** related code exists (similar patterns, tests, adjacent modules)

Look at:
- Related source files and their dependencies
- Existing tests (what's tested, what's missing)
- Recent changes to affected files (`git log` on relevant files)
- Error handling in the code path
- Similar patterns elsewhere in the codebase that work correctly
 
 ### 2.5. Structural Diagnosis
 
 If the bug is straightforwardly isolated (off-by-one, missing null check, typo), skip this section. Not every bug is systemic — structural diagnosis is for bugs where the root cause suggests a recurring condition.
 
 After gathering evidence, step back from the code and diagnose the structural condition that allowed this bug to exist. This is the difference between "what broke" and "why the system is prone to this type of breakage."

 Start by reading the failure at three levels: **event** (what just happened), **pattern** (what keeps happening), and **structure** (what conditions, incentives, delays, or missing feedback loops make the pattern likely). If you only explain the event, you have not finished diagnosing the issue.
 
 Apply the diagnostic playbook:
 
 1. **Observe** — Describe the failure as a causal chain, not a single point. Include timing, sequence, and what triggered the chain.
 2. **Map** — Identify the stocks (accumulated state), flows (rates of change), feedback loops, and delays in the failing code path. Where does state build up? What governs the rate? Is there a balancing loop that should have prevented this? Is a delayed consequence hiding the connection between cause and effect?
 3. **Diagnose** — Match the failure pattern to a system archetype. See [systems-reference.md](systems-reference.md) for the archetype catalog and diagnostic questions. Common matches for bugs:
   - **Shifting the burden** — A workaround suppressed the symptom, weakening the fundamental fix. The symptom returned in a different form.
   - **Drift to low performance** — A standard eroded gradually. What was once a hard constraint became a soft preference, until it broke.
   - **Fixes that fail** — A previous fix introduced a delayed side effect that caused this bug.
 4. **Intervene** — Choose a fix at the right leverage level. See [systems-reference.md](systems-reference.md) for the leverage point ranking. Avoid parameter-level fixes (#12) when a structural fix (#5–#3) is available. Ask: "Does this fix address the condition, or just the symptom?" and "What feedback loop would keep this from quietly reappearing?"
 5. **Check for similar conditions** — Search the codebase for the same structural pattern elsewhere. If the archetype matches, the same bug is latent in those locations.

If the structural diagnosis reveals a deeper architectural problem, note it in the issue for follow-up via `/improve-codebase-architecture`.

### 3. Identify the fix approach

If you were able to reproduce the failure in Step 2, verify that your proposed fix actually suppresses it. If the fix does not suppress the failure, your root cause identification is wrong — return to Step 2. If you could not reproduce, state that the root cause is a best-effort analysis based on code reading.

 Based on your investigation, determine:
 
 - The minimal change needed to fix the root cause
 - Which modules/interfaces are affected
 - What behaviors need to be verified via tests
 - Whether this is a regression, missing feature, or design flaw
 - If the structural diagnosis identified a leverage level, prefer fixes at that level or higher. A parameter fix (changing a constant, adding a null check) is appropriate for isolated bugs. A feedback-loop fix (circuit breaker, invariant assertion, monitoring check) is appropriate for bugs matching a system archetype.
 - If you choose a symptomatic fix for pragmatic reasons, say so explicitly and note what fundamental fix would remove the condition instead of merely managing it.

### 4. Design TDD fix plan

Create a concrete, ordered list of RED-GREEN cycles. Each cycle is one vertical slice:

- **RED**: Describe a specific test that captures the broken/missing behavior
- **GREEN**: Describe the minimal code change to make that test pass

Rules:
- Tests verify behavior through public interfaces, not implementation details
- One test at a time, vertical slices (NOT all tests first, then all code)
- Each test should survive internal refactors
- Include a final refactor step if needed
- **Durability**: Only suggest fixes that would survive radical codebase changes. Describe behaviors and contracts, not internal structure. Tests assert on observable outcomes (API responses, UI state, user-visible effects), not internal state. A good suggestion reads like a spec; a bad one reads like a diff.

### 5. Create the GitHub issue

Create a GitHub issue using `gh issue create` with the template below. Do NOT ask the user to review before creating - just create it and share the URL.

<issue-template>

## Problem

A clear description of the bug or issue, including:
- What happens (actual behavior)
- What should happen (expected behavior)
- How to reproduce (if applicable)

## Root Cause Analysis

Describe what you found during investigation:
- The code path involved
- Why the current code fails
- Any contributing factors

**Fix type:** Correction (addresses root cause) / Workaround (suppresses symptom — note what the real fix would require)

Do NOT include specific file paths, line numbers, or implementation details that couple to current code layout. Describe modules, behaviors, and contracts instead. The issue should remain useful even after major refactors.

## Structural Diagnosis

- **Pattern:** [Archetype name if one matches, e.g., "Shifting the burden" — or "Isolated incident"]
- **Structural condition:** [Why the system is prone to this class of failure]
- **Similar conditions:** [Other code paths with the same structural pattern, if found]
- **Leverage level:** [Parameter fix / Feedback loop fix / Structural fix]
- **Delayed effects to watch:** [What consequence might show up later if this fix is incomplete or creates a new side effect]
 
 [Omit entirely for straightforward isolated bugs.]

## TDD Fix Plan

A numbered list of RED-GREEN cycles:

1. **RED**: Write a test that [describes expected behavior]
   **GREEN**: [Minimal change to make it pass]

2. **RED**: Write a test that [describes next behavior]
   **GREEN**: [Minimal change to make it pass]

...

**REFACTOR**: [Any cleanup needed after all tests pass]

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] All new tests pass
- [ ] Existing tests still pass

</issue-template>

After creating the issue, print the issue URL and a one-line summary of the root cause.

## Handoff

- **Expected input:** a single reported bug, usually delegated from `/qa`'s per-issue depth check, that needs diagnosis before implementation
- **Produces:** a GitHub issue with root-cause analysis, structural diagnosis when relevant, and a TDD fix plan — replaces the lightweight issue `/qa` would otherwise have filed for this bug
- **May recommend:** `/improve-codebase-architecture` when the bug reveals a deeper structural pattern
- **Usually invoked by:** `/qa`
- **Returns control to:** the calling `/qa` loop for the next observation, or `/execute` (often via `/tdd`) when the bug is ready to implement
