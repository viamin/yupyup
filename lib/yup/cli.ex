defmodule Yup.CLI do
  @moduledoc false

  def main(args) do
    case args do
      ["--version"] ->
        IO.puts("yup #{Yup.version()}")

      ["run", path] ->
        case Yup.run_file(path) do
          {:ok, _result} ->
            :ok

          {:error, error} ->
            IO.puts(:stderr, format_error(error))
            exit({:shutdown, 1})
        end

      [] ->
        IO.puts(:stderr, usage())
        exit({:shutdown, 1})

      _ ->
        IO.puts(:stderr, "unknown command\n\n" <> usage())
        exit({:shutdown, 1})
    end
  end

  defp usage do
    """
    Usage:
      yup --version
      yup run FILE
    """
    |> String.trim_trailing()
  end

  defp format_error(%Yup.SourceError{} = error), do: Yup.SourceError.format(error)
  defp format_error(%File.Error{} = error), do: Exception.message(error)
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
