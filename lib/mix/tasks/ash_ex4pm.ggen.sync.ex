defmodule Mix.Tasks.AshEx4pm.Ggen.Sync do
  @moduledoc """
  Runs every ggen_igniter generation unit declared in
  `priv/ggen/manifest.json`, then verifies the result -- structurally
  identical to ex4pm's own `mix ex4pm.ggen.sync`
  (`~/ex4pm/lib/mix/tasks/ex4pm.ggen.sync.ex`), not the legacy
  bash-script convention.

  ## The one real difference from ex4pm's task

  This repo ships no ontology of its own. Every manifest unit's
  `"ontology"` field is the literal placeholder `"{{ex4pm_ontology}}"`,
  resolved here (not by ggen_igniter, which has no such templating) to
  the REAL on-disk path of ex4pm's own packaged
  `priv/ontology/ex4pm.ttl` via `Application.app_dir(:ex4pm, ...)`. This
  is a real, resolvable path once `mix deps.get && mix compile` has run,
  because ex4pm's own `mix.exs` declares `files: ["lib", "priv",
  "mix.exs"]` -- `priv/` ships with the Hex package. No second ontology
  copy is forked; if ex4pm hasn't yet released the ferroplan-capability
  individuals this repo wants to generate from, bump the `{:ex4pm, ...}`
  pin in `mix.exs` first.

  ## Usage

      mix ash_ex4pm.ggen.sync
      mix ash_ex4pm.ggen.sync --manifest priv/ggen/manifest.json
      mix ash_ex4pm.ggen.sync --unit ferroplan
  """
  use Mix.Task

  @shortdoc "Syncs every ggen_igniter generation unit in this repo's manifest, then verifies"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [manifest: :string, unit: :string],
        aliases: [m: :manifest, u: :unit]
      )

    manifest_path = Keyword.get(opts, :manifest, "priv/ggen/manifest.json")
    only_unit = Keyword.get(opts, :unit)

    units =
      manifest_path
      |> load_manifest!()
      |> filter_units(only_unit)
      |> Enum.map(&resolve_ontology!/1)

    if units == [] do
      Mix.shell().info(
        "mix ash_ex4pm.ggen.sync: no generation units to run (manifest empty or --unit matched nothing)."
      )
    else
      Enum.each(units, &sync_unit!/1)

      Mix.shell().info("mix ash_ex4pm.ggen.sync: #{length(units)} unit(s) synced.")

      run_shell_step!("compile", ["compile", "--warnings-as-errors"])

      test_paths = units |> Enum.map(& &1["test_path"]) |> Enum.filter(& &1)

      if test_paths == [] do
        Mix.shell().info(
          "mix ash_ex4pm.ggen.sync: no unit declares a test_path; skipping mix test."
        )
      else
        run_shell_step!("test", ["test" | test_paths])
      end
    end
  end

  defp load_manifest!(path) do
    unless File.exists?(path) do
      Mix.raise("mix ash_ex4pm.ggen.sync: manifest not found at #{path}")
    end

    case Jason.decode(File.read!(path)) do
      {:ok, units} when is_list(units) ->
        units

      {:ok, _other} ->
        Mix.raise("mix ash_ex4pm.ggen.sync: manifest at #{path} must be a JSON array")

      {:error, reason} ->
        Mix.raise(
          "mix ash_ex4pm.ggen.sync: manifest at #{path} is not valid JSON: #{inspect(reason)}"
        )
    end
  end

  defp filter_units(units, nil), do: units

  defp filter_units(units, unit_name) do
    case Enum.filter(units, &(&1["name"] == unit_name)) do
      [] ->
        Mix.raise("mix ash_ex4pm.ggen.sync: no unit named #{inspect(unit_name)} in the manifest")

      matched ->
        matched
    end
  end

  defp resolve_ontology!(%{"ontology" => "{{ex4pm_ontology}}"} = unit) do
    path = Application.app_dir(:ex4pm, "priv/ontology/ex4pm.ttl")

    unless File.exists?(path) do
      Mix.raise(
        "mix ash_ex4pm.ggen.sync: ex4pm's packaged ontology was not found at #{path}. " <>
          "Run `mix deps.get && mix compile` first (ex4pm ships priv/ with its Hex package)."
      )
    end

    Map.put(unit, "ontology", path)
  end

  defp resolve_ontology!(unit), do: unit

  defp run_shell_step!(label, mix_args) do
    env = if label == "test", do: [{"MIX_ENV", "test"}], else: []

    case System.cmd("mix", mix_args, stderr_to_stdout: true, env: env) do
      {output, 0} ->
        Mix.shell().info(output)

      {output, code} ->
        Mix.raise("mix ash_ex4pm.ggen.sync: #{label} step failed (exit #{code}).\n\n#{output}")
    end
  end

  defp sync_unit!(
         %{"name" => name, "ontology" => ontology, "template" => template, "out" => out} = unit
       ) do
    query_args =
      unit
      |> Map.get("query_bindings", %{})
      |> Enum.flat_map(fn {k, v} -> ["--query", "#{k}=#{v}"] end)

    cmd_args =
      ["ggen_igniter.sync", "--ontology", ontology] ++
        query_args ++ ["--template", template, "--out", out]

    Mix.shell().info("mix ash_ex4pm.ggen.sync: unit #{name} -> mix #{Enum.join(cmd_args, " ")}")

    case System.cmd("mix", cmd_args, stderr_to_stdout: true) do
      {output, 0} ->
        Mix.shell().info(output)

      {output, code} ->
        Mix.raise(
          "mix ash_ex4pm.ggen.sync: FAILED at unit #{name} (exit #{code}). Aborting -- no further units were synced.\n\n#{output}"
        )
    end
  end
end
