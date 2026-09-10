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

      case resolve_entity_names(
             resource,
             module,
             dsl_state,
             :actions,
             &Ash.Resource.Info.actions/1
           ) do
        {:ok, action_names} ->
          validate_on(a, resource, action_names, module)

        :unresolved ->
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

      case resolve_entity_names(
             resource,
             module,
             dsl_state,
             :relationships,
             &Ash.Resource.Info.relationships/1
           ) do
        :unresolved ->
          # An unloaded/non-resource `resource:` is already reported by
          # check_actions_exist/3 above (verify/1 runs it first); avoid a
          # second, redundant error for the same root cause here.
          :ok

        {:ok, relationship_names} ->
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

  # Shared self-reference-vs-external-resource resolution: `check_actions_exist/3`
  # and `check_relationships_exist/3` both need this same real, three-way
  # branch to read an entity list (`:actions`/`:relationships`) for a
  # resource that might be (a) the module currently mid-compile (must read
  # the section straight out of `dsl_state` -- `Ash.Resource.Info` cannot
  # call into a module that hasn't finished compiling), (b) a different,
  # already-loaded-and-compiled Ash resource (safe to call the real
  # `Ash.Resource.Info` API on directly), or (c) an unloaded module, a
  # typo, or a loaded module that isn't an Ash resource at all
  # (`:unresolved` -- each caller decides how to report/skip that case).
  defp resolve_entity_names(resource, module, dsl_state, section, info_fun) do
    cond do
      resource == module ->
        {:ok, dsl_state |> Verifier.get_entities([section]) |> Enum.map(& &1.name)}

      Code.ensure_loaded?(resource) and function_exported?(resource, :spark_dsl_config, 0) ->
        {:ok, resource |> info_fun.() |> Enum.map(& &1.name)}

      true ->
        :unresolved
    end
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
