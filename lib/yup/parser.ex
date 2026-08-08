defmodule Yup.Parser do
  @moduledoc """
  Hand-written bootstrap parser for the first tiny YupYup slice.

  This parser is intentionally small and line-oriented. It preserves source
  locations on AST nodes and keeps the AST independent from the BEAM backend.
  The architecture doc records this as a reversible bootstrap decision.
  """

  alias Yup.AST.{BinaryOp, Binding, Call, Function, Identifier, Literal, Program, UnaryOp}
  alias Yup.SourceError

  @binary_op_prec [
    or: ["or"],
    and: ["and"],
    equality: ["==", "!="],
    comparison: ["<", "<=", ">", ">="],
    addition: ["+", "-"],
    multiplication: ["*", "/"]
  ]

  def parse(source, opts \\ []) do
    path = Keyword.get(opts, :path)

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {text, line} -> {line, text} end)
    |> parse_program(path)
  rescue
    error in SourceError -> {:error, error}
  end

  defp parse_program(lines, path) do
    {forms, rest} = parse_forms(lines, path, [])

    case next_significant(rest) do
      nil ->
        functions = Enum.filter(forms, &match?(%Function{}, &1))
        body = Enum.reject(forms, &match?(%Function{}, &1))
        {:ok, %Program{source_path: path, functions: functions, body: body, loc: loc(1, 1)}}

      {line, _text} ->
        raise source_error(path, line, 1, "unexpected input")
    end
  end

  defp parse_forms([], _path, acc), do: {Enum.reverse(acc), []}

  defp parse_forms([{line, raw} | rest] = lines, path, acc) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_forms(rest, path, acc)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      String.starts_with?(trimmed, "def ") ->
        {function, after_function} = parse_function(line, text, rest, path)
        parse_forms(after_function, path, [function | acc])

      true ->
        statement = parse_statement(text, line, path)
        parse_forms(rest, path, [statement | acc])
    end
  end

  defp parse_function(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^def\s+([a-z_][a-zA-Z0-9_?!]*)\(([^)]*)\)\s*$/, trimmed) do
      [_, name, params_text] ->
        params =
          params_text
          |> split_args()
          |> Enum.map(fn param ->
            unless Regex.match?(~r/^[a-z_][a-zA-Z0-9_?!]*$/, param) do
              raise source_error(path, line, 1, "invalid parameter name #{inspect(param)}")
            end

            param
          end)

        {body, after_body} = parse_forms(rest, path, [])

        close_function(after_body, name, line, path, params, body)

      _ ->
        raise source_error(path, line, 1, "expected function definition like def hello(name)")
    end
  end

  defp close_function([{_end_line, end_text} | remaining], name, line, _path, params, body) do
    if String.trim(end_text) == "end" do
      {%Function{name: name, params: params, body: body, loc: loc(line, 1)}, remaining}
    else
      raise "internal parser error: function close called without end"
    end
  end

  defp close_function([], name, line, path, _params, _body) do
    raise source_error(path, line, 1, "missing end for function #{name}")
  end

  defp parse_statement(text, line, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^([a-z_][a-zA-Z0-9_?!]*)\s=\s(.+)$/, trimmed) do
      [_, name, expr] ->
        %Binding{name: name, value: parse_expression(expr, line, path), loc: loc(line, 1)}

      _ ->
        parse_expression(trimmed, line, path)
    end
  end

  defp parse_expression(text, line, path) do
    tokens = tokenize(text, line, path)
    {expr, rest} = parse_or(tokens, path)

    case rest do
      [] ->
        expr

      [%{value: value, column: column} | _] ->
        raise source_error(path, line, column, "unexpected token #{value}")
    end
  end

  defp parse_or(tokens, path),
    do: parse_prec(tokens, path, @binary_op_prec[:or], &parse_and/2)

  defp parse_and(tokens, path),
    do: parse_prec(tokens, path, @binary_op_prec[:and], &parse_equality/2)

  defp parse_equality(tokens, path),
    do: parse_prec(tokens, path, @binary_op_prec[:equality], &parse_comparison/2)

  defp parse_comparison(tokens, path),
    do: parse_prec(tokens, path, @binary_op_prec[:comparison], &parse_addition/2)

  defp parse_addition(tokens, path),
    do: parse_prec(tokens, path, @binary_op_prec[:addition], &parse_multiplication/2)

  defp parse_multiplication(tokens, path),
    do: parse_prec(tokens, path, @binary_op_prec[:multiplication], &parse_unary/2)

  defp parse_prec(tokens, path, ops, next) do
    {left, rest} = next.(tokens, path)
    parse_binary_tail(left, rest, path, ops, next)
  end

  defp parse_binary_tail(left, [token | rest] = tokens, path, ops, next) do
    if binary_op?(token, ops) do
      {right, remaining} = next.(rest, path)

      node = %BinaryOp{
        op: token.value,
        left: left,
        right: right,
        loc: loc(token.line, token.column)
      }

      parse_binary_tail(node, remaining, path, ops, next)
    else
      {left, tokens}
    end
  end

  defp parse_binary_tail(left, [], _path, _ops, _next), do: {left, []}

  defp binary_op?(%{type: :op, value: op}, ops), do: op in ops
  defp binary_op?(%{type: :identifier, value: op}, ops) when op in ["and", "or"], do: op in ops
  defp binary_op?(_token, _ops), do: false

  defp parse_unary(
         [%{type: :identifier, value: "not", line: line, column: column} | rest],
         path
       ) do
    {operand, remaining} = parse_unary(rest, path)
    {%UnaryOp{op: "not", operand: operand, loc: loc(line, column)}, remaining}
  end

  defp parse_unary(tokens, path), do: parse_primary(tokens, path)

  defp parse_primary([], path),
    do: raise(source_error(path, nil, nil, "unexpected end of expression"))

  defp parse_primary([%{type: :int, value: value, line: line, column: column} | rest], _path) do
    {%Literal{kind: :integer, value: String.to_integer(value), loc: loc(line, column)}, rest}
  end

  defp parse_primary([%{type: :string, value: value, line: line, column: column} | rest], _path) do
    {%Literal{kind: :string, value: value, loc: loc(line, column)}, rest}
  end

  defp parse_primary(
         [%{type: :identifier, value: "true", line: line, column: column} | rest],
         _path
       ) do
    {%Literal{kind: :boolean, value: true, loc: loc(line, column)}, rest}
  end

  defp parse_primary(
         [%{type: :identifier, value: "false", line: line, column: column} | rest],
         _path
       ) do
    {%Literal{kind: :boolean, value: false, loc: loc(line, column)}, rest}
  end

  defp parse_primary(
         [%{type: :identifier, value: "nil", line: line, column: column} | rest],
         _path
       ) do
    {%Literal{kind: nil, value: nil, loc: loc(line, column)}, rest}
  end

  defp parse_primary(
         [%{type: :identifier, value: name, line: line, column: column}, %{type: :lparen} | rest],
         path
       ) do
    {args, remaining} = parse_call_args(rest, path, [])
    {%Call{name: name, args: args, loc: loc(line, column)}, remaining}
  end

  defp parse_primary(
         [%{type: :identifier, value: "puts", line: line, column: column} | rest],
         path
       ) do
    {arg, remaining} = parse_or(rest, path)
    {%Call{name: "puts", args: [arg], loc: loc(line, column)}, remaining}
  end

  defp parse_primary(
         [%{type: :identifier, value: name, line: line, column: column} | rest],
         _path
       ) do
    {%Identifier{name: name, loc: loc(line, column)}, rest}
  end

  defp parse_primary([%{type: :lparen} | rest], path) do
    {expr, remaining} = parse_or(rest, path)

    case remaining do
      [%{type: :rparen} | tail] -> {expr, tail}
      [%{line: line, column: column} | _] -> raise source_error(path, line, column, "expected )")
      [] -> raise source_error(path, nil, nil, "expected )")
    end
  end

  defp parse_primary([%{value: value, line: line, column: column} | _], path) do
    raise source_error(path, line, column, "unexpected token #{value}")
  end

  defp parse_call_args([%{type: :rparen} | rest], _path, acc), do: {Enum.reverse(acc), rest}

  defp parse_call_args(tokens, path, acc) do
    {expr, rest} = parse_or(tokens, path)

    case rest do
      [%{type: :comma} | tail] ->
        parse_call_args(tail, path, [expr | acc])

      [%{type: :rparen} | tail] ->
        {Enum.reverse([expr | acc]), tail}

      [%{line: line, column: column} | _] ->
        raise source_error(path, line, column, "expected , or )")

      [] ->
        raise source_error(path, nil, nil, "expected )")
    end
  end

  defp tokenize(text, line, path), do: tokenize(text, line, path, 1, [])

  defp tokenize("", _line, _path, _column, acc), do: Enum.reverse(acc)

  defp tokenize(<<" ", rest::binary>>, line, path, column, acc),
    do: tokenize(rest, line, path, column + 1, acc)

  defp tokenize(<<"\t", rest::binary>>, line, path, column, acc),
    do: tokenize(rest, line, path, column + 1, acc)

  defp tokenize(<<"\"", rest::binary>>, line, path, column, acc) do
    case read_string(rest, "") do
      {:ok, value, remaining, consumed} ->
        token = %{type: :string, value: value, line: line, column: column}
        tokenize(remaining, line, path, column + consumed + 2, [token | acc])

      :error ->
        raise source_error(path, line, column, "unterminated string")
    end
  end

  for {char, type} <- [{"(", :lparen}, {")", :rparen}, {",", :comma}] do
    defp tokenize(<<unquote(char), rest::binary>>, line, path, column, acc) do
      token = %{type: unquote(type), value: unquote(char), line: line, column: column}
      tokenize(rest, line, path, column + 1, [token | acc])
    end
  end

  for op <- ["==", "!=", "<=", ">="] do
    defp tokenize(<<unquote(op), rest::binary>>, line, path, column, acc) do
      token = %{type: :op, value: unquote(op), line: line, column: column}
      tokenize(rest, line, path, column + byte_size(unquote(op)), [token | acc])
    end
  end

  for op <- ["+", "-", "*", "/", "<", ">"] do
    defp tokenize(<<unquote(op), rest::binary>>, line, path, column, acc) do
      token = %{type: :op, value: unquote(op), line: line, column: column}
      tokenize(rest, line, path, column + 1, [token | acc])
    end
  end

  defp tokenize(<<char, _rest::binary>> = text, line, path, column, acc) when char in ?0..?9 do
    {value, rest} = take_while(text, &(&1 in ?0..?9))
    token = %{type: :int, value: value, line: line, column: column}
    tokenize(rest, line, path, column + byte_size(value), [token | acc])
  end

  defp tokenize(<<char, _rest::binary>> = text, line, path, column, acc)
       when char in ?a..?z or char == ?_ do
    {value, rest} =
      take_while(text, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in [?_, ??, ?!]))

    token = %{type: :identifier, value: value, line: line, column: column}
    tokenize(rest, line, path, column + byte_size(value), [token | acc])
  end

  defp tokenize(<<char, _rest::binary>>, line, path, column, _acc) do
    raise source_error(path, line, column, "unexpected character #{inspect(<<char>>)}")
  end

  defp read_string(<<"\"", rest::binary>>, acc), do: {:ok, acc, rest, byte_size(acc)}
  defp read_string(<<"\\\"", rest::binary>>, acc), do: read_string(rest, acc <> "\"")
  defp read_string(<<"\\n", rest::binary>>, acc), do: read_string(rest, acc <> "\n")
  defp read_string("", _acc), do: :error

  defp read_string(<<char::binary-size(1), rest::binary>>, acc),
    do: read_string(rest, acc <> char)

  defp take_while(text, predicate), do: take_while(text, predicate, "")
  defp take_while("", _predicate, acc), do: {acc, ""}

  defp take_while(<<char, rest::binary>>, predicate, acc) do
    if predicate.(char) do
      take_while(rest, predicate, acc <> <<char>>)
    else
      {acc, <<char, rest::binary>>}
    end
  end

  defp split_args(""), do: []

  defp split_args(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp strip_comment(line), do: String.split(line, "#", parts: 2) |> hd()
  defp blank?(line), do: String.trim(line) == ""

  defp next_significant([]), do: nil

  defp next_significant([{line, text} | rest]) do
    if blank?(strip_comment(text)), do: next_significant(rest), else: {line, text}
  end

  defp loc(line, column), do: %{line: line, column: column}

  defp source_error(path, line, column, message) do
    %SourceError{path: path, line: line, column: column, message: message}
  end
end
