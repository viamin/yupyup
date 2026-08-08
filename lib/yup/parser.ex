defmodule Yup.Parser do
  @moduledoc """
  Hand-written bootstrap parser for the first tiny YupYup slice.

  This parser is intentionally small and line-oriented. It preserves source
  locations on AST nodes and keeps the AST independent from the BEAM backend.
  The architecture doc records this as a reversible bootstrap decision.
  """

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
    Literal,
    LiteralPattern,
    Match,
    MatchClause,
    Model,
    ModelState,
    Parameter,
    Program,
    Record,
    RecordConstruction,
    RecordField,
    StateAccess,
    StateUpdate,
    TernaryOp,
    Transition,
    TypeRef,
    UnaryOp
  }

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
    {forms, rest} = parse_forms(lines, path, [], :top_level)

    case next_significant(rest) do
      nil ->
        functions = Enum.filter(forms, &match?(%Function{}, &1))
        records = Enum.filter(forms, &match?(%Record{}, &1))
        models = Enum.filter(forms, &match?(%Model{}, &1))

        body =
          Enum.reject(
            forms,
            &(match?(%Function{}, &1) or match?(%Record{}, &1) or match?(%Model{}, &1))
          )

        {:ok,
         %Program{
           source_path: path,
           functions: functions,
           records: records,
           body: body,
           models: models,
           loc: loc(1, 1)
         }}

      {line, _text} ->
        raise source_error(path, line, 1, "unexpected input")
    end
  end

  defp parse_forms([], _path, acc, _scope), do: {Enum.reverse(acc), []}

  defp parse_forms([{line, raw} | rest] = lines, path, acc, scope) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_forms(rest, path, acc, scope)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      trimmed == "when" or stray_when?(trimmed) ->
        raise source_error(path, line, 1, "stray when outside of match")

      String.starts_with?(trimmed, "def ") ->
        {function, after_function} = parse_function(line, text, rest, path)
        parse_forms(after_function, path, [function | acc], scope)

      String.starts_with?(trimmed, "record ") or trimmed == "record" ->
        if scope != :top_level do
          raise source_error(
                  path,
                  line,
                  1,
                  "record declarations are only allowed at the top level"
                )
        end

        {record, after_record} = parse_record(line, text, rest, path)
        parse_forms(after_record, path, [record | acc], scope)

      String.starts_with?(trimmed, "match ") or trimmed == "match" ->
        {match, after_match} = parse_match(line, text, rest, path)
        parse_forms(after_match, path, [match | acc], scope)

      String.starts_with?(trimmed, "model ") ->
        {model, after_model} = parse_model(line, text, rest, path)
        parse_forms(after_model, path, [model | acc], scope)

      true ->
        statement = parse_statement(text, line, path)
        parse_forms(rest, path, [statement | acc], scope)
    end
  end

  defp stray_when?("when " <> "=" <> _), do: false
  defp stray_when?("when " <> _), do: true
  defp stray_when?(_), do: false

  defp parse_function(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(
           ~r/^def\s+([a-z_][a-zA-Z0-9_?!]*)\(([^)]*)\)(?:\s*->\s*([A-Z][a-zA-Z0-9_]*))?\s*$/,
           trimmed
         ) do
      [_, name, params_text, return_type_name] ->
        params = parse_params(params_text, line, trimmed, path)
        return_type = type_ref_for(return_type_name, trimmed, :arrow, line, path)

        {body, after_body} = parse_forms(rest, path, [], :nested)

        close_function(after_body, name, line, path, params, body, return_type)

      [_, name, params_text] ->
        params = parse_params(params_text, line, trimmed, path)

        {body, after_body} = parse_forms(rest, path, [], :nested)

        close_function(after_body, name, line, path, params, body, nil)

      _ ->
        raise source_error(path, line, 1, "expected function definition like def hello(name)")
    end
  end

  defp parse_params(params_text, line, source, path) do
    params_text
    |> split_args()
    |> Enum.map(&parse_param(&1, line, source, path))
  end

  defp parse_param(text, line, source, path) do
    trimmed = String.trim(text)

    case Regex.run(
           ~r/^([a-z_][a-zA-Z0-9_?!]*)(?:\s*:\s*([A-Z][a-zA-Z0-9_]*))?$/,
           trimmed
         ) do
      [_, name, type_name] ->
        type = type_ref_for(type_name, source, :colon, line, path)
        %Parameter{name: name, type: type, loc: loc(line, column_in(source, name))}

      [_, name] ->
        %Parameter{name: name, loc: loc(line, column_in(source, name))}

      nil ->
        raise source_error(path, line, 1, "invalid parameter #{inspect(text)}")
    end
  end

  defp type_ref_for(nil, _source, _anchor, _line, _path), do: nil

  defp type_ref_for(type_name, source, anchor, line, path) do
    case find_after(source, anchor_marker(anchor)) do
      {:ok, offset, rest} ->
        case :binary.match(rest, type_name) do
          {type_pos, _} ->
            %TypeRef{name: type_name, loc: loc(line, offset + type_pos + 1)}

          :nomatch ->
            %TypeRef{name: type_name, loc: loc(line, 1)}
        end

      :error ->
        raise source_error(
                path,
                line,
                byte_size(source),
                "expected type annotation #{inspect(type_name)}"
              )
    end
  end

  defp anchor_marker(:colon), do: ":"
  defp anchor_marker(:arrow), do: "->"

  defp find_after(source, marker) do
    case :binary.match(source, marker) do
      {pos, len} ->
        {:ok, pos + len, binary_part(source, pos + len, byte_size(source) - pos - len)}

      :nomatch ->
        :error
    end
  end

  defp column_in(source, needle) when is_binary(source) and is_binary(needle) do
    case :binary.match(source, needle) do
      {pos, _length} -> pos + 1
      :nomatch -> 1
    end
  end

  defp column_in(_source, _needle), do: 1

  defp close_function(
         [{_end_line, end_text} | remaining],
         name,
         line,
         _path,
         params,
         body,
         return_type
       ) do
    if String.trim(end_text) == "end" do
      fn_ast =
        %Function{
          name: name,
          params: params,
          body: body,
          return_type: return_type,
          loc: loc(line, 1)
        }

      {fn_ast, remaining}
    else
      raise "internal parser error: function close called without end"
    end
  end

  defp close_function([], name, line, path, _params, _body, _return_type) do
    raise source_error(path, line, 1, "missing end for function #{name}")
  end

  defp parse_record(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^record\s+([A-Z][a-zA-Z0-9_]*)\s*$/, trimmed) do
      [_, name] ->
        {fields, after_body} = parse_record_fields(rest, path, [])
        close_record(after_body, name, line, path, fields)

      _ ->
        raise source_error(path, line, 1, "expected record declaration like record Person")
    end
  end

  defp close_record([{_end_line, end_text} | remaining], name, line, _path, fields) do
    if String.trim(end_text) == "end" do
      {%Record{name: name, fields: fields, loc: loc(line, 1)}, remaining}
    else
      raise "internal parser error: record close called without end"
    end
  end

  defp close_record([], name, line, path, _fields) do
    raise source_error(path, line, 1, "missing end for record #{name}")
  end

  defp parse_record_fields([], _path, acc), do: {Enum.reverse(acc), []}

  defp parse_record_fields([{line, raw} | rest] = lines, path, acc) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_record_fields(rest, path, acc)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      true ->
        case Regex.run(
               ~r/^([a-z_][a-zA-Z0-9_?!]*)(?:\s*:\s*([A-Z][a-zA-Z0-9_]*))?\s*$/,
               trimmed
             ) do
          [_, field, type_name] ->
            field_ast =
              %RecordField{
                name: field,
                type: type_ref_for(type_name, text, :colon, line, path),
                loc: loc(line, column_in(text, field))
              }

            parse_record_fields(rest, path, [field_ast | acc])

          [_, field] ->
            parse_record_fields(rest, path, [
              %RecordField{name: field, loc: loc(line, column_in(text, field))} | acc
            ])

          _ ->
            raise source_error(path, line, 1, "expected field name or end in record body")
        end
    end
  end

  defp parse_match(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^match\s+(.+)$/, trimmed) do
      [_, subject_text] ->
        subject = parse_expression(subject_text, line, path)
        {clauses, after_match} = parse_match_clauses(rest, path, [])
        close_match(after_match, subject, line, path, clauses)

      _ ->
        raise source_error(path, line, 1, "expected match expression like match value")
    end
  end

  defp close_match([{_end_line, end_text} | remaining], subject, line, _path, clauses) do
    if String.trim(end_text) == "end" do
      {%Match{subject: subject, clauses: clauses, loc: loc(line, 1)}, remaining}
    else
      raise "internal parser error: match close called without end"
    end
  end

  defp close_match([], _subject, line, path, _clauses) do
    raise source_error(path, line, 1, "missing end for match")
  end

  # ── model declarations ──────────────────────────────────────────────

  defp parse_model(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^model\s+([A-Z][a-zA-Z0-9_]*)\s*$/, trimmed) do
      [_, name] ->
        {body, after_model} = parse_model_body(rest, path, [])
        close_model(after_model, name, line, path, body)

      _ ->
        raise source_error(path, line, 1, "expected model declaration like model Light")
    end
  end

  defp close_model([{_end_line, end_text} | remaining], name, line, _path, body) do
    if String.trim(end_text) == "end" do
      states = Enum.filter(body, &match?(%ModelState{}, &1))
      transitions = Enum.filter(body, &match?(%Transition{}, &1))
      {%Model{name: name, states: states, transitions: transitions, loc: loc(line, 1)}, remaining}
    else
      raise "internal parser error: model close called without end"
    end
  end

  defp close_model([], name, line, path, _body) do
    raise source_error(path, line, 1, "missing end for model #{name}")
  end

  defp parse_model_body([], _path, acc), do: {Enum.reverse(acc), []}

  defp parse_model_body([{line, raw} | rest] = lines, path, acc) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_model_body(rest, path, acc)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      String.starts_with?(trimmed, "state ") ->
        {state, after_state} = parse_model_state(line, text, rest, path)
        parse_model_body(after_state, path, [state | acc])

      String.starts_with?(trimmed, "transition ") ->
        {transition, after_transition} = parse_transition(line, text, rest, path)
        parse_model_body(after_transition, path, [transition | acc])

      true ->
        raise source_error(path, line, 1, "expected state or transition inside model")
    end
  end

  defp parse_model_state(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^state\s+([a-z_][a-zA-Z0-9_?!]*)\s*=\s*(.+)$/, trimmed) do
      [_, name, expr_text] ->
        value = parse_model_expression(expr_text, line, path)
        {%ModelState{name: name, value: value, loc: loc(line, 1)}, rest}

      _ ->
        raise source_error(path, line, 1, "expected state declaration like state value = :off")
    end
  end

  defp parse_transition(line, text, rest, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^transition\s+([a-z_][a-zA-Z0-9_?!]*)\s+do\s*$/, trimmed) do
      [_, name] ->
        {body, after_transition} = parse_transition_body(rest, path, [])
        close_transition(after_transition, name, line, path, body)

      _ ->
        raise source_error(
                path,
                line,
                1,
                "expected transition declaration like transition toggle do"
              )
    end
  end

  defp close_transition([{_end_line, end_text} | remaining], name, line, _path, body) do
    if String.trim(end_text) == "end" do
      {%Transition{name: name, body: body, loc: loc(line, 1)}, remaining}
    else
      raise "internal parser error: transition close called without end"
    end
  end

  defp close_transition([], name, line, path, _body) do
    raise source_error(path, line, 1, "missing end for transition #{name}")
  end

  defp parse_transition_body([], _path, acc), do: {Enum.reverse(acc), []}

  defp parse_transition_body([{line, raw} | rest] = lines, path, acc) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_transition_body(rest, path, acc)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      String.starts_with?(trimmed, "state.") ->
        statement = parse_transition_statement(text, line, path)
        parse_transition_body(rest, path, [statement | acc])

      true ->
        raise source_error(path, line, 1, "expected state update or end inside transition body")
    end
  end

  defp parse_transition_statement(text, line, path) do
    trimmed = String.trim(text)

    case Regex.run(~r/^state\.([a-z_][a-zA-Z0-9_?!]*)\s*=\s*(.+)$/, trimmed) do
      [_, name, expr_text] ->
        value = parse_model_expression(expr_text, line, path)
        %StateUpdate{name: name, value: value, loc: loc(line, 1)}

      _ ->
        expr = parse_model_expression(trimmed, line, path)
        expr
    end
  end

  # ── model expressions (atoms, ternary, access) ─────────────────────

  defp parse_model_expression(text, line, path) do
    tokens = tokenize(text, line, path)
    {expr, rest} = parse_ternary(tokens, path)

    case rest do
      [] ->
        expr

      [%{value: value, column: column} | _] ->
        raise source_error(path, line, column, "unexpected token #{value}")
    end
  end

  defp parse_ternary(tokens, path) do
    {condition, rest} = parse_or(tokens, path)

    case rest do
      [%{type: :question} | then_tokens] ->
        {then_expr, after_then} = parse_ternary(then_tokens, path)

        case after_then do
          [%{type: :colon} | else_tokens] ->
            {else_expr, remaining} = parse_ternary(else_tokens, path)

            node = %TernaryOp{
              condition: condition,
              then_expr: then_expr,
              else_expr: else_expr,
              loc: loc(line_from(condition), column_from(condition))
            }

            {node, remaining}

          _ ->
            raise source_error(
                    path,
                    line_from(condition),
                    column_from(condition),
                    "expected : in ternary expression"
                  )
        end

      _ ->
        {condition, rest}
    end
  end

  defp line_from(%{loc: %{line: line}}), do: line
  defp line_from(_), do: 1

  defp column_from(%{loc: %{column: column}}), do: column
  defp column_from(_), do: 1

  defp parse_match_clauses([], _path, acc), do: {Enum.reverse(acc), []}

  defp parse_match_clauses([{line, raw} | rest] = lines, path, acc) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_match_clauses(rest, path, acc)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      trimmed == "when" or String.starts_with?(trimmed, "when ") ->
        {clause, after_clause} = parse_match_clause(line, text, rest, path)
        parse_match_clauses(after_clause, path, [clause | acc])

      true ->
        raise source_error(path, line, 1, "expected when clause or end in match")
    end
  end

  defp parse_match_clause(line, text, rest, path) do
    pattern_text =
      text
      |> String.trim()
      |> strip_when_prefix()

    pattern = parse_pattern(pattern_text, line, path)
    {body, after_body} = parse_clause_body(rest, path, [])
    close_match_clause(after_body, pattern, line, path, body)
  end

  defp strip_when_prefix("when " <> rest), do: rest
  defp strip_when_prefix("when"), do: ""

  defp close_match_clause(
         [{_line, next_text} | _] = lines,
         pattern,
         line,
         path,
         body
       ) do
    trimmed = String.trim(next_text)
    trimmed_when = trimmed == "when" or String.starts_with?(trimmed, "when ")
    trimmed_end = trimmed == "end"

    if trimmed_when or trimmed_end or blank?(next_text) do
      {%MatchClause{pattern: pattern, body: body, loc: loc(line, 1)}, lines}
    else
      raise source_error(path, line, 1, "expected when clause, end, or blank line in match body")
    end
  end

  defp close_match_clause([], _pattern, line, path, _body) do
    raise source_error(path, line, 1, "missing end for match clause")
  end

  defp parse_clause_body([], _path, acc), do: {Enum.reverse(acc), []}

  defp parse_clause_body([{line, raw} | rest] = lines, path, acc) do
    text = strip_comment(raw)
    trimmed = String.trim(text)

    cond do
      blank?(text) ->
        parse_clause_body(rest, path, acc)

      trimmed == "end" ->
        {Enum.reverse(acc), lines}

      trimmed == "when" or String.starts_with?(trimmed, "when ") ->
        {Enum.reverse(acc), lines}

      true ->
        statement = parse_statement(text, line, path)
        parse_clause_body(rest, path, [statement | acc])
    end
  end

  defp parse_pattern(text, line, path) do
    trimmed = String.trim(text)

    if trimmed == "" do
      raise source_error(path, line, 1, "missing pattern after when")
    end

    tokens = tokenize(trimmed, line, path)

    case tokens do
      [] ->
        raise source_error(path, line, 1, "missing pattern after when")

      _ ->
        parse_pattern_tokens(tokens, path, trimmed, line)
    end
  end

  defp parse_pattern_tokens(
         [%{type: :tag, value: tag, line: tl, column: tc}, %{type: :lparen} | rest],
         path,
         _text,
         line
       ) do
    {args, remaining} = parse_pattern_args(rest, path, [])

    case remaining do
      [%{type: :rparen} | tail] ->
        ensure_no_trailing_tokens(tail, path, line)
        %ConstructorPattern{tag: tag, args: Enum.reverse(args), loc: loc(tl, tc)}

      [%{line: el, column: ec} | _] ->
        raise source_error(path, el, ec, "expected ) in pattern")

      [] ->
        raise source_error(path, line, 1, "expected ) in pattern")
    end
  end

  defp parse_pattern_tokens(
         [%{type: :int, value: value, line: tl, column: tc} | rest],
         path,
         _text,
         line
       ) do
    ensure_no_trailing_tokens(rest, path, line)
    literal = %Literal{kind: :integer, value: String.to_integer(value), loc: loc(tl, tc)}
    %LiteralPattern{literal: literal, loc: loc(tl, tc)}
  end

  defp parse_pattern_tokens(
         [%{type: :string, value: value, line: tl, column: tc} | rest],
         path,
         _text,
         line
       ) do
    ensure_no_trailing_tokens(rest, path, line)
    literal = %Literal{kind: :string, value: value, loc: loc(tl, tc)}
    %LiteralPattern{literal: literal, loc: loc(tl, tc)}
  end

  defp parse_pattern_tokens(
         [%{type: :identifier, value: "true", line: tl, column: tc} | rest],
         path,
         _text,
         line
       ) do
    ensure_no_trailing_tokens(rest, path, line)
    literal = %Literal{kind: :boolean, value: true, loc: loc(tl, tc)}
    %LiteralPattern{literal: literal, loc: loc(tl, tc)}
  end

  defp parse_pattern_tokens(
         [%{type: :identifier, value: "false", line: tl, column: tc} | rest],
         path,
         _text,
         line
       ) do
    ensure_no_trailing_tokens(rest, path, line)
    literal = %Literal{kind: :boolean, value: false, loc: loc(tl, tc)}
    %LiteralPattern{literal: literal, loc: loc(tl, tc)}
  end

  defp parse_pattern_tokens(
         [%{type: :identifier, value: "nil", line: tl, column: tc} | rest],
         path,
         _text,
         line
       ) do
    ensure_no_trailing_tokens(rest, path, line)
    literal = %Literal{kind: nil, value: nil, loc: loc(tl, tc)}
    %LiteralPattern{literal: literal, loc: loc(tl, tc)}
  end

  defp parse_pattern_tokens(
         [%{type: :identifier, value: name, line: tl, column: tc} | rest],
         path,
         _text,
         line
       ) do
    ensure_no_trailing_tokens(rest, path, line)
    %BinderPattern{name: name, loc: loc(tl, tc)}
  end

  defp parse_pattern_tokens([%{line: tl, column: tc, value: value} | _], path, _line, _text) do
    raise source_error(path, tl, tc, "invalid pattern #{inspect(value)}")
  end

  defp ensure_no_trailing_tokens([], _path, _line), do: :ok

  defp ensure_no_trailing_tokens([%{line: tl, column: tc, value: value} | _], path, _line) do
    raise source_error(path, tl, tc, "unexpected trailing token #{inspect(value)} in pattern")
  end

  defp parse_pattern_args([%{type: :rparen} | _] = tokens, _path, acc),
    do: {Enum.reverse(acc), tokens}

  defp parse_pattern_args([], path, _acc) do
    raise source_error(path, nil, nil, "expected ) in pattern")
  end

  defp parse_pattern_args([%{type: :comma} | _] = tokens, path, _acc) do
    {line, column, _} = first_token_location(tokens)
    raise source_error(path, line, column, "unexpected , in pattern")
  end

  defp parse_pattern_args(tokens, path, acc) do
    {pattern, rest} = parse_one_pattern(tokens, path)

    case rest do
      [%{type: :comma} | tail] ->
        parse_pattern_args(tail, path, [pattern | acc])

      [%{type: :rparen} | _] = tail ->
        {[pattern | acc], tail}

      [%{line: line, column: column} | _] ->
        raise source_error(path, line, column, "expected , or ) in pattern")

      [] ->
        raise source_error(path, nil, nil, "expected ) in pattern")
    end
  end

  defp parse_one_pattern([], path) do
    raise source_error(path, nil, nil, "unexpected end of pattern")
  end

  defp parse_one_pattern(
         [%{type: :tag, value: tag, line: tl, column: tc}, %{type: :lparen} | rest],
         path
       ) do
    {args, remaining} = parse_pattern_args(rest, path, [])

    case remaining do
      [%{type: :rparen} | _] ->
        {%ConstructorPattern{tag: tag, args: Enum.reverse(args), loc: loc(tl, tc)}, remaining}

      [%{line: el, column: ec} | _] ->
        raise source_error(path, el, ec, "expected ) in pattern")

      [] ->
        raise source_error(path, nil, nil, "expected ) in pattern")
    end
  end

  defp parse_one_pattern([%{type: :int, value: value, line: tl, column: tc} | rest], _path) do
    literal = %Literal{kind: :integer, value: String.to_integer(value), loc: loc(tl, tc)}
    {%LiteralPattern{literal: literal, loc: loc(tl, tc)}, rest}
  end

  defp parse_one_pattern([%{type: :string, value: value, line: tl, column: tc} | rest], _path) do
    literal = %Literal{kind: :string, value: value, loc: loc(tl, tc)}
    {%LiteralPattern{literal: literal, loc: loc(tl, tc)}, rest}
  end

  defp parse_one_pattern(
         [%{type: :identifier, value: "true", line: tl, column: tc} | rest],
         _path
       ) do
    literal = %Literal{kind: :boolean, value: true, loc: loc(tl, tc)}
    {%LiteralPattern{literal: literal, loc: loc(tl, tc)}, rest}
  end

  defp parse_one_pattern(
         [%{type: :identifier, value: "false", line: tl, column: tc} | rest],
         _path
       ) do
    literal = %Literal{kind: :boolean, value: false, loc: loc(tl, tc)}
    {%LiteralPattern{literal: literal, loc: loc(tl, tc)}, rest}
  end

  defp parse_one_pattern([%{type: :identifier, value: "nil", line: tl, column: tc} | rest], _path) do
    literal = %Literal{kind: nil, value: nil, loc: loc(tl, tc)}
    {%LiteralPattern{literal: literal, loc: loc(tl, tc)}, rest}
  end

  defp parse_one_pattern(
         [%{type: :identifier, value: name, line: tl, column: tc} | rest],
         _path
       ) do
    {%BinderPattern{name: name, loc: loc(tl, tc)}, rest}
  end

  defp parse_one_pattern([%{line: line, column: column, value: value} | _], path) do
    raise source_error(path, line, column, "invalid pattern #{inspect(value)}")
  end

  defp first_token_location([%{line: line, column: column} | _]), do: {line, column, nil}

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

  defp parse_unary(tokens, path), do: parse_postfix(tokens, path)

  defp parse_postfix(tokens, path) do
    {expr, rest} = parse_primary(tokens, path)
    parse_postfix_tail(expr, rest, path)
  end

  defp parse_postfix_tail(expr, [%{type: :dot, line: dot_line, column: dot_column} | rest], path) do
    case rest do
      [%{type: :identifier, value: field, line: line, column: column} | after_field] ->
        node = %FieldAccess{record: expr, field: field, loc: loc(line, column)}
        parse_postfix_tail(node, after_field, path)

      [%{line: line, column: column} | _] ->
        raise source_error(path, line, column, "expected field name after .")

      [] ->
        raise source_error(path, dot_line, dot_column, "expected field name after .")
    end
  end

  defp parse_postfix_tail(expr, rest, _path), do: {expr, rest}

  defp parse_primary([], path),
    do: raise(source_error(path, nil, nil, "unexpected end of expression"))

  defp parse_primary([%{type: :int, value: value, line: line, column: column} | rest], _path) do
    {%Literal{kind: :integer, value: String.to_integer(value), loc: loc(line, column)}, rest}
  end

  defp parse_primary([%{type: :string, value: value, line: line, column: column} | rest], _path) do
    {%Literal{kind: :string, value: value, loc: loc(line, column)}, rest}
  end

  defp parse_primary([%{type: :atom, value: value, line: line, column: column} | rest], _path) do
    {%Literal{kind: :atom, value: String.to_atom(value), loc: loc(line, column)}, rest}
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
         [%{type: :identifier, value: "puts", line: line, column: column} | rest],
         path
       ) do
    {arg, remaining} = parse_or(rest, path)
    {%Call{name: "puts", args: [arg], loc: loc(line, column)}, remaining}
  end

  defp parse_primary(
         [%{type: :tag, value: tag, line: line, column: column}, %{type: :lparen} | rest],
         path
       ) do
    {args, remaining} = parse_call_args(rest, path, [])
    {%Constructor{tag: tag, args: args, loc: loc(line, column)}, remaining}
  end

  defp parse_primary(
         [
           %{type: :tag, value: tag, line: tl, column: tc},
           %{type: :dot},
           %{type: :identifier, value: "new", line: _ml, column: _mc},
           %{type: :lparen} | rest
         ],
         path
       ) do
    {fields, remaining} = parse_record_construction_args(rest, path, [])
    {%RecordConstruction{name: tag, fields: fields, loc: loc(tl, tc)}, remaining}
  end

  defp parse_primary(
         [%{type: :identifier, value: name, line: line, column: column}, %{type: :lparen} | rest],
         path
       ) do
    {args, remaining} = parse_call_args(rest, path, [])
    {%Call{name: name, args: args, loc: loc(line, column)}, remaining}
  end

  defp parse_primary(
         [
           %{type: :identifier, value: "state", line: line, column: column},
           %{type: :dot},
           %{type: :identifier, value: name}
           | rest
         ],
         _path
       ) do
    {%StateAccess{name: name, loc: loc(line, column)}, rest}
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

  defp parse_primary([%{type: :lbrace, line: line, column: column} | rest], path) do
    {params, after_params} = parse_block_params(rest, path)
    {body_expr, after_body} = parse_or(after_params, path)

    case after_body do
      [%{type: :rbrace} | tail] ->
        {%AnonymousFunction{params: params, body: [body_expr], loc: loc(line, column)}, tail}

      [%{line: line, column: column} | _] ->
        raise source_error(path, line, column, "expected }")

      [] ->
        raise source_error(path, nil, nil, "expected }")
    end
  end

  defp parse_primary([%{value: value, line: line, column: column} | _], path) do
    raise source_error(path, line, column, "unexpected token #{value}")
  end

  defp parse_block_params([%{type: :pipe} | rest], path),
    do: parse_block_param_names(rest, path, [])

  defp parse_block_params([%{line: line, column: column} | _], path) do
    raise source_error(path, line, column, "expected | to start block parameters")
  end

  defp parse_block_params([], path) do
    raise source_error(path, nil, nil, "expected | to start block parameters")
  end

  defp parse_block_param_names([%{type: :pipe} | rest], _path, acc), do: {Enum.reverse(acc), rest}

  defp parse_block_param_names([%{type: :identifier, value: name} | rest], path, acc) do
    case rest do
      [%{type: :comma} | tail] ->
        parse_block_param_names(tail, path, [name | acc])

      [%{type: :pipe} | tail] ->
        {Enum.reverse([name | acc]), tail}

      [%{line: line, column: column} | _] ->
        raise source_error(path, line, column, "expected , or | in block parameters")

      [] ->
        raise source_error(path, nil, nil, "expected | to close block parameters")
    end
  end

  defp parse_block_param_names([%{line: line, column: column} | _], path, _acc) do
    raise source_error(path, line, column, "expected block parameter name")
  end

  defp parse_block_param_names([], path, _acc) do
    raise source_error(path, nil, nil, "expected | to close block parameters")
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

  defp parse_record_construction_args([%{type: :rparen} | rest], _path, acc),
    do: {Enum.reverse(acc), rest}

  defp parse_record_construction_args(
         [%{type: :kwarg, value: name, line: line, column: column} | rest],
         path,
         acc
       ) do
    {value, after_value} = parse_or(rest, path)
    field = {name, value, loc(line, column)}

    case after_value do
      [%{type: :comma} | tail] ->
        parse_record_construction_args(tail, path, [field | acc])

      [%{type: :rparen} | tail] ->
        {Enum.reverse([field | acc]), tail}

      [%{line: el, column: ec} | _] ->
        raise source_error(path, el, ec, "expected , or ) in record fields")

      [] ->
        raise source_error(path, nil, nil, "expected ) in record fields")
    end
  end

  defp parse_record_construction_args([%{line: line, column: column} | _], path, _acc) do
    raise source_error(path, line, column, "expected field name in record construction")
  end

  defp parse_record_construction_args([], path, _acc) do
    raise source_error(path, nil, nil, "expected ) in record construction")
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

  for {char, type} <- [
        {"(", :lparen},
        {")", :rparen},
        {",", :comma},
        {".", :dot},
        {"{", :lbrace},
        {"}", :rbrace},
        {"|", :pipe}
      ] do
    defp tokenize(<<unquote(char), rest::binary>>, line, path, column, acc) do
      token = %{type: unquote(type), value: unquote(char), line: line, column: column}
      tokenize(rest, line, path, column + 1, [token | acc])
    end
  end

  defp tokenize(<<"?", rest::binary>>, line, path, column, acc) do
    token = %{type: :question, value: "?", line: line, column: column}
    tokenize(rest, line, path, column + 1, [token | acc])
  end

  defp tokenize(<<":", rest::binary>>, line, path, column, acc) do
    case rest do
      <<char, _::binary>> when char in ?a..?z or char in ?A..?Z or char == ?_ or char == ?? ->
        {value, remaining} =
          take_while(rest, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in [?_, ??, ?!]))

        token = %{type: :atom, value: value, line: line, column: column}
        tokenize(remaining, line, path, column + byte_size(value) + 1, [token | acc])

      _ ->
        token = %{type: :colon, value: ":", line: line, column: column}
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
       when char in ?A..?Z do
    {value, rest} = take_while(text, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 == ?_))

    token = %{type: :tag, value: value, line: line, column: column}
    tokenize(rest, line, path, column + byte_size(value), [token | acc])
  end

  defp tokenize(<<char, _rest::binary>> = text, line, path, column, acc)
       when char in ?a..?z or char == ?_ do
    {value, rest} =
      take_while(text, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 in [?_, ??, ?!]))

    case rest do
      <<":", after_colon::binary>> ->
        token = %{type: :kwarg, value: value, line: line, column: column}
        tokenize(after_colon, line, path, column + byte_size(value) + 1, [token | acc])

      _ ->
        token = %{type: :identifier, value: value, line: line, column: column}
        tokenize(rest, line, path, column + byte_size(value), [token | acc])
    end
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
