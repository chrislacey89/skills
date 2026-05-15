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

> **One question per turn.** When the diagnosis requires user input, ask one question at a time and wait for the answer before asking the next. Triage is mostly hands-off — minimize questions, but the ones you ask are sequential.
>
> **Prefer single-select.** Use single-select multiple choice when the user is choosing one direction, one priority, or one next step.
>
> **Use multi-select rarely.** Reserve it for compatible sets — goals, constraints, non-goals, success criteria — that can all coexist. If prioritization matters, follow up asking which selected item is primary.
>
> **Use the platform's question tool when available.** In Claude Code, use `AskUserQuestion`; in Codex, `request_user_input`; in Gemini, `ask_user`. Otherwise, present numbered options in chat and wait for the user's reply before proceeding.

## Process

### 1. Capture the problem

Get a brief description of the issue from the user. If they haven't provided one, ask ONE question: "What's the problem you're seeing?"

Do NOT ask follow-up questions yet. Start investigating immediately.

### 2. Explore and diagnose

**Construct a deterministic feedback loop first.** Before any code analysis or hypothesis work, build a fast, agent-runnable, pass/fail signal that reproduces the failure the user described. This is the highest-leverage activity in this skill — every later step is guessing without it. The loop can be a failing test, a `curl` returning the wrong status, a script that prints a known-wrong value, or whatever the stack supports. It must:

- Run on demand with no manual setup beyond a single command
- Return a clear pass/fail outcome an agent can read
- Reliably reproduce the failure the user described — not a similar-shaped failure

**Do not proceed to hypothesis generation until the loop reproduces the failure.** Hypothesizing without a deterministic loop is guessing; Zeller's TRAFFIC framework names "Reproduce" and "Automate" as separate prerequisite steps for a reason, and they dominate time-to-fix on hard bugs. If you cannot construct a reproducing loop within ~5 minutes, scan Zeller's six dimensions of uncontrolled input — **data** (specific values, sizes, encodings), **user interaction** (sequence and timing of clicks, keystrokes, navigations), **time** (clock state, time-of-day, scheduling), **randomness** (seeds, UUIDs, hash collisions), **OS environment** (locale, filesystem, network, env vars, container vs host), and **thread schedules** (concurrent ordering, race windows) — and stop to ask the user for the one missing input from those dimensions that would unblock reproduction. The taxonomy is a probe, not a recital: name the specific value, flag, environment, or sequence the loop is missing, not the catalog. If reproduction is genuinely impossible (live-only failure, hardware-dependent race), say so explicitly in the issue and flag the diagnosis as best-effort code reading rather than silently proceeding.

**Recognize the Heisenbug pattern.** If the failure disappears under a debugger, vanishes when logging is added, or shifts shape under different observation tools, the bug is almost certainly undefined behavior interacting with environmental differences (memory layout, optimization level, instrumentation overhead). The remedy is to find the undefined behavior in the code — uninitialized memory, a data race, reliance on unspecified ordering — not to switch debuggers or strip the logging. A vanishing bug is evidence about the bug's *shape*, not a reason to abandon the trace; do not silently downgrade Heisenbug-shaped reports to "live-only failure."

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

**Form falsifiable hypotheses before testing any one.** With the feedback loop in hand and the code path traced, list 3-5 ranked candidate causes. State each in falsifiable form:

> If **X** is the cause, then changing **Y** will make the loop pass, and changing **Z** will make the failure worse or leave it unchanged.

Rank by strength of evidence — recent changes to the suspect path, structural plausibility, prior incident patterns. Show the ranked list to the user in one short message before testing the top hypothesis. The user checkpoint is cheap and catches insights you cannot infer from code reading alone ("we just deployed a change to candidate #3" is a common save). Drive the loop against the top hypothesis, revise the ranking when evidence contradicts it, and avoid anchoring on the first plausible idea — Zeller's scientific-method recipe.

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

**Feedback-loop diagram (optional).** If a system archetype applies (shifting the burden, drift to low performance, fixes that fail, or any other named archetype from the catalog), consider invoking `/mermaid` to render the causal-loop diagram and embed it in the issue. Meadows' archetypes are canonically drawn in the source material; rendering them as prose loses part of what makes the archetype transferable to a reader pattern-matching their own failure. Skip when the archetype is named but its loop is one short causal step that prose already captures cleanly.

### 3. Identify the fix approach

Run the proposed fix against the Step 2 feedback loop and confirm the loop now passes. If the loop still fails, your root cause identification is wrong — return to Step 2 and revise the hypothesis ranking. Only in the explicit "reproduction was genuinely impossible" branch from Step 2 may you skip this verification; in that case, restate that the root cause is a best-effort analysis based on code reading.

 Based on your investigation, determine:
 
 - The minimal change needed to fix the root cause
 - Which modules/interfaces are affected
 - What behaviors need to be verified via tests
 - Whether this is a regression, missing feature, or design flaw
 - If the structural diagnosis identified a leverage level, prefer fixes at that level or higher. A parameter fix (changing a constant, adding a null check) is appropriate for isolated bugs. A feedback-loop fix (circuit breaker, invariant assertion, monitoring check) is appropriate for bugs matching a system archetype.
 - If you choose a symptomatic fix for pragmatic reasons, say so explicitly and note what fundamental fix would remove the condition instead of merely managing it.

### 4. Design TDD fix plan

**Seam check first.** Before drafting cycles, confirm a regression test can be written at the *right* call site — a seam that exercises the real bug pattern, not a shallower stand-in. If the only available seam is too shallow (the bug lives in an inline closure inside a private method, only manifests through a global side effect with no public observer, or requires dependencies the production caller never injects), the regression test will encode false confidence.

**Stop and treat that as the diagnosis output.** A regression test at the wrong seam is worse than no regression test — it locks in a false-positive guard. Note in the issue that the bug exposes a missing test seam, recommend `/improve-codebase-architecture` with the specific call-site pattern, and either:

- Block this fix on the architectural work (preferred when the bug is structural in origin), or
- Proceed with a clearly labeled workaround-class fix and a follow-up seam-creation issue (when operational pressure justifies it).

This is Ousterhout's `rules-of-thumb` red-flag posture: when the right test is "too hard to write," the structure itself is the finding.

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

Open with a short plain-language walkthrough (usually a single paragraph) that frames the bug for a reader who doesn't have the codebase in their head: what part of the system this touches in domain terms, what the user or system was trying to do, and why the failure matters. Then the concrete details:

- What happens (actual behavior)
- What should happen (expected behavior)
- How to reproduce (if applicable)

Skip the walkthrough only for narrow, self-evident failures whose domain meaning is obvious from the stack trace. See `references/writing-for-humans.md` for the shape and revision bar.

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
- **May recommend:** `/improve-codebase-architecture` when the bug reveals a deeper structural pattern, or when the Step 4 seam check finds no correct call site for a regression test
- **Usually invoked by:** `/qa`
- **Returns control to:** the calling `/qa` loop for the next observation, or `/execute` (often via `/tdd`) when the bug is ready to implement
