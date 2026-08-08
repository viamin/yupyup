defmodule Yup.AST do
  @moduledoc """
  Explicit YupYup AST structs.

  The parser produces these structs instead of Erlang abstract forms so future
  compiler passes, tooling, type checkers, model checkers, and formatters have a
  YupYup-native representation to consume.

  Type annotations on function parameters, function returns, and record fields
  live on the AST as `Yup.AST.TypeRef` payloads attached to `Parameter`,
  `Function.return_type`, and `RecordField` nodes. The bootstrap parser
  preserves them but does not enforce them; a future checker owns that work.
  """
end
