---
name: ts-audit
description: Audit TypeScript and React code against expert-level best practices from 9 Total TypeScript library references. Use when the user wants to review, audit, check, or improve TypeScript code quality — including requests like "audit this file", "review my types", "check my TypeScript", "what's wrong with this code", "improve my TS", "type review", or any request to evaluate TypeScript code against modern patterns. Also use when the user mentions type safety, generics review, or React TypeScript patterns. Covers type safety, generics, narrowing, branded types, discriminated unions, React TypeScript patterns, type transformations, testing patterns, and mocking techniques.
---

# TypeScript Audit

Audit TypeScript code against 9 expert-level references covering type safety, generics, advanced patterns, React integration, type transformations, and testing. The goal is to surface concrete improvements the author may not have considered — not to nitpick style, but to catch real type-safety gaps, missed narrowing opportunities, and patterns that would make the code more robust.

## Invocation

The user provides a target: a file path, directory, or glob pattern. Examples:

- `/ts-audit src/db/queries.ts`
- `/ts-audit src/pipeline/`
- `/ts-audit src/**/*.tsx`

## Invocation Position

This is a side-route skill for TypeScript code quality auditing, not a default pipeline step.

Use `/ts-audit` when you want to audit TypeScript or React code against expert-level patterns from the Total TypeScript library references — whether on a single file, a directory, or a glob of changed files.

Do not use it as a substitute for `/pre-merge` architectural review (which checks structural principles) or `/tdd` (which enforces red-green-refactor). It complements both by focusing specifically on type-safety gaps and TypeScript idiom improvements.

For TypeScript projects, `/ts-audit` pairs naturally with `/pre-merge` Phase 3 (Architectural Review) — running it on changed files provides type-safety analysis that complements the seven structural dimensions.

## Step 1: Read the target code

- **Single file**: read it directly
- **Directory**: glob for `**/*.ts` and `**/*.tsx` files within it
- **Glob pattern**: expand the glob

For large targets (>15 files), focus on files with the richest type-level code — interfaces, generics, service layers, component props. Skip auto-generated files (`*.gen.ts`, `*.d.ts`).

## Step 2: Load the relevant library references

Resolve the library path:
```bash
echo "${CLAUDE_LIBRARY_DIR:-$([ -f "$HOME/.claude/library/index.json" ] && echo "$HOME/.claude/library" || echo "NOT_FOUND")}"
```

Select which books to load based on what's in the target. This keeps context lean — only pay for what you need.

**Always load (core):**

| Book | What it covers |
|------|---------------|
| `total-typescript-book` | Core type system — inference, narrowing, unions, `satisfies`, `as const` |
| `ts-essentials` | Essential patterns — annotations, type guards, discriminated unions |
| `ts-generics` | Generic scope, constraints, inference, overloads |
| `ts-type-transforms` | Mapped types, conditional types, template literals, `infer` |
| `advanced-ts-patterns` | Branded types, assertion functions, identity functions, `const T` |

**Load if target contains `.tsx` files or files that import React:**

| Book | What it covers |
|------|---------------|
| `react-ts-patterns` | React props typing, hooks, `ComponentProps`, discriminated union props |

**Load if target contains test files (`*.test.ts`, `*.test.tsx`, `*.spec.ts`):**

| Book | What it covers |
|------|---------------|
| `testing-fundamentals` | Test structure, assertions, async testing |
| `advanced-vitest-patterns` | Fixtures, custom assertions, performance testing |
| `mocking-techniques` | MSW, dependency injection, fake timers, typed mocks |

Read each selected SKILL.md (path: `{LIB}/books/<name>/SKILL.md`) into context. These contain lookup tables, decision matrices, and anti-pattern catalogs that form the audit criteria.

## Step 3: Analyze the code

Work through each file and check against the loaded references. The categories below describe what to look for — the specific rules come from the library references you just loaded.

### Type Safety (total-typescript-book, ts-essentials)

- Widened types where narrower literals exist (e.g., `status: string` when only `"approved" | "denied" | "tabled"` are valid)
- `any` where `unknown` would be safer
- `as` type assertions that bypass narrowing — could the code use a type guard or discriminated union instead?
- Missing return type annotations on exported/public functions
- Loose `string` or `number` where branded types would prevent value confusion
- **Library-callback return wrapper types without `satisfies`.** A local type that wraps a library-provided callback's return (agent hooks, middleware, proxy, tool handlers, render props, lifecycle methods) and gets returned from the callback as a typed variable. TS excess-property check does not run on returns of typed values — fields not declared by the library's signature are silently dropped at runtime. Remedy: end the returned object expression with `satisfies LibraryReturnType`, return a fresh object literal, or derive the local type via `ReturnType<…>` / `Parameters<…>`. Cite: ts-essentials Rule 31, "Use `satisfies` for type validation without losing inference precision."

### Generics (ts-generics)

- Generics declared at too broad a scope (class-level when function-level suffices)
- Missing or overly loose constraints (`T` with no `extends`)
- Redundant generic parameters the compiler could infer
- Cases where function overloads would clarify input-dependent return types

### Discriminated Unions & Narrowing (total-typescript-book, ts-essentials)

- Boolean props/flags where a discriminated union would be clearer and safer
- Destructured discriminated union parameters (breaks narrowing)
- Switch/if chains on union types missing exhaustive checks
- Filtering arrays of unions without type predicates (result stays wide)

### Advanced Patterns (advanced-ts-patterns)

- Assertion functions using arrow syntax (must use `function` declarations)
- Opportunities for `const T` parameter to preserve literal types
- Places where branded types would prevent mixing semantically distinct values (e.g., `userId` vs `orderId`)
- Builder/accumulator patterns that could leverage generic intersection

### Type Transformations (ts-type-transforms)

- Manual type duplication where `typeof`, mapped types, or conditional types would derive from a single source of truth
- `ReturnType<fn>` instead of `ReturnType<typeof fn>`
- Opportunities for template literal types

### React Patterns (react-ts-patterns) — `.tsx` files or files importing React

- HTML wrapper components not using `ComponentProps<"element">`
- Missing generic parameters on `useState`, `useRef`
- Mutually exclusive props modeled as optional booleans instead of discriminated unions
- Event handlers manually typed instead of derived from React types

### Testing Patterns (testing-fundamentals, advanced-vitest-patterns, mocking-techniques) — test files only

- Mocking that could use dependency injection
- Untyped mocks
- Tests not following arrange/act/assert structure
- API mocking that should use MSW

### Step 3b: Go deeper — surface what the library knows that general knowledge doesn't

After catching the obvious issues above, make a second pass specifically looking for opportunities to apply the *non-obvious* patterns from each loaded reference. These are the findings that differentiate this audit from what any TypeScript developer would notice:

**From advanced-ts-patterns:** Look for functions that accept `string` or `number` parameters where the values are semantically distinct (e.g., a `userId` and an `orderId` both typed as `string`). Suggest branded types at the boundaries. Look for assertion functions written as arrow functions — they must use `function` declarations. Check if any generic function would benefit from `const T` to preserve literal types from callers.

**From ts-type-transforms:** Look for manually duplicated type shapes across files (write-side vs read-side types, DTO vs entity). Suggest `Pick`, `Omit`, intersection types, or mapped types to derive from a single source of truth. Check for `ReturnType<fn>` that should be `ReturnType<typeof fn>`.

**From ts-generics:** Look for generics placed at class or module scope that could be narrowed to function scope. Look for functions returning different types based on input where overloads would make the contract clearer. Check for unconstrained `T` parameters that should have `extends` bounds.

**From react-ts-patterns (if loaded):** Look for components wrapping HTML elements that don't use `ComponentProps<"element">` to forward props. Check for mutually exclusive prop combinations modeled as separate optional props instead of a discriminated union. Look for manual event handler types that could be derived from React's event types.

**From testing books (if loaded):** Look for `test.extend()` fixture opportunities where multiple tests share the same setup. Check for typed mock patterns — are mocks losing type information? Look for API calls being mocked inline that should use MSW for more realistic testing. Check if Effect-based code is being tested via `runPromise` + `rejects.toThrow()` instead of `runPromiseExit` which preserves the typed error channel.

The goal of this second pass is to surface at least 1-2 findings per loaded library that go beyond what a developer would catch from general TypeScript knowledge alone. If a library's patterns genuinely don't apply to the target code, that's fine — skip it. But look carefully before deciding nothing applies.

## Step 4: Generate the report

Structure the report as markdown:

```markdown
# TypeScript Audit Report

**Target:** <file or directory>
**Files analyzed:** <count>
**Findings:** <count>

---

## <Category Name>
_Source: <library book name(s)>_

### <Short description of the finding>

**File:** `<path>`:<line>

**Current code:**
\`\`\`ts
// the relevant snippet
\`\`\`

**Suggested change:**
\`\`\`ts
// the improved version
\`\`\`

**Why:** <1-2 sentences explaining what pattern this violates and why the suggestion is better, grounded in the library reference>

---
```

**Grouping:** by category (Type Safety, Generics, etc.), not by file. Within each category, order findings by file path then line number.

**What to include in each finding:**
- The actual code snippet (keep it focused — just the relevant lines)
- A concrete suggested replacement, not just "consider using X"
- A brief explanation referencing the specific concept from the library

**What to omit:**
- Categories with zero findings — leave them out entirely
- Style preferences (semicolons, quotes, formatting)
- Findings that would break the code's runtime behavior without a broader refactor

End with a summary table:

```markdown
## Summary

| Category | Findings |
|----------|----------|
| Type Safety | N |
| Generics | N |
| ... | ... |
| **Total** | **N** |
```

If no findings at all:

> No issues found. The code aligns well with the patterns from the TypeScript library collection.

## Handoff

- **Expected input:** a file path, directory, or glob pattern pointing to TypeScript or React code to audit
- **Produces:** a structured markdown audit report with findings grouped by category, each grounded in specific Total TypeScript library references
- **May feed into:** `/execute` when findings warrant code changes, or `/pre-merge` when the audit informs the architectural review conversation
- **What comes next:** return to the workflow that invoked the audit — the user decides which findings to act on
