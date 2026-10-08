# LLD: OAuth auth-code + PKCE runtime slice (#22)

Status: implemented. Traces to the issue #22 goal — after the protocol
rules were modeled and independently cross-checked, provide the smallest
OAuth-shaped executable slice that can be related back to those models —
and builds on the #20/#21 verify/export/cross-check work (see
[tlc-crosscheck.md](tlc-crosscheck.md)). This is a **toy**, not a server.

## Goal

`examples/oauth_runtime.yup` is a YupYup program run by the ordinary
`yup run` path: one issuer with one registered client and one in-memory
grant slot, exact redirect URI matching at both endpoints, single-use
authorization codes, and a PKCE verifier check at the token endpoint. Its
printed transcript walks the happy path and each refusal so the demo
doubles as the protocol story.

## Decisions (from the issue's scope and constraints)

- **Written in YupYup, run through the existing CLI.** The issue asks for
  an *example runtime*, and the repo's runtime surface is `yup run`. No
  standalone application endpoint or controller: the slice exercises the existing
  parse → compile → BEAM pipeline (`Yup.run_file/1`) and stays a
  self-contained example, with a narrow `Yup.Runtime` store primitive for
  endpoint-owned grants. The implementation graph entry point is the example
  file plus the tests that drive its compiled functions.
- **Endpoint-owned in-memory storage.** A `Server` record reflects the
  registered `Client` and one `Grant` slot, while `Yup.Runtime` owns the
  actual grant state under a unique endpoint id. The store atomically marks
  a code consumed, so a caller cannot redeem it again by retaining a stale
  pre-redemption record. A production store would key many grants by code;
  that is a non-goal.
- **Exact redirect URI matching, both endpoints.** `issue/4` matches
  client id **and** redirect URI against the registration
  (OAUTH-RT-2, RFC 6749 simple-string comparison); `redeem/4` requires the
  redemption redirect URI to equal the URI the code was issued for, so a
  code minted for one redirect cannot be redeemed at another.
- **Single-use codes via endpoint-owned state.** `redeem/4` delegates the
  atomic lookup-and-consume operation to the endpoint store and reflects the
  consumed `used` flag in its returned server. A consumed code answers
  `"code already redeemed"` (OAUTH-RT-6); a code that was never issued
  answers `"unknown code"`.
- **PKCE with an abstract derivation.** `derive/1` (`"s256:" + verifier`)
  stands in for `BASE64URL(SHA256(ASCII(verifier)))` exactly as the
  verified model abstracts the hash: the runtime rule demonstrated is
  *token iff derive(verifier) == stored challenge*, with the challenge
  stored transformed, never as the raw verifier (OAUTH-RT-4). Real
  cryptography is a non-goal of the issue.
- **Deterministic codes and tokens.** `ac-<client_id>` and `at-<code>`
  because the toy has no randomness; tests and transcript can assert
  exact values. Obvious collision properties — fine for one client and one
  flow, wrong for anything real.
- **Failures are reasons, not HTTP.** Constructors `Ok/Error/Redeemed`
  carry outcomes; the demo renders them as transcript lines. Mapping
  reasons onto OAuth 2.0 error codes (`invalid_grant`, …) and any HTTP
  layer are out of scope.

## Relation to the verified models

`examples/auth_code.yup` proves the single-use rule
(`redemptions <= 1`) and `examples/pkce_exchange.yup` proves the
verifier-matching rule over finite state spaces, cross-checked by TLC in
#21. This slice is the executable counterpart: the same two rules as
running code — the endpoint store's consumed grant plays `redemptions <= 1`,
and the `derive(verifier) == challenge` check plays
`verifier == :matching`. The models remain the checked artifacts; the
example makes the rules runnable and inspectable, and is the anchor the
tests below pin to. Neither proves the other — that relationship was
documentation until #23 made it checkable: the trace conformance tests
now map this runtime's events onto those models' transitions and fail
on disagreement (see [oauth-trace.md](oauth-trace.md)).

## Non-goals (from the issue)

OpenID Connect ID tokens, refresh tokens, dynamic client registration,
multiple tenants/issuers, production cryptographic key management,
external conformance suite integration at the runtime level (the #24
harness documents exactly what such a suite can and cannot check
against the toy — see [oauth-conformance.md](oauth-conformance.md)) —
and, inherited from the toy: HTTP, persistence, expiry, randomness,
scopes, client secrets, or being listened to by anything.

## Testing

`test/oauth_runtime_test.exs` compiles the example once and drives its
exported functions directly: issue-refusal for unregistered redirect URIs
(OAUTH-RT-2), the happy path with token and consumed code (OAUTH-RT-3),
verifier mismatch without consumption (OAUTH-RT-4), redirect mismatch
(OAUTH-RT-5), stale-snapshot and concurrent code reuse plus unknown codes
(OAUTH-RT-6), and that the stored challenge is the derived, not raw,
verifier. `test/cli_test.exs`
runs the example through the built escript and asserts the full
transcript (OAUTH-RT-7).

## Module map

```text
examples/oauth_runtime.yup  new_server/2, derive/1, issue/4, redeem/4,
                            show/1, show_exchange/1,
                            unwrap_ok/2, redeemed_server/2, run/0 demo
test/oauth_runtime_test.exs drives the compiled module's functions
test/cli_test.exs          runs the example through the built escript
```
