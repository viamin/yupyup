defmodule Yup.AST.Program do
  defstruct [:source_path, body: [], functions: [], loc: nil]
end
