defmodule AshEx4pm.MixProject do
  use Mix.Project

  @version "0.1.0"
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
      # Real path dependency -- ash_ex4pm is developed alongside its one
      # real consumer/provider, ex4pm, per this repo's own PRD/ARD
      # (~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md). Every OCEL
      # envelope this extension builds is validated and ingested through
      # ex4pm's own real, canonical functions -- never a hand-rolled
      # struct or a re-implemented ingest path.
      {:ex4pm, path: "../ex4pm"},
      {:igniter, "~> 0.5", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Ash extension for automatic OCEL 2.0 event emission, built on ex4pm's " <>
      "canonical Ex4pm.OCEL.normalize/1 and Ex4pm.Stream.Ingest.ingest_envelope/2."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
