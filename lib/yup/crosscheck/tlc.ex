defmodule Yup.Crosscheck.Tlc do
  @moduledoc """
  Cross-checks `yup verify` results against TLC on exported TLA+ modules
  (issue #21, building on the #20 export).

  The verifier and the exporter share the same parser and model semantics,
  so neither can confirm the other. TLC is the independent checker: for
  each model this module runs `Yup.Verify.verify_file/2` in-process,
  writes `Yup.Export.Tla.export_file/1` output plus a companion `.cfg`
  into a working directory, runs TLC there, and compares verdicts.
  Agreement means both checkers passed the model or both failed it;
  disagreement and anything that is not a verdict are reported loudly.

  TLC is optional. `find_tlc/1` locates an installation through the
  `YUP_TLC` environment variable or the `java` + `CLASSPATH` tla2tools
  convention, and `main/1` skips with exit 0 when none is found, so CI
  and `mix test` pass on machines without a TLA+ install.
  """

  alias Yup.Export.Tla
  alias Yup.SourceError
  alias Yup.Verify
  alias Yup.Verify.{Failure, Result}

  @default_files [
    "examples/auth_code.yup",
    "examples/pkce_exchange.yup",
    "examples/broken_auth_code.yup",
    "examples/broken_pkce_exchange.yup"
  ]

  @module_header ~r/^-+ MODULE ([A-Za-z0-9_]+) -+$/m
  @invariant_definition ~r/^(Invariant\d+) ==/m
  @excerpt_lines 10

  @doc """
  Entry point for `bin/tlc-crosscheck` (also usable as
  `mix run -e 'Yup.Crosscheck.Tlc.main(System.argv())' -- FILE...`).

  With no arguments it cross-checks the example models, including the
  deliberately broken fixtures. Exits 0 when TLC is missing (skip) or
  every verdict agrees, and 1 when any model disagrees or cannot be
  cross-checked.
  """
  # @spec TLA-XC-1
  # @spec TLA-XC-5
  def main(argv) do
    files = if argv == [], do: @default_files, else: argv

    case find_tlc() do
      {:ok, tlc} ->
        results = crosscheck(files, tlc)
        IO.puts([header(length(files), results), ?\n, report(results)])
        System.halt(exit_code(results))

      :error ->
        IO.puts("TLC not found; skipping cross-check (#{tlc_hint()})")
        System.halt(0)
    end
  end

  @doc """
  Locates a TLC installation. `env` defaults to `System.get_env/0`.

  Returns `{:ok, command_words}` when `YUP_TLC` names the command
  (word-split, e.g. `java -cp /opt/tla2tools.jar tlc2.TLC`), or when
  `java` is on `PATH` and `CLASSPATH` names at least one existing entry
  (the tla2tools.jar install convention). Returns `:error` otherwise.
  """
  # @spec TLA-XC-1
  def find_tlc(env \\ System.get_env()) do
    case String.trim(env["YUP_TLC"] || "") do
      "" ->
        if executable_on_path?("java", env["PATH"] || "") and
             classpath_entry_exists?(env["CLASSPATH"]) do
          {:ok, ["java", "tlc2.TLC"]}
        else
          :error
        end

      override ->
        {:ok, String.split(override)}
    end
  end

  @doc """
  Cross-checks `files` against `tlc` (command words) and returns one
  result map per file, in order, with keys:

  - `:file`, `:model` — the source path and the exported model name
  - `:yup` — `:pass`, `:fail`, or `:none` (the verifier produced no
    verdict: the file could not be read, parsed, or fully explored)
  - `:tlc` — TLC's exit status, or nil when TLC was not run
  - `:status` — `:agree`, `:disagree`, or `:error`
  - `:detail` — explanation for `:error` entries, nil otherwise
  - `:tlc_output` — TLC's combined output, kept for disagreement excerpts
  - `:work_dir` — the per-file run directory (named after the source
    basename) holding the exports and TLC's artifacts

  Options: `:work_dir` (the shared parent of the run directories; default
  a fresh directory under the system temp directory, kept after the run so
  TLC's artifacts can be inspected).
  """
  # @spec TLA-XC-2
  # @spec TLA-XC-5
  # @spec TLA-XC-6
  def crosscheck(files, tlc, opts \\ []) do
    work_dir = Keyword.get_lazy(opts, :work_dir, &fresh_work_dir/0)
    File.mkdir_p!(work_dir)
    Enum.map(files, &crosscheck_file(&1, tlc, work_dir))
  end

  @doc """
  0 when every result agrees, 1 when any model disagrees or could not be
  cross-checked.
  """
  # @spec TLA-XC-3
  # @spec TLA-XC-6
  def exit_code(results) do
    if Enum.all?(results, &(&1.status == :agree)), do: 0, else: 1
  end

  @doc """
  One line per result plus a summary line; disagreement lines carry both
  checkers' outcomes and an excerpt of TLC's output.
  """
  # @spec TLA-XC-3
  def report(results) do
    agreeing = Enum.count(results, &(&1.status == :agree))
    summary = "TLC cross-check: #{agreeing}/#{length(results)} models agree"

    results
    |> Enum.map(&format_line/1)
    |> Enum.concat([summary])
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # ── per-file pipeline ───────────────────────────────────────────────

  defp header(file_count, []), do: "TLC cross-check: #{file_count} file(s)"

  defp header(file_count, [%{work_dir: run_dir} | _]),
    do: "TLC cross-check: #{file_count} file(s), work dir #{Path.dirname(run_dir)}"

  # Two source files may export the same model name (auth_code.yup and
  # broken_auth_code.yup both declare `model AuthCode`), so each file gets
  # its own run directory under the shared work dir; TLC runs there with a
  # freshly written module and cfg.
  defp crosscheck_file(file, tlc, work_dir) do
    run_dir = Path.join(work_dir, Path.rootname(Path.basename(file)))
    File.mkdir_p!(run_dir)

    with {:ok, verdict} <- verify_verdict(file),
         {:ok, module_text} <- Tla.export_file(file),
         {:ok, model} <- module_name(module_text) do
      run_and_compare(file, tlc, model, module_text, verdict, run_dir)
    else
      {:error, message} -> error_result(file, format_error(message), run_dir)
    end
  end

  # Only a completed exploration or an invariant violation is a verdict;
  # truncated runs, evaluation failures, and parse or file errors are not
  # comparable with TLC and become cross-check errors instead.
  # @spec TLA-XC-6
  defp verify_verdict(file) do
    case Verify.verify_file(file) do
      {:ok, %Result{}} ->
        {:ok, :pass}

      {:error, %Failure{kind: :invariant}} ->
        {:ok, :fail}

      {:error, %Failure{} = failure} ->
        {:error, Failure.format(failure)}

      {:error, error} ->
        {:error, format_error(error)}
    end
  end

  # The exported module and its companion .cfg must exist in TLC's run
  # directory before TLC is invoked (TLA-XC-4). The .cfg mirrors the
  # trailing comment the exporter documents: SPECIFICATION Spec plus one
  # INVARIANT line per numbered invariant definition.
  # @spec TLA-XC-4
  defp run_and_compare(file, tlc, model, module_text, verdict, run_dir) do
    File.write!(Path.join(run_dir, model <> ".tla"), module_text)

    File.write!(
      Path.join(run_dir, model <> ".cfg"),
      ["SPECIFICATION Spec\n" | config_invariants(module_text)]
    )

    case run_tlc(tlc, model, run_dir) do
      {tlc_output, nil} ->
        error_result(file, tlc_output, run_dir)

      {tlc_output, tlc_status} ->
        %{
          file: file,
          model: model,
          yup: verdict,
          tlc: tlc_status,
          status: status(verdict, tlc_status),
          detail: nil,
          tlc_output: tlc_output,
          work_dir: run_dir
        }
    end
  end

  defp config_invariants(module_text) do
    for [_, name] <- Regex.scan(@invariant_definition, module_text) do
      "INVARIANT #{name}\n"
    end
  end

  defp run_tlc([command | args], model, work_dir) do
    System.cmd(command, args ++ [model], cd: work_dir, stderr_to_stdout: true)
  rescue
    error ->
      {"could not run TLC (#{inspect(tlc_error_command(command))}): #{Exception.message(error)}",
       nil}
  end

  defp tlc_error_command(command) when is_binary(command), do: command
  defp tlc_error_command(command), do: inspect(command)

  defp module_name(module_text) do
    case Regex.run(@module_header, module_text) do
      [_, name] -> {:ok, name}
      nil -> {:error, "could not find a MODULE header in the exported module"}
    end
  end

  defp status(verdict, tlc_status) do
    if agree?(verdict, tlc_status), do: :agree, else: :disagree
  end

  defp agree?(verdict, tlc_status) do
    (verdict == :pass and tlc_status == 0) or (verdict == :fail and tlc_status != 0)
  end

  defp error_result(file, detail, run_dir) do
    %{
      file: file,
      model: nil,
      yup: :none,
      tlc: nil,
      status: :error,
      detail: detail,
      tlc_output: "",
      work_dir: run_dir
    }
  end

  # ── reporting ───────────────────────────────────────────────────────

  defp format_line(%{status: :agree, file: file, model: model, yup: verdict, tlc: tlc_status}) do
    "  agree     #{file} (#{model}): yup #{verdict(verdict)}, tlc #{tlc_outcome(tlc_status)}"
  end

  # @spec TLA-XC-3
  defp format_line(%{status: :disagree} = result) do
    "  DISAGREEMENT #{result.file} (#{result.model}): " <>
      "yup #{verdict(result.yup)} but tlc #{tlc_outcome(result.tlc)}\n" <>
      excerpt(result.tlc_output)
  end

  defp format_line(%{status: :error, file: file, detail: detail}) do
    "  error     #{file}: #{detail}"
  end

  defp verdict(:pass), do: "passed"
  defp verdict(:fail), do: "failed (invariant)"
  defp verdict(:none), do: "produced no verdict"

  defp tlc_outcome(0), do: "passed"
  defp tlc_outcome(status), do: "exited #{status}"

  defp excerpt(output) do
    lines =
      output
      |> String.split("\n", trim: true)
      |> Enum.take(-@excerpt_lines)
      |> Enum.map(&"    #{&1}")

    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n")
    end
  end

  # ── TLC discovery ───────────────────────────────────────────────────

  defp executable_on_path?(name, path) do
    path
    |> String.split(":", trim: true)
    |> Enum.map(&Path.join(&1, name))
    |> Enum.any?(&File.exists?/1)
  end

  defp classpath_entry_exists?(nil), do: false

  defp classpath_entry_exists?(classpath) do
    classpath
    |> String.split(":", trim: true)
    |> Enum.any?(&File.exists?/1)
  end

  defp fresh_work_dir do
    unique = System.unique_integer([:positive])
    Path.join(System.tmp_dir!(), "yup-tlc-crosscheck-#{unique}")
  end

  defp tlc_hint do
    "set YUP_TLC to the TLC command, or put tla2tools.jar on CLASSPATH with java on PATH"
  end

  defp format_error(%SourceError{} = error), do: SourceError.format(error)
  defp format_error(%File.Error{} = error), do: Exception.message(error)
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
