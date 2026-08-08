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

  test "constructs and reads a record field on the BEAM" do
    source = """
    record Person
      name
      age
    end

    person = Person.new(name: "Ada", age: 42)
    puts person.name
    puts person.age
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Ada\n42\n"
  end

  test "records support nested field access" do
    source = """
    record Point
      x
      y
    end

    point = Point.new(x: 1, y: 2)
    puts point.x + point.y
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "3\n"
  end

  test "records are immutable across rebinding" do
    source = """
    record Person
      name
    end

    first = Person.new(name: "Ada")
    second = Person.new(name: "Grace")
    puts first.name
    puts second.name
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Ada\nGrace\n"
  end

  test "records can be used as function parameters and returns" do
    source = """
    record Person
      name
      age
    end

    def rename(person, new_name)
      Person.new(name: new_name, age: person.age)
    end

    person = Person.new(name: "Ada", age: 42)
    updated = rename(person, "Grace")
    puts updated.name
    puts updated.age
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Grace\n42\n"
  end

  test "rejects construction of an undeclared record" do
    source = """
    person = Person.new(name: "Ada", age: 42)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/unknown record type Person/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects record construction with unknown field" do
    source = """
    record Person
      name
      age
    end

    person = Person.new(name: "Ada", age: 42, weight: 70)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/record Person has no field weight/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects record construction missing a required field" do
    source = """
    record Person
      name
      age
    end

    person = Person.new(name: "Ada")
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/record Person is missing field age/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects undeclared record construction used as a match subject" do
    source = """
    match Person.new(name: "Ada", age: 42)
    when _
      puts "any"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/unknown record type Person/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects unknown field in record construction used as a match subject" do
    source = """
    record Person
      name
      age
    end

    match Person.new(name: "Ada", age: 42, weight: 70)
    when _
      puts "any"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/record Person has no field weight/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects missing field in record construction used as a match subject" do
    source = """
    record Person
      name
      age
    end

    match Person.new(name: "Ada")
    when _
      puts "any"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/record Person is missing field age/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "valid record construction as a match subject compiles and runs" do
    source = """
    record Person
      name
    end

    match Person.new(name: "Ada")
    when _
      puts "any"
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "any\n"
  end

  test "field access raises at runtime for missing keys" do
    source = """
    record Person
      name
    end

    person = Person.new(name: "Ada")
    puts person.age
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    capture_io(fn ->
      assert {:ok, module} = Yup.Compiler.compile(program)

      result =
        try do
          Yup.Compiler.run(module)
        catch
          :error, {:badkey, :age} -> :badkey
          :error, {:badkey, key} -> key
        end

      assert result == :badkey or result == :age
    end)
  end
end
