# EARS specs: OAuth conformance/interoperability harness (#24)

Elicited from issue #24 and its acceptance criteria. See
[oauth-conformance.md](oauth-conformance.md) for the LLD these trace
to, [oauth-trace-specs.md](oauth-trace-specs.md) for the trace check
the harness ties its results back to, and
[tlc-crosscheck-specs.md](tlc-crosscheck-specs.md) for the pattern of
optional, skip-safe external tooling this follows. Depends on #23.

- [x] **OAUTH-CF-1**: When `YUP_OIDF_SUITE` is unset or blank,
  `bin/oauth-conformance` shall run the local case manifest against
  `examples/oauth_runtime.yup`, print that the external suite is not
  configured, write no plan, and exit 0 provided every supported case
  passes; `mix test` shall cover the same manifest so CI passes with
  or without an external install.
- [x] **OAUTH-CF-2**: When the harness runs a supported case, it shall
  replay the case's protocol-shaped steps (authorization and token
  requests) against a freshly compiled runtime, check each step's
  outcome against the case's RFC-derived expectation, and check each
  step's mapped event (through `Yup.OAuthTrace`) against the verified
  `AuthCode` and `PkceExchange` models; the case passes only when both
  layers hold, and the models shall be verified in-process before any
  case runs.
- [x] **OAUTH-CF-3**: When a supported case fails — the runtime's
  outcome contradicts its RFC-derived expectation, or its events
  disagree with the verified models — the harness shall print a FAIL
  line naming the case, the failing step, and both verdicts, and shall
  exit nonzero; `bin/oauth-conformance examples/broken_oauth_runtime.yup`
  is the documented failing demo.
- [x] **OAUTH-CF-4**: When a manifest case is unsupported, the harness
  shall report it as `unsupported` with its recorded reason and shall
  not execute it; the documentation shall list every case (supported
  and unsupported) with id and behavior, and a test shall fail if the
  documentation and the manifest drift apart.
- [x] **OAUTH-CF-5**: When `YUP_OIDF_SUITE` names an `http(s)://`
  deployment URL or an existing conformance-suite checkout, the harness
  shall verify the target — a HEAD request that confirms a URL is
  reachable, an existing directory for a checkout — and write a
  byte-stable `plan.json` into the work directory recording the suite
  target (a checkout pinned by absolute path and git commit when
  available), the deployment shape a suite-compatible deployment would
  need, and every case with its support status and reason, and the
  report shall name the plan path.
- [x] **OAUTH-CF-6**: When `YUP_OIDF_SUITE` names a path that does not
  exist or a URL that cannot be reached, or the runtime file or a
  model cannot be loaded or verified, the harness shall report the
  configuration/setup error and exit nonzero rather than skipping
  silently or reporting case results.
- [x] **OAUTH-CF-7**: The documentation shall present the harness as an
  interoperability harness, not certification, shall give the exact
  commands for the local run and the manual external-suite path
  (hosted entry point or a conformance-suite checkout), and shall state
  the permanent limitations — no HTTP so the suite cannot run end to
  end against the toy, the abstracted S256 derivation, reason strings
  instead of OAuth 2.0 error codes — as the expected failures they are.
