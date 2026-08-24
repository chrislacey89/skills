# Refactoring

## Discipline

**One structural change per step.** Run tests after each change, not after a batch. If a refactoring step breaks a test, you know exactly which change caused it.

**Never change structure and behavior in the same step.** Structural changes (extract method, rename, move) keep all tests passing — they reorganize code without altering what it does. Behavior changes enter only through the red-green cycle. Mixing the two makes it impossible to tell whether a test failure is from the restructuring or the new behavior.

**Change the type first, then let the compiler enumerate the call sites.** When a requirement changes what a value is *allowed to be*, edit the type before the implementation — deliberately breaking the build. The errors are the worklist: every construction site, every call site, every match that has to account for the change fails until it does. Editing the implementation first and leaving the type alone is how a widened contract ships with nothing flagging it, because the only record of the old precondition was a parameter name.

> "These compiler errors are your friends! They will guide you in what you need to do to fix the implementation."
> — Wlaschin, *Domain Modeling Made Functional*, Ch. 13

**Precondition — this only works with total functions over closed types.** The compiler can only flag a site that is *obliged* to handle the new case. A discriminated union consumed by an exhaustive `switch` with a `never` default gives you the worklist. A widened `string`, an `any`, an added optional field, or a `switch` with a permissive `default` gives you nothing, and the change ships silently. If the type is not closed, closing it is the first step — see [interface-design.md](interface-design.md) § *Make an illegal input unconstructable, not merely detectable*. Without this precondition stated, the rule gets applied where it does nothing and is then read as superstition.

**A broken build is not a red bar.** The rule above deliberately breaks compilation, which looks like it contradicts *never refactor while RED*. It does not: a red bar is a failing test, meaning behavior is missing; a broken build here is an in-progress mechanical migration with no behavior change in it. Finish the migration in one step and the tests go green unchanged. If getting the build green turns out to *require* new behavior, that is the case the next rule covers — stop and write a test.

**When refactoring reveals missing behavior, stop and write a test.** If you notice an edge case, a missing validation, or an implicit assumption while refactoring — do not fix it inline. Return to the Red phase. Write a failing test for the missing behavior. Get green. Then resume refactoring. New behavior enters only through the ratchet.

## Candidates

After TDD cycle, look for:

- **Duplication** → Extract function/class
- **Long methods** → Break into private helpers (keep tests on public interface)
- **Shallow modules** → Combine or deepen
- **Feature envy** → Move logic to where data lives
- **Primitive obsession** → Introduce value objects — and when the primitive carries a precondition a downstream function depends on, make it unconstructable rather than merely validated ([interface-design.md](interface-design.md) § *Make an illegal input unconstructable, not merely detectable*)
- **Existing code** the new code reveals as problematic
