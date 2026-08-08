defmodule Yup.AST.Model do
  @moduledoc """
  A formal model declaration. Models are non-executable, abstract state-machine
  descriptions that coexist alongside executable code.

  A model contains state field declarations and named transitions that describe
  how state changes.
  """

  defstruct [:name, states: [], transitions: [], loc: nil]
end
