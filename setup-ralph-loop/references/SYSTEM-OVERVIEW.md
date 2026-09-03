# The Hybrid Workflow

This document is the deep rationale for the workflow: why the pipeline is shaped this way, where state lives, how handoffs compress context, and how the system recovers when forward progress breaks. For a quick orientation, read `README.md`. For repository-editing conventions, read `CLAUDE.md`.

## Philosophy

**Cognitive debt is the enemy.** If you can't glance at your project and know where things stand, the system is failing. Every artifact must either live in GitHub (traceable, visible, searchable) or be temporary (deleted after the feature ships). Nothing persists in the filesystem that isn't code, skills, or the compounding knowledge base.

This system cherry-picks the best ideas from three frameworks:

- **Composable skills** — The backbone. GitHub-native planning, composable skill steps, and distinct AFK/HITL execution modes.
- **GSD's structured research** — The rigor. Structured research template, verification ladder, boundary maps, calibrated depth.
- **Compound Engineering's knowledge capture** — The compounding. `docs/solutions/` knowledge base that makes each unit of work easier than the last.

What we explicitly reject:

- GSD's `.gsd/` filesystem (40+ markdown files per milestone that go stale)
- Compound Engineering's 36K-token monolithic plugin (51% context consumed before typing)
- Any system where the developer loses track of where state lives

## The Pipeline

```
/shape → /research (always, depth-calibrated) → /write-a-prd → /prd-to-issues → /execute → QA → /pre-merge → /compound (in-PR, when a lesson exists) → /closeout (merge + teardown) → cleanup
```

The pipeline order is the default path, not a prison. `Ralph` is the AFK execution mode/persona for the `/execute` stage, not a separate pipeline step. For work that requires multiple independent PRDs — where the shaped outcome decomposes into several features each needing their own research-PRD cycle — `/shape` can branch to `/create-milestone`, which creates a planning milestone plus feature issues that move from `roadmap bet` to `research-ready` to `prd` before re-entering the default path at `/research`. For big-batch work (6 weeks) that fits a single PRD, `/write-a-prd` creates a lightweight container milestone to organize the PRD and its downstream slice issues. If `/research` invalidates assumptions from `/shape`, return to `/shape`. If `/research` invalidates assumptions from a milestone feature, backtrack to `/create-milestone` or `/shape` depending on the blast radius. If `/write-a-prd` reveals the problem was misunderstood, return to `/research`. If `/prd-to-issues` reveals materially more work than the appetite supports, return to `/write-a-prd` and reshape. Backtrack deliberately rather than patching forward with stale assumptions.

### Context Engineering

**Artifact precedence.** When a skill consults multiple artifacts, resolve conflicts using this priority order:

1. Working code in the repository (ground truth)
2. The research artifact for this feature — per-user archive entry or closed `research`-labeled spike issue, depending on the project's `research.storage` setting (verified against installed versions at the `date` in its frontmatter; storage location does not affect trust)
3. `docs/solutions/` (compounded knowledge, possibly stale)
4. Framework reference skills (general best practices)
5. Model training data (least reliable for version-specific details)

When the research artifact and `docs/solutions/` disagree, the research artifact wins because it was produced more recently and verified against installed versions — subject to the `date` and `installed_versions_snapshot` in its frontmatter still being plausibly current. The research artifact may live in either the per-user archive or as a closed `research`-labeled GitHub spike issue, depending on the project's `research.storage` setting; both carry equivalent authority because their bodies are produced by the same `/research` skill against the same Phase 0/1 verification. Storage location is a discoverability decision, not a trust decision. Flag the conflict to the user rather than silently choosing. Load `docs/solutions/` on demand — grep for relevant keywords first, read only matching files — rather than loading everything upfront.

**Planning-chain compression.** Each pipeline handoff has a compression artifact: the closing summary (`/shape`), the archived research file (`/research`), the PRD issue (`/write-a-prd`). The downstream skill should work from the written artifact, not from the full prior conversation. If a session is running long after multiple planning skills, start the next pipeline step in a fresh session using the written artifact as its entry point.

**Runtime handoff line.** Every primary pipeline skill prints a `**Next session:**` block at the end of its closing output, in this exact shape:

```
**Next session:** /<next-skill> [arg]
**Input:** <artifact path, issue or PR number, or "use the closing summary above">
```

It is one short block — not a new section, not a paragraph, not a copy-paste cheat sheet — and it draws its data from the skill's existing `## Handoff` section. `/compound` ends the loop only on its post-merge fallback path, where it prints `**Loop closed.** Next: /help when you return to this repo` instead; on its in-PR default path `/closeout` still follows (it performs the merge), so `/compound` prints a normal `**Next session:** /closeout` block.

### Step 1: /shape (Matt's, enhanced)

**What it does:** Interviews you relentlessly about the feature or tranche until every branch of the decision tree is resolved.

**Why it goes first:** You need to know WHAT you're building before you can research HOW to build it. Researching Ably vs Pusher before deciding you need real-time presence is unfocused waste.

**Output:** A shared understanding of the feature or tranche. No file is produced — the understanding lives in your conversation and informs everything that follows.

**Time:** 15-30 min active, 0 min AFK.

**Skill:** Enhanced `/shape`.

When the shaped work requires multiple independent PRDs — where the outcome decomposes into several features each needing their own research-PRD cycle — `/shape` should branch after its closing summary instead of handing off directly to `/research`. The closing summary becomes the input to `/create-milestone`. A blank project or large-scope effort that is one cohesive product stays on the default path; `/write-a-prd` will create a container milestone for big-batch work.

### Step 1.5: /create-milestone (new — only for oversized work)

**What it does:** Turns a tranche-sized outcome into a GitHub milestone plus a small set of sequenced feature issues. Each feature issue starts as a `roadmap bet`, can be promoted to a `research-ready` brief when selected, and later becomes the full PRD issue.

**Why it exists:** `/shape` can clarify an entire application or product area, but `/research` needs a narrower, feature-level question. `/create-milestone` creates that bridge without forcing a giant PRD for the whole tranche.

**Output:** One GitHub milestone, a limited set of feature issues ordered by dependency and architectural risk, and one clearly marked tracer-bullet feature. Selected features are promoted to `research-ready` before entering `/research`.

**Time:** 10-20 min active.

**Skill:** Custom `/create-milestone` skill.

### Step 2: /research (new — always runs, depth-calibrated)

For milestone-planned work, `/research` does not consume a raw `roadmap bet`. It consumes the selected feature issue after that issue has been expanded into a `research-ready` brief containing the problem, user or stakeholder, success signal, why now, appetite, constraints or impositions, assumptions to verify, what the feature proves, and what is out of scope for now.

**This is mandatory, not optional.** You don't know what you don't know. The most expensive research failures happen when you confidently skip research because "middleware is well-understood" — and the API was renamed under you.

**Phase 0 (always runs, 30-60 seconds):** Reads your package.json / lockfile, identifies which dependencies this feature touches, checks for breaking changes between installed versions and latest, flags any stale API patterns. This alone catches the middleware→proxy class of errors.

**Auto-calibration based on Phase 0:**
- **TARGETED (2-5 min):** No version surprises, extending familiar patterns. Output is a 20-line research file confirming the approach is valid.
- **STANDARD (10-20 min):** One dependency has a version mismatch, or a single technical decision needs evaluation.
- **DEEP (20-30 min):** Significant version mismatches, unfamiliar external services, multiple valid approaches.

**Critical rules:**
- Every API reference must include a direct link to official docs (`[proxy.ts](URL) 🔗`) so the developer can click through and audit.
- Every API reference must be verified against documentation for the **installed** version, not the latest. Never trust training data.
- When the approach depends on behavior that changed between versions, flag it with a `🔄 VERSION CHANGE` callout showing old pattern, new pattern, version that introduced the change, and a link to the migration guide.

**Emoji system for scanning:** Research docs use consistent emoji anchors — 🔒 locked decisions, ✅ verified APIs, ⚠️ warnings, 🔄 version changes, 🚫 don't hand-roll, 🪤 pitfalls, 🔗 doc links, 💡 recommendations, 📦 dependencies.

**Staleness check:** When consulting `docs/solutions/`, `/research` checks the `volatility` field and date. Volatile solutions older than 90 days, or solutions whose Shelf Life condition appears met, are flagged as potentially stale before being incorporated.

**Output:** One research artifact, location selected per project via `.claude/settings.json` `research.storage` (default `archive`):

- **`archive`** — file at `~/.claude/research/<repo-slug>/<feature-slug>-<YYYY-MM-DD>.md`, outside the repo. Worktree- and branch-resilient. Right for solo / single-machine / private projects.
- **`spike-issue`** — closed-on-creation GitHub issue in the same repo as the PRD, labeled `research`, with the same body and frontmatter the archive would carry. Reachable from any machine via `gh issue view`, citable from PRD/slice/PR/compound via `Refs #N`. Right for public, portfolio, OSS, transparency-themed, multi-contributor, or multi-machine projects.

Frontmatter captures `date`, `repo`, `feature`, and `installed_versions_snapshot` so future readers can judge freshness regardless of storage location. Referenced in the PRD. Persists after ship — neither location is touched during cleanup or backtracking. Supersession is by new dated artifact, never by editing the existing one.

**Time:** 2-30 min active depending on calibrated depth.

**Skill:** Custom `/research` skill (new).

### Step 3: /write-a-prd (Matt's, enhanced with Shape Up)

**What it does:** Turns the shape conversation + research findings into a shaped pitch filed as a GitHub issue. Uses Shape Up's shaping discipline: sets appetite (time budget) before solution design, names rabbit holes with pre-decided resolutions, declares explicit no-gos, and classifies user stories as must-haves vs. nice-to-haves (~). Interviews you about modules, interfaces, and test boundaries.

**Enhancement:** Now consults `docs/solutions/` for relevant past solutions and incorporates `research.md` recommendations. Surfaces relevant pitfalls during the interview. Validates the pitch is rough (room for builder judgment), solved (rabbit holes patched), bounded (appetite set, no-gos declared), and complete (omitted activities scan — checks for commonly missed work like error handling, auth changes, migrations, monitoring, and surfaces any that apply as Rabbit Holes) before writing. Includes a conditional Flow Sketch for multi-step UI features. Auto-invokes `/design-an-interface` when a module interface is uncertain. For big-batch appetite (6 weeks), creates a lightweight container milestone and attaches the PRD issue to it — distinct from the planning milestone created by `/create-milestone` for multi-PRD tranches.

**Output:** A GitHub issue containing the pitch (optionally attached to a container milestone for big-batch work) — problem story, appetite, solution, rabbit holes, no-gos, flow sketch (conditional), user stories (must-haves + nice-to-haves), implementation decisions, research reference, lessons from past solutions.

**Time:** 10-15 min active.

**Skill:** Enhanced `/write-a-prd`.

### Step 4: /prd-to-issues (Matt's, enhanced)

**What it does:** Breaks the PRD into independently-grabbable GitHub issues using vertical slices (tracer bullets). Each issue is a thin end-to-end slice, not a horizontal layer.

**Enhancement:** Now includes boundary maps in each issue body — what each slice produces (exported functions, types, endpoints), what it consumes from upstream slices, and the contract notes that matter to downstream work (error shape, compatibility posture, versioning readiness when relevant). This forces interface thinking before implementation and prevents slices from making incompatible assumptions. Runs a scope completeness check per slice (verifying Produces covers error paths, loading states, and Rabbit Hole edge cases — not just the happy path), an appetite proportionality check (flagging when decomposition is disproportionate to the stated appetite), and a context completeness check on AFK slices only (a binary presence test for the pointers a fresh context window needs, since the decomposition session holds that context and the AFK implementer does not). When the parent PRD belongs to a milestone, all slice issues are attached to the same milestone for progress tracking.

**Output:** GitHub issues with blocking relationships, acceptance criteria, and boundary maps.

**Time:** 5-10 min active.

**Skill:** Enhanced `/prd-to-issues`.

### Step 5: /execute (HITL or AFK via Ralph)

**What it does:** Executes the next concrete slice. In HITL mode, you run `/execute` directly on a specific issue. In AFK mode, Ralph acts as the runner/persona that repeatedly picks the next unblocked issue, invokes `/execute` + `/tdd`, commits, and iterates. Each AFK iteration is a fresh context window that reads the last commits and open issues — including their comment threads, where the previous iteration forwarded exact errors and partial-progress notes (the read side of the error-forwarding loop documented below). In both modes the thread is also checked for what it names that the *body* does not cover: a concrete capability whose consumer can be named gets promoted into the body or filed with a `Blocks #N` link before the issue closes, rather than read and discarded — the body is the pipeline's baseline, so a requirement left in a comment is outside every mechanism that would carry it forward. `/pre-merge` Phase 4 backstops this at the merge gate for issues named in the PR's `Closes #N` lines.

**Default progression:** Start with HITL Ralph, not AFK Ralph. Use HITL to refine the execution prompt, confirm the repo's quality bar is actually encoded in the workflow, and prove that slice boundaries and feedback loops are working. Go AFK only once the runner is reliably choosing the right next slice and producing reviewable commits without needing frequent rescue.

**Risk-first execution:** Ralph should not blindly take the first issue in the list or optimize for easy wins. Prefer the highest-risk unblocked slice that will reveal architectural, contract, or integration truth earliest. The tracer bullet exists to burn down uncertainty first; AFK execution should preserve that behavior rather than smoothing over it.

**Key enhancement to /execute:** GSD's verification ladder. After tests pass, Ralph checks the actual outcomes — files exist, exports are real (not stubs), imports resolve, API endpoints respond, behavioral flows work. For slices touching schema, migrations, environment config, or new routes, a mandatory runtime startup check verifies that the dev database has the latest schema, the dev server boots from cold, and new routes load without 500 errors — tests that use in-memory databases are not sufficient. For slices whose deploy runtime differs from their test runtime, that ship deploy-time-resolved static assets, or that are bounded by a platform limit the test runtime doesn't enforce, a conditional production-runtime parity rung (Tier 2.7) re-runs the released artifact against the runtime it actually deploys to — closing the dev/prod parity gap where green tests (miniflare, jsdom, mocked seams) certify behavior the production runtime (workerd, the browser, the real deploy layout) rejects; `/pre-merge`'s Runtime Initialization & Production-Runtime Parity dimension mirrors this at review time. "All steps done" is NOT verification. For bug fixes, an additional gate classifies the fix as correction (removes the defect) or workaround (suppresses the failure), searches for structural siblings of the defect pattern, and confirms the corrupted state is no longer produced.

**Key enhancement to /execute:** Branch isolation gate. Before starting any implementation, `/execute` verifies the current branch is appropriate — not a stale feature branch from previous work. **Isolation may be host-provided.** A host environment (Conductor workspaces, GitHub Codespaces, devcontainers) often hands the session a dedicated isolated worktree+branch before `/execute` runs; in that case the pipeline does not own provisioning and must *stand down* rather than nest a worktree or read the host's workspace-named branch as stale. Inflow detection answers only *"am I already isolated?"* — settled by a `.claude/settings.json` `worktree.provisioning` key (`host | pipeline | auto`, default `auto`, mirroring `research.storage`), where `auto` reads a host env-var hint or "toplevel ≠ primary working tree." When no host provides isolation, `/execute` provisions it itself: if worktrunk (`wt`) is available, it uses `wt switch --create` to create an isolated worktree + branch from the appropriate base; otherwise, a plain `git checkout -b` from the appropriate base. The default is the repo's base branch; for a slice with an unmerged `Consumes from #N` dependency that produces symbols the new slice imports, the appropriate base is that sibling slice's branch (Hammant *Trunk-Based Development* Ch. 13 — multiple PRs per story). After creating the worktree, `/execute` *enters* it as a session via the harness `EnterWorktree { path }` tool, so the session's working directory genuinely is the worktree — the cwd tells the truth about where work lands (Norman, knowledge in the world) instead of papering over it with a per-command `cd` prefix; `/closeout` exits that session before teardown (the outflow).

**Key enhancement to /execute:** Now consults `docs/solutions/` and the research archive entry for this feature before implementation, so past lessons and technical decisions don't need re-discovery each iteration.

**Key enhancement to /execute:** When a project uses Next.js or React, Ralph loads `/vercel-react-best-practices`, `/vercel-composition-patterns`, `/next-best-practices`, and `/next-cache-components` before implementation so framework guidance is present in every iteration.

**Quality must be explicit:** Ralph does not infer whether a repo is a throwaway prototype or a long-lived codebase. The quality bar must be stated in the repo and reinforced in the execution skill: small steps, passing feedback loops, reviewable commits, and no silent downgrade from production standards to demo-code shortcuts just because the loop is running AFK.

**Error forwarding between iterations:** If a Ralph iteration fails (build breaks, tests fail, verification fails), the GitHub issue comment should include the exact error output so the next iteration can diagnose rather than repeat. If two consecutive iterations fail on the same issue with the same error class, Ralph should stop and flag the issue for human review rather than continuing to retry.

**Plateau detection (second circuit breaker):** The repeated-failure rule above is a circuit breaker on the *error* signal. A second circuit breaker trips on the *progress* signal. Borrowing Shape Up's Hill Chart vocabulary, each AFK iteration should move the active slice uphill (resolving unknowns) or downhill (executing). An iteration counts as progress only if at least one unmet acceptance criterion, failing check, or unresolved unknown transitions to resolved. Code churn without any such transition is a stationary dot. If two consecutive iterations on the same slice produce stationary dots, Ralph should stop and escalate — same bounded-retry shape as the failure rule. Hysteresis: a single recovering iteration (one resolved unknown or newly-passing check) resets the stationary counter.

**Output:** Commits on the feature branch(es). GitHub issues closed as completed.

**Time:** 5-15 min active (launching + reviewing), 30-120 min AFK.

**Skills:** Enhanced `/execute` (bug-fix verification gate), enhanced `/tdd` (Khorikov code classification + managed/unmanaged mocking discipline + assertion hardening step), pre-commit hooks via `/setup-pre-commit`.

### Step 6: QA (manual)

**What it does:** You test the feature manually. Feedback creates new GitHub issues. Ralph fixes them in subsequent iterations.

**Output:** New issues for bugs, then fixes committed by Ralph.

**Time:** 10-20 min active.

### Step 7: /pre-merge (new)

**What it does:** Creates a GitHub PR with full lineage (links PRD issue, lists closed/open slice issues) and runs an architectural review of the full diff against project principles. The review dimensions live in `pre-merge/review-checklist.md` — that file's numbered headings are the roster, and each dimension's `**Runs in:**` marker names where it executes, so neither this document nor `pre-merge/SKILL.md` restates the list, its size, or its split (`scripts/test-review-dimension-partition.sh` records the incident behind that rule and enforces it). Dimensions marked for a sub-agent run in a fresh review context that sees the diff and nothing of the authoring session; dimensions marked controller-owned run in Phase 4, where the cross-slice context they need already lives. Several dimensions gate themselves off when the diff gives them nothing to check: boundary maps and coverage matrix need a PRD with slice issues, runtime initialization needs schema/config/CLI/deploy-runtime changes, and fix completeness needs a bug fix (it catches workarounds disguised as corrections, missing regression tests, and lone instance fixes). Findings are advisory — presented in the terminal as Observations, Suggestions, or Concerns. When a PRD with slice issues was provided, also notes scope drift: work that appeared in the diff but wasn't in any slice's Boundary Map, and declared Produces that weren't implemented.

**Three modes:** *author-mode* (default — creates the PR, prints advisory findings; auto-invoked by `/execute` Step 6 on the HITL path), *reviewer-mode* (`--pr <n>` — reviews someone else's PR and drafts comment text), and *loop-mode* (`--loop`, or auto-entered when `/execute` hands off on an AFK run). In every mode the review itself runs in a fresh sub-agent context rather than the session that wrote the code — the only exception is by content (typo fixes, dep bumps, formatting-only changes, single-line reverts), never by diff size.

**Loop-mode (the third missing loop):** review was a sensor with no acknowledgement channel. `/pre-merge` emitted findings into a terminal and closed with "No action is required" — nothing tracked whether a finding was acted on, filed, or dropped, so the only thing closing the loop was the operator's memory, and every AFK night produced a branch nobody had reviewed. Loop-mode closes it by making findings **durable** rather than by acting on them: every finding gets a row in a `## Review Disposition Ledger` on the PR, with the grep or type definition that supports or refutes it attached, and the ledger survives the session that produced it. It delegates each dimension pass to its own fresh context — delegation is now unconditional in every mode, so what is loop-specific here is the per-dimension granularity rather than the delegation itself — and auto-runs `/ts-audit` on changed `.ts`/`.tsx` above a stated threshold. **Its exit condition is that every finding has an owner — never that the review came back clean**, which would be the same "zero findings" signal Phase 4's minimum-findings guard already distrusts (Meadows, *Seeking the Wrong Goal*; Leveson, "reward reporting, never low counts").

**What loop-mode deliberately does not do:** fix, file, or decide. It writes one state, `open`; the operator writes `fixed`, `filed`, `accepted`, or `dropped`. That boundary is the whole design. Driving the cycle carries no risk of wrong action, while deciding what to do about a finding carries all of it — and the available evidence measures classifier *agreement*, never whether an automated fix would have been *right*. Because loop-mode makes no commits, the head never moves underneath it, so the review-currency stamp needs no loop-specific rules at all. Automating the disposition step is tracked as follow-on work, gated on the corpus the ledger accumulates — the pipeline's own prove-it-HITL-first rule, applied one level up from the `ralph.sh` review phase that defers on the same ground.

**Output:** A GitHub PR with structured body, stamped at the end of the review with a `## Review Currency` block naming the head SHA the review actually covered. Advisory findings in terminal (author-mode); draft comment text (reviewer-mode); dispositioned findings — fix commits, filed issues, escalations, and the ledger — in loop-mode.

**Time:** 5-10 min active.

**Skill:** Custom `/pre-merge` skill.

### Step 7.5: /closeout (new — owns merge + worktree teardown)

**What it does:** Takes the reviewed PR and returns the workspace to a clean base. Confirms intent (never auto-merges), verifies the PR is pushed, mergeable, and approved, then merges it. Re-anchors the shell to the base checkout *before* removing the worktree — the load-bearing ordering that prevents a removed worktree from stranding the running shell and making a `node_modules`-dependent Stop hook emit false `MODULE_NOT_FOUND` failures. When the session entered the worktree via `EnterWorktree` (the inflow `/execute` uses), the re-anchor is `ExitWorktree { action: "keep" }` — restoring cwd to base without removing the worktree — rather than a bare `cd`; removal still happens explicitly afterward. Prunes the merged branch, pulls the base branch, and verifies the *outcome* (on base, clean tree, PR merged, worktree gone, branch pruned) rather than merely that cleanup ran.

**Why it exists:** `/execute` creates a worktree per slice but nothing removed one, so the worktree stock rose without bound — Meadows' remedy for an inflow-without-outflow stock is to add the missing feedback loop, not to exhort harder. The merge→teardown→pull sequence lived only in the user's memory, which Norman names the wrong place for critical procedure ("prospective memory fails silently"); the skill moves it into the world. It orchestrates existing tools (`gh pr merge`, `wt remove` / `git worktree remove`, `commit-commands:clean_gone`) and introduces no filesystem state.

**Review currency (the second missing loop):** the preconditions originally asked whether a review *happened*, never whether it covered the diff about to merge. Those coincide in the intended linear flow — which is why the gap was invisible — but real HITL sessions accrete scope on a branch after its review pass, and nothing connected the diff `/pre-merge` read to the diff `/closeout` merges. So `/pre-merge` now stamps its reviewed head SHA into the PR body and `/closeout` Step 2 compares it against the current head. Matching SHAs pass silently; an absent stamp (hand-authored or external PR) is noted in one line and continues; a divergence prints `git diff --stat` of the post-review delta and asks once whether to re-review, acknowledge, or stop. It never hard-blocks — showing the delta's *magnitude* is what keeps the loop from becoming an alarm users reflexively dismiss (Meadows again, this time *policy resistance*).

**Boundary:** `/closeout` owns the git-hygiene half of the tail. It does *not* capture lessons (that is `/compound` — and by default the lesson has already ridden the PR via in-PR `/compound` before this step merges; a post-merge `/compound` is the fallback) and does *not* close issues or supersede the research artifact (that is Step 9). HITL-confirmed and non-blocking — it operationalizes an already-optional tail.

**Host-provisioned isolation (outflow asymmetry):** Inflow and outflow have *different* detection needs. `/execute` only asks "am I already isolated?"; `/closeout` asks "who owns teardown?" — a stricter question that cannot use the generic "toplevel ≠ primary working tree" heuristic alone, because a pipeline-made worktree also satisfies it. So when `worktree.provisioning` is `host` (or a host env var like `CONDUCTOR_WORKSPACE_PATH`/`CODESPACES`/`REMOTE_CONTAINERS` is present), `/closeout` **still runs the GitHub-native merge** (`gh pr merge --delete-branch`) but **skips** the worktree teardown and local-branch prune, ceding that half of the lifecycle to the host (Meadows — cede the stock to the one actor that owns it). The deferral is scoped to filesystem teardown, never the merge.

**Output:** Merged PR, torn-down worktree, pruned branch, pulled base, verified clean end state.

**Skill:** Custom `/closeout` skill (new).

### Step 8: /compound (new)

**Where it runs:** By default, **in-PR before merge** — after `/pre-merge` creates the PR and before `/closeout` merges it. `/compound` commits the `docs/solutions/` entry onto the open PR branch so the lesson is reviewed in the same pass as the code and merged atomically with it. The post-merge position implied by this step's number is the *fallback*, for lessons that only surface during or after the merge (integration surprises, QA findings). The step number reflects ownership of the tail, not the default runtime order — which is `/pre-merge → /compound (in-PR) → /closeout`.

**What it does:** Captures what was learned into `docs/solutions/`. Reviews the git log, issue thread, and diff (the open PR branch in-PR, the merged feature post-merge) to identify the most important lessons — root causes, prevention strategies, patterns, key decisions. Applies a 4-question pre-filter before capturing: is this novel, will it last, could it live closer to the source, and (for bug fixes) was the process fixed? Reviews the PRD's Rabbit Holes against actual outcomes — ones that bit are high-value compound targets. For bug fixes, classifies the defect origin phase (specification/design/coding error) and splits prevention into code-level (tests, assertions) vs. process-level (pipeline step changes), and applies `/compound` Phase 4's defect clustering check when a pattern recurs. Also checks for scope accuracy lessons and captures patterns so future planning improves. When a milestone's feature issues are all complete, close the GitHub milestone and optionally capture tranche-level lessons if they add reusable knowledge.

**Output:** One file in `docs/solutions/<category>/` with YAML frontmatter including a `volatility` classification (evergreen/stable/volatile) that drives review cadence. Each solution includes a Shelf Life section declaring what change would make it unnecessary.

**Time:** 5-10 min active.

**Skill:** Custom `/compound` skill (enhanced with Living Documentation principles).

### Step 9: Cleanup

The git-hygiene half of cleanup — merging the PR, tearing down the worktree, pruning the merged branch, and pulling the base — is owned by `/closeout` (Step 7.5). This step covers the remaining, GitHub-native half; `/closeout` defers to it rather than duplicating it.

**What it does:** Close the PRD issue and any remaining slice issues as shipped, and confirm the research artifact's frontmatter still reflects the versions/decisions that landed. If a version bumped during implementation, supersede the existing artifact with a new dated one (new archive file, or new spike issue) rather than editing the existing one — snapshot semantics depend on each artifact being immutable. The original artifact persists (outside the repo for archive mode, in GitHub for spike-issue mode) and is never deleted at this step — stale-trust protection lives in the frontmatter and supersession discipline, not in deletion.

**Output:** Closed issues. Research artifact retained as durable context for future planning in the same area.

### Pipeline Recovery

The pipeline described above is the forward path. This section covers what happens when forward progress stops — either a planned backtrack or an unplanned failure.

**When backtracking to an earlier skill:**

- State which skill you are returning to and why.
- If the backtrack invalidates a written artifact: supersede it (re-run `/research` to produce a new dated artifact — new archive file or new spike issue depending on the project's `research.storage` mode; do not delete prior artifacts and do not edit them in place), update in place (PRD issue body), or close with a comment explaining the backtrack (slice issues). Do not leave stale artifacts for downstream skills to consume.
- Scope the re-run to what changed — do not restart the skill from scratch. Example: "We shaped X, but Y was wrong, so we are re-researching Z."
- After the re-run, proceed forward through the pipeline again from that point.

**When a skill cannot complete:**

- Leave a comment on the relevant GitHub issue with: what was done, what remains, and the exact error output (not a summary). The next agent or user benefits from seeing the real error.
- If the error suggests the approach from `research.md` or the PRD is wrong, say so explicitly — this is a signal to backtrack, not to keep retrying the same approach.
- If `/research` reveals that `/shape` assumptions are fundamentally wrong, backtrack to `/shape`.
- If `/pre-merge` reveals architectural concerns serious enough to warrant rework, backtrack to `/execute`.
- Do not silently swallow errors or continue forward when the underlying approach is broken.

**Forward failure: `/execute` on a PRD issue.** A common misroute is invoking `/execute` directly on a shaped PRD issue that was never decomposed via `/prd-to-issues`. `/execute`'s Step 0 issue-shape detection gate catches this: if the task issue has shaped-pitch markers (Appetite / Rabbit Holes / User Stories / Implementation Decisions) and no `Decomposed into: #…` comment from `/prd-to-issues`, `/execute` halts and routes to `/prd-to-issues`. After decomposition, re-invoke `/execute` on a specific child slice — not the PRD.

**Renegotiation path (PRD ↔ Coverage Matrix).** When `/execute` discovers an unmapped commitment mid-cycle, or a commitment is consciously cut during implementation, the update flow is: edit the PRD issue body → regenerate the Coverage Matrix from the new PRD content. The matrix is a derived view; the PRD is the single source of truth. Never hand-edit a matrix to paper over a PRD change. `/pre-merge`'s Coverage Matrix Reconciliation dimension reconciles the merged slices against the regenerated matrix at the end of a multi-slice PRD and raises a Concern only on unmapped Musts, naming the merge as the action to withhold.

---

## Coverage Matrix (derived view)

A companion to Boundary Maps. The Boundary Map answers *what flows between slices*; the Coverage Matrix answers *which PRD commitment is addressed by which slice*. Both are regenerated views over GitHub-native state — no local matrix file, no hand-maintained spec.

- **Single source of truth:** the PRD issue body (user stories in Must-haves / Nice-to-haves (~)).
- **Classification:** each PRD user story is Must, Want, or ~Tilde (drawn from the PRD's existing section structure).
- **Coverage:** derived from each slice issue's `User Stories Addressed` field.
- **Size gate:** single-slice PRDs skip the matrix. For them, the boundary map and the slice's `User Stories Addressed` field already serve the traceability job.
- **Generation difficulty is a PRD-quality signal.** If the matrix is noisy to generate, report that to the user — do not push structure back into the PRD. PRDs stay rough (Shape Up).
- **Regenerated, not stored.** Whenever a consumer needs the matrix (`/prd-to-issues` Step 5, `/pre-merge` Coverage Matrix Reconciliation), it derives the matrix on the spot from current PRD + slice issues. No stored artifact to drift out of sync.

**Reconciliation gates:** `/prd-to-issues` surfaces unmapped Musts as backpressure before slice creation. `/pre-merge`'s Coverage Matrix Reconciliation raises a Concern on unmapped Musts at the end of a multi-slice PRD — advisory, with the withheld merge named as the action — warns on unmapped Wants, and accepts unmapped ~Tildes silently. `/pre-merge` gates nothing itself; Concern is the strongest tier it defines.

---

## Where State Lives

| State | Location | Why |
|-------|----------|-----|
| Feature plans (PRDs) | GitHub issues | Traceable, visible, survives context resets |
| Milestone roadmaps | GitHub milestones + feature issues | Sequence large work without introducing local roadmap files. Two roles: container milestones (from `/write-a-prd` for big-batch single-PRD work) and planning milestones (from `/create-milestone` for multi-PRD tranches) |
| Work items (slices) | GitHub issues with blocking relationships | Native kanban, Ralph reads them |
| QA bugs | GitHub issues | Created during manual QA, closed by Ralph |
| Decisions register | Ubiquitous language doc (decisions section) | Co-located with terminology, single source of truth |
| Technical research | Per-project, selected by `.claude/settings.json` `research.storage`. Default `archive` → per-user file at `~/.claude/research/<repo-slug>/<feature>-<date>.md`. Opt-in `spike-issue` → closed `research`-labeled GitHub issue in the same repo as the PRD | Storage location matches the project's audience flow without forcing a global rule. Archive is right for solo / single-machine / private work. Spike-issue is right for public, portfolio, OSS, multi-contributor, or multi-machine work where the PRD's audience reads via GitHub. Both carry the same frontmatter and equivalent authority |
| Institutional knowledge | `docs/solutions/` in repo | Compounds over time, consulted during planning |
| Workflow definitions | `.claude/skills/` in repo | Composable, load-on-demand, version-controlled |

### What is NOT in the filesystem

- No `.gsd/` directory
- No `STATE.md`, `ROADMAP.md`, `CONTEXT.md`, `PLAN.md` per slice
- No `progress.txt` as durable task state
- No `docs/brainstorms/`, `docs/specs/` (research lives in the per-user archive outside the repo, not under `docs/`)
- No monolithic AGENTS.md consuming 36K tokens

---

## Skill Installation

Everything lives in `.claude/skills/`. No external dependencies. You own all copies.

### Invocation Roles

Use this taxonomy consistently:

- **Primary pipeline skills** — the default feature-delivery path plus the milestone-planning branch for oversized work: `/shape`, `/create-milestone`, `/research`, `/write-a-prd`, `/prd-to-issues`, `/execute`, `/pre-merge`, `/closeout`, `/compound`
- **Invoked helper skills** — delegated from another skill when a narrower question needs focused rigor: `/api-design-review`, `/design-an-interface`, `/tdd`, `/triage-issue`, `/fix-findings` (the one that is *user*-invoked rather than skill-invoked — the human types it after choosing findings; `disable-model-invocation: true`)
- **Side-route skills** — alternate entry points or supporting paths that reconnect to the main workflow: `/qa`, `/prototype`, `/request-refactor-plan`, `/improve-codebase-architecture`, `/improve-pipeline`, `/ubiquitous-language`, `/ts-audit`, `/walk-commits`, `/visual-recap`, `/help`, `/correct-course`, `/handoff`, `/re-pitch`
- **Infrastructure skills** — repo setup and safety tooling, not feature-delivery stages: `/init-pipeline`, `/setup-pre-commit`, `/setup-ralph-loop`, `/git-guardrails-claude-code`

### Handoff Table

One row per skill. For quick orientation — what each skill expects, what it produces, and where it usually goes next. The narrative Default Handoff Map below covers branch conditions and auto-invocations this table cannot fit.

| Skill | Expects | Produces | Next |
|---|---|---|---|
| `/shape` | Fuzzy problem, unclear scope | Shared understanding — choices, assumptions, impositions, signals | `/research` (or `/create-milestone` for multi-PRD work) |
| `/create-milestone` | `/shape` closing summary for a multi-PRD tranche | GitHub milestone plus sequenced feature issues | `/research` on a `research-ready` feature |
| `/research` | Clarified problem from `/shape` | Research artifact with verified versions and doc links — per-user archive at `~/.claude/research/<repo>/<feature>-<date>.md` (default), or closed `research`-labeled GitHub spike issue when project opts in via `.claude/settings.json` `research.storage = spike-issue` | `/write-a-prd` (may invoke `/api-design-review`) |
| `/write-a-prd` | Validated research plus shaping context | Shaped PRD issue with appetite, rabbit holes, no-gos | `/prd-to-issues` (may invoke `/design-an-interface`) |
| `/prd-to-issues` | Shaped PRD issue | Slice issues with boundary maps and dependency order | `/execute` |
| `/execute` | Concrete slice or task with enough scope clarity | Verified commits, one per logical unit, plus a `## Review Notes` block of re-runnable verification claims for the reviewer | `/pre-merge` — author-mode after Step 5 PR-review confirmation, loop-mode on AFK exits |
| `/pre-merge` | Verified implementation ready to review (author-mode), an existing PR number to review (reviewer-mode via `--pr <n>`), or an AFK handoff from `/execute` (loop-mode via `--loop`) | PR with lineage, stamped with the reviewed head SHA, plus architectural review readout (author-mode); draft PR comment text shaped by `references/comment-craft.md` (reviewer-mode); or that same PR plus a `## Review Disposition Ledger` giving every finding a row, an owner, and its supporting evidence (loop-mode) | `/compound` in-PR when a lesson emerged, then `/closeout` to merge and tear down; loop-mode first hands the ledger's `open` rows back to the operator to settle |
| `/closeout` | Reviewed, mergeable PR from `/pre-merge` (its lesson, if any, already compounded onto it in-PR) on a feature branch (worktree or plain checkout) | Merged PR, torn-down worktree, pruned branch, pulled base, verified clean end state | Step 9 issue-closing; post-merge `/compound` only as the fallback for a lesson that surfaced at/after merge |
| `/compound` | A durable lesson — known at PR time (in-PR default) or surfacing at/after merge (post-merge fallback) | `docs/solutions/` entry with volatility and Shelf Life, riding the PR (in-PR) or committed to base (post-merge) | In-PR: `/closeout` merges the PR carrying it. Post-merge: loop closed. Future `/research` and `/write-a-prd` consult it |
| `/api-design-review` | API-shaped uncertainty from `/research` or `/write-a-prd` | Contract verdict, compatibility class, must-lock decisions | Returns to the calling skill |
| `/design-an-interface` | Module problem with multiple plausible shapes | Contrasted interface options with a recommendation | Returns to caller (usually `/write-a-prd`) |
| `/tdd` | Concrete behavior ready for red-green-refactor | Tested code increments via vertical cycles | Returns to caller (usually `/execute`) |
| `/fix-findings` | The `/pre-merge` finding numbers a human chose, plus the findings themselves (terminal output, or the PR ledger loop-mode wrote) | One commit per accepted finding, each authored by a fresh sub-agent that did not write the code; a per-finding breaker verdict (`killed` / `survived` / `not-run` / `not-applicable`) with the command behind it; `refuted` reports for findings the tree did not confirm. No stamp, no PR edit, no merge | `/pre-merge` delta pass over everything past the stamp, which re-runs the dimensions and re-stamps; then `/compound` if a lesson emerged, then `/closeout` |
| `/qa` | Observed user-facing failures or regressions — single entry for bug conversations | Durable GitHub bug issues in domain language; delegates per-issue to `/triage-issue` for deep bugs | `/execute` (or per-issue to `/triage-issue`) |
| `/triage-issue` | Single bug delegated from `/qa`'s depth check, needing diagnosis before implementation | Root-cause issue with TDD fix plan, replacing the lightweight `/qa` issue for that bug. Built on a Zeller-style spine: deterministic feedback loop first, ranked falsifiable hypotheses, then a seam check that hands off to `/improve-codebase-architecture` when no correct test seam exists | Returns to the `/qa` loop, then `/execute` (often via `/tdd`), or `/improve-codebase-architecture` when the seam check fails |
| `/prototype` | One question that needs throwaway code to answer — a state model to feel out (LOGIC), a layout to compare variants of (UI), or an `Uncertain` assumption to discharge with a focused spike (FEASIBILITY) | Captured answer in the calling skill's durable artifact (research assumption tag, ADR, commit message, NOTES.md) and the spike code deleted in the same change | Returns to the caller (usually `/research` for FEASIBILITY, or the user for LOGIC / UI) |
| `/request-refactor-plan` | Refactor problem needing safer sequencing | GitHub issue with tiny-commit refactor plan | `/execute` |
| `/improve-codebase-architecture` | Architectural friction, coupled modules, shallow pain | Candidate deepening opportunities and a refactor RFC | `/request-refactor-plan` or `/execute` |
| `/improve-pipeline` | Pipeline-level lesson from real-world usage of Skill Kit | GitHub issue in `chrislacey89/skills` with repo-wide improvement proposal | Review issue, then optional implementation in `chrislacey89/skills` |
| `/ubiquitous-language` | Terminology ambiguity or competing domain terms | `UBIQUITOUS_LANGUAGE.md` with decisions register | Returns to the caller workflow |
| `/ts-audit` | TypeScript or React files to audit | Structured findings report grouped by category | `/execute` or `/pre-merge` |
| `/walk-commits` | Finished branch ready to merge, plus the base branch to diff against | Reviewer comprehension and per-commit sign-off (🟢/🟡/🔴) with open items to resolve — a decision, not a durable file | `/closeout` to merge and tear down, then `/compound` only when a durable lesson emerged |
| `/visual-recap` | Finished diff, PR, or branch to comprehend, plus the base branch to diff against | Transient self-contained interactive HTML artifact in the selected mode — scrolling recap (file-tree + change flags, annotated split diffs with line-anchored callouts, schema/API contract cards, UI wireframes, before/after columns, a per-unit series when one root cause repeats across four or more near-identical sites) or walkthrough deck (premise → changes → mechanism → aftermath, one idea per screen) — with CSS-spine diagrams for trivial flows and Mermaid-via-CDN for multi-stage or behavioral graphs, plus the reviewer's feedback (copied back where the artifact is handed off), with durable items promoted to GitHub PR review comments | `/closeout` to merge and tear down, then `/compound` only when a durable lesson emerged |
| `/help` | Uncertainty about current pipeline position | Next-step recommendation with a one-line reason | The recommended next skill |
| `/correct-course` | Invalidated artifact or changed assumption | Blast-radius diagnosis and artifact cleanup plan | The earliest skill that needs to re-run |
| `/handoff` | Long session with no natural compression artifact — mid-skill, exploratory, side-route, or non-pipeline work | Transient handoff doc at a `mktemp` path; references existing artifacts by path, URL, or issue number | Fresh session opened by the user with the doc as input |
| `/re-pitch` | An explanation that did not land, plus the user's signal of non-comprehension | A replacement explanation in the conversation — diagnosed cause, one-sentence anchor, capped sentences, every domain term glossed at first use. No durable artifact | Returns control to whatever was in flight; may recommend `/ubiquitous-language` when the same terms keep needing glosses |
| `/init-pipeline` | Project that will use `/execute` | Claude Code hooks, git guardrails, pre-commit setup | `/execute` (auto-invokes it) |
| `/setup-pre-commit` | Repo needing commit-time quality gates | Lefthook config plus formatter/linter wiring | Normal feature work, now gated at commit |
| `/setup-ralph-loop` | Repo wanting repeatable Ralph execution | `ralph-once.sh` and bounded `ralph.sh` | `/execute`, first HITL then bounded AFK |
| `/git-guardrails-claude-code` | Project or user environment needing git safety | Installed guardrail hooks blocking destructive commands | Normal workflow with guardrails in place |

### Default Handoff Map

- `/shape` → `/research` for work that fits a single PRD, or `/create-milestone` for work that requires multiple independent PRDs
- `/create-milestone` → selected feature issue promoted from `roadmap bet` to `research-ready`, then `/research`
- `/research` → `/write-a-prd` and conditionally `/api-design-review`; when an `Uncertain` assumption is cheaply code-verifiable, `/research` names `/prototype` FEASIBILITY as the discharge route before handoff
- `/prototype` — kit-owned side-route with three branches (LOGIC for state models, UI for layout variants, FEASIBILITY for spike-solution feasibility verdicts). FEASIBILITY is named by `/research` (Phase 4 / Phase 6) and `/execute` (Step 0 advisory) as the discharge route for un-discharged `Uncertain` assumptions; the verdict folds back into the calling artifact and the spike code is deleted in the same change
- `/write-a-prd` → `/prd-to-issues` (with optional container milestone for big-batch work) and conditionally `/design-an-interface` or `/api-design-review`
- `/init-pipeline` is auto-invoked by `/execute` Step 0 when `.claude/hooks/enforce-classification.sh` is missing — scaffolds Claude Code hooks (TDD classification gate, git guardrails), pre-commit hooks, and package manager enforcement
- `/setup-ralph-loop` is auto-invoked by `/execute` when the task comes from a multi-slice GitHub issue and no Ralph scripts exist — prepares `ralph-once.sh` and bounded `ralph.sh` for HITL-to-AFK execution
- `/prd-to-issues` → `/execute`, with Ralph optionally running the AFK execution loop for unblocked slices, then QA and `/pre-merge`
- `/execute` → `/pre-merge` after verification — auto-invoked in **author-mode** at the end of Step 6 when Step 5's manual verification checklist ran and the user confirmed the "Ready for PR Review" item, and auto-entered in **loop-mode** on AFK Ralph iterations, which structurally cannot present a Step 5 checklist. Trivial-task flows that skipped Step 5, and users who answered "no" to the PR-review item, exit cleanly for manual `/pre-merge` invocation. Either way Step 6 writes a `## Review Notes` block into the PR body — re-runnable verification claims rather than conclusions, since the reviewer's whole picture of the change comes from the diff plus notes authored by the agent under review. `/execute` delegates to `/tdd` when backend work benefits from strict red-green-refactor.
- `/pre-merge` → `/compound` (in-PR, when a durable lesson exists — captured onto the open PR so it is reviewed and merged with the code) → `/closeout` (merge + worktree teardown); post-merge `/compound` remains the fallback for lessons that surface at/after merge
- `/pre-merge` Phase 4's next-step menu → `/fix-findings` → `/pre-merge` delta pass → `/closeout`. This is the branch the human takes when a finding should be fixed on this branch rather than handed off as an issue. `/fix-findings` is user-invoked only and never self-triggers: it takes the numbers the human chose, spawns one fresh fixer per finding under `/pre-merge` Phase 3's context contract, spawns a fresh read-only breaker in a `git archive` copy that validates its apparatus before reporting a verdict, and caps at one fixer pass and one breaker pass per finding. It never selects findings (#190's boundary), never merges, and never stamps — `/pre-merge` remains the stamp's only writer, pinned by `scripts/test-review-currency-marker.sh`. Backing it is the **post-review edit lock**: `/pre-merge` Phase 4 writes `.claude/.review-stamped` beside the stamp, the classification hook refuses implementation writes while that flag exists and `.claude/.fix-findings-active` does not, and `/closeout` removes it at merge. The lock's two exits — invoke the skill, or delete the flag by hand — are both deliberate acts, replacing a choice that is silent today
- `/closeout` merges the reviewed PR, re-anchors the shell to the base checkout *before* removing the worktree, prunes the merged branch, pulls base, and verifies a clean end state; it owns the git-hygiene half of the `merge`/`cleanup` tail and hands the issue-closing + research-artifact half to Step 9. HITL-confirmed; never auto-merges
- `/compound` and `/pre-merge` may recommend `/improve-pipeline` when the main lesson is about Skill Kit itself rather than the downstream project; `/improve-pipeline` is advisory and files against `chrislacey89/skills`. `/compound` Phase 4 may also file a proposal stub against `chrislacey89/skills` directly, as the fifth of its permitted mechanisms, when the preventing change belongs to the pack and no downstream artifact could carry it
- `/qa` is the single entry point for bug conversations and feeds bug work back into `/execute`; it delegates per-issue to `/triage-issue` when a specific bug needs root-cause diagnosis, then returns to its own loop
- `/request-refactor-plan` and `/improve-codebase-architecture` produce refactor work that can re-enter at `/execute`
- `/improve-pipeline` captures Skill Kit improvement proposals as GitHub issues in `chrislacey89/skills`, then optionally flows into reviewed implementation of the named repo changes
- `/ts-audit` produces type-safety findings that can feed into `/execute` for fixes or inform `/pre-merge` architectural review
- `/walk-commits` is an optional commit-by-commit comprehension walkthrough at the `/pre-merge` → merge boundary; `/pre-merge` Phase 4 recommends it (without invoking) when the person merging didn't author the diff, and `/execute` Step 5/6 names it as an option before `/pre-merge`. It produces reviewer comprehension and sign-off, not defect findings, and never auto-runs. It may optionally render a per-commit card as a line-anchored callout via the shared `docs/visual-rendering-core.md`
- `/visual-recap` is an optional side-route at the same `/pre-merge` → merge boundary: it renders a finished diff/PR/branch as a transient self-contained interactive HTML artifact so a reviewer who didn't author the change can grasp its shape before reading lines. Step 1 selects one of two canonical modes — the **scrolling recap** for auditing parallel hunks, or the **walkthrough deck** (premise → changes → mechanism → aftermath, one idea per screen) when there is one story the screens advance — and both share the same token core, Grounding Rule, and reading budget. Diagrams take the CSS spine when trivial and Mermaid-via-CDN when multi-stage or behavioral, with a visible per-figure degrade note; the offline invariant covers core blocks, so a figure may degrade but a finding may not. `/pre-merge` Phase 4 may recommend it like `/walk-commits`; it is never auto-invoked, skips small/obvious diffs, finds no defects (that stays `/pre-merge`), may *recommend* `/re-pitch` when the change feels abstract without ever invoking it, and the HTML is transient (gitignored `.context/` or `mktemp`, never committed). It shares the `docs/visual-rendering-core.md` rendering core (vocabulary, copy-text feedback serializer — required on handoff, optional when the author is in the room — Grounding Rule, secret-redaction, Tufte quality bar) with `/walk-commits`
- `/help` reads repo state and recommends the next pipeline skill with a one-line reason — advisory only, never runs the next skill itself
- `/correct-course` diagnoses stale artifacts when an upstream assumption fails, walks the cleanup, and hands off to the earliest skill that needs to re-run
- `/handoff` is invoked ad-hoc when no inter-skill compression artifact covers the situation (mid-skill, exploratory, non-pipeline work, or cross-machine/cross-agent handoff); it is not part of any default path and is not a substitute for the `**Next session:**` runtime line primary skills already emit

```
.claude/skills/
│
│  ── PRIMARY PIPELINE (direct-entry) ───────────────────────────────────
│
├── shape/SKILL.md               # Requirements discovery (enhanced — workflow stories, hidden-function stability probes)
├── create-milestone/SKILL.md    # GitHub milestone planning for multi-PRD tranche work before feature research
├── research/SKILL.md               # Technical research with version checking (new — GSD-structured)
├── write-a-prd/SKILL.md            # Shaped pitch (enhanced — Shape Up discipline, consults solutions + research, auto-invokes /design-an-interface)
├── prd-to-issues/SKILL.md          # Issue decomposition (enhanced — boundary maps in each issue)
├── execute/SKILL.md                # Execution (enhanced — verification ladder, solutions lookup, React/Next.js references, delegates to /tdd)
├── pre-merge/SKILL.md              # PR creation + architectural review before merge (new)
├── closeout/SKILL.md               # Merge the reviewed PR + tear down the worktree + return to a clean base (new)
├── compound/SKILL.md               # Knowledge capture after ship (new — CE-inspired)
│
│  ── INFRASTRUCTURE ────────────────────────────────────────────────────
│
├── init-pipeline/SKILL.md          # Scaffold all enforcement: Claude Code hooks, git guardrails, pre-commit, pnpm (auto-invoked by /execute)
├── setup-pre-commit/SKILL.md       # Lefthook + detected formatter/linter, supports ESLint/Prettier/Biome (enhanced)
├── setup-ralph-loop/SKILL.md       # Generates ralph-once.sh and bounded ralph.sh for HITL-to-AFK /execute execution
├── git-guardrails-claude-code/     # Block dangerous git commands (from Matt, unmodified)
│   ├── SKILL.md
│   └── scripts/block-dangerous-git.sh
│
│  ── INVOKED BY OTHER SKILLS (not called directly) ─────────────────────
│
├── api-design-review/SKILL.md      # Spec-first API contract review for higher-risk API work (invoked by /research and /write-a-prd)
├── design-an-interface/SKILL.md    # Parallel sub-agent interface designs (auto-invoked by /write-a-prd)
├── tdd/                            # Test-driven development delegated primarily from /execute for backend work
│   ├── SKILL.md
│   ├── code-classification.md
│   ├── deep-modules.md
│   ├── interface-design.md
│   ├── mocking.md
│   ├── tests.md
│   └── refactoring.md
├── triage-issue/                    # Bug investigation + structural diagnosis + TDD fix plan, delegated per-issue from /qa when depth is needed
│   ├── SKILL.md
│   └── systems-reference.md
├── fix-findings/                    # Fresh fixer + advisory breaker for the /pre-merge findings a human chose; user-invoked only, never selects, never stamps
│   ├── SKILL.md
│   └── references/                 # mutation-at-consumption.md, next-step-menu.md (bundled)
│
│  ── SIDE ROUTES AND SUPPORTING PATHS ──────────────────────────────────
│
├── qa/SKILL.md                     # Single entry point for bug conversations — files lightweight issues and delegates per-issue to /triage-issue when depth is needed
├── prototype/                      # Kit-owned fork of Matt Pocock's /prototype with a third FEASIBILITY branch (spike-solution discharge for /research Uncertain assumptions)
│   ├── SKILL.md
│   ├── LOGIC.md
│   ├── UI.md
│   └── FEASIBILITY.md
├── improve-codebase-architecture/  # Find deepening opportunities and spin them into refactor work
│   ├── SKILL.md
│   └── REFERENCE.md
├── improve-pipeline/               # Capture Skill Kit improvement proposals as GitHub issues in chrislacey89/skills
│   └── SKILL.md
├── request-refactor-plan/SKILL.md  # Refactor RFC with tiny commits that can re-enter execution through /execute
├── ubiquitous-language/SKILL.md    # Domain glossary support that can sharpen shaping, QA, and refactor conversations
├── ts-audit/                       # Audit TypeScript code against 9 bundled TypeScript library references
│   ├── SKILL.md
│   └── evals/
├── walk-commits/SKILL.md           # Interactive commit-by-commit comprehension walkthrough before merge (optional, recommended by /pre-merge)
├── visual-recap/SKILL.md           # Render a finished diff/PR/branch as a transient interactive HTML recap with line-anchored callouts (optional, never auto-invoked)
├── help/SKILL.md                   # Read repo state and recommend the next pipeline skill (advisory only)
├── correct-course/SKILL.md         # Diagnose stale artifacts and walk the cleanup when an upstream assumption fails
└── re-pitch/SKILL.md               # Re-state an explanation that did not land, in controlled technical English with every domain term glossed
```

### Ralph setup:

`/execute` auto-invokes `/setup-ralph-loop` when it detects multi-slice GitHub-issue work (PRD, big-batch appetite, or multiple user stories) and no `ralph-once.sh` or `ralph.sh` exists in the repo root. The skill generates `ralph-once.sh` for supervised use and bounded `ralph.sh` adapted to the repo's real task source and feedback loops. You can also invoke `/setup-ralph-loop` directly if you want to set up Ralph before reaching `/execute`.

A generated `ralph.sh` should follow Matt's pattern:

```bash
#!/bin/bash
# Ralph — AFK execution loop
# Picks the next unblocked issue, implements one slice, commits, and iterates

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

for ((i=1; i<=$1; i++)); do
  # Compute the frontier from native GitHub issue dependencies rather than
  # asking the model to parse `Blocked by` prose. Recomputed each iteration,
  # because closing a blocker un-gates its dependents automatically.
  FRONTIER=$(gh issue list --state open --limit 100 --json number,blockedBy \
    --jq '[.[]
          | select([.blockedBy.nodes[] | select(.state == "OPEN")] | length == 0)
          | .number] | join(", ")')
  [ -z "$FRONTIER" ] && { echo "No unblocked issues."; break; }

  claude --message "Unblocked GitHub issues, takeable right now: $FRONTIER. Pick the highest-risk one of those that still needs implementation. Use /execute to implement exactly one reviewable slice. Run the repo's feedback loops. If all issue work is complete, say DONE and stop."
  # ... (rest of the script remains the same)
```

Run in a sandboxed environment (Docker or separate terminal). Each iteration is a fresh context window.

The frontier query needs `gh` >= 2.94.0 (see `README.md` § Installation), which exposes `blockedBy` as a `--json` field; `gh issue list` also excludes pull requests by definition, so no filter is needed. Note `state` is the GraphQL enum — uppercase `OPEN`, where the REST endpoint returns lowercase. `/prd-to-issues` §7 wires the edges this reads; `/help` and `/execute` select by the same empty-`open_blockers` rule, so every selection site in the pipeline agrees by construction.

Do **not** introduce a committed `progress.txt` file in this repo. Ralph's durable progress substrate here is GitHub-native state plus commits: PRD issues, slice issues with dependencies, QA issues, issue comments with exact errors, and the commit history itself. That keeps the repo aligned with its "state lives in GitHub, not the filesystem" rule.

### Pre-commit hooks:

`/init-pipeline` handles this automatically — it detects existing tools (formatter, linter, hook manager, package manager), confirms with the user, and invokes `/setup-pre-commit` with the confirmed tools. Defaults to Lefthook + Biome + pnpm if nothing is detected. You can also invoke `/setup-pre-commit` directly if you only want pre-commit hooks without the full pipeline enforcement setup.

---

## Quick Reference

| I want to... | Do this |
|---------------|---------|
| Start a new feature | `/shape` to establish what to build, then hand off to `/research` |
| Plan a blank project or major tranche | `/shape`, then `/create-milestone` if the work requires multiple independent PRDs. If it fits one PRD (even if big-batch), stay on the default path — `/write-a-prd` creates a container milestone |
| Research the technical approach | `/research` (always runs, depth auto-calibrated, invokes `/api-design-review` for higher-risk API contract work, then hands off to `/write-a-prd`) |
| Verify a technical assumption before committing | `/prototype` FEASIBILITY — write a focused spike (one automated test, or a scratch route when visual confirmation is required), capture the verdict in the calling artifact (e.g. downgrade an `Uncertain` tag in the research doc), delete the spike in the same change |
| Feel out a state model or compare layout variants | `/prototype` LOGIC (terminal app over a pure reducer/state machine) or `/prototype` UI (radically different variants on one route, switchable from a floating bar) |
| Promote a milestone feature into the pipeline | Expand the selected feature issue from `roadmap bet` to `research-ready`, then run `/research` |
| Write a shaped pitch | `/write-a-prd` → shaped pitch filed as GitHub issue (appetite → solution → rabbit holes → no-gos, includes API contract sketch when relevant, auto-invokes `/design-an-interface` or `/api-design-review` when needed, then hands off to `/prd-to-issues`) |
| Break into work items | `/prd-to-issues` → GitHub issues with boundary maps that feed `/execute`; Ralph can run the AFK loop over unblocked issues |
| Set up pipeline enforcement | `/init-pipeline` — scaffold Claude Code hooks, git guardrails, pre-commit hooks, pnpm enforcement (auto-invoked by `/execute`) |
| Set up Ralph for a repo | `/setup-ralph-loop` — generate `ralph-once.sh` and bounded `ralph.sh` adapted to the repo's task source and feedback loops |
| Execute AFK | Start with HITL Ralph first, then run a bounded Ralph loop over the highest-risk unblocked issues once the prompt and quality bar are proven |
| Execute HITL | Run `/execute` directly on a specific issue, then `/pre-merge` after verification |
| Write tests first | `/tdd` for strict red-green-refactor, usually delegated from `/execute` |
| Run a QA session or report bugs | `/qa` — single entry point for bug conversations; files lightweight GitHub issues in domain language and delegates per-issue to `/triage-issue` when a specific bug needs root-cause diagnosis |
| Review and create PR before merge | `/pre-merge` — creates PR with PRD lineage, runs architectural review |
| Keep review findings from evaporating between sittings | `/pre-merge --loop` — loop-mode; records every finding in a durable PR ledger with its evidence, auto-runs `/ts-audit` on changed `.ts`/`.tsx`, makes no commits and no decisions, and is what an AFK `/execute` hands off to |
| Understand a branch commit-by-commit before merging it | `/walk-commits` — interactive per-commit walkthrough (intent, riskiest line, deliberate oddities, what's absent by design) with 🟢/🟡/🔴 sign-off; optional, recommended by `/pre-merge`, distinct from its defect review |
| See the shape of a multi-file change before reading lines | `/visual-recap` — render a finished diff/PR/branch as a transient self-contained interactive HTML recap with line-anchored callouts, before/after, and a copy-text feedback loop; optional, never auto-invoked, skips small/obvious diffs, comprehension not defect-finding |
| Merge a reviewed PR and return to a clean base | `/closeout` — confirm, merge, switch off the worktree before removing it, prune the merged branch, pull base, verify a clean end state |
| Improve Skill Kit itself | `/improve-pipeline` — capture a pipeline-level lesson as a GitHub issue in `chrislacey89/skills` after loading canonical Skill Kit context |
| Investigate a specific bug deeply | Start with `/qa` — its Step 3.5 depth check delegates to `/triage-issue` for root-cause analysis, structural diagnosis, and a TDD fix plan that flows into `/execute` |
| Plan a refactor | `/request-refactor-plan` — tiny commits RFC as GitHub issue, then implement via `/execute` |
| Find architecture improvements | `/improve-codebase-architecture` — surface deepening opportunities that can become refactor work |
| Capture lessons learned | `/compound` — by default onto the open PR before `/closeout` merges, so the lesson is reviewed and merged with the code that taught it; post-merge as the fallback for lessons that surface at/after merge |
| Define domain terms | `/ubiquitous-language` to build or update the glossary + decisions register, then reuse that language in shaping, QA, and issue writing |
| Record a decision | Add a row to the decisions register in ubiquitous language doc |
| Clean up after ship | Close the PRD issue and any remaining slice issues; the research artifact persists (archive file outside the repo, or closed spike issue in GitHub) and is never deleted — supersede with a new dated artifact if research changes |
| Audit TypeScript code quality | `/ts-audit` on a file, directory, or glob — produces a structured report of type-safety findings |
| Figure out where I am in the pipeline | `/help` — reads repo state (branch, PRs, issues, research archive, milestones) and recommends the next skill with a one-line reason |
| Understand an explanation that did not land | `/re-pitch` — diagnose whether the reader is missing a term, the situation, or was given too much at once; re-state under checkable rules with every domain term glossed on first use; returns control to whatever was in flight |
| Compact a long session into a fresh-start doc | `/handoff [next-session focus]` — writes a transient doc at a `mktemp` path referencing durable state rather than duplicating it; for mid-skill, exploratory, or cross-agent handoffs, not routine inter-skill ones |
