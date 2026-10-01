defmodule AshEx4pm.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias AshEx4pm.Capability
  alias AshEx4pm.Capabilities

  test "capability ids are unique" do
    capabilities = Capabilities.all()
    ids = Enum.map(capabilities, & &1.id)

    assert ids != []
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "every registry entry points at a real exported Ash projection" do
    assert Enum.all?(Capabilities.all(), fn capability ->
             Capabilities.available?(capability)
           end)
  end

  test "every capability has local reference/explanation and canonical upstream docs" do
    assert Enum.all?(Capabilities.all(), fn %Capability{docs: docs} ->
             is_binary(docs.index) and
               is_binary(docs.reference) and
               is_binary(docs.explanation) and
               is_binary(docs.upstream)
           end)
  end

  test "ferroplan projections remain CONSTRUCT-only and never advertise DO authority" do
    planning = Capabilities.all(owner: :ferroplan)

    assert planning != []
    assert Enum.all?(planning, &(&1.boundary == :construct))
    assert Enum.all?(planning, &(not &1.do_authority?))
    assert Enum.all?(planning, &(&1.authority == :none))
  end

  test "BrceGate and ReceiptedAction expose different authority boundaries" do
    assert {:ok, admission} = Capabilities.get(:brce_admission)
    assert admission.boundary == :admit
    refute admission.do_authority?

    assert {:ok, receipted_do} = Capabilities.get(:receipted_action)
    assert receipted_do.boundary == :do
    assert receipted_do.do_authority?
    assert receipted_do.authority == :operation_dependent
  end

  test "only the explicit receipted action projection advertises consequential DO" do
    do_capabilities = Capabilities.all(do_authority?: true)

    assert Enum.map(do_capabilities, & &1.id) == [:receipted_action]
  end

  test "filtering is typed by descriptor fields" do
    ids =
      AshEx4pm.capabilities(category: :planning)
      |> Enum.map(& &1.id)

    assert :ferroplan_plan in ids
    assert :ferroplan_session_think in ids
    refute :wasm_statistics in ids
  end

  test "unknown capability does not manufacture availability or standing" do
    assert {:error, :unknown_capability} = AshEx4pm.capability(:does_not_exist)
    refute Capabilities.available?(:does_not_exist)
    assert {:error, :unknown_capability} = AshEx4pm.capability_standing(:does_not_exist)
  end

  test "capabilities without a runtime probe remain PROJECTED rather than ALIVE" do
    assert {:projected, %{capability: :brce_admission, reason: :no_runtime_probe}} =
             AshEx4pm.capability_standing(:brce_admission)
  end
end
