# LLD: `yup verify` finite-state explorer (#9)

Status: implemented (bootstrap milestone). Traces to ROADMAP item 11 and the
issue #9 clarifying answers (A1–A5) recorded on the GitHub issue.

## Goal

`yup verify FILE` explores the reachable state space of the single explicit
`model` block in `FILE` using breadth-first search and prints concise,
human-readable counts. It does not execute or compile the executable code that
may coexist in the file.

## Decisions (from elicited intent)

- **Model evaluator boundary (A1).** The evaluator supports exactly the model
  expression subset: literals, current-state reads through bare field names or
  `state.field`, unary and binary operators, and ternaries. Calls to top-level
  `def` functions and every other expression shape are rejected with a
  source-located diagnostic. The evaluator lives in `Yup.Verify.Evaluator` and
  is fully separate from BEAM compilation. State initializers must be
  self-contained: reading state fields (bare or `state.field`) inside a state
  initializer is rejected with a source-located diagnostic.
- **Output format and exit codes (A2).** Concise human-readable text only;
  JSON is deferred. A completed search reports the model name and explored
  state and transition counts and never claims a property was verified (there
  are no invariants yet). Exit 0 for a completed search; nonzero for parse or
  evaluation errors and incomplete searches.
- **Bounded exploration cap (A3).** The search enforces a maximum-state cap
  (`Yup.Verify.Explorer.default_max_states/0`, currently 10000) overridable
  with `--max-states N`. Reaching the cap while states remain to be explored
  reports an incomplete search and exits nonzero; a search that drains the
  queue at exactly the cap is complete. A capped, incomplete search is never
  described as verification success.
- **Multiple models and mixed files (A4).** `yup verify FILE` requires exactly
  one `model` block; zero or multiple models produce a clear diagnostic.
  Executable code may coexist in the file but is not executed or compiled.
  This milestone explores the explicit model only; deriving a model from class
  or actor behavior is recorded on the roadmap, as is checking invariants and
  constraints declared within such a definition.
- **Failing-path tests (A5).** No invariant or `never(...)` syntax was added
  for testing; failure paths are exercised through evaluation errors and
  incomplete searches.

## Local design choices

- **Breadth-first search** from the initial state so any future
  counterexample trace is shortest-first. Transitions are applied in
  declaration order, so exploration order is deterministic.
- **Canonicalization.** A state is a map of declared field names to values.
  The canonical form is the field list sorted by name; canonical forms are the
  visited-set keys, so deduplication is exact (no hash collisions). A
  deterministic `:erlang.phash2` of the canonical form serves as a compact
  state id for output and traces.
- **Predecessor tracking.** The explorer records, for every canonical state,
  the parent canonical state and the transition name that produced it. This is
  enough to reconstruct the transition path from the initial state to any
  explored state, which upcoming invariant work will use for counterexamples.
  Evaluation failures keep the path to the state where the failing transition
  was attempted plus the failing transition name.
- **Sequential transition bodies.** `state.x = expr` statements in a
  transition body apply in order: each right-hand side sees the state as
  mutated by the previous statements of the same body.
- **Bare expression statements** inside a transition body parse (the parser
  keeps them for future guard syntax) but have no state effect; the explorer
  evaluates them for diagnostics and discards the value.

## Module map

```text
Yup.CLI                yup verify [--max-states N] FILE  (exit codes, output)
Yup.Verify             entry: verify_file/2, verify_program/2, format_result/1
Yup.Verify.Evaluator   model expression subset evaluation (raises SourceError)
Yup.Verify.Explorer    BFS queue, visited set, cap, failure wrapping
Yup.Verify.Result      exploration outcome: counts, states, trace_to/2
Yup.Verify.Failure     error outcome: diagnostic + trace/transition/state
```

`Yup.Runtime.truthy?/1` is shared between the language runtime and the
evaluator so ternary truthiness matches documented language truthiness (only
`nil` and `false` are falsy).
