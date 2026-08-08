# YupYup Roadmap

GitHub issues are intended to be the source of truth for actionable work once they exist. This document records the broad milestone order.

1. Expand the core expression language, bindings, literals, and diagnostics.
2. Establish first-class functions and Ruby-style blocks.
3. Define dot-call semantics and chaining for immutable values.
4. Add immutable collections and functional collection operations.
5. Add pattern matching and immutable product types.
10. ~~Add abstract model and transition AST.~~ (done, #8)
7. Experiment with refined types.
8. Introduce actor/process semantics on the BEAM.
9. Add actor request/reply semantics, crash semantics, links, monitors, and supervision.
10. Add abstract model and transition AST.
11. Build a tiny finite-state explorer for `yup verify`.
12. Add invariants, nondeterminism, modeled environments, assumption reporting, `yup find`, monitors, and refinement research.

Syntax and semantics should remain reversible while implementation experience is still sparse.

