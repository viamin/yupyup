# YupYup Architecture

The bootstrap pipeline is:

```text
.yup source
  -> tokenizer / parser
  -> YupYup AST
  -> semantic checks
  -> BEAM backend
  -> Erlang abstract forms
  -> Erlang compiler
  -> loaded BEAM module
```

The AST is intentionally a YupYup representation, not Erlang abstract forms. This keeps the parser independent from the execution backend and leaves room for future consumers:

```text
YupYup AST
  |-- execution/compiler
  |-- name resolver
  |-- type/contracts
  |-- model checking
  |-- constraint finding
  |-- formatter/tooling
```

## Current Components

`Yup.Parser` is a small hand-written parser. It preserves line and column locations on AST nodes. The parser is line-oriented for the first slice, but this is not a long-term grammar commitment.

`Yup.AST.*` modules define explicit structs for programs, functions, calls, bindings, identifiers, literals, binary operations, and unary operations.

`Yup.Compiler` owns compilation and execution orchestration.

`Yup.Compiler.Erlang` lowers YupYup AST to Erlang abstract forms. The backend boundary is explicit so later backends, analyzers, and test helpers can inspect YupYup AST before lowering.

`Yup.Runtime` contains tiny runtime helpers for operations whose semantics are YupYup-specific, such as string-aware `+` and `puts`.

`Yup.CLI` exposes the `yup` escript commands.

## Architectural Decisions

The bootstrap uses Erlang abstract forms and `:compile.forms/2` rather than generating BEAM bytecode. This keeps the implementation close to supported Erlang/OTP compiler machinery.

Generated modules are named deterministically from the source path when available, or from the program term for in-memory compilation. Before loading a generated module, the compiler purges and deletes any older module with the same name.

Bindings are immutable. Rebinding a name in the same scope is rejected before lowering. Erlang variables also reinforce this design choice.

Records are first-class immutable product types. Their declarations live on `Yup.AST.Program.records` and are validated by `Yup.Compiler.Erlang` before lowering. Construction lowers to a BEAM map literal and field access lowers to `maps:get/2`, which keeps the runtime simple until a richer structural type system can take over.

## Open Tradeoffs

The current parser is intentionally simple. It should be replaced or evolved when YupYup needs indentation/newline-sensitive Ruby-like syntax, better recovery, multiline expressions, blocks, and richer diagnostics.

The runtime currently executes compiled modules in the current VM. Future compilation commands may want persistent `.beam` output, source maps, or isolated execution.

