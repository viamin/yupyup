defmodule Yup.Compiler.Erlang do
  @moduledoc """
  Lowers YupYup AST into Erlang abstract forms.
  """

  alias Yup.AST.{
    AnonymousFunction,
    BinaryOp,
    BinderPattern,
    Binding,
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

  alias Yup.SourceError

  # Names whose binding is reserved by the language: `puts` resolves to
  # `Yup.Runtime.puts/1` regardless of caller-scope state, so a local binding
  # would otherwise be silently shadowed by the dispatch clause above.
  @reserved_names MapSet.new(["puts"])

  def module_name(%Program{} = program) do
    key = program.source_path || :erlang.term_to_binary(program)

    hash =
      :crypto.hash(:sha256, to_string(key)) |> Base.encode16(case: :lower) |> binary_part(0, 12)

    :"yup_generated_#{hash}"
  end

  def lower(%Program{} = program) do
    validate_immutable_bindings!(program)

    Process.put(:yup_fresh_counter, :counters.new(1, []))
    module = module_name(program)
    function_names = MapSet.new(program.functions, & &1.name)

    exports = [
      {:run, 0} | Enum.map(program.functions, &{String.to_atom(&1.name), length(&1.params)})
    ]

    [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, exports}
    ] ++
      Enum.map(program.functions, &lower_function(&1, function_names)) ++
      [lower_run(program.body, function_names)]
  end

  defp lower_function(%Function{} = function, function_names) do
    line = line(function)
    args = Enum.map(function.params, &var(&1, line))

    {:function, line, String.to_atom(function.name), length(function.params),
     [{:clause, line, args, [], body(function.body, function_names)}]}
  end

  defp lower_run(body, function_names) do
    {:function, 1, :run, 0, [{:clause, 1, [], [], body(body, function_names)}]}
  end

  defp body([], _function_names), do: [{:atom, 1, :ok}]
  defp body(nodes, function_names), do: Enum.map(nodes, &expr(&1, function_names))

  defp expr(%Literal{kind: :integer, value: value} = node, _function_names),
    do: {:integer, line(node), value}

  defp expr(%Literal{kind: :boolean, value: value} = node, _function_names),
    do: {:atom, line(node), value}

  defp expr(%Literal{kind: nil} = node, _function_names), do: {:atom, line(node), nil}

  defp expr(%Literal{kind: :string, value: value} = node, _function_names) do
    line = line(node)

    {:bin, line,
     [{:bin_element, line, {:string, line, String.to_charlist(value)}, :default, :default}]}
  end

  defp expr(%Identifier{name: name} = node, _function_names), do: var(name, line(node))

  defp expr(%Binding{name: name, value: value} = node, function_names),
    do: {:match, line(node), var(name, line(node)), expr(value, function_names)}

  defp expr(%Call{name: "puts", args: [arg]} = node, function_names) do
    remote_call(line(node), :"Elixir.Yup.Runtime", :puts, [expr(arg, function_names)])
  end

  defp expr(%Call{name: name, args: args} = node, function_names) do
    line = line(node)
    call_args = Enum.map(args, &expr(&1, function_names))

    if MapSet.member?(function_names, name) do
      {:call, line, {:atom, line, String.to_atom(name)}, call_args}
    else
      {:call, line, var(name, line), call_args}
    end
  end

  defp expr(%BinaryOp{op: op, left: left, right: right} = node, function_names) do
    remote_call(line(node), :"Elixir.Yup.Runtime", runtime_for(op), [
      expr(left, function_names),
      expr(right, function_names)
    ])
  end

  defp expr(%UnaryOp{op: "not", operand: operand} = node, function_names) do
    remote_call(line(node), :"Elixir.Yup.Runtime", :not_op, [expr(operand, function_names)])
  end

  defp expr(%AnonymousFunction{params: params, body: fn_body} = node, function_names) do
    line = line(node)
    args = Enum.map(params, &var(&1, line))

    {:fun, line, {:clauses, [{:clause, line, args, [], body(fn_body, function_names)}]}}
  end

  defp expr(%Constructor{tag: tag, args: args} = node, function_names) do
    elements = [{:atom, line(node), String.to_atom(tag)} | Enum.map(args, &expr(&1, function_names))]
    {:tuple, line(node), elements}
  end

  defp expr(%Match{subject: subject, clauses: clauses} = node, function_names) do
    subject_expr = expr(subject, function_names)
    counter = shared_counter()
    clause_forms = Enum.map(clauses, &lower_clause(&1, function_names, counter))

    case clause_forms do
      [] -> raise "internal compiler error: match has no clauses"
      _ -> {:case, line(node), subject_expr, clause_forms}
    end
  end

  defp runtime_for("+"), do: :add
  defp runtime_for("-"), do: :subtract
  defp runtime_for("*"), do: :multiply
  defp runtime_for("/"), do: :divide
  defp runtime_for("=="), do: :equal?
  defp runtime_for("!="), do: :not_equal?
  defp runtime_for("<"), do: :less?
  defp runtime_for("<="), do: :less_or_equal?
  defp runtime_for(">"), do: :greater?
  defp runtime_for(">="), do: :greater_or_equal?
  defp runtime_for("and"), do: :and_op
  defp runtime_for("or"), do: :or_op
  defp runtime_for(other), do: raise("unknown binary operator #{inspect(other)}")

  defp lower_clause(%MatchClause{pattern: pattern, body: clause_body} = node, function_names, counter) do
    {pattern_ast, mapping} = pattern_ast(pattern, %{}, counter)
    renamed_body = rename_in_body(clause_body, mapping)
    body_forms = body(renamed_body, function_names)
    {:clause, line(node), [pattern_ast], [], body_forms}
  end

  defp pattern_ast(%LiteralPattern{literal: literal}, mapping, _counter) do
    {expr(literal, MapSet.new()), mapping}
  end

  defp pattern_ast(%BinderPattern{name: name} = node, mapping, counter) do
    fresh = fresh_name(name, counter)
    {var(fresh, line(node)), Map.put(mapping, name, fresh)}
  end

  defp pattern_ast(%ConstructorPattern{tag: tag, args: args} = node, mapping, counter) do
    {arg_asts, mapping} = Enum.map_reduce(args, mapping, &pattern_ast(&1, &2, counter))
    elements = [{:atom, line(node), String.to_atom(tag)} | arg_asts]
    {{:tuple, line(node), elements}, mapping}
  end

  defp fresh_name(name, counter) do
    n = :counters.get(counter, 1)
    :counters.add(counter, 1, 1)
    "#{name}_#{n}"
  end

  defp shared_counter do
    Process.get(:yup_fresh_counter) ||
      raise("internal compiler error: fresh-name counter not initialized")
  end

  defp rename_in_body(body, mapping) do
    Enum.map(body, fn node -> rename_in_node(node, mapping) end)
  end

  defp rename_in_node(%Identifier{name: name} = node, mapping) do
    case Map.fetch(mapping, name) do
      {:ok, fresh} -> %{node | name: fresh}
      :error -> node
    end
  end

  defp rename_in_node(%BinaryOp{left: left, right: right} = node, mapping) do
    %{
      node
      | left: rename_in_node(left, mapping),
        right: rename_in_node(right, mapping)
    }
  end

  defp rename_in_node(%UnaryOp{operand: operand} = node, mapping) do
    %{node | operand: rename_in_node(operand, mapping)}
  end

  defp rename_in_node(%Call{args: args} = node, mapping) do
    %{node | args: Enum.map(args, &rename_in_node(&1, mapping))}
  end

  defp rename_in_node(%Constructor{args: args} = node, mapping) do
    %{node | args: Enum.map(args, &rename_in_node(&1, mapping))}
  end

  defp rename_in_node(%Binding{value: value} = node, mapping) do
    %{node | value: rename_in_node(value, mapping)}
  end

  defp rename_in_node(%Match{subject: subject, clauses: clauses} = node, mapping) do
    %{
      node
      | subject: rename_in_node(subject, mapping),
        clauses: Enum.map(clauses, &rename_in_clause(&1, mapping))
    }
  end

  defp rename_in_node(node, _mapping), do: node

  defp rename_in_clause(%MatchClause{pattern: _pattern, body: body} = clause, mapping) do
    %{clause | body: rename_in_body(body, mapping)}
  end

  defp remote_call(line, module, function, args) do
    {:call, line, {:remote, line, {:atom, line, module}, {:atom, line, function}}, args}
  end

  defp var(name, line) do
    name =
      name
      |> Macro.camelize()
      |> String.to_atom()

    {:var, line, name}
  end

  defp validate_immutable_bindings!(%Program{} = program) do
    # Top-level `def`s and reserved runtime names occupy names that the
    # dispatch pass treats as direct atom calls (or remote `Runtime.puts/1`
    # calls). Without seeding the validator's bound set with them, a local
    # binding would be accepted here and then silently shadowed at lowering.
    reserved = reserved_names(program)

    Enum.each(program.functions, fn function ->
      if MapSet.member?(@reserved_names, function.name) do
        raise %SourceError{
          path: program.source_path,
          line: line(function),
          column: column(function),
          message: "cannot define function with reserved name #{function.name}"
        }
      end
    end)

    validate_scope!(program.body, reserved, program.source_path)

    Enum.each(program.functions, fn function ->
      bound = reserved |> MapSet.union(MapSet.new(function.params))
      validate_scope!(function.body, bound, program.source_path)
    end)
  end

  defp reserved_names(%Program{} = program) do
    MapSet.new(program.functions, & &1.name)
    |> MapSet.union(@reserved_names)
  end

  defp validate_scope!(nodes, bound, path) do
    Enum.reduce(nodes, bound, fn
      %Binding{name: name} = binding, seen ->
        if MapSet.member?(seen, name) do
          raise %SourceError{
            path: path,
            line: line(binding),
            column: column(binding),
            message: "cannot rebind immutable name #{name}"
          }
        end

        MapSet.put(seen, name)

      %Match{clauses: clauses}, seen ->
        Enum.each(clauses, fn %MatchClause{pattern: pattern, body: body} ->
          updated = add_binder_names(seen, pattern)
          validate_scope!(body, updated, path)
        end)

        seen

      _node, seen ->
        seen
    end)

    :ok
  end

  defp add_binder_names(seen, %BinderPattern{name: name}), do: MapSet.put(seen, name)

  defp add_binder_names(seen, %ConstructorPattern{args: args}),
    do: Enum.reduce(args, seen, fn arg, acc -> add_binder_names(acc, arg) end)

  defp add_binder_names(seen, _pattern), do: seen

  defp line(%{loc: %{line: line}}), do: line
  defp line(_node), do: 1

  defp column(%{loc: %{column: column}}), do: column
  defp column(_node), do: 1
end