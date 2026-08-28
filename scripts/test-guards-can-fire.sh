#!/usr/bin/env bash
# test-guards-can-fire.sh — a guard whose condition cannot become true is worse
# than no guard, because it reports coverage while providing none.
#
# THE DRIFT CLASS. These suites are dense with guards: floors, non-vacuity
# checks, FATALs that stop a run before it reports on text it never read. Each
# one carries a message asserting what it protects. Nothing checks that the
# guard can actually fire, and a guard that cannot is invisible in exactly the
# way the defect it guards against is invisible — the suite prints its normal
# green, the message never appears, and the absence of an alarm reads as the
# absence of a problem. docs/solutions/testing-patterns/
# validate-the-instrument-not-only-the-subject-2026-08-23.md is the family.
#
# THE INCIDENT (PR #296, 2026-08-27). A change hardening three extractors that
# read a physical line where they meant a paragraph shipped four instances of
# its own defect class, all found by review and none by any check. Two were dead
# guards:
#
#   1. `( cd "$scratch"; …; git commit … ) || fatal "could not build the repo"`.
#      `set -e` is suppressed inside the left operand of `||`, so the subshell
#      ran past a failed commit and exited 0. Reproduced under a global
#      core.hooksPath whose pre-commit rejects: the commit failed, the guard
#      stayed silent, and the suite passed only because `git diff` fell back to
#      index-vs-worktree and happened to give the same answer.
#
#   2. A non-vacuity check comparing a value against itself after both sides had
#      been through the same prefix strip, so the condition was unreachable.
#      Deleting the operation it guarded left the suite at 13 passed, 0 failed.
#      Its comment said "Verified: removing the split turns this into a FATAL."
#      It had not been run.
#
# Shape 2 is not decidable by grep in general — it needs the two operands'
# provenance — so this suite does not attempt it. Shape 1 is decidable, and so
# is a third shape from the same PR: an awk paragraph reader that matches its
# anchor against the still-wrapped record. Both are pinned below.
#
# WHY A NEW SUITE RATHER THAN A ROW IN AN EXISTING ONE.
# scripts/test-duplicate-guard-programs.sh is the nearest neighbor and keys on a
# reader appearing twice in one suite; both shapes here appear exactly once, so
# it is silent on them. That is the recurrence docs/solutions/testing-patterns/
# mechanism-generality-lags-the-pattern-2026-08-23.md names — a mechanism
# inherits the syntax of the instance that produced it — which is also why the
# self-tests below plant fixtures instead of trusting a floor: its Prevention #2
# says a detector whose healthy state is zero hits needs a self-test, not a
# floor.
#
# WHAT THIS DOES NOT CATCH, stated so nobody over-trusts it. Only two syntactic
# shapes. A guard can be dead for reasons no grep can see — a comparison whose
# operands are always equal, a condition on a variable that is always empty, a
# `case` arm no value reaches. This narrows the class; it does not close it.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

self="scripts/test-guards-can-fire.sh"

pass=0
fail=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; if [ -n "${2:-}" ]; then printf '       %s\n' "$2"; fi; fail=$((fail + 1)); }
fatal() { printf 'FATAL: %s\n' "$1" >&2; exit 2; }

# Drop whole-line comments before scanning. This suite must NAME the shapes it
# forbids in its own header, and test-compound-clustering-single-source.sh
# records what happens when a suite that quotes what it forbids does not exclude
# its own quoting (its incident 3). A comment in ANY suite may legitimately
# discuss the defect — the fix in test-compound-clustering-single-source.sh does
# exactly that — so the exclusion is by comment, not by filename.
strip_comments() { sed 's/^[[:space:]]*#.*$//'; }

# ---------------------------------------------------------------------------
# Detector A — a subshell used as the left operand of `||`.
#
# `set -e` does not apply inside the left operand of `||`, so `( … ) || fatal`
# cannot report a failure that happens inside the subshell: the subshell keeps
# running and exits with the status of its LAST command. Any guard written this
# way is inert with respect to everything but its final line.
detect_subshell_guard() {  # stdin: file text. stdout: offending lines.
    strip_comments | grep -nE '^[[:space:]]*\)[[:space:]]*\|\|' || true
}

# ---------------------------------------------------------------------------
# Detector B — awk paragraph mode matching the anchor against the wrapped record.
#
# With RS="" the record is a whole markdown paragraph, newlines and all. A reader
# that unwraps (gsub(/\n/," ")) but tests `index($0, …)` is still matching
# line-wise at the anchor, so a wrap landing inside the anchor makes the match
# miss — producing a FATAL that names a rewording which never happened. Build the
# unwrapped record first, then match against it.
detect_wrapped_anchor_match() {  # stdin: file text. stdout: offending lines.
    local text; text="$(cat)"
    if printf '%s' "$text" | strip_comments | grep -q 'RS *= *""'; then
        # shellcheck disable=SC2016  # literal awk source being searched for, not a shell expansion
        printf '%s' "$text" | strip_comments | grep -nE 'index\(\$0,' || true
    fi
}

# ---------------------------------------------------------------------------
# Detector C — a `fatal`-calling helper invoked inside a command substitution.
#
# Third shape of the same class, and the one that arrived by the route this
# suite exists to close: it was written INTO the fix for detector A's shape,
# in the same session, by the author who had just diagnosed it (#305).
#
# `fatal` runs `exit`. Inside `$( … )` that exits only the subshell, so the
# FATAL text reaches stderr, the assignment silently yields the empty string,
# and the run continues to a summary line that says everything passed. Observed
# exactly once, verbatim: `stragglers="$(scan_stragglers "$repo_root" | …)"`
# printed its FATAL and still finished "27 passed, 0 failed", exit 0.
#
# It is a distinct shape from detector A, not a rewording of it: A keys on `)`
# followed by `||` at the start of a line, which is absent here — the subshell
# is `$( … )` on an assignment's right-hand side and there is no `||` at all.
# A mechanism written against one instance's syntax stays silent on the next
# (docs/solutions/testing-patterns/mechanism-generality-lags-the-pattern-2026-08-23.md),
# which is why this is a third detector rather than a widened first one.
#
# The rule the fix follows: a helper that can abort the run returns a status and
# sets a variable; the CALLER, in the main shell, calls fatal.
#
# WHAT IT DOES NOT CATCH — and this list is the enforced boundary, not a
# gesture at one. A reader who takes it as complete should be right, so it was
# built by running the detector against each shape rather than by reasoning
# about the regex:
#
#   - transitive aborts. The exiter set holds `fatal` and its DIRECT callers.
#     `a() { fatal …; }; b() { a; }; x="$(b)"` passes — b is one hop too far.
#   - a `)` anywhere between `$(` and the call: `x="$(printf '%s' "$(date)" && scan f)"`.
#     The `[^)]*` cannot cross it.
#   - `fatal` with a single-quoted first argument, or bare `fatal`. reaches()
#     requires `"`, `$`, or a letter after the name.
#   - a helper defined in a sourced file, or reached through a variable
#     (`cmd=scan; x="$($cmd f)"`).
#   - a call split across lines inside the substitution.
#
# Backtick substitution IS caught (see the call-site regex below) — it has the
# same semantics and the same failure, so disclosing it as a gap would have been
# the cheaper and worse choice.
#
# This narrows the shape; it does not close the class. Stated at this length
# because the prose overclaiming what the matcher enforces is the exact defect
# this branch exists to close (docs/solutions/testing-patterns/
# mechanism-generality-lags-the-pattern-2026-08-23.md, Prevention #1: narrow the
# prose to what is enforced, or widen the matcher — both honest, the gap is not).
exiting_helpers() {  # stdin: file text. stdout: names of helpers that can abort the run.
    strip_comments | awk '
        # Keyed on a `fatal` CALL, not on the bare word `exit`. This comment
        # deliberately avoids apostrophes: it sits inside a single-quoted awk
        # program, and one apostrophe here closes the shell string. That is not
        # hypothetical either — it happened while writing this block.
        #
        # The narrowing is measured, not cautious. Nine helpers in this repo
        # embed an awk program, and the awk `exit` statement is both correct and
        # indistinguishable from a shell exit to a line-level regex. The first
        # draft matched `exit` anywhere in a body and flagged all nine —
        # theme_block, section_body, hero_count, paragraph_at and the rest —
        # every one a false positive on an awk statement doing its job. A
        # detector that reddens on correct code gets deleted, so it is worse
        # than no detector.
        #
        # WHAT THAT GIVES UP, stated plainly: a helper that runs a bare shell
        # `exit` without going through fatal() is not caught. That hole is real
        # and accepted, because fatal() is the uniform convention across this
        # suite family for aborting a run, while `exit` is a word two other
        # languages in these same files also use.
        function reaches(s) {
            return (s ~ /(^|[^[:alnum:]_])fatal[[:space:]]*["$a-zA-Z]/)
        }
        /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{/ {
            name = $0; sub(/\(\).*/, "", name); gsub(/[[:space:]]/, "", name)
            indent = $0; sub(/[^[:space:]].*$/, "", indent)
            # fatal() is an exiter by definition, not by calling itself. Without
            # this seed the set came out EMPTY across every suite in the repo,
            # so the call-site scan below never ran on real code while its
            # section still printed a universal ok. It also restores the
            # shortest instance of the class: n="$(fatal "boom")".
            if (name == "fatal") hit[name] = 1
            rest = $0; sub(/^[^{]*\{/, "", rest)
            if (rest ~ /\}/) { if (reaches(rest)) hit[name] = 1; cur = ""; next }
            cur = name; curind = indent; if (reaches(rest)) hit[cur] = 1
            next
        }
        # Close on `}` at the indentation of the definition itself. Closing on
        # the first `}` at any indent ended the body early at a nested brace —
        # an embedded awk program, a { … } group, a heredoc line — so a
        # `fatal` called after such a block was invisible. That miss landed on
        # the very population the narrowing comment above names: the helpers
        # that embed awk. (No apostrophes in this comment — see the note above.)
        cur != "" && $0 ~ ("^" curind "\\}") { cur = ""; next }
        cur != "" && reaches($0) { hit[cur] = 1 }
        END { for (n in hit) print n }
    '
}

detect_exiting_helper_in_substitution() {  # stdin: file text. stdout: offending lines.
    local text; text="$(cat)"
    local body; body="$(printf '%s' "$text" | strip_comments)"

    local exiters; exiters="$(printf '%s' "$text" | exiting_helpers)"
    [ -n "$exiters" ] || { printf ''; return 0; }

    # Any call to one of them textually inside $( … ).
    local n
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        # The prefix group is OPTIONAL. `\$\(` consumes the `(`, so a call sitting
        # immediately after it — `$(scan foo)`, the exact observed shape — has no
        # boundary character left for a mandatory `[^[:alnum:]_]` to match. The
        # first draft required one and silently matched nothing; its own
        # self-test is what caught that.
        # shellcheck disable=SC2016  # a literal regex over shell source, not an expansion
        # Backticks too: `hits=\`scan foo\`` has identical semantics and an
        # identical failure, and was a silent gap when only $( … ) was matched.
        printf '%s' "$body" | grep -nE '(\$\(([^)]*[^[:alnum:]_])?|`([^`]*[^[:alnum:]_])?)'"$n"'([[:space:]]|\||\)|;|`)' || true
    done <<< "$exiters"
# Detector C — a counting pipeline that cannot survive a zero match.
#
# These suites run under `set -o pipefail`, so a `grep` that legitimately finds
# NOTHING returns 1 and aborts the whole script at that line — before the floor
# or assertion on the next line can report the count. The guard names what it
# protects and cannot fire, which is this suite's whole subject, arriving
# through a pipeline instead of through a subshell.
#
# The tell is narrow and unambiguous: a command substitution whose pipeline
# sends `grep` into a counter (`wc -l`, `wc -c`). Counting is the operation
# whose ZERO result is meaningful, so those are exactly the greps that must be
# allowed to match nothing. A bare `grep` elsewhere may legitimately be required
# to match, so it is not flagged.
#
# Three instances shipped in #304's own contract test — the tracked-markdown
# census, the unit count, and the id count — and none was caught by reading.
# All three surfaced only by running the suite against a tree where the thing
# being counted was absent, which is the mutation direction
# docs/solutions/testing-patterns/
# battery-that-only-perturbs-what-is-present-2026-08-28.md is about.
detect_unguarded_count() {  # stdin: file text. stdout: offending lines.
    local text; text="$(cat)"
    if printf '%s' "$text" | strip_comments | grep -q 'set -[a-z]*o pipefail\|set -o pipefail'; then
        printf '%s' "$text" | strip_comments \
            | grep -nE '\$\(.*grep[^|]*\|[[:space:]]*wc ' \
            | grep -v '|| true' || true
    fi
}

# ---------------------------------------------------------------------------
section "the scan covers a real file list"

# Excludes ITSELF. The self-tests below hold both forbidden shapes as fixture
# strings, and a fixture is not a comment, so the comment filter cannot reach
# them. scripts/test-compound-clustering-single-source.sh made the same
# exclusion for the same reason (its incident 3) and named the cost, which
# applies here verbatim: a genuine dead guard pasted into THIS file would not be
# caught by THIS file. That is the accepted price of letting a suite carry
# executable examples of what it forbids — and the self-tests are what make the
# exclusion survivable, since they exercise the detectors directly.
suites="$(git ls-files 'scripts/test-*.sh' | grep -v -x -- "$self")"
suite_count="$(printf '%s\n' "$suites" | grep -c . || true)"
[ "${suite_count:-0}" -ge 10 ] \
    || fatal "found only ${suite_count:-0} contract suite(s) — the glob is wrong, and an empty list passes every assertion below vacuously."
ok "scanning $suite_count contract suites"

# ---------------------------------------------------------------------------
section "no guard is a subshell on the left of \`||\`"

while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(detect_subshell_guard < "$f")"
    if [ -n "$hits" ]; then
        bad "$f guards a subshell with \`|| …\`, which cannot fire" \
            "set -e is suppressed in the left operand of ||; check the RESULT afterward instead: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done <<< "$suites"
[ "$fail" -eq 0 ] && ok "no inert subshell guards"

# ---------------------------------------------------------------------------
section "no counting pipeline dies on a legitimate zero match"
# ---------------------------------------------------------------------------

before_c="$fail"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(detect_unguarded_count < "$f")"
    if [ -n "$hits" ]; then
        bad "$f counts with an unguarded grep under pipefail" \
            "a zero match aborts the run before the floor can report it; wrap as { grep … || true; }: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done <<< "$suites"
[ "$fail" -eq "$before_c" ] && ok "every counting pipeline survives a zero match"

# ---------------------------------------------------------------------------
section "no awk paragraph reader matches its anchor against the wrapped record"

before_fail="$fail"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    hits="$(detect_wrapped_anchor_match < "$f")"
    if [ -n "$hits" ]; then
        bad "$f uses RS=\"\" but matches with index(\$0, …)" \
            "unwrap into a variable first and match that, or a wrap inside the anchor false-reds: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done <<< "$suites"
[ "$fail" -eq "$before_fail" ] && ok "every paragraph reader matches an unwrapped record"

# ---------------------------------------------------------------------------
section "no run-aborting helper is called inside a command substitution"

before_fail_c="$fail"
# Count the helpers the detector actually examined, and SAY the number.
#
# The first version printed a bare "every run-aborting helper can actually abort
# the run" — a universal over a set that was, measured across all 21 suites,
# EMPTY: nothing seeded `fatal` itself, so no file had an exiter and the
# call-site grep never ran on real code even once. The label was a claim about a
# population the mechanism had not reached, which is the class this very suite
# exists to close. Reporting the count makes a future drop from N to 0 visible,
# where today it would print the same green.
scanned_exiters=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    n_ex="$(exiting_helpers < "$f" | grep -c . || true)"
    scanned_exiters=$((scanned_exiters + n_ex))
    hits="$(detect_exiting_helper_in_substitution < "$f")"
    if [ -n "$hits" ]; then
        bad "$f calls a fatal/exit helper inside \`\$( … )\`, where the exit kills only the subshell" \
            "the FATAL prints, the assignment yields empty, and the run reports a pass; return a status and let the caller abort: $(printf '%s' "$hits" | tr '\n' ' ')"
    fi
done <<< "$suites"
[ "$scanned_exiters" -gt 0 ] \
    || fatal "detector C found 0 run-aborting helpers across $suite_count suites, so its call-site scan ran against nothing and its ok below would be a universal over an empty set. Every suite here defines fatal(); finding none means the extractor is broken, not that the repo is clean."
[ "$fail" -eq "$before_fail_c" ] \
    && ok "$scanned_exiters run-aborting helper(s) across $suite_count suites, none called inside \`\$( … )\` or backticks"

# ---------------------------------------------------------------------------
section "the detectors still detect (self-test)"

# A floor would say "we looked at N files." It would not say the regexes still
# match anything, and a detector whose healthy state is zero hits is exactly the
# one that rots silently. Each detector is run against a fixture it MUST flag and
# a corrected fixture it MUST NOT.

bad_subshell='#!/usr/bin/env bash
(
    cd /tmp
    false
) || fatal "cannot fire"'
good_subshell='#!/usr/bin/env bash
(
    cd /tmp
    false
)
[ -f /tmp/marker ] || fatal "this one can fire"'

if [ -n "$(printf '%s' "$bad_subshell" | detect_subshell_guard)" ]; then
    ok "detector A flags a subshell guarded by \`||\`"
else
    fatal "detector A no longer matches the shape it is named for — the regex rotted, and its section above now passes everything."
fi
if [ -z "$(printf '%s' "$good_subshell" | detect_subshell_guard)" ]; then
    ok "detector A leaves a result-checked subshell alone"
else
    fatal "detector A flags the CORRECTED form, so the fix it prescribes does not clear it."
fi

# shellcheck disable=SC2016  # fixtures are literal awk/shell source, not expansions
bad_awk='awk -v anchor="$2" '"'"'
    BEGIN { RS = "" }
    index($0, anchor) { gsub(/\n/, " "); print; exit }
'"'"' "$1"'
# shellcheck disable=SC2016  # fixtures are literal awk/shell source, not expansions
good_awk='awk -v anchor="$2" '"'"'
    BEGIN { RS = "" }
    { rec = $0; gsub(/\n/, " ", rec) }
    index(rec, anchor) { print rec; exit }
'"'"' "$1"'

if [ -n "$(printf '%s' "$bad_awk" | detect_wrapped_anchor_match)" ]; then
    ok "detector B flags a paragraph reader matching \$0"
else
    fatal "detector B no longer matches the shape it is named for."
fi
if [ -z "$(printf '%s' "$good_awk" | detect_wrapped_anchor_match)" ]; then
    ok "detector B leaves the unwrap-then-match form alone"
else
    fatal "detector B flags the CORRECTED form, so the fix it prescribes does not clear it."
fi

# shellcheck disable=SC2016  # literal fixture text
bad_count='set -euo pipefail
n="$(grep -oE "<section" "$f" | wc -l | tr -d " ")"'
# shellcheck disable=SC2016  # literal fixture text
good_count='set -euo pipefail
n="$( { grep -oE "<section" "$f" || true; } | wc -l | tr -d " ")"'
# shellcheck disable=SC2016  # literal fixture text
no_pipefail='set -eu
n="$(grep -oE "<section" "$f" | wc -l)"'

if [ -n "$(printf '%s' "$bad_count" | detect_unguarded_count)" ]; then
    ok "detector C flags an unguarded counting grep under pipefail"
else
    fatal "detector C no longer matches the shape it is named for — its section above now passes everything."
fi
if [ -z "$(printf '%s' "$good_count" | detect_unguarded_count)" ]; then
    ok "detector C leaves the guarded form alone"
else
    fatal "detector C flags the CORRECTED form, so the fix it prescribes does not clear it."
fi
if [ -z "$(printf '%s' "$no_pipefail" | detect_unguarded_count)" ]; then
    ok "detector C stays silent without pipefail, where the shape is harmless"
else
    fatal "detector C fires without pipefail, where a zero match does not abort — it is matching syntax, not the hazard."
fi

# The comment exclusion is load-bearing: this file's own header quotes both
# shapes, and so does the fix in test-compound-clustering-single-source.sh.
# Without it the detectors would flag the prose explaining them.
# shellcheck disable=SC2016  # literal fixture text
commented='# ) || fatal "this is prose about the defect"
#     index($0, anchor) { … }
BEGIN { RS = "" }'
if [ -z "$(printf '%s' "$commented" | detect_subshell_guard)" ] \
   && [ -z "$(printf '%s' "$commented" | detect_wrapped_anchor_match)" ] \
   && [ -z "$(printf '%s' "$commented" | detect_unguarded_count)" ]; then
    ok "all three detectors ignore commented-out prose about the shapes"
else
    fatal "a detector flags a comment — every suite that documents this defect class, including this one, would go red for explaining it."
fi

# Pin the exclusion itself. It is load-bearing (see the scan list above), and an
# exclusion that silently stopped matching would put this file back in the scan
# where its own fixtures would redden it — a false red on a suite that is
# working, which is how a suite gets deleted rather than fixed.
printf '%s\n' "$suites" | grep -qx -- "$self" \
    && fatal "$self is in its own scan list; its fixture strings will flag as real defects."
ok "this suite is excluded from its own scan, and the exclusion still matches"

# ---------------------------------------------------------------------------

# shellcheck disable=SC2016  # fixtures are literal shell source, not expansions
bad_subst='#!/usr/bin/env bash
fatal() { printf "FATAL: %s\\n" "$1" >&2; exit 2; }
scan() { git grep -l -- "$1" || fatal "cannot read the tree"; }
hits="$(scan foo | grep -v skip)"
'
# shellcheck disable=SC2016  # fixtures are literal shell source, not expansions
good_subst='#!/usr/bin/env bash
fatal() { printf "FATAL: %s\\n" "$1" >&2; exit 2; }
scan() { out="$(git grep -l -- "$1")" || return 2; }
scan foo || fatal "cannot read the tree"
hits="$(printf "%s" "$out" | grep -v skip)"
'

if [ -n "$(printf '%s' "$bad_subst" | detect_exiting_helper_in_substitution)" ]; then
    ok "detector C flags a fatal-calling helper invoked inside \$( … )"
else
    fatal "detector C no longer matches the shape it is named for — the regex rotted, and its section above now passes everything."
fi
if [ -z "$(printf '%s' "$good_subst" | detect_exiting_helper_in_substitution)" ]; then
    ok "detector C leaves the status-returning form alone"
else
    fatal "detector C flags the CORRECTED form, so the fix it prescribes does not clear it."
fi

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
