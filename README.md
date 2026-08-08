# YupYup

YupYup is an experimental programming language targeting the Erlang BEAM. It aims to explore Ruby-like ergonomics, actor-oriented reliability, gradual structural typing, and native formal-methods concepts.

Today it is a tiny toy compiler, not a usable production language.

The language is **YupYup**. The command is **`yup`**. Source files use **`.yup`**.

## Prerequisites

- Erlang/OTP
- Elixir and Mix

The bootstrap has been tested with Elixir 1.20 and OTP 29.

## Build

```sh
mix deps.get
mix escript.build
```

This creates an executable named `yup` in the project root.

## Run

```sh
./yup --version
./yup run examples/hello.yup
./yup run examples/comparison.yup
./yup run examples/booleans.yup
./yup run examples/functions.yup
```

Expected output:

```text
Hello, world
```

## Test

```sh
mix test
```

## Example

```yup
def hello(name)
  "Hello, " + name
end

puts hello("world")
```

## Current Capability

The bootstrap supports a small slice: function definitions, function calls, immutable local bindings, integers, strings, booleans, `nil`, arithmetic/string operators (`+`, `-`, `*`, `/`), comparison operators (`==`, `!=`, `<`, `<=`, `>`, `>=`), boolean operators (`and`, `or`, `not`), `puts`, and anonymous functions/Ruby-shaped blocks (`{ |x| x * 2 }`) as first-class function values.

It does not yet implement actors, types, formal verification, dot calls, multiline `do ... end` blocks, collections, pattern matching, short-circuit boolean operators in the BEAM backend, or string interpolation.

Read [docs/VISION.md](docs/VISION.md) for the larger experiment.
