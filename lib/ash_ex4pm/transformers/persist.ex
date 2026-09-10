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
         :ok <- validate_object_types(activities, object_types_by_name, module),
         :ok <- validate_attribute_types(activities, module),
         :ok <- validate_object_type_attribute_types(object_types, module) do
      normalized =
        Enum.map(activities, fn a ->
          if resource_dsl? and is_nil(a.resource), do: %{a | resource: module}, else: a
        end)

      provenance_source =
        Transformer.get_option(dsl_state, [:ex4pm], :provenance_source, :ash_ex4pm)

      compiled = %{
        activities: normalized,
        object_types: object_types_by_name,
        provenance_source: provenance_source
      }

      dsl_state
      |> Transformer.persist(:ash_ex4pm_compiled, compiled)
      |> register_notifier(resource_dsl?)
      |> then(&{:ok, &1})
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

  # `object_type ..., attributes: [...]` entries declare OCEL 2.0 *object*
  # attribute types, a distinct, wider set than @allowed_attribute_types
  # (event-attribute types): object attributes additionally allow
  # `:decimal` (see AshEx4pm.ObjectType's moduledoc, and
  # AshEx4pm.Test.Invoice's `total_amount: :decimal` fixture), which
  # `@allowed_attribute_types` deliberately excludes for event attributes.
  # Previously nothing validated this list at all -- a typo'd or
  # unsupported object-type attribute type compiled silently and was only
  # ever caught (or not) by `AshEx4pm.Notifier.declared_attributes/2`'s
  # raw, uncoerced Map.fetch pass-through at emit time, contrary to
  # AshEx4pm.ObjectType's moduledoc claim that this transformer checks it
  # at compile time.
  @allowed_object_type_attribute_types [
    :string,
    :integer,
    :float,
    :decimal,
    :boolean,
    :atom,
    :date,
    :datetime
  ]

  defp validate_object_type_attribute_types(object_types, module) do
    Enum.reduce_while(object_types, :ok, fn object_type, :ok ->
      case Enum.find(object_type.attributes, fn {_name, type} ->
             type not in @allowed_object_type_attribute_types
           end) do
        nil ->
          {:cont, :ok}

        {attr_name, bad_type} ->
          {:halt,
           {:error,
            Spark.Error.DslError.exception(
              module: module,
              path: [:ex4pm, object_type.name, :attributes, attr_name],
              message:
                "object_type #{inspect(object_type.name)} declares attribute " <>
                  "#{inspect(attr_name)} with unsupported type #{inspect(bad_type)} -- " <>
                  "must be one of #{inspect(@allowed_object_type_attribute_types)}."
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
