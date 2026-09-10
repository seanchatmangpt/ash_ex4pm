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

  relationships do
    has_many(:line_items, AshEx4pm.Test.LineItem)
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

    update :add_line_item do
      accept([])
      require_atomic?(false)
      argument(:line_item, :map, allow_nil?: false)
      change(manage_relationship(:line_item, :line_items, type: :create))
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

defmodule AshEx4pm.Test.Invoice do
  @moduledoc """
  Real Ash resource declaring an explicit `object_type` -- proves the OCEL
  2.0 object-type schema (name + typed attributes) is a real, compiled
  DSL construct, not just `AshEx4pm.Notifier.resource_type_name/1`'s
  module-name derivation.
  """
  use Ash.Resource,
    domain: AshEx4pm.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [AshEx4pm.Notifier],
    extensions: [AshEx4pm]

  ex4pm do
    object_type(:invoice, attributes: [total_amount: :decimal, currency: :string])
    activity(:invoice_created, on: :create, object_type: :invoice)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:total_amount, :currency])
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:total_amount, :decimal, public?: true)
    attribute(:currency, :string, public?: true)
  end
end

defmodule AshEx4pm.Test.LineItem do
  @moduledoc "Real related Ash resource -- appended via manage_relationship on Order."
  use Ash.Resource,
    domain: AshEx4pm.Test.Domain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:sku, :order_id])
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:sku, :string, public?: true)
  end

  relationships do
    belongs_to(:order, AshEx4pm.Test.Order, public?: true)
  end
end

defmodule AshEx4pm.Test.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.Order)
    resource(AshEx4pm.Test.Widget)
    resource(AshEx4pm.Test.Invoice)
    resource(AshEx4pm.Test.LineItem)
  end
end
