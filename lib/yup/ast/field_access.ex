defmodule Yup.AST.FieldAccess do
  defstruct [:record, :field, loc: nil]
end
