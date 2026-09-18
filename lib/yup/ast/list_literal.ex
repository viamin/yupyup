defmodule Yup.AST.ListLiteral do
  @moduledoc """
  An immutable list literal, e.g. `[1, 2, 3]`.

  Lowers to a native BEAM list. Collection operations such as `map` and
  `select` always return a new list; the original `ListLiteral` value is
  never mutated.
  """

  defstruct elements: [], loc: nil
end
