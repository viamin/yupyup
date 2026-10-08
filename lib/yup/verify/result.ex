defmodule Yup.Verify.Result do
  @moduledoc """
  Outcome of a completed-or-aborted exploration: counts, the names of any
  invariants that held at every explored state, and the predecessor
  information needed to reconstruct transition paths.

  States are canonicalized as the field list sorted by name, which is the
  visited-set key (exact deduplication, no hash collisions). The compact
  state id exposed to callers is a deterministic `:erlang.phash2/1` of that
  canonical form.
  """

  defstruct [
    :model_name,
    :path,
    :max_states,
    :initial,
    states: 0,
    transitions: 0,
    complete: true,
    order: [],
    parents: %{},
    invariants: []
  ]

  def complete?(%__MODULE__{complete: complete}), do: complete

  # @spec VERIFY-4
  def states(%__MODULE__{order: order}) do
    Enum.map(order, fn canonical -> {state_id_of(canonical), Map.new(canonical)} end)
  end

  def state_id(state) when is_map(state), do: state_id_of(canonical_form(state))

  def canonical_form(state) when is_map(state) do
    state |> Map.to_list() |> Enum.sort()
  end

  # @spec VERIFY-4
  def trace(parents, canonical), do: trace_back(parents, canonical, [])

  defp trace_back(_parents, nil, acc), do: acc

  defp trace_back(parents, canonical, acc) do
    case Map.fetch(parents, canonical) do
      {:ok, {nil, _name}} -> acc
      {:ok, {parent, name}} -> trace_back(parents, parent, [name | acc])
      :error -> acc
    end
  end

  # @spec VERIFY-4
  def trace_to(%__MODULE__{parents: parents}, target) do
    canonical = canonical_form(target)

    if Map.has_key?(parents, canonical) do
      {:ok, trace(parents, canonical)}
    else
      {:error, :unknown_state}
    end
  end

  defp state_id_of(canonical), do: :erlang.phash2(canonical)
end
