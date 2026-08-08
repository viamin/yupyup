defmodule Yup.AST.StateAccess do
  @moduledoc """
  Reads the current value of a model state field at a point in a transition.

  `state.name` in a transition body.
  """

  defstruct [:name, loc: nil]
end
