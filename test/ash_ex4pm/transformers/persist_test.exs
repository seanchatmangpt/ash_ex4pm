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
end
