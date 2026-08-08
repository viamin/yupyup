defmodule Yup.ParserTest do
  use ExUnit.Case, async: true

  alias Yup.AST.{
    BinaryOp,
    BinderPattern,
    Call,
    Constructor,
    ConstructorPattern,
    Function,
    Identifier,
    Literal,
    LiteralPattern,
    Match,
    MatchClause,
    Program,
    UnaryOp
  }

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
            }} = Yup.Parser.parse("not not ready", path: "expr.yup")
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
    assert error.message =~ "unexpected end of expression"
  end

  test "parses match with literal integer and binder patterns" do
    source = """
    match value
    when 0
      puts "zero"
    when n
      puts n
    end
    """

    assert {:ok, %Program{body: [%Match{subject: %Identifier{name: "value"}, clauses: clauses}]}} =
             Yup.Parser.parse(source, path: "match.yup")

    assert [
             %MatchClause{
               pattern: %LiteralPattern{literal: %Literal{kind: :integer, value: 0}},
               body: [%Call{}]
             },
             %MatchClause{pattern: %BinderPattern{name: "n"}, body: [%Call{}]}
           ] = clauses
  end

  test "parses match with constructor patterns into tagged tuples" do
    source = """
    match result
    when Ok(value)
      puts value
    when Error(reason)
      puts reason
    end
    """

    assert {:ok,
            %Program{
              body: [
                %Match{
                  clauses: [
                    %MatchClause{
                      pattern: %ConstructorPattern{
                        tag: "Ok",
                        args: [%BinderPattern{name: "value"}]
                      }
                    },
                    %MatchClause{
                      pattern: %ConstructorPattern{
                        tag: "Error",
                        args: [%BinderPattern{name: "reason"}]
                      }
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "match.yup")
  end

  test "parses constructor expressions into tagged tuple form" do
    assert {:ok,
            %Program{
              body: [
                %Call{
                  args: [%Constructor{tag: "Ok", args: [%Literal{kind: :integer, value: 42}]}]
                }
              ]
            }} = Yup.Parser.parse("puts Ok(42)", path: "expr.yup")
  end

  test "parses literal patterns for strings, booleans, and nil" do
    for {source, kind, value} <- [
          {"when \"hi\"", :string, "hi"},
          {"when true", :boolean, true},
          {"when false", :boolean, false},
          {"when nil", nil, nil}
        ] do
      full = "match x\n#{source}\n  puts x\nend\n"

      assert {:ok,
              %Program{
                body: [
                  %Match{clauses: [%MatchClause{pattern: %LiteralPattern{literal: literal}}]}
                ]
              }} = Yup.Parser.parse(full, path: "match.yup")

      assert literal.kind == kind
      assert literal.value == value
    end
  end

  test "preserves source location on match clauses" do
    source = """
    match value
    when 0
      puts "zero"
    end
    """

    assert {:ok,
            %Program{
              body: [
                %Match{
                  loc: %{line: 1, column: 1},
                  clauses: [%MatchClause{loc: %{line: 2, column: 1}}]
                }
              ]
            }} = Yup.Parser.parse(source, path: "match.yup")
  end

  test "reports missing end for match with source location" do
    source = """
    match value
    when 0
      puts "zero"
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "match.yup")
    assert error.message =~ "missing end for match"
  end

  test "reports stray when at top level" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("when 0\n  puts x\nend\n", path: "bad.yup")

    assert error.line == 1
    assert error.message =~ "stray when outside of match"
  end

  test "reports invalid pattern syntax" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("match x\nwhen 42 99\n  puts x\nend\n", path: "bad.yup")

    assert error.message =~ "unexpected trailing token"
  end

  test "reports missing pattern after when" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("match x\nwhen \n  puts x\nend\n", path: "bad.yup")

    assert error.message =~ "missing pattern after when"
  end

  # ── model declarations ─────────────────────────────────────────────

  test "parses model with state and transition into AST" do
    source = """
    model Light
      state value = :off

      transition toggle do
        state.value = value == :off ? :on : :off
      end
    end
    """

    assert {:ok, %Program{models: [model]}} = Yup.Parser.parse(source, path: "model.yup")
    assert model.name == "Light"
    assert model.loc == %{line: 1, column: 1}
    assert [state] = model.states
    assert state.name == "value"
    assert %Literal{kind: :atom, value: :off} = state.value
    assert state.loc == %{line: 2, column: 1}
    assert [transition] = model.transitions
    assert transition.name == "toggle"
    assert transition.loc == %{line: 4, column: 1}
    assert [update] = transition.body
    assert %StateUpdate{name: "value"} = update
  end

  test "parses atom literals" do
    source = """
    model Light
      state value = :on
    end
    """

    assert {:ok, %Program{models: [%Model{states: [state]}]}} =
             Yup.Parser.parse(source, path: "model.yup")

    assert %Literal{kind: :atom, value: :on} = state.value
  end

  test "parses ternary expressions in model context" do
    source = """
    model Light
      state value = :off

      transition toggle do
        state.value = value == :off ? :on : :off
      end
    end
    """

    assert {:ok, %Program{models: [%Model{transitions: [transition]}]}} =
             Yup.Parser.parse(source, path: "model.yup")

    assert [%StateUpdate{value: %TernaryOp{} = ternary}] = transition.body
    assert %BinaryOp{op: "=="} = ternary.condition
    assert %Literal{kind: :atom, value: :on} = ternary.then_expr
    assert %Literal{kind: :atom, value: :off} = ternary.else_expr
  end

  test "parses state access in model expressions" do
    source = """
    model Switch
      state on = :false

      transition flip do
        state.on = state.on == :true ? :false : :true
      end
    end
    """

    assert {:ok, %Program{models: [%Model{transitions: [transition]}]}} =
             Yup.Parser.parse(source, path: "model.yup")

    assert [%StateUpdate{value: %TernaryOp{condition: %BinaryOp{left: %StateAccess{}}}}] =
             transition.body
  end

  test "model and executable code coexist in one source file" do
    source = """
    model Light
      state value = :off

      transition toggle do
        state.value = :on
      end
    end

    puts "model parsed alongside code"
    """

    assert {:ok,
            %Program{
              models: [%Model{name: "Light"}],
              body: [%Call{name: "puts"}],
              functions: []
            }} = Yup.Parser.parse(source, path: "coexist.yup")
  end

  test "model with multiple states and transitions" do
    source = """
    model TrafficLight
      state color = :red
      state timer = 0

      transition advance do
        state.color = color == :red ? :green : color == :green ? :yellow : :red
      end

      transition tick do
        state.timer = timer + 1
      end
    end
    """

    assert {:ok, %Program{models: [model]}} = Yup.Parser.parse(source, path: "model.yup")
    assert length(model.states) == 2
    assert length(model.transitions) == 2
    assert Enum.at(model.states, 0).name == "color"
    assert Enum.at(model.states, 1).name == "timer"
  end

  test "reports missing end for model" do
    source = """
    model Light
      state value = :off
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")
    assert error.message =~ "missing end for model Light"
  end

  test "reports missing end for transition" do
    source = """
    model Light
      state value = :off
      transition toggle do
        state.value = :on
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")
    assert error.message =~ "missing end for transition toggle"
  end

  test "reports bad model name" do
    source = """
    model 123Bad
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")
    assert error.message =~ "expected model declaration"
  end

  test "reports unexpected content inside model" do
    source = """
    model Light
      puts "nope"
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")
    assert error.message =~ "expected state or transition inside model"
  end

  test "reports unexpected content inside transition body" do
    source = """
    model Light
      state value = :off
      transition toggle do
        puts "nope"
      end
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")
    assert error.message =~ "expected state update or end inside transition body"
  end

  test "preserves source locations on model AST nodes" do
    source = """
    model Light
      state value = :off

      transition toggle do
        state.value = :on
      end
    end
    """

    assert {:ok, %Program{models: [model]}} = Yup.Parser.parse(source, path: "model.yup")
    assert %{line: 1, column: 1} = model.loc
    assert %{line: 2, column: 1} = hd(model.states).loc
    assert %{line: 4, column: 1} = hd(model.transitions).loc
  end

  test "parses model with atom containing special chars" do
    source = """
    model Flags
      state status = :ok?!
    end
    """

    assert {:ok, %Program{models: [%Model{states: [state]}]}} =
             Yup.Parser.parse(source, path: "model.yup")

    assert %Literal{kind: :atom, value: :"ok?!"} = state.value
  end
end
