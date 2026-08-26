# Scala conventions

Conventions for Scala code in this project. For workflow (branching,
PRs, refactors) see METHODOLOGIES.md.

These are constraints, not suggestions. "Liberties constrain,
constraints liberate" — the tighter the rules, the less time is spent
re-deciding the same questions and the more consistent the codebase
becomes. When a rule below conflicts with a quick-and-natural way of
writing something, the rule wins.

The overall posture: lean extremely hard into the type system, and
prefer functional style — values in, values out, immutability by
default, effects at the edges. Scala permits both; this codebase
demands both. Scala also permits Java-with-nicer-syntax; that dialect
is not written here.

Examples use Scala 3 syntax. In a Scala 2 project the rules are
identical with the mechanical substitutions: `sealed trait` + `final
case class` for `enum`, a value class or newtype for `opaque type`,
`implicit` for `given`/`using`.

## Type discipline

The type system is the design surface. Code in this project is Scala
that happens to compile because the design was expressed in types
first, not Scala that was beaten into compiling.

### Types come first, implementation follows.

When writing a new function or module, the type signatures are written
first — inputs, outputs, intermediate shapes, error ADTs — and the
implementation is constrained to fit them. The signatures are the
design; if they are awkward or imprecise, the implementation will be
too.

A signature like `def apply(input: String, opts: Map[String, Any]): Any`
is a non-design and is not acceptable. A signature like
`def apply(doc: Document, op: SignedOp): Either[ApplyError, Applied]`
is a design the implementation must live up to.

### Illegal states are unrepresentable.

If two fields can never be set at the same time, the type does not
allow them to be set at the same time. If a value goes through phases
(received → decoded → validated → applied), each phase is its own type.
If a function only makes sense after some validation has happened, it
takes the validated type, not the raw one.

The test: by reading the type alone, can you tell what state the value
is in? If no, the type is doing less than it must.

Algebraic data types — `enum` in Scala 3, `sealed trait` + `final case
class` in Scala 2 — are the primary tool. This shape:

```scala
enum Delivery:
  case Pending(queuedAt: Timestamp)
  case Sent(queuedAt: Timestamp, sentAt: Timestamp)
  case Acked(sentAt: Timestamp, ackedAt: Timestamp, by: WorkerId)
```

is correct. This shape:

```scala
final case class Delivery(
  queuedAt: Option[Timestamp],
  sentAt: Option[Timestamp],
  ackedAt: Option[Timestamp],
  by: Option[WorkerId],
  state: String,
)
```

is not. The first form is checkable: a function that takes
`Delivery.Acked` cannot be handed an un-acked delivery. The second form
is documentation in field names and prayer at runtime. A case class
whose fields are mostly `Option[T]` is an ADT that hasn't been admitted
yet.

### Every `match` on our own ADTs is exhaustive — no `case _` arm.

A wildcard arm on one of our own sealed types silently absorbs every
case added later. The compiler's exhaustiveness check is the single
cheapest correctness tool Scala gives us — with fatal warnings on (see
the tooling floor) a missing case is a compile error — and a `case _`
arm turns it off.

```scala
// Correct — adding a case to Op breaks this at compile time:
op match
  case ins: Op.Insert => applyInsert(doc, ins)
  case del: Op.Delete => applyDelete(doc, del)
  case rt: Op.Retag   => applyRetag(doc, rt)

// Not this — a future Op.Move silently falls into the sink:
op match
  case ins: Op.Insert => applyInsert(doc, ins)
  case _              => Right(Applied.noop)
```

Silently absorbing unknown cases is among the worst classes of bug:
wrong behavior that looks right. This rule has no exceptions for our
own types. For *foreign* types where exhaustiveness cannot be checked
(unsealed hierarchies, Java enums that may grow), a `case _` arm is
unavoidable — keep it, and make it loud (return an error or log),
never a silent no-op.

A related note on shape: a 60-line `match` with one arm per case is
not a "long function" — it is flat dispatch that handles all the cases
in one place, and it stays flat. Splitting it into a dozen two-line
helpers obscures the exhaustiveness check and forces the reader to
chase indirection.

### Identifier-shaped values are opaque types.

If two values are both `String` (or both `Long`) but mean different
things — a user id and an order id, a byte offset and a sequence
number, a display name and a canonical key — the compiler cannot help
when they get swapped. They get opaque types:

```scala
opaque type UserId = String
object UserId:
  def parse(raw: String): Either[IdError, UserId] = ...

opaque type SeqNo = Long
object SeqNo:
  def apply(n: Long): SeqNo = n
  extension (s: SeqNo) def next: SeqNo = s + 1
```

New identifier domains get new opaque types. The cost is one smart
constructor where the value is born; the benefit is the compiler
refuses to let `(user, order)` be called with arguments swapped —
at zero runtime cost.

The constructor is where the format invariant lives — a `parse`
function is the only place the grammar is checked, and a typed value
in hand is proof the check passed. The underlying representation stays
invisible outside the defining scope; construction goes through the
constructor or not at all. (Scala 2: a `final class ... extends
AnyVal` with a private constructor and a smart constructor on the
companion serves the same role.)

Expose operations deliberately: equality comes free; add an `Ordering`
only when ordering is meaningful in the domain (it is for `SeqNo`; it
is not for `UserId`).

### Wide types are not allowed.

`String` is almost never the right type. If the value is one of a
known set, it is an `enum`. If it is a name in a domain, it is an
opaque type. If it is unvalidated input, it stays in a raw/boundary
type until parsing refines it.

Same for numbers. `Long` is rarely the right type — `SeqNo`,
`ByteOffset`, `RetryCount` carry meaning that `Long` does not, and
arithmetic that mixes them is almost always a bug the opaque type
prevents. Every `String`, `Long`, or `Boolean` in a signature is
examined to see if something more specific is meant. It usually is.
(Two `Boolean` parameters in a row is an enum asking to exist.)

`Any`, `AnyRef`, and `Map[String, Any]` passed through core logic are
the same failure at larger scale — they are not types, they are the
absence of a design.

### Parse, don't validate.

Data crossing any boundary — the wire, disk, a plugin, an editor
extension, an AI agent — arrives as bytes or a raw decoded form and is
*parsed into a typed value once*, at the boundary. Downstream code
takes the typed value and never re-checks it.

`def decode(raw: RawFrame): Either[DecodeError, Envelope]` is the
boundary's contract. A function that takes `Envelope` needs no
defensive checks; the type is the proof. Validation that returns
`Boolean` and leaves the data in its raw type is not parsing — it
forces every downstream function to trust a check it cannot see.

### Protocols are encoded in types.

When code goes through a sequence of operations that must happen in a
specific order — handshake before frames, decode before apply, begin
before commit — the sequence is encoded in the types: each step's
method returns the next state's type, and the next step is defined
only on that type.

```scala
final class Handshake private[net] (...):
  def accept(hello: Hello): Either[HandshakeError, Session]

final class Session private[net] (...):
  def send(frame: Frame): Either[SendError, Unit]
```

A caller cannot `send` before `accept` succeeds — there is no
`Session` to call it on. This is harder than one class with a `state`
field and runtime checks, but the compiler then enforces the
protocol — and a compiler-enforced protocol is the only kind that
survives long-term.

### Type relationships are expressed in the type system.

When two types are related (an op and its inverse, a request and its
response, a key set and a value lookup), the relationship is expressed
with generics, type classes with abstract type members, or conversion
instances rather than being written out twice and hoped to stay in
sync:

```scala
trait Command[C]:
  type Response
  type Error
```

The bar for adding genuine complexity here (match types, higher-kinded
towers, macro-generated instances) is high — they earn their place
only when the alternative is bug-prone manual duplication. The simple
forms (plain generics, abstract type members, ordinary given
instances) are the default.

## Functional style

### Pure core, effectful shell.

The core logic — state transitions, validation, encode/decode,
business rules — is pure functions: values in, values out, no IO, no
clocks, no randomness, no global state. Time, entropy, network, and
disk are passed in as values or injected at the edges. This is what
makes the core trivially testable (property tests, replay) and its
behavior deterministic.

IO lives in a thin shell that calls into the pure core. If the project
uses an effect system (cats-effect, ZIO), effects are values and the
shell is where they are built and run — the core's signatures mention
no effect type. If it doesn't, the shell is plain side-effecting code
at the top of the call stack. Either way, `Future`/`IO`/`ZIO` never
leaks into core signatures.

### Immutability is the default. `var` is opt-in, local, and invisible from outside.

Bindings are `val`. Collections are the immutable ones — the
`scala.collection.mutable` package is imported only inside a function
that builds a value and returns an immutable result. Case class fields
are never `var`. Transformation passes take values and *return new
values* (`copy`, not assignment); they do not mutate shared structures
in place. Local mutation inside a function — a counter, a
`mutable.ArrayBuffer` being filled before `.toList` — is fine;
locality is the qualifier.

Shared mutable state (a `var` on an object, a class used as a grab-bag
mutable context) is how ordering bugs get in. When two components need
to coordinate, prefer messages or returned values over shared
mutation; a genuinely shared cache/registry gets an explicit
concurrent structure with a tiny critical section — never "the
context" threaded through the system.

### Expressions over statements.

Scala is expression-oriented; use it. `val x = if cond then a else b`
over declare-then-assign. `match` as an expression over a mutable
accumulator. A function body that is one expression pipeline reads as
its own specification. `return` is never written; the last expression
is the result.

### Combinators over loops; for-comprehensions over flatMap towers.

`map`/`filter`/`foldLeft`/`collect` chains state intent; `while` with
an index states mechanics. Use combinators when the operation is a
per-element transformation; a chain that has grown a five-line lambda
with its own `val`s wants to be a named function.

Chaining three or more monadic steps (`Either`, `Option`, an effect
type) is what for-comprehensions are for — a `for`/`yield` over a
flatMap tower. Collecting the first error from a list of `Either`s is
a fold or a `traverse` (when cats is already on the classpath), never
a `var` accumulator and a `break`.

### Data and functions, not object hierarchies.

Types are data (`case class`, `enum`); behavior is functions and type
classes. Traits are contracts for *capability polymorphism* (a storage
backend, a transport, a plugin surface), not a way to share code — no
inheritance for reuse, no base-class-with-common-fields patterns, no
self-type layer cakes. Prefer plain functions over a trait until there
is a second implementation or a genuine seam (plugins, tests) that
needs one.

Prefer `enum` + exhaustive `match` for *closed* sets we own (op kinds,
protocol frames); prefer a trait or type class for *open* sets others
extend (plugins). Choosing between them is a design decision — make it
explicitly, per type.

`given`/`using` (Scala 2: `implicit`) is reserved for genuine type
class instances and capability evidence. Implicit *conversions* are
banned outright, and an implicit parameter used to quietly thread "the
context" everywhere is the shared-mutable-context smell in new
clothing — dependencies worth having are worth naming in signatures.

## Error handling

### Errors are values returned, not exceptions thrown.

Anything that can fail recoverably returns `Either[E, A]` with a
purpose-built sealed error ADT. Error ADTs are part of the API design
and get the same type-first treatment: a caller should be able to
`match` on the failure and do something different per case, or the
cases are wrong.

Exceptions are reserved for **defects** — invariants believed
unviolable. A `throw` is a statement that this situation is a bug, not
a runtime condition the caller should handle. In practice:

- Core code: no `.get` on `Option` or `Either`, no `.head` on a
  possibly-empty collection, no partial `match` — ever, on values that
  depend on external input. The total forms (`headOption`,
  `getOrElse`, `lift`, exhaustive match) exist; use them.
- `Try` and `catch` appear only at the JVM/Java-interop boundary,
  wrapping an API that throws, and are immediately mapped into a typed
  `Either` — `Try` is not a return type in this codebase's own APIs.
- `.get` in tests is fine; tests are supposed to blow up on broken
  assumptions.
- A stringly-typed error channel (`Either[String, A]`, an ADT case
  `Custom(msg: String)`) is a wide type wearing an error costume — the
  cases are designed, not accreted.

Never use `Either` where the failure is impossible by construction —
that's what the type discipline above is for — and never use a throw
where the failure is real. Both directions of the mistake cost.

### Absence is `Option`, never `null`.

`null` does not appear in this codebase. Optionality is `Option[T]` in
the type, where the compiler makes the absent case unskippable. The
single exception is the Java-interop boundary, where a possibly-null
return is wrapped with `Option(...)` in the same expression that
receives it — `null` never travels.

### Boundaries validate; the interior trusts.

Anything arriving from outside the process — wire frames, persisted
state, plugin messages, editor RPC — is parsed and validated exactly
once at the boundary (see "Parse, don't validate"). After the
boundary, the types are trusted: no defensive re-checking, no
`require`-as-documentation scattered through the interior.

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
and only for a *why* the code genuinely can't express (an invariant, a
protocol quirk, an external-tool bug being worked around).

**The deletion test — apply it to every comment, existing or new.**
Would deleting this comment lose something a competent reader cannot
recover from the code, the identifier names, the nearby docs, and the
tests? If no, delete it. Most comments that survive a lazy first pass
are a WHAT wearing a WHY costume.

A comment is noise — delete it — when a test already guards the
behavior, when the fact is stated elsewhere (package docs, type docs),
when it narrates control flow, or when it labels a section (extract
the section into a named function instead).

Scaladoc discipline: public items that form the API surface get `/** */`
docs stating the contract (inputs, invariants, errors) — that is API
documentation, not commentary, and it is held to the same why-not-what
standard. Case class fields: all or none, preferring none — fold the
one non-obvious field invariant into the type's top-level doc rather
than scattering `@param` lines.

Tests document themselves through their names and assertion shape —
no preamble comment blocks. Tracker IDs live in commits, PRs, and
project state, never in code comments or test names.

## What this codebase does not do

Patterns from broader Scala/JVM practice that are not used here,
listed so nobody reaches for them by default:

- **`.get`/`.head`-driven development.** Every partial call outside
  tests is reviewed as a probable bug.
- **`null`.** `Option` in types; `Option(...)`-wrap at the Java
  boundary.
- **Exceptions for control flow.** Errors are values; `Try` is an
  interop shim, not an API.
- **Stringly-typed APIs.** Raw `String` ids, `Any`/`Map[String, Any]`
  payloads, JSON ASTs passed through core logic. Parse into types at
  the boundary.
- **Case-class-of-`Option`s state machines.** That's an ADT.
- **Wildcard `match` arms on our own sealed types.** Exhaustiveness is
  the point.
- **Inheritance for code reuse.** No base classes with common fields,
  no trait layer cakes, no `override` towers. Composition, ADTs, and
  type classes only.
- **Implicit conversions.** Banned. An API that needs its arguments
  silently rewritten is a wrong API.
- **`asInstanceOf`/`isInstanceOf`.** Pattern matching narrows; a cast
  outside a boundary decoder is the compiler being overridden, not
  helped.
- **Shared mutable context objects.** No `var` fields, no mutable
  "world" passed around, no implicit context grab-bags. Values flow
  through signatures, where they are visible.
- **Premature effect polymorphism.** No tagless-final `F[_]` towers or
  free monads by default — concrete types until a genuine second
  interpreter exists and pays for the abstraction.
- **Macro/operator cleverness.** Symbolic operator DSLs and macros
  need a strong, argued case; a newcomer must be able to read the call
  site.

## Tooling floor

- `scalafmt` with the checked-in `.scalafmt.conf`; formatting is not a
  discussion.
- Warnings are errors. Scala 3: `-Werror` plus `-Wunused:all`,
  `-Wvalue-discard`, `-Wnonunit-statement`. Scala 2: `-Xfatal-warnings`,
  `-Xlint`, `-Wunused`. Exhaustivity warnings becoming errors is what
  makes the no-wildcard-match rule enforceable, and value-discard
  warnings are what catch a dropped `Either` — neither is optional.
- `scalafix` with `DisableSyntax` enforcing the bans above (`null`,
  `var` in non-local position, `asInstanceOf`, `isInstanceOf`,
  `return`, implicit conversions). A per-line suppression without a
  one-line reason is a review flag.
- Public API surfaces of stable modules document their contract in
  Scaladoc; internal modules start with it off, API-surface modules
  start with it on.
