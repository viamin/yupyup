defmodule Yup.Export.Tla do
  @moduledoc """
  Exports a finite model to a TLA+ module for cross-checking with an
  external TLC installation (issue #20).

  The exporter consumes the same model boundary as `Yup.Verify`: state
  fields become TLA+ variables, initializer values become `Init`, each
  transition becomes a next-state action, and each invariant becomes a
  numbered TLA+ invariant definition. Transition bodies translate so that
  fields assigned earlier in the same body are read primed and unassigned
  fields stay `UNCHANGED`, and operands that are not statically boolean are
  compared against `FALSE` so boolean operators keep YupYup truthiness.
  Unsupported syntax fails with a source-located diagnostic rather than
  emitting a module that TLC would misread.
  """

  alias Yup.AST.{
    AnonymousFunction,
    BinaryOp,
    Call,
    Constructor,
    FieldAccess,
    Identifier,
    Invariant,
    ListLiteral,
    Literal,
    MapLiteral,
    Match,
    Model,
    ModelState,
    Program,
    RecordConstruction,
    StateAccess,
    StateUpdate,
    TernaryOp,
    Transition,
    UnaryOp
  }

  alias Yup.SourceError

  @reserved ~w(Init Next Spec vars)
  # Bound by `EXTENDS Integers`, so action names cannot shadow them.
  @imported ~w(Nat Int)
  # Model names are interpolated verbatim into the module header, and the
  # parser accepts any capitalized word, so all-caps TLA+ keywords (TRUE,
  # IF, MODULE, ...) and the global BOOLEAN/STRING sets must be rejected
  # rather than emitted as a header SANY cannot parse.
  @tla_reserved ~w(
    ASSUME ASSUMPTION AXIOM BOOLEAN BY CASE CHOOSE CONSTANT CONSTANTS
    COROLLARY DEFINE DEFS ELSE ENABLED EXTENDS FALSE HAVE HIDE IF IN
    INSTANCE LAMBDA LEMMA LET LOCAL MODULE NEW OBVIOUS OTHER PICK PROOF
    PROPOSITION PROVED QED RECURSIVE SUFFICES TAKE THEN THEOREM TRUE
    UNCHANGED UNION USE VARIABLE VARIABLES WITNESS WITH STRING
  )
  @boolean_ops ~w(== != < <= > >= and or)
  @ordering_ops ~w(< <= > >=)
  @comparison %{"==" => "=", "!=" => "#", "<" => "<", "<=" => "=<", ">" => ">", ">=" => ">="}
  @arithmetic %{"+" => "+", "-" => "-", "*" => "*"}
  @exportable_name ~r/^[a-z_][a-zA-Z0-9_]*$/

  @unsupported %{
    AnonymousFunction => "anonymous functions",
    Call => "calls",
    Constructor => "constructor expressions",
    FieldAccess => "field access",
    ListLiteral => "list literals",
    MapLiteral => "map literals",
    Match => "match expressions",
    RecordConstruction => "record construction"
  }

  def export_file(path) do
    with {:ok, source} <- read_source(path),
         {:ok, program} <- Yup.Parser.parse(source, path: path) do
      export_program(program, path: path)
    end
  end

  # @spec TLA-6
  def export_program(%Program{} = program, opts \\ []) do
    path = Keyword.get(opts, :path, program.source_path)

    case program.models do
      [model] ->
        export_model(model, path: path)

      models ->
        {:error,
         SourceError.exception(
           path: path,
           message: "expected exactly one model to export, found #{length(models)}"
         )}
    end
  end

  # @spec TLA-1
  # @spec TLA-5
  def export_model(%Model{} = model, opts \\ []) do
    path = Keyword.get(opts, :path)
    validate_name(model, path)
    fields = validate_fields(model, path)
    actions = validate_transitions(model, path)
    validate_invariants(model, path, actions)

    {:ok, module_text(model, path, fields, actions)}
  rescue
    error in SourceError -> {:error, error}
  end

  defp read_source(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, %File.Error{action: "read", path: path, reason: reason}}
    end
  end

  # ── validation ──────────────────────────────────────────────────────

  # @spec TLA-4
  defp validate_name(%Model{name: name, loc: loc}, path) do
    if name in @tla_reserved do
      raise source_error(path, loc, "model name #{name} is a TLA+ reserved word")
    end

    :ok
  end

  # State fields export as TLA+ variables, so names must survive verbatim:
  # ? and ! are not TLA+ identifier characters and `vars` collides with the
  # generated variables tuple.
  # @spec TLA-4
  defp validate_fields(%Model{name: name, states: states, loc: loc}, path) do
    if states == [] do
      raise source_error(path, loc, "model #{name} has no state fields to export")
    end

    Enum.each(states, fn declaration ->
      field = declaration.name

      cond do
        field == "vars" ->
          raise source_error(
                  path,
                  declaration.loc,
                  "state field vars collides with the generated vars definition"
                )

        not exportable_name?(field) ->
          raise source_error(
                  path,
                  declaration.loc,
                  "state field #{field} cannot be exported to TLA+ because ? and ! are not " <>
                    "TLA+ identifier characters"
                )

        true ->
          :ok
      end
    end)

    detect_duplicate_fields(states, path)
    states
  end

  defp detect_duplicate_fields(states, path) do
    Enum.reduce(states, MapSet.new(), fn declaration, seen ->
      field = declaration.name

      if MapSet.member?(seen, field) do
        raise source_error(path, declaration.loc, "duplicate state field #{field}")
      end

      MapSet.put(seen, field)
    end)

    :ok
  end

  # Transition names are camelized into TLA+ action names and must not
  # collide with each other or with the module's generated definitions.
  defp validate_transitions(%Model{transitions: transitions}, path) do
    Enum.reduce(transitions, {[], MapSet.new()}, fn transition, {actions, used} ->
      action = checked_action_name(transition, path)

      cond do
        action in @reserved ->
          raise source_error(
                  path,
                  transition.loc,
                  "transition #{transition.name} would export as #{action}, which collides " <>
                    "with the generated #{action} definition"
                )

        action in @imported ->
          raise source_error(
                  path,
                  transition.loc,
                  "transition #{transition.name} would export as #{action}, which collides " <>
                    "with #{action} imported by EXTENDS Integers"
                )

        MapSet.member?(used, action) ->
          raise source_error(
                  path,
                  transition.loc,
                  "transition #{transition.name} would export as #{action}, which collides " <>
                    "with another generated definition"
                )

        true ->
          {[{action, transition} | actions], MapSet.put(used, action)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp checked_action_name(%Transition{name: name, loc: loc}, path) do
    cond do
      not exportable_name?(name) ->
        raise source_error(
                path,
                loc,
                "transition #{name} cannot be exported to TLA+ because ? and ! are not " <>
                  "TLA+ identifier characters"
              )

      action_name(name) == "" ->
        raise source_error(
                path,
                loc,
                "transition #{name} cannot be exported to TLA+ because it has no name parts"
              )

      true ->
        action_name(name)
    end
  end

  # Invariant labels are free-form strings, so definitions are numbered
  # (Invariant1, Invariant2, ...) in declaration order and only need to be
  # kept distinct from action names.
  defp validate_invariants(%Model{invariants: invariants}, path, actions) do
    action_names = MapSet.new(actions, fn {action, _transition} -> action end)

    Enum.each(Enum.with_index(invariants, 1), fn {declaration, index} ->
      definition = "Invariant#{index}"

      if MapSet.member?(action_names, definition) do
        raise source_error(
                path,
                declaration.loc,
                "invariant \"#{declaration.name}\" would export as #{definition}, which " <>
                  "collides with another generated definition"
              )
      end
    end)

    :ok
  end

  defp exportable_name?(name), do: Regex.match?(@exportable_name, name)

  defp action_name(name) do
    name
    |> String.split("_", trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  # ── module assembly ─────────────────────────────────────────────────

  defp module_text(%Model{} = model, path, fields, actions) do
    names = Enum.map(fields, & &1.name)

    env = %{
      path: path,
      fields: MapSet.new(names),
      names: names,
      assigned: MapSet.new(),
      mode: :invariant
    }

    [
      header(model.name),
      "\\* Generated by `yup export tla`.\nEXTENDS Integers\n\n",
      "VARIABLES #{Enum.join(names, ", ")}\n\n",
      "vars == << #{Enum.join(names, ", ")} >>\n\n",
      init(fields, env),
      Enum.map(actions, fn {action, transition} -> action_block(action, transition, env) end),
      "Next == #{next(actions)}\n\n",
      "Spec == Init /\\ [][Next]_vars\n\n",
      invariant_block(model, env),
      tlc_config(model.name, model.invariants)
    ]
    |> IO.iodata_to_binary()
  end

  defp header(name) do
    dashes = String.duplicate("-", 28)
    "#{dashes} MODULE #{name} #{dashes}\n"
  end

  defp init(fields, env) do
    env = %{env | mode: :initializer}

    conjuncts =
      for %ModelState{name: name, value: value} <- fields do
        "  /\\ #{name} = #{render(value, env)}"
      end

    "Init ==\n" <> Enum.join(conjuncts, "\n") <> "\n\n"
  end

  # @spec TLA-2
  defp action_block(action, %Transition{name: name, body: body}, base_env) do
    env = %{base_env | mode: :transition}

    {conjuncts, assigned} =
      Enum.reduce(body, {[], MapSet.new()}, fn statement, {lines, assigned} ->
        update = transition_update(statement, env)
        field = update.name

        cond do
          not MapSet.member?(env.fields, field) ->
            raise source_error(
                    env.path,
                    update.loc,
                    "assignment to undeclared state field #{field}"
                  )

          MapSet.member?(assigned, field) ->
            raise source_error(
                    env.path,
                    update.loc,
                    "state field #{field} is assigned more than once in transition #{name}"
                  )

          true ->
            value = render(update.value, %{env | assigned: assigned})
            {["  /\\ #{field}' = #{value}" | lines], MapSet.put(assigned, field)}
        end
      end)

    lines =
      case Enum.reject(env.names, &MapSet.member?(assigned, &1)) do
        [] ->
          Enum.reverse(conjuncts)

        unchanged ->
          Enum.reverse(conjuncts) ++ ["  /\\ UNCHANGED << #{Enum.join(unchanged, ", ")} >>"]
      end

    "\\* transition #{name}\n#{action} ==\n" <> Enum.join(lines, "\n") <> "\n\n"
  end

  # The parser also accepts bare `state.field` expression statements (no
  # `=`) in transition bodies, which `yup verify` evaluates and discards
  # (lib/yup/verify/explorer.ex). TLA+ next-state actions have no equivalent
  # for a statement with no effect on the primed variables, so this is a
  # real subset restriction, not an unreachable defensive clause: models
  # `yup verify` accepts with such statements are rejected here.
  defp transition_update(%StateUpdate{} = update, _env), do: update

  defp transition_update(node, env) do
    raise source_error(
            env.path,
            Map.get(node, :loc),
            "only state updates are supported in exported transition bodies"
          )
  end

  defp next([]), do: "FALSE"

  defp next(actions), do: Enum.map_join(actions, " \\/ ", &elem(&1, 0))

  defp invariant_block(%Model{invariants: invariants}, env) do
    invariants
    |> Enum.with_index(1)
    |> Enum.map(fn {%Invariant{name: name, condition: condition}, index} ->
      "\\* invariant \"#{name}\"\nInvariant#{index} == #{truthy(condition, env)}\n\n"
    end)
    |> Enum.join()
  end

  defp tlc_config(name, invariants) do
    declarations =
      Enum.map(Enum.with_index(invariants, 1), fn {_invariant, index} ->
        "\\*   INVARIANT Invariant#{index}\n"
      end)

    [
      "\\* Check with TLC: save this module as #{name}.tla with a companion\n",
      "\\* #{name}.cfg containing:\n",
      "\\*   SPECIFICATION Spec\n",
      declarations,
      "\\* Then run: java tlc2.TLC #{name}\n",
      String.duplicate("=", 77) <> "\n"
    ]
  end

  # ── expression translation ──────────────────────────────────────────

  # @spec TLA-3
  defp render(%Literal{kind: :integer, value: value}, _ctx), do: Integer.to_string(value)

  defp render(%Literal{kind: :boolean, value: value}, _ctx) do
    if value, do: "TRUE", else: "FALSE"
  end

  defp render(%Literal{kind: :atom, value: value}, _ctx) do
    inspect(Atom.to_string(value))
  end

  defp render(%Literal{kind: :string} = node, ctx),
    do: raise(unsupported(node, ctx, "string literals"))

  defp render(%Literal{kind: nil} = node, ctx), do: raise(unsupported(node, ctx, "nil literals"))

  defp render(%Identifier{name: name} = node, ctx), do: render_read(name, node, ctx)

  defp render(%StateAccess{name: name} = node, ctx), do: render_read(name, node, ctx)

  defp render(%UnaryOp{op: "not", operand: operand}, ctx) do
    "(~ " <> truthy(operand, ctx) <> ")"
  end

  defp render(%UnaryOp{} = node, ctx), do: raise(unsupported(node, ctx, "unary operators"))

  defp render(
         %TernaryOp{condition: condition, then_expr: then_expr, else_expr: else_expr},
         ctx
       ) do
    "(IF #{truthy(condition, ctx)} THEN #{render(then_expr, ctx)} ELSE #{render(else_expr, ctx)})"
  end

  defp render(%BinaryOp{} = node, ctx), do: render_binary(node, ctx)

  # @spec TLA-4
  defp render(node, ctx), do: raise(unsupported(node, ctx))

  defp render_binary(%BinaryOp{op: "/"} = node, ctx), do: render_division(node, ctx)

  defp render_binary(%BinaryOp{op: op, left: left, right: right} = node, ctx) do
    cond do
      Map.has_key?(@comparison, op) ->
        render_comparison(op, left, right, node, ctx)

      Map.has_key?(@arithmetic, op) ->
        "(#{render(left, ctx)} #{@arithmetic[op]} #{render(right, ctx)})"

      op in ["and", "or"] ->
        boolean_op = if op == "and", do: " /\\ ", else: " \\/ "
        "(" <> truthy(left, ctx) <> boolean_op <> truthy(right, ctx) <> ")"

      true ->
        raise unsupported(node, ctx, "'#{op}' operators")
    end
  end

  # YupYup `/` truncates toward zero (`Yup.Runtime.divide/2` is Elixir
  # `div/2`), but TLA+ `div` floors, so `-1 / 2` would explore `0` in
  # `yup verify` and `-1` in TLC. The floored quotient is adjusted by one
  # whenever the operands' signs differ and the division isn't exact, which
  # is exactly when flooring and truncating disagree.
  # @spec TLA-3
  defp render_division(%BinaryOp{left: left, right: right}, ctx) do
    left_text = render(left, ctx)
    right_text = render(right, ctx)
    floor = "(#{left_text} div #{right_text})"
    signs_differ = "(#{left_text} < 0) # (#{right_text} < 0)"
    inexact = "(#{left_text} % #{right_text}) # 0"

    "(IF #{signs_differ} /\\ #{inexact} THEN #{floor} + 1 ELSE #{floor})"
  end

  # TLC's ordering operators (`<`, `=<`, `>`, `>=`) require integer operands
  # on both sides, but `yup verify` orders atoms and booleans too via Elixir
  # term ordering. Operands that are statically known to be non-integer
  # (atoms, booleans, or expressions guaranteed to produce one of those)
  # would export to a module TLC aborts on, so they are rejected here;
  # `==`/`!=` have no such restriction since TLC equality works across types.
  # @spec TLA-4
  defp render_comparison(op, left, right, node, ctx) do
    if op in @ordering_ops and (non_integer_operand?(left) or non_integer_operand?(right)) do
      raise unsupported(node, ctx, "ordering comparisons over non-integer operands")
    end

    "(#{render(left, ctx)} #{@comparison[op]} #{render(right, ctx)})"
  end

  defp render_read(name, node, ctx) do
    cond do
      not MapSet.member?(ctx.fields, name) ->
        raise source_error(ctx.path, node.loc, "unknown state field #{name}")

      ctx.mode == :initializer ->
        raise source_error(
                ctx.path,
                node.loc,
                "state initializers cannot read state fields (#{name})"
              )

      ctx.mode == :transition and MapSet.member?(ctx.assigned, name) ->
        name <> "'"

      true ->
        name
    end
  end

  # `and`/`or`/`not` and ternary conditions must match YupYup truthiness
  # (only false is falsy among exportable values), so operands that are not
  # statically boolean are compared against FALSE rather than handed to TLC
  # as booleans.
  defp truthy(expression, ctx) do
    text = render(expression, ctx)

    if boolean_expr?(expression) do
      text
    else
      "(#{text} # FALSE)"
    end
  end

  defp boolean_expr?(%Literal{kind: :boolean}), do: true
  defp boolean_expr?(%UnaryOp{op: "not"}), do: true
  defp boolean_expr?(%BinaryOp{op: op}), do: op in @boolean_ops

  defp boolean_expr?(%TernaryOp{then_expr: then_expr, else_expr: else_expr}),
    do: boolean_expr?(then_expr) and boolean_expr?(else_expr)

  defp boolean_expr?(_other), do: false

  defp non_integer_operand?(%Literal{kind: :atom}), do: true

  defp non_integer_operand?(%TernaryOp{then_expr: then_expr, else_expr: else_expr}),
    do: non_integer_operand?(then_expr) and non_integer_operand?(else_expr)

  defp non_integer_operand?(other), do: boolean_expr?(other)

  defp unsupported(node, ctx, description) do
    source_error(
      ctx.path,
      Map.get(node, :loc),
      "#{description} are not supported in TLA+ export"
    )
  end

  defp unsupported(node, ctx) do
    description = Map.get(@unsupported, node.__struct__, "expressions")
    unsupported(node, ctx, description)
  end

  defp source_error(path, %{line: line, column: column}, message),
    do: SourceError.exception(path: path, line: line, column: column, message: message)

  defp source_error(path, %{line: line}, message),
    do: SourceError.exception(path: path, line: line, message: message)

  defp source_error(path, _loc, message),
    do: SourceError.exception(path: path, message: message)
end
