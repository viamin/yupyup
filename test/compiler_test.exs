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

  test "rejects record construction with duplicate field" do
    source = """
    record Person
      name
      age
    end

    person = Person.new(name: "Ada", name: "Bob")
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "record.yup")

    assert_raise Yup.SourceError, ~r/duplicate field name in record Person construction/, fn ->
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

  # ── dot calls and chaining (issue #3) ───────────────────────────────

  test "a dot call runs the same as the equivalent ordinary call" do
    source = """
    def double(value)
      value * 2
    end

    puts double(3)
    puts 3.double()
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "dot_call.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "6\n6\n"
  end

  test "a dot call passes the receiver as the first argument alongside other args" do
    source = """
    def add(value, amount)
      value + amount
    end

    puts 3.add(4)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "dot_call.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "7\n"
  end

  test "chained dot calls evaluate left to right" do
    source = """
    def double(value)
      value * 2
    end

    def add(value, amount)
      value + amount
    end

    puts 3.double().add(4)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "dot_call.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "10\n"
  end

  test "a dot call resolves a bound function value receiver-first" do
    source = """
    double = { |x| x * 2 }
    puts 5.double()
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "dot_call.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "10\n"
  end

  test "mixes field reads and dot calls in one chain" do
    source = """
    record Address
      city
    end

    record Person
      address
    end

    def shout(text)
      text + "!"
    end

    person = Person.new(address: Address.new(city: "Boston"))
    puts person.address.city.shout()
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "dot_call.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Boston!\n"
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

  test "annotated function parameter compiles and runs the same as an unannotated one" do
    annotated = """
    def greet(person: Person)
      "Hello, " + person
    end

    puts greet("world")
    """

    assert {:ok, program} = Yup.Parser.parse(annotated, path: "annotated.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Hello, world\n"
  end

  test "annotated return type compiles and runs the same as an unannotated one" do
    annotated = """
    def hello(name) -> String
      "Hello, " + name
    end

    puts hello("world")
    """

    assert {:ok, program} = Yup.Parser.parse(annotated, path: "annotated.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Hello, world\n"
  end

  test "annotated record fields compile and run identically to unannotated ones" do
    annotated = """
    record Person
      name: String
      age: Integer
    end

    person = Person.new(name: "Ada", age: 42)
    puts person.name
    puts person.age
    """

    assert {:ok, program} = Yup.Parser.parse(annotated, path: "annotated.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Ada\n42\n"
  end

  test "fully annotated record and function compile and run identically" do
    source = """
    record Person
      name: String
    end

    def greet(person: Person) -> String
      "Hello, " + person.name
    end

    puts greet(Person.new(name: "Ada"))
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "annotated.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Hello, Ada\n"
  end

  test "ignoring annotations means a call with a wrong-shape value still compiles" do
    # A future type checker will reject `greet(42)` because `Person` is the
    # declared parameter type, but today the bootstrap ignores annotations so
    # the program runs unchanged.
    source = """
    def greet(person: Person)
      "Hello, " + person
    end

    puts greet(42)
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "annotated.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output =~ "Hello,"
  end

  test "annotated and unannotated versions of the same program produce the same output" do
    annotated = """
    def add(a: Integer, b: Integer) -> Integer
      a + b
    end

    puts add(3, 4)
    """

    unannotated = """
    def add(a, b)
      a + b
    end

    puts add(3, 4)
    """

    assert {:ok, annotated_program} = Yup.Parser.parse(annotated, path: "a.yup")
    assert {:ok, unannotated_program} = Yup.Parser.parse(unannotated, path: "u.yup")

    annotated_output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(annotated_program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    unannotated_output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(unannotated_program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert annotated_output == unannotated_output
    assert annotated_output == "7\n"
  end

  # ── immutable collections (issue #4) ────────────────────────────────

  test "executes a list literal and prints its elements" do
    assert {:ok, program} = Yup.Parser.parse("puts [1, 2, 3]", path: "list.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[1, 2, 3]\n"
  end

  test "executes an empty list literal" do
    assert {:ok, program} = Yup.Parser.parse("puts []", path: "list.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[]\n"
  end

  test "executes a nested list literal" do
    assert {:ok, program} = Yup.Parser.parse("puts [1, [2, 3]]", path: "list.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[1, [2, 3]]\n"
  end

  test "executes a list literal containing strings with quoted display" do
    assert {:ok, program} = Yup.Parser.parse(~s(puts ["a", "b"]), path: "list.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == ~s(["a", "b"]\n)
  end

  test "prints nil list elements distinctly from an empty list" do
    assert {:ok, program} = Yup.Parser.parse("puts [nil, false]", path: "list.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[nil, false]\n"
  end

  test "prints nil map values distinctly from an absent value" do
    assert {:ok, program} = Yup.Parser.parse("puts { a: nil }", path: "map.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "{a: nil}\n"
  end

  test "prints a top-level constructor value in source shape" do
    assert {:ok, program} = Yup.Parser.parse("puts Ok(1)", path: "ctor.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Ok(1)\n"
  end

  test "prints constructor values nested in a list with quoted string payloads" do
    source = """
    puts [Ok(1), Error("nope")]
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "ctor.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == ~s{[Ok(1), Error("nope")]\n}
  end

  test "prints a function value in opaque form instead of crashing" do
    source = """
    double = { |x| x * 2 }
    puts double
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "fn.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output =~ "#Function<"
  end

  test "executes a map literal and reads fields via dot syntax" do
    source = """
    user = { name: "Ada", active: true }
    puts user.name
    puts user.active
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "map.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "Ada\ntrue\n"
  end

  test "executes an empty map literal" do
    assert {:ok, program} = Yup.Parser.parse("puts {}", path: "map.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "{}\n"
  end

  test "prints a map literal with keys in sorted order" do
    assert {:ok, program} = Yup.Parser.parse("puts { b: 2, a: 1 }", path: "map.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "{a: 1, b: 2}\n"
  end

  test "executes map with a block-driven operation over a list" do
    source = """
    values = [1, 2, 3]
    doubled = values.map { |value| value * 2 }
    puts doubled
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[2, 4, 6]\n"
  end

  test "executes select with a block-driven predicate over a list" do
    source = """
    values = [1, 2, 3, 4]
    evens = values.select { |value| value / 2 * 2 == value }
    puts evens
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[2, 4]\n"
  end

  test "map does not mutate the original list" do
    source = """
    values = [1, 2, 3]
    doubled = values.map { |value| value * 2 }
    puts values
    puts doubled
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[1, 2, 3]\n[2, 4, 6]\n"
  end

  test "select does not mutate the original list" do
    source = """
    values = [1, 2, 3, 4]
    evens = values.select { |value| value / 2 * 2 == value }
    puts values
    puts evens
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[1, 2, 3, 4]\n[2, 4]\n"
  end

  test "map and select compose via dot-call chaining" do
    source = """
    values = [1, 2, 3, 4, 5]
    result = values.select { |value| value / 2 * 2 == value }.map { |value| value * 10 }
    puts result
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[20, 40]\n"
  end

  test "map also works as a plain call passing the list first" do
    source = """
    values = [1, 2, 3]
    puts map(values, { |value| value * 2 })
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    output =
      capture_io(fn ->
        assert {:ok, module} = Yup.Compiler.compile(program)
        assert {:ok, :ok} = Yup.Compiler.run(module)
      end)

    assert output == "[2, 4, 6]\n"
  end

  test "rejects a map literal with a duplicate key" do
    source = """
    user = { name: "Ada", name: "Grace" }
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "map.yup")

    assert_raise Yup.SourceError, ~r/duplicate key name in map literal/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "rejects defining a top-level function with the reserved map name" do
    source = """
    def map(x)
      x
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    assert_raise Yup.SourceError, ~r/cannot define function with reserved name map/, fn ->
      Yup.Compiler.Erlang.lower(program)
    end
  end

  test "raises at runtime when calling map on a non-list value" do
    source = """
    user = { name: "Ada" }
    puts user.map { |value| value }
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")
    assert {:ok, module} = Yup.Compiler.compile(program)

    assert_raise FunctionClauseError, fn ->
      capture_io(fn -> Yup.Compiler.run(module) end)
    end
  end

  test "rejects calling an unimplemented collection operation" do
    source = """
    values = [1, 2, 3]
    puts values.reduce { |acc, value| acc + value }
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "collections.yup")

    assert {:error, message} = Yup.Compiler.compile(program)
    assert message =~ "unbound_var"
  end
end
