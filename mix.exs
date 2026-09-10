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
      source_url: @source_url
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
      # Real hex dependency, 2026-09-10 -- ex4pm v26.9.9 is published on
      # Hex (hex.pm/packages/ex4pm/26.9.9, checksum
      # 721d62414e9ac870c897af7c78a755c360b3315e3d8f5b0b32a75c8bd72a0b00,
      # tagged v26.9.9 in ~/ex4pm). Was a path dependency during initial
      # co-development (see git history) -- switched now that a real,
      # tagged, checksum-verifiable release exists, per this repo's own
      # PRD (~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md) and the goal
      # of being a real, independently hex-publishable package.
      #
      # Exact-pinned (== 26.9.9), not "~> 26.9", as of 2026-09-09: ex4pm
      # has no CHANGELOG.md or stated versioning policy for its third
      # CalVer component (checked ../ex4pm/CHANGELOG.md directly -- it
      # does not exist yet), so "~> 26.9" cannot actually guarantee the
      # compatibility a SemVer `~>` pin implies. Exact-pin until ex4pm
      # publishes a real versioning policy for that component; then
      # revisit and loosen this constraint.
      {:ex4pm, "== 26.9.9"},
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
