defmodule Yup.Verify.Trace do
  @moduledoc """
  Test-time trace conformance between runtime events and parsed models.

  A conformance session starts every model at its initial state (checking
  declared invariants there, the way `Yup.Verify.Explorer` checks the
  initial state). Each `event/2` call applies the event's mapped model
  transitions through `Yup.Verify.Semantics` — the exact declaration
  semantics `yup verify` uses — then rechecks every model's invariants and
  compares the runtime's claims about the abstract state against the
  post-transition states. Any mismatch is a `%Disagreement{}`.

  This is trace checking over the concrete events it is fed, not a
  refinement proof: nothing here explores the runtime's full behavior, and
  the gluing relation (the claims) is supplied by the caller, not proved.
  Agreement means the checked traces conformed; a disagreement means one
  concrete runtime observation contradicted the model.
  """

  alias Yup.AST.{Invariant, Model, Transition}
  alias Yup.SourceError
  alias Yup.Verify.Semantics

  defmodule Event do
    @moduledoc """
    One runtime observation mapped onto model steps.

    `steps` lists `{model name, transition name}` pairs to apply, in
    order; an empty list is a stuttering step (no model moves). `claims`
    are `{model name, assertion}` pairs describing what the runtime
    observed about the post-event abstract state — `{:equals, field,
    value}`, `{:increments, field}` (by exactly one), or `{:unchanged,
    field}` — checked against the state the mapped transitions produced.
    """

    defstruct [:label, steps: [], claims: []]
  end

  defmodule Disagreement do
    @moduledoc """
    Why a conformance session rejected an event (or the initial state).

    `reason` is `:duplicate_model`, `:unknown_model`, `:unknown_transition`,
    `:unknown_field`, `:invariant` (a mapped step or the initial state
    violated a declared invariant), `:claim` (the runtime's observation
    contradicted the post-transition model state), or `:evaluation`.
    """

    defstruct [
      :reason,
      :detail,
      :label,
      :model,
      :transition,
      :state,
      invariant: nil,
      claim: nil
    ]

    def format(%__MODULE__{} = disagreement) do
      label = disagreement.label && " at event \"#{disagreement.label}\""

      "disagreement (#{disagreement.reason})#{label}: #{disagreement.detail}"
    end
  end

  defstruct [:path, models: %{}, envs: %{}, states: %{}, history: []]

  # @spec OAUTH-TC-5
  def new(models, opts \\ []) when is_list(models) do
    path = Keyword.get(opts, :path)

    with :ok <- check_unique_names(models),
         {:ok, session} <- build_session(models, path),
         :ok <- check_invariants(session, nil, session.states) do
      {:ok, session}
    end
  rescue
    error in SourceError ->
      {:error, %Disagreement{reason: :evaluation, detail: Exception.message(error), label: nil}}
  end

  # @spec OAUTH-TC-5
  # @spec OAUTH-TC-6
  def event(%__MODULE__{} = session, %Event{} = event) do
    with {:ok, moved} <- apply_steps(session, event),
         :ok <- check_invariants(session, event, moved),
         :ok <- check_claims(session, event, moved) do
      {:ok, %{session | states: moved, history: [event.label | session.history]}}
    end
  rescue
    error in SourceError ->
      {:error,
       %Disagreement{reason: :evaluation, detail: Exception.message(error), label: event.label}}
  end

  def state(%__MODULE__{} = session, model_name), do: Map.fetch!(session.states, model_name)

  def states(%__MODULE__{} = session), do: session.states

  def labels(%__MODULE__{} = session), do: Enum.reverse(session.history)

  defp check_unique_names(models) do
    names = Enum.map(models, fn %Model{name: name} -> name end)

    case names -- Enum.uniq(names) do
      [name | _] ->
        {:error,
         %Disagreement{
           reason: :duplicate_model,
           detail: "two models named #{inspect(name)} in the trace session"
         }}

      [] ->
        :ok
    end
  end

  defp build_session(models, path) do
    entries =
      Map.new(models, fn %Model{} = model ->
        {model.name,
         %{
           model: model,
           env: Semantics.transition_env(model, path),
           state: Semantics.initial_state(model, path)
         }}
      end)

    {:ok,
     %__MODULE__{
       path: path,
       models: Map.new(entries, fn {name, entry} -> {name, entry.model} end),
       envs: Map.new(entries, fn {name, entry} -> {name, entry.env} end),
       states: Map.new(entries, fn {name, entry} -> {name, entry.state} end)
     }}
  end

  # Applies the event's mapped transitions, threading the per-model states.
  defp apply_steps(session, event) do
    Enum.reduce_while(event.steps, {:ok, session.states}, fn {model_name, transition_name},
                                                             {:ok, states} ->
      with {:ok, model} <- fetch_model(session, event, model_name),
           {:ok, transition} <- fetch_transition(model, event, model_name, transition_name),
           {:ok, next} <- step(session, event, model, transition, states[model_name]) do
        {:cont, {:ok, Map.put(states, model_name, next)}}
      else
        {:error, %Disagreement{} = disagreement} -> {:halt, {:error, disagreement}}
      end
    end)
  end

  defp fetch_model(session, event, name) do
    case Map.fetch(session.models, name) do
      {:ok, model} ->
        {:ok, model}

      :error ->
        {:error,
         disagreement(:unknown_model, event, "no model named #{inspect(name)} in the session",
           model: name
         )}
    end
  end

  defp fetch_transition(model, event, model_name, transition_name) do
    case Enum.find(model.transitions, &match?(%Transition{name: ^transition_name}, &1)) do
      nil ->
        {:error,
         disagreement(
           :unknown_transition,
           event,
           "model #{model_name} has no transition named #{inspect(transition_name)}",
           model: model_name,
           transition: transition_name
         )}

      transition ->
        {:ok, transition}
    end
  end

  defp step(session, event, model, transition, state) do
    case Semantics.apply(transition, state, session.envs[model.name]) do
      {:ok, next} ->
        {:ok, next}

      {:error, error} ->
        {:error,
         disagreement(:evaluation, event, Exception.message(error),
           model: model.name,
           transition: transition.name
         )}
    end
  end

  defp check_invariants(session, event, states) do
    Enum.reduce_while(session.models, :ok, fn {name, model}, :ok ->
      case Semantics.check_invariants(model.invariants, states[name], session.envs[name]) do
        :ok ->
          {:cont, :ok}

        {:error, {:invariant, %Invariant{} = invariant}} ->
          {:halt,
           {:error,
            disagreement(
              :invariant,
              event,
              "invariant \"#{invariant.name}\" failed at #{name} state " <>
                format_state(states[name]),
              model: name,
              state: states[name],
              invariant: invariant.name
            )}}

        {:error, {:evaluation, error}} ->
          {:halt,
           {:error,
            disagreement(:evaluation, event, Exception.message(error),
              model: name,
              state: states[name]
            )}}
      end
    end)
  end

  # @spec OAUTH-TC-6
  defp check_claims(session, event, moved) do
    Enum.reduce_while(event.claims, :ok, fn {model_name, assertion}, :ok ->
      case check_claim(session, event, moved, model_name, assertion) do
        :ok -> {:cont, :ok}
        {:error, disagreement} -> {:halt, {:error, disagreement}}
      end
    end)
  end

  defp check_claim(session, event, moved, model_name, {:equals, field, value}) do
    with {:ok, actual} <- fetch_field(moved, event, model_name, field) do
      if actual == value do
        :ok
      else
        {:error,
         claim_disagreement(
           event,
           session,
           moved,
           model_name,
           {:equals, field, value},
           "claim #{model_name}.#{field} == #{inspect(value)} failed: " <>
             "model state has #{inspect(actual)}"
         )}
      end
    end
  end

  defp check_claim(session, event, moved, model_name, {:increments, field}) do
    with {:ok, pre} <- fetch_field(session.states, event, model_name, field),
         {:ok, post} <- fetch_field(moved, event, model_name, field) do
      if is_integer(pre) and is_integer(post) and post == pre + 1 do
        :ok
      else
        {:error,
         claim_disagreement(
           event,
           session,
           moved,
           model_name,
           {:increments, field},
           "claim #{model_name}.#{field} increments failed: " <>
             "model state moved #{inspect(pre)} -> #{inspect(post)}"
         )}
      end
    end
  end

  defp check_claim(session, event, moved, model_name, {:unchanged, field}) do
    with {:ok, pre} <- fetch_field(session.states, event, model_name, field),
         {:ok, post} <- fetch_field(moved, event, model_name, field) do
      if post == pre do
        :ok
      else
        {:error,
         claim_disagreement(
           event,
           session,
           moved,
           model_name,
           {:unchanged, field},
           "claim #{model_name}.#{field} unchanged failed: " <>
             "model state moved #{inspect(pre)} -> #{inspect(post)}"
         )}
      end
    end
  end

  defp fetch_field(states, event, model_name, field) do
    with {:ok, model_state} <- fetch_model_state(states, event, model_name) do
      case Map.fetch(model_state, field) do
        {:ok, value} ->
          {:ok, value}

        :error ->
          {:error, unknown_field_disagreement(event, model_name, field)}
      end
    end
  end

  defp unknown_field_disagreement(event, model_name, field) do
    disagreement(
      :unknown_field,
      event,
      "model #{model_name} has no state field #{inspect(field)}",
      model: model_name
    )
  end

  defp fetch_model_state(states, event, model_name) do
    case Map.fetch(states, model_name) do
      {:ok, model_state} -> {:ok, model_state}
      :error -> {:error, unknown_model_disagreement(event, model_name)}
    end
  end

  defp claim_disagreement(event, session, moved, model_name, claim, detail) do
    disagreement(:claim, event, detail,
      model: model_name,
      state: moved[model_name] || session.states[model_name],
      claim: claim
    )
  end

  defp unknown_model_disagreement(event, model_name) do
    disagreement(:unknown_model, event, "no model named #{inspect(model_name)} in the session",
      model: model_name
    )
  end

  defp disagreement(reason, event, detail, opts) do
    %Disagreement{
      reason: reason,
      detail: detail,
      label: event && event.label,
      model: opts[:model],
      transition: opts[:transition],
      state: opts[:state],
      invariant: opts[:invariant],
      claim: opts[:claim]
    }
  end

  defp format_state(state) do
    fields =
      state
      |> Map.to_list()
      |> Enum.sort()
      |> Enum.map_join(", ", fn {name, value} -> "#{name}: #{inspect(value)}" end)

    "{#{fields}}"
  end
end
