defmodule Yup.Verify.TraceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Yup.Verify.Trace
  alias Yup.Verify.Trace.Event

  @counter """
  model Counter
    state count = 0
    state frozen = :no

    invariant "count stays below two" do
      count < 2
    end

    transition tick do
      state.count = count + 1
    end

    transition idle do
    end
  end
  """

  @guarded """
  model Guarded
    state hits = 0

    invariant "at most one hit" do
      hits <= 1
    end

    transition hit do
      state.hits = hits == 0 ? hits + 1 : hits
    end
  end
  """

  @bad_initial """
  model BadInitial
    state count = 2

    invariant "count stays below two" do
      count < 2
    end

    transition idle do
    end
  end
  """

  @bad_body """
  model BadBody
    state count = 0

    transition broken do
      state.bogus = 1
    end
  end
  """

  defp model(source) do
    {:ok, program} = Yup.Parser.parse(source, path: "model.yup")
    hd(program.models)
  end

  defp event(label, steps, claims) do
    %Event{label: label, steps: steps, claims: claims}
  end

  # ── session setup ───────────────────────────────────────────────────

  # @spec OAUTH-TC-5
  test "new starts each model at its verified initial state" do
    {:ok, session} = Trace.new([model(@counter), model(@guarded)])

    assert Trace.state(session, "Counter") == %{count: 0, frozen: :no}
    assert Trace.state(session, "Guarded") == %{hits: 0}
    assert Map.keys(Trace.states(session)) == ["Counter", "Guarded"]
    assert Trace.labels(session) == []
  end

  test "new rejects two models with the same name" do
    assert {:error, %Trace.Disagreement{reason: :duplicate_model} = disagreement} =
             Trace.new([model(@counter), model(@counter)])

    assert Trace.Disagreement.format(disagreement) =~ "two models named \"Counter\""
  end

  # @spec OAUTH-TC-5
  test "new checks invariants at the initial state" do
    assert {:error, %Trace.Disagreement{reason: :invariant} = disagreement} =
             Trace.new([model(@bad_initial)])

    assert disagreement.invariant == "count stays below two"
    assert disagreement.state == %{count: 2}
    assert Trace.Disagreement.format(disagreement) =~ "count stays below two"
  end

  # ── stepping mapped transitions ─────────────────────────────────────

  test "steps run the mapped transitions in order" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:ok, session} =
             Trace.event(session, event("tick", [{"Counter", "tick"}], []))

    assert Trace.state(session, "Counter") == %{count: 1, frozen: :no}
    assert Trace.labels(session) == ["tick"]
  end

  # @spec OAUTH-TC-5
  test "steps reuse the explorer's transition semantics" do
    # The guarded transition body is a ternary over current state, the
    # same expression semantics yup verify explores; a second hit must
    # no-op exactly the way the model says.
    {:ok, session} = Trace.new([model(@guarded)])

    assert {:ok, session} = Trace.event(session, event("hit", [{"Guarded", "hit"}], []))

    assert Trace.state(session, "Guarded") == %{hits: 1}
  end

  test "events with no steps are stuttering steps" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:ok, session} = Trace.event(session, event("wait", [], []))

    assert Trace.state(session, "Counter") == %{count: 0, frozen: :no}
    assert Trace.labels(session) == ["wait"]
  end

  test "unknown models and transitions are disagreements" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:error, %Trace.Disagreement{reason: :unknown_model} = missing_model} =
             Trace.event(session, event("step", [{"Nope", "tick"}], []))

    assert missing_model.detail =~ "no model named \"Nope\""

    assert {:error, %Trace.Disagreement{reason: :unknown_transition} = missing_transition} =
             Trace.event(session, event("step", [{"Counter", "explode"}], []))

    assert missing_transition.detail =~ "no transition named \"explode\""
  end

  test "evaluation failures inside mapped transitions are disagreements" do
    {:ok, session} = Trace.new([model(@bad_body)])

    assert {:error, %Trace.Disagreement{reason: :evaluation} = disagreement} =
             Trace.event(session, event("step", [{"BadBody", "broken"}], []))

    assert disagreement.detail =~ "assignment to undeclared state field bogus"
  end

  # @spec OAUTH-TC-5
  test "mapped steps may not violate declared invariants" do
    {:ok, session} = Trace.new([model(@counter)])
    {:ok, session} = Trace.event(session, event("tick 1", [{"Counter", "tick"}], []))

    assert {:error, %Trace.Disagreement{reason: :invariant} = disagreement} =
             Trace.event(session, event("tick 2", [{"Counter", "tick"}], []))

    assert disagreement.invariant == "count stays below two"
    assert disagreement.state == %{count: 2, frozen: :no}
    assert Trace.Disagreement.format(disagreement) =~ ~s/at event "tick 2"/
  end

  # ── claims over pre/post states ─────────────────────────────────────

  test "equals claims compare against the post-transition state" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:ok, session} =
             Trace.event(
               session,
               event("tick", [{"Counter", "tick"}], [{"Counter", {:equals, :count, 1}}])
             )

    assert {:error, %Trace.Disagreement{reason: :claim} = disagreement} =
             Trace.event(
               session,
               event("idle", [], [{"Counter", {:equals, :count, 5}}])
             )

    assert disagreement.claim == {:equals, :count, 5}
    assert disagreement.detail =~ "model state has 1"
  end

  test "increments claims require exactly one step forward" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:ok, session} =
             Trace.event(
               session,
               event("tick", [{"Counter", "tick"}], [{"Counter", {:increments, :count}}])
             )

    assert {:error, %Trace.Disagreement{reason: :claim} = disagreement} =
             Trace.event(session, event("idle", [], [{"Counter", {:increments, :count}}]))

    assert disagreement.claim == {:increments, :count}
    assert disagreement.detail =~ "moved 1 -> 1"
  end

  test "increments claims fail on non-numeric state" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:error, %Trace.Disagreement{reason: :claim} = disagreement} =
             Trace.event(session, event("idle", [], [{"Counter", {:increments, :frozen}}]))

    assert disagreement.detail =~ "moved :no -> :no"
  end

  test "unchanged claims fail when a mapped step moved the field" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:error, %Trace.Disagreement{reason: :claim} = disagreement} =
             Trace.event(
               session,
               event("tick", [{"Counter", "tick"}], [{"Counter", {:unchanged, :count}}])
             )

    assert disagreement.claim == {:unchanged, :count}
    assert disagreement.detail =~ "moved 0 -> 1"
  end

  test "claims on unknown models and fields are disagreements" do
    {:ok, session} = Trace.new([model(@counter)])

    assert {:error, %Trace.Disagreement{reason: :unknown_model}} =
             Trace.event(session, event("idle", [], [{"Nope", {:equals, :count, 0}}]))

    assert {:error, %Trace.Disagreement{reason: :unknown_field} = disagreement} =
             Trace.event(session, event("idle", [], [{"Counter", {:equals, :bogus, 0}}]))

    assert disagreement.detail =~ "no state field :bogus"
  end

  test "a disagreeing event leaves the session at the last good state" do
    {:ok, session} = Trace.new([model(@counter)])
    {:ok, session} = Trace.event(session, event("tick", [{"Counter", "tick"}], []))

    assert {:error, %Trace.Disagreement{}} =
             Trace.event(
               session,
               event("tick 2", [{"Counter", "tick"}], [{"Counter", {:equals, :count, 99}}])
             )

    assert Trace.state(session, "Counter") == %{count: 1, frozen: :no}
    assert Trace.labels(session) == ["tick"]
  end
end
