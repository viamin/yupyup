defmodule Yup.AST.BinaryOp do
  defstruct [:op, :left, :right, loc: nil]
end
