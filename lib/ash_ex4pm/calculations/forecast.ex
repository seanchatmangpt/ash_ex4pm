defmodule AshEx4pm.Calculations.Forecast do
  @moduledoc """
  Ash calculation: forecast a numeric-array attribute through the real wasm4pm engine.

  Options: `field:` (attribute holding `[number()]`), `method:` (`:forecast | :holt | :ewma`,
  default `:forecast`), plus `alpha:`/`beta:`.  Returns the run's `value`, or `nil` on refusal
  or non-numeric input.
  """
  use Ash.Resource.Calculation

  @impl true
  def init(opts) do
    if is_atom(opts[:field]), do: {:ok, opts}, else: {:error, "field: is required"}
  end

  @impl true
  def load(_query, opts, _ctx), do: [opts[:field]]

  @impl true
  def calculate(records, opts, _ctx) do
    run_opts = Keyword.take(opts, [:method, :alpha, :beta])

    Enum.map(records, fn record ->
      case Map.get(record, opts[:field]) do
        [_ | _] = series ->
          case AshEx4pm.WasmRuntime.forecast(series, run_opts) do
            {:ok, run} -> run.value
            {:error, _} -> nil
          end

        _ ->
          nil
      end
    end)
  end
end
