defmodule Yup.Compiler.Erlang do
  @moduledoc """
  Lowers YupYup AST into Erlang abstract forms.
  """

  alias Yup.AST.{
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

    exports = [
      {:run, 0} | Enum.map(program.functions, &{String.to_atom(&1.name), length(&1.params)})
    ]

    [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, exports}
    ] ++
      Enum.map(program.functions, &lower_function/1) ++ [lower_run(program.body)]
  end

  defp lower_function(%Function{} = function) do
    line = line(function)
    args = Enum.map(function.params, &var(&1, line))
    body_forms = body(function.body)

    {:function, line, String.to_atom(function.name), length(function.params),
     [{:clause, line, args, [], body_forms}]}
  end

  defp lower_run(body) do
    {:function, 1, :run, 0, [{:clause, 1, [], [], body(body)}]}
  end

  defp body([]), do: [{:atom, 1, :ok}]
  defp body(nodes), do: Enum.map(nodes, &expr/1)

  defp expr(%Literal{kind: :integer, value: value} = node), do: {:integer, line(node), value}
  defp expr(%Literal{kind: :boolean, value: value} = node), do: {:atom, line(node), value}
  defp expr(%Literal{kind: nil} = node), do: {:atom, line(node), nil}

  defp expr(%Literal{kind: :string, value: value} = node) do
    line = line(node)

    {:bin, line,
     [{:bin_element, line, {:string, line, String.to_charlist(value)}, :default, :default}]}
  end

  defp expr(%Identifier{name: name} = node), do: var(name, line(node))

  defp expr(%Binding{name: name, value: value} = node),
    do: {:match, line(node), var(name, line(node)), expr(value)}

  defp expr(%Call{name: "puts", args: [arg]} = node) do
    remote_call(line(node), :"Elixir.Yup.Runtime", :puts, [expr(arg)])
  end

  defp expr(%Call{name: name, args: args} = node) do
    {:call, line(node), {:atom, line(node), String.to_atom(name)}, Enum.map(args, &expr/1)}
  end

  defp expr(%BinaryOp{op: op, left: left, right: right} = node) do
    remote_call(line(node), :"Elixir.Yup.Runtime", runtime_for(op), [expr(left), expr(right)])
  end

  defp expr(%UnaryOp{op: "not", operand: operand} = node) do
    remote_call(line(node), :"Elixir.Yup.Runtime", :not_op, [expr(operand)])
  end

  defp expr(%Constructor{tag: tag, args: args} = node) do
    elements = [{:atom, line(node), String.to_atom(tag)} | Enum.map(args, &expr/1)]
    {:tuple, line(node), elements}
  end

  defp expr(%Match{subject: subject, clauses: clauses} = node) do
    subject_expr = expr(subject)
    counter = shared_counter()
    clause_forms = Enum.map(clauses, &lower_clause(&1, counter))

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

  defp lower_clause(%MatchClause{pattern: pattern, body: clause_body} = node, counter) do
    {pattern_ast, mapping} = pattern_ast(pattern, %{}, counter)
    renamed_body = rename_in_body(clause_body, mapping)
    body_forms = body(renamed_body)
    {:clause, line(node), [pattern_ast], [], body_forms}
  end

  defp pattern_ast(%LiteralPattern{literal: literal}, mapping, _counter) do
    {expr(literal), mapping}
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
    validate_scope!(program.body, MapSet.new(), program.source_path)

    Enum.each(program.functions, fn function ->
      bound = MapSet.new(function.params)
      validate_scope!(function.body, bound, program.source_path)
    end)
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
