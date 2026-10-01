defmodule AshEx4pm.WasmRuntime do
  @moduledoc """
  Ash-facing adapter over the bundled wasm engines of `Ex4pm` (wasm4pm statistics,
  forecasting, and ferroplan).  Owns no semantics; delegates to `Ex4pm` and, if the
  installed ex4pm lacks the contract, every call is a typed
  `:wasm_runtime_unavailable` refusal with standing `:partial_alive`.

  Results are candidates only; this adapter grants no DO authority.
  """

  @provider Ex4pm

  @required_contract [health: 1, wasm: 1, ferroplan: 3, statistics: 3, forecast: 2]

  @doc "Canonical provider module (owned by ex4pm)."
  @spec provider() :: module()
  def provider, do: @provider

  @doc "Provider surface this adapter requires."
  @spec required_contract() :: keyword(non_neg_integer())
  def required_contract, do: @required_contract

  @doc "Required provider functions that are not exported (empty when fully available)."
  @spec missing_contract() :: keyword(non_neg_integer())
  def missing_contract do
    if Code.ensure_loaded?(@provider) do
      Enum.reject(@required_contract, fn {name, arity} ->
        function_exported?(@provider, name, arity)
      end)
    else
      @required_contract
    end
  end

  @doc "True when ex4pm exports the full required contract."
  @spec available?() :: boolean()
  def available?, do: missing_contract() == []

  @doc "Evidence-bounded standing from `Ex4pm.health(probe: false)` (no wasm call executed)."
  @spec standing() :: {atom(), map()}
  def standing do
    if available?() do
      health = apply(@provider, :health, [[probe: false]])
      {health.standing, health}
    else
      {:partial_alive, %{provider: @provider, missing: missing_contract()}}
    end
  end

  @doc "Per-engine health (`Ex4pm.health/1`); probes real wasm unless `probe: false`."
  @spec health(keyword()) :: {:ok, map()} | {:error, term()}
  def health(opts \\ []), do: with_provider(fn -> {:ok, apply(@provider, :health, [opts])} end)

  @doc "Inspection-only list of wasm4pm algorithm engines (`Ex4pm.wasm/1`)."
  @spec algorithms(keyword()) :: {:ok, [map()]} | {:error, term()}
  def algorithms(opts \\ []), do: with_provider(fn -> {:ok, apply(@provider, :wasm, [opts])} end)

  @doc "Real wasm statistics (`Ex4pm.statistics/3`)."
  @spec statistics(atom(), term(), keyword()) :: {:ok, struct()} | {:error, term()}
  def statistics(op, data, opts \\ []),
    do: with_provider(fn -> apply(@provider, :statistics, [op, data, opts]) end)

  @doc "Real wasm forecast (`Ex4pm.forecast/2`); `:method` is `:forecast | :holt | :ewma`."
  @spec forecast([number()], keyword()) :: {:ok, struct()} | {:error, term()}
  def forecast(series, opts \\ []),
    do: with_provider(fn -> apply(@provider, :forecast, [series, opts]) end)

  @doc "Ferroplan operation (`Ex4pm.ferroplan/3`)."
  @spec ferroplan(atom(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def ferroplan(op, subject \\ %{}, opts \\ []),
    do: with_provider(fn -> apply(@provider, :ferroplan, [op, subject, opts]) end)

  defp with_provider(fun) do
    if available?() do
      fun.()
    else
      {:error, {:wasm_runtime_unavailable, %{provider: @provider, missing: missing_contract()}}}
    end
  end
end
