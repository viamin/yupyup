defmodule Yup.Crosscheck.TlcTest do
  use ExUnit.Case, async: false

  @examples [
    "examples/auth_code.yup",
    "examples/pkce_exchange.yup",
    "examples/broken_auth_code.yup",
    "examples/broken_pkce_exchange.yup"
  ]

  @script Path.expand("bin/tlc-crosscheck", File.cwd!())

  # A fake TLC that records whether the exported .tla and companion .cfg
  # exist at invocation time (TLA-XC-4), echoes their contents into the
  # log, and — like real TLC — reports an invariant violation and exits 1
  # for models whose per-file run directory starts with `broken_` (the
  # deliberately broken fixtures), so agreement — including "both
  # checkers fail" — can be exercised without a TLA+ install. A bare
  # nonzero exit is not a fail verdict, so the shim must print TLC's
  # invariant-violation message too.
  @recording_shim ~S"""
  #!/bin/sh
  tla=no
  cfg=no
  [ -f "$1.tla" ] && tla=yes
  [ -f "$1.cfg" ] && cfg=yes
  printf 'model=%s tla=%s cfg=%s\n' "$1" "$tla" "$cfg" >> "$FAKE_TLC_LOG"
  if [ "$tla" = yes ] && [ "$cfg" = yes ]; then
    head -n 1 "$1.tla" >> "$FAKE_TLC_LOG"
    cat "$1.cfg" >> "$FAKE_TLC_LOG"
  fi
  case "$(basename "$(pwd)")" in
    broken_*)
      printf 'Error: Invariant Invariant1 is violated by the initial state:\n'
      exit 1
      ;;
    *) exit 0 ;;
  esac
  """

  describe "find_tlc/1" do
    # @spec TLA-XC-1
    test "reports TLC missing without an override, java, or CLASSPATH" do
      env = %{"YUP_TLC" => nil, "PATH" => "/usr/bin:/bin", "CLASSPATH" => nil}
      assert :error = Yup.Crosscheck.Tlc.find_tlc(env)
    end

    # @spec TLA-XC-1
    test "reports TLC missing when java is installed but CLASSPATH names nothing" do
      env = %{"YUP_TLC" => "", "PATH" => "/usr/bin:/bin", "CLASSPATH" => "/no/such/tla2tools.jar"}
      assert :error = Yup.Crosscheck.Tlc.find_tlc(env)
    end

    # @spec TLA-XC-1
    @tag :tmp_dir
    test "finds java tlc2.TLC when java is on PATH and CLASSPATH has an entry", %{
      tmp_dir: tmp_dir
    } do
      bin = Path.join(tmp_dir, "bin")
      File.mkdir_p!(bin)
      File.write!(Path.join(bin, "java"), "#!/bin/sh\nexit 0\n")
      File.chmod!(Path.join(bin, "java"), 0o755)

      jar = Path.join(tmp_dir, "tla2tools.jar")
      File.write!(jar, "")

      env = %{"YUP_TLC" => "", "PATH" => bin, "CLASSPATH" => jar}
      assert {:ok, ["java", "tlc2.TLC"]} = Yup.Crosscheck.Tlc.find_tlc(env)
    end

    # @spec TLA-XC-1
    test "uses the YUP_TLC override as command words" do
      env = %{
        "YUP_TLC" => "  java -cp /opt/tla2tools.jar tlc2.TLC  ",
        "PATH" => "",
        "CLASSPATH" => nil
      }

      assert {:ok, ["java", "-cp", "/opt/tla2tools.jar", "tlc2.TLC"]} =
               Yup.Crosscheck.Tlc.find_tlc(env)
    end
  end

  describe "crosscheck/3" do
    # @spec TLA-XC-2
    # @spec TLA-XC-5
    @tag :tmp_dir
    test "records agreement for the passing and broken example models", %{tmp_dir: tmp_dir} do
      {shim, _log} = recording_shim(tmp_dir)

      results = Yup.Crosscheck.Tlc.crosscheck(@examples, [shim], work_dir: tmp_dir)

      assert [%{status: :agree}, %{status: :agree}, %{status: :agree}, %{status: :agree}] =
               results

      assert Enum.map(results, & &1.yup) == [:pass, :pass, :fail, :fail]
      assert Enum.map(results, & &1.tlc) == [0, 0, 1, 1]

      # The broken fixtures reuse the AuthCode/PkceExchange model names;
      # their run directories are named after the source files.
      assert Enum.map(results, &Path.basename(&1.work_dir)) ==
               ~w(auth_code pkce_exchange broken_auth_code broken_pkce_exchange)
    end

    # @spec TLA-XC-6
    @tag :tmp_dir
    test "reports unreadable files as errors without running TLC", %{tmp_dir: tmp_dir} do
      [result] = Yup.Crosscheck.Tlc.crosscheck(["nope.yup"], ["echo"], work_dir: tmp_dir)

      assert result.status == :error
      assert result.yup == :none
      assert result.tlc == nil
      assert result.detail =~ "could not read \"nope.yup\""
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1
    end

    # @spec TLA-XC-6
    @tag :tmp_dir
    test "reports unexportable models as errors with a printable diagnostic", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "strings.yup")

      File.write!(source, """
      model Strings
        state label = "none"

        invariant "label stays none" do
          label == "none"
        end

        transition relabel do
          state.label = "none"
        end
      end
      """)

      [result] = Yup.Crosscheck.Tlc.crosscheck([source], ["echo"], work_dir: tmp_dir)

      assert result.status == :error
      assert result.yup == :none
      assert result.tlc == nil
      assert is_binary(result.detail)
      assert result.detail =~ "string literals are not supported in TLA+ export"
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1

      report = Yup.Crosscheck.Tlc.report([result])
      assert report =~ "error     #{source}:"
      assert report =~ "0/1 models agree"
    end

    # @spec TLA-XC-3
    test "report makes a disagreement obvious with a TLC excerpt" do
      result = %{
        file: "examples/auth_code.yup",
        model: "AuthCode",
        yup: :pass,
        tlc: 1,
        status: :disagree,
        detail: nil,
        tlc_output: "line one\nInvariant1 is violated.\nline three"
      }

      report = Yup.Crosscheck.Tlc.report([result])

      assert report =~
               "DISAGREEMENT examples/auth_code.yup (AuthCode): yup passed but tlc exited 1"

      assert report =~ "    Invariant1 is violated."
      assert report =~ "0/1 models agree"
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1
    end

    # @spec TLA-XC-3
    @tag :tmp_dir
    test "disagrees when TLC reports a violation yup does not find", %{tmp_dir: tmp_dir} do
      shim =
        write_shim(
          tmp_dir,
          "#!/bin/sh\necho 'Error: Invariant Invariant1 is violated by the initial state:'\nexit 1\n"
        )

      [result] =
        Yup.Crosscheck.Tlc.crosscheck(["examples/auth_code.yup"], [shim], work_dir: tmp_dir)

      assert result.status == :disagree
      assert result.yup == :pass
      assert result.tlc == 1
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1
    end

    # TLC exits nonzero for tool and spec errors too (here: an unparsable
    # module), so only a reported invariant violation confirms yup's fail
    # verdict — anything else is an error, never agreement.
    # @spec TLA-XC-6
    @tag :tmp_dir
    test "reports a nonzero TLC exit without a violation as an error, not agreement", %{
      tmp_dir: tmp_dir
    } do
      shim = write_shim(tmp_dir, "#!/bin/sh\necho 'Error: Parse error on line 3'\nexit 1\n")
      file = "examples/broken_auth_code.yup"

      [result] = Yup.Crosscheck.Tlc.crosscheck([file], [shim], work_dir: tmp_dir)

      assert result.status == :error
      assert result.yup == :fail
      assert result.tlc == 1
      assert result.detail =~ "without reporting an invariant violation"
      assert result.detail =~ "Parse error on line 3"
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1

      report = Yup.Crosscheck.Tlc.report([result])
      assert report =~ "error     examples/broken_auth_code.yup:"
      assert report =~ "0/1 models agree"
    end

    # @spec TLA-XC-6
    @tag :tmp_dir
    test "reports an unusable TLC outcome as an error when yup passes", %{tmp_dir: tmp_dir} do
      shim = write_shim(tmp_dir, "#!/bin/sh\necho 'Error: Out of memory'\nexit 1\n")

      [result] =
        Yup.Crosscheck.Tlc.crosscheck(["examples/auth_code.yup"], [shim], work_dir: tmp_dir)

      assert result.status == :error
      assert result.yup == :pass
      assert result.tlc == 1
      assert result.detail =~ "Out of memory"
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1
    end

    # @spec TLA-XC-6
    @tag :tmp_dir
    test "reports TLC that cannot be executed as an error", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "no-such-tlc")

      [result] =
        Yup.Crosscheck.Tlc.crosscheck(["examples/auth_code.yup"], [missing], work_dir: tmp_dir)

      assert result.status == :error
      assert result.yup == :pass
      assert result.tlc == nil
      assert result.detail =~ "could not run TLC"
      assert Yup.Crosscheck.Tlc.exit_code([result]) == 1
    end

    @tag :tlc
    @tag :tmp_dir
    test "cross-checks the example models with a real TLC install", %{tmp_dir: tmp_dir} do
      {:ok, tlc} = Yup.Crosscheck.Tlc.find_tlc()

      results = Yup.Crosscheck.Tlc.crosscheck(@examples, tlc, work_dir: tmp_dir)

      for result <- results do
        assert result.status == :agree, inspect(result, pretty: true)
      end
    end
  end

  describe "bin/tlc-crosscheck" do
    # @spec TLA-XC-1
    test "skips cleanly when TLC is missing" do
      assert {output, 0} =
               System.cmd(@script, [],
                 env: %{"YUP_TLC" => nil, "CLASSPATH" => "", "MIX_ENV" => "test"},
                 stderr_to_stdout: true
               )

      assert output =~ "TLC not found"
      assert output =~ "skipping cross-check"
    end

    # @spec TLA-XC-2
    # @spec TLA-XC-5
    @tag :tmp_dir
    test "agrees on the example models, failing both checkers on the broken fixtures", %{
      tmp_dir: tmp_dir
    } do
      {shim, _log} = recording_shim(tmp_dir)

      assert {output, 0} =
               run_script(%{"YUP_TLC" => shim, "FAKE_TLC_LOG" => recording_log(tmp_dir)})

      assert output =~ "4/4 models agree"
      assert output =~ "agree     examples/auth_code.yup (AuthCode): yup passed, tlc passed"

      assert output =~
               "agree     examples/broken_auth_code.yup (AuthCode): " <>
                 "yup failed (invariant), tlc exited 1"

      assert output =~
               "agree     examples/broken_pkce_exchange.yup (PkceExchange): " <>
                 "yup failed (invariant), tlc exited 1"
    end

    # @spec TLA-XC-4
    @tag :tmp_dir
    test "generates the exported .tla and .cfg before TLC runs", %{tmp_dir: tmp_dir} do
      {shim, _log} = recording_shim(tmp_dir)

      assert {_output, 0} =
               run_script(%{"YUP_TLC" => shim, "FAKE_TLC_LOG" => recording_log(tmp_dir)})

      recorded = File.read!(recording_log(tmp_dir))

      # Every invocation found the exported module and its cfg already in
      # place, in its own run directory.
      assert Enum.count(String.split(recorded, "model=")) == 5
      assert String.contains?(recorded, "tla=yes cfg=yes")
      refute String.contains?(recorded, "tla=no")
      refute String.contains?(recorded, "cfg=no")

      assert recorded =~ "---- MODULE AuthCode ----"
      assert recorded =~ "---- MODULE PkceExchange ----"
      assert recorded =~ "SPECIFICATION Spec"
      assert recorded =~ "INVARIANT Invariant1"
    end

    # @spec TLA-XC-3
    @tag :tmp_dir
    test "makes disagreement obvious and exits nonzero", %{tmp_dir: tmp_dir} do
      shim = write_shim(tmp_dir, "#!/bin/sh\nexit 0\n")

      assert {output, 1} = run_script(%{"YUP_TLC" => shim})

      assert output =~
               "DISAGREEMENT examples/broken_auth_code.yup (AuthCode): " <>
                 "yup failed (invariant) but tlc passed"

      assert output =~
               "DISAGREEMENT examples/broken_pkce_exchange.yup (PkceExchange): " <>
                 "yup failed (invariant) but tlc passed"

      assert output =~ "2/4 models agree"
    end

    # @spec TLA-XC-6
    @tag :tmp_dir
    test "does not claim agreement when TLC fails without a violation", %{tmp_dir: tmp_dir} do
      shim = write_shim(tmp_dir, "#!/bin/sh\necho 'Error: Parse error on line 3'\nexit 1\n")

      assert {output, 1} = run_script(%{"YUP_TLC" => shim})

      refute output =~ "4/4 models agree"
      assert output =~ "0/4 models agree"
      assert output =~ "error     examples/broken_auth_code.yup:"
      assert output =~ "TLC exited 1 without reporting an invariant violation"
      assert output =~ "    Error: Parse error on line 3"
    end

    # @spec TLA-XC-6
    @tag :tmp_dir
    test "reports files without a verifier verdict as errors and exits nonzero", %{
      tmp_dir: tmp_dir
    } do
      shim = write_shim(tmp_dir, "#!/bin/sh\nexit 0\n")

      assert {output, 1} =
               System.cmd(@script, ["nope.yup"],
                 env: %{"YUP_TLC" => shim, "MIX_ENV" => "test"},
                 stderr_to_stdout: true
               )

      assert output =~ "error     nope.yup: could not read \"nope.yup\""
      assert output =~ "0/1 models agree"
    end
  end

  defp recording_shim(tmp_dir) do
    {write_shim(tmp_dir, @recording_shim), recording_log(tmp_dir)}
  end

  defp recording_log(tmp_dir), do: Path.join(tmp_dir, "tlc.log")

  defp write_shim(tmp_dir, script) do
    shim = Path.join(tmp_dir, "fake_tlc.sh")
    File.write!(shim, script)
    File.chmod!(shim, 0o755)
    shim
  end

  defp run_script(env) do
    System.cmd(@script, [], env: Map.merge(%{"MIX_ENV" => "test"}, env), stderr_to_stdout: true)
  end
end
