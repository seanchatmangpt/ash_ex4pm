defmodule AshEx4pm.Test.Series do
  @moduledoc false
  use Ash.Resource, domain: AshEx4pm.Test.SeriesDomain, data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy, create: [:name, :values]])

    action :mean_of, :term do
      argument(:values, {:array, :float}, allow_nil?: false)

      run(fn input, _ctx ->
        case AshEx4pm.WasmRuntime.statistics(:mean, input.arguments.values, []) do
          {:ok, run} -> {:ok, run.value}
          {:error, refusal} -> {:ok, {:refused, refusal.code}}
        end
      end)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
    attribute(:values, {:array, :float}, public?: true)
  end

  calculations do
    calculate(:mean, :term, {AshEx4pm.Calculations.Statistic, op: :mean, field: :values})
    calculate(:median, :term, {AshEx4pm.Calculations.Statistic, op: :median, field: :values})
    calculate(:next, :term, {AshEx4pm.Calculations.Forecast, field: :values, method: :holt})
    calculate(:bad_op, :term, {AshEx4pm.Calculations.Statistic, op: :nope, field: :values})
  end
end

defmodule AshEx4pm.Test.SeriesDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.Series)
  end
end

defmodule AshEx4pm.WasmRuntimeTest do
  @moduledoc """
  Chicago-style: real bundled wasm4pm artifact driven through `Ex4pm`, real Ash
  resource with ETS data layer; assertions on returned values and persisted records.
  """
  use ExUnit.Case, async: false

  alias AshEx4pm.Test.Series
  alias AshEx4pm.WasmRuntime

  test "contract is available and standing reports from health(probe: false)" do
    assert WasmRuntime.missing_contract() == []
    assert WasmRuntime.available?()
    {standing, health} = WasmRuntime.standing()
    assert standing in [:alive, :partial_alive, :blocked, :build_broken]
    assert is_map(health.wasm4pm)
  end

  test "algorithms/1 lists wasm engines without executing" do
    assert {:ok, [first | _] = algos} = WasmRuntime.algorithms()
    assert length(algos) >= 30
    assert first.executed == false
  end

  test "statistics/3 and forecast/2 run the real wasm" do
    assert {:ok, run} = WasmRuntime.statistics(:mean, [1.0, 2.0, 3.0, 4.0])
    IO.inspect(run.value, label: "mean value shape")
    assert run.standing == :alive

    assert {:ok, f} = WasmRuntime.forecast([1.0, 2.0, 3.0, 4.0, 5.0], method: :holt)
    IO.inspect(f.value, label: "holt value shape")

    assert {:error, %Ex4pm.Refusal{code: :invalid_forecast_method}} =
             WasmRuntime.forecast([1.0], method: :bogus)

    assert {:error, %Ex4pm.Refusal{code: :unsupported_statistics_operation}} =
             WasmRuntime.statistics(:nope, [1.0])
  end

  test "ferroplan/3 refuses an unsupported op with a typed refusal" do
    assert {:error, %Ex4pm.Refusal{code: :ferroplan_unsupported_operation}} =
             WasmRuntime.ferroplan(:nope)
  end

  test "Ash generic action and calculations over persisted numeric arrays" do
    rec = Ash.create!(Series, %{name: "s", values: [1.0, 2.0, 3.0, 4.0, 10.0]})

    loaded = Ash.load!(rec, [:mean, :median, :next, :bad_op])
    IO.inspect({loaded.mean, loaded.median, loaded.next}, label: "calc values")

    {:ok, direct_mean} = WasmRuntime.statistics(:mean, [1.0, 2.0, 3.0, 4.0, 10.0])
    assert loaded.mean == direct_mean.value
    assert loaded.median != nil
    assert loaded.next != nil
    assert loaded.bad_op == nil

    empty = Ash.create!(Series, %{name: "e", values: []})
    assert Ash.load!(empty, [:mean]).mean == nil

    assert Series
           |> Ash.ActionInput.for_action(:mean_of, %{values: [2.0, 4.0]})
           |> Ash.run_action!() ==
             WasmRuntime.statistics(:mean, [2.0, 4.0]) |> elem(1) |> Map.get(:value)
  end
end
