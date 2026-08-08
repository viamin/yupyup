defmodule Yup.Compiler.Erlang do
  @moduledoc """
  Lowers YupYup AST into Erlang abstract forms.
  """

  alias Yup.AST.{BinaryOp, Binding, Call, Function, Identifier, Literal, Program}
  alias Yup.SourceError

  def module_name(%Program{} = program) do
    key = program.source_path || :erlang.term_to_binary(program)

    hash =
      :crypto.hash(:sha256, to_string(key)) |> Base.encode16(case: :lower) |> binary_part(0, 12)

    :"yup_generated_#{hash}"
  end

  def lower(%Program{} = program) do
    validate_immutable_bindings!(program)

    module = module_name(program)

    exports = [
      {:run, 0} | Enum.map(program.functions, &{String.to_atom(&1.name), length(&1.params)})
    ]

    [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, exports}
    ] ++ Enum.map(program.functions, &lower_function/1) ++ [lower_run(program.body)]
  end

  defp lower_function(%Function{} = function) do
    line = line(function)
    args = Enum.map(function.params, &var(&1, line))

    {:function, line, String.to_atom(function.name), length(function.params),
     [{:clause, line, args, [], body(function.body)}]}
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
    runtime =
      case op do
        "+" -> :add
        "-" -> :subtract
        "*" -> :multiply
        "/" -> :divide
      end

    remote_call(line(node), :"Elixir.Yup.Runtime", runtime, [expr(left), expr(right)])
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

      _node, seen ->
        seen
    end)

    :ok
  end

  defp line(%{loc: %{line: line}}), do: line
  defp line(_node), do: 1

  defp column(%{loc: %{column: column}}), do: column
  defp column(_node), do: 1
end
