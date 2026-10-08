defmodule Yup.OAuthTrace do
  @moduledoc """
  The explicit mapping from `examples/oauth_runtime.yup` events to the
  verified models' transitions (issue #23).

  This is the abstraction relation of the trace check: which model
  transitions a runtime observation maps to, and what the runtime's
  outcome claims about the models' abstract state afterwards. It lives
  in `lib` (moved out of test support by the #24 conformance harness,
  which reuses it) but is still tooling rather than part of the
  language: the compiler and verifier never read it;
  `Yup.Verify.Trace` is the generic engine it feeds.

  ## Event mapping

  Runtime event                            | AuthCode             | PkceExchange
  -----------------------------------------|----------------------|----------------------------------
  issue -> Ok                              | `issue`, issued      | — (stutter)
  issue -> Error                           | — (stutter)          | — (stutter)
  redeem, matching verifier, Redeemed      | `redeem`, +1         | `submit_valid_verifier`, token
  redeem, any verifier, refused reuse      | `redeem` (guard)     | — (stutter)
  redeem, matching verifier, refused other | — (stutter)          | — (stutter)
  redeem, wrong verifier, Redeemed         | `redeem`, +1         | `submit_invalid_verifier`, token
  redeem, wrong verifier, refused          | — (stutter)          | `submit_invalid_verifier`, no token
  redeem, unknown code, Redeemed           | `redeem`, +1         | `submit_valid_verifier`, token
  redeem, unknown code, refused            | — (stutter)          | — (stutter)

  Three rules carry the load:

  - **Transitions are chosen from the event's inputs, except a terminal
    reuse refusal.** Which model transition fires normally depends on what
    the caller submitted — whether the code is the one the grant slot holds
    and the submitted verifier derives to the stored challenge — so a
    runtime that *succeeds* on inputs the model rejects is still mapped to
    the model's refusal transition and surfaces as a disagreement, instead
    of being silently mapped to the success transition. The store checks
    reuse before the verifier, however, and that outcome takes priority:
    the caller's stale snapshot cannot otherwise preserve a prior token.
  - **Claims are chosen from the runtime's outcome.** A minted token
    claims `token_issued` and a consumed code claims a redemption,
    whether or not the runtime's internal state agrees — the abstraction
    counts observable exchanges.
  - **Refusals may do less than the model permits.** A refused exchange
    never steps a model toward a token: it either maps to the model's own
    refusal encoding (the AuthCode `redeem` guard for reuse, the
    `submit_invalid_verifier` transition for a wrong verifier) or
    stutters. Trace conformance only fails when the runtime does what the
    model forbids, never when it declines what the model allows.

  What the mapping cannot see, the check cannot catch: client
  registration and redirect URIs are outside both models (an issue for an
  unregistered client, or an exchange at the wrong redirect URI, is
  invisible to the model side).
  """

  alias Yup.Verify.Trace.Event

  @auth_code "AuthCode"
  @pkce_exchange "PkceExchange"

  @reuse_reason "code already redeemed"

  @doc """
  Maps an authorization-endpoint outcome.

  The models have no notion of client registration, so a refused
  authorization is a stuttering step and even an issued-for-unregistered
  code cannot contradict them; only the issued/not-issued bit is modeled.
  """
  # @spec OAUTH-TC-1
  def issue(result)

  def issue({:Ok, _granted}) do
    %Event{
      label: "issue: code issued",
      steps: [{@auth_code, "issue"}],
      claims: [{@auth_code, {:equals, :issued, true}}]
    }
  end

  def issue({:Error, _reason}) do
    %Event{
      label: "issue: refused",
      steps: [],
      claims: [{@auth_code, {:unchanged, :issued}}]
    }
  end

  @doc """
  Maps a token-endpoint observation.

  `server` is the snapshot the runtime was called with (its grant carries
  the stored challenge), and `derive` is the runtime's own derivation
  function, so input classification uses the runtime's notion of a
  matching verifier. Five params is deliberate: each is one observable of
  the exchange (snapshot, code, verifier, outcome, derivation).
  """
  # @spec OAUTH-TC-1
  # @spec OAUTH-TC-2
  # @spec OAUTH-TC-3
  def redeem(server, code, verifier, result, derive)

  def redeem(server, code, verifier, result, derive) do
    result
    |> classified(server, code, verifier, derive)
    |> exchange_event(result)
  end

  defp classified({:Error, @reuse_reason}, _server, _code, _verifier, _derive), do: :reuse

  defp classified(_result, server, code, verifier, derive) do
    grant = server.grant

    cond do
      code == "" or grant.code != code -> :unknown_code
      derive.(verifier) == grant.challenge -> :matching_verifier
      true -> :wrong_verifier
    end
  end

  defp exchange_event(:matching_verifier, {:Redeemed, _server, _token}) do
    %Event{
      label: "redeem: verifier matched, token issued",
      steps: [{@auth_code, "redeem"}, {@pkce_exchange, "submit_valid_verifier"}],
      claims: [
        {@auth_code, {:increments, :redemptions}},
        {@pkce_exchange, {:equals, :token_issued, true}}
      ]
    }
  end

  # A minted token on a mismatched verifier maps to the model's invalid
  # submission transition: the token claim below is exactly what the
  # model forbids there, so this event disagrees by construction.
  defp exchange_event(:wrong_verifier, {:Redeemed, _server, _token}) do
    %Event{
      label: "redeem: verifier mismatched, token issued",
      steps: [{@auth_code, "redeem"}, {@pkce_exchange, "submit_invalid_verifier"}],
      claims: [
        {@auth_code, {:increments, :redemptions}},
        {@pkce_exchange, {:equals, :token_issued, true}}
      ]
    }
  end

  # A token for a code the grant slot never holds still counts as an
  # attempted redemption; the AuthCode guard (nothing issued, nothing
  # redeemable) is what rejects it.
  defp exchange_event(:unknown_code, {:Redeemed, _server, _token}) do
    %Event{
      label: "redeem: unknown code, token issued",
      steps: [{@auth_code, "redeem"}, {@pkce_exchange, "submit_valid_verifier"}],
      claims: [
        {@auth_code, {:increments, :redemptions}},
        {@pkce_exchange, {:equals, :token_issued, true}}
      ]
    }
  end

  # The single-use rule as the model states it: AuthCode's `redeem`
  # guard no-ops a second redemption, so the step is invariant-preserving
  # and the runtime's refusal agrees with the unchanged redemptions.
  defp exchange_event(:reuse, {:Error, @reuse_reason}) do
    %Event{
      label: "redeem: code already redeemed, refused",
      steps: [{@auth_code, "redeem"}],
      claims: [
        {@auth_code, {:unchanged, :redemptions}},
        {@pkce_exchange, {:unchanged, :token_issued}}
      ]
    }
  end

  defp exchange_event(:wrong_verifier, {:Error, _reason}) do
    %Event{
      label: "redeem: verifier mismatched, refused",
      steps: [{@pkce_exchange, "submit_invalid_verifier"}],
      claims: [
        {@pkce_exchange, {:equals, :token_issued, false}},
        {@auth_code, {:unchanged, :redemptions}}
      ]
    }
  end

  defp exchange_event(:unknown_code, {:Error, _reason}) do
    %Event{
      label: "redeem: unknown code, refused",
      steps: [],
      claims: [
        {@auth_code, {:unchanged, :redemptions}},
        {@pkce_exchange, {:unchanged, :token_issued}}
      ]
    }
  end

  # Refused with a matching verifier for a reason the models do not
  # cover (redirect mismatch): doing less than the model permits is
  # conforming, so no model moves.
  defp exchange_event(:matching_verifier, {:Error, _reason}) do
    %Event{
      label: "redeem: verifier matched, refused",
      steps: [],
      claims: [
        {@auth_code, {:unchanged, :redemptions}},
        {@pkce_exchange, {:unchanged, :token_issued}}
      ]
    }
  end
end
