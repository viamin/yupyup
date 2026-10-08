defmodule Yup.OAuthRuntimeTest do
  @moduledoc false

  use ExUnit.Case

  # The runtime slice under test is a YupYup program, not an Elixir module:
  # compile examples/oauth_runtime.yup once and drive its exported
  # functions directly, the same boundary `yup run` uses. Constructor tags
  # keep their YupYup spelling, so results match {:Ok, ...}, {:Error, ...},
  # and {:Redeemed, ..., ...}.
  @example_path Path.expand("examples/oauth_runtime.yup", File.cwd!())
  @client_id "toy-client"
  @redirect_uri "https://app.example/cb"
  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  setup_all do
    {:ok, source} = File.read(@example_path)
    {:ok, program} = Yup.Parser.parse(source, path: @example_path)
    {:ok, module} = Yup.Compiler.compile(program)

    %{mod: module}
  end

  setup %{mod: mod} do
    %{server: mod.new_server(@client_id, @redirect_uri)}
  end

  defp authorize(mod, server) do
    {:Ok, granted} = mod.issue(server, @client_id, @redirect_uri, mod.derive(@verifier))
    granted
  end

  describe "authorization endpoint" do
    # @spec OAUTH-RT-1
    test "issues a code for the registered client and its exact redirect uri", %{
      mod: mod,
      server: server
    } do
      {:Ok, granted} = mod.issue(server, @client_id, @redirect_uri, mod.derive(@verifier))

      assert granted.grant.code == "ac-" <> @client_id
      assert granted.grant.redirect_uri == @redirect_uri
      assert granted.grant.used == false
    end

    # @spec OAUTH-RT-2
    test "refuses an unregistered redirect uri and leaves no usable grant", %{
      mod: mod,
      server: server
    } do
      result = mod.issue(server, @client_id, "https://evil.example/cb", mod.derive(@verifier))

      assert {:Error, reason} = result
      assert reason =~ "unregistered"

      assert server.grant.code == ""
      assert server.grant.used == false
    end

    # @spec OAUTH-RT-2
    test "refuses an unregistered client id", %{mod: mod, server: server} do
      result = mod.issue(server, "imposter", @redirect_uri, mod.derive(@verifier))

      assert {:Error, reason} = result
      assert reason =~ "unregistered"
    end

    # @spec OAUTH-RT-1
    test "stores the challenge derived from the verifier, never the raw verifier", %{
      mod: mod,
      server: server
    } do
      granted = authorize(mod, server)

      assert granted.grant.challenge == mod.derive(@verifier)
      refute granted.grant.challenge == @verifier
    end
  end

  describe "token endpoint" do
    # @spec OAUTH-RT-3
    test "redeems the code once with the matching verifier", %{mod: mod, server: server} do
      granted = authorize(mod, server)
      code = granted.grant.code

      {:Redeemed, after_redeem, token} = mod.redeem(granted, code, @redirect_uri, @verifier)

      assert token == "at-" <> code
      assert after_redeem.grant.code == code
      assert after_redeem.grant.used == true
    end

    # @spec OAUTH-RT-4
    test "refuses a mismatched verifier without consuming the code", %{
      mod: mod,
      server: server
    } do
      granted = authorize(mod, server)
      code = granted.grant.code

      assert {:Error, reason} = mod.redeem(granted, code, @redirect_uri, "wrong-verifier")
      assert reason =~ "verifier mismatch"

      assert {:Redeemed, _after_redeem, _token} =
               mod.redeem(granted, code, @redirect_uri, @verifier)
    end

    # @spec OAUTH-RT-5
    test "refuses a redirect uri other than the one the code was issued for", %{
      mod: mod,
      server: server
    } do
      granted = authorize(mod, server)
      code = granted.grant.code

      assert {:Error, reason} =
               mod.redeem(granted, code, "https://evil.example/cb", @verifier)

      assert reason =~ "redirect uri mismatch"
    end

    # @spec OAUTH-RT-6
    test "refuses a reused code after a successful redemption", %{mod: mod, server: server} do
      granted = authorize(mod, server)
      code = granted.grant.code

      {:Redeemed, after_redeem, _token} = mod.redeem(granted, code, @redirect_uri, @verifier)

      assert {:Error, reason} = mod.redeem(after_redeem, code, @redirect_uri, @verifier)
      assert reason =~ "already redeemed"
    end

    # @spec OAUTH-RT-6
    test "refuses a replay through a stale server snapshot", %{mod: mod, server: server} do
      granted = authorize(mod, server)
      code = granted.grant.code

      assert {:Redeemed, _after_redeem, _token} =
               mod.redeem(granted, code, @redirect_uri, @verifier)

      assert {:Error, "code already redeemed"} =
               mod.redeem(granted, code, @redirect_uri, @verifier)
    end

    # @spec OAUTH-RT-6
    test "serializes simultaneous redemptions of the same grant", %{mod: mod, server: server} do
      granted = authorize(mod, server)
      code = granted.grant.code

      results =
        [
          Task.async(fn -> mod.redeem(granted, code, @redirect_uri, @verifier) end),
          Task.async(fn -> mod.redeem(granted, code, @redirect_uri, @verifier) end)
        ]
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &match?({:Redeemed, _, _}, &1)) == 1
      assert Enum.count(results, &match?({:Error, "code already redeemed"}, &1)) == 1
    end

    # @spec OAUTH-RT-6
    test "refuses a code that was never issued", %{mod: mod, server: server} do
      assert {:Error, reason} =
               mod.redeem(server, "ac-never-issued", @redirect_uri, @verifier)

      assert reason =~ "unknown code"
    end
  end
end
