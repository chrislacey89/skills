# Restated claims in unchecked prose

A **prose contract** is a claim, standard, or rule stated in text that no
compiler, type checker, or schema relates to its other statements — an LLM
prompt, a policy string, an error-message contract, a `SKILL.md` body. When
such a claim is stated at more than one **operative site** — a place a reader
or a caller acts on, as opposed to a place that merely mentions it — changing
the claim has a failure mode with no equivalent in code.

This file is the canonical statement. `/tdd` § 4 Refactor points at it for the
author-time move; `/pre-merge` Dimension 1 points at it for the review-time
detector; `/execute` Step 4 points at it for the scope check on set-claims.
None of them restates it.

## Why an additive edit is not a replacement

Replacing a rule in code deletes the old rule, and every dependent breaks
loudly. Replacing a rule in prose does not delete anything. The new sentence
and the sentence it supersedes are both present, both read as true, and both
satisfy any substring search written to check the work.

**A prose contract has no negative space.** There is nothing that fails when
the old statement survives. A guard test written against the new wording passes
while the old wording is still the one some readers reach.

## The census comes before the remedy

Finding the sites is the hard half, and it is the half that fails. Grep finds
the shape you already understand: a search scoped by the phrasing that surfaced
the known sites cannot surface a site worded differently, and cannot leave the
file class you started in.

**Enumerate by what the claim does, not by how it reads.** Walk the whole
artifact — not the hunks the diff touched — and list every place it makes a
reader or a model act on the claim. For a judging prompt that is each verdict
definition, each scored criterion, and each field the caller branches on. For
an error-message contract it is each message a caller string-matches. For a
skill it is each instruction whose behavior changes with the claim.

The tell that a census stopped early: every site found shares one wording, or
they all live in one kind of file.

## The remedy, and its limit

Extract the claim to a single interpolated constant and reference it at each
site. Six sites become one. The check is then exact and needs no judgment.

**Assert the literal appears once.** Be precise about what that buys: it pins
that nobody re-inlined the constant. It cannot see a restatement in fresh
words, because a restatement is a different literal. The census, not the
assertion, is what has to be complete.

**Where interpolation is unavailable** — text that must ship inline across
independently-installed copies — consolidation does not apply. Two fallbacks,
in order:

1. **Generate or sync the copies from one source**, so a partial edit cannot
   land. In this repo that is `scripts/skill-references.manifest` plus
   `scripts/sync-skill-references.sh`, enforced by the `check-skill-references`
   CI job. This file reaches `/tdd` and `/pre-merge` that way.
2. **Reference the canonical statement by name or section** rather than restate
   part of it. Reference by partial enumeration is the dangerous middle — it
   reads as a pointer and behaves as a copy. The phrase and the finding are
   `docs/solutions/architecture-decisions/by-construction-claims-need-a-mechanism-2026-08-11.md`'s.

## Why a written warning does not close this

Three prose statements of this rule already existed in the repo where the
triggering incident happened, and were read during the task. The defect shipped
twice anyway, the second time in the commit written to fix the first.

Kuhn's survey records the same result outside software. Caterpillar Fundamental
English restricted under 1,000 words across more than 20,000 publications, taught
through a 30-lesson course. It was discontinued in 1982 because its guidelines
"were not enforceable in the English documents produced" (p. 15) — the rules
were sound, but they were prose rather than a checkable grammar, so nobody
could verify compliance at scale. Its successor moved enforcement into an
authoring tool and grew the same controlled vocabulary by nearly two orders of
magnitude.

The lesson is not that the rules were badly written. It is that a rule a writer
must remember and self-apply erodes at scale, and only a mechanism changes that.

## Sources

- Ousterhout, *A Philosophy of Software Design* — information leakage, "a design
  decision reflected in multiple modules."
- Kuhn, *A Survey and Classification of Controlled Natural Languages* (2014),
  p. 15, p. 29 — enforceability as the discriminator between an abandoned
  controlled language and a scaled one.
