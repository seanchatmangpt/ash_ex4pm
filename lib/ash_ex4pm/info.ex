defmodule AshEx4pm.Info do
  @moduledoc """
  Introspection for `AshEx4pm`-extended resources/domains -- mirrors
  `AshR2RML.Resource.Info`'s real 4-form surface
  (`~/ash_r2rml/lib/ash_r2rml/resource.ex:514-553`): a nil-returning
  wrapper, a tagged-tuple form, a bang form, and a predicate.
  """

  @doc "Returns the compiled `ex4pm` state for `resource_or_domain`, or `nil` if absent."
  def compiled(resource_or_domain) do
    case compiled_result(resource_or_domain) do
      {:ok, compiled} -> compiled
      {:error, _} -> nil
    end
  end

  @doc "Returns `{:ok, compiled}` or `{:error, :not_compiled}`."
  def compiled_result(resource_or_domain) do
    case Spark.Dsl.Extension.get_persisted(resource_or_domain, :ash_ex4pm_compiled, nil) do
      nil -> {:error, :not_compiled}
      compiled -> {:ok, compiled}
    end
  end

  @doc "Bang variant of `compiled_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def compiled!(resource_or_domain) do
    case compiled_result(resource_or_domain) do
      {:ok, compiled} -> compiled
      {:error, reason} -> raise ArgumentError, "AshEx4pm.Info.compiled!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource_or_domain` carry compiled `ex4pm` state?"
  def compiled?(resource_or_domain), do: match?({:ok, _}, compiled_result(resource_or_domain))

  @doc "The real, compiled `AshEx4pm.Activity` list for `resource_or_domain`, or `[]` if absent."
  def activities(resource_or_domain) do
    case compiled(resource_or_domain) do
      nil -> []
      %{activities: activities} -> activities
    end
  end
end
