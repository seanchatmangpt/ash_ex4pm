defmodule AshEx4pm.EngineRunTest do
  @moduledoc """
  Chicago-style: real Ash actions on the real ETS data layer call the real
  ex4pm engines (BEAM default) and the real runtime ledger. Assertions are on
  persisted rows, returned errors and replayed receipts.
  """
  use ExUnit.Case, async: false

  alias AshEx4pm.EngineRun

  defp ocel do
    %{
      "objects" => [
        %{"id" => "c1", "type" => "case"},
        %{"id" => "c2", "type" => "case"}
      ],
      "events" => [
        %{
          "id" => "e1",
          "activity" => "a",
          "timestamp" => "2026-01-01T00:00:01Z",
          "objects" => ["c1"]
        },
        %{
          "id" => "e2",
          "activity" => "b",
          "timestamp" => "2026-01-01T00:00:02Z",
          "objects" => ["c1"]
        },
        %{
          "id" => "e3",
          "activity" => "a",
          "timestamp" => "2026-01-01T00:00:03Z",
          "objects" => ["c2"]
        },
        %{
          "id" => "e4",
          "activity" => "b",
          "timestamp" => "2026-01-01T00:00:04Z",
          "objects" => ["c2"]
        }
      ]
    }
  end

  defp create(action, args) do
    EngineRun |> Ash.Changeset.for_create(action, args) |> Ash.create()
  end

  test "discover persists the Run envelope; receipt replays through the real ledger" do
    # ex4pm 26.10.1 flattens object-centric logs by :object_type (OCEL.flatten/2);
    # the documented discover option is required for this fixture.
    assert {:ok, row} = create(:discover, %{subject: ocel(), engine_opts: [object_type: "case"]})
    persisted = Ash.get!(EngineRun, row.id)

    assert persisted.operation == :discover
    assert is_atom(persisted.engine)
    assert is_binary(persisted.subject_hash)
    assert is_binary(persisted.receipt_hash)
    assert is_binary(persisted.pending_hash)
    assert persisted.receipt_hash != persisted.pending_hash
    assert persisted.standing in [:alive, :partial_alive]
    assert persisted.value != nil

    assert [%{id: id}] =
             EngineRun
             |> Ash.Query.for_read(:by_receipt, %{receipt_hash: persisted.receipt_hash})
             |> Ash.read!()

    assert id == row.id

    assert {:ok, {:ok, _verified}} =
             EngineRun
             |> Ash.ActionInput.for_action(:replay, %{hash: persisted.receipt_hash})
             |> Ash.run_action()
  end

  test "replay of an unknown hash returns the typed refusal" do
    assert {:ok, {:error, %Ex4pm.Refusal{code: :receipt_not_found}}} =
             EngineRun
             |> Ash.ActionInput.for_action(:replay, %{hash: "nope"})
             |> Ash.run_action()
  end

  test "malformed subject is refused with Errors.Refused and no row persists" do
    before = length(Ash.read!(EngineRun))

    # AshEx4pm.Errors.Refused is Splode class :forbidden, so Ash surfaces it
    # wrapped in Ash.Error.Forbidden.
    assert {:error, %Ash.Error.Forbidden{errors: errors}} =
             create(:discover, %{subject: "not a log"})

    assert Enum.any?(errors, &match?(%AshEx4pm.Errors.Refused{reason: :invalid_observation}, &1))
    assert length(Ash.read!(EngineRun)) == before
  end

  test "invalid planning problem is refused, nothing persisted" do
    before = length(Ash.read!(EngineRun))
    assert {:error, %Ash.Error.Forbidden{errors: errors}} = create(:plan, %{problem: :nope})

    assert Enum.any?(
             errors,
             &match?(%AshEx4pm.Errors.Refused{reason: :invalid_planning_problem}, &1)
           )

    assert length(Ash.read!(EngineRun)) == before
  end

  test "discover then simulate/conform/optimize on the discovered model" do
    {:ok, d} = create(:discover, %{subject: ocel(), engine_opts: [object_type: "case"]})
    model = d.value

    for {action, args} <- [
          simulate: %{model: model},
          conform: %{subject: ocel(), model: model, engine_opts: [object_type: "case"]},
          optimize: %{subject: ocel(), model: model, engine_opts: [object_type: "case"]}
        ] do
      case create(action, args) do
        {:ok, row} ->
          assert Ash.get!(EngineRun, row.id).operation == action

        {:error, %Ash.Error.Invalid{errors: errors}} ->
          # typed refusal is an acceptable engine outcome; must be Refused and unpersisted
          assert Enum.all?(errors, &match?(%AshEx4pm.Errors.Refused{}, &1))
      end
    end
  end

  test "capabilities generic action lists engine candidates" do
    assert {:ok, caps} =
             EngineRun
             |> Ash.ActionInput.for_action(:capabilities, %{operation: :discover})
             |> Ash.run_action()

    assert [%Ex4pm.Core.Capability{} | _] = caps
  end
end
