defmodule AshEx4pm.Transformers.PersistTest do
  @moduledoc """
  Chicago-style (state-based, real collaborator) test for
  `AshEx4pm.Transformers.Persist.after?/1`.

  Proves the fix for the adversarial review finding: `transform/1` has no
  real data dependency on primary-key/relationship/attribute info, so
  `after?/1` must run after every other transformer unconditionally
  (matching the real `AshAi.Transformers.ResourceTools` precedent), not a
  hand-picked five-clause list. No mocks: calls the real `after?/1`
  function directly against real Ash core transformer modules and an
  arbitrary unrelated module.
  """
  use ExUnit.Case, async: true

  alias AshEx4pm.Transformers.Persist

  test "after?/1 returns true for the five previously hard-coded core transformers" do
    assert Persist.after?(Ash.Resource.Transformers.CachePrimaryKey)
    assert Persist.after?(Ash.Resource.Transformers.DefaultPrimaryKey)
    assert Persist.after?(Ash.Resource.Transformers.SetRelationshipInformation)
    assert Persist.after?(Ash.Resource.Transformers.BelongsToAttribute)
    assert Persist.after?(Ash.Resource.Transformers.BelongsToSourceAttribute)
  end

  test "after?/1 also returns true for core transformers NOT in the old five-clause list" do
    assert Persist.after?(Ash.Resource.Transformers.AttributesByName)
    assert Persist.after?(Ash.Resource.Transformers.CacheRelationships)
    assert Persist.after?(Ash.Resource.Transformers.ValidationsAndChangesForType)
  end

  test "after?/1 returns true for any arbitrary module, unconditionally" do
    assert Persist.after?(SomeUnrelatedRandomModule)
    assert Persist.after?(__MODULE__)
  end

  describe "automatic simple_notifiers registration" do
    # Real, no-mock proof (adversarial review finding, notifier.ex:10): a
    # resource that declares `extensions: [AshEx4pm]` WITHOUT a manual
    # `notifiers: [AshEx4pm.Notifier]` entry still has
    # `AshEx4pm.Notifier` show up in the real
    # `Ash.Resource.Info.notifiers/1` list, because `transform/1` now
    # persists it into the same `:simple_notifiers` key
    # `use Ash.Resource, simple_notifiers: [...]` seeds.

    test "AshEx4pm.Notifier is present via Ash.Resource.Info.notifiers/1 with no manual notifiers: entry" do
      assert AshEx4pm.Notifier in Ash.Resource.Info.notifiers(AshEx4pm.Test.Gadget)
    end

    test "a manually-declared notifiers: [AshEx4pm.Notifier] resource is not duplicated" do
      notifiers = Ash.Resource.Info.notifiers(AshEx4pm.Test.Order)

      assert Enum.count(notifiers, &(&1 == AshEx4pm.Notifier)) == 1
    end

    test "a real create action on the auto-registered resource fires the notifier and reaches ex4pm's real Evidence.Store" do
      {:ok, gadget} =
        AshEx4pm.Test.Gadget
        |> Ash.Changeset.for_create(:create, %{sku: "gadget-sku-1"})
        |> Ash.create()

      assert gadget.sku == "gadget-sku-1"

      entries = Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store)

      assert Enum.any?(entries, fn r ->
               match?(%{operation: {:ingest, :batch}}, r) and
                 Map.get(r.metadata || %{}, :agent_id) == "ash_ex4pm"
             end)
    end
  end
end
