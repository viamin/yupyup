defmodule Yup.ParserTest do
  use ExUnit.Case, async: true

  alias Yup.AST.{BinaryOp, Call, Function, Identifier, Literal, Program, UnaryOp}

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

  test "parses arithmetic operators with standard precedence" do
    assert {:ok, %Program{body: [%BinaryOp{} = op]}} =
             Yup.Parser.parse("1 + 2 * 3", path: "expr.yup")

    assert op.op == "+"
    assert %Literal{kind: :integer, value: 1} = op.left
    assert %BinaryOp{op: "*"} = op.right
    assert op.loc == %{line: 1, column: 3}
  end

  test "parses comparison operators" do
    for op_text <- ["==", "!=", "<", "<=", ">", ">="] do
      assert {:ok, %Program{body: [%BinaryOp{op: ^op_text} = op]}} =
               Yup.Parser.parse("1 #{op_text} 2", path: "expr.yup")

      assert %Literal{kind: :integer, value: 1} = op.left
      assert %Literal{kind: :integer, value: 2} = op.right
    end
  end

  test "parses comparison with precedence over equality" do
    assert {:ok, %Program{body: [%BinaryOp{op: "=="} = op]}} =
             Yup.Parser.parse("1 + 2 == 3", path: "expr.yup")

    assert %BinaryOp{op: "+"} = op.left
    assert %Literal{kind: :integer, value: 3} = op.right
  end

  test "parses boolean and/or expressions" do
    assert {:ok, %Program{body: [%BinaryOp{op: "and"} = and_op]}} =
             Yup.Parser.parse("true and false", path: "expr.yup")

    assert %Literal{kind: :boolean, value: true} = and_op.left
    assert %Literal{kind: :boolean, value: false} = and_op.right

    assert {:ok, %Program{body: [%BinaryOp{op: "or"} = or_op]}} =
             Yup.Parser.parse("true or false", path: "expr.yup")

    assert %Literal{kind: :boolean, value: true} = or_op.left
    assert %Literal{kind: :boolean, value: false} = or_op.right
  end

  test "parses and as higher precedence than or" do
    assert {:ok, %Program{body: [%BinaryOp{op: "or", right: %BinaryOp{op: "and"}} = or_op]}} =
             Yup.Parser.parse("false or true and true", path: "expr.yup")

    assert %Literal{kind: :boolean, value: false} = or_op.left
  end

  test "parses unary not with source location" do
    assert {:ok, %Program{body: [%UnaryOp{op: "not", operand: %Literal{value: true}, loc: loc}]}} =
             Yup.Parser.parse("not true", path: "expr.yup")

    assert loc == %{line: 1, column: 1}
  end

  test "parses unary not chained with right associativity" do
    assert {:ok,
            %Program{
              body: [%UnaryOp{op: "not", operand: %UnaryOp{op: "not", operand: %Identifier{}}}]
            }} =
             Yup.Parser.parse("not not ready", path: "expr.yup")
  end

  test "parses nil literal as a nil kind" do
    assert {:ok, %Program{body: [%Literal{kind: nil, value: nil}]}} =
             Yup.Parser.parse("nil", path: "expr.yup")
  end

  test "parses boolean literals" do
    assert {:ok, %Program{body: [%Literal{kind: :boolean, value: true}]}} =
             Yup.Parser.parse("true", path: "expr.yup")

    assert {:ok, %Program{body: [%Literal{kind: :boolean, value: false}]}} =
             Yup.Parser.parse("false", path: "expr.yup")
  end

  test "parses comparison against nil and booleans" do
    assert {:ok, %Program{body: [%BinaryOp{op: "==", left: %Literal{kind: nil}, right: right}]}} =
             Yup.Parser.parse("nil == nil", path: "expr.yup")

    assert match?(%Literal{kind: nil}, right)

    assert {:ok,
            %Program{
              body: [
                %BinaryOp{
                  op: "!=",
                  left: %Literal{kind: :boolean, value: true},
                  right: %Literal{kind: :boolean, value: false}
                }
              ]
            }} = Yup.Parser.parse("true != false", path: "expr.yup")
  end

  test "parses grouping with parentheses" do
    assert {:ok,
            %Program{
              body: [
                %BinaryOp{op: "*", left: %BinaryOp{op: "+", left: %Literal{value: 1}} = grouped}
              ]
            }} = Yup.Parser.parse("(1 + 2) * 3", path: "expr.yup")

    assert %Literal{kind: :integer, value: 2} = grouped.right
  end

  test "parses a function with comparison body" do
    source = """
    def is_adult(age)
      age >= 18
    end

    puts is_adult(21)
    """

    assert {:ok, %Program{functions: [%Function{body: [%BinaryOp{op: ">="}]}], body: [%Call{}]}} =
             Yup.Parser.parse(source, path: "expr.yup")
  end

  test "returns source-oriented syntax errors" do
    assert {:error, error} = Yup.Parser.parse(~s(puts "unterminated), path: "bad.yup")
    assert error.path == "bad.yup"
    assert error.line == 1
    assert error.message == "unterminated string"
  end

  test "reports unknown characters with source location" do
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("1 + @", path: "bad.yup")
    assert error.line == 1
    assert error.column == 5
    assert error.message =~ "unexpected character"
  end

  test "reports unexpected operator at end of expression" do
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("1 + ", path: "bad.yup")
    assert error.line == 1
    assert error.message =~ "unexpected end of expression"
  end
end
