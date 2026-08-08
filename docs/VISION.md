# YupYup Vision

YupYup is an experimental general-purpose programming language targeting the Erlang BEAM. It starts as a toy, but the experiment is technically serious: can a language combine Ruby-like joy, Erlang-like resilience, gradual structural typing, and formal methods that feel closer to debugging than ceremony?

## Influences

YupYup borrows from Erlang/OTP: isolated processes, message passing, supervision, immutable data, pattern matching, "let it crash" failure handling, and reliability under concurrency and load.

It borrows from Ruby ergonomics: readable syntax, low ceremony, dot notation, chained calls, blocks, first-class functions, duck typing, and expressive collections. YupYup is Ruby-shaped, not Ruby-compatible. It should not inherit mutable object graphs, global mutable state, monkey patching, or class inheritance as the primary abstraction.

It borrows from gradual and structural typing. Untyped code should remain pleasant. Typed code should be native YupYup syntax, not an external annotation layer. Structural types should preserve the duck-typing philosophy, and refined types may eventually express propositions such as:

```yup
type Money = Int where self >= 0
```

## Values And Actors

The guiding rule is:

```text
Values don't mutate.
Actors transition.
```

Ordinary values should be immutable. Stateful behavior should primarily live in actors/processes whose transitions are explicit and whose communication maps to BEAM process semantics.

## Formal Methods As Native Concepts

YupYup should eventually let programmers write executable systems, abstract models, properties, assumptions, monitors, and refinement relationships in one language. One language does not mean one abstraction level. Formal methods are useful partly because they let programmers abstract away irrelevant implementation detail.

A future YupYup system may include an executable actor and a simpler model:

```yup
model TransferProtocol
  state status: [:pending, :reserved, :credited, :complete]

  transition reserve
    from :pending
    to :reserved
  end
end
```

The exact syntax is unresolved. The architectural commitment is that models can be more abstract than implementations, and future refinement concepts should make that relationship explicit rather than magical.

## Lessons To Preserve

From TLA+, YupYup should learn state-transition systems, safety and liveness properties, fairness, explicit assumptions, refinement, and counterexample traces.

From Alloy, YupYup should learn that verification is also exploratory. A future `yup find` should search for a world or behavior satisfying constraints, not only prove or disprove assertions.

From P, YupYup should learn actor-oriented modeling: communicating asynchronous state machines, explicit states, monitors, modeled environments, nondeterminism, and systematic event schedule exploration.

From Dafny, Verus, and related code verifiers, YupYup should learn that code-level reasoning and system-level model checking are different engines with different strengths. The language should eventually present them as related parts of a continuum.

## Verification UX

YupYup must not imply an unbounded proof when it only searched a bounded state space. Successful verification should report bounds and assumptions. Failed verification should prioritize counterexample traces that feel debuggable.

The long-term continuum is:

```text
dynamic code
  -> structural types
  -> refined types
  -> pre/postconditions
  -> state invariants
  -> behavioral models
  -> temporal properties
  -> model checking / constraint finding
  -> refinement between models and implementations
```

Developers should be able to use only as much of this continuum as they need.

