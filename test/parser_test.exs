defmodule Yup.ParserTest do
  use ExUnit.Case, async: true

  alias Yup.AST.{
    AnonymousFunction,
    BinaryOp,
    BinderPattern,
    Binding,
    Call,
    Constructor,
    ConstructorPattern,
    FieldAccess,
    Function,
    Identifier,
    ListLiteral,
    Literal,
    LiteralPattern,
    MapLiteral,
    Match,
    MatchClause,
    Model,
    Parameter,
    Program,
    Record,
    RecordConstruction,
    RecordField,
    StateAccess,
    StateUpdate,
    TernaryOp,
    TypeRef,
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

  test "parses an anonymous function literal as a first-class function value" do
    assert {:ok,
            %Program{
              body: [
                %Binding{
                  name: "double",
                  value: %AnonymousFunction{params: ["x"], body: [%BinaryOp{op: "*"} = op]}
                }
              ]
            }} = Yup.Parser.parse("double = { |x| x * 2 }", path: "block.yup")

    assert %Identifier{name: "x"} = op.left
    assert %Literal{kind: :integer, value: 2} = op.right
  end

  test "parses an anonymous function literal with source location" do
    assert {:ok, %Program{body: [%AnonymousFunction{loc: loc}]}} =
             Yup.Parser.parse("{ |x| x }", path: "block.yup")

    assert loc == %{line: 1, column: 1}
  end

  test "parses an anonymous function with multiple block parameters" do
    assert {:ok, %Program{body: [%AnonymousFunction{params: ["x", "y"]}]}} =
             Yup.Parser.parse("{ |x, y| x + y }", path: "block.yup")
  end

  test "parses an anonymous function with no block parameters" do
    assert {:ok, %Program{body: [%AnonymousFunction{params: []}]}} =
             Yup.Parser.parse("{ || 42 }", path: "block.yup")
  end

  test "parses calling a name bound to a function value" do
    source = """
    double = { |x| x * 2 }
    puts double(4)
    """

    assert {:ok,
            %Program{
              body: [
                %Binding{name: "double", value: %AnonymousFunction{}},
                %Call{name: "puts", args: [%Call{name: "double", args: [%Literal{value: 4}]}]}
              ]
            }} = Yup.Parser.parse(source, path: "block.yup")
  end

  test "reports a missing closing brace for an anonymous function" do
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("{ |x| x * 2", path: "bad.yup")

    assert error.message == "expected }"
  end

  test "reports a missing pipe to start block parameters" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("values.map { x }", path: "bad.yup")

    assert error.message == "expected | to start block parameters"
  end

  test "reports an invalid separator between block parameters" do
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("{ |x x| x }", path: "bad.yup")

    assert error.message == "expected , or | in block parameters"
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

  test "parses record declaration into AST" do
    source = """
    record Person
      name
      age
    end
    """

    assert {:ok,
            %Program{
              records: [
                %Record{
                  name: "Person",
                  fields: [
                    %RecordField{name: "name"},
                    %RecordField{name: "age"}
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "record.yup")
  end

  test "parses record construction with keyword fields" do
    source = """
    record Person
      name
      age
    end

    person = Person.new(name: "Ada", age: 42)
    """

    assert {:ok,
            %Program{
              records: [
                %Record{
                  name: "Person",
                  fields: [
                    %RecordField{name: "name"},
                    %RecordField{name: "age"}
                  ]
                }
              ],
              body: [
                %Binding{
                  name: "person",
                  value: %RecordConstruction{
                    name: "Person",
                    fields: [
                      {"name", %Literal{kind: :string, value: "Ada"}, _},
                      {"age", %Literal{kind: :integer, value: 42}, _}
                    ]
                  }
                }
              ]
            }} = Yup.Parser.parse(source, path: "record.yup")
  end

  test "parses field access with dot syntax" do
    source = """
    record Person
      name
    end

    person = Person.new(name: "Ada")
    puts person.name
    """

    assert {:ok,
            %Program{
              body: [
                %Binding{},
                %Call{
                  args: [
                    %FieldAccess{
                      record: %Identifier{name: "person"},
                      field: "name"
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "record.yup")
  end

  test "parses chained field access" do
    assert {:ok,
            %Program{
              body: [
                %FieldAccess{
                  record: %FieldAccess{
                    record: %Identifier{name: "person"},
                    field: "address"
                  },
                  field: "city"
                }
              ]
            }} = Yup.Parser.parse("person.address.city", path: "expr.yup")
  end

  test "field access binds tighter than addition" do
    assert {:ok,
            %Program{
              body: [
                %BinaryOp{
                  op: "+",
                  right: %FieldAccess{field: "age", record: %Identifier{name: "person"}}
                }
              ]
            }} = Yup.Parser.parse("1 + person.age", path: "expr.yup")
  end

  # ── dot calls and chaining (issue #3) ───────────────────────────────

  test "parses a dot call as a receiver-first call" do
    assert {:ok,
            %Program{
              body: [
                %Call{
                  name: "double",
                  args: [],
                  receiver: %Literal{kind: :integer, value: 3}
                }
              ]
            }} = Yup.Parser.parse("3.double()", path: "expr.yup")
  end

  test "parses a dot call with arguments" do
    assert {:ok,
            %Program{
              body: [
                %Call{
                  name: "add",
                  args: [%Literal{kind: :integer, value: 4}],
                  receiver: %Identifier{name: "value"}
                }
              ]
            }} = Yup.Parser.parse("value.add(4)", path: "expr.yup")
  end

  test "preserves source location on a dot call" do
    assert {:ok, %Program{body: [%Call{loc: loc}]}} =
             Yup.Parser.parse("3.double()", path: "expr.yup")

    assert loc == %{line: 1, column: 3}
  end

  test "a bare field read remains a field access, not a call" do
    assert {:ok,
            %Program{
              body: [
                %FieldAccess{record: %Identifier{name: "person"}, field: "name"}
              ]
            }} = Yup.Parser.parse("person.name", path: "expr.yup")
  end

  test "a dot call with an empty argument list has no args" do
    assert {:ok,
            %Program{
              body: [%Call{name: "name", args: [], receiver: %Identifier{name: "person"}}]
            }} = Yup.Parser.parse("person.name()", path: "expr.yup")
  end

  test "dot calls chain left to right" do
    assert {:ok,
            %Program{
              body: [
                %Call{
                  name: "second",
                  args: [%Literal{kind: :integer, value: 4}],
                  receiver: %Call{name: "first", args: [], receiver: %Identifier{name: "value"}}
                }
              ]
            }} = Yup.Parser.parse("value.first().second(4)", path: "expr.yup")
  end

  test "mixes field reads and dot calls in a single chain" do
    assert {:ok,
            %Program{
              body: [
                %Call{
                  name: "length",
                  args: [],
                  receiver: %Call{
                    name: "format",
                    args: [],
                    receiver: %FieldAccess{
                      record: %Identifier{name: "person"},
                      field: "address"
                    }
                  }
                }
              ]
            }} = Yup.Parser.parse("person.address.format().length()", path: "expr.yup")
  end

  test "a dot call on a record construction chains correctly" do
    source = """
    record Person
      name
    end

    Person.new(name: "Ada").greet()
    """

    assert {:ok,
            %Program{
              body: [
                %Call{name: "greet", args: [], receiver: %RecordConstruction{name: "Person"}}
              ]
            }} = Yup.Parser.parse(source, path: "expr.yup")
  end

  test "dot calls bind tighter than binary operators" do
    assert {:ok,
            %Program{
              body: [
                %BinaryOp{
                  op: "+",
                  left: %Call{name: "double", args: [], receiver: %Literal{value: 1}},
                  right: %Call{name: "double", args: [], receiver: %Literal{value: 2}}
                }
              ]
            }} = Yup.Parser.parse("1.double() + 2.double()", path: "expr.yup")
  end

  test "record construction still constructs a record and does not become a dot call" do
    source = """
    record Person
      name
      age
    end

    person = Person.new(name: "Ada", age: 42)
    """

    assert {:ok,
            %Program{
              body: [
                %Binding{
                  value: %RecordConstruction{
                    name: "Person",
                    fields: [
                      {"name", %Literal{kind: :string, value: "Ada"}, _},
                      {"age", %Literal{kind: :integer, value: 42}, _}
                    ]
                  }
                }
              ]
            }} = Yup.Parser.parse(source, path: "expr.yup")
  end

  test "reports expected field name after . for malformed dot syntax" do
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("value.()", path: "bad.yup")

    assert error.message =~ "expected field name after ."
  end

  test "reports missing closing paren for a malformed dot call" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("value.operation(1", path: "bad.yup")

    assert error.message =~ "expected"
  end

  test "rejects a dot call on state access in a model expression" do
    source = """
    model Light

      transition toggle do
        state.value = state.value()
      end
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")

    assert error.message =~ "dot calls are not supported in model expressions"
  end

  test "rejects a dot call on a record construction in a model expression" do
    source = """
    record Light
      value
    end

    model Beacon
      state value = Light.new(value: :off).value()
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "model.yup")

    assert error.message =~ "dot calls are not supported in model expressions"
  end

  test "parses standalone atom literals" do
    assert {:ok, %Program{body: [%Call{args: [%Literal{kind: :atom, value: :weird}]}]}} =
             Yup.Parser.parse("puts :weird", path: "atom.yup")
  end

  test "reports missing end for record" do
    source = """
    record Person
      name
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "record.yup")

    assert error.message =~ "missing end for record Person"
  end

  test "rejects record declarations inside function bodies" do
    source = """
    def foo()
      record Person
        name
      end
    end
    """

    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse(source, path: "nested.yup")

    assert error.message =~ "record declarations are only allowed at the top level"
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

  # ── type annotations ──────────────────────────────────────────────

  test "parses an annotated function parameter into the AST" do
    source = """
    def greet(person: Person)
      person
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  name: "greet",
                  params: [
                    %Parameter{
                      name: "person",
                      type: %TypeRef{name: "Person"},
                      loc: %{line: 1, column: _}
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")
  end

  test "parses an annotated function return type into the AST" do
    source = """
    def greet(person) -> String
      person
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  name: "greet",
                  params: [%Parameter{name: "person", type: nil}],
                  return_type: %TypeRef{name: "String", loc: %{line: 1, column: _}}
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")
  end

  test "parses the annotated example from the type-annotation issue" do
    source = """
    def greet(person: Person) -> String
      "Hello, " + person.name
    end

    record Person
      name: String
    end
    """

    assert {:ok, program} = Yup.Parser.parse(source, path: "annotated.yup")

    assert [%Function{name: "greet", params: params, return_type: return_type, body: body}] =
             program.functions

    assert [%Parameter{name: "person", type: %TypeRef{name: "Person"}}] = params
    assert %TypeRef{name: "String"} = return_type
    assert [%BinaryOp{op: "+"}] = body

    assert [%Record{fields: [%RecordField{name: "name", type: %TypeRef{name: "String"}}]}] =
             program.records
  end

  test "preserves unannotated parameters when other parameters are annotated" do
    source = """
    def mixed(a: A, b)
      a + b
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  params: [
                    %Parameter{name: "a", type: %TypeRef{name: "A"}},
                    %Parameter{name: "b", type: nil}
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")
  end

  test "preserves unannotated record fields when other fields are annotated" do
    source = """
    record Person
      name: String
      age
    end
    """

    assert {:ok,
            %Program{
              records: [
                %Record{
                  fields: [
                    %RecordField{name: "name", type: %TypeRef{name: "String"}},
                    %RecordField{name: "age", type: nil}
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")
  end

  test "parses an unannotated function exactly as before" do
    source = """
    def hello(name)
      "Hello, " + name
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  name: "hello",
                  params: [%Parameter{name: "name", type: nil, loc: %{line: 1, column: _}}],
                  return_type: nil,
                  body: [%BinaryOp{}]
                }
              ]
            }} = Yup.Parser.parse(source, path: "untyped.yup")
  end

  test "parses an unannotated record exactly as before" do
    source = """
    record Person
      name
      age
    end
    """

    assert {:ok,
            %Program{
              records: [
                %Record{
                  fields: [
                    %RecordField{name: "name", type: nil},
                    %RecordField{name: "age", type: nil}
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "untyped.yup")
  end

  test "preserves source locations on parameter type annotations" do
    source = """
    def greet(person: Person)
      person
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  params: [
                    %Parameter{
                      name: "person",
                      type: %TypeRef{name: "Person", loc: %{line: 1, column: column}}
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")

    assert column == 19
  end

  test "preserves source locations on record field type annotations" do
    source = """
    record Person
      name: String
    end
    """

    assert {:ok,
            %Program{
              records: [
                %Record{
                  fields: [
                    %RecordField{
                      name: "name",
                      loc: %{line: 2, column: field_column},
                      type: %TypeRef{name: "String", loc: %{line: 2, column: type_column}}
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")

    assert field_column == 3
    assert type_column == 9
  end

  test "preserves correct column when parameter name matches a substring in def keyword" do
    # Regression: column_in searched the full "def" line, so for
    # "def d(d: D)" the "d" in the name matched inside "def" first.
    source = """
    def d(d: D)
      d
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  name: "d",
                  params: [
                    %Parameter{
                      name: "d",
                      type: %TypeRef{name: "D", loc: %{line: 1, column: type_col}},
                      loc: %{line: 1, column: name_col}
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "substring.yup")

    # "def d(d: D)"
    #  1234567890...
    #  d at column 7, D at column 10
    assert name_col == 7
    assert type_col == 10
  end

  test "preserves correct type column when params share the same type name" do
    # Regression: type_ref_for searched the full source for the type name,
    # so both params with the same type pointed at the first occurrence.
    source = """
    def f(a: A, b: A)
      a + b
    end
    """

    assert {:ok,
            %Program{
              functions: [
                %Function{
                  name: "f",
                  params: [
                    %Parameter{
                      name: "a",
                      type: %TypeRef{name: "A", loc: %{line: 1, column: first_type_col}},
                      loc: %{line: 1, column: first_name_col}
                    },
                    %Parameter{
                      name: "b",
                      type: %TypeRef{name: "A", loc: %{line: 1, column: second_type_col}},
                      loc: %{line: 1, column: second_name_col}
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "shared_type.yup")

    # "def f(a: A, b: A)"
    #  123456789...
    #  a at column 7, A at column 10 (first)
    #  b at column 13, A at column 16 (second)
    assert first_name_col == 7
    assert first_type_col == 10
    assert second_name_col == 13
    assert second_type_col == 16
  end

  test "preserves source locations on deeply indented record field type annotations" do
    source = "record Person\n        name: String\n      end\n"

    assert {:ok,
            %Program{
              records: [
                %Record{
                  fields: [
                    %RecordField{
                      name: "name",
                      loc: %{line: 2, column: field_column},
                      type: %TypeRef{name: "String", loc: %{line: 2, column: type_column}}
                    }
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")

    assert field_column == 9
    assert type_column == 15
  end

  test "preserves source locations on unannotated indented record fields" do
    source = "record Person\n    name\n    age\n  end\n"

    assert {:ok,
            %Program{
              records: [
                %Record{
                  fields: [
                    %RecordField{name: "name", loc: %{line: 2, column: 5}},
                    %RecordField{name: "age", loc: %{line: 3, column: 5}}
                  ]
                }
              ]
            }} = Yup.Parser.parse(source, path: "annotated.yup")
  end

  test "rejects an annotation whose type name is not an uppercase identifier" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("def f(x: string)\n  x\nend\n", path: "bad.yup")

    assert error.message =~ "invalid parameter"
  end

  # ── collections (issue #4) ──────────────────────────────────────────

  test "parses a list literal" do
    assert {:ok,
            %Program{
              body: [
                %ListLiteral{
                  elements: [
                    %Literal{kind: :integer, value: 1},
                    %Literal{kind: :integer, value: 2},
                    %Literal{kind: :integer, value: 3}
                  ],
                  loc: %{line: 1, column: 1}
                }
              ]
            }} = Yup.Parser.parse("[1, 2, 3]", path: "expr.yup")
  end

  test "parses an empty list literal" do
    assert {:ok, %Program{body: [%ListLiteral{elements: []}]}} =
             Yup.Parser.parse("[]", path: "expr.yup")
  end

  test "parses a map literal with identifier-shaped keys" do
    assert {:ok,
            %Program{
              body: [
                %MapLiteral{
                  entries: [
                    {"name", %Literal{kind: :string, value: "Ada"}, %{line: 1, column: 3}},
                    {"active", %Literal{kind: :boolean, value: true}, %{line: 1, column: 16}}
                  ],
                  loc: %{line: 1, column: 1}
                }
              ]
            }} = Yup.Parser.parse(~s({ name: "Ada", active: true }), path: "expr.yup")
  end

  test "disambiguates a block literal from a map literal by the leading pipe" do
    assert {:ok, %Program{body: [%Binding{value: %AnonymousFunction{params: ["x"]}}]}} =
             Yup.Parser.parse("double = { |x| x * 2 }", path: "expr.yup")

    assert {:ok, %Program{body: [%Binding{value: %MapLiteral{entries: entries}}]}} =
             Yup.Parser.parse(~s(point = { x: 1, y: 2 }), path: "expr.yup")

    assert [{"x", _, _}, {"y", _, _}] = entries
  end

  test "parses a dot call with a trailing block as the call's block field" do
    assert {:ok,
            %Program{
              body: [
                %Call{
                  name: "map",
                  args: [],
                  receiver: %Identifier{name: "values"},
                  block: %AnonymousFunction{params: ["value"]}
                }
              ]
            }} = Yup.Parser.parse("values.map { |value| value * 2 }", path: "expr.yup")
  end

  test "a dot call without a trailing block leaves the block field nil" do
    assert {:ok, %Program{body: [%Call{name: "length", block: nil}]}} =
             Yup.Parser.parse("values.length()", path: "expr.yup")
  end

  test "rejects a list literal missing its closing bracket" do
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("[1, 2", path: "bad.yup")

    assert error.message =~ "expected ] in list literal"
  end

  test "rejects a map literal with a missing value" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse("{ name: }", path: "bad.yup")

    assert error.message =~ "unexpected token }"
  end

  test "rejects a map literal with a duplicate key" do
    assert {:error, %Yup.SourceError{} = error} =
             Yup.Parser.parse(~s({ name: 1, name: 2 }), path: "bad.yup")

    assert error.message =~ "duplicate key name in map literal"
  end

  test "reports a key entry error for a brace literal with no pipe and no key" do
    # A `{` not followed by `|` starts a map literal (see docs/LANGUAGE.md),
    # so `{ x * 2 }` fails on the first entry, not on block parameters.
    assert {:error, %Yup.SourceError{} = error} = Yup.Parser.parse("{ x * 2 }", path: "bad.yup")

    assert error.message == "expected key: value entry in map literal"
  end
end
