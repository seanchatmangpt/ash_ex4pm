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
        with :ok <- check_actions_exist(activities, module, dsl_state) do
          check_no_duplicate_names(activities, module)
        end
    end
  end

  defp check_actions_exist(activities, module, dsl_state) do
    Enum.find_value(activities, :ok, fn a ->
      resource = a.resource || module

      action_names =
        if resource == module do
          # Self-reference (the common, resource-level case): the module is
          # still mid-compile, so Ash.Resource.Info can't be called on it as
          # a loaded module -- read its own actions section directly out of
          # the dsl_state we already have, the real Spark-verifier-safe way.
          dsl_state
          |> Verifier.get_entities([:actions])
          |> Enum.map(& &1.name)
        else
          # A domain-level activity explicitly names a DIFFERENT, already
          # separately-compiled resource -- safe to call the real
          # Ash.Resource.Info API on it directly.
          if Code.ensure_loaded?(resource) and function_exported?(resource, :spark_dsl_config, 0) do
            resource |> Ash.Resource.Info.actions() |> Enum.map(& &1.name)
          end
        end

      if action_names && a.on && a.on not in action_names do
        {:error,
         Spark.Error.DslError.exception(
           module: module,
           path: [:ex4pm, a.name, :on],
           message:
             "`activity #{inspect(a.name)}, on: #{inspect(a.on)}` references an action that " <>
               "does not exist on #{inspect(resource)}. Real action names: #{inspect(action_names)}."
         )}
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
