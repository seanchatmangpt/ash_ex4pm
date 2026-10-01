defmodule AshEx4pm.BroadcasterTest do
  # Threads the optional realtime broadcaster (app env
  # `:ash_ex4pm, :broadcaster`) through `AshEx4pm.Notifier.notify/1` into
  # `Ex4pm.Stream.Ingest.ingest_envelope/2`'s real `:broadcaster` opt.
  # Real collaborators, no mocks: a real Agent stands in for the
  # broadcaster's consumer; the real global Evidence.Store proves the
  # ingest side effects. Shares the app env + global store, so not async.
  use ExUnit.Case, async: false

  alias AshEx4pm.Test.Order

  setup do
    Application.delete_env(:ash_ex4pm, :broadcaster)

    on_exit(fn ->
      Application.delete_env(:ash_ex4pm, :broadcaster)
    end)

    :ok
  end

  defp create_order do
    Order
    |> Ash.Changeset.for_create(:create, %{status: :pending})
    |> Ash.create()
  end

  test "default path unchanged: no app env set, ingest still lands in Ex4pm.Evidence.Store" do
    assert Application.get_env(:ash_ex4pm, :broadcaster) == nil

    before = length(Ex4pm.Evidence.Store.all())

    assert {:ok, _order} = create_order()

    assert length(Ex4pm.Evidence.Store.all()) == before + 2
  end

  test "fun broadcaster receives %{envelope:, log:, event_count:}" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    Application.put_env(:ash_ex4pm, :broadcaster, fn payload ->
      Agent.update(agent, &[payload | &1])
    end)

    assert {:ok, _order} = create_order()

    [payload] = Agent.get(agent, & &1)
    assert %{envelope: envelope, log: log, event_count: 1} = payload
    # ingest_envelope broadcasts the VALIDATED envelope struct, not the raw map
    assert envelope.schema == "ash_ex4pm/1"
    assert is_list(log.events) and length(log.events) == 1
  end

  test "MFA broadcaster is invoked with the payload appended to args" do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    Application.put_env(:ash_ex4pm, :broadcaster, {__MODULE__, :capture, [agent]})

    assert {:ok, _order} = create_order()

    [payload] = Agent.get(agent, & &1)
    assert %{envelope: %{}} = payload
  end

  def capture(agent, payload) do
    Agent.update(agent, &[payload | &1])
  end

  test "a crashing broadcaster raises out of notify/1 but the ingest side effects survive" do
    before = length(Ex4pm.Evidence.Store.all())

    Application.put_env(:ash_ex4pm, :broadcaster, fn _payload ->
      raise "broadcaster boom"
    end)

    # Real, verified ingest.ex:129-137 behavior: the broadcaster runs
    # synchronously AFTER the receipts are stored, unrescued -- the raise
    # propagates out of ingest_envelope (ingest.ex:132) through notify/1
    # (notifier.ex:175) and Ash wraps it as Ash.Error.Unknown from the
    # action, while the already-stored pending + outcome receipts prove
    # the ingest itself succeeded.
    assert_raise(Ash.Error.Unknown, ~r/broadcaster boom/, fn -> create_order() end)

    assert length(Ex4pm.Evidence.Store.all()) == before + 2
  end
end
