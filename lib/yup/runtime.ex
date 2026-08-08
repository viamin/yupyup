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
    IO.puts(value)
    :ok
  end

  defp truthy?(value) when value in [nil, false], do: false
  defp truthy?(_value), do: true
end
