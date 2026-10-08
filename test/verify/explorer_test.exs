defmodule Yup.Verify.ExplorerTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Yup.Parser
  alias Yup.Verify.{Explorer, Failure, Result}

  @light """
  model Light
    state value = :off

    transition toggle do
      state.value = value == :off ? :on : :off
    end
  end
  """

  @traffic """
  model TrafficLight
    state color = :red

    transition advance do
      state.color = color == :red ? :green : color == :green ? :yellow : :red
    end
  end
  """

  @counter """
  model Counter
    state count = 0

    transition increment do
      state.count = count + 1
    end
  end
  """

  @boomer """
  model Boomer
    state n = 0

    transition increment do
      state.n = n == 3 ? 1 / 0 : n + 1
    end
  end
  """

  @light_invariants """
  model Light
    state value = :off

    invariant "value is on or off" do
      value == :on or value == :off
    end

    transition toggle do
      state.value = value == :off ? :on : :off
    end
  end
  """

  @counter_bound """
  model Counter
    state count = 0

    invariant "count stays below 3" do
      count < 3
    end

    transition increment do
      state.count = count + 1
    end
  end
  """

  defp explore(source, opts \\ []) do
    {:ok, program} = Parser.parse(source, path: "model.yup")
    [model] = program.models
    Explorer.explore(model, Keyword.put(opts, :path, "model.yup"))
  end

  # ── breadth-first exploration and counts ────────────────────────────

  # @spec VERIFY-4
  test "explores the light model exhaustively with counts" do
    assert {:ok, %Result{} = result} = explore(@light)

    assert result.model_name == "Light"
    assert Result.complete?(result)
    assert result.states == 2
    assert result.transitions == 2
  end

  # @spec VERIFY-4
  test "lists explored states with deterministic ids" do
    assert {:ok, result} = explore(@light)

    states = Result.states(result)
    assert length(states) == 2
    assert Enum.map(states, &elem(&1, 1)) |> Enum.sort() == [%{value: :off}, %{value: :on}]

    ids = Enum.map(states, &elem(&1, 0))
    assert length(ids) == length(Enum.uniq(ids))
    assert Result.state_id(%{value: :on}) in ids
  end

  # @spec VERIFY-4
  test "deduplicates states by canonical form regardless of field order" do
    source = """
    model Pair
      state a = 0
      state b = 0

      transition bump do
        state.a = a == 1 ? 0 : a + 1
        state.b = a == 0 ? 1 : 0
      end
    end
    """

    # From {0, 0}: bump -> {1, 0}; then -> {0, 1}; then -> {1, 0}. The final
    # transition deduplicates a previously visited canonical state.
    assert {:ok, result} = explore(source)
    assert result.states == 3
    assert result.transitions == 3
  end

  # @spec VERIFY-4
  test "retains shortest-path traces via predecessors" do
    assert {:ok, result} = explore(@traffic)

    assert result.states == 3
    assert result.transitions == 3
    assert {:ok, []} = Result.trace_to(result, %{color: :red})
    assert {:ok, ["advance"]} = Result.trace_to(result, %{color: :green})
    assert {:ok, ["advance", "advance"]} = Result.trace_to(result, %{color: :yellow})
    assert {:error, :unknown_state} = Result.trace_to(result, %{color: :purple})
  end

  # @spec VERIFY-4
  test "orders traces from the initial state through distinct transitions" do
    parents = %{
      [state: :initial] => {nil, nil},
      [state: :middle] => {[state: :initial], "first"},
      [state: :final] => {[state: :middle], "second"}
    }

    assert Result.trace(parents, state: :final) == ["first", "second"]
  end

  # @spec VERIFY-4
  test "keeps the initial state on the result" do
    assert {:ok, result} = explore(@light)
    assert result.initial == %{value: :off}
  end

  # ── bounded exploration cap ─────────────────────────────────────────

  # @spec VERIFY-6
  test "reports an incomplete search when the cap leaves states pending" do
    assert {:error, %Failure{kind: :incomplete} = failure} = explore(@counter, max_states: 5)

    assert failure.diagnostic.message =~ "exploration incomplete"
    assert failure.diagnostic.message =~ "state cap (5)"
    assert failure.diagnostic.message =~ "5 states, 4 transitions"
  end

  # @spec VERIFY-6
  test "reports a complete search when the queue drains exactly at the cap" do
    assert {:ok, %Result{} = result} = explore(@light, max_states: 2)
    assert Result.complete?(result)
    assert result.states == 2
  end

  # @spec VERIFY-6
  test "treats the cap as incomplete when even the initial state is pending" do
    assert {:error, %Failure{kind: :incomplete} = failure} = explore(@light, max_states: 1)

    assert failure.diagnostic.message =~ "explored 1 state, 0 transitions"
  end

  # @spec VERIFY-6
  test "defaults to the documented maximum-state cap" do
    assert Explorer.default_max_states() == 10_000

    assert {:error, %Failure{kind: :incomplete} = failure} = explore(@counter)
    assert failure.diagnostic.message =~ "state cap (10000)"
    assert failure.diagnostic.message =~ "10000 states, 9999 transitions"
  end

  # @spec VERIFY-6
  test "rejects non-positive max-states values" do
    for max_states <- [0, -1] do
      assert {:error, %Failure{kind: :evaluation} = failure} =
               explore(@light, max_states: max_states)

      assert failure.diagnostic.message =~ "--max-states must be a positive integer"
    end
  end

  # ── failures retain trace information ───────────────────────────────

  # @spec VERIFY-7
  test "evaluation failures keep the trace to the failing state" do
    assert {:error, %Failure{kind: :evaluation} = failure} = explore(@boomer)

    assert failure.state == %{n: 3}
    assert failure.transition == "increment"
    assert failure.trace == ["increment", "increment", "increment"]
    assert failure.diagnostic.message =~ "division by zero in model expression"
    assert failure.diagnostic.line != nil
  end

  # @spec VERIFY-7
  test "evaluation failures format with location and trace context" do
    {:error, failure} = explore(@boomer)
    formatted = Failure.format(failure)

    assert formatted =~ "model.yup:5:"
    assert formatted =~ "division by zero in model expression"
    assert formatted =~ "while applying transition increment to state {n: 3}"
    assert formatted =~ "reached via: increment, increment, increment"
  end

  # @spec VERIFY-7
  test "failures before exploration format as diagnostics only" do
    source = """
    model Light
      state value = :off
      state value = :on
    end
    """

    assert {:error, %Failure{kind: :evaluation} = failure} = explore(source)
    assert failure.trace == []
    assert failure.diagnostic.message =~ "duplicate state field value"
    assert Failure.format(failure) =~ "model.yup:3: duplicate state field value"
  end

  # @spec VERIFY-7
  test "rejects updates to undeclared state fields with location" do
    source = """
    model Light
      state value = :off

      transition typo do
        state.valua = :on
      end
    end
    """

    assert {:error, %Failure{kind: :evaluation} = failure} = explore(source)
    assert failure.diagnostic.message =~ "assignment to undeclared state field valua"
  end

  # ── invariant checking ──────────────────────────────────────────────

  # @spec INVARIANT-2
  test "checks a passing invariant at every explored state" do
    assert {:ok, %Result{} = result} = explore(@light_invariants)

    assert result.states == 2
    assert result.invariants == ["value is on or off"]
  end

  # @spec INVARIANT-2
  test "checks invariants in declaration order and records held names" do
    source = """
    model Light
      state value = :off

      invariant "on or off" do
        value == :on or value == :off
      end

      invariant "not purple" do
        value != :purple
      end
    end
    """

    assert {:ok, result} = explore(source)
    assert result.invariants == ["on or off", "not purple"]
  end

  # @spec INVARIANT-2
  test "checks invariants at the initial state when there are no transitions" do
    source = """
    model Light
      state value = :off

      invariant "starts off" do
        value == :off
      end
    end
    """

    assert {:ok, result} = explore(source)
    assert result.states == 1
    assert result.invariants == ["starts off"]
  end

  # @spec INVARIANT-2
  test "uses language truthiness for invariant conditions" do
    source = """
    model Truthy
      state value = :off

      invariant "atoms are truthy" do
        value
      end
    end
    """

    assert {:ok, result} = explore(source)
    assert result.invariants == ["atoms are truthy"]
  end

  # @spec INVARIANT-2
  test "fails when the condition evaluates to nil" do
    source = """
    model NilState
      state value = nil

      invariant "value present" do
        value
      end
    end
    """

    assert {:error, %Failure{kind: :invariant, invariant: "value present"}} = explore(source)
  end

  # @spec INVARIANT-3
  test "reports initial-state violations with an empty trace" do
    source = """
    model Light
      state value = :purple

      invariant "value is on or off" do
        value == :on or value == :off
      end

      transition toggle do
        state.value = :off
      end
    end
    """

    assert {:error, %Failure{kind: :invariant} = failure} = explore(source)

    assert failure.invariant == "value is on or off"
    assert failure.state == %{value: :purple}
    assert failure.trace == []
    assert failure.diagnostic.line == 4
    assert failure.diagnostic.message =~ ~s/invariant "value is on or off" failed/
  end

  # @spec INVARIANT-3
  test "formats invariant failures with the counterexample trace" do
    assert {:error, %Failure{} = failure} = explore(@counter_bound)

    formatted = Failure.format(failure)

    assert formatted =~ "model.yup:4:1:"
    assert formatted =~ ~s/invariant "count stays below 3" failed/
    assert formatted =~ "counterexample state {count: 3}"
    assert formatted =~ "reached via: increment, increment, increment"
  end

  # @spec INVARIANT-7
  test "reports a shortest counterexample when violations sit at different depths" do
    source = """
    model Counter
      state count = 0

      invariant "count stays below 3" do
        count < 3
      end

      transition increment do
        state.count = count + 1
      end

      transition jump do
        state.count = count + 3
      end
    end
    """

    assert {:error, %Failure{kind: :invariant} = failure} = explore(source)

    assert failure.state == %{count: 3}
    assert failure.trace == ["jump"]
  end

  # @spec INVARIANT-3
  test "reports the first failing invariant in declaration order" do
    source = """
    model Light
      state value = :off

      invariant "holds" do
        value == :off
      end

      invariant "fails" do
        value == :purple
      end
    end
    """

    assert {:error, %Failure{kind: :invariant} = failure} = explore(source)
    assert failure.invariant == "fails"
  end

  # @spec INVARIANT-5
  test "evaluation errors inside invariants keep the state and trace" do
    source = """
    model Boomer
      state count = 0

      invariant "no division by zero" do
        1 / 0 == 1
      end

      transition increment do
        state.count = count + 1
      end
    end
    """

    assert {:error, %Failure{kind: :evaluation} = failure} = explore(source)

    assert failure.state == %{count: 0}
    assert failure.trace == []
    assert failure.transition == nil
    assert failure.diagnostic.message =~ "division by zero in model expression"

    formatted = Failure.format(failure)

    assert formatted =~ "model.yup:5:"
    assert formatted =~ "while evaluating an invariant at state {count: 0}"
    assert formatted =~ "reached via: initial state"
  end

  # @spec INVARIANT-5
  test "unknown fields in invariants are source-located evaluation errors" do
    source = """
    model Light
      state value = :off

      invariant "typo" do
        valu == :off
      end
    end
    """

    assert {:error, %Failure{kind: :evaluation} = failure} = explore(source)
    assert failure.diagnostic.message =~ "unknown state field valu"
    assert failure.diagnostic.line == 5
  end

  # @spec INVARIANT-6
  test "rejects duplicate invariant names with location" do
    source = """
    model Light
      state value = :off

      invariant "same" do
        value == :off
      end

      invariant "same" do
        value == :on
      end
    end
    """

    assert {:error, %Failure{kind: :evaluation} = failure} = explore(source)
    assert failure.diagnostic.message =~ ~s/duplicate invariant name "same"/
    assert failure.diagnostic.line == 8
  end

  # @spec INVARIANT-2
  test "checks invariants when the search completes exactly at the cap" do
    assert {:ok, %Result{} = result} = explore(@light_invariants, max_states: 2)

    assert Result.complete?(result)
    assert result.invariants == ["value is on or off"]
  end

  # ── self-contained initializers ─────────────────────────────────────

  # @spec VERIFY-3
  test "rejects state initializers that read other state fields" do
    source = """
    model Chain
      state a = 1
      state b = a + 1
    end
    """

    assert {:error, %Failure{kind: :evaluation} = failure} = explore(source)
    assert failure.diagnostic.message =~ "state initializers cannot read state fields (a)"
    assert failure.diagnostic.line == 3
  end
end
