# TypeScript conventions

Conventions for TypeScript code in this project. For workflow
(branching, PRs, refactors) see METHODOLOGIES.md.

These are constraints, not suggestions. "Liberties constrain,
constraints liberate" — the tighter the rules, the less time is spent
re-deciding the same questions and the more consistent the codebase
becomes. When a rule below conflicts with a quick-and-natural way of
writing something, the rule wins.

The overall posture: the type system is the design surface, and
functional style is the default — values in, values out, immutability
by default, effects at the edges.

## Type discipline

Code in this project is TypeScript that happens to run, not JavaScript
that happens to type-check. The two end up shaped very differently.

### Types come first, implementation follows.

When writing a new function or module, the type signatures are written
first — inputs, outputs, intermediate shapes — and the implementation
is constrained to fit them. The signatures are the design; if they are
awkward or imprecise, the implementation will be too.

A signature like `(input: string, opts?: any) => any` is a non-design
and is not acceptable. A signature like
`(msg: DraftMessage, ctx: RenderContext) => Result<RenderedBlock[], RenderError>`
is a design the implementation must live up to.

### Illegal states are unrepresentable.

If two fields can never be set at the same time, the type does not
allow them to be set at the same time. If a value goes through phases
(draft → sent → acked; loading → loaded → failed), each phase is its
own type. If a function only makes sense after some validation has
happened, it takes the validated type, not the raw one.

The test: by reading the type alone, can you tell what state the value
is in? If no, the type is doing less than it must.

Discriminated unions are the primary tool. This shape:

```typescript
type MessageState =
  | { phase: 'draft'; body: string }
  | { phase: 'sent'; body: string; sentAt: Timestamp }
  | { phase: 'acked'; body: string; sentAt: Timestamp; ackedBy: UserId };
```

is correct. A single interface with optional `sentAt?`, `ackedBy?`,
and a `phase: string` is not — that form is documentation in field
names and prayer at runtime. A state object that is mostly optional
fields is a discriminated union that hasn't been admitted yet.

### Every variant union has exhaustive dispatch.

For any `switch` or pattern match on a discriminated union, the
default arm asserts exhaustiveness:

```typescript
default: {
  const _exhaustive: never = value;
  throw new Error(`unhandled variant: ${(value as { phase?: string }).phase}`);
}
```

The `never` assignment is the compile-time guarantee — when a new
variant is added upstream, the compiler points at every site that
needs updating. The runtime throw is the second line of defense for
cases where types lie (wire data, third-party input).

Silently falling through on unknown variants produces wrong output
that looks right. This rule has no exceptions. Plain `switch` on a
discriminant is the default; reach for a pattern-matching library only
when the pattern is genuinely complex and the `switch` form is
becoming unreadable.

### Identifier-shaped strings are branded.

If two values are both `string` but mean different things — a user id
and an order id, a display name and a canonical key — the compiler
cannot help when they get swapped. They are branded:

```typescript
export type UserId = string & { readonly __brand: 'UserId' };
export type OrderId = string & { readonly __brand: 'OrderId' };
```

New identifier domains get new brands. The cost is one smart
constructor where the value is born; the benefit is the compiler
refuses to let `(user, order)` be called with arguments swapped.

### Wide types are not allowed.

`string` is almost never the right type. If the value is one of a
known set of strings, it is a string literal union. If it is a name in
a domain, it is a brand. If it is unvalidated input, it is `unknown`
(see below) until validation refines it.

Same for `number`. Every `string` or `number` in a signature is
examined to see if something more specific is meant. It usually is.

### `any` is never the right answer.

`any` is a hole in the type system. There is no situation in this
codebase where `any` is correct. Any introduction of `any` is treated
as a bug to be fixed, not a tradeoff to be accepted.

### Casts are reserved for two narrow purposes.

`as` casts are almost as dangerous as `any`. They are permitted in
exactly two places:

- **Brand constructors.** `s as UserId` inside the smart constructor
  `mkUserId(s: string): UserId`. The cast is the *point* of the
  constructor; everything outside it sees the branded type.
- **Boundary crossings** — wire decode, storage reads, FFI/WASM
  returns — where values cross from `unknown` after their shape has
  been validated at runtime.

Everywhere else, an `as` is a signal that the types are wrong and need
to be fixed, not bypassed. `as unknown as Foo` overrides two layers of
type protection at once and belongs only at boundaries with a runtime
validation immediately before it.

### `unknown` is the boundary type. `any` is not.

When data crosses from outside the type system (`JSON.parse`, wire
frames, WASM/FFI returns, storage), it is `unknown`. `unknown` forces
the caller to narrow before use, which is the whole point.

Narrowing is where validation lives — parse, don't validate. A
function `decodeEnvelope(input: unknown): Result<Envelope, DecodeError>`
is the boundary's contract. Everything downstream of the boundary sees
the typed value and never re-checks it.

### Protocols are encoded in types.

When code goes through a sequence of operations that must happen in a
specific order, the sequence is encoded in the types — distinct
context/state types per step, not one mutable context and trust in the
call order. A compiler-enforced protocol is the only kind that
survives long-term.

### Mutability is opt-in, not the default.

Function parameters are `readonly` unless the function is explicitly a
builder. Array types are `readonly T[]` unless mutation is intentional
and local. Object types have `readonly` fields unless the field is
meant to change. `as const` is applied to literal data that should not
change after construction.

`readonly` is information the compiler can use: a `readonly` parameter
says "this function does not mutate its input"; the compiler enforces
it; callers rely on it. Explicitly mutable accumulators (a builder, a
render buffer) are allowed when they are local and named as such.

### Type relationships are expressed in the type system.

When two types are related (input/output shapes, key set and value
lookup), the relationship is expressed with generics, mapped types, or
conditional types rather than written out twice and hoped to stay in
sync. Drift is impossible when types are derived, not duplicated.

The bar for genuine complexity (recursive conditional types, deeply
nested mapped types) is high — the simple forms (generics, basic
mapped types, one-level conditionals) are the default.

### `Partial<T>` is not a substitute for designing the input.

`Partial<T>` is occasionally right — config objects with defaults,
builder intermediate states. It is frequently a shortcut for "I did
not want to think about which fields are actually optional." If a
function needs some fields and not others, its parameter type is
exactly those fields — `Pick<T, 'a' | 'b'>` or a fresh interface, not
`Partial<EverythingTheCallerHas>`.

## Error handling

### Errors are values returned, not exceptions thrown.

For anything that can fail recoverably, the function returns a result
type:

```typescript
type Result<A, E> = { ok: true; value: A } | { ok: false; error: E };
```

Thrown exceptions are reserved for **defects** — invariants believed
unviolable (e.g. the `_exhaustive: never` case above). A `throw` is a
statement that this situation is a bug, not a runtime condition the
caller should handle.

### Boundaries validate; the interior trusts.

Anything coming over the wire, out of storage, or across a WASM/FFI
boundary is validated (manually or with a schema library) before the
value flows into the rest of the codebase. After the boundary, the
types are trusted — no defensive re-checking downstream.

## Functions

### Pure functions returning new values.

Transformation and render-prep passes are functions: input in, output
out, no mutation of shared state. Local mutation inside a function (a
counter, an array being populated before return) is fine — locality is
the qualifier. A function that takes a context object and mutates
fields on it is refactored to return a new value instead. Shared state
mutation belongs only in explicitly-designated stores/accumulators,
of which there are few and all are named as such.

### Function length is not the metric.

A 60-line `switch` with one arm per variant is not a "long function" —
it is a flat function that handles all the cases in one place.
Splitting it into eleven two-line helpers obscures the exhaustiveness
check and forces the reader to chase indirection. Flat dispatch stays
flat. What is split out: distinct *operations*, each its own named
function because each is its own concern.

### Ternaries fit on one line, or they don't exist.

A ternary is allowed only when the entire `cond ? a : b` expression
fits on one physical line (including any leading `const X =`). The
moment it wraps — nesting, large operands, multi-line calls — refactor
to `let` + procedural `if`. The value of a ternary depends entirely on
fitting in a glance; once it wraps, `if/else` reads strictly better.
The rule is symmetric for nullish-coalescing and logical-OR chains
that wrap. If `const` matters structurally, extract a helper function
and `return` from each branch.

## Comments

Comments explain **why**, not **what** — the code and the identifier
names already say what. A comment earns its place by anchoring to an
invariant, a precondition, or a non-obvious constraint the reader
can't recover from the diff.

**An inline comment is a smell.** When a block of code needs a comment
to explain what it does, extract it into a function whose name states
the intent — the name is the documentation. If the code's purpose is
already obvious, delete the comment. Order of preference: **rename,
extract, delete, comment** — comment last, kept to one or two lines,
and only for a *why* the code genuinely can't express.

**The deletion test — apply it to every comment, existing or new.**
Would deleting this comment lose something a competent reader cannot
recover from the code, the identifier names, the nearby docs, and the
tests? If no, delete it. Do not rationalize narration as a "why" —
most comments that survive a lazy first pass are a WHAT wearing a WHY
costume.

A comment is noise — delete it — when a test already guards the
behavior, when the fact is stated elsewhere, when it narrates control
flow, or when it labels a section (extract the section into a named
function instead). Doc comments sit directly above what they document.
Interface fields: all documented or none, preferring none, with the
one non-obvious invariant folded into the type's top-level doc.

Tests document themselves through `describe`/`it` names and assertion
shape — no preamble comment blocks. Tracker IDs live in commits, PRs,
and project state, never in code comments or test names.

## What this codebase does not do

- **Class hierarchies for domain data.** Data is discriminated
  unions; behavior is functions.
- **`null` as absence.** `T | undefined` for optionality, `Result`
  for failure.
- **Throwing for control flow.** Errors are values.
- **Mutating shared context objects to communicate between passes.**
  Threading explicit values is more verbose and more visible. The
  visibility is the point.
- **Defensive `any` or `as` casts to silence the compiler.** When the
  compiler complains, the types are wrong; they get fixed, not
  bypassed.
