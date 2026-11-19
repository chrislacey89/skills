# Readable structure for new code

Six defaults for the code a pipeline run writes. A reader who opens a file
should meet one job and the point of the file before its details. A reader at
a call site should be able to tell what each argument is, which behavior the
call selects, whether it writes, and what has to be called first, without
opening the function.

This file is the canonical statement. `/execute` Step 3 points at it for the
author-time defaults, and `/pre-merge`'s Readable structure review dimension
points at it for the review-time check. Neither restates its thresholds, its
exceptions, or its examples — `docs/restated-claims.md` is the standing account
of why a rule stated at two operative sites drifts.

## Scope

These limits hold for all six defaults.

- **The repo's own conventions win.** A pattern is the team's when it is
  written down or when the established code shows it across the repo. Written
  down means under `Conventions` in the repo profile, in the host repo's
  CLAUDE.md or AGENTS.md, or enforced by its linter or formatter; a lint rule
  such as `no-use-before-define` is one. Either kind overrides a default here,
  and a written one settles the question wherever the two disagree. Martin
  states the order of authority himself: "Every programmer has his own favorite
  formatting rules, but if he works in a team, then the team rules" (*Clean
  Code* ch. 5).
- **New code only.** The defaults cover code the current change adds.
  Reordering, splitting, or converting existing code is its own change, never
  folded into a feature branch. The Surgical Scope review dimension is the
  check on that.
- **One file is not a convention.** New code in an existing file follows that
  file's order only when that order is the repo's: the rest of the established
  code is laid out the same way, or a written convention says so. Then a file
  that puts its helpers first gets its new helper with the others, because the
  same order in every file is what lets a reader know where to look (*The Art
  of Readable Code* ch. 4, on consistent ordering). Where the file is the
  outlier, laid out differently from the rest of the repo with nothing written
  to back it, the new code takes the top-down default below: a new function
  goes above the helpers it calls, and a new helper goes below its caller. The
  existing code in that file stays where it is.

**The examples are in TypeScript.** Each default below shows one **Avoid**
block and one **Prefer** block. TypeScript is the language of the examples and
nothing more: the defaults apply in every language, and the notes under "Where
the language limits the order" and "Languages with named arguments" still
decide how.

## The file

### 1. One job per file

**Default.** When new code adds an unrelated second job to a file, put it in
its own file, named for that job.

**Avoid**, `src/dates.ts` after the change:

```ts
export function formatDate(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}

// Added by this change: an unrelated second job.
export function exportCsv(rows: string[][]): string {
  return rows.map((cells) => cells.join(",")).join("\n");
}
```

**Prefer**, `src/dates.ts` left as it was and a new `src/csv.ts`:

```ts
export function exportCsv(rows: string[][]): string {
  return rows.map((cells) => cells.join(",")).join("\n");
}
```

**Not a violation.** `pad` stays in `dates.ts`. A helper that only the file's
job uses belongs with it.

A reader who has to change the date formatter should not have to read past a
CSV exporter to do it. Martin's test for a class or module is that it "should
have one, and only one, reason to change" (*Clean Code* ch. 10). Boswell and
Foucher give the common case: a generic subproblem sitting inside
project-specific code, where the rule is to "separate the generic code from
the project-specific code" (*The Art of Readable Code* ch. 10).

**What "unrelated" means.** Two jobs are unrelated when each can be understood
and changed without knowing the other, and callers usually want only one of
them. That is Ousterhout's condition for separating (*A Philosophy of Software
Design* ch. 9).

**What stays together.** The same chapter gives the conditions for combining,
and they override the default:

- a helper that only the file's job uses
- pieces that share knowledge: the same format, the same data structure, the
  same design decision
- pieces that are always used together
- pieces a reader cannot understand one at a time

Splitting those leaves two shallow files that each leak into the other, so
this default never asks for a split the Deep Modules dimension would object
to.

**Not a size rule.** A long file with one job passes. A short file with two
unrelated jobs does not. Never split a file because of its line count.

### 2. Highest level on top

**Default.** A new file reads top-down. The exported function or component the
file exists for comes first. The helpers it calls come below it, each caller
above its callees, in the order they are called. Detail goes down.

**Avoid:**

```ts
function greeting(name: string): string {
  return `Hi ${name},`;
}

function joinLink(token: string): string {
  return `https://example.com/join/${token}`;
}

export function buildInviteEmail(invite: Invite): string {
  return [greeting(invite.name), joinLink(invite.token)].join("\n\n");
}
```

**Prefer:**

```ts
export function buildInviteEmail(invite: Invite): string {
  return [greeting(invite.name), joinLink(invite.token)].join("\n\n");
}

function greeting(name: string): string {
  return `Hi ${name},`;
}

function joinLink(token: string): string {
  return `https://example.com/join/${token}`;
}
```

Martin calls this the Stepdown Rule (*Clean Code* ch. 3) and, as layout, the
newspaper order: "We would like a source file to be like a newspaper article"
(ch. 5). The top of the file tells the reader what it does, and they can stop
reading as soon as they have enough detail. "If one function calls another,
they should be vertically close, and the caller should be above the callee, if
at all possible" (ch. 5).

**Constants and types.** Sort them by level, not by kind:

- One the reader needs in order to understand the top function stays with it:
  a default, a limit, a configuration value, the type of its argument or its
  result. *Clean Code* keeps configurable data at the high level and passes it
  down (ch. 17, G35), and ch. 5's own listing leaves the default in the
  high-level function for that reason.
- A detail constant or type goes below, beside the helper that uses it: a
  pattern one helper matches against, a lookup table, the shape of an
  intermediate value.

**Where the language limits the order.** The default applies as far as the
language allows.

- **JavaScript and TypeScript.** Write named functions as `function`
  declarations, which hoist, so the order can follow the reading order
  ([MDN: Hoisting](https://developer.mozilla.org/en-US/docs/Glossary/Hoisting)).
  Keep arrow functions for inline callbacks and values. A `const`, a `let`, or
  a `class` cannot be read before the line that defines it has run
  ([MDN: temporal dead zone](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/let#temporal_dead_zone_tdz)).
  So anything evaluated while the module loads (a top-level call, a constant
  computed from another constant) must sit after what it reads, or it throws.
  A function body may name a `const` defined lower in the file, because the
  body runs after the module has loaded.
- **Languages that need the definition first.** Where a name must be defined
  before the line that uses it runs or compiles, as in shell and C, follow the
  language.

## The call site

### 3. Parameter objects

**Default.** A function the change defines takes one named object in place of
its parameter list when it has:

- three or more parameters, or
- two parameters of the same type that a caller could swap.

One or two clearly different parameters stay positional.

**Avoid:**

```ts
createInvite("ada@example.com", "editor", "team_42", "user_7", 14);
```

**Prefer:**

```ts
createInvite({
  email: "ada@example.com",
  role: "editor",
  teamId: "team_42",
  inviterId: "user_7",
  expiresInDays: 14,
});
```

**Not a violation.** `point(x, y)`, and a callback handed straight to `map`.
Both are among the exceptions below.

A positional call site does not say which argument is which, so the reader
goes to the signature to find out. Martin calls that a double-take: "Anything
that forces you to check the function signature is equivalent to a
double-take" (*Clean Code* ch. 3). The same chapter ranks argument counts:
none is best, then one, then two, and three is to be avoided. Two arguments of
one type are the sharper case, because swapping them is not a type error.
Fowler adds what the object buys beyond the call site: the group of values
gets a name, and behavior that belongs to the group gets a home (*Refactoring*,
2nd ed., ch. 6, Introduce Parameter Object).

**Exceptions.** These stay positional:

- **A callback handed straight to its caller.** A function passed to `map`,
  `filter`, or an event handler takes the arguments that caller sends.
- **A signature the code does not choose.** A framework callback, an interface
  or protocol implementation, an override.
- **Two of the same type in an order every reader already knows.** The parts
  of one ordered value, such as `point(x, y)`, are not swappable in the sense
  above (*Clean Code* ch. 3).

**Languages with named arguments.** A language with named or keyword arguments
uses those in place of a parameter object. The call site already says what
each argument is.

### 4. No flag arguments

**Default.** A function the change defines does not take a boolean, or any
other selector value, whose job is to pick which behavior runs. Write one
named function per behavior.

**Avoid:**

```ts
function loadUsers(includeInactive: boolean): User[] {
  return includeInactive ? db.users.all() : db.users.where({ active: true });
}

loadUsers(true);
```

**Prefer:**

```ts
function loadActiveUsers(): User[] {
  return db.users.where({ active: true });
}

function loadAllUsers(): User[] {
  return db.users.all();
}
```

`loadUsers(true)` does not say what `true` selects, so the reader opens the
function to find out. Default 3 does not catch it, because one clearly
different parameter stays positional. Martin reads the flag as a statement
about the function as well as the call: "Boolean arguments loudly declare that
the function does more than one thing" (*Clean Code* ch. 17, F3; ch. 3 gives
the same rule for flag arguments). The neighboring heuristic widens it from
booleans to any argument that selects behavior, an enum or an integer
included, and gives the same remedy of separate functions (ch. 17, G15).

**Stays as it is.** These exceptions are this document's own line, not the
book's:

- **A boolean that is the data.** `setVisible(true)` stores the value it is
  given. It does not branch on it to choose a behavior.
- **A named option.** `{ includeInactive: true }` inside a parameter object
  already says what it selects. Prefer the split when the two behaviors share
  little code.
- **A signature the code does not choose**, as in default 3.

### 5. A name owns up to its side effects

**Default.** A function the change defines whose name reads as a question or a
lookup (`get`, `find`, `is`, `has`, `check`, `to`) does not write to a
database, a network, a file, or state another caller can read. When it has to
write, either the name says so or the function is split into one that answers
and one that acts.

**Avoid:**

```ts
function getSession(userId: string): Session {
  const existing = sessions.find(userId);
  if (existing) return existing;
  return sessions.insert({ userId, startedAt: new Date() });
}
```

**Prefer**, either form. A name that says so:

```ts
function getOrCreateSession(userId: string): Session {
  return sessions.find(userId) ?? sessions.insert({ userId, startedAt: new Date() });
}
```

Or one function that answers and one that acts:

```ts
function findSession(userId: string): Session | undefined {
  return sessions.find(userId);
}

function createSession(userId: string): Session {
  return sessions.insert({ userId, startedAt: new Date() });
}
```

`getSession` reads as free to call, so a caller who only wants to know whether
a session exists starts one by asking. "Side effects are lies. Your function
promises to do one thing, but it also does other hidden things" (*Clean Code*
ch. 3). The heuristics give the renaming remedy twice: a name should describe
the side effect, as when a `getOos` that creates the stream becomes
`createOrReturnOos` (ch. 17, N7), and a reader should not have to open the
body to learn what a function does (ch. 17, G20). Command Query Separation is
the splitting remedy: a function either changes state or answers a question
(ch. 3).

**Stays as it is.** These exceptions are this document's own line, not the
book's. This default is about names that hide a write, and it is looser than
Command Query Separation as the book states it:

- **A command that returns what it made.** `createSession` returning the
  session is fine.
- **A cache the caller cannot observe.** Memoizing a computed value inside the
  function is not a side effect in this sense.
- **Logging and metrics.**

### 6. Make a required call order visible

**Default.** When the steps a change defines must run in a fixed order, each
step takes the previous step's result as an argument, so the wrong order
cannot be written.

**Avoid:**

```ts
const exporter = new ReportExporter(reportId);
exporter.loadRows();
exporter.applyFilters();
exporter.write();
```

**Prefer:**

```ts
const rows = loadRows(reportId);
const filtered = applyFilters(rows);
writeReport(filtered);
```

The three method calls work in one order only, and nothing at the call site
says so: `exporter.write()` on the first line type-checks and fails when it
runs. Martin calls this a hidden temporal coupling. His remedy is a bucket
brigade, where each step produces the result the next one needs, so the order
is in the arguments (*Clean Code* ch. 17, G31).

**Stays as it is.** An order the framework or the language owns: a component
lifecycle, a test's setup hooks, open and close around a resource.

## Sources

- Robert C. Martin, *Clean Code*: ch. 3 "Functions" (the Stepdown Rule,
  function arguments, flag arguments, side effects, Command Query Separation),
  ch. 5 "Formatting" (the newspaper metaphor, vertical ordering, team rules),
  ch. 10 "Classes" (one reason to change), ch. 17 "Smells and Heuristics" (F3,
  Flag Arguments; G15, Selector Arguments; G20, Function Names Should Say What
  They Do; G31, Hidden Temporal Couplings; G35, Keep Configurable Data at High
  Levels; N7, Names Should Describe Side-Effects).
- Martin Fowler, *Refactoring* (2nd ed.): ch. 6 "A First Set of Refactorings"
  (Introduce Parameter Object).
- John Ousterhout, *A Philosophy of Software Design*: ch. 9 "Better Together
  Or Better Apart?".
- Dustin Boswell and Trevor Foucher, *The Art of Readable Code*: ch. 4
  "Aesthetics" (consistent ordering), ch. 10 "Extracting Unrelated
  Subproblems".
