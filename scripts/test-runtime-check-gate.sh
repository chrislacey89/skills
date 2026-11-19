#!/usr/bin/env bash
# Its patterns match literal Markdown backticks; expansion would defeat them.
# shellcheck disable=SC2016
# test-runtime-check-gate.sh — /execute runs a declared verify.runtime_check
# where verification needs it, and stops when it fails (#711).
#
# THE DRIFT CLASS. A worktree isolates files, not a running stack. Tests run in
# a second worktree can pass against another worktree's database or dev server,
# and read as verified. `verify.runtime_check` is the repo's declared command
# that exits 0 only when this worktree's own stack answers. Its value is in
# where /execute runs it and what a failure does; a rewording that drops the
# stop turns a declared precondition back into a note nobody reads.
#
# WHAT THIS PINS, reading the real files:
#   1. /execute Step 4 runs runtime_check before the test command (the
#      paragraph comes first, before Tier 1), says HITL waits and AFK stops,
#      and says an undeclared or `none` field keeps today's behavior.
#   2. Tier 2.5 runs it again and stops on failure rather than noting a skip.
#   3. Step 0 never runs it: every Step 0 mention points at Step 4.
#   4. /init-pipeline's verify question asks for it.
#   5. The field /execute reads is one sidecar.sh writes: `runtime_check` is in
#      VERIFY_FIELD_NAMES, the one list `config set`, `profile`, and the
#      `unasked=` line read.
#
# WHAT THIS DOES NOT PIN. Whether a repo's command checks the right stack; the
# pack cannot tell, and the question text says so.

set -u
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repo_root" || exit 1
ex=execute/SKILL.md

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ "$#" -lt 2 ] || printf '       %s\n' "$2"; fail=$((fail + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }
has() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else bad "$1" "no '$2' in that text"; fi; }

step0="$(awk '/^### 0\. /{f=1; next} /^### 1\. /{f=0} f' "$ex")"
step4="$(awk '/^### 4\. /{f=1; next} /^#### Tier 1/{f=0} f' "$ex")"
tier25="$(awk '/^#### Tier 2\.5/{f=1; next} /^#### /{f=0} f' "$ex")"
para="$(grep '^\*\*Runtime check, when declared\.\*\*' <<<"$step4" || true)"

section "/execute Step 4: runtime_check runs before the test command"
if [ -n "$para" ]; then ok "Step 4 has the runtime-check paragraph before Tier 1"; else bad "Step 4 has the runtime-check paragraph before Tier 1"; fi
check_line="$(grep -n '^\*\*Runtime check, when declared\.\*\*' <<<"$step4" | cut -d: -f1)"
test_line="$(grep -n '^Run the typecheck and test commands listed under `Verify`' <<<"$step4" | cut -d: -f1)"
if [ -n "$check_line" ] && [ -n "$test_line" ] && [ "$check_line" -lt "$test_line" ]; then
    ok "the runtime check comes before the test command"
else
    bad "the runtime check comes before the test command" "check at line '${check_line:-none}', test command at '${test_line:-none}' of Step 4"
fi
has "it names the field it runs" '`runtime_check`' "$para"
has "it starts or stops nothing" 'never starts or stops anything' "$para"
has "HITL tells the user and waits" 'in a HITL run, tell the user what it printed and wait' "$para"
has "AFK stops" 'in an AFK iteration, **stop**' "$para"
has "none or undeclared keeps today's behavior" 'Printed as `none`, or not declared at all: there is nothing to check' "$para"

section "/execute Tier 2.5: runs it again, and a failure stops"
t25_line="$(grep -F 'runtime_check' <<<"$tier25" || true)"
has "Tier 2.5 runs runtime_check" '`runtime_check` passes' "$t25_line"
has "a failure stops rather than being noted" 'it is not a skipped check to note' "$t25_line"

section "/execute Step 0 never runs it"
n=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    case "$line" in
        *"(Step 4)"*) ;;
        *) bad "a Step 0 mention of runtime_check points at Step 4" "${line:0:200}" ;;
    esac
done < <(grep -F 'runtime_check' <<<"$step0" || true)
ok "$n Step 0 mention(s) read, each checked above"

section "/init-pipeline asks for it"
if grep -qF '**`runtime_check`**' init-pipeline/SKILL.md; then ok "/init-pipeline's verify question names runtime_check"; else bad "/init-pipeline's verify question names runtime_check"; fi

section "the field is one sidecar.sh writes (stream 1 adds it)"
names="$(sed -n 's/^VERIFY_FIELD_NAMES=(\(.*\))$/\1/p' init-pipeline/scripts/sidecar.sh)"
if [ -z "$names" ]; then
    bad "sidecar.sh has a VERIFY_FIELD_NAMES line" "not found"
elif tr ' ' '\n' <<<"$names" | grep -qx runtime_check; then
    ok "runtime_check is in sidecar.sh's VERIFY_FIELD_NAMES ($names)"
else
    bad "runtime_check is in sidecar.sh's VERIFY_FIELD_NAMES" "the list is: $names"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
