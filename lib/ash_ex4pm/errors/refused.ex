defmodule AshEx4pm.Errors.Refused do
  @moduledoc """
  Pre-mutation refusal raised by `AshEx4pm.Changes.ReceiptedAction`.

  `reason` is the typed refusal term:

    * `{:authority_refused, code}` -- BRCE admission refused (`refusal` holds
      the `%Ex4pm.Refusal{}`)
    * `{:idempotency_conflict, key}` -- same key, different fingerprint
    * `{:idempotency_in_flight, key}` -- same key and fingerprint still running
    * `{:stale_subject, expected, actual}` -- caller's expected subject hash
      does not match the persisted subject
    * `{:receipt_store_unavailable, store}` -- idempotency ledger not running
  """
  use Splode.Error, fields: [:reason, :refusal], class: :forbidden

  def message(%{reason: reason}), do: "receipted action refused: #{inspect(reason)}"
end
