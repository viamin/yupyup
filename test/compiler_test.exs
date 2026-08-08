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

  test "binds and calls an anonymous function value" do
    source = """
    double = { |x| x * 2 }
    puts double(4)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "block.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "8\n"
  end

  test "passes a function value as an argument to another function" do
    source = """
    def invoke(callback, value)
      callback(value)
    end

    double = { |x| x * 2 }
    puts invoke(double, 5)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "block.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "10\n"
  end

  test "supports anonymous functions with multiple parameters" do
    source = """
    add = { |x, y| x + y }
    puts add(3, 4)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "block.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "7\n"
  end

  test "rejects rebinding the reserved puts name" do
    source = """
    puts = { |x| x }
    puts(42)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    assert_raise Yup.SourceError, ~r/cannot rebind immutable name puts/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects defining a top-level function with the reserved puts name" do
    source = """
    def puts()
      1
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    assert_raise Yup.SourceError, ~r/cannot define function with reserved name puts/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects rebinding a top-level function name in the body" do
    source = """
    def foo()
      1
    end

    foo = 42
    foo()
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    assert_raise Yup.SourceError, ~r/cannot rebind immutable name foo/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects rebinding a top-level function name inside another function body" do
    source = """
    def foo()
      1
    end

    def bar()
      foo = 2
      foo
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "rebind.yup")

    assert_raise Yup.SourceError, ~r/cannot rebind immutable name foo/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "executes match with literal integer patterns" do
    source = """
    match 42
    when 0
      puts "zero"
    when 42
      puts "the answer"
    when 99
      puts "ninety-nine"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "match.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "the answer\n"
  end

  test "executes match with constructor patterns" do
    source = """
    result = Ok(42)

    match result
    when Ok(value)
      puts "ok: " + value
    when Error(reason)
      puts "err: " + reason
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "match.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "ok: 42\n"
  end

  test "executes match with the second constructor clause" do
    source = """
    result = Error("nope")

    match result
    when Ok(value)
      puts "ok: " + value
    when Error(reason)
      puts "err: " + reason
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "match.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "err: nope\n"
  end

  test "executes match with binder pattern falling through to the catch-all" do
    source = """
    answer = 7

    match answer
    when 0
      puts "zero"
    when 42
      puts "the answer"
    when n
      puts "other: " + n
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "match.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "other: 7\n"
  end

  test "executes match with multiple statements in a clause body" do
    source = """
    match Ok(42)
    when Ok(value)
      label = "ok"
      puts label + ":" + value
    when other
      puts "other"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "match.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "ok:42\n"
  end

  test "executes match inside a function body" do
    source = """
    def unwrap(value)
      match value
      when Ok(inner)
        inner
      when Error(reason)
        99
      end
    end

    puts unwrap(Ok(10))
    puts unwrap(Error("nope"))
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "fn_match.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "10\n99\n"
  end

  test "match raises when no clause matches" do
    source = """
    match 7
    when 0
      puts "zero"
    when 42
      puts "forty-two"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "match.yup")

    capture_io(fn ->
      assert {:ok, module} = Yup.Compiler.compile(program)

      result =
        try do
          Yup.Compiler.run(module)
        catch
          :error, {:case_clause, value} -> value
        end

      assert result == 7
    end)
  end

  test "compiles program with models alongside executable code" do
    source = """
    model Light
      state value = :off

      transition toggle do
        state.value = :on
      end
    end

    puts "model ignored, code still runs"
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "model.yup")

    capture_io(fn ->
      assert {:ok, module} = Yup.Compiler.compile(program)
      assert {:ok, :ok} = Yup.Compiler.run(module)
    end)
  end

  test "compiles program containing only a model" do
    source = """
    model Light
      state value = :off

      transition toggle do
        state.value = :on
      end
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "model.yup")

    capture_io(fn ->
      assert {:ok, module} = Yup.Compiler.compile(program)
      assert {:ok, :ok} = Yup.Compiler.run(module)
    end)
  end
end
