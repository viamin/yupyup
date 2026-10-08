# YupYup Language Sketch

This is a living sketch, not a stable specification.

## Implemented In The Bootstrap

Files use the `.yup` extension.

Function definitions:

```yup
def hello(name)
  "Hello, " + name
end
```

Function calls:

```yup
hello("world")
puts hello("world")
```

Literals:

```yup
123
"text"
true
false
nil
:off
:on
:ok?
```

Atoms are written with a leading colon and an identifier name. They are
symbolic constants primarily used in model state expressions.

Immutable local bindings:

```yup
name = "world"
puts name
```

Rebinding the same name in a scope is a compile error and reports the source
location of the offending line.

Anonymous functions (Ruby-shaped blocks):

```yup
double = { |x| x * 2 }
puts double(4)
```

An anonymous function is written as `{ |params| expr }`: a pipe-delimited
parameter list followed by a single expression. It is an ordinary expression,
so it can be bound to a name and later called, or passed to a function and
called from inside it:

```yup
def invoke(callback, value)
  callback(value)
end

double = { |x| x * 2 }
puts invoke(double, 5)
```

Blocks are not a distinct kind of value from functions: an anonymous function
literal lowers directly to a BEAM `fun` and is called the same way a bound
name would be. There is no separate proc/lambda distinction.

Operators:

```yup
1 + 2
4 - 1
2 * 3
8 / 2
"Hello, " + name
1 == 1
1 != 2
2 < 3
3 <= 3
4 > 3
4 >= 4
true and false
true or false
not ready
```

Operator precedence, from highest to lowest:

1. Unary `not`
2. `*`, `/`
3. `+`, `-` (`+` also concatenates strings)
4. `<`, `<=`, `>`, `>=`
5. `==`, `!=`
6. `and`
7. `or`

`and`, `or`, and `not` use Ruby-like truthiness: only `nil` and `false` are
falsy. All other values are truthy. `==` and `!=` follow BEAM loose equality.

Pattern matching against literals and tagged values:

```yup
result = Ok(42)

match result
when Ok(value)
  puts "ok: " + value
when Error(reason)
  puts "err: " + reason
end
```

Patterns supported in this slice:

- Literal patterns: `when 42`, `when "hello"`, `when true`, `when nil`.
- Binder patterns: `when value` binds the matched subject to `value`.
- Constructor patterns: `when Ok(value)` matches the tagged value `Ok(value)`
  and binds `value` to the inner payload.

Constructors are written with an uppercase tag followed by an argument list:

```yup
answer = Ok(42)
reason = Error("nope")
```

A constructor expression such as `Ok(42)` lowers to the tagged tuple
`{:ok, 42}` and matches the pattern `Ok(value)` against that tuple. The full
tag/arity space is intentionally small until records and richer data
constructors join the language.

`match` lowers to a BEAM `case` expression. The first matching clause runs.
If no clause matches, the program raises a BEAM `case_clause` error, just like
an unmatched Erlang case.

Pattern matching is supported at the top level of a program or function body,
and within a `match` clause body. Patterns and expressions are distinct AST
nodes (`Yup.AST.LiteralPattern`, `Yup.AST.BinderPattern`,
`Yup.AST.ConstructorPattern`, `Yup.AST.Constructor`), so later passes such as
type checking and refinement have a stable surface to consume.

## Records

Records are immutable product types. A record declaration names a type and
lists its fields. Declarations live at the top of a `.yup` file:

```yup
record Person
  name
  age
end
```

A record is constructed with `Type.new(name: value, ...)` using keyword
arguments:

```yup
person = Person.new(name: "Ada", age: 42)
```

Each declared field must be supplied exactly once; supplying an unknown field
or omitting a declared field is a compile error and reports the offending
source location.

Field access uses dot syntax. Reads are immutable; a record value never
changes after construction. A "copy with a change" pattern works by
constructing a new record and reusing fields from the old one:

```yup
def rename(person, new_name)
  Person.new(name: new_name, age: person.age)
end
```

Records lower to BEAM maps at the moment, which keeps them compatible with
ordinary `maps:get/2` semantics while richer structural typing is being
designed. Field access like `person.name` lowers to `maps:get(:name, person)`
and produces a `badkey` error at runtime if the field is absent on a value
that is not a well-formed record.

## Dot Calls And Chaining

For ordinary immutable values, `value.operation(arg)` behaves like
`operation(value, arg)`: the receiver is passed as the first positional
argument to an ordinary YupYup call — a known top-level `def` or a bound
function value.

```yup
def double(value)
  value * 2
end

def add(value, amount)
  value + amount
end

puts 3.double().add(4)
```

Dot calls are postfix operations that bind tighter than unary and binary
operators, and a chain of dot calls and field reads associates left to
right. Field reads and calls can be mixed freely in a chain:

```yup
person.address.format().length()
```

Parentheses distinguish a field read from a call, including for a
zero-argument call: `person.name` reads the `name` field, while
`person.name()` calls `name` with `person` as its receiver. `Type.new(...)`
remains the dedicated record-construction form and is unaffected by dot-call
parsing; a value returned by `Type.new(...)` can itself start a dot-call
chain.

Dot calls are kept visible in the AST: `Yup.AST.Call` carries a `receiver`
field that holds the parsed receiver expression, or `nil` for a plain call
like `double(4)`.

This milestone does not introduce type-scoped methods, mutation, or Ruby's
object model — dot calls resolve to ordinary YupYup calls only. Dot calls
inside model expressions (`state name = expr` and transition bodies) are out
of scope and are rejected with a source-located error, since actor
references may eventually use different dot-call dispatch once actor
semantics are designed; that dispatch remains unresolved.

## Immutable Collections

YupYup has a list literal and a map literal. Both are ordinary immutable
values: operations on them always return a new value, and the BEAM's own
list and map representations already guarantee this without any extra
runtime bookkeeping.

List literals hold an ordered sequence of expressions:

```yup
values = [1, 2, 3]
nested = [1, [2, 3]]
empty = []
```

A list literal lowers directly to a native BEAM list, so YupYup lists are as
BEAM-friendly as it gets.

Map literals hold `name: value` fields, the same keyword-field syntax
`Type.new(name: value)` already uses for record construction, but without a
declared `record` type:

```yup
user = { name: "Ada", active: true }
puts user.name
puts user.active
```

A map literal lowers to a native BEAM map, identically to how a record
construction lowers (see [Records](#records)); field access on a map literal
value uses the same dot syntax and `maps:get/2` lowering that record field
access uses. Supplying the same key twice in one map literal is a compile
error reported at the offending key's source location. An empty map literal
is written `{}`.

Because a block literal is also written with braces, `{ ... }` is
disambiguated by what follows the opening brace: `{ |params| ... }` is a
block (see [Implemented In The Bootstrap](#implemented-in-the-bootstrap)),
`{ name: value, ... }` or `{}` is a map literal, and anything else is a
syntax error naming both possibilities. This resolves the map-literal-versus-
records design question left open when collections were proposed: an
anonymous map literal is the dynamic, untyped counterpart to a declared
`record`, and reuses the same lowering and field-access machinery.

Lists support a small, block-driven operation set: `map` transforms each
element, and `select` keeps only the elements where the block returns a
truthy value. Neither operation is ordinary Ruby Enumerable parity — they are
the minimum needed for small functional programs, and both return a new list
rather than changing the receiver.

```yup
values = [1, 2, 3]
doubled = values.map { |value| value * 2 }
evens = values.select { |value| value / 2 * 2 == value }
```

`collection.operation { |x| ... }` is new postfix syntax: a dot call whose
sole argument is a trailing block written without parentheses, rather than
`collection.operation({ |x| ... })`. Both forms parse to the same `Call`
node with the block as its one argument; the parenthesized form already
worked before this trailing-block form was added, since a block literal was
already an ordinary expression. `map` and `select` are reserved names —
defining a top-level function or binding a local name called `map` or
`select` is a compile error, the same restriction `puts` already has, since
both names dispatch straight to `Yup.Runtime` regardless of whether the call
has a receiver.

`puts` prints a list as `[1, 2, 3]` and a map as `{name: "Ada"}` rather than
treating a list of integers as an Erlang charlist. Strings nested inside a
printed list or map are quoted (`["a", "b"]`) so they are distinguishable
from other element kinds; a top-level `puts "a"` is unaffected and still
prints the bare string. `nil` prints as `nil`, both at the top level and
inside a collection, so `puts [nil]` prints `[nil]` rather than looking like
an empty list. Constructor values print in their source shape, so
`puts Ok(1)` prints `Ok(1)` and `puts [Error("nope")]` prints
`[Error("nope")]`; constructor payloads follow the same nested rules, so
string payloads stay quoted. Function values print in an opaque inspected
form (`#Function<...>`) rather than crashing. Map keys print in sorted order
since BEAM maps do not preserve insertion order.

Calling `map` or `select` on a value that is not a list is a runtime error.
Calling any other collection-shaped operation name (for example `reduce`,
which is not implemented) is not specially recognized, so it falls through
to ordinary call dispatch and fails to compile as an unbound reference,
consistent with calling any other undefined name.

`new_endpoint`, `store_grant`, and `redeem_grant` are reserved internal
runtime operations used only by the OAuth runtime example. They are not a
general persistence API: the endpoint store assigns opaque ids, stores a
grant, and atomically consumes a grant respectively. They remain deliberately
small until YupYup gains a user-facing state or actor model.

List literals do not yet support indexing, pattern matching inside `match`,
or a Set type; a Set is left for a later issue. See [Current
Limitations](#current-limitations) for what else is out of scope.

## Type Annotations

YupYup parses type annotations as first-class syntax so future checkers can
consume the YupYup AST directly. Untyped code remains the default; annotations
are additive.

Function parameter annotations:

```yup
def greet(person: Person)
  "Hello, " + person
end
```

Function return annotations:

```yup
def hello(name) -> String
  "Hello, " + name
end
```

Record field annotations:

```yup
record Person
  name: String
  age: Integer
end
```

An annotation references a type by an uppercase identifier. The bootstrap
parser stores annotations on the AST:

- A function parameter becomes a `Yup.AST.Parameter` whose `type` field holds
  either `nil` (unannotated) or a `Yup.AST.TypeRef{name: ...}` carrying its
  source location.
- A function's optional return type lives on `Yup.AST.Function.return_type`
  and is `nil` when omitted.
- A record field becomes a `Yup.AST.RecordField` with the same optional
  `type: nil | TypeRef` shape.

### Checker Non-Goals In This Slice

The bootstrap deliberately does **not** enforce annotations. A future gradual
structural type checker will own that responsibility. Specifically, the
current slice does not:

- Check that an argument matches its declared parameter type.
- Check that a returned value matches the declared return type.
- Check that a record construction supplies values whose dynamic types match
  the field annotations.
- Infer types from expression bodies.
- Track refined types, generic constraints, or generic instantiations.
- Treat annotation mismatches as runtime errors or warnings.

Untyped and annotated programs compile and run identically today. The
annotations are preserved in the AST so a future checker has the source
intent available without a separate annotation sidecar.

## Current Limitations

The parser is line-oriented and intentionally tiny. Anonymous function bodies are limited to a single expression on the same line as the `{ |params| ... }` literal; there is no `do ... end` block form yet (see Proposed And Unresolved). The parser does not support nested blocks other than `def ... end`, `match ... end`, `record ... end`, model `transition ... end` and `invariant ... end`, string interpolation, comments inside string literals, type-scoped methods, mutable record updates, record patterns inside `match`, guards inside `when`, exhaustive matching warnings, actors (including actor dot-call dispatch), or full type checking.

List and map literals (see [Immutable Collections](#immutable-collections)) are the only collection types today: there is no Set, no indexing into a list, no list or map pattern inside `match`, and no collection operations beyond `map` and `select`.

Type annotations are parsed and preserved on the AST but the bootstrap does
not enforce them. See [Type Annotations](#type-annotations) above and the
checker non-goals listed there for what is intentionally out of scope today.

Formal models describe state machines at an abstraction level distinct from
executable code. Models coexist alongside functions and statements in the
same source file but are not compiled to BEAM — they are preserved in the
explicit AST for future model-checking and verification passes.

```yup
model Light
  state value = :off

  transition toggle do
    state.value = value == :off ? :on : :off
  end
end
```

Model declarations:

- `model Name` opens a named model block. Model names start with an uppercase
  letter.
- `state name = expr` declares a named state field with a deterministic
  initial value. State initializers use model expressions.
- `transition name do … end` defines a named transition. The body describes
  how state changes when the transition fires.
- `invariant "name" do expr end` declares a named invariant checked at every
  explored state (see [Model Invariants](#model-invariants)).

Within a transition body, `state.name` reads the current value of a state
field and `state.name = expr` sets its next value.

Model expressions support a ternary conditional:

```yup
value == :off ? :on : :off
```

Models are intentionally non-executable. They parse into explicit AST nodes
(`Yup.AST.Model`, `Yup.AST.ModelState`, `Yup.AST.Transition`,
`Yup.AST.TernaryOp`, `Yup.AST.StateAccess`, `Yup.AST.StateUpdate`) for
downstream analysis.

Boolean operators are not short-circuiting in the BEAM backend yet. `true or (1 / 0)` evaluates both sides today.

## Model Invariants

Models can declare named invariants. An invariant is a model property checked
by `yup verify` at every state it explores; it is never lowered to BEAM code
and is not a production assertion.

```yup
model Light
  state value = :off

  invariant "value is on or off" do
    value == :on or value == :off
  end

  transition toggle do
    state.value = value == :off ? :on : :off
  end
end
```

Invariant declarations:

- `invariant "name" do expr end` names the property with a non-empty string
  label and a body of exactly one expression line, closed by its own `end`.
  The label is reported verbatim when the invariant fails.
- The condition uses the model expression subset (literals, state field reads
  through bare names or `state.field`, unary/binary operators, and ternaries)
  and is parsed into a `Yup.AST.Invariant` node with the header's source
  location. Calls, dot calls, and other expression shapes are rejected with
  source-located diagnostics, as in state initializers and transition bodies.
- The condition holds at a state when it evaluates truthy under YupYup
  truthiness: only `nil` and `false` fail an invariant.
- Invariant names must be unique within a model; duplicates are rejected with
  a source-located diagnostic before exploration begins.

When an invariant fails at an explored state, `yup verify` exits nonzero and
reports the invariant's name and source location together with a
counterexample: the violating state and the transition trace from the initial
state. Because exploration is breadth-first, the trace is a shortest one.

```text
examples/broken_invariant.yup:4:1: invariant "count stays below 3" failed
  counterexample state {count: 3}
  reached via: increment, increment, increment
```

When a completed search finds no violations, the held invariants are reported
alongside the exploration counts:

```text
model Light: exploration complete: 2 states, 2 transitions explored; 1 invariant held at every explored state
```

These results are bounded by the finite state space `yup verify` explores: a
completed search reports what held at every explored state and never claims
unbounded proof, and a search cut off by `--max-states` reports
incompleteness rather than any invariant outcome. An invariant condition that
fails to evaluate (division by zero, an unknown field) aborts the search as
an evaluation error carrying the state and trace where it happened.

Passing and failing examples ship in `examples/invariants.yup` and
`examples/broken_invariant.yup`. Temporal properties, fairness, refinement,
and SMT-backed proof are out of scope.

## External Cross-Checking With TLA+

Finite models can be exported to a TLA+ module and checked with an external
TLA+/TLC installation, so verification results do not depend solely on
YupYup's own verifier:

```sh
./yup export tla examples/auth_code.yup > AuthCode.tla
```

`yup export tla FILE` writes the module to stdout, so save it under the
model's name with a `.tla` extension (TLC requires the module name and the
file name to match). The generated module declares:

- every state field as a TLA+ `VARIABLES` entry, in declaration order, with
  the initializer values as `Init`;
- one next-state action per transition, disjoined into `Next`, where fields
  the body does not assign stay `UNCHANGED` and a field assigned earlier in
  the same body is read at its next-state (primed) value, matching YupYup's
  sequential update semantics;
- one numbered `Invariant` definition per declared invariant, plus
  `Spec == Init /\ [][Next]_vars`, which allows stuttering so TLC explores
  the same finite state graph as `yup verify` without spurious deadlock
  reports.

The export supports the `yup verify` expression subset minus strings and
`nil`: integer, boolean, and atom literals, state field reads, `+ - * /`,
`== != < <= > >=`, `and`/`or`/`not`, and ternaries. The translation
preserves YupYup semantics:

- atoms become distinct TLA+ strings (`:known` becomes `"known"`);
- `/` truncates toward zero like `Yup.Runtime.divide/2` (Elixir `div/2`), but
  TLA+ `div` floors, so `/` becomes an `IF` expression over `div` and `%`
  that adds one back to the floored quotient whenever the operands' signs
  differ and the division isn't exact — the only case where flooring and
  truncating disagree; `<=` becomes `=<`; `!=` becomes `#`;
- `and`, `or`, `not`, and ternary conditions test YupYup truthiness, so
  operands that are not statically boolean (everything except comparisons,
  boolean operators, and boolean literals) are compared against `FALSE`.

Ordering comparisons (`< <= > >=`) require both operands to be statically
non-atom and non-boolean, since TLC's ordering operators only accept
integers, unlike `yup verify`'s Elixir term ordering; `==`/`!=` have no such
restriction.

Anything else fails with a source-located diagnostic and a nonzero exit:
string and `nil` literals, calls and list/map/record expressions, bare
expression statements (no assignment) in transition bodies, ordering
comparisons over operands that are statically atoms or booleans, assigning
the same field twice in one transition, and names that cannot become TLA+
identifiers (such as `ok?`) or that collide with generated definitions
(`vars`, `Init`, `Next`, `Spec`, and the numbered invariants). The file must
contain exactly one model block, as with `yup verify`.

To check an exported model with TLC, save the module and the companion
configuration the module's trailing comment documents, then run TLC from an
existing TLA+ installation:

```sh
./yup export tla examples/auth_code.yup > AuthCode.tla
cat > AuthCode.cfg <<'EOF'
SPECIFICATION Spec
INVARIANT Invariant1
EOF
java tlc2.TLC AuthCode
```

`examples/auth_code.yup` and `examples/pkce_exchange.yup` both export
cleanly. Temporal properties, refinement checking, and installing or
vendoring TLC are out of scope: TLC comes from your own TLA+ installation.

### Automated Cross-Check

`bin/tlc-crosscheck` automates that manual loop: for each model it runs
the YupYup verifier, exports the TLA+ module and generates the companion
`.cfg` into a working directory, runs TLC there, and compares the two
checkers' pass/fail verdicts. With no arguments it checks the finite
safety examples — including the deliberately broken fixtures, which both
checkers must fail:

```sh
bin/tlc-crosscheck                    # the four example models
bin/tlc-crosscheck my/model.yup       # or your own files
```

TLC is found through the `YUP_TLC` environment variable (word-split, so
it can carry a classpath) or through `java` on `PATH` with
`tla2tools.jar` on `CLASSPATH`:

```sh
export YUP_TLC='java -cp /opt/tla2tools.jar tlc2.TLC'
# or: export CLASSPATH=/opt/tla2tools.jar   # with java on PATH
```

Agreement prints one `agree` line per file (`yup failed (invariant),
tlc exited 1` is agreement — both checkers rejected the model). Any file
where one checker passes and the other fails prints a `DISAGREEMENT`
line with both outcomes and an excerpt of TLC's output, and the script
exits 1; the same goes for files the verifier cannot give a verdict on
(unreadable, unparsable, evaluation failure, or an exploration that hit
its state cap) or that cannot be exported. When no TLC installation is
found the script prints why and exits 0, so CI and local test runs skip
cleanly without a TLA+ install; `mix test` likewise excludes its
TLC-dependent test.

The trust boundary this draws: `yup verify` and `yup export tla` share
the same parser and model semantics, so neither can catch a bug in the
other. TLC replaying the exported module is the independent check — but
both only ever speak about the same finite state graph, never about
unbounded behavior of the real system.

## The OAuth Runtime Example

`examples/oauth_runtime.yup` is the executable counterpart to the verified
finite models: the smallest OAuth-shaped runtime slice that supports
authorization-code + PKCE exchange, written in YupYup and run through the
ordinary `yup run` path.

```sh
./yup run examples/oauth_runtime.yup
```

The slice has one issuer with one registered client and one in-memory grant
slot. Immutable server records reflect the grant, but `Yup.Runtime` owns the
endpoint state and atomically consumes it, so a stale pre-redemption record
cannot replay a code. The authorization endpoint (`issue`) issues a code
only when the client id and redirect URI exactly match the registration; the
token endpoint (`redeem`) hands out a token only when the code is the one
issued, not yet consumed, redeemed at the same redirect URI it was issued
for, and the verifier's derived challenge matches the stored challenge.

The two protocol rules the verified models prove appear here as running
code: the endpoint store's consumed grant plays `redemptions <= 1` from
`examples/auth_code.yup`, and the `derive(verifier) == challenge` check plays
`verifier == :matching` from `examples/pkce_exchange.yup`. The models remain
the checked artifacts; the example makes the rules runnable. Neither proves
the other, but the trace check below relates them event by event — which is
checking, not proof.

This is a **toy subset** of OAuth, not a server. Its non-goals, deliberate
and permanent for this example:

- OpenID Connect ID tokens, refresh tokens, and dynamic client registration.
- Multiple tenants or issuers, or more than one registered client.
- Production cryptographic key management: `derive(verifier)`
  (`"s256:" + verifier`) stands in for `BASE64URL(SHA256(verifier))`
  exactly as the model abstracts the hash, and there are no client secrets.
- HTTP, persistence, expiry, scopes, or randomness — codes and tokens are
  deterministic (`ac-<client_id>`, `at-<code>`), and the single grant slot
  means a second authorization overwrites the first.
- External conformance suite integration; error results are reason
  strings, not OAuth 2.0 error codes.

### Trace Checking The Runtime Against The Models

The test suite connects this runtime back to the verified models with a
trace check: each runtime observation is mapped to model transitions and
the models are stepped through them, so a runtime that permits behavior
the models forbid fails the suite. `Yup.Verify.Trace` is the generic
engine; the OAuth-specific mapping lives in `test/support/oauth_trace.ex`
(`Yup.OAuthTrace`), and `test/oauth_trace_test.exs` drives it.

The event mapping, stated once:

| Runtime event                                | AuthCode           | PkceExchange                  |
| -------------------------------------------- | ------------------ | ----------------------------- |
| issue → Ok                                   | `issue`, issued    | — (stutter)                   |
| issue → Error                                | — (stutter)        | — (stutter)                   |
| redeem, matching verifier, Redeemed          | `redeem`, +1       | `submit_valid_verifier`, token |
| redeem, matching verifier, refused (reuse)   | `redeem` (guard)   | — (stutter)                   |
| redeem, matching verifier, refused (other)   | — (stutter)        | — (stutter)                   |
| redeem, wrong verifier, Redeemed             | `redeem`, +1       | `submit_invalid_verifier`, token |
| redeem, wrong verifier, refused              | — (stutter)        | `submit_invalid_verifier`, no token |
| redeem, unknown code, Redeemed               | `redeem`, +1       | `submit_valid_verifier`, token |
| redeem, unknown code, refused                | — (stutter)        | — (stutter)                   |

Three rules govern it. Mapped **transitions are chosen from the event's
inputs** — which code was submitted, whether the verifier derives to the
stored challenge — never from the outcome, so a runtime that succeeds on
inputs the model rejects still maps to the model's refusal transition
and disagrees by construction. **Claims are chosen from the outcome**: a
minted token claims `token_issued`, a consumed code claims a redemption,
whatever the runtime's internals did. And **refusals may do less than
the model permits**: a refused exchange maps to the model's own refusal
encoding — `submit_invalid_verifier`, or `AuthCode.redeem`'s guard for
a reused code — or stutters; conformance only fails when the runtime
does what the model forbids.

Each mapped event is checked by stepping the models through
`Yup.Verify.Semantics` — the same code `yup verify` uses to apply
transitions — rechecking invariants at every step, then comparing the
claims against the model states the steps actually produced. Any
mismatch, invariant violation, or evaluation error is a *disagreement*
and the session stops at its last conforming event.

`examples/broken_oauth_runtime.yup` is the deliberately bad counterpart:
its token endpoint mints a token from every refused exchange, and the
tests assert the check fails on it three ways — a token on a wrong
verifier contradicts `PkceExchange`, and both a re-minted code and a
token for an unknown code contradict `AuthCode`'s single-use rule.

This is **trace checking, not refinement**: it runs only on the concrete
traces the tests feed it, the gluing relation (the mapping and its
claims) is supplied rather than proved, and it sees only what the models
model — client registration and redirect URIs are invisible to it and
remain covered by the runtime's own tests.

## Proposed And Unresolved

Dot calls on actor references may represent message operations rather than
ordinary receiver-first calls once actor semantics are designed. The syntax
can look the same as an ordinary dot call while dispatch semantics depend on
the receiver; this dispatch is unresolved (see [Dot Calls And
Chaining](#dot-calls-and-chaining) for what is implemented today).

The short `{ |x| x * 2 }` block form is implemented (see above). The
Ruby-style multiline `do |value| ... end` block form is not implemented yet
and its delimiter syntax and parser architecture requirements (the parser is
still line-oriented) remain open questions:

```yup
values.map do |value|
  value * 2
end
```

Whichever multiline form ships should still lower to an ordinary first-class
function value, consistent with the short block form.

Actors are proposed as first-class BEAM-oriented constructs:

```yup
actor Counter
  state count = 0

  on increment
    state.count = count + 1
  end
end
```

The parser now records type annotations on the AST, but the gradual
structural checker that should consume them, the syntax for declaring new
structural types, refined types, and pre/postconditions, and how annotations
interact with actor boundaries are still proposed and unresolved:

```yup
type Percentage = Float where 0.0 <= self <= 1.0
```


String interpolation may eventually join the slice if it can be added without
distorting the bootstrap parser:

```yup
"Hello, #{name}"
```

None of these proposed forms are implemented yet.
