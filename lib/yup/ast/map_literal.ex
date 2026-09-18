defmodule Yup.AST.MapLiteral do
  @moduledoc """
  An immutable, untyped map literal, e.g. `{ name: "Ada", active: true }`.

  A `MapLiteral` is the dynamic counterpart to a `Yup.AST.RecordConstruction`:
  it builds a map value without a declared `record` type. `fields` holds
  `{name, value, loc}` triples, matching `RecordConstruction.fields`, so
  lowering and field access share the same shape as records.
  """

  defstruct fields: [], loc: nil
end
