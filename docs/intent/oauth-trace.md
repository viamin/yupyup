# LLD: OAuth runtime ↔ model trace checking (#23)

Status: implemented. Traces to the issue #23 goal — connect the minimal
OAuth runtime's behavior back to the auth-code and PKCE models with
trace/refinement-style checks — and builds on the #22 runtime slice (see
[oauth-runtime.md](oauth-runtime.md)), whose models were verified and
independently cross-checked in #19–#21 (see
[tlc-crosscheck.md](tlc-crosscheck.md)). EARS:
[oauth-trace-specs.md](oauth-trace-specs.md).

## Goal

`test/oauth_trace_test.exs` drives the compiled `examples/oauth_runtime.yup`
through its whole transcript, maps each runtime observation onto the
verified models' transitions, and checks the mapped steps against the
models. Where #22 could only *say* "the endpoint store plays
`redemptions <= 1`", this issue makes the relation executable and
falsifiable: the check fails loudly when the runtime permits behavior
the models forbid.

## Decisions (from the issue's scope and constraints)

- **Trace checking, not refinement proving.** The check runs over the
  concrete events the tests feed it. It never explores the runtime's
  full behavior, never proves the gluing relation, and claims nothing
  about unbounded traces — the same discipline `yup verify` applies to
  its own results. A pass means "these traces conformed"; nothing more.
- **Two pieces: a generic engine in `lib`, the OAuth mapping in test
  support.** `Yup.Verify.Trace` (new) knows models, events, and
  disagreements; `Yup.OAuthTrace` (`test/support/oauth_trace.ex`, new)
  knows OAuth: which runtime observation maps to which transition and
  what the outcome claims about the abstract state. Keeping the
  abstraction relation out of the language toolchain matches #22's
  decision to keep OAuth knowledge in examples and tests; putting the
  engine in `lib` keeps it a `Yup.Verify`-family primitive that docs can
  point at. `mix.exs` gained `elixirc_paths/1` so `test/support` compiles
  only under `:test`.
- **One model semantics.** Initial-state construction, transition
  application, and invariant evaluation were extracted from
  `Yup.Verify.Explorer` into `Yup.Verify.Semantics` (new), and the
  explorer now calls that module. The trace check therefore steps models
  through the exact code `yup verify` uses — the credibility of the
  whole feature rests on not having two subtly different semantics. No
  explorer behavior changed; its test suite passes untouched.
- **Events are steps plus claims.** A `%Yup.Verify.Trace.Event{}` carries
  `steps` (`{model, transition}` pairs to apply; `[]` = stuttering) and
  `claims` — the gluing relation as data: `{:equals, field, value}`,
  `{:increments, field}`, or `{:unchanged, field}` over the post-event
  state. The engine applies the steps, rechecks every model's
  invariants (initial state included), then compares the claims against
  the states the *model* produced, pre vs post. A mismatch is a
  `%Trace.Disagreement{}` (`:claim`, `:invariant`, `:unknown_model`,
  `:unknown_transition`, `:unknown_field`, `:evaluation`,
  `:duplicate_model`) and the session stays at its last conforming state.
- **Transitions are chosen from inputs, never the outcome.** Which
  mapped transition fires depends on what the caller submitted — is the
  code the one the grant slot holds, does the submitted verifier derive
  to the stored challenge — while the claims are derived from the
  runtime's outcome. A runtime that mints a token on a wrong verifier is
  therefore mapped to `submit_invalid_verifier` *claiming*
  `token_issued == true`: the disagreement is structural, not an
  artifact of how the mapper read the result.
- **Refusals map to the models' own refusal encodings, or stutter.**
  A wrong verifier maps to `PkceExchange.submit_invalid_verifier`
  (`token_issued` false — the model agrees no token may flow); a reuse
  refusal maps to `AuthCode.redeem`, whose ternary guard no-ops a second
  redemption, demonstrating the single-use rule as running model
  behavior; redirect mismatch, unknown code, and unregistered issue
  stutter — the models have no corresponding state. Doing less than the
  model permits is conforming: trace conformance fails only when the
  runtime does what the model forbids.
- **Documented blind spots.** Client registration and redirect URIs are
  outside both models, so a runtime that issued for unregistered
  clients or ignored redirect binding cannot be caught here (the #22
  endpoint tests cover those rules at the runtime level). A minted
  token for an unknown code *is* caught — the abstraction counts any
  observable exchange, so it maps to an attempted redemption that
  `AuthCode`'s guard (nothing issued, nothing redeemable) rejects.
- **The bad fixture follows the `broken_*` convention.**
  `examples/broken_oauth_runtime.yup` is `examples/oauth_runtime.yup`
  with one mutation: `redeem` mints a token from every refused
  exchange. It is runnable like its sibling, and the disagreement tests
  exercise three distinct failures through it: wrong-verifier mint
  (PkceExchange `token_issued`), re-mint of a consumed code (AuthCode
  `redemptions` increments), and mint for an unknown code (AuthCode
  guard). One fixture, three falsifiable claims.

## Non-goals (from the issue)

A refinement theorem prover or trace-inclusion check over all runtime
behaviors, a CLI surface for trace checking, counterexample
minimization, modeling registration/redirect URIs, and any runtime
behavior beyond the #22 slice.

## Testing

`test/verify/trace_test.exs` unit-tests the engine against inline
models: session setup, initial-state invariant checking, step
application through the shared semantics, stuttering, invariant
violations from mapped steps, every claim kind's pass/fail, unknown
model/transition/field handling, evaluation errors, and that a
disagreeing event leaves the session at the last good state.
`test/oauth_trace_test.exs` pins the mapping (exact event shapes for
every runtime outcome, including the inputs-not-outcome rule), walks
the good runtime's full transcript to conformance with final model
states asserted, and asserts the broken fixture disagrees in the three
ways above. `setup_all` verifies both model files first, so a model
that stops holding its invariants fails the suite for that reason
before any trace is checked.

## Module map

```text
lib/yup/verify/semantics.ex  Yup.Verify.Semantics  initial_state/2, transition_env/2,
                            apply/3, check_invariants/3 (extracted from Explorer)
lib/yup/verify/trace.ex      Yup.Verify.Trace      new/2, event/2, state/2, states/1, labels/1
lib/yup/verify/explorer.ex   now steps through Yup.Verify.Semantics (no behavior change)
test/support/oauth_trace.ex  Yup.OAuthTrace        issue/1, redeem/5 — the explicit mapping
examples/broken_oauth_runtime.yup              the deliberately bad runtime fixture
test/verify/trace_test.exs                     engine tests
test/oauth_trace_test.exs                      mapping, conformance, disagreement tests
```
