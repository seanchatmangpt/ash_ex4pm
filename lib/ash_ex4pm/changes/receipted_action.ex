defmodule AshEx4pm.Changes.ReceiptedAction do
  @moduledoc """
  Receipted DO seam: an `Ash.Resource.Change` that runs the real Ash
  mutation *inside* `Ex4pm.Evidence.BRCE.execute/5` and binds the real
  consequence to the outcome receipt.

  Unlike `AshEx4pm.Changes.BrceGate` (admission-only, `fn -> :admitted end`),
  this change registers an outermost `around_action` (`prepend?: true`).
  Ash runs `around_action` hooks around the whole in-transaction pipeline
  -- `before_action` hooks, the data-layer write and `after_action` hooks
  (`Ash.Changeset.run_around_actions/2`) -- so every refusal below happens
  before any other hook's side effect and before the write, and the BRCE
  outcome receipt covers the real write:

    1. subject = `subject_hash(resource, persisted_record | nil)` (the
       record's current persisted state, re-read from the data layer for
       update/destroy). A caller-supplied expected subject
       (`context: %{expected_subject: hash}` or the `:expected_subject`
       option) that differs is refused `{:stale_subject, expected, actual}`.
    2. idempotency (`idempotency_key: attribute_or_argument | fun/1`):
       fingerprint = sha256 of `%{resource, action, operation, subject
       identity (resource + primary key), input (params + arguments)}`.
       Same key + same fingerprint of a sealed entry returns the sealed
       result with metadata `replay: :known_replay` WITHOUT re-running the
       mutation; same key + different fingerprint is refused
       `{:idempotency_conflict, key}` before mutation.
    3. authority: `BRCE.execute/5` admits against the actor-derived
       authority (`BrceGate.authority_for/3`); refusal is
       `{:authority_refused, code}`. `operation: :local` is
       non-consequential: admission is skipped and the pending/outcome
       receipts are written with `authority: :none` (nil authority hash).
    4. the real mutation runs as BRCE's `fun`; `fun` returns the
       consequence term `%{resource, action, primary_key, changed}` so the
       outcome receipt's `artifact_hash` IS the consequence digest. A
       failed write becomes a `:blocked` outcome receipt and the original
       Ash error is returned.

  The result carries `Ash.Resource.put_metadata(record, :ash_ex4pm_receipt,
  map)` with keys `subject`, `operation`, `authority` (authority hash or
  `:none`), `consequence` (sha256 digest), `consequence_term`, `replay`
  (`:fresh | :known_replay`), `standing`, `receipt` (the
  `%Ex4pm.Evidence.Receipt{phase: :outcome}`), `receipt_hash`,
  `pending_hash`, `idempotency_key`, `fingerprint`, and on replay
  `replay_verification` (`Ex4pm.Evidence.Replay.verify/1` of the sealed
  receipt).

  Refusals are `AshEx4pm.Errors.Refused` (class `:forbidden`) with a typed
  `reason`.

  ## Options

    * `:operation` (required) -- BRCE operation name; `:local` = authority-free
    * `:idempotency_key` -- attribute/argument name, or `fun(changeset) -> key | nil`
    * `:expected_subject` -- static expected subject (context wins)
    * `:authority_from` -- as in `BrceGate`
    * `:store` -- `AshEx4pm.ReceiptStore` module (default `AshEx4pm.ReceiptStore.Ets`)
    * `:evidence_store` -- `Ex4pm.Evidence.Store` server (default its registered name)

  Update/destroy actions using this change need `require_atomic? false`.

  ## Remaining boundary

  The receipt is sealed inside the transaction (around_action); a commit
  failure after the around_action returns is not captured. The ETS data
  layer has no transactions, so this is UNVERIFIED for transactional data
  layers.
  """
  use Ash.Resource.Change

  alias AshEx4pm.Errors.Refused
  alias Ex4pm.Core.Hash
  alias Ex4pm.Evidence.{BRCE, Receipt, Replay, Store}

  @metadata_key :ash_ex4pm_receipt

  @impl true
  def change(changeset, opts, context) do
    operation = Keyword.fetch!(opts, :operation)

    authority =
      if operation == :local,
        do: nil,
        else: AshEx4pm.Changes.BrceGate.authority_for(changeset, opts, context)

    Ash.Changeset.around_action(
      changeset,
      fn changeset, callback -> run(changeset, callback, operation, authority, opts) end,
      prepend?: true
    )
  end

  @doc "Subject hash of `record`'s persisted state (`nil` = not yet persisted)."
  def subject_hash(resource, record) do
    primary_key = Ash.Resource.Info.primary_key(resource)

    state =
      case record do
        nil -> nil
        record -> Map.take(record, attribute_names(resource))
      end

    Hash.digest(%{
      resource: resource,
      primary_key: record && Map.new(primary_key, &{&1, Map.get(record, &1)}),
      state: state
    })
  end

  @doc "The receipt metadata attached to a result, or nil."
  def receipt(record), do: Map.get(record.__metadata__ || %{}, @metadata_key)

  defp run(changeset, callback, operation, authority, opts) do
    store = Keyword.get(opts, :store, AshEx4pm.ReceiptStore.Ets)
    subject = subject_hash(changeset.resource, persisted(changeset))

    with :ok <- check_subject(changeset, opts, subject),
         {:ok, idem} <- idempotency(changeset, opts, operation, store) do
      case idem do
        {:replay, entry} ->
          {:ok, replayed(entry), changeset, %{notifications: []}}

        claim ->
          case execute(changeset, callback, operation, authority, subject, claim, opts) do
            {:ok, _result, _changeset, _instructions} = ok ->
              ok

            {:error, _} = error ->
              release(claim, store)
              error
          end
      end
    end
  end

  # -- subject ---------------------------------------------------------------

  defp persisted(%{action_type: :create}), do: nil

  defp persisted(changeset) do
    primary_key = Ash.Resource.Info.primary_key(changeset.resource)
    pk = Map.new(primary_key, &{&1, Map.get(changeset.data, &1)})

    case Ash.get(changeset.resource, pk, domain: changeset.domain, authorize?: false) do
      {:ok, record} -> record
      {:error, _} -> nil
    end
  end

  defp check_subject(changeset, opts, actual) do
    case changeset.context[:expected_subject] || Keyword.get(opts, :expected_subject) do
      nil -> :ok
      ^actual -> :ok
      expected -> refuse({:stale_subject, expected, actual})
    end
  end

  # -- idempotency -----------------------------------------------------------

  defp idempotency(changeset, opts, operation, store) do
    case idempotency_key(changeset, Keyword.get(opts, :idempotency_key)) do
      nil ->
        {:ok, :no_key}

      key ->
        fingerprint = fingerprint(changeset, operation)
        store_key = {changeset.resource, changeset.action.name, key}

        case store.reserve(store_key, fingerprint) do
          :reserved ->
            {:ok, {:claimed, key, store_key, fingerprint}}

          {:sealed, %{fingerprint: ^fingerprint} = entry} ->
            {:ok, {:replay, entry}}

          {:sealed, _other} ->
            refuse({:idempotency_conflict, key})

          {:in_flight, ^fingerprint} ->
            refuse({:idempotency_in_flight, key})

          {:in_flight, _other} ->
            refuse({:idempotency_conflict, key})

          {:error, :receipt_store_unavailable} ->
            refuse({:receipt_store_unavailable, store})
        end
    end
  end

  defp idempotency_key(_changeset, nil), do: nil
  defp idempotency_key(changeset, fun) when is_function(fun, 1), do: fun.(changeset)

  defp idempotency_key(changeset, name) when is_atom(name),
    do: Ash.Changeset.get_argument_or_attribute(changeset, name)

  defp fingerprint(changeset, operation) do
    primary_key = Ash.Resource.Info.primary_key(changeset.resource)

    identity =
      case changeset.action_type do
        :create -> nil
        _ -> Map.new(primary_key, &{&1, Map.get(changeset.data, &1)})
      end

    Hash.digest(%{
      resource: changeset.resource,
      action: changeset.action.name,
      operation: operation,
      subject: %{resource: changeset.resource, primary_key: identity},
      input: %{
        params: stringify(changeset.params || %{}),
        arguments: stringify(changeset.arguments || %{})
      }
    })
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp release({:claimed, _key, store_key, _fp}, store), do: store.release(store_key)
  defp release(_claim, _store), do: :ok

  defp replayed(%{result: result, receipt: meta}) do
    verification =
      case Replay.verify(meta.receipt) do
        {:ok, %{replay: :match}} -> :match
        {:error, refusal} -> {:mismatch, refusal.code}
      end

    Ash.Resource.put_metadata(
      result,
      @metadata_key,
      Map.merge(meta, %{replay: :known_replay, replay_verification: verification})
    )
  end

  # -- DO --------------------------------------------------------------------

  defp execute(changeset, callback, operation, authority, subject, claim, opts) do
    slot = {__MODULE__, make_ref()}
    evidence_store = Keyword.get(opts, :evidence_store, Store)

    fun = fn ->
      case callback.(changeset) do
        {:ok, result, new_changeset, instructions} ->
          Process.put(slot, {result, new_changeset, instructions})
          consequence_term(new_changeset, result)

        {:error, error} ->
          throw({__MODULE__, :mutation_failed, error})
      end
    end

    metadata = %{resource: inspect(changeset.resource), action: changeset.action.name}

    outcome =
      if operation == :local do
        local_execute(subject, fun, evidence_store, metadata)
      else
        BRCE.execute(subject, operation, authority, fun,
          store: evidence_store,
          metadata: metadata
        )
      end

    stashed = Process.delete(slot)

    case outcome do
      {:ok, %{result: consequence, pending: pending, receipt: receipt}} ->
        {result, new_changeset, instructions} = stashed
        meta = receipt_metadata(operation, subject, consequence, pending, receipt, claim)
        seal(claim, result, meta, Keyword.get(opts, :store, AshEx4pm.ReceiptStore.Ets))

        {:ok, Ash.Resource.put_metadata(result, @metadata_key, meta), new_changeset, instructions}

      {:error, %Ex4pm.Refusal{} = refusal} ->
        {:error, Refused.exception(reason: {:authority_refused, refusal.code}, refusal: refusal)}

      {:error, %{error: {:throw, {__MODULE__, :mutation_failed, error}}}} ->
        {:error, error}

      {:error, %{error: %{__exception__: true} = exception}} ->
        {:error, exception}

      {:error, %{error: other}} ->
        {:error, Refused.exception(reason: {:mutation_failed, other})}
    end
  end

  # Authority-free receipting for `operation: :local`: the same pending ->
  # outcome chain `BRCE.execute/5` writes, with a nil authority (no
  # admission is consulted; nothing consequential is being authorized).
  defp local_execute(subject, fun, store, metadata) do
    pending = Receipt.pending(subject, :local, nil, metadata)
    {:ok, _} = Store.put(pending, store)

    try do
      result = fun.()
      outcome = Receipt.outcome(pending, result, :alive, Map.put(metadata, :result, :ok))
      {:ok, _} = Store.put(outcome, store)
      {:ok, %{result: result, pending: pending, receipt: outcome}}
    catch
      kind, reason ->
        outcome =
          Receipt.outcome(
            pending,
            %{kind: kind, reason: inspect(reason)},
            :blocked,
            Map.put(metadata, :result, :caught)
          )

        {:ok, _} = Store.put(outcome, store)
        {:error, %{error: {kind, reason}, pending: pending, receipt: outcome}}
    end
  end

  defp consequence_term(changeset, result) do
    resource = changeset.resource
    primary_key = Ash.Resource.Info.primary_key(resource)

    %{
      resource: resource,
      action: changeset.action.name,
      primary_key: Map.new(primary_key, &{&1, Map.get(result, &1)}),
      changed: Map.take(result, Map.keys(changeset.attributes))
    }
  end

  defp receipt_metadata(operation, subject, consequence, pending, receipt, claim) do
    {key, fingerprint} =
      case claim do
        {:claimed, key, _store_key, fingerprint} -> {key, fingerprint}
        _ -> {nil, nil}
      end

    %{
      subject: subject,
      operation: operation,
      authority: receipt.authority_hash || :none,
      consequence: receipt.artifact_hash,
      consequence_term: consequence,
      replay: :fresh,
      standing: receipt.standing,
      receipt: receipt,
      receipt_hash: receipt.hash,
      pending_hash: pending.hash,
      idempotency_key: key,
      fingerprint: fingerprint
    }
  end

  defp seal({:claimed, _key, store_key, fingerprint}, result, meta, store) do
    store.seal(store_key, %{fingerprint: fingerprint, result: result, receipt: meta})
  end

  defp seal(_claim, _result, _meta, _store), do: :ok

  defp refuse(reason), do: {:error, Refused.exception(reason: reason)}

  defp attribute_names(resource),
    do: resource |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)
end
