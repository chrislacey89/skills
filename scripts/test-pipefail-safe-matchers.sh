#!/usr/bin/env bash
# The literals below quote shell syntax — `grep -q`, `<<<"$var"` — so single
# quotes are what keeps them literal. File-wide, so it precedes the first command.
# shellcheck disable=SC2016
# test-pipefail-safe-matchers.sh — no committed suite may feed a producer into
# an early-exiting reader while `pipefail` is on.
#
# THE DEFECT: `producer | grep -q NEEDLE` under `set -o pipefail`.
#
# `grep -q` exits at the first match. The producer to its left is still writing,
# takes SIGPIPE, and dies non-zero. Under `pipefail` the *pipeline* then reports
# that failure — so the caller reads "no match" from a pipeline that matched.
#
# It is invisible at small sizes. If the producer's whole output fits in the pipe
# buffer it finishes writing before `grep -q` exits, and the pipeline is correct.
# The bug appears only when the haystack outgrows the buffer, which happens when
# a file the suite scans *grows* — long after the assertion was written and
# reviewed. The two directions it fails in are not symmetric:
#
#   assert_has   -> reports FAIL on a needle that is present  (loud, annoying)
#   assert_lacks -> reports  ok  BECAUSE the needle was found (silent, and wrong)
#
# The second is the one that matters: a ban that passes because the banned thing
# is there. It reproduced in this repo during PR #308 — `docs/visual-recap-
# design.md`, then 93 KB, answered NOT-FOUND for a needle it contains, while the
# 27 KB `docs/visual-rendering-core.md` answered correctly from the identical
# two lines. Both files have grown since, which is the point: nothing about the
# assertions changed.
#
# THE FIX, and why it is not "add `|| true`": take the producer out of the
# pipeline, so `pipefail` has no second exit status to see.
#
#   grep -q NEEDLE <<<"$var"          # variable haystack
#   grep -q NEEDLE < <(producer)      # command haystack
#
# `|| true` only hides the wrong status; the pipeline still races, and the next
# reader sees a matcher whose correctness depends on a file staying small.
#
# WHY A TEST AND NOT PROSE: docs/solutions/testing-patterns/
# validate-the-instrument-not-only-the-subject-2026-08-23.md already recorded
# this pattern — a measuring instrument that fails while reporting normally —
# and shipped prose for it, on the stated ground that its instruments "were
# ad-hoc, authored in-session, and discarded. Nothing in a repository can assert
# a property of a script that was never written to it." That reason does not
# hold for this instance: the instrument is a committed suite, and siblings of
# the same shape were committed across a dozen-plus files. Committed instruments
# are exactly what a repository *can* assert a property of.
#
# REACH — stated, because a mechanism that implies coverage it lacks is the
# defect one level up (see mechanism-generality-lags-the-pattern-2026-08-23.md):
# this suite catches the `| grep -q` form in every spelling GNU and BSD grep
# accept — the clustered short flags (`-q`, `-qF`, `-Fq`) and the long forms
# (`--quiet`, `--silent`). The long forms are named explicitly because the
# first draft of this regex required a single literal `-` before the flag
# cluster, so `grep --quiet` reproduced the bug and the detector reported
# "ok" against a repo containing it. A guardrail that a rename walks straight
# past is the shape this suite exists to prevent, one level down. It does NOT
# catch the truncating-read form (`sed -n 'Np' | cut -c1-200` losing a claim
# past the cut) — that is instance 2 of the entry above and stays prose, because
# "this cut is too narrow for its input" is not decidable from the text.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

printf '\n=== 1. No committed suite pipes a producer into `grep -q` ===\n'

# Strip comment-only lines first: this file's own header describes the banned
# shape, and a detector that flags its own explanation is the self-matching
# defect #306's mutation pass found in its suite. `||` is excluded separately —
# `cmd || grep -q …` is a fallback, not a pipeline, and has no producer to kill.
violations="$(
  for f in scripts/*.sh; do
    [ "$f" = "scripts/test-pipefail-safe-matchers.sh" ] && continue
    grep -nE '\|[[:space:]]*grep[[:space:]]+(--quiet|--silent|-[A-Za-z]*q)' "$f" \
      | grep -vE '^[0-9]+:[[:space:]]*#' \
      | grep -vE '\|\|[[:space:]]*grep' \
      | sed "s|^|$f:|" || true
  done
)"

if [ -z "$violations" ]; then
  ok "no 'producer | grep -q' pipeline in any committed suite"
else
  n=$(wc -l <<<"$violations" | tr -d ' ')
  bad "$n pipeline(s) feed a producer into 'grep -q' under pipefail"
  sed 's/^/       /' <<<"$violations"
  printf '       fix: grep -q NEEDLE <<<"$var"   or   grep -q NEEDLE < <(producer)\n'
fi

printf '\n=== 2. No capture dies before its own diagnostic can print ===\n'

# The sibling shape, and the one that fails *silently in the other direction*.
#
#   var="$(producer | head -1 | cut -d: -f1)"
#
# `head` exits after its line, so the producer takes SIGPIPE — but the louder
# case needs no SIGPIPE at all: when `grep` simply finds nothing it exits 1, and
# under `set -e` + `pipefail` the assignment aborts the whole script *there*.
# Every one of these captures is followed by a hand-written empty-check —
# `FAIL Step 1 instruction not found`, `FATAL: no loop-pass marker template
# found` — that exists precisely for the not-found case and is unreachable when
# it happens. CI still reddens; the crafted reason never prints.
#
# `|| true` is the correct guard here rather than a mask: the next line already
# decides what an empty capture means, and this only lets it run.
capture_violations="$(
  for f in scripts/*.sh; do
    [ "$f" = "scripts/test-pipefail-safe-matchers.sh" ] && continue
    grep -q 'set -[a-z]*o pipefail\|set -o pipefail' "$f" || continue
    grep -nE '=\"?\$\(.*\|[[:space:]]*head\b' "$f" \
      | grep -vE '^[0-9]+:[[:space:]]*#' \
      | grep -vF '|| true' \
      | sed "s|^|$f:|" || true
  done
)"

if [ -z "$capture_violations" ]; then
  ok "every '\$(… | head …)' capture under pipefail is guarded"
else
  n=$(wc -l <<<"$capture_violations" | tr -d ' ')
  bad "$n capture(s) abort before their own empty-check can run"
  sed 's/^/       /' <<<"$capture_violations"
  printf '       fix: append `|| true` inside the substitution, so the next line decides\n'
fi

printf '\n=== 3. The replacement forms are actually safe (not just different) ===\n'

# A sweep that swaps one unsafe idiom for another is the defect class
# re-introduced by its own correction — sweep-commits-reintroduce-their-own-
# defect-class-2026-08-18.md. So prove both replacements on a haystack far
# larger than any pipe buffer, with the needle at the very front so an
# early-exiting reader is guaranteed to quit while the producer is mid-write.
big="$(python3 -c 'print("NEEDLE"); print("x"*200000)')"

if grep -q 'NEEDLE' <<<"$big"; then
  ok "here-string form finds a front-loaded needle in a 200 KB haystack"
else
  bad "here-string form MISSED a needle it contains — replacement is unsafe"
fi

if grep -q 'NEEDLE' < <(printf '%s\n' "$big"); then
  ok "process-substitution form finds a front-loaded needle in a 200 KB haystack"
else
  bad "process-substitution form MISSED a needle it contains — replacement is unsafe"
fi

# The negative control: the banned form must actually be broken here, or this
# suite is banning a shape that does nothing and rows 1-2 prove nothing.
# (Guarded so a future shell/grep that fixes the race turns this into a
# reported change rather than a silent green.)
if printf '%s\n' "$big" | grep -q 'NEEDLE'; then
  ok "NOTE: the banned form answered correctly here — the race did not fire on this shell/grep; the ban still stands on the reproduced 93 KB case"
else
  ok "banned form reproduces the defect: reports NOT-FOUND for a needle it contains"
fi

printf '\n=== 4. The detector matches every spelling of the banned flag ===\n'

# The evasion this suite shipped with in its first draft: a regex requiring one
# literal `-` before the flag cluster reported clean against `grep --quiet`,
# which reproduces the defect identically. Planted here rather than asserted, so
# a future narrowing of the regex reddens instead of going quietly vacuous.
plant_dir="$(mktemp -d)"
trap 'rm -rf "$plant_dir"' EXIT
plant_scan() {  # $1 = the line to plant. echoes the detector's verdict lines.
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "$1" > "$plant_dir/planted.sh"
  grep -nE '\|[[:space:]]*grep[[:space:]]+(--quiet|--silent|-[A-Za-z]*q)' "$plant_dir/planted.sh" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -vE '\|\|[[:space:]]*grep' || true
}

for spelling in \
  'printf "%s" "$x" | grep -q NEEDLE' \
  'printf "%s" "$x" | grep -qF NEEDLE' \
  'printf "%s" "$x" | grep -Fq NEEDLE' \
  'printf "%s" "$x" | grep --quiet NEEDLE' \
  'printf "%s" "$x" | grep --silent NEEDLE'
do
  if [ -n "$(plant_scan "$spelling")" ]; then
    ok "flags: $spelling"
  else
    bad "walked past a banned spelling: $spelling"
  fi
done

# …and the two shapes it must NOT flag, or it cries wolf and gets deleted.
for allowed in \
  'grep -q NEEDLE <<<"$x"' \
  'grep -q NEEDLE < <(producer)' \
  'producer || grep -q NEEDLE file'
do
  if [ -z "$(plant_scan "$allowed")" ]; then
    ok "leaves alone: $allowed"
  else
    bad "false positive on a safe form: $allowed"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
