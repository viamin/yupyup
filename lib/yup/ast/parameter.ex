defmodule Yup.AST.Parameter do
  @moduledoc """
  A function parameter with an optional type annotation.

  Unannotated parameters carry `type: nil`. The parameter name stays available
  for the lowering pass even when the annotation is present.
  """

  defstruct [:name, type: nil, loc: nil]
end
