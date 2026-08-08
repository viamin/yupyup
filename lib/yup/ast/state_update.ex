defmodule Yup.AST.StateUpdate do
  @moduledoc """
  Sets the new value of a model state field within a transition.

  `state.name = expr` in a transition body.
  """

  defstruct [:name, :value, loc: nil]
end
