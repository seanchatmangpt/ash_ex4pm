defmodule AshEx4pm.ReceiptStore.Ets do
  @moduledoc """
  Real ETS-backed `AshEx4pm.ReceiptStore`: durable for the runtime of the
  owning process (add `AshEx4pm.ReceiptStore.Ets` to a supervision tree).

  The GenServer only owns a named `:public` table; reads and the atomic
  reservation (`:ets.insert_new/2`) go straight to ETS from the caller's
  process. If the owner is not running every callback returns
  `{:error, :receipt_store_unavailable}` rather than raising.
  """
  @behaviour AshEx4pm.ReceiptStore

  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, {:read_concurrency, true}])
    {:ok, %{table: table}}
  end

  @impl AshEx4pm.ReceiptStore
  def reserve(key, fingerprint) do
    guard(fn ->
      if :ets.insert_new(@table, {key, {:in_flight, fingerprint}}) do
        :reserved
      else
        case :ets.lookup(@table, key) do
          [{^key, {:sealed, entry}}] -> {:sealed, entry}
          [{^key, {:in_flight, existing}}] -> {:in_flight, existing}
          # released between insert_new and lookup: retry once
          [] -> reserve(key, fingerprint)
        end
      end
    end)
  end

  @impl AshEx4pm.ReceiptStore
  def seal(key, entry) do
    guard(fn ->
      true = :ets.insert(@table, {key, {:sealed, entry}})
      :ok
    end)
  end

  @impl AshEx4pm.ReceiptStore
  def release(key) do
    guard(fn ->
      :ets.match_delete(@table, {key, {:in_flight, :_}})
      :ok
    end)
    |> case do
      {:error, _} -> :ok
      :ok -> :ok
    end
  end

  defp guard(fun) do
    fun.()
  rescue
    ArgumentError -> {:error, :receipt_store_unavailable}
  end
end
