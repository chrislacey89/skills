# The trivial-task exception

This file is the canonical statement of the rule. `/execute` Step 0 points at it
from its TDD classification gate, and `/lfg` points at it to auto-size its tiny
path. Neither restates it — `docs/restated-claims.md` is the standing account of
why a rule stated at two operative sites drifts.

**Trivial-task exception.** For single-commit cleanups unrelated to active feature work — typo fixes, dead code removal, comment-only changes, formatting-only changes, dependency version bumps without API surface changes — you may skip classification by creating `.claude/.tdd-skipped` directly. This exception applies only when **all** of the following are true:

- The task is not tied to an open GitHub issue, PRD, slice issue, or QA bug
- The task is not part of an active feature branch created for multi-slice work
- The change is expected to be a single commit (not a sequence of logical units)
- The change does not touch behavior — no new conditionals, no new state, no new exported symbols, no schema or migration changes

If any of these is false, go through the normal classification gate. When in doubt, use the gate — the cost of one extra `/tdd` invocation is lower than the cost of an unverified behavior change slipping through as "trivial."
