defmodule Yup.SourceError do
  @moduledoc """
  Source-oriented parser and compiler diagnostic.
  """

  defexception [:message, :path, :line, :column]

  def format(%__MODULE__{} = error) do
    location =
      [error.path, error.line, error.column]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    if location == "" do
      error.message
    else
      "#{location}: #{error.message}"
    end
  end
end
