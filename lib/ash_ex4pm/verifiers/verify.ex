defmodule AshEx4pm.Verifiers.Verify do
  @moduledoc """
  Fails closed (`Spark.Error.DslError`) rather than allowing a silently
  broken configuration to compile -- mirrors `AshR2RML.Resource.Verify`
  (`~/ash_r2rml/lib/ash_r2rml/resource.ex:486-512`).

  Checks, both real:
  1. Every `activity`'s `on:` action must actually exist on the target
     resource (resource-level: the declaring module itself;
     domain-level: the explicit `resource:`). Catches the exact class of
     bug this extension exists to prevent: a typo'd action name silently
     never firing, the way `Ex4pmDomain.Notifier.OcelNotifier`'s own
     `ingest_batch/1` call silently never fires today.
  2. No two activities declare the same `name` for the same resource
     (the `identifier: :name` Spark option already enforces this at
     parse time for a single section, but this re-checks explicitly in
     case entities were merged from multiple `ex4pm do ... end` blocks
     across a resource and its domain).
  3. Every `object_relationship`'s `relationship:` must actually exist on
     the target resource -- the same fail-closed discipline as (1),
     applied to O2O declarations so a typo'd relationship name is a
     compile error, never a silent no-op at emit time.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    case Verifier.get_persisted(dsl_state, :ash_ex4pm_compiled) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           module: module,
           path: [:ex4pm],
           message: "AshEx4pm.Transformers.Persist did not run -- no compiled state found."
         )}

      %{activities: activities} ->
        with :ok <- check_actions_exist(activities, module, dsl_state),
             :ok <- check_relationships_exist(activities, module, dsl_state) do
          check_no_duplicate_names(activities, module)
        end
    end
  end

  defp check_actions_exist(activities, module, dsl_state) do
    Enum.find_value(activities, :ok, fn a ->
      resource = a.resource || module

      cond do
        resource == module ->
          # Self-reference (the common, resource-level case): the module is
          # still mid-compile, so Ash.Resource.Info can't be called on it as
          # a loaded module -- read its own actions section directly out of
          # the dsl_state we already have, the real Spark-verifier-safe way.
          action_names =
            dsl_state
            |> Verifier.get_entities([:actions])
            |> Enum.map(& &1.name)

          validate_on(a, resource, action_names, module)

        Code.ensure_loaded?(resource) and function_exported?(resource, :spark_dsl_config, 0) ->
          # A domain-level activity explicitly names a DIFFERENT, already
          # separately-compiled resource -- safe to call the real
          # Ash.Resource.Info API on it directly.
          action_names = resource |> Ash.Resource.Info.actions() |> Enum.map(& &1.name)
          validate_on(a, resource, action_names, module)

        true ->
          # `resource:` names an unloaded module, a genuine typo, or a
          # loaded module that isn't an Ash resource at all -- fail closed
          # instead of silently skipping validation for this activity.
          {:error,
           Spark.Error.DslError.exception(
             module: module,
             path: [:ex4pm, a.name, :resource],
             message: "`resource: #{inspect(resource)}` is not a compiled Ash resource."
           )}
      end
    end)
  end

  defp validate_on(a, resource, action_names, module) do
    if a.on && a.on not in action_names do
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:ex4pm, a.name, :on],
         message:
           "`activity #{inspect(a.name)}, on: #{inspect(a.on)}` references an action that " <>
             "does not exist on #{inspect(resource)}. Real action names: #{inspect(action_names)}."
       )}
    end
  end

  defp check_relationships_exist(activities, module, dsl_state) do
    Enum.find_value(activities, :ok, fn a ->
      resource = a.resource || module

      relationship_names =
        cond do
          resource == module ->
            # Self-reference: the module is still mid-compile, so read the
            # `relationships` section directly out of `dsl_state`, the same
            # verifier-safe pattern `check_actions_exist/3` uses for `:actions`.
            dsl_state
            |> Verifier.get_entities([:relationships])
            |> Enum.map(& &1.name)

          Code.ensure_loaded?(resource) and function_exported?(resource, :spark_dsl_config, 0) ->
            resource |> Ash.Resource.Info.relationships() |> Enum.map(& &1.name)

          true ->
            nil
        end

      cond do
        relationship_names == nil ->
          # An unloaded/non-resource `resource:` is already reported by
          # check_actions_exist/3 above (verify/1 runs it first); avoid a
          # second, redundant error for the same root cause here.
          :ok

        true ->
          Enum.find_value(a.object_relationships, :ok, fn rel ->
            if rel.relationship not in relationship_names do
              {:error,
               Spark.Error.DslError.exception(
                 module: module,
                 path: [:ex4pm, a.name, :object_relationship, rel.relationship],
                 message:
                   "`object_relationship relationship: #{inspect(rel.relationship)}` references " <>
                     "a relationship that does not exist on #{inspect(resource)}. Real " <>
                     "relationship names: #{inspect(relationship_names)}."
               )}
            end
          end)
      end
    end)
  end

  defp check_no_duplicate_names(activities, module) do
    dupes =
      activities
      |> Enum.frequencies_by(& &1.name)
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    if dupes == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         module: module,
         path: [:ex4pm],
         message: "Duplicate activity name(s): #{inspect(dupes)}."
       )}
    end
  end
end
