defmodule Yup.Verify.Evaluator do
  @moduledoc """
  Evaluator for the model expression subset (issue #9, clarifying answer A1).

  Supported: literals, current-state reads through bare field names or
  `state.field`, unary and binary operators, and ternaries. Calls to top-level
  `def` functions and every other expression shape are rejected with a
  source-located diagnostic.

  This evaluator is deliberately separate from BEAM compilation: models are
  non-executable descriptions consumed by the verifier, not lowered code.
  """

  alias Yup.AST.{
    AnonymousFunction,
    BinaryOp,
    Call,
    Constructor,
    FieldAccess,
    Identifier,
    ListLiteral,
    Literal,
    MapLiteral,
    Match,
    RecordConstruction,
    StateAccess,
    TernaryOp,
    UnaryOp
  }

  alias Yup.SourceError

  defstruct [:path, :state, :mode, fields: MapSet.new()]

  # @spec VERIFY-2
  def env(path, fields, state, mode) do
    %__MODULE__{
      path: path,
      fields: MapSet.new(fields, &field_name/1),
      state: Map.new(state, fn {key, value} -> {field_name(key), value} end),
      mode: mode
    }
  end

  # State field names cross the parser boundary as strings but the verify
  # domain keys states by atom, so canonicalize once at each entry point.
  def field_name(name) when is_binary(name), do: String.to_atom(name)
  def field_name(name) when is_atom(name), do: name

  # @spec VERIFY-2
  def eval(%Literal{value: value}, _env), do: value

  def eval(%Identifier{name: name} = node, env), do: read_field(name, node, env)

  def eval(%StateAccess{name: name} = node, env), do: read_field(name, node, env)

  def eval(%UnaryOp{op: "not"} = node, env), do: Yup.Runtime.not_op(eval(node.operand, env))

  def eval(%TernaryOp{} = node, env) do
    if Yup.Runtime.truthy?(eval(node.condition, env)) do
      eval(node.then_expr, env)
    else
      eval(node.else_expr, env)
    end
  end

  def eval(%BinaryOp{} = node, env), do: eval_binary(node, env)

  def eval(node, env), do: raise(unsupported(node, env))

  defp eval_binary(%BinaryOp{left: left, right: right} = node, env) do
    left_value = eval(left, env)
    right_value = eval(right, env)
    apply_binary(node, env, {left_value, right_value})
  end

  # Exception handlers cannot access bindings created in their protected
  # expression. Keep the operands in a function argument so diagnostics can
  # distinguish division by zero from other arithmetic errors.
  defp apply_binary(%BinaryOp{op: op} = node, env, {left_value, right_value}) do
    apply_op(op, left_value, right_value)
  rescue
    ArithmeticError -> raise source_error(env.path, node.loc, arithmetic_message(op, right_value))
  end

  defp apply_op("+", left, right), do: Yup.Runtime.add(left, right)
  defp apply_op("-", left, right), do: Yup.Runtime.subtract(left, right)
  defp apply_op("*", left, right), do: Yup.Runtime.multiply(left, right)
  defp apply_op("/", left, right), do: Yup.Runtime.divide(left, right)
  defp apply_op("==", left, right), do: Yup.Runtime.equal?(left, right)
  defp apply_op("!=", left, right), do: Yup.Runtime.not_equal?(left, right)
  defp apply_op("<", left, right), do: Yup.Runtime.less?(left, right)
  defp apply_op("<=", left, right), do: Yup.Runtime.less_or_equal?(left, right)
  defp apply_op(">", left, right), do: Yup.Runtime.greater?(left, right)
  defp apply_op(">=", left, right), do: Yup.Runtime.greater_or_equal?(left, right)
  defp apply_op("and", left, right), do: Yup.Runtime.and_op(left, right)
  defp apply_op("or", left, right), do: Yup.Runtime.or_op(left, right)

  defp read_field(name, node, env) do
    field = field_name(name)

    cond do
      not MapSet.member?(env.fields, field) ->
        raise source_error(env.path, node.loc, "unknown state field #{name}")

      env.mode == :initializer ->
        raise source_error(
                env.path,
                node.loc,
                "state initializers cannot read state fields (#{name})"
              )

      true ->
        Map.fetch!(env.state, field)
    end
  end

  @unsupported %{
    AnonymousFunction => "anonymous functions",
    Call => "function calls",
    Constructor => "constructor expressions",
    FieldAccess => "field access",
    ListLiteral => "list literals",
    MapLiteral => "map literals",
    Match => "match expressions",
    RecordConstruction => "record construction"
  }

  defp unsupported(node, env) do
    description = Map.get(@unsupported, node.__struct__, "expressions")

    source_error(
      env.path,
      Map.get(node, :loc),
      "#{description} are not supported in model expressions"
    )
  end

  defp arithmetic_message("/", 0), do: "division by zero in model expression"
  defp arithmetic_message(op, _), do: "arithmetic error evaluating '#{op}' in model expression"

  defp source_error(path, %{line: line, column: column}, message),
    do: SourceError.exception(path: path, line: line, column: column, message: message)

  defp source_error(path, _loc, message),
    do: SourceError.exception(path: path, message: message)
end
