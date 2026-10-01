defmodule AshEx4pm.Calculations.CapabilityProjection do
  @moduledoc """
  Ash calculation deriving `admitted` from stored projection fields
  (`standing`, `replay_verified`, `artifact_sha256`). Never re-executes the engine.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _ctx), do: [:standing, :replay_verified, :artifact_sha256]

  @impl true
  def calculate(records, _opts, _ctx), do: Enum.map(records, &admitted?/1)

  defp admitted?(r) do
    r.standing == :alive and r.replay_verified == true and is_binary(r.artifact_sha256)
  end
end
