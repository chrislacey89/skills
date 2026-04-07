# Refactoring

## Discipline

**One structural change per step.** Run tests after each change, not after a batch. If a refactoring step breaks a test, you know exactly which change caused it.

**Never change structure and behavior in the same step.** Structural changes (extract method, rename, move) keep all tests passing — they reorganize code without altering what it does. Behavior changes enter only through the red-green cycle. Mixing the two makes it impossible to tell whether a test failure is from the restructuring or the new behavior.

**When refactoring reveals missing behavior, stop and write a test.** If you notice an edge case, a missing validation, or an implicit assumption while refactoring — do not fix it inline. Return to the Red phase. Write a failing test for the missing behavior. Get green. Then resume refactoring. New behavior enters only through the ratchet.

## Candidates

After TDD cycle, look for:

- **Duplication** → Extract function/class
- **Long methods** → Break into private helpers (keep tests on public interface)
- **Shallow modules** → Combine or deepen
- **Feature envy** → Move logic to where data lives
- **Primitive obsession** → Introduce value objects
- **Existing code** the new code reveals as problematic
