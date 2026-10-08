defmodule Yup.OAuthTraceTest do
  @moduledoc false

  use ExUnit.Case

  alias Yup.OAuthTrace, as: Mapping
  alias Yup.Verify.Trace
  alias Yup.Verify.Trace.Event

  @runtime_path Path.expand("examples/oauth_runtime.yup", File.cwd!())
  @broken_path Path.expand("examples/broken_oauth_runtime.yup", File.cwd!())
  @auth_code_path Path.expand("examples/auth_code.yup", File.cwd!())
  @pkce_path Path.expand("examples/pkce_exchange.yup", File.cwd!())
  @client_id "toy-client"
  @redirect_uri "https://app.example/cb"
  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  setup_all do
    # The models under conformance are verified first, exactly the way CI
    # verifies them, so a model that stopped holding its invariants fails
    # here for that reason instead of producing confusing disagreements.
    assert {:ok, _} = Yup.Verify.verify_file(@auth_code_path)
    assert {:ok, _} = Yup.Verify.verify_file(@pkce_path)

    models =
      for path <- [@auth_code_path, @pkce_path] do
        {:ok, source} = File.read(path)
        {:ok, program} = Yup.Parser.parse(source, path: path)
        hd(program.models)
      end

    {:ok, mod} = compile(@runtime_path)
    {:ok, broken} = compile(@broken_path)

    %{mod: mod, broken: broken, models: models}
  end

  setup %{models: models} do
    {:ok, session} = Trace.new(models)
    %{session: session}
  end

  defp compile(path) do
    {:ok, source} = File.read(path)
    {:ok, program} = Yup.Parser.parse(source, path: path)
    Yup.Compiler.compile(program)
  end

  defp authorize(mod, server) do
    {:Ok, granted} = mod.issue(server, @client_id, @redirect_uri, mod.derive(@verifier))
    granted
  end

  defp conform!(session, event) do
    assert {:ok, session} = Trace.event(session, event)
    session
  end

  defp mapped_redeem(mod, server, code, verifier, result) do
    Mapping.redeem(server, code, verifier, result, &mod.derive/1)
  end

  # ── the explicit event mapping ──────────────────────────────────────

  describe "event mapping" do
    # @spec OAUTH-TC-1
    test "a successful issue maps to AuthCode's issue transition" do
      assert Mapping.issue({:Ok, :granted}) == %Event{
               label: "issue: code issued",
               steps: [{"AuthCode", "issue"}],
               claims: [{"AuthCode", {:equals, :issued, true}}]
             }
    end

    # @spec OAUTH-TC-2
    test "a refused issue stutters because registration is unmodeled" do
      assert Mapping.issue({:Error, "unregistered client or redirect uri"}) == %Event{
               label: "issue: refused",
               steps: [],
               claims: [{"AuthCode", {:unchanged, :issued}}]
             }
    end

    # @spec OAUTH-TC-1
    test "a successful matching-verifier redeem maps to both success transitions", %{
      mod: mod
    } do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      result = mod.redeem(granted, granted.grant.code, @redirect_uri, @verifier)

      assert mapped_redeem(mod, granted, granted.grant.code, @verifier, result) == %Event{
               label: "redeem: verifier matched, token issued",
               steps: [
                 {"AuthCode", "redeem"},
                 {"PkceExchange", "submit_valid_verifier"}
               ],
               claims: [
                 {"AuthCode", {:increments, :redemptions}},
                 {"PkceExchange", {:equals, :token_issued, true}}
               ]
             }
    end

    # @spec OAUTH-TC-2
    test "a wrong-verifier refusal maps to the model's invalid submission", %{mod: mod} do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      code = granted.grant.code
      {:Error, "verifier mismatch"} = result = mod.redeem(granted, code, @redirect_uri, "wrong")

      assert mapped_redeem(mod, granted, code, "wrong", result) == %Event{
               label: "redeem: verifier mismatched, refused",
               steps: [{"PkceExchange", "submit_invalid_verifier"}],
               claims: [
                 {"PkceExchange", {:equals, :token_issued, false}},
                 {"AuthCode", {:unchanged, :redemptions}}
               ]
             }
    end

    # @spec OAUTH-TC-2
    test "a reuse refusal maps to AuthCode's guarded redeem", %{mod: mod} do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      code = granted.grant.code
      {:Redeemed, _, _} = mod.redeem(granted, code, @redirect_uri, @verifier)

      {:Error, "code already redeemed"} =
        result = mod.redeem(granted, code, @redirect_uri, @verifier)

      assert mapped_redeem(mod, granted, code, @verifier, result) == %Event{
               label: "redeem: code already redeemed, refused",
               steps: [{"AuthCode", "redeem"}],
               claims: [
                 {"AuthCode", {:unchanged, :redemptions}},
                 {"PkceExchange", {:unchanged, :token_issued}}
               ]
             }
    end

    # @spec OAUTH-TC-2
    test "a reuse refusal takes precedence over a wrong verifier", %{mod: mod} do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      code = granted.grant.code
      {:Redeemed, _, _} = mod.redeem(granted, code, @redirect_uri, @verifier)

      {:Error, "code already redeemed"} =
        result = mod.redeem(granted, code, @redirect_uri, "wrong")

      assert mapped_redeem(mod, granted, code, "wrong", result) == %Event{
               label: "redeem: code already redeemed, refused",
               steps: [{"AuthCode", "redeem"}],
               claims: [
                 {"AuthCode", {:unchanged, :redemptions}},
                 {"PkceExchange", {:unchanged, :token_issued}}
               ]
             }
    end

    # @spec OAUTH-TC-2
    test "a redirect-mismatch refusal stutters because redirects are unmodeled", %{mod: mod} do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      code = granted.grant.code

      {:Error, "redirect uri mismatch"} =
        result = mod.redeem(granted, code, "https://evil.example/cb", @verifier)

      assert mapped_redeem(mod, granted, code, @verifier, result) == %Event{
               label: "redeem: verifier matched, refused",
               steps: [],
               claims: [
                 {"AuthCode", {:unchanged, :redemptions}},
                 {"PkceExchange", {:unchanged, :token_issued}}
               ]
             }
    end

    # @spec OAUTH-TC-2
    test "an unknown-code refusal stutters", %{mod: mod} do
      server = mod.new_server(@client_id, @redirect_uri)

      {:Error, "unknown code"} =
        result = mod.redeem(server, "ac-never-issued", @redirect_uri, @verifier)

      assert mapped_redeem(mod, server, "ac-never-issued", @verifier, result) == %Event{
               label: "redeem: unknown code, refused",
               steps: [],
               claims: [
                 {"AuthCode", {:unchanged, :redemptions}},
                 {"PkceExchange", {:unchanged, :token_issued}}
               ]
             }
    end

    # @spec OAUTH-TC-3
    test "the same wrong-verifier inputs map differently when a token is minted", %{
      mod: mod
    } do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))

      minted = {:Redeemed, granted, "at-forged"}

      assert mapped_redeem(mod, granted, granted.grant.code, "wrong", minted) == %Event{
               label: "redeem: verifier mismatched, token issued",
               steps: [
                 {"AuthCode", "redeem"},
                 {"PkceExchange", "submit_invalid_verifier"}
               ],
               claims: [
                 {"AuthCode", {:increments, :redemptions}},
                 {"PkceExchange", {:equals, :token_issued, true}}
               ]
             }
    end

    # @spec OAUTH-TC-3
    test "a minted token for an unknown code maps to an attempted redemption" do
      server = %{grant: %{code: "", challenge: "s256:none"}}
      minted = {:Redeemed, server, "at-forged"}

      assert Mapping.redeem(server, "ac-ghost", @verifier, minted, fn v -> "s256:" <> v end) ==
               %Event{
                 label: "redeem: unknown code, token issued",
                 steps: [
                   {"AuthCode", "redeem"},
                   {"PkceExchange", "submit_valid_verifier"}
                 ],
                 claims: [
                   {"AuthCode", {:increments, :redemptions}},
                   {"PkceExchange", {:equals, :token_issued, true}}
                 ]
               }
    end
  end

  # ── the good runtime conforms ───────────────────────────────────────

  describe "conformance" do
    # @spec OAUTH-TC-4
    test "the runtime's transcript conforms event by event", %{mod: mod, session: session} do
      server = mod.new_server(@client_id, @redirect_uri)

      refused_issue =
        mod.issue(server, @client_id, "https://evil.example/cb", mod.derive(@verifier))

      session = conform!(session, Mapping.issue(refused_issue))

      {:Ok, granted} =
        result = mod.issue(server, @client_id, @redirect_uri, mod.derive(@verifier))

      session = conform!(session, Mapping.issue(result))
      code = granted.grant.code

      {:Error, "verifier mismatch"} = wrong = mod.redeem(granted, code, @redirect_uri, "wrong")
      session = conform!(session, mapped_redeem(mod, granted, code, "wrong", wrong))

      {:Error, "redirect uri mismatch"} =
        mismatch = mod.redeem(granted, code, "https://evil.example/cb", @verifier)

      session = conform!(session, mapped_redeem(mod, granted, code, @verifier, mismatch))

      {:Redeemed, _, _} = exchanged = mod.redeem(granted, code, @redirect_uri, @verifier)
      session = conform!(session, mapped_redeem(mod, granted, code, @verifier, exchanged))

      {:Error, "code already redeemed"} =
        replay = mod.redeem(granted, code, @redirect_uri, @verifier)

      session = conform!(session, mapped_redeem(mod, granted, code, @verifier, replay))

      assert Trace.state(session, "AuthCode") == %{issued: true, redemptions: 1}

      assert Trace.state(session, "PkceExchange") == %{
               challenge: :known,
               verifier: :matching,
               token_issued: true
             }

      assert Trace.labels(session) == [
               "issue: refused",
               "issue: code issued",
               "redeem: verifier mismatched, refused",
               "redeem: verifier matched, refused",
               "redeem: verifier matched, token issued",
               "redeem: code already redeemed, refused"
             ]
    end

    # @spec OAUTH-TC-4
    test "an unknown-code refusal conforms as a stuttering step", %{mod: mod, session: session} do
      server = mod.new_server(@client_id, @redirect_uri)

      {:Error, "unknown code"} =
        result = mod.redeem(server, "ac-never-issued", @redirect_uri, @verifier)

      session =
        conform!(session, mapped_redeem(mod, server, "ac-never-issued", @verifier, result))

      assert Trace.state(session, "AuthCode") == %{issued: false, redemptions: 0}

      assert Trace.state(session, "PkceExchange") == %{
               challenge: :known,
               verifier: :unknown,
               token_issued: false
             }
    end

    # @spec OAUTH-TC-4
    test "a wrong-verifier refusal leaves the exchange conforming afterwards", %{
      mod: mod,
      session: session
    } do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      session = conform!(session, Mapping.issue({:Ok, granted}))
      code = granted.grant.code

      {:Error, "verifier mismatch"} = wrong = mod.redeem(granted, code, @redirect_uri, "wrong")
      session = conform!(session, mapped_redeem(mod, granted, code, "wrong", wrong))

      {:Redeemed, _, _} = exchanged = mod.redeem(granted, code, @redirect_uri, @verifier)
      conform!(session, mapped_redeem(mod, granted, code, @verifier, exchanged))
    end

    # @spec OAUTH-TC-2
    test "a wrong-verifier replay preserves an already-issued token", %{
      mod: mod,
      session: session
    } do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      session = conform!(session, Mapping.issue({:Ok, granted}))
      code = granted.grant.code

      {:Redeemed, _, _} = exchanged = mod.redeem(granted, code, @redirect_uri, @verifier)
      session = conform!(session, mapped_redeem(mod, granted, code, @verifier, exchanged))

      {:Error, "code already redeemed"} =
        replay = mod.redeem(granted, code, @redirect_uri, "wrong")

      session = conform!(session, mapped_redeem(mod, granted, code, "wrong", replay))

      assert Trace.state(session, "AuthCode") == %{issued: true, redemptions: 1}

      assert Trace.state(session, "PkceExchange") == %{
               challenge: :known,
               verifier: :matching,
               token_issued: true
             }
    end
  end

  # ── the broken runtime disagrees ────────────────────────────────────

  describe "disagreement" do
    # @spec OAUTH-TC-6
    test "a wrong-verifier mint disagrees on PkceExchange token_issued", %{
      broken: broken,
      session: session
    } do
      granted = authorize(broken, broken.new_server(@client_id, @redirect_uri))
      session = conform!(session, Mapping.issue({:Ok, granted}))
      code = granted.grant.code

      assert {:Redeemed, _, _} =
               result = broken.redeem(granted, code, @redirect_uri, "plain-wrong-verifier")

      assert {:error, %Trace.Disagreement{} = disagreement} =
               Trace.event(
                 session,
                 mapped_redeem(broken, granted, code, "plain-wrong-verifier", result)
               )

      assert disagreement.reason == :claim
      assert disagreement.model == "PkceExchange"
      assert disagreement.claim == {:equals, :token_issued, true}
      assert disagreement.detail =~ "token_issued == true failed"
      assert disagreement.state == %{challenge: :known, verifier: :wrong, token_issued: false}

      assert Trace.Disagreement.format(disagreement) ==
               "disagreement (claim) at event \"redeem: verifier mismatched, token issued\": " <>
                 "claim PkceExchange.token_issued == true failed: model state has false"
    end

    # @spec OAUTH-TC-6
    test "a re-minted code disagrees on AuthCode redemptions", %{broken: broken, session: session} do
      granted = authorize(broken, broken.new_server(@client_id, @redirect_uri))
      session = conform!(session, Mapping.issue({:Ok, granted}))
      code = granted.grant.code

      {:Redeemed, _, _} = exchanged = broken.redeem(granted, code, @redirect_uri, @verifier)
      session = conform!(session, mapped_redeem(broken, granted, code, @verifier, exchanged))

      assert {:Redeemed, _, _} = replay = broken.redeem(granted, code, @redirect_uri, @verifier)

      assert {:error, %Trace.Disagreement{} = disagreement} =
               Trace.event(session, mapped_redeem(broken, granted, code, @verifier, replay))

      assert disagreement.reason == :claim
      assert disagreement.model == "AuthCode"
      assert disagreement.claim == {:increments, :redemptions}
      assert disagreement.detail =~ "moved 1 -> 1"

      # The session stays at the last conforming state.
      assert Trace.state(session, "AuthCode") == %{issued: true, redemptions: 1}
    end

    # @spec OAUTH-TC-6
    test "a minted token for an unknown code disagrees on AuthCode redemptions", %{
      broken: broken,
      session: session
    } do
      server = broken.new_server(@client_id, @redirect_uri)

      assert {:Redeemed, _, _} =
               result = broken.redeem(server, "ac-never-issued", @redirect_uri, @verifier)

      assert {:error, %Trace.Disagreement{} = disagreement} =
               Trace.event(
                 session,
                 mapped_redeem(broken, server, "ac-never-issued", @verifier, result)
               )

      assert disagreement.reason == :claim
      assert disagreement.model == "AuthCode"
      assert disagreement.detail =~ "moved 0 -> 0"

      assert Trace.Disagreement.format(disagreement) =~
               ~s(at event "redeem: unknown code, token issued")
    end

    # @spec OAUTH-TC-6
    test "the good runtime never disagrees where the broken one does", %{
      mod: mod,
      session: session
    } do
      granted = authorize(mod, mod.new_server(@client_id, @redirect_uri))
      session = conform!(session, Mapping.issue({:Ok, granted}))
      code = granted.grant.code

      {:Redeemed, _, _} = exchanged = mod.redeem(granted, code, @redirect_uri, @verifier)
      session = conform!(session, mapped_redeem(mod, granted, code, @verifier, exchanged))

      {:Error, "code already redeemed"} =
        replay = mod.redeem(granted, code, @redirect_uri, @verifier)

      conform!(session, mapped_redeem(mod, granted, code, @verifier, replay))
    end
  end
end
