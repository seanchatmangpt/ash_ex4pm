defmodule AshEx4pm.UpgradeContractTest do
  # Pins the ex4pm v26.10.1 behaviours ash_ex4pm depends on, against the real
  # dependency (no doubles). Shares the global Evidence.Store, so not async.
  use ExUnit.Case, async: false

  alias AshEx4pm.Test.Order

  test "ex4pm 26.10.1 has removed the Beam4pm engine and ash_ex4pm has no generated delegate" do
    refute Code.ensure_loaded?(Ex4pm.Engine.Beam4pm)
    refute Code.ensure_loaded?(AshEx4pm.Ferroplan)
  end

  test "release 26.10.1 contract: @version, exact ex4pm pin, lock checksum, changelog entry" do
    mix_exs = File.read!("mix.exs")

    assert mix_exs =~ ~s(@version "26.10.8")
    assert mix_exs =~ ~s({:ex4pm, "== 26.10.1"})

    lock = File.read!("mix.lock")

    assert lock =~
             ~s("ex4pm": {:hex, :ex4pm, "26.10.1", "269ee75f8226945538ff0627fe5267210a08e951fa6289991e1d3d0bb110782c")

    assert File.read!("CHANGELOG.md") =~ "## [26.10.1] - 2026-10-01"
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
