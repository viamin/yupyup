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
./yup run examples/match.yup
./yup run examples/records.yup
./yup run examples/dot_calls.yup
./yup run examples/collections.yup
./yup verify examples/light.yup
./yup verify --max-states 100 examples/counter.yup
./yup verify examples/invariants.yup
./yup verify examples/broken_invariant.yup
./yup verify examples/auth_code.yup
./yup verify examples/broken_auth_code.yup
./yup verify examples/pkce_exchange.yup
./yup verify examples/broken_pkce_exchange.yup
./yup export tla examples/auth_code.yup > AuthCode.tla
./yup export tla examples/pkce_exchange.yup > PkceExchange.tla
```

`yup verify` explores the reachable states of the file's single `model` block
and checks any declared invariants at every explored state. Use
`--max-states N` to set its exploration cap; an incomplete exploration exits
nonzero and reports the counts reached. A failing invariant exits nonzero and
prints its name, source location, the violating state, and a counterexample
trace from the initial state; results only ever speak about explored states,
never unbounded proof.

`examples/auth_code.yup` is the security-protocol verification example: it
models an authorization code that may be redeemed at most once, guarded by the
invariant `redemptions <= 1`. `examples/broken_auth_code.yup` is the same
protocol without the single-use guard, so verification exits nonzero with the
counterexample trace `issue, redeem, redeem` reaching the doubly-redeemed
state `{issued: true, redemptions: 2}`.

`examples/pkce_exchange.yup` models the PKCE token-exchange rule the same
way: a token may be issued only when the submitted verifier matches the
stored challenge, guarded by the invariant
`not token_issued or verifier == :matching`. The challenge and verifier
values stay abstract atoms (`:known`, `:unknown`, `:matching`, `:wrong`) and
the cryptographic checking (deriving the challenge from the verifier) is
deliberately abstracted out of this finite model: it proves the protocol
rule, not the hash. `examples/broken_pkce_exchange.yup` is the same exchange
with a server that issues the token on an invalid verifier, so verification
exits nonzero with the counterexample trace `submit_invalid_verifier`
reaching the state `{challenge: :known, token_issued: true, verifier: :wrong}`.

`yup export tla FILE` writes the file's single model as a TLA+ module on
stdout for cross-checking with an external TLA+/TLC installation; save it as
`<Model>.tla` next to the companion `.cfg` the module documents. See
[External Cross-Checking With TLA+](docs/LANGUAGE.md#external-cross-checking-with-tla)
in the language docs for the supported subset and how to run TLC.

`bin/tlc-crosscheck` automates that cross-check: it verifies each model,
exports it, runs TLC on the exported module, and exits nonzero with a
`DISAGREEMENT` line whenever the two checkers' pass/fail verdicts differ.
TLC is optional — without an installation (no `YUP_TLC`, and no `java`
with `tla2tools.jar` on `CLASSPATH`) the script and the test suite skip
cleanly:

```sh
YUP_TLC='java -cp /opt/tla2tools.jar tlc2.TLC' bin/tlc-crosscheck
```

Expected output:

```text
Hello, world
```

## Test

```sh
mix test
```

The TLC cross-check test runs only when a TLC installation is available
(`YUP_TLC`, or `java` with `tla2tools.jar` on `CLASSPATH`); otherwise it
is excluded, so the suite passes without a TLA+ install.

## Example

```yup
def hello(name)
  "Hello, " + name
end

puts hello("world")
```

Records introduce immutable product types:

```yup
record Person
  name
  age
end

person = Person.new(name: "Ada", age: 42)
puts person.name
```

Lists and maps are immutable collections; `map` and `select` are block-driven
list operations that always return a new list:

```yup
values = [1, 2, 3]
doubled = values.map { |value| value * 2 }
puts doubled

user = { name: "Ada", active: true }
puts user.name
```

## Current Capability

The bootstrap supports a small slice: function definitions, function calls, immutable local bindings, integers, strings, booleans, `nil`, arithmetic/string operators (`+`, `-`, `*`, `/`), comparison operators (`==`, `!=`, `<`, `<=`, `>`, `>=`), boolean operators (`and`, `or`, `not`), `puts`, anonymous functions/Ruby-shaped blocks (`{ |x| x * 2 }`) as first-class function values, constructor expressions (`Ok(42)`), `match` against literal, binder, and constructor patterns, immutable record types with keyword construction and dot-call field access, dot calls with full postfix chaining for ordinary immutable values (`value.operation(arg)`), and immutable list/map literals with block-driven `map`/`select` list operations.

Type annotations on function parameters, function returns, and record fields parse and survive in the AST, but the bootstrap deliberately does not enforce them — the structural type checker that will consume them is still future work.

It does not yet implement actors (including actor dot-call dispatch), a full structural type checker, formal verification, multiline `do ... end` blocks, a Set type, list indexing or list/map patterns in `match`, mutable record updates, record destructure patterns in `match`, short-circuit boolean operators in the BEAM backend, or string interpolation.

Read [docs/VISION.md](docs/VISION.md) for the larger experiment.
