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

      ["verify" | rest] ->
        verify(rest)

      ["export" | rest] ->
        export(rest)

      [] ->
        IO.puts(:stderr, usage())
        exit({:shutdown, 1})

      _ ->
        IO.puts(:stderr, "unknown command\n\n" <> usage())
        exit({:shutdown, 1})
    end
  end

  defp verify(args) do
    case OptionParser.parse(args, strict: [max_states: :integer]) do
      {opts, [path], []} ->
        case Yup.Verify.verify_file(path, opts) do
          {:ok, result} ->
            IO.puts(Yup.Verify.format_result(result))
            :ok

          {:error, error} ->
            IO.puts(:stderr, format_error(error))
            exit({:shutdown, 1})
        end

      {_opts, files, []} ->
        IO.puts(
          :stderr,
          "yup verify takes exactly one FILE, got: #{Enum.join(files, " ")}\n\n" <> usage()
        )

        exit({:shutdown, 1})

      {_opts, _files, invalid} ->
        IO.puts(:stderr, option_errors(invalid) <> "\n\n" <> usage())
        exit({:shutdown, 1})
    end
  end

  defp export(["tla" | rest]) do
    case rest do
      [path] ->
        case Yup.Export.Tla.export_file(path) do
          {:ok, module} ->
            IO.write(module)

          {:error, error} ->
            IO.puts(:stderr, format_error(error))
            exit({:shutdown, 1})
        end

      files ->
        IO.puts(
          :stderr,
          "yup export tla takes exactly one FILE, got: #{Enum.join(files, " ")}\n\n" <> usage()
        )

        exit({:shutdown, 1})
    end
  end

  defp export(_args) do
    IO.puts(:stderr, "unknown export command\n\n" <> usage())
    exit({:shutdown, 1})
  end

  defp option_errors(invalid) do
    invalid
    |> Enum.map(fn
      {flag, nil} -> "unknown option #{flag}"
      {flag, value} -> "invalid value for #{flag}: #{value}"
    end)
    |> Enum.join("\n")
  end

  defp usage do
    """
    Usage:
      yup --version
      yup run FILE
      yup verify [--max-states N] FILE
      yup export tla FILE
    """
    |> String.trim_trailing()
  end

  defp format_error(%Yup.SourceError{} = error), do: Yup.SourceError.format(error)
  defp format_error(%Yup.Verify.Failure{} = failure), do: Yup.Verify.Failure.format(failure)
  defp format_error(%File.Error{} = error), do: Exception.message(error)
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
