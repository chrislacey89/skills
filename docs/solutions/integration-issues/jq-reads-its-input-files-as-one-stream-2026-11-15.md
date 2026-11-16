---
date: 2026-11-15
category: integration-issues
problem_type: batching per-file jq reads into one invocation removes the file boundary, so a JSON value can start in one file and end in the next and a corrupt pair parses as valid
components: [init-pipeline/scripts/sidecar.sh, owners_scan, owners_of]
technologies: [jq, bash]
severity: medium
volatility: stable
---

# jq reads every input file as one stream

## Problem

jq treats the files named on its command line as one continuous input stream, not as separate documents. A JSON value can begin in one file and end in the next, and `input_filename` names only the file where the value ended. A lookup that merged one jq call per file into one jq call over all the files lost the per-file parse boundary that the old error handling depended on.

```bash
printf 1 > c; printf 2 > d
jq -n -c '[inputs, input_filename]' c d     # [12,null]
```

## Context

`sidecar.sh` resolved a checkout's sidecar by asking, for each key, which `sidecar.json` lists it. It started one `jq -e` per file per key. Each call either parsed its one file or failed, and a failure was reported as "cannot read <file>; refusing to treat it as a miss" (#530). That rule keeps an unreadable sidecar from answering `github`.

To start one jq per resolve instead of K+3, `owners_scan` passed every `sidecar.json` to a single `jq -n 'reduce inputs …'`. It guarded against a file holding zero or several values by grouping values on `input_filename` and requiring one value per file.

A review then split one value across two files: `a/sidecar.json` = `{"keys":[]} {"keys":["remote:…"]` and `b/sidecar.json` = `}`. Neither file parses alone. The per-file read refused both. The batched read counted one value per file, credited the second value to `b`, and resolved to `b` with exit 0.

## Symptoms

- A lookup over several files returns an answer while running jq on each file alone exits non-zero.
- `input_filename` is `null`, or names the later of two files for a value that began in the earlier one.
- A per-file value count passes even though a file is truncated or holds a fragment.

## Root Cause

The input stream is the unit jq parses, not the file. When files are named on the command line, jq concatenates them before parsing, so a value's text can cross files. Any per-file check built on `inputs` or `input_filename` (counting values per file, keying results by file) is measured after the boundary is already gone, so it cannot detect a value that crossed it.

## Learning Level

- **Level:** Pattern
- **Feedback loop or delay:** The batching was a performance change, and every existing corrupt-file test kept passing, because each used a single bad file. With only one bad file the next file's leading `{` still forces a parse error. Only a value split exactly across a file boundary shows the difference, and no test had one until a reviewer built it.

## Rule Scope

- **Applies when:** several files are read in one jq invocation as positional inputs (`jq … f1 f2 …` with `inputs`, `input`, `--slurp`, or the implicit input loop), and the result must be correct per file, or a parse failure in one file must be reported against that file.
- **Inverts or does not apply when:** the files are deliberately one logical stream (NDJSON shards, concatenated logs), where crossing values are impossible by construction or acceptable. One jq per file keeps the boundary too, at the process cost this change was trying to avoid.
- **Sibling docs:** `docs/solutions/architecture-decisions/compat-default-is-every-failures-answer-2026-10-24.md` covers the consequence this guards: a sidecar that cannot be read must never be answered as "no sidecar".

## Solution

Read each file as its own string and parse it with `fromjson`, inside the one jq call. A value then cannot leave its file, and `fromjson` errors on a string holding no value, several values, or a fragment. Any error fails the whole call, and the caller falls back to the per-file read, which names the bad file.

**Before** (one stream; a split value passes):

```bash
jq -n -r 'reduce inputs as $d ({}; .[input_filename] += [$d]) | …' "${files[@]}"
```

**After** (one string per file; parsed alone):

```bash
for f in "${files[@]}"; do jqargs+=(--rawfile "f$i" "$f" --arg "p$i" "$f"); i=$((i + 1)); done
jq -n -r --argjson n "${#files[@]}" '
  $ARGS.named as $a
  | [range(0; $n) | {f: $a["p\(.)"], d: ($a["f\(.)"] | fromjson)}] | …' "${jqargs[@]}"
```

`--rawfile`, its entry in `$ARGS.named`, and `fromjson`'s rejection of empty, whitespace-only, and multi-value strings were checked on jq 1.6 (Ubuntu 20.04) and 1.7.1. The process count stays at one per resolve.

## Prevention

**Code-level:** `scripts/test-state-backend.sh` builds the split pair (`{"keys":[]} {"keys":[…]` / `}`) and asserts that resolve refuses with exit 1, prints nothing on stdout, and names both files on stderr. Reverting `owners_scan` to one input stream fails those three assertions, and none of the pre-existing corrupt-file cases do.

**Process-level:** When a change batches N per-item tool invocations into one, list the failure boundaries each invocation gave for free: process exit status, parse unit, timeout, working directory. Show that the batched form still has each one, or add a test that splits an input across the new seam.

## Key Decision

**Decision:** Keep one jq per resolve, with per-file parsing via `--rawfile` + `fromjson`. On any jq error, fall back to the existing per-file read rather than reproducing its error text.
**Rationale:** The process count is the point of the change, and the fallback keeps every #530/#542 refusal and warning coming from the code that already produces it.
**Alternatives considered:** One jq per file (correct, but K processes per call); a single stream plus heuristics to detect crossing (cannot see what the stream already merged).
**Revisable:** Yes, if `ARG_MAX` ever binds (about 5,000 sidecars) or jq gains a per-file input mode.

## Related

- PR #742 (one jq per resolve), review finding C1, fix `ae7a932`.
- Open on the same PR, not fixed here: the per-file `jq -e` read treats a `sidecar.json` holding several JSON values as a miss (it answers from the last value), so `backend` answers `github`. This predates #742 and is the compat-default failure from the sibling entry above.

## Shelf Life

Until jq offers a documented per-file input boundary, or `sidecar.sh` stops reading `sidecar.json` with jq.
