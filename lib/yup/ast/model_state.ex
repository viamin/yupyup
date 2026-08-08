defmodule Yup.AST.ModelState do
  @moduledoc """
  A state field declaration within a model.

  Names the field and provides an initial (deterministic) value expression.
  """

  defstruct [:name, :value, loc: nil]
end
