---
date: 2026-08-27
category: testing-patterns
problem_type: a contract test written to guard a prose contract asserts what the prose means via substring matching, making the test itself a hand-maintained restatement of the prose's semantics — it drifts from the meaning the same way the original restatement drifted from its canon, and hardening it tightens the strings without touching the gap
components: [scripts, pre-merge, contract-tests]
technologies: [bash, grep, contract-tests, llm-skills]
severity: high
volatility: evergreen
---

# A contract test over prose semantics is itself a restated claim

## The incident

#291 reported that `pre-merge/SKILL.md` hand-restated the review-dimension
roster and the copy drifted from the canon at birth, silently dropping the one
merge-blocking dimension. The fix moved ownership into the canon as structured
`**Runs in:**` markers, taught `SKILL.md` to derive the split from them, and —
per this repo's "Route to the mechanism" doctrine — pinned it with a contract
test.

The test then failed the same way the original restatement had, twice, with a
full review pass between each round:

- **Round 1.** The suite anchored "SKILL.md derives the split" with a
  whole-file `grep -qF '**Runs in:**'`. The string appears at four sites;
  only one is the rule. Deleting the rule and hand-writing the roster back as
  a Markdown table left the suite fully green — the original incident,
  reproducible under a green build. The "Phase 4 runs the relocated dimension"
  check was satisfied by the *only* occurrence of the dimension's name in
  Phase 4: the sentence saying when to **skip** it.
- **Round 2, after hardening.** The fix scoped the searches to phase spans and
  switched the search terms. A fresh reviewer defeated every hardened
  assertion in one pass: prose reading "**Skip** every dimension whose marker
  reads `the controller, in Phase 4`" satisfied the run-check; the
  "roster in any markup" detector was walked past by four markups (a table,
  lowercase, by-number, one-title-per-line); and the census behind the
  "no restatement survives" claim missed its third site in three rounds —
  each census scoped by the directory or file type where the previous
  instance happened to live.

- **Round 3, after this entry existed (PR #297, same day).** The follow-up
  branch corrected the labels to state reach — and stated it by enumerating
  what each matcher *misses*. Every positive half held under probing ("no
  verbatim copy of a gate's first 60 characters" — exact). Every negative
  enumeration was wrong somewhere: "a TWO-threshold copy is NOT reached" was
  false when one threshold was the Observation bound; "that bullet shape
  only" missed that the shape's own regex excluded lowercase labels and
  indented bullets; a miss-list for the by-number detector was incomplete
  the day it was written. Seven defects across two corrective commits, all
  in elaboration *around* mechanisms — a split copied into a second file, a
  justification clause, an over-specified description of a command's output
  — none in a mechanism itself. The converging commit was subtractive: net
  −3 lines, every surviving claim probed red/green before commit.

Each round's corrective hunk violated the rule it enforced. The review that
caught them asked exactly the question
`sweep-commits-reintroduce-their-own-defect-class-2026-08-18.md` prescribes.

## Why the class recurs when the fix is a grep

A prose contract's consumer is a reader — in this repo, an LLM session
executing a `SKILL.md`. Whether "Phase 4 runs the controller-owned
dimensions" is *true* is a fact about how a reader interprets the whole
document. A substring assertion cannot decide that fact; it can only pin the
presence of strings, and prose is unbounded in the ways it can carry a string
while inverting its meaning. So every assertion of the form "the file says X,
therefore the reader will do X" is a second, shadow statement of X — a
restated claim in the exact sense of `docs/restated-claims.md`, with the same
failure mode: it reads as coverage while diverging from the thing it
restates. Hardening the strings narrows individual bypasses and leaves the
gap intact, because the gap is categorical, not calibrational.

#284 had already drawn the boundary this violates: **a contract test
reconciles a writer and a reader across a machine-readable seam.** When both
surfaces are literal (a stamp template and the sed script that parses it, a
marker vocabulary and its schema), the test is exact and drift fails loudly.
When one surface is "what a reader does with this paragraph," there is no
seam to reconcile — there is a lint over prose, wearing a contract test's
filename.

## What held, and what to do instead

The empirical record on this branch is one-sided. Across two full review
passes plus two authoring-time dogfoods:

- **Substring assertions over prose semantics caught zero defects** and were
  themselves defeated four times.
- **Fresh-context readers caught every defect** — the misassigned rationale,
  the skip-inversion, the census misses, the contradiction between a legend
  and a marker — including all defects *in the test*.

So split every guard-shaped idea by what can hold it:

1. **Structured data → contract test.** If the claim can be carried by a
   marker vocabulary, a schema, a template, or a literal round-trip, put the
   claim in that structure and test the structure. Moving the roster's
   ownership into `**Runs in:**` markers is what made the partition testable
   at all. Prefer *changing the artifact to be machine-readable* over
   asserting on the prose around it.
2. **Syntactic surface of a drift class → detector, not proof.** "A literal
   count near the word *dimensions*", "four canon titles in one paragraph" —
   these are decidable patterns. Ship them as detectors with (a) a census
   population of **every tracked file** minus an explicit allowlist, never a
   population scoped by where the known instances lived; (b) planted
   self-tests — a positive that must hit, a near-miss that must stay silent
   (`mechanism-generality-lags-the-pattern` § Prevention: a zero-hit detector
   needs a self-test, not a floor); (c) set-membership pins on the files
   earlier censuses missed, so an allowlist edit fails loudly. Label them
   detectors in the file; do not let their labels claim "no X anywhere."
3. **Semantic property of prose → a reader, on the record.** The only
   competent oracle for "does this document instruct correctly" is executing
   it: hand a fresh-context agent the artifact and its canon, ask it to
   perform the derivation, compare the result. Say in the test file's header
   that this property is held by review, so the suite's green cannot be
   misread as covering it. In this repo that reader already has a home —
   `/pre-merge`'s delegated review — and on this branch it had a 100% catch
   rate.

## The census discipline, because it failed three times in one ticket

Round 1's census searched for the phrasing of the known sites (`11|eleven`)
and missed a "10 dimensions". Round 2's searched the directory of the known
sites (`pre-merge/*.md`) and missed a skill one directory over and a full
roster in a `.js` file. `docs/restated-claims.md` names both tells verbatim —
*every site found shares one wording, or they all live in one kind of file* —
and knowing the tell did not prevent hitting it, twice, because the author
extending their own last grep is structurally the person least able to see
its boundary. When a fix claims to close a class: the census runs over the
whole tracked tree, and a reviewer who did not write the fix checks the
corrective hunk against the rule it enforces.

## Prevention

- Before writing `scripts/test-*.sh` for a prose claim, apply #284's test:
  name the two machine-readable surfaces being reconciled. If one surface is
  "the reader will understand," restructure the artifact (markers, schema,
  template) or assign the property to review — do not write the grep.
- A detector's assertion label states its mechanism's actual reach
  ("no match in N scanned files for pattern P"), never the property it
  approximates ("no restatement survives").
- **State reach positively; never enumerate the negative space.** Round 3's
  refinement of the rule above, learned by following it and still failing: a
  positive reach statement ("no verbatim copy of a gate's first 60
  characters") is closed and checkable against the matcher one line down. A
  miss-enumeration ("a TWO-threshold copy is NOT reached") is an open-ended
  claim about everything the matcher does not do, and it can never be
  complete — on PR #297 every label error, all seven, sat in a negative
  clause while every positive clause held. Say what the matcher is, and stop.
- **Corrective rounds converge by subtraction, not by more careful prose.**
  Each fix round adds sentences that make claims about mechanisms; some
  roughly constant fraction of new falsifiable claims are wrong, so rounds
  that elaborate do not converge. Delete the restated split instead of
  correcting it; cut the justification clause instead of fixing it; and
  probe — break once, watch it go red — every claim that survives the
  subtraction, before the commit rather than after the review.
- Mutation batteries aim at both regions: the assertions *and* the
  set-membership (which files, which spans, which allowlist).
- For changes to a skill's operative prose, the review includes a
  reader-derivation pass: a fresh context executes the changed instructions
  and reports where it guessed.

## Related

- `a-planted-term-cannot-discriminate-meaning-2026-09-04.md` — the second
  recording, eight days later, with the measurement: fourteen independent
  breaker passes, fourteen `survived`, four by restoring the fix's exact
  inverse; a planted-positive self-test fell with the rest. Ships the two
  mechanisms this entry's Prevention could only prescribe.

- PR #297 (round 3, the negative-space refinement) — and its review trail:
  chrislacey89/skills#300 (widen detectors against found misses),
  chrislacey89/skills#301 (procedure/applicability restatements matched by
  nothing — decide the shape before adding a grep).
- Clustering judgment: round 3 is the *same* pattern as this entry, not a
  sibling — hence this update instead of a third file. Mechanism for the
  negative-space refinement: the closest candidate is a wording detector
  over assertion labels, blocked because negative space can be phrased in
  unboundedly many ways — the same open-endedness that makes those claims
  wrong makes them undetectable. Per rule 3 above, the property is held by
  review's reader-derivation pass.

## Shelf life

Evergreen — the boundary is categorical (what substring matching can decide),
not tied to any current file layout. Revisit only if the artifacts themselves
become machine-readable enough (e.g., skills carrying structured front-matter
for their control flow) that claims currently semantic become syntactic.
