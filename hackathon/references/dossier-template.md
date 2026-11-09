---
phase: profile        # profile | choose | shape | build | demo | done
event: <event name>
date: <YYYY-MM-DD of the event>
brief: <URL or "pasted">
---

# Hackathon dossier: <event name>

## Event profile

| Field | Status | Value (verbatim quote when stated) |
|---|---|---|
| Start time | stated / not stated | |
| Build window | | |
| Submission deadline and platform | | |
| Judging format and length | | |
| Judging criteria and weights | | |
| Tracks and prizes (incl. sponsor) | | |
| Category entry (pick one, or eligible for every award) | | |
| Stated values about what wins | | |
| Kickoff remarks (examples given, judges per table) | | |
| Team size | | |
| Pre-built code, templates, installed tooling | | |
| Allowed tools and models | | |
| Required artifacts (repo, video, write-up) | | |

## Team

| Person | Writes code? | Lane (build / demo / both) | Accounts to log in |
|---|---|---|---|
| | | | |

## Open questions for the organizers

- Does installed developer tooling (agent skills, hooks, CLIs) count as pre-built code?
- <one line per `not stated` field that matters>

## Reference class

- <past winner>: <what it had in common with the others>, or `none found`

## Candidates

| # | One-liner | Fit | Familiar surprise | Peak moment | 60-s legibility | Factory | Slow-dep risk | Why you | Total |
|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | |

Weights: <stated weights, or "equal; none stated">

Blind second scorer: <cells that met the Locked disagreement threshold, and how each was settled>

**Chosen:** #<n>
**High-concept line:** <a known X, with Y>
**Peak moment:** <the one thing the judge watches happen, that they don't predict>
**Award line:** <the best (award) entry in the room because (reason, in the organizers' words)>
**Said back by:** <who, outside the build, repeated what it is and why it wins>
**Real-world ground:** <the dataset, standard, or official system it is built on>
**What the AI does that a judge can watch:** <reads / decides / explains / builds; "drafts only" caps Peak moment at 3>

## Scope ladder

| Rung | Adds (what a judge notices) | Done when | Tracer test | Acceptance script (3 min, phone) | Stretch |
|---|---|---|---|---|---|
| 1 | tracer bullet: <end-to-end path> | | | | |
| 2 | | | | | |
| S | submission page: every required section, video by the story checkpoint | page matches the required artifacts | — | demo-lane owner reads it on a phone | never `~` |
| … | | | | | `~` |

The peak-moment rung and the most ambitious AI rung are never `~`.

**Who sees what** (signed off by: <non-builder>):

| Role | Sees | Can do | Guards |
|---|---|---|---|
| | | | |

**Identity:** name <…> · tagline <…> · domain <…> · email-sending domain <…> · visual direction and component library <…>

**Rabbit holes / no-gos:**
- <part> → <what to do instead>

**Slow-dependency work (kickoff block / rung 1):**
- <keys, auth, deploy target (final hostname), riskiest integration, data access>

**Factory plan:** <hooks, CI, scan, logging, decision log>

**Lane owners:** build: <name(s)> · demo: <name, or "solo: folded into checkpoints">

Non-builder scorer column (Phase 1): <their scores, taken before they saw either grid>, or `none`

## Decision log (seed for DECISIONS.md)

| Decision | Alternatives rejected | Why |
|---|---|---|
| | | |

## Pre-flight (night before)

- [ ] Project chosen; award line said back by someone outside the build
- [ ] Accounts logged in on the build machine (git host, model provider, deploy target)
- [ ] Every API key tested with one real call, under the env var name the code will read
- [ ] Domain bought; email-sending domain verified; paid tiers on
- [ ] Who-sees-what table signed off; visual direction and component library chosen
- [ ] Deploy target reachable; hello-world deploy rehearsed
- [ ] Chargers, adapters, hotspot
- [ ] Rules guide read; Event profile rechecked against it

## Clock plan

| Mark | Time |
|---|---|
| Start | |
| Kickoff block ends | |
| Checkpoints | |
| First Q&A drill (second checkpoint) | |
| Restyle cutoff (second checkpoint) | |
| Story checkpoint (last before the freeze) | |
| Freeze | |
| Submit by | |
| Deadline | |

## Rung log

| Rung | Start | End | Minutes | Notes |
|---|---|---|---|---|

## Checkpoint re-plans

| Time | Median rung (min) | Rungs that fit | Kept | Cut | Added |
|---|---|---|---|---|---|

## Pre-demo (DO-CONFIRM, at the freeze)

- [ ] Seeded demo data shows the peak moment on the first try
- [ ] Fallback video of the demo path recorded and saved locally
- [ ] Tests green, CI green
- [ ] Deployed URL loads on a phone and on venue wifi or a hotspot
- [ ] No secrets in the repo or the logs
- [ ] README top: high-concept line, how to run, how it was built
- [ ] Submission page has every required artifact, known limitations included
- [ ] Test, commit, and decision counts match across the page, the README, and the site

## Pre-handoff confirmations (after Phase 4 steps 2-4)

- [ ] Submission filed before the submit-by time
- [ ] Table script rehearsed at full length and at 15 seconds
- [ ] Judge Q&A drilled from DECISIONS.md
- [ ] No commits pushed after the deadline

## After the event (logged during the window, not done)

- <pack improvements, retrospective notes, internal docs>

