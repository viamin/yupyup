# EARS specs: `yup verify` finite-state explorer (#9)

Elicited from issue #9 and its clarifying answers (A1–A5). See
[verify-explorer.md](verify-explorer.md) for the LLD these trace to.

- [x] **VERIFY-1**: When `yup verify` runs on a file, the file shall contain
  exactly one `model` block; zero or multiple models produce a clear
  diagnostic and a nonzero exit, and coexisting executable code is neither
  executed nor compiled.
- [x] **VERIFY-2**: When the model evaluator evaluates an expression, it shall
  accept literals, current-state reads through bare field names or
  `state.field`, unary and binary operators, and ternaries, and shall reject
  calls to top-level `def` functions and all other expression shapes with a
  source-located diagnostic.
- [x] **VERIFY-3**: When a state initializer is evaluated, reads of state
  fields (bare or `state.field`) shall be rejected with a source-located
  diagnostic, since state initializers must be self-contained.
- [x] **VERIFY-4**: When the explorer runs, it shall explore breadth-first
  from the initial state, deduplicate states by canonical form, and record
  predecessor/transition information sufficient to reconstruct the path from
  the initial state to any explored state.
- [x] **VERIFY-5**: When a search completes, `yup verify` shall report the
  model name and explored state and transition counts without claiming any
  property was verified, and shall exit 0.
- [x] **VERIFY-6**: When the search reaches the maximum-state cap with states
  still to explore, `yup verify` shall report the search as incomplete and
  exit nonzero; when the search completes at the cap, it shall report it as
  complete; the cap defaults to 10000 and `--max-states N` overrides it.
- [x] **VERIFY-7**: When an evaluation error aborts exploration, the failure
  shall retain the source-located diagnostic plus the transition trace
  leading to the state where the failing transition was attempted.
