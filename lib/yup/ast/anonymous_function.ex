defmodule Yup.AST.AnonymousFunction do
  @moduledoc """
  A block-shaped function value, e.g. `{ |x| x * 2 }`.

  Anonymous functions are ordinary first-class function values. They are a
  distinct AST node from `Yup.AST.Function` only because they are expressions
  (bindable and passable) rather than named top-level declarations.
  """

  defstruct params: [], body: [], loc: nil
end
