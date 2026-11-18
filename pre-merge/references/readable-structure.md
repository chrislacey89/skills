# Readable structure for new code

Three defaults for laying out the code a pipeline run writes. A reader who opens
a file should meet one job, the point of the file before its details, and call
sites that say what each argument is.

This file is the canonical statement. `/execute` Step 3 points at it for the
author-time defaults, and `/pre-merge`'s Readable structure review dimension
points at it for the review-time check. Neither restates its thresholds or its
exceptions — `docs/restated-claims.md` is the standing account of why a rule
stated at two operative sites drifts.

## Scope

These limits hold for all three defaults.

- **The repo's own conventions win.** Anything under `Conventions` in the repo
  profile, anything in the host repo's CLAUDE.md or AGENTS.md, and anything its
  linter or formatter enforces overrides a default here. A lint rule such as
  `no-use-before-define` is one of those conventions. Martin states the order
  of authority himself: "Every programmer has his own favorite formatting
  rules, but if he works in a team, then the team rules" (*Clean Code* ch. 5).
- **New code only.** The defaults cover code the current change adds.
  Reordering, splitting, or converting existing code is its own change, never
  folded into a feature branch. The Surgical Scope review dimension is the
  check on that.
- **New code in an existing file follows that file's order.** The top-down
  default below applies to files the change creates. A file that already puts
  its helpers first gets its new helper with the others, because a file that
  orders half its functions one way and half the other is harder to read than
  either order (*The Art of Readable Code* ch. 4, on consistent ordering).

## 1. One job per file

**Default.** When new code adds an unrelated second job to a file, put it in
its own file, named for that job.

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

## 2. Highest level on top

**Default.** A new file reads top-down. The exported function or component the
file exists for comes first. The helpers it calls come below it, each caller
above its callees, in the order they are called. Detail goes down.

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

## 3. Parameter objects

**Default.** A function the change defines takes one named object in place of
its parameter list when it has:

- three or more parameters, or
- two parameters of the same type that a caller could swap.

`createInvite(email, role, teamId, inviterId, expiresInDays)` becomes
`createInvite({ email, role, teamId, inviterId, expiresInDays })`. One or two
clearly different parameters stay positional.

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

## Sources

- Robert C. Martin, *Clean Code*: ch. 3 "Functions" (the Stepdown Rule,
  function arguments), ch. 5 "Formatting" (the newspaper metaphor, vertical
  ordering, team rules), ch. 10 "Classes" (one reason to change), ch. 17
  "Smells and Heuristics" (G35, Keep Configurable Data at High Levels).
- Martin Fowler, *Refactoring* (2nd ed.): ch. 6 "A First Set of Refactorings"
  (Introduce Parameter Object).
- John Ousterhout, *A Philosophy of Software Design*: ch. 9 "Better Together
  Or Better Apart?".
- Dustin Boswell and Trevor Foucher, *The Art of Readable Code*: ch. 4
  "Aesthetics" (consistent ordering), ch. 10 "Extracting Unrelated
  Subproblems".
