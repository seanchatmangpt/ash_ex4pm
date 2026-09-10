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

defmodule AshEx4pm.Test.SideEffectLog do
  @moduledoc """
  Real named Agent process used as a side-effect log for the
  before_action ordering test below -- a real collaborator, not a mock.
  """
  use Agent

  def start_link(_opts), do: Agent.start_link(fn -> 0 end, name: __MODULE__)
  def reset, do: Agent.update(__MODULE__, fn _ -> 0 end)
  def bump, do: Agent.update(__MODULE__, fn count -> count + 1 end)
  def count, do: Agent.get(__MODULE__, & &1)
end

defmodule AshEx4pm.Test.SideEffectChange do
  @moduledoc """
  Real `Ash.Resource.Change` registering its own plain `before_action`
  hook (no `prepend?: true`) that bumps `AshEx4pm.Test.SideEffectLog` --
  used to prove `AshEx4pm.Changes.BrceGate`'s admission check runs
  before any other `before_action` side effect, regardless of where the
  gate is declared relative to this change in the resource's `changes:`
  list.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      AshEx4pm.Test.SideEffectLog.bump()
      changeset
    end)
  end
end

defmodule AshEx4pm.Test.OrderedGatedResource do
  @moduledoc """
  BrceGate is declared AFTER `SideEffectChange` here on purpose --
  this is exactly the "maintainer places the gate second" hazard the
  ordering finding described. If BrceGate's hook ran in plain
  declaration order (appended, not prepended), a refused action would
  still let `SideEffectChange`'s side effect run first. The
  `prepend?: true` fix in `AshEx4pm.Changes.BrceGate` must keep the
  side effect from ever running when admission is refused, no matter
  this declaration order.
  """
  use Ash.Resource,
    domain: AshEx4pm.Test.OrderedGatedDomain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy])

    create :create do
      change({AshEx4pm.Test.SideEffectChange, []})
      change({AshEx4pm.Changes.BrceGate, operation: :ordered_gated_create})
    end
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshEx4pm.Test.OrderedGatedDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.OrderedGatedResource)
  end
end
