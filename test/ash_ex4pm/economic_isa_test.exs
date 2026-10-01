defmodule AshEx4pm.EconomicISATest do
  use ExUnit.Case, async: true

  alias AshEx4pm.EconomicISA

  test "adapter has one canonical provider and no local registry" do
    assert EconomicISA.provider() == Ex4pm.EconomicISA

    assert EconomicISA.required_contract() == [
             registry: 0,
             ranges: 0,
             unknown_opcode: 0,
             escape_opcode: 0,
             lookup: 1,
             category: 1,
             encode: 1,
             encode_extended: 1,
             decode: 1,
             to_event: 2
           ]

    refute function_exported?(EconomicISA, :local_registry, 0)
  end

  test "standing is :alive against the installed canonical ex4pm" do
    assert {:alive, evidence} = EconomicISA.standing()
    assert evidence.provider == Ex4pm.EconomicISA
    assert evidence.contract == EconomicISA.required_contract()
    assert EconomicISA.missing_contract() == []
    assert EconomicISA.available?()
  end

  test "fixed bytes remain exact and agree with the canonical registry" do
    assert {:error, %Ex4pm.Refusal{code: :unknown_economic_activity}} =
             EconomicISA.encode(:unknown)

    assert {:ok, %{name: :unknown, opcode: 0x00}} = EconomicISA.decode(<<0x00>>)
    assert {:ok, <<0x21>>} = EconomicISA.encode(:fill)
    assert {:ok, <<0x41>>} = EconomicISA.encode(:pay)
    assert {:ok, <<0x61>>} = EconomicISA.encode(:deliver)
    assert {:ok, <<0xC0>>} = EconomicISA.encode(:recognize_revenue)
    assert {:ok, <<0xE0>>} = EconomicISA.encode(:authorize)

    assert {:ok, %{name: :pay, opcode: 0x41, category: :payment_settlement}} =
             EconomicISA.decode(<<0x41>>)

    assert {:ok, 0x41} = EconomicISA.lookup_activity(:pay)
    assert {:ok, :pay} = EconomicISA.lookup_byte(0x41)
    assert {:ok, :payment_settlement} = EconomicISA.category(0x41)
    assert {:ok, 0x00} = EconomicISA.unknown()
    assert {:ok, 0xFF} = EconomicISA.escape()

    assert {:ok, registry} = EconomicISA.registry()
    assert Enum.any?(registry, &(&1.name == :pay and &1.opcode == 0x41))
  end

  test "unregistered activity or opcode is a typed error, not a guess" do
    assert {:error, {:unknown_economic_activity, :not_an_activity}} =
             EconomicISA.lookup_activity(:not_an_activity)

    assert {:error, {:unknown_economic_opcode, 0x7F}} = EconomicISA.lookup_byte(0x7F)
    assert {:error, %Ex4pm.Refusal{}} = EconomicISA.encode(:not_an_activity)
  end

  test "projection preserves the canonical frame rather than inventing an Ash meaning" do
    assert {:ok,
            %{
              opcode: 0x41,
              activity: :pay,
              category: :payment_settlement,
              semantic_id: nil,
              frame: <<0x41>>
            }} = EconomicISA.project(:pay)

    semantic_id = "urn:example:economic:custom-action"
    size = byte_size(semantic_id)

    assert {:ok,
            %{
              opcode: 0xFF,
              activity: :extended,
              category: :extended,
              semantic_id: ^semantic_id,
              frame: <<0xFF, ^size::16, ^semantic_id::binary>>
            }} = EconomicISA.project({:extended, semantic_id})
  end

  test "to_event projects a verb into the canonical OCEL event IR" do
    assert {:ok, %Ex4pm.Event{} = event} =
             EconomicISA.to_event(:pay, "payment-1", "2026-09-10T22:00:00Z",
               object_ids: ["inv-1"]
             )

    assert event.id == "payment-1"
    assert event.activity == "pay"
    assert event.object_ids == ["inv-1"]
    assert event.attributes["economic_opcode"] == 0x41
    assert event.attributes["economic_category"] == "payment_settlement"

    assert {:error, %Ex4pm.Refusal{}} = EconomicISA.to_event(:not_an_activity, "x", "t")
  end
end
