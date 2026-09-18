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

  def puts(value) do
    value |> display() |> IO.puts()
    :ok
  end

  def map(list, fun) when is_list(list), do: Enum.map(list, fun)
  def select(list, fun) when is_list(list), do: Enum.filter(list, fun)

  # Lists and maps print as `[1, 2, 3]` / `{name: "Ada"}` rather than going
  # through IO.puts's charlist/Chars heuristics directly, since a YupYup list
  # of integers is otherwise indistinguishable from an Erlang charlist. Map
  # keys are sorted for deterministic output since BEAM map iteration order
  # is not insertion order.
  defp display(nil), do: "nil"

  defp display(value) when is_list(value) do
    "[" <> Enum.map_join(value, ", ", &nested_display/1) <> "]"
  end

  defp display(value) when is_map(value) do
    fields =
      value
      |> Map.to_list()
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join(", ", fn {key, val} -> "#{key}: #{nested_display(val)}" end)

    "{" <> fields <> "}"
  end

  # Constructor values are tagged tuples and String.Chars has no tuple
  # implementation, so they print in their YupYup source shape, `Ok(1)`.
  # Payloads use the nested rules so strings inside stay quoted.
  defp display(value) when is_tuple(value) do
    [tag | args] = Tuple.to_list(value)
    Atom.to_string(tag) <> "(" <> Enum.map_join(args, ", ", &nested_display/1) <> ")"
  end

  # Function values have no String.Chars implementation either; print their
  # opaque inspect form rather than crashing.
  defp display(value) when is_function(value), do: inspect(value)

  defp display(value), do: to_string(value)

  defp nested_display(value) when is_binary(value), do: inspect(value)
  defp nested_display(value), do: display(value)

  defp truthy?(value) when value in [nil, false], do: false
  defp truthy?(_value), do: true
end
