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

The bootstrap supports a tiny slice: function definitions, function calls, immutable local bindings, integers, strings, booleans, `nil`, basic arithmetic/string operators, and `puts`.

It does not yet implement actors, types, formal verification, dot calls, blocks, collections, pattern matching, or string interpolation.

Read [docs/VISION.md](docs/VISION.md) for the larger experiment.
