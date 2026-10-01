defmodule AshEx4pm.ReceiptStore do
  @moduledoc """
  Idempotency ledger behaviour for `AshEx4pm.Changes.ReceiptedAction`.

  A store maps an idempotency key to either an in-flight reservation
  (`{:in_flight, fingerprint}`) or a sealed entry (the fingerprint, the
  sealed Ash result and its receipt metadata). `reserve/2` must be atomic:
  two concurrent callers with the same key must never both get
  `:reserved`.

  `Ex4pm.Evidence.Store` (the ex4pm receipt ledger) is keyed by receipt
  hash and holds receipts, not results, so it cannot answer "what did
  key K already produce"; this behaviour is that missing index. The
  in-repo implementation is `AshEx4pm.ReceiptStore.Ets`.
  """

  @type key :: term()
  @type fingerprint :: String.t()
  @type entry :: %{fingerprint: fingerprint(), result: term(), receipt: map()}

  @callback reserve(key(), fingerprint()) ::
              :reserved
              | {:sealed, entry()}
              | {:in_flight, fingerprint()}
              | {:error, term()}
  @callback seal(key(), entry()) :: :ok | {:error, term()}
  @callback release(key()) :: :ok
end
