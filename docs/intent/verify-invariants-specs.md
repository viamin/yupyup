# EARS specs: `yup verify` invariants (#10)

Elicited from issue #10 and its acceptance criteria. See
[verify-invariants.md](verify-invariants.md) for the LLD these trace to, and
[verify-explorer-specs.md](verify-explorer-specs.md) for the #9 explorer
specs these build on.

- [x] **INVARIANT-1**: When the parser encounters an `invariant "name" do`
  block inside a model, it shall record a `Yup.AST.Invariant` with the name,
  a single-expression condition in the model expression subset, and the
  header's source location, in declaration order; malformed headers, empty or
  multi-expression bodies, missing `end`, and invariants outside a model
  shall be rejected with source-located diagnostics.
- [x] **INVARIANT-2**: When the explorer dequeues a state, including the
  initial state, it shall evaluate every declared invariant's condition at
  that state in declaration order using the model expression evaluator and
  YupYup truthiness (only `nil` and `false` are falsy).
- [x] **INVARIANT-3**: When an invariant condition evaluates falsy at an
  explored state, `yup verify` shall exit nonzero and report the invariant's
  name and source location together with the violating state and a
  counterexample trace of transitions from the initial state.
- [x] **INVARIANT-4**: When a completed search finds no invariant violations,
  `yup verify` shall report how many invariants held, qualified as holding at
  every explored state, without language implying unbounded proof, and shall
  exit 0.
- [x] **INVARIANT-5**: When an invariant condition fails to evaluate, the
  exploration shall abort with an evaluation failure retaining the
  source-located diagnostic, the state where evaluation was attempted, and
  the trace leading to that state.
- [x] **INVARIANT-6**: When a model declares two invariants with the same
  name, verification shall fail with a source-located diagnostic naming the
  duplicate before any state is explored.
- [x] **INVARIANT-7**: When a violating state is reachable at multiple
  depths, the reported counterexample trace shall be a shortest one, since
  exploration is breadth-first.
