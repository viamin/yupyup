defmodule Yup.Runtime do
  @moduledoc false

  def add(left, right) when is_binary(left) or is_binary(right) do
    to_string(left) <> to_string(right)
  end

  def add(left, right), do: left + right

  def subtract(left, right), do: left - right
  def multiply(left, right), do: left * right
  def divide(left, right), do: div(left, right)

  def puts(value) do
    IO.puts(value)
    :ok
  end
end
