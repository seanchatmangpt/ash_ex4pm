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

defmodule AshEx4pm.Test.Widget do
  @moduledoc """
  Real Ash resource with a primary key NOT named :id -- proves
  `AshEx4pm.Notifier.record_id/2` resolves the real, declared primary
  key via `Ash.Resource.Info.primary_key/1` instead of assuming :id.
  """
  use Ash.Resource,
    domain: AshEx4pm.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [AshEx4pm.Notifier],
    extensions: [AshEx4pm]

  ex4pm do
    activity(:widget_created, on: :create)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:sku])
    end
  end

  attributes do
    attribute(:sku, :string, primary_key?: true, allow_nil?: false, public?: true)
  end
end

defmodule AshEx4pm.Test.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.Order)
    resource(AshEx4pm.Test.Widget)
  end
end
