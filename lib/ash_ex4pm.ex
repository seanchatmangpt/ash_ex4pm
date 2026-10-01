defmodule AshEx4pm do
  @moduledoc """
  Ash projection for ex4pm process evidence, admitted runtime capabilities,
  wasm4pm analysis, ferroplan planning, and receipted Ash actions.

  Semantic ownership stays upstream: wasm4pm and ferroplan own algorithms,
  ex4pm owns admitted runtime/evidence integration, and AshEx4pm projects those
  capabilities into Ash. Capability existence never implies runtime standing,
  authority, or DO.

  See docs/INDEX.md for the federated Diátaxis navigation.
  """

  use Spark.Dsl.Extension,
    sections: [AshEx4pm.Dsl.section()],
    transformers: [AshEx4pm.Transformers.Persist],
    verifiers: [AshEx4pm.Verifiers.Verify]

  @doc "Returns the machine-readable AshEx4pm capability projection registry."
  def capabilities(filters \\ []), do: AshEx4pm.Capabilities.all(filters)

  @doc "Returns one capability descriptor by id."
  def capability(id), do: AshEx4pm.Capabilities.get(id)

  @doc "Returns evidence-bounded standing for one projected capability."
  def capability_standing(id), do: AshEx4pm.Capabilities.standing(id)
end
