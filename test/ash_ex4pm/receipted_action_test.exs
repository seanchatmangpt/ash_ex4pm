defmodule AshEx4pm.Changes.ReceiptedActionTest do
  @moduledoc """
  Chicago-style: real Ash resource on the real ETS data layer, real
  `Ex4pm.Evidence.BRCE` / `Ex4pm.Evidence.Store`, real
  `AshEx4pm.ReceiptStore.Ets`. Assertions are on persisted state
  (record counts, re-read records), returned metadata and real receipt
  recomputation -- no interaction doubles.
  """
  use ExUnit.Case, async: false

  require Ash.Query

  alias AshEx4pm.Changes.ReceiptedAction
  alias AshEx4pm.Errors.Refused
  alias AshEx4pm.Test.ReceiptedResource

  @capable %{capabilities: [:do]}

  defp label, do: "r-" <> Integer.to_string(System.unique_integer([:positive]))

  defp count(label) do
    ReceiptedResource
    |> Ash.Query.filter(label == ^label)
    |> Ash.read!(authorize?: false)
    |> length()
  end

  defp create(params, actor) do
    ReceiptedResource
    |> Ash.Changeset.for_create(:create, params, actor: actor)
    |> Ash.create()
  end

  defp refusal_reason({:error, error}) do
    error
    |> Ash.Error.to_error_class()
    |> Map.fetch!(:errors)
    |> Enum.find_value(fn
      %Refused{reason: reason} -> reason
      _ -> nil
    end)
  end

  test "unauthorized DO is refused and the record is NOT created" do
    l = label()
    result = create(%{label: l}, %{capabilities: []})

    assert {:authority_refused, :authority_denied} = refusal_reason(result)
    assert count(l) == 0

    # no actor => empty authority map => still refused, never ambient authority
    assert {:authority_refused, :authority_denied} = refusal_reason(create(%{label: l}, nil))

    assert count(l) == 0
  end

  test "authorized create persists and carries a receipt binding the real consequence" do
    l = label()
    assert {:ok, record} = create(%{label: l}, @capable)
    assert count(l) == 1

    meta = ReceiptedAction.receipt(record)
    assert meta.replay == :fresh
    assert meta.standing == :alive
    assert meta.operation == :receipted_create
    assert "sha256:" <> _ = meta.authority
    assert meta.subject == ReceiptedAction.subject_hash(ReceiptedResource, nil)

    # the consequence digest is recomputable from the real persisted record
    persisted = Ash.get!(ReceiptedResource, record.id, authorize?: false)
    assert meta.consequence_term.primary_key == %{id: persisted.id}
    assert meta.consequence_term.changed.label == persisted.label
    assert meta.consequence == Ex4pm.Core.Hash.digest(meta.consequence_term)
    assert meta.receipt.artifact_hash == meta.consequence

    # the outcome receipt is real, stored, and chained to its pending receipt
    assert {:ok, %{replay: :match}} = Ex4pm.Evidence.Replay.verify(meta.receipt)
    assert {:ok, stored} = Ex4pm.Evidence.Store.get(meta.receipt_hash)
    assert stored.parent_hash == meta.pending_hash
    assert {:ok, %{phase: :pending}} = Ex4pm.Evidence.Store.get(meta.pending_hash)
  end

  test "same idempotency key + same input replays without a second mutation" do
    l = label()
    key = "req-" <> l
    assert {:ok, first} = create(%{label: l, request_id: key}, @capable)
    assert count(l) == 1

    assert {:ok, second} = create(%{label: l, request_id: key}, @capable)
    assert count(l) == 1
    assert second.id == first.id

    meta = ReceiptedAction.receipt(second)
    assert meta.replay == :known_replay
    assert meta.replay_verification == :match
    assert meta.idempotency_key == key
    assert meta.receipt_hash == ReceiptedAction.receipt(first).receipt_hash
  end

  test "same idempotency key + different input is refused before mutation" do
    l = label()
    other = label()
    key = "req-" <> l
    assert {:ok, _} = create(%{label: l, request_id: key}, @capable)

    assert {:idempotency_conflict, ^key} =
             refusal_reason(create(%{label: other, request_id: key}, @capable))

    assert count(other) == 0
    assert count(l) == 1
  end

  test "operation :local succeeds without an actor and is receipted authority-free" do
    l = label()

    assert {:ok, record} =
             ReceiptedResource
             |> Ash.Changeset.for_create(:local_create, %{label: l})
             |> Ash.create()

    assert count(l) == 1
    meta = ReceiptedAction.receipt(record)
    assert meta.authority == :none
    assert meta.receipt.authority_hash == nil
    assert meta.receipt.operation == :local
    assert meta.standing == :alive
    assert {:ok, %{replay: :match}} = Ex4pm.Evidence.Replay.verify(meta.receipt)
  end

  test "a stale expected subject is refused before mutation; a current one is admitted" do
    l = label()
    assert {:ok, record} = create(%{label: l}, @capable)
    read_subject = ReceiptedAction.subject_hash(ReceiptedResource, record)

    # someone else changes the record after we read it
    moved = label()
    assert {:ok, _} = record |> Ash.Changeset.for_update(:touch, %{label: moved}) |> Ash.update()
    current = Ash.get!(ReceiptedResource, record.id, authorize?: false)
    current_subject = ReceiptedAction.subject_hash(ReceiptedResource, current)
    refute current_subject == read_subject

    wanted = label()

    stale =
      record
      |> Ash.Changeset.for_update(:relabel, %{label: wanted},
        actor: @capable,
        context: %{expected_subject: read_subject}
      )
      |> Ash.update()

    assert {:stale_subject, ^read_subject, ^current_subject} = refusal_reason(stale)
    assert Ash.get!(ReceiptedResource, record.id, authorize?: false).label == moved

    assert {:ok, updated} =
             current
             |> Ash.Changeset.for_update(:relabel, %{label: wanted},
               actor: @capable,
               context: %{expected_subject: current_subject}
             )
             |> Ash.update()

    assert updated.label == wanted
    assert ReceiptedAction.receipt(updated).subject == current_subject
    assert Ash.get!(ReceiptedResource, record.id, authorize?: false).label == wanted
  end
end
