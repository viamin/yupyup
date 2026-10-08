defmodule Yup.Verify.EvaluatorTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Yup.Parser
  alias Yup.SourceError
  alias Yup.Verify.Evaluator

  defp initializer_expr(source) do
    declaration =
      if String.starts_with?(source, "state ") do
        source
      else
        "state value = " <> source
      end

    {:ok, program} = Parser.parse("model M\n  #{declaration}\nend", path: "model.yup")
    [model] = program.models
    [state] = model.states
    state.value
  end

  defp eval_initializer(source) do
    expr = initializer_expr(source)
    Evaluator.eval(expr, Evaluator.env("model.yup", [], %{}, :initializer))
  end

  defp transition_expr(source) do
    wrapped = """
    model M
      state b = 0
      transition go do
        #{source}
      end
    end
    """

    {:ok, program} = Parser.parse(wrapped, path: "model.yup")
    [model] = program.models
    [transition] = model.transitions
    [update] = transition.body
    update.value
  end

  defp eval_transition(source, state) do
    expr = transition_expr(source)
    env = Evaluator.env("model.yup", Map.keys(state), state, :transition)
    Evaluator.eval(expr, env)
  end

  defp transition_value(source, state) do
    {:ok, program} = Parser.parse(source, path: "model.yup")
    [model] = program.models
    [transition] = model.transitions
    env = Evaluator.env("model.yup", Map.keys(state), state, :transition)

    Enum.reduce_while(transition.body, {:ok, state}, fn
      %Yup.AST.StateUpdate{name: name, value: value}, {:ok, working} ->
        {:cont, {:ok, Map.put(working, name, Evaluator.eval(value, %{env | state: working}))}}

      expr, {:ok, working} ->
        Evaluator.eval(expr, %{env | state: working})
        {:cont, {:ok, working}}
    end)
  end

  # ── literal and operator subset ─────────────────────────────────────

  # @spec VERIFY-2
  test "evaluates integer, atom, string, boolean, and nil literals" do
    assert eval_initializer("7") == 7
    assert eval_initializer(":off") == :off
    assert eval_initializer(~s("ready")) == "ready"
    assert eval_initializer("true") == true
    assert eval_initializer("false") == false
    assert eval_initializer("nil") == nil
  end

  # @spec VERIFY-2
  test "reads current state through bare field names and state.field" do
    state = %{a: 1, b: 0}
    assert eval_transition("state.b = a", state) == 1
    assert eval_transition("state.b = state.a", state) == 1
  end

  # @spec VERIFY-2
  test "evaluates unary and binary operators" do
    state = %{a: 6, b: 3, s: "x", t: "y"}

    assert eval_transition("state.b = a + b", state) == 9
    assert eval_transition("state.b = a - b", state) == 3
    assert eval_transition("state.b = a * b", state) == 18
    assert eval_transition("state.b = a / b", state) == 2
    assert eval_transition("state.b = s + t", state) == "xy"
    assert eval_transition("state.b = a == b", state) == false
    assert eval_transition("state.b = a != b", state) == true
    assert eval_transition("state.b = a < b", state) == false
    assert eval_transition("state.b = a <= 6", state) == true
    assert eval_transition("state.b = a > b", state) == true
    assert eval_transition("state.b = a >= 7", state) == false
    assert eval_transition("state.b = a > 0 and b > 0", state) == true
    assert eval_transition("state.b = a < 0 or b > 0", state) == true
    assert eval_transition("state.b = not (a == b)", state) == true
  end

  # @spec VERIFY-2
  test "evaluates ternaries with language truthiness and lazy branches" do
    state = %{a: 1}

    assert eval_transition("state.b = a == 1 ? :yes : :no", state) == :yes
    assert eval_transition("state.b = a == 2 ? :yes : :no", state) == :no
    # Only nil and false are falsy, so :off is truthy.
    assert eval_transition("state.b = :off ? 1 : 2", state) == 1
    assert eval_transition("state.b = nil ? 1 : 2", state) == 2
    # The untaken branch is not evaluated.
    assert eval_transition("state.b = a == 1 ? :yes : 1 / 0", state) == :yes
  end

  # @spec VERIFY-2
  test "applies transition updates sequentially within one body" do
    source = """
    model Swap
      state a = 1
      state b = 2

      transition swap do
        state.a = b
        state.b = state.a
      end
    end
    """

    assert {:ok, %{a: 2, b: 2}} = transition_value(source, %{a: 1, b: 2})
  end

  # ── rejections with source-located diagnostics ──────────────────────

  # @spec VERIFY-2
  test "rejects calls to top-level def functions with location" do
    expr = transition_expr("state.b = helper(1)")
    env = Evaluator.env("model.yup", [:b], %{b: 0}, :transition)

    assert_raise SourceError, ~r/function calls are not supported in model expressions/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # @spec VERIFY-2
  test "rejects unsupported expression shapes with location" do
    env = Evaluator.env("model.yup", [:b], %{b: 0}, :transition)

    for {source, fragment} <- [
          {"state.b = [1, 2]", "list literals"},
          {"state.b = { a: 1 }", "map literals"},
          {"state.b = Ok(1)", "constructor expressions"},
          {"state.b = { |x| x }", "anonymous functions"}
        ] do
      expr = transition_expr(source)

      assert_raise SourceError, ~r/#{fragment} are not supported in model expressions/, fn ->
        Evaluator.eval(expr, env)
      end
    end
  end

  # @spec VERIFY-2
  test "rejects reads of unknown state fields with location" do
    expr = transition_expr("state.b = missing")
    env = Evaluator.env("model.yup", [:b], %{b: 0}, :transition)

    assert_raise SourceError, ~r/unknown state field missing/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # @spec VERIFY-2
  test "rejects division by zero with location" do
    expr = transition_expr("state.b = 1 / 0")
    env = Evaluator.env("model.yup", [:b], %{b: 0}, :transition)

    assert_raise SourceError, ~r/division by zero in model expression/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # @spec VERIFY-2
  test "rejects arithmetic type errors with location" do
    expr = transition_expr("state.b = 1 + :x")
    env = Evaluator.env("model.yup", [:b], %{b: 0}, :transition)

    assert_raise SourceError, ~r/arithmetic error evaluating '\+' in model expression/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # ── self-contained state initializers ───────────────────────────────

  # @spec VERIFY-3
  test "rejects bare field reads in state initializers" do
    expr = initializer_expr("state b = a + 1")
    env = Evaluator.env("model.yup", [:a, :b], %{}, :initializer)

    assert_raise SourceError, ~r/state initializers cannot read state fields \(a\)/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # @spec VERIFY-3
  test "rejects state.field reads in state initializers" do
    expr = initializer_expr("state b = state.a")
    env = Evaluator.env("model.yup", [:a, :b], %{}, :initializer)

    assert_raise SourceError, ~r/state initializers cannot read state fields \(a\)/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # @spec VERIFY-3
  test "reports unknown names in state initializers as unknown fields" do
    expr = initializer_expr("state b = count_typo + 1")
    env = Evaluator.env("model.yup", [:count, :b], %{}, :initializer)

    assert_raise SourceError, ~r/unknown state field count_typo/, fn ->
      Evaluator.eval(expr, env)
    end
  end

  # @spec VERIFY-3
  test "rejects calls inside state initializers" do
    expr = initializer_expr("state b = helper(2)")
    env = Evaluator.env("model.yup", [:b], %{}, :initializer)

    assert_raise SourceError, ~r/function calls are not supported in model expressions/, fn ->
      Evaluator.eval(expr, env)
    end
  end
end
