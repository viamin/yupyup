# EARS specs: OAuth runtime ↔ model trace checking (#23)

Elicited from issue #23 and its acceptance criteria. See
[oauth-trace.md](oauth-trace.md) for the LLD these trace to,
[oauth-runtime-specs.md](oauth-runtime-specs.md) for the runtime slice
whose events are checked, and [tlc-crosscheck-specs.md](tlc-crosscheck-specs.md)
for the cross-checking of the models themselves.
Depends on #22.

- [x] **OAUTH-TC-1**: When the runtime issues a code for the registered
  client and then redeems it with the matching verifier, the event
  mapping shall map the issue to `AuthCode.issue` (`issued` becomes
  true) and the redemption to `AuthCode.redeem` (redemptions increments)
  plus `PkceExchange.submit_valid_verifier` (`token_issued` becomes
  true), and a conformance session fed those events shall accept them.
- [x] **OAUTH-TC-2**: When the runtime refuses an exchange, the mapping
  shall produce invariant-preserving model behavior only — a wrong
  verifier maps to `PkceExchange.submit_invalid_verifier` with
  `token_issued` false, and a reuse refusal — regardless of submitted
  verifier — maps to `AuthCode.redeem` whose guard leaves `redemptions`
  unchanged. Redirect mismatch, unknown
  code, and unregistered issue map to stuttering steps with unchanged
  claims — and the session shall accept each such event.
- [x] **OAUTH-TC-3**: When the runtime returns `Redeemed` for inputs the
  models reject — a verifier that does not derive to the stored
  challenge, or a code the grant never held — the mapping shall still
  choose the mapped transitions from the inputs (except that the terminal
  reuse refusal takes priority) and derive the claims from the outcome, so the event
  disagrees with the model by construction.
- [x] **OAUTH-TC-4**: When the good runtime's full transcript (refused
  unregistered issue, issued code, wrong-verifier refusal, redirect
  mismatch refusal, successful PKCE redemption, reuse refusal,
  unknown-code refusal) is mapped and checked event by event, every
  event shall be accepted and the session shall end at
  `AuthCode {issued: true, redemptions: 1}` and
  `PkceExchange {verifier: :matching, token_issued: true}`.
- [x] **OAUTH-TC-5**: The trace engine shall step models through
  `Yup.Verify.Semantics` — the same declaration semantics `yup verify`
  explores — shall check every model's invariants at the initial state
  and after each event, and shall report unknown model, unknown
  transition, unknown claim field, invariant violations, and evaluation
  errors as disagreements that leave the session at its last conforming
  state.
- [x] **OAUTH-TC-6**: When the deliberately broken runtime fixture
  (`examples/broken_oauth_runtime.yup`, which mints a token from every
  refused exchange) is run through the same mapping, the check shall
  fail: a wrong-verifier mint as a `:claim` disagreement on
  `PkceExchange.token_issued`, and both a re-mint of a redeemed code and
  a mint for an unknown code as `:claim` disagreements on
  `AuthCode.redemptions` increments.
- [x] **OAUTH-TC-7**: The documentation shall present this work as trace
  checking over concrete runtime traces — an explicit event-to-transition
  mapping plus gluing claims, checked event by event — and shall state
  that it is not a refinement proof: no exhaustive runtime exploration,
  no proved abstraction relation.
