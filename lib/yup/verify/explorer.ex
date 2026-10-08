defmodule Yup.Verify.Explorer do
  @moduledoc """
  Breadth-first finite-state explorer for model declarations (issue #9).

  Explores from the initial state, deduplicates states by canonical form, and
  records each state's predecessor and producing transition so traces can be
  reconstructed. Invariant conditions (issue #10) are checked at every
  dequeued state, shortest-first. Enforces a maximum-state cap so unbounded
  models are reported as incomplete searches rather than loops.
  """

  alias Yup.AST.{Invariant, Model}
  alias Yup.SourceError
  alias Yup.Verify.{Failure, Result, Semantics}

  @default_max_states 10_000

  def default_max_states, do: @default_max_states

  # @spec VERIFY-4
  # @spec INVARIANT-2
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
    initial = Semantics.initial_state(model, path)

    canonical = Result.canonical_form(initial)

    %{
      name: model.name,
      path: path,
      max_states: max_states,
      transitions: model.transitions,
      invariants: build_invariants(model, path),
      env: Semantics.transition_env(model, path),
      initial: initial,
      queue: :queue.in(canonical, :queue.new()),
      visited: MapSet.new([canonical]),
      parents: %{canonical => {nil, nil}},
      order: [canonical],
      edges: 0
    }
  end

  # Invariants share the duplicate-name rule state fields already have.
  defp build_invariants(%Model{invariants: invariants}, path) do
    {ordered, _seen} =
      Enum.reduce(invariants, {[], MapSet.new()}, fn %Invariant{name: name} = declaration,
                                                     {ordered, seen} ->
        if MapSet.member?(seen, name) do
          raise source_error(path, declaration.loc, "duplicate invariant name \"#{name}\"")
        end

        {[declaration | ordered], MapSet.put(seen, name)}
      end)

    Enum.reverse(ordered)
  end

  # At the cap we still drain the queue: queued states may only transition
  # back to states we've already visited, in which case the search is
  # complete. Incompleteness is reported the moment an expansion would add
  # a state we have no room for.
  defp run(queue, search) do
    if :queue.is_empty(queue) do
      {:ok, result(search, true)}
    else
      {{:value, current}, queue} = :queue.out(queue)

      case check_invariants(search, current) do
        :ok -> expand(queue, search, current)
        {:error, failure} -> {:error, failure}
      end
    end
  end

  # Invariants are checked as states are dequeued, so the initial state is
  # covered and the first violation found carries a shortest trace (BFS).
  defp check_invariants(%{invariants: []}, _current), do: :ok

  defp check_invariants(search, current) do
    case Semantics.check_invariants(search.invariants, Map.new(current), search.env) do
      :ok ->
        :ok

      {:error, {:invariant, invariant}} ->
        {:error, invariant_failure(search, current, invariant)}

      {:error, {:evaluation, error}} ->
        {:error, evaluation_failure(search, current, nil, error)}
    end
  end

  defp expand(queue, search, current) do
    initial = {:ok, {queue, search}}

    outcome =
      Enum.reduce_while(search.transitions, initial, fn transition, {:ok, {queue, search}} ->
        case Semantics.apply(transition, Map.new(current), search.env) do
          {:ok, next} ->
            case add_successor(queue, search, current, transition.name, next) do
              {:ok, {queue, search}} -> {:cont, {:ok, {queue, search}}}
              {:incomplete, search} -> {:halt, {:error, incomplete_failure(search)}}
            end

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

    cond do
      MapSet.member?(search.visited, canonical) ->
        {:ok, {queue, %{search | edges: search.edges + 1}}}

      MapSet.size(search.visited) >= search.max_states ->
        {:incomplete, search}

      true ->
        search = %{
          search
          | edges: search.edges + 1,
            queue: :queue.in(canonical, queue),
            visited: MapSet.put(search.visited, canonical),
            parents: Map.put(search.parents, canonical, {current, name}),
            order: [canonical | search.order]
        }

        {:ok, {search.queue, search}}
    end
  end

  # Transition bodies apply sequentially: each state update evaluates against
  # the state as mutated by the previous statements of the same body
  # (Yup.Verify.Semantics.apply/3, shared with the trace checker).

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
      parents: search.parents,
      invariants: Enum.map(search.invariants, & &1.name)
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

  # A counterexample is a concrete reachable state, so the failure reports
  # it and the trace without any boundedness qualifier.
  defp invariant_failure(search, current, invariant) do
    message = "invariant \"#{invariant.name}\" failed"

    %Failure{
      kind: :invariant,
      diagnostic: source_error(search.path, invariant.loc, message),
      state: Map.new(current),
      transition: nil,
      invariant: invariant.name,
      trace: Result.trace(search.parents, current)
    }
  end

  defp validate_max_states!(max_states) when is_integer(max_states) and max_states >= 1, do: :ok

  defp validate_max_states!(_max_states) do
    raise SourceError.exception(message: "--max-states must be a positive integer")
  end

  defp source_error(path, %{line: line, column: column}, message),
    do: SourceError.exception(path: path, line: line, column: column, message: message)

  defp source_error(path, %{line: line}, message),
    do: SourceError.exception(path: path, line: line, message: message)

  defp source_error(path, _loc, message),
    do: SourceError.exception(path: path, message: message)
end
