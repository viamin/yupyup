defmodule Yup.Conformance.OAuth.Cases do
  @moduledoc """
  The conformance case manifest for `examples/oauth_runtime.yup` (#24).

  Each supported case names one protocol behavior an external OAuth
  conformance tool — the OpenID Foundation Conformance Suite and friends
  — exercises on a deployment, anchored to its normative source, and
  carries the steps the harness replays in protocol shape:
  `{:authorize, fields, expect}` and `{:token, fields, expect}`
  requests, the two endpoint shapes such a suite drives. Each
  unsupported case records why it cannot run against this runtime —
  the honestly documented expected-failure list the issue asks for.

  The manifest is data so the report, the documentation table in
  `docs/LANGUAGE.md`, and the `plan.json` handed to an external suite
  are generated from or checked against this one list.
  """

  defstruct [:id, :title, :source, steps: [], reason: nil]

  @client_id "toy-client"
  @redirect_uri "https://app.example/cb"
  @evil_redirect_uri "https://evil.example/cb"
  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

  @registered %{client_id: @client_id, redirect_uri: @redirect_uri, verifier: @verifier}
  @other_redirect %{client_id: @client_id, redirect_uri: @evil_redirect_uri, verifier: @verifier}
  @unregistered %{client_id: "imposter", redirect_uri: @redirect_uri, verifier: @verifier}
  @matching_verifier %{code: :last_issued, redirect_uri: @redirect_uri, verifier: @verifier}

  @wrong_verifier %{
    code: :last_issued,
    redirect_uri: @redirect_uri,
    verifier: "plain-wrong-verifier"
  }

  @bound_elsewhere %{
    code: :last_issued,
    redirect_uri: @evil_redirect_uri,
    verifier: @verifier
  }

  @never_issued %{code: "ac-never-issued", redirect_uri: @redirect_uri, verifier: @verifier}

  @doc "The registered client the runtime example serves."
  def client_id, do: @client_id

  @doc "The redirect URI registered for that client."
  def redirect_uri, do: @redirect_uri

  @doc "A case is supported when it carries no unsupported-reason."
  # @spec OAUTH-CF-4
  def supported?(%__MODULE__{reason: nil}), do: true
  def supported?(_test_case), do: false

  @doc "The whole manifest, supported cases first."
  # @spec OAUTH-CF-4
  def all do
    [
      supported(
        "authorization-code-issued",
        "issues a code for the registered client, storing only the derived challenge",
        "RFC 6749 §4.1.2; RFC 7636 §4.4.1",
        [
          {:authorize, @registered, :code_issued}
        ]
      ),
      supported(
        "authorization-redirect-exact-match",
        "refuses a redirect uri other than the registered one",
        "RFC 6749 §3.1.2.3",
        [
          {:authorize, @other_redirect, {:refused, "unregistered"}}
        ]
      ),
      supported(
        "authorization-unregistered-client",
        "refuses an unregistered client id",
        "RFC 6749 §4.1.2.1",
        [
          {:authorize, @unregistered, {:refused, "unregistered"}}
        ]
      ),
      supported(
        "token-exchange-valid-verifier",
        "exchanges the code for a token when the verifier derives to the stored challenge",
        "RFC 7636 §4.6",
        [
          {:authorize, @registered, :code_issued},
          {:token, @matching_verifier, :token_issued}
        ]
      ),
      supported(
        "token-exchange-wrong-verifier",
        "refuses a verifier that does not derive to the stored challenge, without consuming the code",
        "RFC 7636 §4.6",
        [
          {:authorize, @registered, :code_issued},
          {:token, @wrong_verifier, {:refused, "verifier mismatch"}},
          {:token, @matching_verifier, :token_issued}
        ]
      ),
      supported(
        "authorization-code-single-use",
        "refuses a replay of an already-redeemed code",
        "RFC 6749 §4.1.2",
        [
          {:authorize, @registered, :code_issued},
          {:token, @matching_verifier, :token_issued},
          {:token, @matching_verifier, {:refused, "code already redeemed"}}
        ]
      ),
      supported(
        "token-endpoint-redirect-binding",
        "refuses redemption at a redirect uri other than the one the code was issued for",
        "RFC 6749 §4.1.3",
        [
          {:authorize, @registered, :code_issued},
          {:token, @bound_elsewhere, {:refused, "redirect uri mismatch"}}
        ]
      ),
      supported(
        "token-unknown-code-refused",
        "refuses a code that was never issued",
        "RFC 6749 §5.2 (invalid_grant)",
        [
          {:token, @never_issued, {:refused, "unknown code"}}
        ]
      ),
      unsupported(
        "provider-metadata-discovery",
        "well-known provider metadata discovery",
        "OIDC Discovery",
        "the suite starts from /.well-known/openid-configuration; the runtime is an " <>
          "in-process function slice with no HTTP, so there is no URL to fetch"
      ),
      unsupported(
        "oidc-id-token",
        "openid connect id token issuance",
        "OIDC Core",
        "no OpenID Connect layer: opaque access tokens only, no signing keys, " <>
          "no ID token claims"
      ),
      unsupported(
        "pkce-s256-test-vectors",
        "pkce s256 verification vectors",
        "RFC 7636 App. B",
        "derive/1 is the deliberate s256: + verifier abstraction, exactly as the model " <>
          "abstracts the hash; real BASE64URL(SHA256(...)) is out of scope"
      ),
      unsupported(
        "token-response-error-codes",
        "token endpoint error codes",
        "RFC 6749 §5.2",
        "refusals are reason strings, not OAuth 2.0 error codes; this is an expected " <>
          "failure against any real suite"
      ),
      unsupported(
        "token-expiry-and-refresh",
        "token expiry and refresh tokens",
        "RFC 6749 §4.2.2, §6",
        "tokens never expire and refresh tokens do not exist"
      ),
      unsupported(
        "client-authentication",
        "client authentication at the token endpoint",
        "RFC 6749 §2.3.1",
        "the one registered client has no secret; the token endpoint never authenticates a client"
      ),
      unsupported(
        "scope-handling-and-consent",
        "scope handling and consent",
        "RFC 6749 §3.3",
        "no scopes, no consent step, no resource indicators anywhere in the grant"
      ),
      unsupported(
        "https-and-tls-profile",
        "https endpoints and tls profile",
        "suite baseline",
        "nothing listens on any port; there is no TLS to profile"
      ),
      unsupported(
        "fapi-security-profile",
        "fapi security profile conformance",
        "FAPI 1.0/2.0",
        "FAPI profiles require signed request objects and mTLS or private_key_jwt; " <>
          "the toy implements none of it"
      ),
      unsupported(
        "dynamic-client-registration",
        "dynamic client registration",
        "RFC 7591",
        "one fixed registration in source; there is no registration endpoint"
      )
    ]
  end

  defp supported(id, title, source, steps) do
    %__MODULE__{id: id, title: title, source: source, steps: steps}
  end

  defp unsupported(id, title, source, reason) do
    %__MODULE__{id: id, title: title, source: source, reason: reason}
  end
end
