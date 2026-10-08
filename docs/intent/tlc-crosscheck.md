# LLD: TLC cross-check (#21)

Status: implemented. Traces to the issue #21 goal of routinely comparing
YupYup's verifier result with an independent checker, and builds on the
#20 TLA+ export (see [tla-export.md](tla-export.md)). Together the two
issues define the trust boundary: `yup verify` is YupYup checking YupYup,
so its result is only as trustworthy as the verifier itself; TLC replaying
the same finite models from an independently generated TLA+ module is the
outside check. Neither is a proof of the unbounded system — both speak
about the same finite state graph.

## Goal

`bin/tlc-crosscheck [FILE...]` runs the YupYup verifier and an external
TLC installation on the same models and exits nonzero with a loud
`DISAGREEMENT` line whenever their pass/fail verdicts differ. TLC stays
optional: without an installation the script skips (exit 0) and the test
suite excludes its TLC-dependent test, so CI and local runs pass with or
without a TLA+ install.

## Decisions (from the issue's scope and constraints)

- **Optional TLC, discoverable.** `Yup.Crosscheck.Tlc.find_tlc/1` returns
  the TLC command words when `YUP_TLC` is set (word-split override, the
  hook the tests also use to inject a fake TLC), or when `java` is on
  `PATH` **and** `CLASSPATH` names at least one existing entry — the
  tla2tools.jar install convention the #20 module footer documents.
  Requiring `CLASSPATH` (rather than `java` alone) keeps machines with
  Java but no TLA+ tools — such as stock CI runners — on the skip path
  instead of reporting spurious disagreements from `ClassNotFoundException`
  runs. Everything else is a skip.
- **Comparison scope: finite safety invariants only.** A verdict is
  `pass` (completed exploration, all invariants held) or `fail`
  (`%Yup.Verify.Failure{kind: :invariant}`). Everything the verifier
  cannot turn into a verdict — unreadable file, parse error, evaluation
  failure, or an exploration truncated by the state cap — is reported as
  a cross-check `error` entry with the verifier's diagnostic and exits
  nonzero (TLA-XC-6), because a truncated run and a complete TLC pass are
  not comparable. TLC's verdict is its exit status.
- **Export before TLC.** For each file the runner exports the module
  with `Yup.Export.Tla.export_file/1`, writes it as `<Model>.tla` plus a
  generated `<Model>.cfg` (`SPECIFICATION Spec` and one `INVARIANT
  InvariantN` line per numbered definition in the module text) into a
  per-file run directory — named after the source basename, because the
  broken fixtures reuse the `AuthCode`/`PkceExchange` model names — and
  only then spawns TLC with that directory as its cwd (TLA-XC-4). The
  run directories live under a per-run work directory that survives the
  run for inspection and is named in the report.
- **Reuse in-process, spawn only TLC.** The YupYup side runs
  `Yup.Verify.verify_file/2` and the exporter inside the cross-check
  process — the same boundaries the CLI uses — so the only external
  process is TLC itself. That is the trust boundary in code: TLC never
  runs YupYup output through YupYup tooling. `crosscheck/3` is silent and
  returns one result map per file (verdicts, TLC status and output, run
  directory); `main/1` prints the report and turns it into an exit code.
- **Loud disagreement, quiet skip.** Agreeing files print one
  `agree` line each (including `yup failed, tlc exited 1` for the broken
  fixtures); a disagreeing file prints a `DISAGREEMENT` line with both
  outcomes plus an excerpt of TLC's output, and the script exits 1
  (TLA-XC-3). When TLC is missing the script prints why and exits 0
  (TLA-XC-1) — a skip must not fail CI, a disagreement must.
- **Entry point.** `bin/tlc-crosscheck` is a thin `sh` wrapper around
  `mix run -e 'Yup.Crosscheck.Tlc.main(System.argv())' -- "$@"`, matching
  `bin/lint`'s dependency on the mix toolchain; when mix is unavailable
  the wrapper warns and exits 0 for the same skip reason. The default
  file set is the four example models, whose broken halves are expected
  to fail on both checkers (TLA-XC-5) — that pair is the deliberately
  broken fixture the issue asks for.

## Non-goals (from the issue)

Comparing counterexample traces or state counts (pass/fail verdicts
only), temporal properties, refinement, and installing or vendoring TLC.

## Testing

Tests inject a fake TLC through `YUP_TLC` (a `sh` shim that records
whether `<Model>.tla` and `<Model>.cfg` exist at invocation time and
fails models run from `broken_*` run directories), so skip behavior,
export-before-TLC ordering, agreement including the broken fixtures, and
disagreement reporting are all covered without a TLA+ install. A
`:tlc`-tagged test runs the real cross-check whenever `find_tlc/0`
succeeds; `test/test_helper.exs` excludes it otherwise (TLA-XC-1).

## Module map

```text
Yup.Crosscheck.Tla  find_tlc/0,1; crosscheck/3; exit_code/1; report/1; main/1
bin/tlc-crosscheck  sh wrapper -> mix run -> Yup.Crosscheck.Tlc.main/1
```
