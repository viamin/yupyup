defmodule Yup.AST.ListLiteral do
  @moduledoc """
  An immutable list literal, e.g. `[1, 2, 3]`.

  Lists lower to BEAM lists, so they stay cheap and pattern-friendly on the
  Erlang side. A list is an ordinary immutable value: collection operations
  return new lists and never mutate the original.
  """

  defstruct elements: [], loc: nil
end
