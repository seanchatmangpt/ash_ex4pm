defmodule AshEx4pm.EconomicISATest do
  use ExUnit.Case, async: true

  alias AshEx4pm.EconomicISA

  test "adapter has one canonical provider and no local registry" do
    assert EconomicISA.provider() == Ex4pm.EconomicISA

    assert EconomicISA.required_contract() == [
             registry: 0,
             unknown: 0,
             escape: 0,
             lookup_byte: 1,
             lookup_activity: 1,
             category: 1,
             encode: 1,
             decode: 1,
             to_event: 3
           ]

    refute function_exported?(EconomicISA, :local_registry, 0)
  end

  test "standing is explicit at the dependency boundary" do
    case EconomicISA.standing() do
      {:alive, evidence} ->
        assert evidence.provider == Ex4pm.EconomicISA
        assert evidence.contract == EconomicISA.required_contract()
        assert EconomicISA.missing_contract() == []

      {:partial_alive, evidence} ->
        assert evidence.provider == Ex4pm.EconomicISA
        assert evidence.missing != []
        assert evidence.missing == EconomicISA.missing_contract()
    end
  end

  test "older ex4pm releases are refused instead of shadowed by a copied registry" do
    unless EconomicISA.available?() do
      assert {:error, {:economic_isa_unavailable, evidence}} = EconomicISA.encode(:pay)
      assert evidence.provider == Ex4pm.EconomicISA
      assert evidence.missing != []

      assert {:error, {:economic_isa_unavailable, _}} =
               EconomicISA.to_event(:pay, "payment-1", "2026-09-10T22:00:00Z")
    end
  end

  test "when canonical provider is installed fixed bytes remain exact" do
    if EconomicISA.available?() do
      assert {:ok, <<0x00>>} = EconomicISA.encode(:unknown)
      assert {:ok, <<0x21>>} = EconomicISA.encode(:fill)
      assert {:ok, <<0x41>>} = EconomicISA.encode(:pay)
      assert {:ok, <<0x61>>} = EconomicISA.encode(:deliver)
      assert {:ok, <<0xC1>>} = EconomicISA.encode(:recognize_revenue)
      assert {:ok, <<0xE1>>} = EconomicISA.encode(:authorize)

      assert {:ok, {:fixed, 0x41, :pay}} = EconomicISA.decode(<<0x41>>)
      assert {:ok, 0x41} = EconomicISA.lookup_activity(:pay)
      assert {:ok, :pay} = EconomicISA.lookup_byte(0x41)
      assert EconomicISA.category(0x41) == :payment_settlement
    end
  end

  test "projection preserves the canonical frame rather than inventing an Ash meaning" do
    if EconomicISA.available?() do
      assert {:ok,
              %{
                opcode: 0x41,
                activity: :pay,
                category: :payment_settlement,
                semantic_id: nil,
                frame: <<0x41>>
              }} = EconomicISA.project(:pay)

      semantic_id = "urn:example:economic:custom-action"

      assert {:ok,
              %{
                opcode: 0xFF,
                activity: :extended,
                category: :escape,
                semantic_id: ^semantic_id,
                frame: <<0xFF, ^semantic_id::binary>>
              }} = EconomicISA.project({:extended, semantic_id})
    end
  end
end
