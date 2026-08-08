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

## Current Limitations

The parser is line-oriented and intentionally tiny. It does not support nested blocks other than `def ... end`, string interpolation, arrays, maps, comments inside string literals, dot calls, pattern matching, actors, types, or verification constructs.

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