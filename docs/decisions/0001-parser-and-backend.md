# 0001. Bootstrap Parser And BEAM Backend

## Status

Accepted for bootstrap.

## Decision

Use a small hand-written parser for the first vertical slice and lower explicit YupYup AST to Erlang abstract forms consumed by `:compile.forms/2`.

## Context

The first milestone needs `yup run examples/hello.yup`, source locations, a genuine YupYup AST, and a BEAM execution path. A parser generator may become useful later, but the initial grammar is small enough that a hand-written parser is clearer and easier to change.

## Consequences

The parser is intentionally limited and line-oriented. This is acceptable for the bootstrap but should be revisited when blocks, dot chaining, multiline expressions, and richer errors become important.

The backend avoids hand-written BEAM bytecode and relies on Erlang/OTP compiler machinery. Backend-specific forms stay behind `Yup.Compiler.Erlang`.

