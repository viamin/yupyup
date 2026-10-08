defmodule Yup.Verify.Semantics do
  @moduledoc """
  Model-declaration semantics shared by the explorer and the trace checker.

  Initial-state construction, transition application, and invariant
  evaluation live here so `Yup.Verify.Explorer` (full state-space search)
  and `Yup.Verify.Trace` (single-trace conformance) step models through
  the exact same code. Evaluation errors surface as `{:error,
  %Yup.SourceError{}}` tuples so callers can wrap them in their own
  failure shapes.
  """

  alias Yup.AST.{Invariant, Model, ModelState, StateUpdate, Transition}
  alias Yup.SourceError
  alias Yup.Verify.Evaluator

  # State initializers must be self-contained: Evaluator.eval rejects field
  # reads in :initializer mode (clarifying answer A1).
  def initial_state(%Model{states: states}, path) do
    fields = Enum.map(states, & &1.name)

    Enum.reduce(states, {%{}, MapSet.new()}, fn %ModelState{name: name} = declaration,
                                                {initial, seen} ->
      if MapSet.member?(seen, name) do
        loc = declaration.loc && %{line: declaration.loc.line}
        raise source_error(path, loc, "duplicate state field #{name}")
      end

      env = Evaluator.env(path, fields, %{}, :initializer)
      value = Evaluator.eval(declaration.value, env)
      {Map.put(initial, Evaluator.field_name(name), value), MapSet.put(seen, name)}
    end)
    |> elem(0)
  end

  def transition_env(%Model{states: states}, path) do
    Evaluator.env(path, Enum.map(states, & &1.name), %{}, :transition)
  end

  # Transition bodies apply sequentially: each state update evaluates against
  # the state as mutated by the previous statements of the same body.
  def apply(%Transition{body: body}, state, env) do
    Enum.reduce_while(body, {:ok, state}, fn
      %StateUpdate{name: name} = update, {:ok, working} ->
        field = Evaluator.field_name(name)

        if MapSet.member?(env.fields, field) do
          value = Evaluator.eval(update.value, %{env | state: working})
          {:cont, {:ok, Map.put(working, field, value)}}
        else
          {:halt,
           {:error,
            source_error(env.path, update.loc, "assignment to undeclared state field #{name}")}}
        end

      expression, {:ok, working} ->
        Evaluator.eval(expression, %{env | state: working})
        {:cont, {:ok, working}}
    end)
  rescue
    error in SourceError -> {:error, error}
  end

  # Invariants are checked in declaration order against the given state;
  # a falsy condition reports the invariant, a raising condition reports
  # the evaluation error. Callers translate both into their failure types.
  def check_invariants(invariants, state, env) do
    Enum.reduce_while(invariants, :ok, fn %Invariant{} = invariant, :ok ->
      case eval_condition(invariant.condition, %{env | state: state}) do
        {:ok, value} ->
          if Yup.Runtime.truthy?(value) do
            {:cont, :ok}
          else
            {:halt, {:error, {:invariant, invariant}}}
          end

        {:error, error} ->
          {:halt, {:error, {:evaluation, error}}}
      end
    end)
  end

  defp eval_condition(condition, env) do
    {:ok, Evaluator.eval(condition, env)}
  rescue
    error in SourceError -> {:error, error}
  end

  defp source_error(path, %{line: line, column: column}, message),
    do: SourceError.exception(path: path, line: line, column: column, message: message)

  defp source_error(path, %{line: line}, message),
    do: SourceError.exception(path: path, line: line, message: message)

  defp source_error(path, _loc, message),
    do: SourceError.exception(path: path, message: message)
end
