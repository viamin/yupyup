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

## Current Limitations

The parser is line-oriented and intentionally tiny. Anonymous function bodies are limited to a single expression on the same line as the `{ |params| ... }` literal; there is no `do ... end` block form yet (see Proposed And Unresolved). The parser does not support nested statement blocks other than `def ... end`, `match ... end`, `model ... end`, and `transition ... end`, string interpolation, arrays, maps, comments inside string literals, dot calls, full record syntax, guards inside `when`, exhaustive matching warnings, actors, types, or verification constructs (model checking and refinement checking are not yet implemented).

Boolean operators are not short-circuiting in the BEAM backend yet. `true or (1 / 0)` evaluates both sides today.

## Proposed And Unresolved

Dot calls may eventually make:

```yup
value.operation(arg)
```

behave conceptually like:

```yup
operation(value, arg)
```

for ordinary immutable values. Dot calls on actor references may instead represent message operations. The syntax can look similar while dispatch semantics depend on the receiver.

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

Types should be native, gradual, and structural:

```yup
def greet(person: Person) -> String
  "Hello, " + person.name
end

type Percentage = Float where 0.0 <= self <= 1.0
```


String interpolation may eventually join the slice if it can be added without
distorting the bootstrap parser:

```yup
"Hello, #{name}"
```

None of these proposed forms are implemented yet.