defmodule Yup.AST.Function do
  defstruct [:name, params: [], body: [], return_type: nil, loc: nil]
end
