defmodule Yup.ParserTest do
  use ExUnit.Case, async: true

  alias Yup.AST.{BinaryOp, Call, Function, Literal, Program}

  test "parses hello program into YupYup AST" do
    source = """
    def hello(name)
      "Hello, " + name
    end

    puts hello("world")
    """

    assert {:ok, %Program{functions: [%Function{name: "hello"}], body: [%Call{name: "puts"}]}} =
             Yup.Parser.parse(source, path: "hello.yup")
  end

  test "parses binary expressions with source locations" do
    assert {:ok, %Program{body: [%Call{args: [%BinaryOp{} = op]}]}} =
             Yup.Parser.parse(~s(puts "Hello, " + "world"), path: "expr.yup")

    assert op.op == "+"
    assert %Literal{kind: :string, value: "Hello, "} = op.left
    assert op.loc == %{line: 1, column: 16}
  end

  test "returns source-oriented syntax errors" do
    assert {:error, error} = Yup.Parser.parse(~s(puts "unterminated), path: "bad.yup")
    assert error.path == "bad.yup"
    assert error.line == 1
    assert error.message == "unterminated string"
  end
end
