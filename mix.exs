defmodule AshEx4pm.MixProject do
  use Mix.Project

  @version "26.9.10"
  @source_url "https://github.com/seanchatmangpt/ash_ex4pm"

  def project do
    [
      app: :ash_ex4pm,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      description: description(),
      docs: docs(),
      source_url: @source_url,
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [verify: :test]]
  end

  defp aliases do
    [
      verify: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test"
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.2"},
      # Path dependency on the canonical ~/ex4pm checkout (v26.9.30, 345
      # commits past the only published release, Hex 26.9.9). Hex has no
      # newer release and the HEAD SHA is not on the remote, so a Hex or
      # git pin is unavailable (checked hex.pm/api/packages/ex4pm). Switch
      # back to `{:ex4pm, "== 26.9.30"}` once ex4pm publishes it.
      {:ex4pm, path: "../ex4pm"},
      {:igniter, "~> 0.5", optional: true},
      # ggen_igniter drives this repo's own admitted-ferroplan-capability
      # generation unit (mix ash_ex4pm.ggen.sync) -- see
      # priv/ggen/manifest.json. Not runtime: this repo ships no ontology
      # of its own; it re-queries the ex4pm dependency's packaged
      # priv/ontology/ex4pm.ttl (ex4pm's mix.exs declares `files: ["lib",
      # "priv", "mix.exs"]`, so priv/ ships with the Hex package) rather
      # than forking a second copy, avoiding the two-repo-drift problem
      # ex4pm's own ex4pmb: prefix comment already flags for beam4pm/ex4pm.
      {:ggen_igniter, "~> 26.9", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Ash extension for automatic OCEL 2.0 event emission and an optional BRCE " <>
      "admission gate, built on ex4pm's real Ex4pm.Stream.Ingest.ingest_envelope/1 " <>
      "and Ex4pm.Evidence.BRCE.execute/4."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Sean Chatman"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
