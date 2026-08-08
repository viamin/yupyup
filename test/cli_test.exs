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

    assert output == "Hello, world\n"
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

  test "unknown command exits non-zero" do
    assert catch_exit(Yup.CLI.main(["wat"])) == {:shutdown, 1}
  end
end
