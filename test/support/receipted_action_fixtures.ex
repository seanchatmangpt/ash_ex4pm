defmodule AshEx4pm.Test.ReceiptedResource do
  @moduledoc """
  Real ETS-backed resource exercising `AshEx4pm.Changes.ReceiptedAction`:
  a consequential create (idempotency keyed by the `:request_id`
  argument), a consequential update (stale-subject target), a plain
  un-receipted update (used to make a subject stale), and an
  authority-free `:local` create.
  """
  use Ash.Resource,
    domain: AshEx4pm.Test.ReceiptedDomain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:label])
      argument(:request_id, :string)

      change(
        {AshEx4pm.Changes.ReceiptedAction,
         operation: :receipted_create, idempotency_key: :request_id}
      )
    end

    create :local_create do
      accept([:label])
      change({AshEx4pm.Changes.ReceiptedAction, operation: :local})
    end

    update :relabel do
      accept([:label])
      require_atomic?(false)
      change({AshEx4pm.Changes.ReceiptedAction, operation: :receipted_relabel})
    end

    update :touch do
      accept([:label])
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:label, :string, public?: true)
  end
end

defmodule AshEx4pm.Test.ReceiptedDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.ReceiptedResource)
  end
end
