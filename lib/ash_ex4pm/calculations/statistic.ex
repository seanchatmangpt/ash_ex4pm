defmodule AshEx4pm.Calculations.Statistic do
  @moduledoc """
  Ash calculation: a wasm4pm statistic (`op:`, e.g. `:mean`, `:median`, `:std_deviation`,
  `:percentile`) over a numeric-array attribute (`field:`).  Extra options (e.g. `p:`) pass
  through.  Returns the run's `value`, or `nil` on refusal or non-list input.
  """
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    if is_atom(opts[:op]) and is_atom(opts[:field]),
      do: {:ok, opts},
      else: {:error, "op: and field: are required"}
  end

  @impl true
  def load(_query, opts, _ctx), do: [opts[:field]]

  @impl true
  def calculate(records, opts, _ctx) do
    run_opts = Keyword.drop(opts, [:op, :field])

    Enum.map(records, fn record ->
      case Map.get(record, opts[:field]) do
        [_ | _] = data ->
          case AshEx4pm.WasmRuntime.statistics(opts[:op], data, run_opts) do
            {:ok, run} -> run.value
            {:error, _} -> nil
          end

        _ ->
          nil
      end
    end)
  end
end
