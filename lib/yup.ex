defmodule Yup do
  @moduledoc """
  Public entry point for the YupYup bootstrap compiler.
  """

  @version Mix.Project.config()[:version]

  def version, do: @version

  def run_file(path) do
    with {:ok, source} <- File.read(path),
         {:ok, program} <- Yup.Parser.parse(source, path: path),
         {:ok, module} <- Yup.Compiler.compile(program),
         {:ok, result} <- Yup.Compiler.run(module) do
      {:ok, result}
    end
  end
end
