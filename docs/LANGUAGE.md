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
```

Immutable local bindings:

```yup
name = "world"
puts name
```

Rebinding the same name in a scope is a compile error and reports the source
location of the offending line.

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

## Current Limitations

The parser is line-oriented and intentionally tiny. It does not support nested blocks other than `def ... end`, `match ... end`, and `record ... end`, string interpolation, arrays, comments inside string literals, general method-call dot syntax, mutable record updates, record patterns inside `match`, guards inside `when`, exhaustive matching warnings, actors, types, or verification constructs.

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

Blocks should lower to ordinary first-class functions:

```yup
double = { |x| x * 2 }

values.map do |value|
  value * 2
end
```

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

Formal models should be expressible at abstraction levels different from executable code:

```yup
model Light
  state value = :off

  transition toggle do
    state.value = value == :off ? :on : :off
  end
end
```

String interpolation may eventually join the slice if it can be added without
distorting the bootstrap parser:

```yup
"Hello, #{name}"
```

None of these proposed forms are implemented yet.