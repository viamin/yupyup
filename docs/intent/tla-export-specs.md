# EARS specs: TLA+ export (#20)

Elicited from issue #20 and its acceptance criteria. See
[tla-export.md](tla-export.md) for the LLD these trace to, and
[verify-invariants-specs.md](verify-invariants-specs.md) for the `yup verify`
invariant specs whose results this export cross-checks.

- [x] **TLA-1**: When `yup export tla FILE` is given a file containing
  exactly one model whose declarations are all exportable, it shall write a
  complete TLA+ module to stdout — named after the model, declaring the
  state fields as `VARIABLES` in declaration order, the initializer values
  as `Init`, one next-state action per transition, and one numbered
  `Invariant` definition per declared invariant — and exit 0.
- [x] **TLA-2**: When a transition body assigns state fields, the exported
  action shall constrain each assigned field's primed value to the
  translated expression, keep fields the body does not assign `UNCHANGED`,
  and read a field assigned earlier in the same body at its primed value,
  preserving YupYup's sequential update semantics.
- [x] **TLA-3**: When an exported expression uses only supported syntax, the
  translation shall be semantically equivalent TLA+: equality and
  comparisons map to TLA+ operators (`<=` to `=<`, `!=` to `#`), integer
  division `/` maps to `div`, atoms map to distinct TLA+ strings, and
  `and`/`or`/`not` and ternary conditions preserve YupYup truthiness by
  testing operands that are not statically boolean against `FALSE`.
- [x] **TLA-4**: When any part of the model is not exportable — string or
  `nil` literals, unsupported expression shapes, assigning the same field
  more than once in one transition, or names that cannot map to TLA+
  identifiers or that collide with generated definitions — the export shall
  fail with a source-located diagnostic naming the problem, and the command
  shall exit nonzero without emitting a module.
- [x] **TLA-5**: When the same model is exported more than once, the
  generated module text shall be byte-for-byte identical, with every line
  derived from declaration order rather than ambient state.
- [x] **TLA-6**: When the source file does not contain exactly one model
  block, the export shall fail with a diagnostic stating how many models
  were found.
