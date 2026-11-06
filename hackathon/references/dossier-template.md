---
phase: profile        # profile | choose | shape | build | done
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
| Team size | | |
| Pre-built code, templates, installed tooling | | |
| Allowed tools and models | | |
| Required artifacts (repo, video, write-up) | | |

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

Blind second scorer: <cells that differed by 2 or more, and how each was settled>

**Chosen:** #<n>
**High-concept line:** <a known X, with Y>
**Peak moment:** <the one thing the judge watches happen>

## Scope ladder

| Rung | Adds (what a judge notices) | Done when | Tracer test | Stretch |
|---|---|---|---|---|
| 1 | tracer bullet: <end-to-end path> | | | |
| 2 | | | | |
| … | | | | `~` |

**Rabbit holes / no-gos:**
- <part> → <what to do instead>

**Slow-dependency work (kickoff block / rung 1):**
- <keys, auth, deploy target, riskiest integration, data access>

**Factory plan:** <hooks, CI, scan, logging, decision log>

## Decision log (seed for DECISIONS.md)

| Decision | Alternatives rejected | Why |
|---|---|---|
| | | |

## Pre-flight (night before)

- [ ] Accounts logged in on the build machine (git host, model provider, deploy target)
- [ ] Every API key tested with one real call
- [ ] Deploy target reachable; hello-world deploy rehearsed
- [ ] Chargers, adapters, hotspot
- [ ] Rules guide read; Event profile rechecked against it

## Clock plan

| Mark | Time |
|---|---|
| Start | |
| Kickoff block ends | |
| Checkpoints | |
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
- [ ] Submission filed before the submit-by time
- [ ] Table script rehearsed at full length and at 15 seconds
- [ ] Judge Q&A drilled from DECISIONS.md
