defmodule AshEx4pm do
  @moduledoc """
  Ash extension providing automatic OCEL 2.0 event emission for Ash
  resources/domains, built directly on ex4pm's real, canonical
  functions -- never a hand-rolled envelope shape or a re-implemented
  ingest path. See `~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md` for
  the full PRD/ARD this implements.

  ## Usage

      defmodule MyApp.Order do
        use Ash.Resource,
          domain: MyApp.Domain,
          notifiers: [AshEx4pm.Notifier],
          extensions: [AshEx4pm]

        ex4pm do
          activity :order_created, on: :create
        end

        actions do
          defaults [:read, :destroy]
          create :create
        end
      end

  `notifiers: [AshEx4pm.Notifier]` must be added explicitly (this
  extension does not inject itself into an already-declared
  `notifiers:` list -- see the PRD's explicit non-goal, "global notifier
  injection", `ash-extension-core-pack`'s own tracker names this as a
  real, unbuilt gap). `extensions: [AshEx4pm]` provides the `ex4pm do
  ... end` DSL and compiles it; `notifiers: [AshEx4pm.Notifier]` is what
  actually fires on every matching action.
  """

  use Spark.Dsl.Extension,
    sections: [AshEx4pm.Dsl.section()],
    transformers: [AshEx4pm.Transformers.Persist],
    verifiers: [AshEx4pm.Verifiers.Verify]
end
