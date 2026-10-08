# EARS specs: OAuth auth-code + PKCE runtime slice (#22)

Elicited from issue #22 and its acceptance criteria. See
[oauth-runtime.md](oauth-runtime.md) for the LLD these trace to, and
[tlc-crosscheck-specs.md](tlc-crosscheck-specs.md) for the specs whose
verified finite models (`examples/auth_code.yup`,
`examples/pkce_exchange.yup`) this executable slice relates back to.
Depends on #21.

- [x] **OAUTH-RT-1**: When the authorization endpoint function is called
  with the registered client id and its exact registered redirect URI, it
  shall return `Ok(server)` carrying a freshly issued authorization code
  bound to that redirect URI and to the submitted challenge, with the code
  marked unconsumed; the code and token values are deterministic
  (`ac-<client_id>`, `at-<code>`) because the toy has no randomness.
- [x] **OAUTH-RT-2**: When the authorization endpoint function is called
  with any other redirect URI (or a client id that is not the one
  registered client), it shall return `Error(reason)` naming the
  registration failure and shall not issue a usable grant — the grant slot
  keeps its previous, unusable placeholder value.
- [x] **OAUTH-RT-3**: When the token endpoint function is called with the
  issued code, the exact redirect URI the code was issued for, and the
  verifier whose derived challenge equals the stored challenge, it shall
  return `Redeemed(server, token)` with a deterministic access token and
  shall mark the code consumed in the returned server, so the caller
  threading that server onwards holds a code that can no longer be
  redeemed.
- [x] **OAUTH-RT-4**: When the token endpoint function is called with a
  verifier whose derivation does not equal the stored challenge, it shall
  return `Error("verifier mismatch")` without consuming the grant — the
  same code remains redeemable with the correct verifier afterwards.
- [x] **OAUTH-RT-5**: When the token endpoint function is called with a
  redirect URI different from the one the code was issued for, it shall
  return `Error("redirect uri mismatch")` without consuming the grant.
- [x] **OAUTH-RT-6**: When the token endpoint function is called with a
  code that was never issued or with a code already consumed by an earlier
  successful redemption, it shall return `Error(reason)` and shall not mint
  another token for that code.
- [x] **OAUTH-RT-7**: When `yup run examples/oauth_runtime.yup` executes,
  it shall exit 0 and print a transcript that shows, in order: the refused
  authorization request with an unregistered redirect URI, the issued code
  for the registered redirect URI, the refused redemption with a wrong
  verifier, the refused redemption with a mismatched redirect URI, the
  successful PKCE redemption with its access token, and the refused replay
  of the already-consumed code.
