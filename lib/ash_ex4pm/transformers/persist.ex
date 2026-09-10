defmodule AshEx4pm.Transformers.Persist do
  @moduledoc """
  Normalizes the raw `ex4pm do ... end` DSL entities into a compiled,
  persisted state -- mirrors `AshR2RML.Resource.Persist`
  (`~/ash_r2rml/lib/ash_r2rml/resource.ex:169-249`).

  Two real capabilities, per `ash-extension-core-pack` v26.9.10's
  ontology (`aex:contextNormalize`, `aex:afterTransformer`):

  1. **Context normalization** (the real `AshAi.Transformers.ResourceTools`
     pattern, `~/xaas/deps/ash_ai/lib/ash_ai/transformers/resource_tools.ex:13-55,125-127`):
     a resource-level `activity` entity has its `resource` field filled in
     automatically; a domain-level `activity` entity must set `resource`
     explicitly (no implicit resource to infer it from) or compilation
     fails.
  2. **Transformer ordering**: `transform/1` below only reads/writes the
     `:ex4pm` entities and the `:provenance_source` option -- it never reads
     attributes, relationships, or primary-key info from `dsl_state`, so it
     has no real data dependency on any specific core transformer. Rather
     than enumerate a hand-picked list of transformers that happen not to
     matter (which gives false confidence that dependencies are covered,
     and misses any other core transformer not in the list), this follows
     the real `AshAi.Transformers.ResourceTools` precedent
     (`~/xaas/deps/ash_ai/lib/ash_ai/transformers/resource_tools.ex:11`),
     whose `transform/1` has the same shape (only sets a field to the
     module): `after?/1` returns `true` unconditionally, so this
     transformer simply runs after everything else regardless of what
     future `transform/1` changes come to need.
  """
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)
    resource_dsl? = resource_dsl?(module)

    entities = Transformer.get_entities(dsl_state, [:ex4pm])
    {activities, object_types} = Enum.split_with(entities, &match?(%AshEx4pm.Activity{}, &1))

    object_types_by_name = Map.new(object_types, &{&1.name, &1})

    with :ok <- validate_context(activities, module, resource_dsl?),
         :ok <- validate_object_types(activities, object_types_by_name, module) do
      normalized =
        Enum.map(activities, fn a ->
          if resource_dsl? and is_nil(a.resource), do: %{a | resource: module}, else: a
        end)

      provenance_source =
        Transformer.get_option(dsl_state, [:ex4pm], :provenance_source, :ash_ex4pm)

      compiled = %{
        activities: normalized,
        object_types: object_types_by_name,
        provenance_source: provenance_source,
        context: if(resource_dsl?, do: :resource, else: :domain)
      }

      {:ok, Transformer.persist(dsl_state, :ash_ex4pm_compiled, compiled)}
    end
  end

  # Every `activity` that explicitly declares `object_type:` must name a
  # real, declared `object_type` entity in the same section -- this is the
  # real OCEL 2.0 object-type-schema check the extension previously had no
  # concept of at all (object types were purely emergent from
  # `AshEx4pm.Notifier.resource_type_name/1`'s module-name derivation).
  # Activities with no `object_type:` set are left alone -- that stays a
  # real, disclosed back-compat fallback (see AshEx4pm.Activity's
  # moduledoc), not silently promoted into a required declaration, so
  # existing resources that never declared object types keep compiling.
  defp validate_object_types(activities, object_types_by_name, module) do
    activities
    |> Enum.find(
      &(not is_nil(&1.object_type) and not Map.has_key?(object_types_by_name, &1.object_type))
    )
    |> case do
      nil ->
        :ok

      bad ->
        {:error,
         Spark.Error.DslError.exception(
           module: module,
           path: [:ex4pm, bad.name, :object_type],
           message:
             "`activity #{inspect(bad.name)}` declares `object_type: #{inspect(bad.object_type)}`, " <>
               "which does not resolve to any declared `object_type #{inspect(bad.object_type)}, " <>
               "attributes: [...]` entity in this section. Declared object types: " <>
               "#{inspect(Map.keys(object_types_by_name))}."
         )}
    end
  end

  defp validate_context(activities, module, true = _resource_dsl?) do
    explicit = Enum.find(activities, &(not is_nil(&1.resource)))

    if explicit do
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:ex4pm, explicit.name, :resource],
         message:
           "Resource-level `activity #{inspect(explicit.name)}` cannot set `resource:` explicitly -- " <>
             "it is filled in automatically as #{inspect(module)}."
       )}
    else
      :ok
    end
  end

  defp validate_context(activities, module, false = _resource_dsl?) do
    missing = Enum.find(activities, &is_nil(&1.resource))

    if missing do
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:ex4pm, missing.name, :resource],
         message:
           "Domain-level `activity #{inspect(missing.name)}` requires an explicit `resource:` -- " <>
             "there is no resource to infer it from at the domain level."
       )}
    else
      :ok
    end
  end

  # ash_ai AshAi.Transformers.ResourceTools pattern (resource_tools.ex:125-127):
  # `@spark_is` is the module attribute Spark sets to Ash.Resource or Ash.Domain
  # on any module using a DSL extension declared against that behaviour.
  defp resource_dsl?(module) do
    Module.get_attribute(module, :spark_is) == Ash.Resource
  end
end
