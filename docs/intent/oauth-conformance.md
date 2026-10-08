# LLD: OAuth conformance/interoperability harness (#24)

Status: implemented. Traces to the issue #24 goal — a documented,
repeatable path for running the minimal OAuth runtime against external
OAuth/OIDC/FAPI conformance tooling where the supported subset fits —
and builds on the #23 trace checking (see
[oauth-trace.md](oauth-trace.md)) whose event mapping it reuses, on the
#22 runtime slice (see [oauth-runtime.md](oauth-runtime.md)), and on
the #19–#21 verify/export/cross-check story (see
[tlc-crosscheck.md](tlc-crosscheck.md)). EARS:
[oauth-conformance-specs.md](oauth-conformance-specs.md).

## Goal

`bin/oauth-conformance [RUNTIME.yup]` replays a manifest of
RFC-anchored conformance cases against the compiled runtime in protocol
shape, checks every step against the verified models through the #23
mapping, prints one line per case (pass / FAIL / unsupported with its
documented reason), and exits nonzero when any supported case fails.
When `YUP_OIDF_SUITE` names an OpenID Foundation Conformance Suite
deployment URL or a checkout, the harness additionally writes a
deterministic `plan.json` hand-off for a manual suite run; without it
the external part is skipped with a note and a passing local run exits
0.

## Decisions (from the issue's scope and constraints)

- **Interoperability harness, not certification.** The suite drives a
  deployed HTTPS provider end to end through a browser; the toy has no
  HTTP by permanent non-goal, so the suite cannot run against it
  wholesale and the docs say exactly that. What fits is executed: the
  manifest's cases encode the same RFC behaviors the suite's tests
  implement, run against the runtime's two request shapes
  (authorization and token), and the suite itself remains a documented
  manual path with exact commands and the `plan.json` hand-off.
- **The RFCs are the independent anchor.** For the models, #21 used TLC
  as the outside checker; here the normative RFC text is the outside
  statement of the protocol the runtime is checked against — the
  manifest's expectations are authored from the RFC requirements, not
  from the runtime's implementation. And each case needs **two**
  agreeing layers: the RFC-derived expectation about the outcome, and
  conformance of the same events with the verified models. That is the
  issue's "tie the result back to the verified model/runtime
  trace-checking story" made mechanical — a runtime that satisfies the
  RFC cases but drifts from the models still fails.
- **The manifest is data.** `Yup.Conformance.OAuth.Cases` holds every
  case: id, behavior title, normative source, and either the runnable
  steps or the documented reason it cannot run. The report, the
  `docs/LANGUAGE.md` table, and `plan.json` are all generated from or
  fixture-checked against that one list, so support cannot be
  overstated anywhere without a test failing.
- **Unsupported cases are documented honestly.** Ten behaviors an
  external suite would attempt are recorded as expected failures with
  reasons — no discovery (no HTTP), no OIDC ID token, real S256
  vectors (the `derive/1` abstraction), OAuth 2.0 error codes (reason
  strings), expiry/refresh, client authentication, scopes/consent, TLS,
  FAPI profiles, dynamic registration.
- **Optional, skip-safe external integration.** `find_suite/1` reads
  `YUP_OIDF_SUITE`: an `http(s)://` target is a deployment URL,
  anything else is a checkout path. Unset means skip (exit 0 on a
  passing local run, note printed) — the same skip-not-fail discipline
  as #21. A path that is set but missing is a configuration error that
  exits nonzero: a typo is not a skip. A URL target is verified by a
  HEAD request (curl), so an unreachable deployment is the same kind
  of configuration error rather than reporting a nonexistent suite as
  a successful run; the probe is injected via a `:probe` opt in tests
  so the harness does not depend on network access in `mix test`. A
  checkout is pinned by absolute path plus git commit when available,
  and `plan.json` is byte-stable (sorted keys, no timestamps), so a
  suite commit plus plan bytes are reproducible evidence of a manual
  run.
- **Reuse, don't duplicate, the #23 mapping.** `Yup.OAuthTrace` moved
  from `test/support` to `lib/yup/oauth_trace.ex` so the harness and
  the trace tests share one abstraction relation; it remains tooling
  rather than language surface (the compiler and verifier never read
  it), which is why `mix.exs` lost its `elixirc_paths` test-support
  override. The harness also verifies both models in-process before
  any case runs, exactly the way the #23 tests do, so a model that
  stopped holding its invariants fails the run for that reason first.
- **The broken fixture is the falsifiable demo.**
  `bin/oauth-conformance examples/broken_oauth_runtime.yup` exits 1:
  its mints fail the wrong-verifier, single-use, redirect-binding, and
  unknown-code cases at the protocol layer, and the first two also
  disagree with the models — one command shows both layers catching
  breakage.

## Non-goals (from the issue)

An HTTP/TLS adapter or discovery documents for the runtime, OIDC/FAPI
feature work, driving the external suite automatically (it needs a
browser-mediated authorization), certification claims of any kind, and
comparing counterexample traces.

## Testing

`test/conformance/oauth_test.exs` covers: the manifest (pinned id
list, supported entries carry protocol-shaped steps, unsupported
entries carry non-empty reasons, and every id and title appears in the
`docs/LANGUAGE.md` tables — the documentation fixture check);
`find_suite/1` classification and the unset/blank skip; the good
runtime passing every supported case at both layers; the broken
runtime failing loudly at both layers; setup and suite-configuration
errors (unreadable runtime, missing path, unreachable URL via the
injected curl-process boundary); the plan
(byte-stability, URL target, checkout pinning, missing-path error,
unreachable URL rejected); and the wrapper script end to end (local
subset + skip note, plan written with `YUP_OIDF_SUITE` set, nonzero
exit against the broken runtime). CI additionally runs
`bin/oauth-conformance` as the harness smoke check, mirroring the
#21 script.

## Module map

```text
lib/yup/conformance/oauth.ex        Yup.Conformance.OAuth      main/1, find_suite/0,1, run/1,
                                                               exit_code/1, report/1
lib/yup/conformance/oauth/cases.ex  Yup.Conformance.OAuth.Cases all/0, supported?/1
lib/yup/oauth_trace.ex              Yup.OAuthTrace             moved from test/support (#24)
bin/oauth-conformance               sh wrapper -> mix run -> Yup.Conformance.OAuth.main/1
test/conformance/oauth_test.exs     manifest, runner, plan, and script tests
docs/LANGUAGE.md                    the manifest tables and the external-suite guide
```
