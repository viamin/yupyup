defmodule Yup.CompilerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  test "compiles and executes a YupYup program on the BEAM" do
    source = """
    def hello(name)
      "Hello, " + name
    end

    puts hello("world")
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "hello.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Hello, world\n"
  end

  test "rejects rebinding immutable names" do
    source = """
    x = 1
    x = 2
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    assert_raise Yup.SourceError, ~r/cannot rebind immutable name x/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end
end
