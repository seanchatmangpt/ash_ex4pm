defmodule AshEx4pm.Evidence.RealtimeBridge do
  use GenServer

  @persistent_term_key "ash_ex4pm/evidence_bridge"

  @doc "Opts: `:capacity` (default: app env :ash_ex4pm :bridge_capacity, else 10_000)."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    capacity =
      Keyword.get_lazy(opts, :capacity, fn ->
        Application.get_env(:ash_ex4pm, :bridge_capacity, 10_000)
      end)

    _table =
      :ets.new(:ash_ex4pm_evidence_ring, [
        :ordered_set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    :persistent_term.put(@persistent_term_key, %{seq: 0, pending: :queue.new()})
    {:ok, %{capacity: capacity}, {:continue, :tick}}
  end

  @doc """
  Producer-side emit: writes the envelope/event into the persistent_term handoff
  slot (cheap, crash-safe for the producer); the bridge drains it on its tick.
  """
  def push(item) do
    cur = :persistent_term.get(@persistent_term_key, %{seq: 0, pending: :queue.new()})
    :persistent_term.put(@persistent_term_key, %{cur | pending: :queue.in(item, cur.pending)})
    :ok
  end

  @impl true
  def handle_continue(:tick, state) do
    handle_info(:tick, state)
  end

  @impl true
  def handle_info(:tick, %{capacity: cap} = state) do
    table = ring_table()
    cur = :persistent_term.get(@persistent_term_key, %{seq: 0, pending: :queue.new()})
    items = :queue.to_list(cur.pending)

    batch =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, i} -> {cur.seq + i, item} end)

    Enum.each(batch, fn entry -> :ets.insert(table, entry) end)

    evict_oldest(table, cap)

    :persistent_term.put(@persistent_term_key, %{
      cur
      | seq: cur.seq + length(items),
        pending: :queue.new()
    })

    Process.send_after(self(), :tick, 50)
    {:noreply, state}
  end

  defp ring_table, do: :ash_ex4pm_evidence_ring

  defp evict_oldest(table, cap) do
    excess = :ets.info(table, :size) - cap

    if excess > 0 do
      table
      |> :ets.tab2list()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.take(excess)
      |> Enum.each(fn {seq, _item} -> :ets.delete(table, seq) end)
    end

    :ok
  end

  @doc "Drain the ring: returns events oldest-first and clears the buffer."
  @spec drain() :: [term()]
  def drain do
    table = ring_table()
    entries = table |> :ets.tab2list() |> Enum.sort_by(&elem(&1, 0))
    :ets.delete_all_objects(table)
    Enum.map(entries, &elem(&1, 1))
  end

  @doc "Current ring occupancy."
  @spec size() :: non_neg_integer()
  def size, do: :ets.info(ring_table(), :size)

  @doc "Configured ring capacity (app env :ash_ex4pm :bridge_capacity, else 10_000)."
  def capacity do
    Application.get_env(:ash_ex4pm, :bridge_capacity, 10_000)
  end

  @impl true
  def handle_call(:drain, _from, state) do
    {:reply, drain(), state}
  end
end
