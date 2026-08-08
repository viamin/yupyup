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

  test "executes integer arithmetic with runtime semantics" do
    source = """
    x = 10
    puts x + 2 * 3
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "arith.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "16\n"
  end

  test "executes integer division and subtraction" do
    source = """
    puts 8 / 2
    puts 4 - 1
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "arith.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "4\n3\n"
  end

  test "executes string concatenation" do
    source = """
    message = "Hello, " + "world"
    puts message
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "strings.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Hello, world\n"
  end

  test "executes comparison operators and prints booleans" do
    source = """
    puts 1 == 1
    puts 1 != 2
    puts 2 < 3
    puts 3 <= 3
    puts 4 > 3
    puts 4 >= 4
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "cmp.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "true\ntrue\ntrue\ntrue\ntrue\ntrue\n"
  end

  test "executes boolean and/or/not with truthy/falsy rules" do
    source = """
    puts true and false
    puts true or false
    puts not true
    puts not nil
    puts not false
    puts true and not false
    puts false or true
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "bool.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "false\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\n"
  end

  test "supports nil equality and inequality" do
    source = """
    puts nil == nil
    puts nil != 1
    puts nil == false
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "nil.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "true\ntrue\nfalse\n"
  end

  test "supports comparison inside function bodies" do
    source = """
    def is_adult(age)
      age >= 18
    end

    puts is_adult(21)
    puts is_adult(10)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "fn.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "true\nfalse\n"
  end

  test "supports combining arithmetic and comparisons with parentheses" do
    source = """
    puts (1 + 2) * 3 == 9
    puts 1 + 2 * 3 == 7
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "group.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "true\ntrue\n"
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

  test "rejects rebinding function parameters" do
    source = """
    def foo(name)
      name = "other"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    assert_raise Yup.SourceError, ~r/cannot rebind immutable name name/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects rebinding across top-level body with source location" do
    source = """
    x = 1
    x = 2
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    try do
      Yup.Compiler.Erlang.lower(program)
    rescue
      error in Yup.SourceError ->
        assert error.path == "rebind.yup"
        assert error.line == 2
        assert error.message =~ "cannot rebind immutable name x"
    end
  end
end