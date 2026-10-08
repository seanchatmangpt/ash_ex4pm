defmodule AshEx4pm.MixProject do
  use Mix.Project

  @version "26.10.8"
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
      # Hex release ex4pm 26.10.1 (hex.pm/packages/ex4pm/26.10.1, checksum
      # b42dd8d63b11fea76b10bb8f84503635f8ee0e6e6851cd7a8102759650c93be6).
      # Exact-pinned: ex4pm's third CalVer component carries contract
      # changes (each release's CHANGELOG declares its public contract).
      {:ex4pm, "== 26.10.1"},
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
      maintainers: ["Sean Chatman"],
      files: ~w(lib priv mix.exs README.md CHANGELOG.md docs docs/**/*)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/INDEX.md",
        "docs/diataxis/index.md",
        "docs/diataxis/reference/api.md",
        "docs/diataxis/explanation/architecture.md",
        "docs/PRD-ARD-v26.10.2.md"
      ]
    ]
  end
end
