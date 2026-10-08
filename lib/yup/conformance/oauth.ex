defmodule Yup.Conformance.OAuth do
  @moduledoc """
  Interoperability harness for the OAuth runtime example (issue #24).

  The OpenID Foundation Conformance Suite drives a deployed HTTPS
  provider end to end, so it cannot run against
  `examples/oauth_runtime.yup` — an in-process YupYup function slice
  with no HTTP. Where the supported subset fits, this module is the
  repeatable path: a manifest of conformance cases
  (`Yup.Conformance.OAuth.Cases`), each anchored to the RFC behavior an
  external suite's test implements, replayed against the compiled
  runtime in protocol shape (authorization and token requests), and
  tied back to the #23 trace check — every step of every case is also
  mapped through `Yup.OAuthTrace` and checked against the verified
  models. A case passes only when the RFC-derived expectation about the
  outcome and the model conformance both hold.

  This is an interoperability harness, not certification. When
  `YUP_OIDF_SUITE` names an external suite target — a deployment URL
  such as `https://www.certification.openid.net` or a local
  conformance-suite checkout — the harness also writes a deterministic
  `plan.json` into the work dir recording the suite target, the
  deployment shape a suite-compatible deployment would need, and every
  case with its support status and reason: the hand-off artifact for a
  manual suite run. The URL must be reachable for the plan to be
  written — a HEAD request confirms the deployment is up, treating an
  unreachable target as a configuration error rather than reporting a
  nonexistent suite as a successful run. Without `YUP_OIDF_SUITE` the
  external part is skipped with a note while the local subset still
  runs.
  """

  alias Yup.Conformance.OAuth.Cases
  alias Yup.OAuthTrace, as: Mapping
  alias Yup.SourceError
  alias Yup.Verify
  alias Yup.Verify.Trace

  @default_runtime "examples/oauth_runtime.yup"
  @default_models ["examples/auth_code.yup", "examples/pkce_exchange.yup"]

  @doc """
  Entry point for `bin/oauth-conformance` (also usable as
  `mix run -e 'Yup.Conformance.OAuth.main(System.argv())' -- FILE`).

  With no argument it checks the good runtime example; an argument
  names another runtime file (`examples/broken_oauth_runtime.yup` is
  the deliberately failing demo). Prints one line per case and exits 0
  when every supported case passes and the external suite — when
  configured — is usable, 1 otherwise.
  """
  # @spec OAUTH-CF-1
  # @spec OAUTH-CF-2
  # @spec OAUTH-CF-3
  def main(argv) do
    results = run(runtime_file: runtime_file(argv), suite: suite_from_env())
    IO.puts(report(results))
    System.halt(exit_code(results))
  end

  @doc """
  Locates the external suite target. `env` defaults to
  `System.get_env/0`.

  Returns `{:ok, %{kind: :url, target: url}}` when `YUP_OIDF_SUITE`
  names an `http(s)://` deployment, `{:ok, %{kind: :path, target:
  path}}` when it names anything else (a conformance-suite checkout),
  and `:error` when it is unset or blank.
  """
  # @spec OAUTH-CF-1
  # @spec OAUTH-CF-5
  def find_suite(env \\ System.get_env()) do
    case String.trim(env["YUP_OIDF_SUITE"] || "") do
      "" ->
        :error

      target ->
        is_url = String.starts_with?(target, ["http://", "https://"])
        kind = if is_url, do: :url, else: :path
        {:ok, %{kind: kind, target: target}}
    end
  end

  @doc """
  Runs the manifest and returns the results map with keys:

  - `:runtime_file`, `:work_dir` — the runtime under check and the run
    directory (kept after the run; the plan lands there)
  - `:setup` — `:ok`, or `{:error, detail}` when a model stopped
    verifying or the runtime file could not be loaded; no cases run
  - `:supported` — one result per supported case: `%{id, title,
    source, protocol, models}` where `protocol` is `:pass` or
    `{:fail, detail}` and `models` is `:conform` or `{:disagree,
    detail}`
  - `:unsupported` — `%{id, title, source, reason}` per documented
    expected failure
  - `:suite` — `:not_configured`, the described suite map, or
    `{:error, detail}` for an unusable target
  - `:plan_path` — where `plan.json` was written, or nil

  Options: `:runtime_file` (default `examples/oauth_runtime.yup`),
  `:work_dir` (default a fresh directory under the system temp
  directory), `:suite` (default `:not_configured`; pass a map shaped
  like `find_suite/1`'s `{:ok, _}` value), `:probe` (a 1-arity
  function used to verify that a `:url` suite is reachable — defaults
  to a HEAD request), and `:command_runner` (the 3-arity command
  runner used by that default probe; tests inject it to avoid HTTP).
  """
  # @spec OAUTH-CF-2
  # @spec OAUTH-CF-5
  # @spec OAUTH-CF-6
  def run(opts \\ []) do
    runtime_file = Keyword.get(opts, :runtime_file, @default_runtime)
    work_dir = Keyword.get_lazy(opts, :work_dir, &fresh_work_dir/0)
    command_runner = Keyword.get(opts, :command_runner, &System.cmd/3)
    probe = Keyword.get(opts, :probe, &default_probe(&1, command_runner))
    File.mkdir_p!(work_dir)

    results = %{
      runtime_file: runtime_file,
      work_dir: work_dir,
      setup: :ok,
      supported: [],
      unsupported: unsupported_cases(),
      suite: Keyword.get(opts, :suite, :not_configured),
      plan_path: nil
    }

    case setup(runtime_file) do
      {:ok, mod, models} ->
        attach_plan(%{results | supported: run_supported(mod, models)}, probe)

      {:error, detail} ->
        attach_plan(%{results | setup: {:error, detail}}, probe)
    end
  end

  @doc """
  0 when setup succeeded, every supported case passes at both layers,
  and the suite target (when configured) is usable; 1 otherwise.
  """
  # @spec OAUTH-CF-3
  # @spec OAUTH-CF-6
  def exit_code(results) do
    setup_ok? = match?(:ok, results.setup)
    suite_ok? = not match?({:error, _detail}, results.suite)
    checks = [setup_ok?, suite_ok? | Enum.map(results.supported, &pass?/1)]

    if Enum.all?(checks), do: 0, else: 1
  end

  @doc """
  One line per case plus header, suite, and summary lines. Supported
  cases print `pass` or `FAIL` with the failing detail; unsupported
  cases print their documented reason.
  """
  # @spec OAUTH-CF-3
  def report(results) do
    header =
      "OAuth conformance harness: #{length(results.supported)} supported case(s), " <>
        "#{length(results.unsupported)} documented as unsupported"

    body =
      case results.setup do
        :ok ->
          supported = Enum.map(results.supported, &supported_line/1)
          unsupported = Enum.map(results.unsupported, &unsupported_line/1)
          supported ++ unsupported

        {:error, detail} ->
          ["setup error: #{detail} — no cases were run"]
      end

    lines = [header] ++ body ++ [suite_line(results), summary(results)]
    Enum.join(lines, "\n") <> "\n"
  end

  # ── setup: verified models plus the compiled runtime ────────────────

  defp setup(runtime_file) do
    with :ok <- verify_models(),
         {:ok, models} <- parse_models(),
         {:ok, mod} <- compile_runtime(runtime_file) do
      {:ok, mod, models}
    end
  end

  # The conformance story rests on the models holding their invariants,
  # so they are verified exactly the way CI verifies them before any
  # case runs; a model that stopped holding fails the whole run for
  # that reason instead of producing confusing disagreements.
  defp verify_models do
    Enum.reduce_while(@default_models, :ok, fn path, :ok ->
      case Verify.verify_file(path) do
        {:ok, _result} ->
          {:cont, :ok}

        {:error, %Verify.Failure{} = failure} ->
          {:halt, {:error, Verify.Failure.format(failure)}}

        {:error, error} ->
          {:halt, {:error, format_error(error)}}
      end
    end)
  end

  defp parse_models do
    parse_models(@default_models, [])
  end

  defp parse_models([], models), do: {:ok, Enum.reverse(models)}

  defp parse_models([path | rest], models) do
    with {:ok, source} <- read_source(path),
         {:ok, program} <- Yup.Parser.parse(source, path: path) do
      parse_models(rest, [hd(program.models) | models])
    else
      {:error, error} -> {:error, format_error(error)}
    end
  end

  defp compile_runtime(path) do
    with {:ok, source} <- read_source(path),
         {:ok, program} <- Yup.Parser.parse(source, path: path),
         {:ok, module} <- Yup.Compiler.compile(program) do
      {:ok, module}
    else
      {:error, error} -> {:error, format_error(error)}
    end
  end

  # File.read/1 fails with a bare posix atom (:enoent); wrapping it in
  # File.Error lets format_error/1 report the path, not just the atom.
  defp read_source(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, %File.Error{action: "read", path: path, reason: reason}}
    end
  end

  # ── case execution ──────────────────────────────────────────────────

  defp run_supported(mod, models) do
    cases = Enum.filter(Cases.all(), &Cases.supported?/1)
    Enum.map(cases, &run_case(&1, mod, models))
  end

  # Each case is an independent scenario: a fresh trace session (the
  # models start at their initial states) and a fresh server (one
  # registered client, one empty grant slot).
  defp run_case(test_case, mod, models) do
    case Trace.new(models) do
      {:ok, session} ->
        state = %{
          mod: mod,
          server: mod.new_server(Cases.client_id(), Cases.redirect_uri()),
          granted: nil,
          session: session
        }

        test_case
        |> Map.take([:id, :title, :source])
        |> Map.merge(run_steps(test_case.steps, state, 1))

      {:error, disagreement} ->
        test_case
        |> Map.take([:id, :title, :source])
        |> Map.merge(%{
          protocol: :pass,
          models: {:disagree, Trace.Disagreement.format(disagreement)}
        })
    end
  end

  # A case passes when every step's outcome matches its RFC-derived
  # expectation and its mapped event conforms to the models. On a
  # protocol failure the failing event is still checked against the
  # models, so a case that also contradicts a model reports both.
  # @spec OAUTH-CF-2
  defp run_steps([], _state, _index), do: %{protocol: :pass, models: :conform}

  defp run_steps([{kind, fields, expect} | rest], state, index) do
    {outcome, event} = execute({kind, fields, expect}, state)

    case expectation(expect, outcome, fields, state.mod) do
      :ok ->
        step_event(event, rest, state, index, outcome)

      {:error, detail} ->
        failure = "step #{index} (#{kind}): " <> detail
        %{protocol: {:fail, failure}, models: model_verdict(event, state)}
    end
  end

  defp step_event(event, rest, state, index, outcome) do
    case Trace.event(state.session, event) do
      {:ok, session} ->
        run_steps(rest, %{advance(state, outcome) | session: session}, index + 1)

      {:error, disagreement} ->
        %{protocol: :pass, models: {:disagree, Trace.Disagreement.format(disagreement)}}
    end
  end

  defp execute({:authorize, fields, _expect}, state) do
    challenge = state.mod.derive(fields.verifier)

    outcome = state.mod.issue(state.server, fields.client_id, fields.redirect_uri, challenge)

    {outcome, Mapping.issue(outcome)}
  end

  defp execute({:token, fields, _expect}, state) do
    mod = state.mod
    server = if state.granted, do: state.granted, else: state.server
    code = resolve_code(fields.code, state)
    outcome = mod.redeem(server, code, fields.redirect_uri, fields.verifier)
    event = Mapping.redeem(server, code, fields.verifier, outcome, &mod.derive/1)
    {outcome, event}
  end

  defp resolve_code(:last_issued, state), do: state.granted.grant.code
  defp resolve_code(code, _state) when is_binary(code), do: code

  defp advance(state, {:Ok, granted}), do: %{state | granted: granted}
  defp advance(state, {:Redeemed, server, _token}), do: %{state | granted: server}
  defp advance(state, _outcome), do: state

  defp model_verdict(event, state) do
    case Trace.event(state.session, event) do
      {:ok, _session} -> :conform
      {:error, disagreement} -> {:disagree, Trace.Disagreement.format(disagreement)}
    end
  end

  # ── RFC-derived expectations ────────────────────────────────────────

  defp expectation(:code_issued, {:Ok, granted}, fields, mod) do
    challenge = granted.grant.challenge

    cond do
      granted.grant.code == "" ->
        {:error, "issued an empty code"}

      challenge != mod.derive(fields.verifier) ->
        {:error, "stored challenge is not derived from the submitted verifier"}

      challenge == fields.verifier ->
        {:error, "stored the raw verifier instead of a derived challenge"}

      true ->
        :ok
    end
  end

  defp expectation(:code_issued, outcome, _fields, _mod) do
    {:error, "expected an issued code but the endpoint " <> outcome_text(outcome)}
  end

  defp expectation(:token_issued, {:Redeemed, _server, token}, _fields, _mod) do
    if token != "", do: :ok, else: {:error, "issued an empty token"}
  end

  defp expectation(:token_issued, outcome, _fields, _mod) do
    {:error, "expected an issued token but the endpoint " <> outcome_text(outcome)}
  end

  defp expectation({:refused, contains}, {:Error, reason}, _fields, _mod) do
    if reason =~ contains do
      :ok
    else
      {:error, "expected refusal \"#{contains}\" but the endpoint refused \"#{reason}\""}
    end
  end

  defp expectation({:refused, contains}, outcome, _fields, _mod) do
    {:error, "expected refusal \"#{contains}\" but the endpoint " <> outcome_text(outcome)}
  end

  defp outcome_text({:Ok, _server}), do: "issued a code"
  defp outcome_text({:Error, reason}), do: "refused \"#{reason}\""
  defp outcome_text({:Redeemed, _server, token}), do: "issued token \"#{token}\""

  # ── the external-suite plan ─────────────────────────────────────────

  defp attach_plan(%{suite: :not_configured} = results, _probe), do: results

  defp attach_plan(results, probe) do
    case describe_suite(results.suite, probe) do
      {:ok, suite} ->
        plan_path = Path.join(results.work_dir, "plan.json")
        File.write!(plan_path, json(plan(results, suite)) <> "\n")
        %{results | suite: suite, plan_path: plan_path}

      {:error, detail} ->
        %{results | suite: {:error, detail}}
    end
  end

  # A path target must be an existing directory and a URL target must
  # be reachable: a typo in YUP_OIDF_SUITE is a configuration error,
  # not a skip (OAUTH-CF-6). For URLs, the probe (defaulting to a HEAD
  # request via curl) is the reachability check, so an unreachable
  # target fails the run instead of producing a `plan.json` for a suite
  # no one can ever talk to.
  defp describe_suite(%{kind: :url} = suite, probe) do
    case probe.(suite.target) do
      :ok ->
        {:ok, %{kind: :url, target: suite.target, label: suite.target, commit: nil}}

      {:error, detail} ->
        {:error, detail}
    end
  end

  defp describe_suite(%{kind: :path, target: target}, _probe) do
    if File.dir?(target) do
      abs = Path.absname(target)
      commit = git_commit(target)
      label = if commit, do: abs <> " @ " <> commit, else: abs
      {:ok, %{kind: :path, target: abs, label: label, commit: commit}}
    else
      {:error, "YUP_OIDF_SUITE names #{target}, which is not a directory"}
    end
  end

  # The commit is optional pinning evidence: a checkout without git
  # metadata (or a machine without git) pins the path alone. The
  # top-level guard matters because rev-parse from a plain directory
  # reports the nearest *enclosing* repository: only a checkout that is
  # itself a repo's top level pins that repo's commit (OAUTH-CF-5).
  defp git_commit(dir) do
    case System.cmd("git", ["-C", dir, "rev-parse", "--show-toplevel", "HEAD"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        [top, commit] = output |> String.trim() |> String.split("\n")
        if top == Path.absname(dir), do: commit, else: nil

      {_output, _status} ->
        nil
    end
  rescue
    _error -> nil
  end

  # The default reachability probe: a HEAD request with a short timeout
  # and `--fail`, so DNS failure, connection refused, timeout, TLS
  # error, and any HTTP >= 400 are all treated as unreachable — the
  # exact failure mode does not matter, only that the suite can be
  # talked to and answers success. Missing curl is also unreachable,
  # since the harness has no other way to verify the deployment.
  defp default_probe(url, command_runner) do
    case command_runner.(
           "curl",
           ["--silent", "--fail", "--head", "--max-time", "5", url],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {_output, _status} -> {:error, "YUP_OIDF_SUITE names #{url}, which is not reachable"}
    end
  rescue
    _error -> {:error, "YUP_OIDF_SUITE names #{url}, which is not reachable"}
  end

  defp plan(results, suite) do
    %{
      "harness" => "yup oauth-conformance (issue #24)",
      "suite" => %{
        "kind" => Atom.to_string(suite.kind),
        "target" => suite.target,
        "git_commit" => suite.commit
      },
      "runtime" => %{
        "file" => results.runtime_file,
        "shape" => "compiled YupYup functions; no HTTP endpoints"
      },
      "deployment_shape" => %{
        "issuer" => "none (in-process runtime slice)",
        "authorization_request" => "issue(server, client_id, redirect_uri, challenge)",
        "token_request" => "redeem(server, code, redirect_uri, verifier)",
        "grant_types" => ["authorization_code"],
        "code_challenge_method" => "S256, abstracted as derive(verifier) = s256: + verifier",
        "registered_client" => %{
          "client_id" => Cases.client_id(),
          "redirect_uri" => Cases.redirect_uri()
        }
      },
      # Manifest-derived, not run-derived: on a setup error no case ran,
      # but the plan must still record every case's support status
      # (OAUTH-CF-5). Map.take drops the struct's nil :reason so
      # plan_entry/1 does not emit "reason": null for supported cases.
      "supported" =>
        Cases.all()
        |> Enum.filter(&Cases.supported?/1)
        |> Enum.map(&Map.take(&1, [:id, :title, :source]))
        |> Enum.map(&plan_entry/1),
      "unsupported" => Enum.map(results.unsupported, &plan_entry/1)
    }
  end

  defp plan_entry(entry) do
    base = %{"id" => entry.id, "title" => entry.title, "source" => entry.source}

    case entry do
      %{reason: reason} -> Map.put(base, "reason", reason)
      _other -> base
    end
  end

  # The plan is flat string/list/map data, so a minimal deterministic
  # encoder (sorted keys, byte-stable output) avoids a JSON dependency;
  # stability is what lets a suite commit plus plan bytes serve as
  # pinned evidence of a manual run.
  defp json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, val} -> json(key) <> ": " <> json(val) end)
      |> Enum.sort()
      |> Enum.join(", ")

    "{" <> entries <> "}"
  end

  defp json(values) when is_list(values) do
    "[" <> Enum.map_join(values, ", ", &json/1) <> "]"
  end

  defp json(nil), do: "null"

  defp json(value) when is_binary(value) do
    escaped = String.replace(value, "\\", "\\\\")
    "\"" <> String.replace(escaped, "\"", "\\\"") <> "\""
  end

  # ── reporting ───────────────────────────────────────────────────────

  defp supported_line(%{protocol: :pass, models: :conform} = result) do
    "  pass        #{result.id} (#{result.source}): protocol ok, models conform"
  end

  # @spec OAUTH-CF-3
  defp supported_line(result) do
    "  FAIL        #{result.id} (#{result.source}): #{fail_detail(result)}"
  end

  defp fail_detail(%{protocol: {:fail, detail}, models: models}) do
    detail <> "; models: " <> models_text(models)
  end

  defp fail_detail(%{protocol: :pass, models: {:disagree, detail}}) do
    "protocol ok; models: " <> detail
  end

  defp models_text(:conform), do: "conform"
  defp models_text({:disagree, detail}), do: detail

  defp unsupported_line(result) do
    "  unsupported #{result.id} (#{result.source}): #{result.reason}"
  end

  defp suite_line(%{suite: :not_configured}) do
    "external suite: not configured (set YUP_OIDF_SUITE to a suite deployment URL " <>
      "or checkout); plan not written"
  end

  defp suite_line(%{suite: {:error, detail}}) do
    "external suite error: #{detail}"
  end

  defp suite_line(%{suite: suite, plan_path: plan_path}) do
    "external suite: plan written to #{plan_path} for #{suite.label}"
  end

  defp summary(%{setup: {:error, _detail}}) do
    "OAuth conformance harness: setup failed; no cases run"
  end

  defp summary(results) do
    passing = Enum.count(results.supported, &pass?/1)
    "OAuth conformance harness: #{passing}/#{length(results.supported)} supported cases pass"
  end

  defp pass?(%{protocol: :pass, models: :conform}), do: true
  defp pass?(_result), do: false

  # ── small helpers ───────────────────────────────────────────────────

  defp runtime_file([]), do: @default_runtime
  defp runtime_file([file | _rest]), do: file

  defp suite_from_env do
    case find_suite() do
      {:ok, suite} -> suite
      :error -> :not_configured
    end
  end

  defp unsupported_cases do
    Cases.all()
    |> Enum.reject(&Cases.supported?/1)
    |> Enum.map(&Map.take(&1, [:id, :title, :source, :reason]))
  end

  defp fresh_work_dir do
    unique = System.unique_integer([:positive])
    Path.join(System.tmp_dir!(), "yup-oauth-conformance-#{unique}")
  end

  defp format_error(%SourceError{} = error), do: SourceError.format(error)
  defp format_error(%File.Error{} = error), do: Exception.message(error)
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end
