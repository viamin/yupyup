defmodule Yup.AST.TernaryOp do
  @moduledoc """
  A ternary conditional expression: `condition ? then_expr : else_expr`.
  """

  defstruct [:condition, :then_expr, :else_expr, loc: nil]
end
