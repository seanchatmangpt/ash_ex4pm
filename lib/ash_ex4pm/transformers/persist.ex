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

    with :ok <- validate_context(activities, module, resource_dsl?) do
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

      dsl_state
      |> Transformer.persist(:ash_ex4pm_compiled, compiled)
      |> register_notifier(resource_dsl?)
      |> then(&{:ok, &1})
    end
  end

  # Registers `AshEx4pm.Notifier` into the same `:simple_notifiers` persisted
  # key that `use Ash.Resource, simple_notifiers: [...]` seeds
  # (deps/ash/lib/ash/resource.ex:34,132) and that
  # `Ash.Resource.Info.notifiers/1` reads alongside the explicit
  # `notifiers:` list (deps/ash/lib/ash/resource/info.ex:278-281). This
  # makes `notifiers: [AshEx4pm.Notifier]` unnecessary: opting into the
  # extension via `extensions: [AshEx4pm]` on a resource is itself the
  # explicit opt-in, so requiring a second, easy-to-forget manual step to
  # activate emission is a real ergonomic/correctness gap, not a load-bearing
  # evidence-forcing admission. Domain-level DSL usage has no notifier
  # concept, so this only applies when `resource_dsl?` is true.
  defp register_notifier(dsl_state, true = _resource_dsl?) do
    # `Ash.Resource.Info.notifiers/1` concatenates the explicit `notifiers:`
    # option's persisted list with `:simple_notifiers` without
    # deduplicating (deps/ash/lib/ash/resource/info.ex:278-281), so a
    # resource that still explicitly lists `notifiers: [AshEx4pm.Notifier]`
    # (harmless but now redundant, per notifier.ex's moduledoc) must be
    # checked here too, or `notify/1` fires twice per real notification.
    already_explicit? = AshEx4pm.Notifier in Transformer.get_persisted(dsl_state, :notifiers, [])
    simple = Transformer.get_persisted(dsl_state, :simple_notifiers, [])

    if already_explicit? or AshEx4pm.Notifier in simple do
      dsl_state
    else
      Transformer.persist(dsl_state, :simple_notifiers, [AshEx4pm.Notifier | simple])
    end
  end

  defp register_notifier(dsl_state, false = _resource_dsl?), do: dsl_state

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
