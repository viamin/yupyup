defmodule Yup.AST.Call do
  @moduledoc """
  An ordinary YupYup call: a known top-level `def` or a bound function value.

  `receiver` is `nil` for a plain call like `double(4)`. A dot call like
  `4.double()` sets `receiver` to the parsed receiver expression; the
  receiver is passed as the first argument when the call is lowered.

  `block` is `nil` unless the call carries a trailing brace block, e.g.
  `values.map { |value| value * 2 }`. A block is an ordinary
  `Yup.AST.AnonymousFunction` value appended as the last argument when the
  call is lowered.
  """

  defstruct [:name, args: [], receiver: nil, block: nil, loc: nil]
end
