defmodule Yup.Runtime do
  @moduledoc false

  def add(left, right) when is_binary(left) or is_binary(right) do
    to_string(left) <> to_string(right)
  end

  def add(left, right), do: left + right

  def subtract(left, right), do: left - right
  def multiply(left, right), do: left * right
  def divide(left, right), do: div(left, right)

  def equal?(left, right), do: left == right
  def not_equal?(left, right), do: left != right
  def less?(left, right), do: left < right
  def less_or_equal?(left, right), do: left <= right
  def greater?(left, right), do: left > right
  def greater_or_equal?(left, right), do: left >= right

  def and_op(left, right), do: truthy?(left) and truthy?(right)
  def or_op(left, right), do: truthy?(left) or truthy?(right)
  def not_op(value), do: not truthy?(value)

  def puts(value) when is_list(value) or is_map(value) do
    IO.puts(inspect(value, charlists: :as_list))
    :ok
  end

  def puts(value) do
    IO.puts(value)
    :ok
  end

  # ── immutable collection operations ─────────────────────────────────
  # Every operation returns a new value; the input collection is never
  # mutated (BEAM lists and maps are structurally immutable anyway).

  def map(list, fun) when is_list(list), do: Enum.map(list, fun)

  def select(list, fun) when is_list(list) do
    Enum.filter(list, fn element -> truthy?(fun.(element)) end)
  end

  def each(list, fun) when is_list(list) do
    Enum.each(list, fun)
    list
  end

  # Ruby-shaped reduce: the block receives (memo, element) and, without an
  # explicit initial value, the first element seeds the memo.
  def reduce([first | rest], fun), do: do_reduce(rest, first, fun)
  def reduce([], _fun), do: nil
  def reduce(list, initial, fun) when is_list(list), do: do_reduce(list, initial, fun)

  def length(value) when is_list(value), do: :erlang.length(value)
  def length(value) when is_map(value), do: map_size(value)

  def keys(map) when is_map(map), do: Map.keys(map)
  def values(map) when is_map(map), do: Map.values(map)

  defp do_reduce(list, initial, fun) do
    Enum.reduce(list, initial, fn element, memo -> fun.(memo, element) end)
  end

  defp truthy?(value) when value in [nil, false], do: false
  defp truthy?(_value), do: true
end
