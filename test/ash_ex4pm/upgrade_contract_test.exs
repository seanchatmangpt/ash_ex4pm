defmodule AshEx4pm.UpgradeContractTest do
  # Pins the ex4pm v26.9.30 behaviours ash_ex4pm depends on, against the real
  # dependency (no doubles). Shares the global Evidence.Store, so not async.
  use ExUnit.Case, async: false

  alias AshEx4pm.Test.Order

  test "ex4pm 26.9.30 no longer forward-declares ferroplan routes on Beam4pm" do
    assert {:error, %Ex4pm.Refusal{code: :beam4pm_unsupported_operation}} =
             Ex4pm.Engine.Beam4pm.execute(:ferroplan_fond_policy, %{}, [])

    refute function_exported?(AshEx4pm.Ferroplan, :ferroplan_fond_policy, 2)
  end

  test "re-ingesting a byte-identical envelope is ignored with the original receipt hash" do
    {:ok, order} =
      Order |> Ash.Changeset.for_create(:create, %{status: :pending}) |> Ash.create()

    activity = %AshEx4pm.Activity{name: :upgrade_dedup_probe, on: :create, resource: Order}

    notification = %Ash.Notifier.Notification{
      resource: Order,
      action: %{name: :create, type: :create},
      data: order,
      changeset: nil
    }

    envelope = AshEx4pm.Notifier.build_envelope(activity, notification)

    assert {:ok, %{status: :ingested}} = Ex4pm.Stream.Ingest.ingest_envelope(envelope)

    assert {:ok, %{status: :duplicate_ignored, original_receipt_hash: hash}} =
             Ex4pm.Stream.Ingest.ingest_envelope(envelope)

    assert is_binary(hash)
  end

  test "a negative sequence is still refused :invalid_sequence" do
    envelope = %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{"agent_id" => "ash_ex4pm", "runtime" => "beam"},
      "sequence" => -1,
      "objects" => %{},
      "events" => []
    }

    assert {:error, %Ex4pm.Refusal{code: :invalid_sequence}} =
             Ex4pm.Stream.Ingest.ingest_envelope(envelope)
  end
end
