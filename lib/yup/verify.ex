defmodule Yup.Verify do
  @moduledoc """
  Entry point for `yup verify`: finite-state exploration of a model.

  Parses the file, requires exactly one `model` block (executable code may
  coexist but is neither executed nor compiled), and runs the breadth-first
  explorer, checking any declared invariants at every explored state (issue
  #10). Returns `{:ok, result}` for an exploration that ran to completion and
  `{:error, error}` for parse or evaluation errors, incomplete searches, and
  invariant violations; a completed exploration reports what held at the
  explored states, never an unbounded proof claim.
  """

  alias Yup.AST.Program
  alias Yup.SourceError
  alias Yup.Verify.{Explorer, Result}

  def verify_file(path, opts \\ []) do
    with {:ok, source} <- read_source(path),
         {:ok, program} <- Yup.Parser.parse(source, path: path) do
      verify_program(program, opts)
    end
  end

  defp read_source(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, %File.Error{action: "read", path: path, reason: reason}}
    end
  end

  # @spec VERIFY-1
  def verify_program(%Program{} = program, opts \\ []) do
    path = Keyword.get(opts, :path, program.source_path)

    with :ok <- require_single_model(program.models, path) do
      Explorer.explore(hd(program.models), Keyword.put(opts, :path, path))
    end
  end

  # @spec VERIFY-5
  # @spec INVARIANT-4
  def format_result(%Result{} = result) do
    "model #{result.model_name}: exploration complete: " <>
      format_counts(result.states, result.transitions) <>
      " explored" <> held_invariants(result)
  end

  # The suffix is scoped to explored states so a completed search never
  # implies unbounded proof (issue #10 constraint).
  defp held_invariants(%Result{invariants: []}), do: ""

  defp held_invariants(%Result{invariants: invariants}) do
    "; " <> pluralize(length(invariants), "invariant") <> " held at every explored state"
  end

  # Shared between the complete and incomplete messages so state/transition
  # counts always pluralize consistently.
  def format_counts(states, transitions) do
    "#{pluralize(states, "state")}, #{pluralize(transitions, "transition")}"
  end

  defp pluralize(1, word), do: "1 #{word}"
  defp pluralize(count, word), do: "#{count} #{word}s"

  defp require_single_model([_model], _path), do: :ok

  defp require_single_model(models, path) do
    {:error,
     SourceError.exception(
       path: path,
       message: "expected exactly one model to verify, found #{length(models)}"
     )}
  end
end
