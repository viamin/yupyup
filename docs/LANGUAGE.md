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

Lists and maps are immutable literal values:

```yup
values = [1, 2, 3]
user = { name: "Ada", active: true }
```

A list literal is a comma-separated `[...]` element list; elements can be any
expression. A map literal is a comma-separated `{ key: value, ... }` entry
list; keys are bare identifiers (not arbitrary expressions) and lower to BEAM
atoms, matching how record fields are represented, so `user.name` reads a map
literal's `name` entry the same way it reads a record field. Duplicate keys
in the same map literal are a compile error reported at the offending key's
source location.

A `{` starting an expression is disambiguated by what follows: `{ |params|
... }` is an anonymous function literal (see [Implemented In The
Bootstrap](#implemented-in-the-bootstrap)), and any other `{` starts a map
literal.

Lists and maps support a small set of builtin operations, called either as a
dot call (`values.map { |value| value * 2 }`) or as a plain call
(`map(values, { |value| value * 2 })`) — the receiver becomes the first
argument either way, matching ordinary [dot-call
semantics](#dot-calls-and-chaining). Every operation returns a new value; the
input collection is never mutated.

| Operation | Arity | Notes |
| --- | --- | --- |
| `map(collection, fun)` | 2 | Lists only. |
| `select(collection, fun)` | 2 | Lists only; keeps elements where `fun` is truthy. |
| `each(collection, fun)` | 2 | Lists only; runs `fun` for effect and returns the original list. |
| `reduce(collection, fun)` | 2 | Lists only; the first element seeds the accumulator. Returns `nil` for an empty list. |
| `reduce(collection, initial, fun)` | 3 | Lists only. |
| `length(collection)` | 1 | Lists and maps. |
| `keys(collection)` | 1 | Maps only. |
| `values(collection)` | 1 | Maps only. |

The arity table is enforced at compile time with a source-located
`Yup.SourceError` (e.g. calling `map` with no function argument). Whether the
`fun` argument is actually a function value is not checked at compile time —
it may be a block literal, a bound name, or a call result, exactly like an
ordinary function-value argument — so passing a non-function raises an
ordinary BEAM runtime error. `map`, `select`, `each`, and `reduce` are
list-only: calling them on a map is not rejected at compile time and instead
fails with a raw BEAM `FunctionClauseError` at runtime, since `Yup.Runtime`
only defines clauses for lists.

### Call Resolution Precedence

`map`, `select`, `each`, `reduce`, `length`, `keys`, and `values` are builtin
names. A plain call to one of these names resolves in this order:

1. A top-level `def` with the same name (a user definition shadows the
   builtin entirely, for every call to that name in the program).
2. `puts`, which always resolves to `Yup.Runtime.puts/1`.
3. The collection builtin.
4. A local binding called as a function value (the fallback used for any
   other name).

This means a top-level `def map(...)` makes every call to `map(...)` resolve
to that definition instead of the builtin. But binding a local name that
merely happens to share a builtin's name — e.g. `map = { |acc, x| acc + x }`
— does not shadow the builtin for a plain call: `map(0, 5)` still resolves to
the builtin (and fails its arity check, since `map` expects a collection and
a function). Ordinary data bindings like `values = [1, 2, 3]` are unaffected
by this precedence, since `values` is never called as a function there — the
conflict only matters for a name that is both a builtin and is called
plain-call-style (`name(...)`) rather than read as a value or used as a dot
call receiver.

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

The parser is line-oriented and intentionally tiny. Anonymous function bodies are limited to a single expression on the same line as the `{ |params| ... }` literal; there is no `do ... end` block form yet (see Proposed And Unresolved). The same line-oriented constraint applies to list and map literals: `[...]` and `{ key: value }` must each fit on one line, since the parser has no notion of a multiline literal continuing past its opening line. The parser does not support nested blocks other than `def ... end`, `match ... end`, and `record ... end`, string interpolation, comments inside string literals, type-scoped methods, mutable record updates, record patterns inside `match`, guards inside `when`, exhaustive matching warnings, actors (including actor dot-call dispatch), full type checking, or verification constructs.

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