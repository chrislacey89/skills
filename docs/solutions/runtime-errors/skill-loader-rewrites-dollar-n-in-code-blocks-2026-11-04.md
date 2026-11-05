---
date: 2026-11-04
category: runtime-errors
problem_type: the text an agent loads from a SKILL.md differs from the file on disk, because the skill loader rewrites $N to the invocation's arguments inside code blocks, so awk and shell snippets break only when the skill is invoked with arguments
components: [prd-to-issues/SKILL.md, excavate/SKILL.md, respond-to-review/SKILL.md, fix-findings/SKILL.md, execute/SKILL.md, closeout/SKILL.md, setup-ralph-loop/SKILL.md, scripts/test-skill-arg-substitution.sh]
technologies: [claude-code, awk, bash]
severity: high
volatility: volatile
---

# The skill loader rewrites `$N` inside a SKILL.md's code blocks

## Problem

When a skill is invoked with arguments, Claude Code replaces `$0`, `$1`, ... in the SKILL.md body with those arguments, inside fenced code blocks too. awk's `$0` (the current line) and `$1` (the first field), and a shell script's `$0`/`$1`, become the arguments. The file on disk is unchanged, so nothing that reads the file sees the broken text.

## Symptoms

- prd-to-issues' Blocked-by reconcile reported `MISMATCH` for every slice that has blockers, and `match` for every slice without. No error was printed.
- Running the same block from the file by hand works. The failure appears only in an invoked skill, and only when arguments were passed.
- awk raises no syntax error: an argument such as `ITEM-9` parses as the expression `ITEM - 9`, which evaluates to a number.

## Root Cause

`$N` is the loader's shorthand for `$ARGUMENTS[N]` (https://code.claude.com/docs/en/skills), and substitution is textual over the whole body. A probe skill on Claude Code 2.1.318, invoked with two arguments, gave:

| Spelling in the file | What the agent loaded |
|---|---|
| `$0`, `$1` | the 1st and 2nd argument |
| `$2` (with only two arguments) | `$2`, unchanged |
| `$(1)`, `${1}`, `$ 0`, `$NF`, `$10` | unchanged |

So a reference is replaced exactly when N is lower than the argument count. That is why a skill that usually runs with no arguments looks fine. `/fix-findings 1 3` rewrites both `$0` and `$1`.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** none existed. Every contract suite reads the SKILL.md file, never the text the agent loads, so a whole class of defect was invisible to CI. The failure surfaces only in a downstream run, as wrong data rather than an error.

## Rule Scope

- **Applies when:** the text is in a SKILL.md body, the skill can take arguments (any skill can be typed with them), and the snippet uses a single-digit positional or field reference: awk, shell, Perl.
- **Does not apply when:** the file is not a skill body, such as `references/*.md`, `SYSTEM-OVERVIEW.md`, or `docs/*.md`, which an agent reads with the Read tool and which no loader rewrites. `SYSTEM-OVERVIEW.md`'s ralph script keeps `$1` for that reason.
- **Sibling docs:** `testing-patterns/a-preset-variable-tests-a-path-no-run-takes-2026-10-26.md`. The class is the same (a test exercises a different channel than the agent's), but the direction differs. There, the test supplies input the agent never has. Here, the agent's channel transforms text the test reads untransformed.

## Solution

Spell awk field references `$(N)`, which is a POSIX awk field expression, and shell positional parameters `${N}`. Both survive the loader and behave identically: prd-to-issues' and respond-to-review's readers gave the same output under macOS awk, mawk, and gawk.

**Before:**
```text
awk '/^## /{on = ($0 ~ /^## Blocked by[[:space:]]*$/); next} on'
```

**After:**
```text
awk '/^## /{on = ($(0) ~ /^## Blocked by[[:space:]]*$/); next} on'
```

A bare regex (`on = /^## Blocked by/`) also avoids `$0` there, but `$(N)` is one rule that covers every field reference, including `$1` and `$2`.

`\$0` is not an escape to rely on: the probe could not show that the loader strips the backslash in every case, and awk rejects one that survives.

## Prevention

**Code-level:** `scripts/test-skill-arg-substitution.sh` fails on any bare `$<digit>` (not followed by another digit) in a tracked `*/SKILL.md`, in CI and in lefthook pre-push. Two gaps from PR #707's review were open when this was written: the self-check runs its own copy of the regex rather than the one the scan uses, and the scan passes when it read no files (outside a git checkout).

**Process-level:** the probe result is pinned by nothing. A loader change in a later Claude Code could start rewriting `$(N)` or `${N}`, and no suite would notice. Re-run the probe when bumping `.claude-code-version`. It is a throwaway skill under `.claude/skills/probe/` in a scratch repo, invoked with `claude -p "/probe A B"`, asking the model to echo a few `$` spellings verbatim.

## Defect Classification (bug-fix compounds only)

**Origin phase:** Coding error (in a harness the pack does not control)
**Fix type:** Workaround. The real fix is upstream: no substitution inside code blocks, or a documented escape.

## Related

- PR #707

## Shelf Life

When Claude Code stops substituting inside fenced code blocks, or documents an escape. Then the spelling rule and its test can go.
