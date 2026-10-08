defmodule Yup.Verify.Failure do
  @moduledoc """
  Error outcome of an attempted exploration.

  `kind` is `:evaluation` when a model expression failed to evaluate (the
  diagnostic is the source-located `Yup.SourceError`) or `:incomplete` when
  the maximum-state cap was reached with states still to explore. Evaluation
  failures retain the transition trace up to the state where the failing
  transition was attempted, for upcoming invariant counterexample work.
  """

  defstruct [:diagnostic, :state, :transition, trace: [], kind: :evaluation]

  # @spec VERIFY-7
  def format(%__MODULE__{kind: :incomplete, diagnostic: diagnostic}) do
    Yup.SourceError.format(diagnostic)
  end

  def format(%__MODULE__{kind: :evaluation, state: nil, diagnostic: diagnostic}) do
    Yup.SourceError.format(diagnostic)
  end

  def format(%__MODULE__{kind: :evaluation} = failure) do
    Yup.SourceError.format(failure.diagnostic) <>
      "\n  while applying transition #{failure.transition} to state #{format_state(failure.state)}, " <>
      "reached via: #{format_trace(failure.trace)}"
  end

  defp format_state(state) do
    fields =
      state
      |> Map.to_list()
      |> Enum.sort()
      |> Enum.map_join(", ", fn {name, value} -> "#{name}: #{inspect(value)}" end)

    "{#{fields}}"
  end

  defp format_trace([]), do: "initial state"
  defp format_trace(trace), do: Enum.join(trace, ", ")
end
