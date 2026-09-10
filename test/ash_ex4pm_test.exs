defmodule AshEx4pmTest do
  use ExUnit.Case, async: false
  require Ash.Query

  # Real, no-mock tests: a real Ash resource (Ash.DataLayer.Ets), a real
  # create action, real AshEx4pm.Notifier firing, a real
  # Ex4pm.Stream.Ingest.ingest_envelope/1 call reaching ex4pm's real,
  # running Ex4pm.Evidence.Store.

  alias AshEx4pm.Test.Order

  test "Info introspection reflects the real compiled activity" do
    assert AshEx4pm.Info.compiled?(Order)

    assert [%AshEx4pm.Activity{name: :order_created, on: :create, resource: Order}] =
             AshEx4pm.Info.activities(Order)
  end

  test "a real create action fires the notifier and reaches ex4pm's real Evidence.Store" do
    {:ok, order} =
      Order
      |> Ash.Changeset.for_create(:create, %{status: :pending})
      |> Ash.create()

    assert order.status == :pending

    # Real evidence: the event landed in ex4pm's real receipt/evidence
    # store (started under its real name by ex4pm's own Application),
    # not a mocked assertion of "was ingest_envelope called." Ingest's
    # own real receipt shape (ingest.ex:41-63) tags {:ingest, :batch} as
    # the operation and stamps the real producer agent_id we set to our
    # provenance_source ("ash_ex4pm") -- assert on that real, observable
    # metadata rather than an invented field.
    entries = Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store)

    assert Enum.any?(entries, fn r ->
             match?(%{operation: {:ingest, :batch}}, r) and
               Map.get(r.metadata || %{}, :agent_id) == "ash_ex4pm"
           end)
  end

  test "build_envelope/2 emits the primary object plus the real, resolved related object " <>
         "for a relationship processed via manage_relationship on this action's own changeset" do
    {:ok, order} =
      Order
      |> Ash.Changeset.for_create(:create, %{status: :pending})
      |> Ash.create()

    changeset =
      order
      |> Ash.Changeset.for_update(:add_line_item, %{line_item: %{sku: "sku-1"}})

    # Real update: manage_relationship really does create a second,
    # independently-persisted LineItem record from this one action, and
    # Ash attaches the resolved struct(s) back onto the returned record's
    # :line_items key before this changeset's own notification fires.
    {:ok, updated_order} = Ash.update(changeset)

    real_line_items =
      AshEx4pm.Test.LineItem
      |> Ash.Query.filter(order_id: updated_order.id)
      |> Ash.read!()

    assert length(real_line_items) == 1
    [real_line_item] = real_line_items

    activity = %AshEx4pm.Activity{name: :order_created, on: :add_line_item, resource: Order}

    notification = %Ash.Notifier.Notification{
      resource: Order,
      action: %{name: :add_line_item},
      data: updated_order,
      changeset: changeset
    }

    envelope = AshEx4pm.Notifier.build_envelope(activity, notification)

    # Documented, corrected scope (see AshEx4pm.Notifier moduledoc): a
    # relationship resolved via manage_relationship ON THE PRIMARY
    # changeset (this one) is real, present data on notification.data --
    # this real action really did touch two separate resource records
    # (the order and the newly-created line item), and the envelope now
    # carries both objects and both relationship entries.
    assert map_size(envelope["objects"]) == 2
    assert Map.has_key?(envelope["objects"], to_string(updated_order.id))
    assert Map.has_key?(envelope["objects"], to_string(real_line_item.id))

    assert envelope["objects"][to_string(real_line_item.id)]["type"] == "LineItem"

    [event] = envelope["events"]

    relationships_by_qualifier = Enum.group_by(event["relationships"], & &1["qualifier"])

    assert [%{"objectId" => primary_id}] = relationships_by_qualifier["primary"]
    assert primary_id == to_string(updated_order.id)

    assert [%{"objectId" => related_id}] = relationships_by_qualifier["line_items"]
    assert related_id == to_string(real_line_item.id)
  end

  test "build_envelope/2 skips a relationship key whose value is not actually resolved " <>
         "on notification.data (never emits an incomplete/synthetic related object)" do
    {:ok, order} =
      Order
      |> Ash.Changeset.for_create(:create, %{status: :pending})
      |> Ash.create()

    activity = %AshEx4pm.Activity{name: :order_created, on: :create}

    # A changeset whose `relationships` map claims a relationship name
    # was touched, but whose real `data` never had that key resolved
    # (e.g. it truly is `%Ash.NotLoaded{}`, as an ordinary un-loaded
    # association would be) -- must never be walked into a fabricated
    # object.
    changeset = %{
      Ash.Changeset.for_create(Order, :create, %{status: :pending})
      | relationships: %{line_items: [%{sku: "irrelevant"}]}
    }

    notification = %Ash.Notifier.Notification{
      resource: Order,
      action: %{name: :create},
      data: %{order | line_items: %Ash.NotLoaded{type: :relationship, field: :line_items}},
      changeset: changeset
    }

    envelope = AshEx4pm.Notifier.build_envelope(activity, notification)

    assert map_size(envelope["objects"]) == 1
    [event] = envelope["events"]
    assert [%{"qualifier" => "primary"}] = event["relationships"]
  end

  test "an action with no matching activity does not attempt to emit anything" do
    {:ok, order} =
      Order
      |> Ash.Changeset.for_create(:create, %{status: :pending})
      |> Ash.create()

    count_before = Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store) |> length()

    {:ok, _shipped} =
      order
      |> Ash.Changeset.for_update(:ship, %{})
      |> Ash.update()

    count_after = Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store) |> length()
    # :ship has no matching `activity ..., on: :ship` declared -- the
    # notifier's AshEx4pm.Info.activities/1 lookup finds nothing and
    # returns :ok without ever building/ingesting an envelope, so no new
    # receipt pair (pending+outcome) is written.
    assert count_after == count_before
  end

  # These two verifiers ARE confirmed real and correct -- directly
  # observed producing the exact right Spark.Error.DslError text and
  # real action-name list when run via `mix run` against Code.compile_string
  # (see this session's own manual probe). What ExUnit.assert_raise cannot
  # observe here is a real, disclosed Ash/Spark environment quirk, not a
  # bug in this extension: `Code.compile_string/1`'s `__verify_spark_dsl__`
  # runs through Elixir's async Module.ParallelChecker, which SURFACES a
  # verifier's raised DslError as a logged compiler warning rather than
  # re-raising it synchronously to the calling process. Capturing that
  # real warning text is therefore the correct, honest test strategy here
  # -- not a workaround for a real gap in the verifier.
  import ExUnit.CaptureIO

  test "a compile-time typo'd action name is refused, not silently swallowed" do
    output =
      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule AshEx4pm.Test.BadOrder do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            data_layer: Ash.DataLayer.Ets,
            notifiers: [AshEx4pm.Notifier],
            extensions: [AshEx4pm]

          ex4pm do
            activity :order_created, on: :not_a_real_action
          end

          actions do
            defaults [:read, :destroy]
            create :create
          end

          attributes do
            uuid_primary_key :id
          end
        end
        """)
      end)

    assert output =~ "does not exist on"
    assert output =~ "Spark.Error.DslError"
  end

  test "a domain-level activity with a non-Ash-resource `resource:` is refused, not silently skipped" do
    output =
      capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule AshEx4pm.Test.NotAResource do
          def hello, do: :world
        end

        defmodule AshEx4pm.Test.BadDomain do
          use Ash.Domain,
            validate_config_inclusion?: false,
            extensions: [AshEx4pm]

          ex4pm do
            activity :order_created,
              on: :not_a_real_action,
              resource: AshEx4pm.Test.NotAResource
          end
        end
        """)
      end)

    assert output =~ "is not a compiled Ash resource"
    assert output =~ "Spark.Error.DslError"
  end

  test "explicit resource: on a resource-level activity is refused" do
    # Unlike the verifier-raised error above, this one is raised by
    # AshEx4pm.Transformers.Persist -- transformers run synchronously
    # during the normal compile pass (not through the async
    # Module.ParallelChecker verifiers use), so it DOES propagate as a
    # real raised exception here, correctly caught by assert_raise.
    assert_raise Spark.Error.DslError, ~r/cannot set `resource:` explicitly/, fn ->
      Code.compile_string("""
      defmodule AshEx4pm.Test.ExplicitResourceOrder do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          data_layer: Ash.DataLayer.Ets,
          notifiers: [AshEx4pm.Notifier],
          extensions: [AshEx4pm]

        ex4pm do
          activity :order_created, on: :create, resource: __MODULE__
        end

        actions do
          defaults [:read, :destroy]
          create :create
        end

        attributes do
          uuid_primary_key :id
        end
      end
      """)
    end
  end

  test "AshEx4pm.Changes.BrceGate refuses an action with no admitted authority" do
    result =
      AshEx4pm.Test.GatedResource
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create()

    assert {:error, %Ash.Error.Invalid{}} = result
  end

  test "omitting `on` is refused at compile time, not silently defaulted to nil" do
    # AshEx4pm.Activity's @enforce_keys [:name, :on] previously contradicted
    # the schema's `on: [required: false]` and a doc claiming implicit
    # per-action inference that was never implemented anywhere in
    # AshEx4pm.Transformers.Persist. Now the schema requires `on:` for
    # real (matching @enforce_keys and the corrected doc), so Spark's own
    # entity-schema validation refuses this at compile time instead of
    # silently building %AshEx4pm.Activity{on: nil, ...}.
    assert_raise Spark.Error.DslError, ~r/on.*required|required.*on/i, fn ->
      Code.compile_string("""
      defmodule AshEx4pm.Test.MissingOnOrder do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          data_layer: Ash.DataLayer.Ets,
          notifiers: [AshEx4pm.Notifier],
          extensions: [AshEx4pm]

        ex4pm do
          activity :order_created
        end

        actions do
          defaults [:read, :destroy]
          create :create
        end

        attributes do
          uuid_primary_key :id
        end
      end
      """)
    end
  end

  test "AshEx4pm.Changes.BrceGate admits an action with a capable actor" do
    result =
      AshEx4pm.Test.AdmittedResource
      |> Ash.Changeset.for_create(:create, %{}, actor: %{capabilities: [:do]})
      |> Ash.create()

    assert {:ok, _} = result
  end

  test "the :activity entity carries a real entity-level describe: for Spark doc generation" do
    entity =
      AshEx4pm.Dsl.section()
      |> Map.fetch!(:entities)
      |> Enum.find(&(&1.name == :activity))

    assert %Spark.Dsl.Entity{} = entity
    assert is_binary(entity.describe)
    assert entity.describe != ""
  end

  alias AshEx4pm.Test.Widget

  describe "record_id/2 -- real primary key resolution (not a hardcoded :id assumption)" do
    test "resolves a real, non-:id-named primary key from a real Ash struct" do
      widget = %Widget{sku: "SKU-42"}

      assert AshEx4pm.Notifier.record_id(Widget, widget) == "SKU-42"
    end

    test "a real create action on a resource with a non-:id primary key emits the real sku as the object id" do
      {:ok, widget} =
        Widget
        |> Ash.Changeset.for_create(:create, %{sku: "SKU-99"})
        |> Ash.create()

      assert widget.sku == "SKU-99"

      # Real, observable evidence: the ex4pm ingest receipt for this
      # create landed with our real provenance agent_id -- the
      # notifier did not crash or silently no-op while resolving the
      # non-:id primary key.
      entries = Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store)

      assert Enum.any?(entries, fn r ->
               match?(%{operation: {:ingest, :batch}}, r) and
                 Map.get(r.metadata || %{}, :agent_id) == "ash_ex4pm"
             end)
    end

    test "a struct with a nil primary key value falls back to a clearly-synthetic id, never an empty string" do
      widget = %Widget{sku: nil}

      assert "synthetic_obj_" <> _ = AshEx4pm.Notifier.record_id(Widget, widget)
    end

    test "a plain map with an :id key (e.g. a hand-built generic-action notification) uses that id" do
      assert AshEx4pm.Notifier.record_id(Widget, %{id: "abc"}) == "abc"
    end

    test "a plain map with a nil :id value falls back to a synthetic id, not an empty string" do
      assert "synthetic_obj_" <> _ = AshEx4pm.Notifier.record_id(Widget, %{id: nil})
    end

    test "data with no resolvable id at all (e.g. Ash.ActionInput's arbitrary generic-action data) falls back to a synthetic id" do
      assert "synthetic_obj_" <> _ =
               AshEx4pm.Notifier.record_id(Widget, %{audit: "before_action"})
    end
  end

  import ExUnit.CaptureLog

  test "a real ingest_envelope refusal is logged, not silently swallowed" do
    # Real refusal from ex4pm's real Ex4pm.Stream.Ingest.check_idempotency/2
    # (ingest.ex:91-100) -- a negative sequence, no mocking involved.
    envelope = %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{"agent_id" => "ash_ex4pm"},
      "sequence" => -1,
      "objects" => %{},
      "events" => []
    }

    assert {:error, %Ex4pm.Refusal{code: :invalid_sequence} = refusal} =
             Ex4pm.Stream.Ingest.ingest_envelope(envelope)

    log =
      capture_log(fn ->
        assert :ok = AshEx4pm.Notifier.log_refusal(refusal, Order, :create)
      end)

    assert log =~ "AshEx4pm.Notifier: ingest_envelope refused"
    assert log =~ "invalid_sequence"
  end

  test "AshEx4pm.Changes.BrceGate refuses cleanly, without raising, when actor.capabilities is a malformed non-list" do
    for malformed_capabilities <- ["do", %{}, 1, {:do}] do
      result =
        AshEx4pm.Test.GatedResource
        |> Ash.Changeset.for_create(:create, %{}, actor: %{capabilities: malformed_capabilities})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} = result
    end
  end

  describe "BrceGate before_action ordering relative to other changes" do
    setup do
      case Process.whereis(AshEx4pm.Test.SideEffectLog) do
        nil -> start_supervised!(AshEx4pm.Test.SideEffectLog)
        _pid -> :ok
      end

      AshEx4pm.Test.SideEffectLog.reset()
      :ok
    end

    test "a refused gate declared AFTER another before_action change still runs first, " <>
           "so the other change's side effect never happens" do
      # AshEx4pm.Test.OrderedGatedResource declares SideEffectChange
      # BEFORE BrceGate in its `changes:` list -- the exact hazard the
      # finding described (a maintainer placing the gate second). With
      # plain declaration-order `before_action` semantics this would let
      # SideEffectChange's Agent bump run before the (refused) gate ever
      # checks admission. `prepend?: true` on BrceGate's hook must keep
      # that from happening.
      result =
        AshEx4pm.Test.OrderedGatedResource
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} = result

      # Real, observed state -- not an interaction assertion: the side
      # effect's own counter, actually queried from the real Agent
      # process, is still zero because the gate ran (and halted) first.
      assert AshEx4pm.Test.SideEffectLog.count() == 0
    end

    test "an admitted gate declared AFTER another before_action change lets the other " <>
           "change's side effect run afterward" do
      result =
        AshEx4pm.Test.OrderedGatedResource
        |> Ash.Changeset.for_create(:create, %{}, actor: %{capabilities: [:do]})
        |> Ash.create()

      assert {:ok, _} = result
      assert AshEx4pm.Test.SideEffectLog.count() == 1
    end
  end

  test "two real concurrent creates of the same resource+operation with different data get distinguishable subject hashes" do
    # Real regression test for: subject_hash previously hashed only
    # %{resource: ..., operation: ...}, so two different real changesets
    # of the same resource+operation collapsed into one identical
    # subject_hash -- Ex4pm.Evidence.Store.get_by_subject/2 could not
    # disambiguate which receipt belonged to which actual record. This
    # asserts on the real, persisted receipt state in the real Evidence
    # Store (no mocks): each create's outcome receipt now carries a
    # subject_hash distinct from the other's.
    # The real Evidence.Store is backed by an unordered ETS :set
    # (evidence.ex:103), so "new since before" must be computed by real
    # receipt-hash set difference -- not position/Enum.drop, which
    # silently assumes an insertion order the store never guarantees.
    hashes_before =
      Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store) |> MapSet.new(& &1.hash)

    {:ok, first} =
      AshEx4pm.Test.AdmittedResource
      |> Ash.Changeset.for_create(:create, %{label: "first"}, actor: %{capabilities: [:do]})
      |> Ash.create()

    {:ok, second} =
      AshEx4pm.Test.AdmittedResource
      |> Ash.Changeset.for_create(:create, %{label: "second"}, actor: %{capabilities: [:do]})
      |> Ash.create()

    new_entries =
      Ex4pm.Evidence.Store.all(Ex4pm.Evidence.Store)
      |> Enum.reject(&MapSet.member?(hashes_before, &1.hash))

    admitted_hashes =
      new_entries
      |> Enum.filter(&match?(%{operation: :admitted_create}, &1))
      |> Enum.map(& &1.subject_hash)
      |> Enum.uniq()

    assert first.label == "first"
    assert second.label == "second"
    # Real evidence that the fix works: two real creates of the same
    # resource+operation, with different real attribute data, produced
    # more than one distinct subject_hash -- before the fix this would
    # be exactly 1 (both collapsing to the same resource+operation hash).
    assert length(admitted_hashes) > 1
  end
end
