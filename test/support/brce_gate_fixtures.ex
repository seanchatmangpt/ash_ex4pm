defmodule AshEx4pm.Test.GatedResource do
  @moduledoc false
  use Ash.Resource,
    domain: AshEx4pm.Test.GatedDomain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy])

    create :create do
      change({AshEx4pm.Changes.BrceGate, operation: :gated_create})
    end
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshEx4pm.Test.GatedDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.GatedResource)
  end
end

defmodule AshEx4pm.Test.AdmittedResource do
  @moduledoc false
  use Ash.Resource,
    domain: AshEx4pm.Test.AdmittedDomain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:label])
      change({AshEx4pm.Changes.BrceGate, operation: :admitted_create})
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:label, :string, public?: true)
  end
end

defmodule AshEx4pm.Test.AdmittedDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.AdmittedResource)
  end
end
