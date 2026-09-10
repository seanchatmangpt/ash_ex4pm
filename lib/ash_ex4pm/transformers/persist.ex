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

    activities = Transformer.get_entities(dsl_state, [:ex4pm])

    with :ok <- validate_context(activities, module, resource_dsl?),
         :ok <- validate_attribute_types(activities, module) do
      normalized =
        Enum.map(activities, fn a ->
          if resource_dsl? and is_nil(a.resource), do: %{a | resource: module}, else: a
        end)

      provenance_source =
        Transformer.get_option(dsl_state, [:ex4pm], :provenance_source, :ash_ex4pm)

      compiled = %{
        activities: normalized,
        provenance_source: provenance_source,
        context: if(resource_dsl?, do: :resource, else: :domain)
      }

      {:ok, Transformer.persist(dsl_state, :ash_ex4pm_compiled, compiled)}
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

  @allowed_attribute_types [:string, :integer, :float, :boolean, :atom, :date, :datetime]

  # Validates every declared `attributes: [name: type, ...]` entry against
  # the real allowed OCEL event-attribute type set at compile time, so a
  # typo'd or unsupported type (e.g. `attributes: [carrier: :strnig]`) fails
  # the build instead of silently reaching AshEx4pm.Notifier.build_envelope/2
  # at runtime.
  defp validate_attribute_types(activities, module) do
    Enum.reduce_while(activities, :ok, fn activity, :ok ->
      case Enum.find(activity.attributes, fn {_name, type} ->
             type not in @allowed_attribute_types
           end) do
        nil ->
          {:cont, :ok}

        {attr_name, bad_type} ->
          {:halt,
           {:error,
            Spark.Error.DslError.exception(
              module: module,
              path: [:ex4pm, activity.name, :attributes, attr_name],
              message:
                "activity #{inspect(activity.name)} declares attribute " <>
                  "#{inspect(attr_name)} with unsupported type #{inspect(bad_type)} -- " <>
                  "must be one of #{inspect(@allowed_attribute_types)}."
            )}}
      end
    end)
  end

  # ash_ai AshAi.Transformers.ResourceTools pattern (resource_tools.ex:125-127):
  # `@spark_is` is the module attribute Spark sets to Ash.Resource or Ash.Domain
  # on any module using a DSL extension declared against that behaviour.
  defp resource_dsl?(module) do
    Module.get_attribute(module, :spark_is) == Ash.Resource
  end
end
