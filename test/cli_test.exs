defmodule Yup.CLITest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  setup_all do
    Mix.Tasks.Escript.Build.run([])
    %{yup: Path.expand("yup", File.cwd!())}
  end

  test "prints version" do
    assert capture_io(fn -> Yup.CLI.main(["--version"]) end) =~ ~r/^yup \d+\.\d+\.\d+/
  end

  test "runs hello example through built escript", %{yup: yup} do
    assert File.exists?(yup)
    assert {output, 0} = System.cmd(yup, ["run", "examples/hello.yup"], stderr_to_stdout: true)

    assert output =~ "Hello, world"
  end

  test "runs functions example through built escript", %{yup: yup} do
    assert {output, 0} =
             System.cmd(yup, ["run", "examples/functions.yup"], stderr_to_stdout: true)

    assert output =~ "8"
    assert output =~ "10"
  end

  test "runs match example through built escript", %{yup: yup} do
    assert {output, 0} = System.cmd(yup, ["run", "examples/match.yup"], stderr_to_stdout: true)

    assert output =~ "got ok: 42"
    assert output =~ "got error: nope"
    assert output =~ "the answer"
  end

  test "runs records example through built escript", %{yup: yup} do
    assert {output, 0} = System.cmd(yup, ["run", "examples/records.yup"], stderr_to_stdout: true)

    assert output =~ "Ada"
    assert output =~ "42"
    assert output =~ "Grace"
  end

  test "runs dot_calls example through built escript", %{yup: yup} do
    assert {output, 0} =
             System.cmd(yup, ["run", "examples/dot_calls.yup"], stderr_to_stdout: true)

    assert output =~ "6"
    assert output =~ "10"
    assert output =~ "Ada"
  end

  test "runs collections example through built escript", %{yup: yup} do
    assert {output, 0} =
             System.cmd(yup, ["run", "examples/collections.yup"], stderr_to_stdout: true)

    assert output =~ "[2, 4, 6]"
    assert output =~ "[2]"
    # The original list is printed again at the end, proving map/select never
    # mutated it.
    assert output =~ "[1, 2, 3]"
    assert output =~ "Ada"
    assert output =~ "true"
  end

  @tag :tmp_dir
  test "reports dot calls in model expressions as a source-located error", %{
    tmp_dir: tmp_dir,
    yup: yup
  } do
    path = Path.join(tmp_dir, "model_dot_call.yup")

    File.write!(path, """
    model Light
      transition toggle do
        state.value = state.value()
      end
    end
    """)

    assert {output, 1} = System.cmd(yup, ["run", path], stderr_to_stdout: true)
    assert output =~ "dot calls are not supported in model expressions"
  end

  @tag :tmp_dir
  test "reports source-oriented syntax errors through built escript", %{
    tmp_dir: tmp_dir,
    yup: yup
  } do
    path = Path.join(tmp_dir, "bad.yup")
    File.write!(path, ~s(puts "unterminated))

    assert {output, 1} = System.cmd(yup, ["run", path], stderr_to_stdout: true)
    assert output =~ "#{path}:1:6: unterminated string"
  end

  @tag :tmp_dir
  test "reports rebinding compile errors through built escript", %{
    tmp_dir: tmp_dir,
    yup: yup
  } do
    path = Path.join(tmp_dir, "rebind.yup")
    File.write!(path, "x = 1\nx = 2\n")

    assert {output, 1} = System.cmd(yup, ["run", path], stderr_to_stdout: true)
    assert output =~ "#{path}:2:1: cannot rebind immutable name x"
  end

  @tag :tmp_dir
  test "reports unexpected characters through built escript", %{
    tmp_dir: tmp_dir,
    yup: yup
  } do
    path = Path.join(tmp_dir, "bad.yup")
    File.write!(path, "1 + @")

    assert {output, 1} = System.cmd(yup, ["run", path], stderr_to_stdout: true)
    assert output =~ "#{path}:1:5: unexpected character"
  end

  describe "verify" do
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

    # @spec VERIFY-5
    test "verifies light example with zero exit", %{yup: yup} do
      assert {output, 0} =
               System.cmd(yup, ["verify", "examples/light.yup"], stderr_to_stdout: true)

      assert output =~ "model Light: exploration complete: 2 states, 2 transitions explored"
    end

    # @spec VERIFY-6
    @tag :tmp_dir
    test "reports incomplete exploration with nonzero exit", %{tmp_dir: tmp_dir, yup: yup} do
      path = Path.join(tmp_dir, "counter.yup")
      File.write!(path, @counter)

      for args <- [["verify", path, "--max-states", "5"], ["verify", "--max-states", "5", path]] do
        assert {output, 1} = System.cmd(yup, args, stderr_to_stdout: true)
        assert output =~ "model Counter: exploration incomplete"
        assert output =~ "reached state cap (5) with states still to explore"
        assert output =~ "explored 5 states, 4 transitions"
        assert output =~ "increase --max-states"
      end
    end

    # @spec VERIFY-1
    @tag :tmp_dir
    test "reports a file with no model with nonzero exit", %{tmp_dir: tmp_dir, yup: yup} do
      path = Path.join(tmp_dir, "no_model.yup")
      File.write!(path, "puts 1\n")

      assert {output, 1} = System.cmd(yup, ["verify", path], stderr_to_stdout: true)
      assert output =~ "expected exactly one model to verify, found 0"
    end

    # @spec VERIFY-7
    @tag :tmp_dir
    test "reports evaluation failures with trace context and nonzero exit", %{
      tmp_dir: tmp_dir,
      yup: yup
    } do
      path = Path.join(tmp_dir, "boomer.yup")
      File.write!(path, @boomer)

      assert {output, 1} = System.cmd(yup, ["verify", path], stderr_to_stdout: true)
      assert output =~ "#{path}:5:"
      assert output =~ "division by zero in model expression"
      assert output =~ "while applying transition increment to state {n: 3}"
      assert output =~ "reached via: increment, increment, increment"
    end

    # @spec INVARIANT-4
    test "verifies passing invariant example with zero exit", %{yup: yup} do
      assert {output, 0} =
               System.cmd(yup, ["verify", "examples/invariants.yup"], stderr_to_stdout: true)

      assert output =~
               "model Light: exploration complete: 2 states, 2 transitions explored; " <>
                 "1 invariant held at every explored state"
    end

    # @spec INVARIANT-3
    test "reports invariant failures with counterexample and nonzero exit", %{yup: yup} do
      assert {output, 1} =
               System.cmd(yup, ["verify", "examples/broken_invariant.yup"],
                 stderr_to_stdout: true
               )

      assert output =~ "examples/broken_invariant.yup:4:1:"
      assert output =~ ~s/invariant "count stays below 3" failed/
      assert output =~ "counterexample state {count: 3}"
      assert output =~ "reached via: increment, increment, increment"
    end

    # @spec INVARIANT-5
    @tag :tmp_dir
    test "reports invariant evaluation errors with nonzero exit", %{
      tmp_dir: tmp_dir,
      yup: yup
    } do
      path = Path.join(tmp_dir, "boom_invariant.yup")

      File.write!(path, """
      model Boomer
        state count = 0

        invariant "no division by zero" do
          1 / 0 == 1
        end
      end
      """)

      assert {output, 1} = System.cmd(yup, ["verify", path], stderr_to_stdout: true)

      assert output =~ "division by zero in model expression"
      assert output =~ "while evaluating an invariant at state {count: 0}"
      assert output =~ "reached via: initial state"
    end

    # @spec VERIFY-6
    test "rejects an invalid max-states value", %{yup: yup} do
      assert {output, 1} =
               System.cmd(yup, ["verify", "--max-states", "wat", "examples/light.yup"],
                 stderr_to_stdout: true
               )

      assert output =~ "invalid value for --max-states: wat"
    end

    test "rejects a missing file argument" do
      assert catch_exit(Yup.CLI.main(["verify"])) == {:shutdown, 1}
    end

    test "rejects unknown verify options", %{yup: yup} do
      assert {output, 1} =
               System.cmd(yup, ["verify", "--wat", "examples/light.yup"], stderr_to_stdout: true)

      assert output =~ "unknown option --wat"
    end
  end

  test "unknown command exits non-zero" do
    assert catch_exit(Yup.CLI.main(["wat"])) == {:shutdown, 1}
  end
end
