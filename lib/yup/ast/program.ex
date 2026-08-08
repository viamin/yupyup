defmodule Yup.AST.Program do
  defstruct [:source_path, body: [], functions: [], records: [], loc: nil]
end
