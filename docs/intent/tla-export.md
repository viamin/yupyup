# LLD: TLA+ export (#20)

Status: implemented (bootstrap milestone). Traces to the issue #20 goal of a
third-party checker so YupYup verification results never depend solely on
YupYup's own verifier, and builds on the #9/#10 model, explorer, and
invariant work (see [verify-invariants.md](verify-invariants.md)). The
generated artifacts are checked with an external TLA+/TLC installation; none
is vendored or automated here.

## Goal

`yup export tla FILE` writes the file's single model as a TLA+ module on
stdout. Saving it as `<Model>.tla` next to the companion `.cfg` the module
documents lets an external TLC installation replay the finite exploration
and re-check the declared invariants, independently of `yup verify`.

## Decisions (from the issue's scope and non-goals)

- **CLI surface.** A new `yup export tla FILE` command writes module text to
  stdout; the user redirects it into `<Model>.tla` (TLC requires module and
  file names to match, and model names already satisfy TLA+ module naming).
  No `--out` flag, no TLC invocation: running the external checker stays a
  documented manual step per the non-goals.
- **State and Init.** Each `state name = expr` becomes one TLA+ variable,
  in declaration order; `Init` conjoins `name = <translated expr>`.
  Initializers keep the verifier's rule that they cannot read state fields.
- **Transitions.** Each transition becomes an action named by camelizing its
  name (`submit_valid_verifier` becomes `SubmitValidVerifier`). The action
  conjoins `name' = expr` for every assigned field and one
  `UNCHANGED << ... >>` conjunct listing unassigned fields in declaration
  order. Because a YupYup transition body applies updates sequentially,
  an expression reads a field assigned earlier in the same body at its
  next-state value: the TLA+ conjunct refers to the primed variable, which
  the earlier conjunct already fixed. Assigning the same field twice in one
  body cannot be expressed this way and is rejected with a diagnostic.
  `Next` is the disjunction of all actions (`FALSE` for a model with no
  transitions), and `Spec == Init /\ [][Next]_vars` allows stuttering, so
  TLC explores the same finite state graph as `yup verify` without
  reporting spurious deadlocks.
- **Invariants.** Invariant labels are free-form strings, so definitions are
  numbered `Invariant1, Invariant2, ...` in declaration order, each
  preceded by a comment carrying the original label. The module ends with a
  comment showing the exact companion `.cfg` (`SPECIFICATION Spec` plus one
  `INVARIANT InvariantN` line each) and the `java tlc2.TLC` command line.
- **Expression translation.** Supported: the verifier's model expression
  subset minus strings and `nil`. Integers, booleans, atoms, field reads
  (bare or `state.`), `+ - * /` (with `/` as integer division, so TLA+
  `div`), `== != < <= > >=` (`<=` becomes `=<`, `!=` becomes `#`),
  `and or not`, and ternaries. Atoms become distinct TLA+ strings
  (`:known` becomes `"known"`). `and`/`or`/`not` and ternary conditions
  must preserve YupYup truthiness (only `false` is falsy among exportable
  values), so operands that are not statically boolean — comparisons,
  boolean operators, and boolean literals are — render as
  `(... # FALSE)` instead of being handed to TLC as booleans. A
  non-boolean invariant condition gets the same treatment at the top level.
- **Determinism.** Every line derives from AST declaration order; atoms
  render through `inspect/1` and set iteration is never used for output
  ordering. Exporting the same model twice yields identical bytes, which the
  golden tests pin.
- **Rejections.** String literals, `nil`, unsupported expression shapes
  (calls, lists, maps, records, matches), duplicate field assignment in one
  transition, assignment to undeclared fields, unknown field reads,
  initializer field reads, and names that cannot become TLA+ identifiers
  (`?`/`!` are not identifier characters) or that collide with generated
  definitions (`vars`, `Init`, `Next`, `Spec`, action names, and numbered
  invariants) all fail with source-located diagnostics and a nonzero exit.
  A file must contain exactly one model block, mirroring `yup verify`.

## Non-goals (from the issue)

Full YupYup expression coverage, temporal properties, refinement checking,
and installing or vendoring TLC.

## Local design choices

- `Yup.Export.Tla` is a sibling of `Yup.Verify.*` under a new `Yup.Export`
  namespace: it consumes `Yup.AST.Model` directly, mirroring how
  `Yup.Verify` reads `Program.models` without touching the BEAM backend.
- The translation context is a plain map (`path`, `fields` as a set,
  `names` in declaration order, `assigned`, `mode`); `mode` distinguishes
  initializer, transition, and invariant rendering, reusing the verifier's
  diagnostic wording where the rules coincide.
- Output is assembled as iodata and flattened once; the module text always
  ends with a newline so `yup export tla f.yup > M.tla` produces a complete
  file.

## Module map

```text
Yup.Export.Tla     export_file/1, export_program/2, export_model/2, rendering
Yup.CLI            `yup export tla FILE` writes the module to stdout
```
