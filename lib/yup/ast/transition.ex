defmodule Yup.AST.Transition do
  @moduledoc """
  A named transition within a model.

  The body describes how model state changes when this transition fires.
  """

  defstruct [:name, body: [], loc: nil]
end
