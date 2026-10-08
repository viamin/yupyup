# EARS specs: TLC cross-check (#21)

Elicited from issue #21 and its acceptance criteria. See
[tlc-crosscheck.md](tlc-crosscheck.md) for the LLD these trace to, and
[tla-export-specs.md](tla-export-specs.md) for the export specs whose
modules this cross-check replays in TLC. Depends on #20.

- [x] **TLA-XC-1**: When TLC cannot be found — no usable `YUP_TLC`
  environment override, or no `java` on `PATH` together with a `CLASSPATH`
  naming at least one existing entry — `bin/tlc-crosscheck` shall print a
  message saying TLC is missing, skip all cross-checks, and exit 0, and the
  `mix test` suite shall exclude its TLC-dependent test.
- [x] **TLA-XC-2**: When TLC is available, the cross-check shall, for each
  model file, run the YupYup verifier, export the TLA+ module and generate
  the companion `.cfg` into a working directory, run TLC in that directory,
  and record agreement when both checkers pass the model or both fail it.
- [x] **TLA-XC-3**: When the two checkers disagree on any file — one
  reports failure where the other passes — the cross-check shall print a
  `DISAGREEMENT` line naming the file, both checkers' outcomes, and an
  excerpt of TLC's output, and shall exit nonzero.
- [x] **TLA-XC-4**: When TLC is invoked for a model, the exported
  `<Model>.tla` and the companion `<Model>.cfg` shall already exist in
  TLC's working directory.
- [x] **TLA-XC-5**: When no files are passed, the cross-check shall check
  the finite safety models `examples/auth_code.yup`,
  `examples/pkce_exchange.yup`, `examples/broken_auth_code.yup`, and
  `examples/broken_pkce_exchange.yup`, with the deliberately broken
  fixtures expected to fail on both checkers.
- [x] **TLA-XC-6**: When the YupYup verifier cannot produce a verdict
  (unreadable file, parse error, evaluation failure, or an exploration
  that hit its state cap) or the model cannot be exported, the cross-check
  shall report that file as an error rather than agreement or
  disagreement, and shall exit nonzero.
