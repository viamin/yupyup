defmodule Yup.VerifyTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Yup.SourceError
  alias Yup.Verify

  @light """
  model Light
    state value = :off

    transition toggle do
      state.value = value == :off ? :on : :off
    end
  end
  """

  defp write_model(tmp_dir, name, source) do
    path = Path.join(tmp_dir, name)
    File.write!(path, source)
    path
  end

  # ── entry point ─────────────────────────────────────────────────────

  # @spec VERIFY-4
  test "verify_file explores the shipped light example" do
    assert {:ok, result} = Verify.verify_file("examples/light.yup")

    assert result.model_name == "Light"
    assert result.states == 2
    assert result.transitions == 2
    assert result.complete == true
  end

  # @spec VERIFY-5
  test "format_result reports counts without claiming property verification" do
    {:ok, result} = Verify.verify_file("examples/light.yup")

    assert Verify.format_result(result) ==
             "model Light: exploration complete: 2 states, 2 transitions explored"

    refute Verify.format_result(result) =~ ~r/verif/i
  end

  # ── exactly one model ───────────────────────────────────────────────

  # @spec VERIFY-1
  @tag :tmp_dir
  test "rejects a file with no model", %{tmp_dir: tmp_dir} do
    path = write_model(tmp_dir, "no_model.yup", "puts 1\n")

    assert {:error, %SourceError{} = error} = Verify.verify_file(path)
    assert error.message == "expected exactly one model to verify, found 0"
  end

  # @spec VERIFY-1
  @tag :tmp_dir
  test "rejects a file with multiple models", %{tmp_dir: tmp_dir} do
    path = write_model(tmp_dir, "two_models.yup", @light <> "\n" <> @light)

    assert {:error, %SourceError{} = error} = Verify.verify_file(path)
    assert error.message == "expected exactly one model to verify, found 2"
  end

  # @spec VERIFY-1
  @tag :tmp_dir
  test "does not execute coexisting executable code", %{tmp_dir: tmp_dir} do
    path = write_model(tmp_dir, "mixed.yup", @light <> ~s(\nputs "must not run"\n))

    output = capture_io(fn -> assert {:ok, _result} = Verify.verify_file(path) end)
    assert output == ""
  end

  # @spec VERIFY-1
  @tag :tmp_dir
  test "propagates parse errors as source errors", %{tmp_dir: tmp_dir} do
    path = write_model(tmp_dir, "bad.yup", "model Light\n  state value = \nend\n")

    assert {:error, %SourceError{} = error} = Verify.verify_file(path)
    assert error.message =~ "unexpected end of expression"
  end

  test "reports a missing file" do
    assert {:error, %File.Error{}} = Verify.verify_file("examples/does_not_exist.yup")
  end

  # ── bounded exploration and failures through the entry point ────────

  # @spec VERIFY-6
  @tag :tmp_dir
  test "honors the max-states option", %{tmp_dir: tmp_dir} do
    counter = """
    model Counter
      state count = 0

      transition increment do
        state.count = count + 1
      end
    end
    """

    counter_path = write_model(tmp_dir, "counter.yup", counter)
    light_path = write_model(tmp_dir, "light.yup", @light)

    assert {:error, %Verify.Failure{kind: :incomplete}} =
             Verify.verify_file(counter_path, max_states: 5)

    # A bounded/cyclic model completes within the default cap.
    assert {:ok, result} = Verify.verify_file(light_path)
    assert result.complete == true
  end

  # @spec VERIFY-6
  @tag :tmp_dir
  test "rejects a non-positive max-states option", %{tmp_dir: tmp_dir} do
    path = write_model(tmp_dir, "light.yup", @light)

    assert {:error, %Verify.Failure{} = failure} = Verify.verify_file(path, max_states: 0)
    assert failure.diagnostic.message =~ "--max-states must be a positive integer"
  end

  # @spec VERIFY-3
  @tag :tmp_dir
  test "rejects self-referential state initializers end to end", %{tmp_dir: tmp_dir} do
    chained = """
    model Chain
      state a = 1
      state b = a + 1
    end
    """

    path = write_model(tmp_dir, "chain.yup", chained)

    assert {:error, %Verify.Failure{} = failure} = Verify.verify_file(path)
    assert failure.diagnostic.message =~ "state initializers cannot read state fields (a)"
  end

  # ── invariants ──────────────────────────────────────────────────────

  # @spec INVARIANT-4
  test "format_result reports held invariants without claiming proof" do
    {:ok, result} = Verify.verify_file("examples/invariants.yup")

    assert Verify.format_result(result) ==
             "model Light: exploration complete: 2 states, 2 transitions explored; " <>
               "1 invariant held at every explored state"

    refute Verify.format_result(result) =~ ~r/prov|verif/i
  end

  # @spec INVARIANT-4
  @tag :tmp_dir
  test "format_result pluralizes multiple held invariants", %{tmp_dir: tmp_dir} do
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

    path = write_model(tmp_dir, "two_invariants.yup", source)

    assert {:ok, result} = Verify.verify_file(path)
    assert Verify.format_result(result) =~ "2 invariants held at every explored state"
  end

  # @spec INVARIANT-3
  test "verify_file reports invariant violations with counterexamples" do
    assert {:error, %Verify.Failure{kind: :invariant} = failure} =
             Verify.verify_file("examples/broken_invariant.yup")

    assert failure.invariant == "count stays below 3"
    assert failure.state == %{count: 3}
    assert failure.trace == ["increment", "increment", "increment"]
    assert failure.diagnostic.line == 4
    assert Verify.Failure.format(failure) =~ "counterexample state {count: 3}"
  end

  # ── program-level API ───────────────────────────────────────────────

  # @spec VERIFY-1
  test "verify_program explores an in-memory parsed program" do
    {:ok, program} = Yup.Parser.parse(@light, path: "light.yup")
    assert {:ok, result} = Verify.verify_program(program, path: "light.yup")
    assert result.model_name == "Light"
  end
end
