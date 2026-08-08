defmodule Yup.AST.RecordField do
  @moduledoc """
  A record field declaration with an optional type annotation.

  Unannotated fields carry `type: nil`. The field name stays available for the
  lowering pass even when the annotation is present.
  """

  defstruct [:name, type: nil, loc: nil]
end
