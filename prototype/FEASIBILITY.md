# Feasibility Prototype

A focused **spike solution** that gives a binary verdict on whether a single technical assumption holds. Use this when the only honest answer to a question is "let's run it and see," and the question is small enough that a 10-line throwaway test can settle it.

The vocabulary is Kent Beck's. From *Extreme Programming Explained*: a spike solution is **a small program written to explore the answer to a technical question, then thrown away**. The spike is not the feature; it's the question made executable.

If the question is "what does this shape feel like?" — wrong branch. Use [LOGIC.md](LOGIC.md). If the question is "what should this look like?" — wrong branch. Use [UI.md](UI.md).

## When this is the right shape

- An `Uncertain` (or `Speculative`) assumption surfaced in a `/research` artifact that explicitly recommends a spike to discharge.
- A library claim that can't be confirmed by reading docs alone — does the streaming path actually emit partial tags, does the SDK accept this header, does this format render where we need it to.
- A version-specific behavior question — does the installed version still expose the API we're planning to call.
- A renderer / parser / format compatibility question — does this content survive a round-trip through the toolchain.
- A binary precondition for a PRD — if the answer is "no," the PRD changes. If the answer is "yes," nothing changes.

The defining signal: **one question, two possible verdicts, code is the cheapest evidence**. If you find yourself drafting more than one question, split the spike — one verdict per spike, no exceptions.

## Why this branch exists

Kent Beck's *Defect Cost Increase* names the cost curve directly: the longer an unverified assumption survives, the more expensive its eventual contradiction. An `Uncertain` assumption discharged at `/research` time costs minutes (a 10-line spike). The same assumption discovered at `/execute` time costs hours of mid-implementation pivot. After merge, it costs a retrospective, a rewrite, or both.

XP's *test-first programming* operates self-similarly: TDD at the minute scale, FEASIBILITY spike at the assumption scale, themes at the quarter scale. FEASIBILITY is the assumption-scale rung — the spike *is* the question made executable, the verdict *is* the test's outcome, and the spike is deleted once the verdict is captured.

Hunt & Thomas's distinction in *The Pragmatic Programmer* helps locate this against neighboring shapes: **tracer bullets** are real-but-minimal end-to-end implementations that stay in the codebase; **prototypes** (LOGIC and UI in this skill) are throwaway code that explores a design question; **feasibility spikes** sit between — throwaway like a prototype, real-API like a tracer bullet, scoped to a single yes/no question. Beck's *spike solution* is the canonical primary name for the activity; tracer-bullet contrast is the supporting clarification.

## Process

### 1. State the question and the two possible verdicts

Before writing any spike code, write down — in one sentence each — the question and what each verdict would mean.

> **Question:** Does Streamdown render a custom `<book>` XML tag inline mid-paragraph without breaking surrounding prose?
> **If yes:** PRD proceeds as drafted, assumption tag downgrades from `Uncertain` to `Verified`.
> **If no:** PRD must pivot to a different inline-rendering primitive; flag for `/correct-course` from `/research`.

A spike whose verdicts both lead to "we'll figure it out" is not a feasibility question; it's a design exploration in disguise. Send it to LOGIC or UI instead.

### 2. Pick the artifact shape

Two shapes, picked by what kind of evidence is cheapest:

#### Shape A — Automated test (preferred default)

Write **one focused test** using the project's existing test runner — Vitest, Jest, pytest, RSpec, whatever the host project uses. The test exercises the real library or system, asserts the expected behavior, and emits a pass/fail verdict.

Pick this when:

- The behavior is verifiable programmatically (string output, exit code, return value, structural shape).
- The library or system can be exercised from a test environment.
- The verdict is binary and machine-checkable.

This is the default. Reach for Shape B only when visual confirmation is genuinely required.

#### Shape B — Temporary scratch route (visual-confirmation case)

Mount a **single throwaway route** (or page, screen, endpoint) that exercises the real system in a way the user can eyeball. Use whatever routing convention the project already uses; don't invent a new top-level structure. Name it so a casual reader can see it's a spike.

Pick this only when:

- The verdict requires visual judgment (does this *look* right when rendered, does this animation actually play, does this layout reflow as expected).
- A test runner can't observe the behavior cheaply (e.g., browser rendering, native UI, video frames).

Shape B exists because some verdicts genuinely need eyeballs. Most don't — if a test can answer it, write the test.

### 3. Write the spike

Whichever shape, hold the spike to these rules:

- **Real library, real version.** Import from the installed package, hit the real API surface. Mocks defeat the spike's purpose.
- **One assertion or one observable outcome.** Multiple assertions widen the question. Keep the spike scoped to the single verdict.
- **Minimal scaffolding.** No fixtures, no helpers, no shared setup beyond what the test runner or framework forces. The spike is read once and deleted; brevity beats reuse.
- **No production code paths.** The spike doesn't import from app code or live alongside it as if it were a fixture. It exists in a clearly throwaway location (e.g. `spike-<question-slug>.test.ts` colocated with the area the question concerns, or `app/spike-<slug>/page.tsx` for Shape B).

### 4. Run it and capture the verdict

Run the spike. Read the output. Decide which verdict fired.

Capture the verdict somewhere durable **before** deleting the spike. Three lines is enough — the question, the verdict, and the date.

For verdicts that fold back into a `/research` artifact, the canonical update is in that artifact: change the assumption's tag (`Uncertain` → `Verified` / `Refuted`), and add a one-line note citing the spike's date and the observed outcome. The research artifact is the single home for the fact — *Once and Only Once*, per Beck — so the verdict doesn't also live in a `NOTES.md` and a commit message and a chat log. If `/research` ran in spike-issue storage mode, the original spike-issue body is point-in-time and not edited; instead, the calling PRD or the new `/research` run cites the verdict and supersedes the older snapshot when the change is material.

If `/research` is not the caller, capture the verdict in whatever durable artifact the calling skill names: a commit message, an ADR, a comment on the issue that triggered the spike. Wherever it lives, the *question* must be captured alongside the *verdict* — a verdict without its question is a fact without a referent and rots fast.

### 5. Delete the spike

Same change that captures the verdict, delete the spike code. A merged spike is a dead file pretending to be alive — future readers will assume it's a test that means something, and the cost of explaining what it means accumulates every time someone reads it.

The exception: when the spike's structure happens to be a useful regression test for the verified behavior, promote it. But "promote" means rewriting it with real assertions, a real name, real coverage of edge cases, and a place in the suite that someone has signed off on — not leaving the spike in place and renaming the file. Spike code was written under spike constraints; production tests are not.

### 6. Hand off back to the caller

Tell the calling skill what happened:

- **Verified verdict** → the calling skill's assumption tag downgrades; the original plan proceeds.
- **Refuted verdict** → the calling skill's plan needs to change. If the caller was `/research`, this is a `/correct-course` trigger or a re-run of `/research` with the new evidence. If the caller was `/execute`'s Step 0 advisory, this is a stop-and-flag — the slice cannot proceed on stale assumptions.
- **Ambiguous verdict** → the spike was too wide. Split the question into smaller sub-questions, pick one, write a new spike. Do not record an ambiguous result as a verified or refuted verdict.

## What this branch is *not* for

The spike-solution narrowness defines what this branch refuses to cover:

- **Performance exploration.** "How fast is X?" is not a binary verdict; it's a measurement. Use a benchmark, not a spike.
- **"See what happens" coding.** Open-ended exploration without a stated question is the failure mode this branch exists to prevent. State the question and the two verdicts before writing any code, or stop.
- **Refactor exploration.** "What would this look like if we restructured it?" is a design question — use `/request-refactor-plan` or a LOGIC prototype.
- **Multi-question spikes.** One spike, one question, one verdict. If multiple questions exist, write multiple spikes (or pick one and accept that the others stay open).
- **Design exploration in disguise.** "Which API shape feels better?" is a LOGIC question. "Which layout reads cleaner?" is a UI question. The signal that you're in the wrong branch: more than one verdict could plausibly be "good enough" and you'd still need to choose.
- **Standing infrastructure.** If the spike happens to be useful indefinitely, it's not a spike anymore — promote it to a real test or a real fixture in a deliberate, separate change.

## Anti-patterns

- **Spikes that grow features.** A spike that gains a second assertion, a third configuration, or a "while I'm here" tweak has stopped being a spike. Delete it and start over with a tighter question.
- **Spikes that survive the change.** The deletion is part of the work, not a follow-up. A spike file on `main` after the verdict has been captured is a smell.
- **Verdicts without questions.** "It works" is not a verdict. The verdict is the answer to *the question stated in step 1*. Without the question, the answer has no meaning to the next reader.
- **Spikes for questions the docs already answer.** Read the docs first. Spike only when the docs are silent, ambiguous, or contradicted by behavior. Otherwise the spike is busywork — a confirmation ritual that costs more than reading.
- **Spikes that wrap mocks.** A spike against a mocked library proves nothing about the real library. Hit the real surface.

## Related terminology

The word "spike" appears in two places in Skill Kit:

- **`/research`'s `spike-issue` storage mode** (configured via `.claude/settings.json` `research.storage = spike-issue`) — a GitHub-issue-shaped home for the research artifact. The storage *mode* uses "spike" in the sense of "the research result, frozen as a closed issue."
- **This branch's spike solution** — Kent Beck's XP term for a small program that answers a technical question and then dies. The *activity*, not the artifact.

Both senses are legitimate and they don't collide in practice; if terminology gets confusing in a specific repo, the [#70 meta-glossary](https://github.com/chrislacey89/skills/issues/70) is where the pinning lives.
