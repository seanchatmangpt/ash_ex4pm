defmodule AshEx4pm.Capability do
  @moduledoc """
  Machine-readable description of one AshEx4pm capability projection.

  A capability record describes ownership, the Ash-facing projection, the
  OBSERVE/ANALYZE/CONSTRUCT/ADMIT/DO boundary, documentation, and an optional
  inspection-only standing callback. Registration never grants authority and
  never means the upstream capability is ALIVE.
  """

  @enforce_keys [
    :id,
    :category,
    :owner,
    :projection,
    :operation,
    :arity,
    :boundary,
    :authority,
    :do_authority?,
    :docs
  ]

  defstruct [
    :id,
    :category,
    :owner,
    :projection,
    :operation,
    :arity,
    :boundary,
    :authority,
    :do_authority?,
    :standing,
    :docs
  ]

  @type boundary :: :observe | :inspect | :analyze | :construct | :admit | :do
  @type authority :: :none | :required | :operation_dependent
  @type standing_probe :: {module(), atom(), [term()]} | nil

  @type t :: %__MODULE__{
          id: atom(),
          category: atom(),
          owner: atom(),
          projection: module(),
          operation: atom(),
          arity: non_neg_integer(),
          boundary: boundary(),
          authority: authority(),
          do_authority?: boolean(),
          standing: standing_probe(),
          docs: map()
        }
end
