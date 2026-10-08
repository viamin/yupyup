defmodule Yup.Conformance.OAuthTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Yup.Conformance.OAuth
  alias Yup.Conformance.OAuth.Cases

  @script Path.expand("bin/oauth-conformance", File.cwd!())
  @language_docs Path.expand("docs/LANGUAGE.md", File.cwd!())
  @broken_path "examples/broken_oauth_runtime.yup"

  @supported_ids [
    "authorization-code-issued",
    "authorization-redirect-exact-match",
    "authorization-unregistered-client",
    "token-exchange-valid-verifier",
    "token-exchange-wrong-verifier",
    "authorization-code-single-use",
    "token-endpoint-redirect-binding",
    "token-unknown-code-refused"
  ]

  @unsupported_ids [
    "provider-metadata-discovery",
    "oidc-id-token",
    "pkce-s256-test-vectors",
    "token-response-error-codes",
    "token-expiry-and-refresh",
    "client-authentication",
    "scope-handling-and-consent",
    "https-and-tls-profile",
    "fapi-security-profile",
    "dynamic-client-registration"
  ]

  @all_ids @supported_ids ++ @unsupported_ids

  # ── the manifest is the harness configuration ───────────────────────

  describe "the manifest" do
    # @spec OAUTH-CF-4
    test "is the pinned list of supported and unsupported cases" do
      cases = Cases.all()

      assert Enum.map(cases, & &1.id) == @all_ids
      assert Enum.count(cases, &Cases.supported?/1) == length(@supported_ids)

      assert Enum.count(cases, fn test_case -> not Cases.supported?(test_case) end) ==
               length(@unsupported_ids)
    end

    # @spec OAUTH-CF-4
    test "supported cases carry protocol-shaped steps and unsupported cases carry reasons" do
      for test_case <- Cases.all(), Cases.supported?(test_case) do
        assert test_case.steps != []
        assert Enum.all?(test_case.steps, &step?/1)
        assert test_case.reason == nil
      end

      for test_case <- Cases.all(), not Cases.supported?(test_case) do
        assert is_binary(test_case.reason) and test_case.reason != ""
        assert test_case.steps == []
      end
    end

    # @spec OAUTH-CF-4
    test "documents every case and its support status in the language docs" do
      {:ok, docs} = File.read(@language_docs)

      for test_case <- Cases.all() do
        assert docs =~ test_case.id
        assert docs =~ test_case.title
      end
    end
  end

  # ── external suite discovery ────────────────────────────────────────

  describe "find_suite/1" do
    # @spec OAUTH-CF-1
    test "reports the suite missing when YUP_OIDF_SUITE is unset or blank" do
      assert :error = OAuth.find_suite(%{"YUP_OIDF_SUITE" => nil})
      assert :error = OAuth.find_suite(%{"YUP_OIDF_SUITE" => "   "})
    end

    # @spec OAUTH-CF-5
    test "classifies an http(s) target as a deployment url" do
      suite = "https://www.certification.openid.net"

      assert {:ok, %{kind: :url, target: ^suite}} =
               OAuth.find_suite(%{"YUP_OIDF_SUITE" => suite})
    end

    # @spec OAUTH-CF-5
    test "classifies anything else as a checkout path" do
      assert {:ok, %{kind: :path, target: "/opt/conformance-suite"}} =
               OAuth.find_suite(%{"YUP_OIDF_SUITE" => "/opt/conformance-suite"})
    end
  end

  # ── the good runtime conforms at both layers ────────────────────────

  describe "run/1 against the good runtime" do
    # @spec OAUTH-CF-2
    @tag :tmp_dir
    test "passes every supported case in protocol and against the models", %{tmp_dir: tmp_dir} do
      results = OAuth.run(work_dir: tmp_dir)

      assert results.setup == :ok
      assert results.suite == :not_configured
      assert results.plan_path == nil
      assert results.supported != []

      for result <- results.supported do
        assert result.protocol == :pass, "#{result.id}: #{inspect(result.protocol)}"
        assert result.models == :conform, "#{result.id}: #{inspect(result.models)}"
      end

      assert Enum.map(results.unsupported, & &1.id) == @unsupported_ids
      assert OAuth.exit_code(results) == 0

      count = length(results.supported)
      assert OAuth.report(results) =~ "#{count}/#{count} supported cases pass"
    end
  end

  # ── the broken runtime fails loudly ─────────────────────────────────

  describe "run/1 against the broken runtime" do
    # @spec OAUTH-CF-3
    @tag :tmp_dir
    test "fails the cases the broken rules break, at both layers", %{tmp_dir: tmp_dir} do
      results = OAuth.run(runtime_file: @broken_path, work_dir: tmp_dir)

      assert results.setup == :ok
      assert OAuth.exit_code(results) == 1

      by_id = Map.new(results.supported, fn result -> {result.id, result} end)

      wrong = Map.fetch!(by_id, "token-exchange-wrong-verifier")
      assert {:fail, detail} = wrong.protocol
      assert detail =~ "step 2 (token)"
      assert detail =~ "verifier mismatch"

      assert {:disagree, disagreement} = wrong.models
      assert disagreement =~ "token_issued"

      reuse = Map.fetch!(by_id, "authorization-code-single-use")
      assert {:fail, reuse_detail} = reuse.protocol
      assert reuse_detail =~ "already redeemed"

      assert {:disagree, reuse_disagreement} = reuse.models
      assert reuse_disagreement =~ "redemptions"

      unknown = Map.fetch!(by_id, "token-unknown-code-refused")
      assert {:fail, unknown_detail} = unknown.protocol
      assert unknown_detail =~ "unknown code"

      report = OAuth.report(results)
      assert report =~ "FAIL"
      assert report =~ "token-exchange-wrong-verifier"
      assert report =~ "unsupported"
    end

    # @spec OAUTH-CF-3
    @tag :tmp_dir
    test "still reports the documented unsupported cases", %{tmp_dir: tmp_dir} do
      results = OAuth.run(runtime_file: @broken_path, work_dir: tmp_dir)

      assert Enum.map(results.unsupported, & &1.id) == @unsupported_ids
      assert Enum.all?(results.unsupported, fn entry -> entry.reason != "" end)
    end
  end

  # ── setup and configuration errors ──────────────────────────────────

  describe "setup and suite configuration errors" do
    # @spec OAUTH-CF-6
    @tag :tmp_dir
    test "an unreadable runtime file is a setup error, not a case pass", %{tmp_dir: tmp_dir} do
      results = OAuth.run(runtime_file: "nope.yup", work_dir: tmp_dir)

      assert {:error, detail} = results.setup
      assert detail =~ "nope.yup"
      assert results.supported == []
      assert OAuth.exit_code(results) == 1
      assert OAuth.report(results) =~ "setup error"
    end

    # @spec OAUTH-CF-6
    @tag :tmp_dir
    test "a suite path that does not exist is a configuration error", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "no-such-suite")

      results = OAuth.run(work_dir: tmp_dir, suite: %{kind: :path, target: missing})

      assert {:error, detail} = results.suite
      assert detail =~ "no-such-suite"
      assert results.plan_path == nil
      assert OAuth.exit_code(results) == 1
      assert OAuth.report(results) =~ "external suite error"
    end
  end

  # ── the external-suite plan ─────────────────────────────────────────

  describe "the plan hand-off" do
    # @spec OAUTH-CF-5
    @tag :tmp_dir
    test "writes a byte-stable plan.json for a deployment url", %{tmp_dir: tmp_dir} do
      suite = %{kind: :url, target: "https://www.certification.openid.net"}

      results = OAuth.run(work_dir: tmp_dir, suite: suite)

      assert results.plan_path == Path.join(tmp_dir, "plan.json")

      plan = File.read!(results.plan_path)
      assert plan =~ "\"harness\""
      assert plan =~ "https://www.certification.openid.net"
      assert plan =~ "authorization-code-issued"
      assert plan =~ "pkce-s256-test-vectors"
      assert plan =~ "\"reason\""

      assert OAuth.exit_code(results) == 0
      assert OAuth.report(results) =~ "plan written to"

      again = OAuth.run(work_dir: Path.join(tmp_dir, "again"), suite: suite)
      assert File.read!(again.plan_path) == plan
    end

    # @spec OAUTH-CF-5
    @tag :tmp_dir
    test "pins a checkout path in the plan", %{tmp_dir: tmp_dir} do
      checkout = Path.join(tmp_dir, "conformance-suite")
      File.mkdir_p!(checkout)

      suite = %{kind: :path, target: checkout}
      results = OAuth.run(work_dir: Path.join(tmp_dir, "work"), suite: suite)

      assert results.plan_path != nil
      assert File.read!(results.plan_path) =~ Path.absname(checkout)
      assert results.suite.label =~ Path.absname(checkout)
    end
  end

  # ── the wrapper script ──────────────────────────────────────────────

  describe "bin/oauth-conformance" do
    # @spec OAUTH-CF-1
    test "runs the local subset and notes the external suite skip" do
      assert {output, 0} =
               System.cmd(@script, [],
                 env: %{"YUP_OIDF_SUITE" => nil, "MIX_ENV" => "test"},
                 stderr_to_stdout: true
               )

      assert output =~ "supported cases pass"
      assert output =~ "not configured"
      assert output =~ "YUP_OIDF_SUITE"
      assert output =~ "unsupported"
    end

    # @spec OAUTH-CF-5
    @tag :tmp_dir
    test "writes the plan when YUP_OIDF_SUITE names a checkout", %{tmp_dir: tmp_dir} do
      assert {output, 0} =
               System.cmd(@script, [],
                 env: %{"YUP_OIDF_SUITE" => tmp_dir, "MIX_ENV" => "test"},
                 stderr_to_stdout: true
               )

      assert output =~ "plan written to"
      assert output =~ "plan.json"
    end

    # @spec OAUTH-CF-3
    test "fails loudly against the broken runtime" do
      assert {output, 1} =
               System.cmd(@script, [@broken_path],
                 env: %{"YUP_OIDF_SUITE" => nil, "MIX_ENV" => "test"},
                 stderr_to_stdout: true
               )

      assert output =~ "FAIL"
      assert output =~ "token-exchange-wrong-verifier"
    end
  end

  defp step?({:authorize, fields, expect}) do
    fields?(fields, [:client_id, :redirect_uri, :verifier]) and expect?(expect)
  end

  defp step?({:token, fields, expect}) do
    fields?(fields, [:code, :redirect_uri, :verifier]) and expect?(expect)
  end

  defp step?(_other), do: false

  defp fields?(fields, keys) do
    is_map(fields) and Enum.sort(Map.keys(fields)) == Enum.sort(keys)
  end

  defp expect?(:code_issued), do: true
  defp expect?(:token_issued), do: true

  defp expect?({:refused, contains}) when is_binary(contains), do: true
  defp expect?(_other), do: false
end
