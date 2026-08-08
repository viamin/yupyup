defmodule Yup.Compiler do
  @moduledoc """
  Compiler facade for YupYup programs.
  """

  alias Yup.Compiler.Erlang
  alias Yup.SourceError

  def compile(program) do
    forms = Erlang.lower(program)
    module = Erlang.module_name(program)

    case :compile.forms(forms, [:binary, :return_errors]) do
      {:ok, ^module, binary} ->
        :code.purge(module)
        :code.delete(module)

        case :code.load_binary(module, ~c"nofile", binary) do
          {:module, ^module} -> {:ok, module}
          {:error, reason} -> {:error, "failed to load generated module: #{inspect(reason)}"}
        end

      {:error, errors, warnings} ->
        {:error, format_compile_errors(errors, warnings)}
    end
  rescue
    error in SourceError -> {:error, error}
  end

  def run(module), do: {:ok, apply(module, :run, [])}

  defp format_compile_errors(errors, warnings) do
    details =
      (List.wrap(errors) ++ List.wrap(warnings))
      |> Enum.map(&inspect/1)
      |> Enum.join("\n")

    "generated BEAM compilation failed\n" <> details
  end
end
