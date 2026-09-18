defmodule Yup.AST.MapLiteral do
  @moduledoc """
  An immutable map literal, e.g. `{ name: "Ada", active: true }`.

  Entries are `key: value` pairs whose keys are bare identifiers; keys lower
  to BEAM atoms, matching the record representation so dot field access like
  `user.name` works uniformly. Maps lower to BEAM maps and are immutable:
  operations never mutate the original value.
  """

  defstruct entries: [], loc: nil
end
