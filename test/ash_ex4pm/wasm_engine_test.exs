defmodule AshEx4pm.Test.WasmProbe do
  @moduledoc false
  use Ash.Resource,
    domain: AshEx4pm.Test.WasmProbeDomain,
    data_layer: Ash.DataLayer.Ets

  actions do
    defaults([:read, :destroy])

    # Create action whose before_action change routes to the real ex4pm
    # engine graph (Ex4pm.Engine.execute/3 -> Ex4pmEngine.Wasm.Discover ->
    # RealTransport -> real Wasmex instance) and persists the outcome.
    create :discover do
      accept([:label])
      argument(:traces, {:array, {:array, :string}}, allow_nil?: false)
      argument(:engine_opts, :term, default: [])
      change(AshEx4pm.Test.WasmProbe.RouteToEngine)
    end

    # Generic action: returns the engine's Result struct/refusal verbatim.
    action :discover_raw, :term do
      argument(:traces, {:array, {:array, :string}}, allow_nil?: false)
      argument(:engine_opts, :term, default: [])

      run(fn input, _ctx ->
        subject = %{traces: input.arguments.traces}
        {:ok, Ex4pm.Engine.execute(:discover, subject, input.arguments.engine_opts)}
      end)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:label, :string, public?: true)
    attribute(:standing, :atom, public?: true)
    attribute(:activities, {:array, :string}, public?: true)
    attribute(:edges, {:array, :map}, public?: true)
    attribute(:refusal, :string, public?: true)
  end
end

defmodule AshEx4pm.Test.WasmProbe.RouteToEngine do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _ctx) do
    Ash.Changeset.before_action(changeset, fn cs ->
      subject = %{traces: Ash.Changeset.get_argument(cs, :traces)}

      case Ex4pm.Engine.execute(:discover, subject, Ash.Changeset.get_argument(cs, :engine_opts)) do
        {:ok, result} ->
          cs
          |> Ash.Changeset.force_change_attribute(:standing, result.standing)
          |> Ash.Changeset.force_change_attribute(:activities, result.value["activities"])
          |> Ash.Changeset.force_change_attribute(:edges, result.value["edges"])

        {:error, reason} ->
          Ash.Changeset.force_change_attribute(cs, :refusal, inspect(reason))
      end
    end)
  end
end

defmodule AshEx4pm.Test.WasmProbeDomain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshEx4pm.Test.WasmProbe)
  end
end

defmodule AshEx4pm.WasmEngineTest do
  @moduledoc """
  Chicago-style: a real Ash action (real ETS data layer) routes to the real
  `Ex4pm.Engine.execute/3`, which selects `Ex4pmEngine.Wasm.Discover`, which
  drives a real `Wasmex` instance of the real wasm4pm artifact through
  `Ex4pmEngine.Wasm.RealTransport` (alloc/write/call/read/free, plus real
  `_replay_v1` re-execution). Assertions are on persisted records and
  returned engine results -- no doubles.

  Artifact: env `WASM4PM_EX4PM_WASM`. Unset, or ex4pm/wasmex modules absent,
  => explicit named skip (not a silent pass).
  """
  use ExUnit.Case, async: false

  @artifact System.get_env("WASM4PM_EX4PM_WASM")

  cond do
    @artifact in [nil, ""] ->
      @moduletag skip: "WASM4PM_EX4PM_WASM unset: no real wasm4pm artifact to execute"

    not File.regular?(@artifact) ->
      @moduletag skip: "WASM4PM_EX4PM_WASM is not a regular file: #{@artifact}"

    not (Code.ensure_loaded?(Ex4pm.Engine) and Code.ensure_loaded?(Wasmex) and
             Code.ensure_loaded?(Ex4pmEngine.Wasm.RealTransport)) ->
      @moduletag skip: "ex4pm engine / Wasmex / RealTransport modules not available"

    true ->
      :ok
  end

  alias AshEx4pm.Test.WasmProbe

  setup do
    {:ok, transports} = Ex4pmEngine.Wasm.RealTransport.all_transports(@artifact)
    {:ok, engine_opts: transports}
  end

  test "Ash create action routes to Engine.execute against the real wasm artifact; result persists",
       %{engine_opts: engine_opts} do
    traces = [["a", "b", "c"], ["a", "b"]]

    assert {:ok, record} =
             WasmProbe
             |> Ash.Changeset.for_create(:discover, %{
               label: "wasm-probe",
               traces: traces,
               engine_opts: engine_opts
             })
             |> Ash.create()

    # re-read from the real data layer: state, not interactions
    persisted = Ash.get!(WasmProbe, record.id)

    assert persisted.standing == :alive
    assert persisted.refusal == nil
    assert Enum.sort(persisted.activities) == ["a", "b", "c"]

    ab = Enum.find(persisted.edges, &(&1["from"] == "a" and &1["to"] == "b"))
    bc = Enum.find(persisted.edges, &(&1["from"] == "b" and &1["to"] == "c"))
    assert ab["freq"] == 2
    assert bc["freq"] == 1
  end

  test "generic Ash action returns the engine result with observed, replay-verified wasm identity",
       %{engine_opts: engine_opts} do
    assert {:ok, {:ok, result}} =
             WasmProbe
             |> Ash.ActionInput.for_action(:discover_raw, %{
               traces: [["x", "y"]],
               engine_opts: engine_opts
             })
             |> Ash.run_action()

    assert result.standing == :alive
    assert result.value["activities"] |> Enum.sort() == ["x", "y"]

    {:ok, bytes} = File.read(@artifact)
    expected_hash = Ex4pm.Core.Hash.digest(bytes)
    inspected = inspect(result.evidence)
    assert inspected =~ expected_hash
  end

  test "without a wasm transport the engine graph refuses and the action persists the refusal, not a result" do
    assert {:ok, record} =
             WasmProbe
             |> Ash.Changeset.for_create(:discover, %{
               label: "no-transport",
               traces: [["a", "b"]],
               engine_opts: []
             })
             |> Ash.create()

    persisted = Ash.get!(WasmProbe, record.id)
    assert persisted.standing == nil
    assert persisted.activities == nil
    assert is_binary(persisted.refusal)
  end
end
