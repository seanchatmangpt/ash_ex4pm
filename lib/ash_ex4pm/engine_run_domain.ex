defmodule AshEx4pm.EngineRunDomain do
  @moduledoc "Ash domain for `AshEx4pm.EngineRun`."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.EngineRun)
  end
end
