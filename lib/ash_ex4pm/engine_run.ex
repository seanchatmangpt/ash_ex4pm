defmodule AshEx4pm.EngineRun do
  @moduledoc """
  ETS-backed record of one real ex4pm analytical run (CONSTRUCT only).

  Create actions `:discover | :conform | :simulate | :optimize | :plan` call
  the matching `Ex4pm` function through `AshEx4pm.Changes.RunEngine` and
  persist the `%Ex4pm.Run{}` envelope. Refusals raise
  `AshEx4pm.Errors.Refused` and persist nothing. `:by_receipt` reads by
  outcome receipt hash; generic actions `:replay` and `:capabilities` wrap
  `Ex4pm.replay/2` and `Ex4pm.capabilities/2`.
  """
  use Ash.Resource,
    domain: AshEx4pm.EngineRunDomain,
    data_layer: Ash.DataLayer.Ets

  alias AshEx4pm.Changes.RunEngine

  actions do
    defaults([:read, :destroy])

    read :by_receipt do
      argument(:receipt_hash, :string, allow_nil?: false)
      filter(expr(receipt_hash == ^arg(:receipt_hash)))
    end

    create :discover do
      argument(:subject, :term, allow_nil?: false)
      argument(:engine_opts, :term, default: [])
      change({RunEngine, operation: :discover})
    end

    create :conform do
      argument(:subject, :term, allow_nil?: false)
      argument(:model, :term, allow_nil?: false)
      argument(:engine_opts, :term, default: [])
      change({RunEngine, operation: :conform})
    end

    create :simulate do
      argument(:model, :term, allow_nil?: false)
      argument(:engine_opts, :term, default: [])
      change({RunEngine, operation: :simulate})
    end

    create :optimize do
      argument(:subject, :term, allow_nil?: false)
      argument(:model, :term, allow_nil?: false)
      argument(:engine_opts, :term, default: [])
      change({RunEngine, operation: :optimize})
    end

    create :plan do
      argument(:problem, :term, allow_nil?: false)
      argument(:engine_opts, :term, default: [])
      change({RunEngine, operation: :plan})
    end

    action :replay, :term do
      argument(:hash, :string, allow_nil?: false)
      argument(:engine_opts, :term, default: [])

      run(fn input, _ctx ->
        {:ok, Ex4pm.replay(input.arguments.hash, input.arguments.engine_opts)}
      end)
    end

    action :capabilities, {:array, :term} do
      argument(:operation, :atom, default: :discover)
      argument(:engine_opts, :term, default: [])

      run(fn input, _ctx ->
        {:ok, Ex4pm.capabilities(input.arguments.operation, input.arguments.engine_opts)}
      end)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:operation, :atom, public?: true)
    attribute(:engine, :atom, public?: true)
    attribute(:algorithm, :term, public?: true)
    attribute(:subject_hash, :string, public?: true)
    attribute(:standing, :atom, public?: true)
    attribute(:value, :term, public?: true)
    attribute(:receipt_hash, :string, public?: true)
    attribute(:pending_hash, :string, public?: true)
    attribute(:evidence, :term, public?: true)
  end
end
