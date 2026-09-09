defmodule AshEx4pm.Test.Order do
  @moduledoc "Real Ash resource under test -- Ash.DataLayer.Ets, no database needed."
  use Ash.Resource,
    domain: AshEx4pm.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [AshEx4pm.Notifier],
    extensions: [AshEx4pm]

  ex4pm do
    activity(:order_created, on: :create)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:status])
    end

    update :ship do
      accept([])
      change(set_attribute(:status, :shipped))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:status, :atom, default: :pending, public?: true)
  end
end

defmodule AshEx4pm.Test.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.Order)
  end
end
