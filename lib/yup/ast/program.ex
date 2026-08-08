defmodule Yup.AST.Program do
  defstruct [:source_path, body: [], functions: [], models: [], loc: nil]
end
