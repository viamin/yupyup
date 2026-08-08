defmodule Yup.AST.TypeRef do
  @moduledoc """
  A reference to a type by name, used as the payload of a parameter or record
  field annotation.

  Type annotations are preserved on the AST for later checkers; this slice of
  YupYup parses them but does not enforce them.
  """

  defstruct [:name, loc: nil]
end
