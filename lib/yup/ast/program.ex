defmodule Yup.AST.Program do
  defstruct [:source_path, body: [], functions: [], records: [], models: [], loc: nil]
end
