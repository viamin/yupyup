defmodule Yup.AST.Model do
  @moduledoc """
  A formal model declaration. Models are non-executable, abstract state-machine
  descriptions that coexist alongside executable code.

  A model contains state field declarations, named transitions that describe
  how state changes, and named invariants checked at every explored state by
  `yup verify`.
  """

  defstruct [:name, states: [], transitions: [], invariants: [], loc: nil]
end
