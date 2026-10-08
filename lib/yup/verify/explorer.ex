defmodule Yup.Verify.Explorer do
  @moduledoc """
  Breadth-first finite-state explorer for model declarations (issue #9).

  Explores from the initial state, deduplicates states by canonical form, and
  records each state's predecessor and producing transition so traces can be
  reconstructed for upcoming invariant work. Enforces a maximum-state cap so
  unbounded models are reported as incomplete searches rather than loops.
  """

  alias Yup.AST.{Model, ModelState, StateUpdate, Transition}
  alias Yup.SourceError
  alias Yup.Verify.{Evaluator, Failure, Result}

  @default_max_states 10_000

  def default_max_states, do: @default_max_states

  # @spec VERIFY-4
  def explore(%Model{} = model, opts \\ []) do
    path = Keyword.get(opts, :path)
    max_states = Keyword.get(opts, :max_states, @default_max_states)

    validate_max_states!(max_states)

    search = build_search(model, path, max_states)
    run(search.queue, search)
  rescue
    error in SourceError ->
      {:error, %Failure{kind: :evaluation, diagnostic: error, state: nil, transition: nil}}
  end

  defp build_search(%Model{} = model, path, max_states) do
    fields = Enum.map(model.states, & &1.name)
    initial = build_initial(model, path, fields)

    canonical = Result.canonical_form(initial)

    %{
      name: model.name,
      path: path,
      max_states: max_states,
      transitions: model.transitions,
      env: Evaluator.env(path, fields, %{}, :transition),
      initial: initial,
      queue: :queue.in(canonical, :queue.new()),
      visited: MapSet.new([canonical]),
      parents: %{canonical => {nil, nil}},
      order: [canonical],
      edges: 0
    }
  end

  # State initializers must be self-contained: Evaluator.eval rejects field
  # reads in :initializer mode (clarifying answer A1).
  defp build_initial(%Model{states: states}, path, fields) do
    Enum.reduce(states, {%{}, MapSet.new()}, fn %ModelState{name: name} = declaration,
                                               {initial, seen} ->
      if MapSet.member?(seen, name) do
        raise source_error(path, declaration.loc, "duplicate state field #{name}")
      end

      env = Evaluator.env(path, fields, %{}, :initializer)
      value = Evaluator.eval(declaration.value, env)
      {Map.put(initial, name, value), MapSet.put(seen, name)}
    end)
    |> elem(0)
  end

  defp run(queue, search) do
    cond do
      :queue.is_empty(queue) ->
        {:ok, result(search, true)}

      MapSet.size(search.visited) >= search.max_states ->
        {:error, incomplete_failure(search)}

      true ->
        {{:value, current}, queue} = :queue.out(queue)
        expand(queue, search, current)
    end
  end

  defp expand(queue, search, current) do
    initial = {:ok, {queue, search}}

    outcome =
      Enum.reduce_while(search.transitions, initial, fn transition, {:ok, {queue, search}} ->
        case apply_transition(transition, Map.new(current), search.env) do
          {:ok, next} ->
            {:cont, {:ok, add_successor(queue, search, current, transition.name, next)}}

          {:error, error} ->
            {:halt, {:error, evaluation_failure(search, current, transition.name, error)}}
        end
      end)

    case outcome do
      {:ok, {queue, search}} -> run(queue, search)
      {:error, failure} -> {:error, failure}
    end
  end

  defp add_successor(queue, search, current, name, next) do
    canonical = Result.canonical_form(next)
    search = %{search | edges: search.edges + 1}

    if MapSet.member?(search.visited, canonical) do
      {queue, search}
    else
      search = %{
        search
        | queue: :queue.in(canonical, queue),
          visited: MapSet.put(search.visited, canonical),
          parents: Map.put(search.parents, canonical, {current, name}),
          order: [canonical | search.order]
      }

      {search.queue, search}
    end
  end

  # Transition bodies apply sequentially: each state update evaluates against
  # the state as mutated by the previous statements of the same body.
  defp apply_transition(%Transition{body: body}, state, env) do
    Enum.reduce_while(body, {:ok, state}, fn
      %StateUpdate{name: name} = update, {:ok, working} ->
        if MapSet.member?(env.fields, name) do
          value = Evaluator.eval(update.value, %{env | state: working})
          {:cont, {:ok, Map.put(working, name, value)}}
        else
          {:halt, {:error, source_error(env.path, update.loc, "assignment to undeclared state field #{name}")}}
        end

      expression, {:ok, working} ->
        Evaluator.eval(expression, %{env | state: working})
        {:cont, {:ok, working}}
    end)
  rescue
    error in SourceError -> {:error, error}
  end

  defp result(search, complete) do
    %Result{
      model_name: search.name,
      path: search.path,
      max_states: search.max_states,
      initial: search.initial,
      states: MapSet.size(search.visited),
      transitions: search.edges,
      complete: complete,
      order: Enum.reverse(search.order),
      parents: search.parents
    }
  end

  # A capped search never counts as verification success (clarifying A3).
  defp incomplete_failure(search) do
    message =
      "model #{search.name}: exploration incomplete: reached state cap (#{search.max_states}) " <>
        "with states still to explore; explored " <>
        Yup.Verify.format_counts(MapSet.size(search.visited), search.edges) <>
        "; increase --max-states to broaden the search"

    %Failure{
      kind: :incomplete,
      diagnostic: SourceError.exception(path: search.path, message: message),
      state: nil,
      transition: nil
    }
  end

  defp evaluation_failure(search, current, name, error) do
    %Failure{
      kind: :evaluation,
      diagnostic: error,
      state: Map.new(current),
      transition: name,
      trace: Result.trace(search.parents, current)
    }
  end

  defp validate_max_states!(max_states) when is_integer(max_states) and max_states >= 1, do: :ok

  defp validate_max_states!(_max_states) do
    raise SourceError.exception(message: "--max-states must be a positive integer")
  end

  defp source_error(path, %{line: line, column: column}, message),
    do: SourceError.exception(path: path, line: line, column: column, message: message)

  defp source_error(path, _loc, message),
    do: SourceError.exception(path: path, message: message)
end
