# LLD: `yup verify` invariants (#10)

Status: implemented (bootstrap milestone). Traces to ROADMAP item 12 and
issue #10, building on the #9 explorer (see
[verify-explorer.md](verify-explorer.md)). This LLD supersedes the #9 A2
parenthetical "there are no invariants yet" and the "upcoming invariant work"
notes: invariant checking now exists.

## Goal

Models can declare named invariants, and `yup verify` checks every invariant
at every state it explores. A failing invariant exits nonzero and reports the
invariant's name and source location together with a readable counterexample:
the violating state and the transition trace from the initial state.

## Decisions (from elicited intent and the issue's open design questions)

- **Syntax.** `invariant "name" do expr end` inside a `model` block. The name
  is a string label reported verbatim in failures. The body is a single
  expression line; the block closes with its own `end`. This follows the
  issue's illustrative syntax but uses the language's `or`/`and`/`not`
  keywords instead of `||`, consistent with the rest of YupYup.
- **Expression language inside invariants (issue open question).** Exactly the
  #9 model expression subset (A1 boundary): literals, current-state reads via
  bare field names or `state.field`, unary/binary operators, and ternaries.
  Calls, dot calls, and every other expression shape are rejected with
  source-located diagnostics by the existing `Yup.Verify.Evaluator`. No new
  expression forms were added for invariants.
- **Semantics.** An invariant holds at a state when its condition evaluates
  truthy under YupYup truthiness (only `nil` and `false` are falsy). It is a
  model property checked during finite-state exploration only — it never
  compiles into executable code and is not a production assertion.
- **Check timing.** The explorer checks every declared invariant, in
  declaration order, at each state as it is dequeued — which includes the
  initial state. Because exploration is breadth-first, the first violation
  found carries a shortest counterexample trace.
- **Failure output (issue open question: trace formatting).** The diagnostic
  line carries the invariant's source location (the `invariant "..." do`
  header line) and the message `invariant "name" failed`. Two indented
  context lines follow: `counterexample state {field: value, ...}` and
  `reached via: transition, ...` (or `reached via: initial state`). A
  counterexample is a concrete reachable state, so it needs no boundedness
  qualifier.
- **Success output.** When a completed search finds no violations, the counts
  line gains `; N invariant(s) held at every explored state`. The wording is
  deliberately bounded to the explored state space and never says "verified"
  or "proved"; an incomplete (capped) search reports incompleteness and makes
  no invariant claim at all.
- **Evaluation errors inside invariants.** A condition that fails to evaluate
  (division by zero, unknown field, unsupported shape) aborts exploration as
  an evaluation failure that retains the diagnostic, the state, and the trace
  to it (`while evaluating an invariant at state ...`).
- **Duplicate names.** Two invariants with the same name in one model are
  rejected at exploration setup with a source-located diagnostic naming the
  duplicate, mirroring duplicate state field handling.
- **Non-goals.** Temporal properties, fairness, refinement, and SMT-backed
  proof remain out of scope, per the issue.

## Local design choices

- `Yup.AST.Invariant{name, condition, loc}` joins the model AST family;
  `Yup.AST.Model` gains `invariants: []` in declaration order.
- Invariant conditions reuse `Yup.Runtime.truthy?/1` so hold/fail matches
  documented language truthiness.
- The failure taxonomy gains `kind: :invariant` plus an `invariant` name
  field on `Yup.Verify.Failure`; `Yup.Verify.Result` carries the list of held
  invariant names.
- Invariant checks run before successor generation on each dequeued state, so
  an invariant failure is reported even when the same expansion would have
  tripped the state cap afterwards. A violation in a queued state that the
  cap never dequeues is reported as an incomplete search, not a failure.

## Module map (delta over #9)

```text
Yup.Parser            invariant "name" do expr end inside model bodies
Yup.AST.Invariant     named invariant node (name, condition, loc)
Yup.AST.Model         invariants: [] in declaration order
Yup.Verify.Explorer   checks invariants per dequeued state; wraps failures
Yup.Verify.Failure    kind: :invariant + invariant name; counterexample format
Yup.Verify.Result     invariants: held invariant names
Yup.Verify            format_result appends the held-invariant suffix
```
