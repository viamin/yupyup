defmodule Yup.AST.Invariant do
  @moduledoc """
  A named model invariant declared inside a `model` block.

  Invariants are model properties: `yup verify` evaluates the condition at
  every explored state and reports a counterexample trace when it fails. They
  are not production code assertions and never lower to BEAM.
  """

  defstruct [:name, :condition, :loc]
end
