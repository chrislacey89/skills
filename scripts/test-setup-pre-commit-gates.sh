#!/usr/bin/env bash
# test-setup-pre-commit-gates.sh — executable contract for the commands
# setup-pre-commit/SKILL.md documents for its two security gates (#401).
#
# CLAUDE.md § "Commands a skill documents" rule (b): a skill's fenced block is
# copied out and run unsupervised in someone else's repo, so a checkable claim
# about tool behavior needs a check, not careful reading. The skill claims its
# gates "fail closed": a scanner missing from PATH blocks, an audit that cannot
# reach the registry blocks, and there is no `|| true` or skip-if-absent
# wrapper. Without this suite a later edit that appends `|| true` to either
# `run:` line turns the gate into one that reports green when it could not run,
# and no review pass is guaranteed to notice (#243 is the incident for the
# class: wrong command claims caught only by humans).
#
# Every assertion EXTRACTS the real text from the real SKILL.md and EXECUTES it
# (docs/solutions/testing-patterns/guard-and-subject-must-be-one-artifact-*:
# the guard and the subject must be one artifact, not a restated copy).
# Nothing here needs gitleaks or the network. The gitleaks flags and the Step 7
# fixture are NOT pinned here; they need the gitleaks binary.
#
# Tools that CI's script-test job may lack (lefthook, yq, npm) make only their
# own assertion SKIP loudly; a SKIP line names the tool, it is never a silent pass.

set -euo pipefail

# A caller that reached this suite via a git hook has GIT_DIR and friends set;
# the lefthook fixture's `git init`/`git add` would land on the real repo.
# See docs/solutions/testing-patterns/scratch-git-repos-inherit-the-hook-git-dir-2026-09-17.md.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
skill="$repo_root/setup-pre-commit/SKILL.md"

pass=0
fail=0
skip=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

section() { printf '\n=== %s ===\n' "$1"; }
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
skipped() { printf '  SKIP %s\n' "$1"; skip=$((skip + 1)); }

# --- extraction -------------------------------------------------------------
# The Step 5 "Security gates" yaml block: the first ```yaml fence after the
# "**Security gates" label, up to its closing fence.
extract_gates_block() {
    awk '
        /^\*\*Security gates/ { want = 1; next }
        want && /^```yaml/ { inblock = 1; next }
        inblock && /^```/ { exit }
        inblock { print }
    ' "$skill"
}

# The `run:` value of one named command inside that block.
extract_run() {
    awk -v name="$1" '
        $0 ~ "^    " name ":$" { found = 1; next }
        found && /^ *run: / { sub(/^ *run: /, ""); print; exit }
    '
}

# The Step 2 detection grep line (a fenced bash line starting with grep -rnE).
extract_detect_grep() {
    awk '
        /^```/ { fence = !fence; next }
        fence && /^grep -rnE "gitleaks/ { print; exit }
    ' "$skill"
}

gates="$(extract_gates_block)"
secret_cmd="$(printf '%s\n' "$gates" | extract_run secret-scan)"
audit_tmpl="$(printf '%s\n' "$gates" | extract_run dependency-audit)"
detect_cmd="$(extract_detect_grep)"

section "extraction floors"
if [[ -n "$gates" ]]; then ok "found the Step 5 security-gates yaml block"; else bad "no Step 5 security-gates yaml block"; fi
if [[ -n "$secret_cmd" ]]; then ok "found the secret-scan run line: $secret_cmd"; else bad "no secret-scan run line"; fi
if [[ -n "$audit_tmpl" ]]; then ok "found the dependency-audit run line: $audit_tmpl"; else bad "no dependency-audit run line"; fi
if [[ -n "$detect_cmd" ]]; then ok "found the Step 2 detection grep"; else bad "no Step 2 detection grep"; fi
if [[ -z "$gates" || -z "$secret_cmd" || -z "$audit_tmpl" || -z "$detect_cmd" ]]; then
    printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
    exit 1
fi

# --- claim 1: a scanner missing from PATH fails the gate ---------------------
section "secret-scan fails closed when the binary is missing"
empty_bin="$tmp/empty-bin"
mkdir -p "$empty_bin"
set +e
PATH="$empty_bin" /bin/sh -c "$secret_cmd" >/dev/null 2>&1
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    ok "extracted secret-scan command exits nonzero with no scanner on PATH (exit $rc)"
else
    bad "extracted secret-scan command exited 0 with no scanner on PATH"
fi

if command -v lefthook >/dev/null 2>&1; then
    # The same claim through the tool the skill names. PATH carries lefthook,
    # sh and git but no gitleaks.
    bin="$tmp/bin"
    mkdir -p "$bin" "$tmp/repo"
    for t in lefthook sh git; do ln -s "$(command -v "$t")" "$bin/$t"; done
    printf 'pre-commit:\n  commands:\n    secret-scan:\n      run: %s\n' "$secret_cmd" >"$tmp/repo/lefthook.yml"
    # lefthook skips a command with "no matching staged files" when nothing is
    # staged, which exits 0 for a reason unrelated to the claim; stage a file.
    (cd "$tmp/repo" && git init -q . && echo x >staged.txt && git add staged.txt)
    set +e
    (cd "$tmp/repo" && PATH="$bin" lefthook run pre-commit >/dev/null 2>&1)
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        ok "lefthook run pre-commit fails with the extracted secret-scan and no scanner (exit $rc)"
    else
        bad "lefthook run pre-commit exited 0 with the extracted secret-scan and no scanner"
    fi
else
    skipped "lefthook not installed; the through-lefthook half of the missing-binary claim is not checked (the sh half above ran)"
fi

# --- claim 2: npm audit against an unreachable registry fails ----------------
section "dependency-audit fails closed when the registry is unreachable"
if command -v npm >/dev/null 2>&1; then
    proj="$tmp/proj"
    mkdir -p "$proj"
    cat >"$proj/package.json" <<'J'
{"name":"x","version":"1.0.0","dependencies":{"left-pad":"1.3.0"}}
J
    # A lockfile with one dependency: an empty project can short-circuit, and a
    # missing lockfile fails for the wrong reason (ENOLOCK) and would pass vacuously.
    cat >"$proj/package-lock.json" <<'J'
{"name":"x","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"x","version":"1.0.0","dependencies":{"left-pad":"1.3.0"}},"node_modules/left-pad":{"version":"1.3.0","resolved":"https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz","integrity":"sha512-XI5MPzVNApjAyhQzphX8BkmKsKUxD4LdyK24iZeQGinBN9yTQT3bFlCBy/aVx2HrNcqQGsdot8ghrjyrvMCoEA=="}}}
J
    audit_cmd="${audit_tmpl//\{package_manager\}/npm}"
    set +e
    out="$(cd "$proj" && npm_config_registry=http://127.0.0.1:9 npm_config_cache="$tmp/npm-cache" /bin/sh -c "$audit_cmd" 2>&1)"
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
        ok "extracted dependency-audit command exits nonzero against an unreachable registry (exit $rc)"
    else
        bad "extracted dependency-audit command exited 0 against an unreachable registry"
    fi
    # Non-vacuity: it failed because the audit endpoint was unreachable, not
    # for an unrelated reason such as a missing lockfile.
    if [[ "$out" == *"audit"* && "$out" == *"ECONNREFUSED"* ]]; then
        ok "the failure is the audit request being refused, not an unrelated error"
    else
        bad "the audit failure was not a refused audit request: $out"
    fi
else
    skipped "npm not installed; the unreachable-registry claim is not checked"
fi

# --- claim 3: the Step 2 detection grep matches an audit script --------------
section "Step 2 detection grep finds an audit step in package.json"
# grep exits 2 when any listed path is missing, even on a match, so the exit
# status is not the signal; a hit is output that names package.json.
run_detect() {
    local out
    out="$(cd "$1" || exit 0; eval "$detect_cmd" 2>/dev/null || true)"
    [[ "$out" == *package.json* ]]
}
hit="$tmp/detect-hit"
miss="$tmp/detect-miss"
mkdir -p "$hit" "$miss"
printf '{"scripts":{"audit":"npm audit --audit-level=high"}}\n' >"$hit/package.json"
printf '{"scripts":{"test":"vitest run"}}\n' >"$miss/package.json"
if run_detect "$hit"; then ok "matches a package.json with an audit script"; else bad "did not match a package.json with an audit script"; fi
if run_detect "$miss"; then bad "matched a package.json with no audit script"; else ok "does not match a package.json with no audit script"; fi

# --- claim 4: the Step 5 yaml parses and carries one pre-commit: key ---------
section "Step 5 security-gates block is one mapping with one pre-commit: key"
n_pc="$(printf '%s\n' "$gates" | awk '/^pre-commit:/ { n++ } END { print n + 0 }')"
n_pp="$(printf '%s\n' "$gates" | awk '/^pre-push:/ { n++ } END { print n + 0 }')"
# awk counts physical lines; in a yaml block each top-level key is its own line,
# so line and key coincide here.
if [[ "$n_pc" == 1 ]]; then ok "exactly one pre-commit: key"; else bad "pre-commit: key count is $n_pc, expected 1"; fi
if [[ "$n_pp" == 1 ]]; then ok "exactly one pre-push: key"; else bad "pre-push: key count is $n_pp, expected 1"; fi
if command -v yq >/dev/null 2>&1; then
    # The doc's {package_manager} placeholder is not valid yaml; fill it as Step 5 tells the agent to.
    filled="${gates//\{package_manager\}/npm}"
    if printf '%s\n' "$filled" | yq '.' >/dev/null 2>&1; then
        ok "the block parses as yaml once the placeholder is filled"
    else
        bad "the block does not parse as yaml"
    fi
else
    skipped "yq not installed; the yaml-parse half of the block claim is not checked (the key counts above ran)"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[[ $fail -eq 0 ]]
