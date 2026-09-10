defmodule AshEx4pm.Notifier do
  @moduledoc """
  Real `Ash.Notifier` that emits an OCEL 2.0 event for every Ash action
  matching a compiled `activity` declaration, via
  `Ex4pm.Stream.Ingest.ingest_envelope/1` -- the function that actually
  exists and works, not `Ex4pm.Stream.Ingest.ingest_batch/1` (the dead
  call `Ex4pmDomain.Notifier.OcelNotifier` makes, confirmed nonexistent,
  `~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md` BLOCKER 1).

  Registered automatically for any resource using `extensions: [AshEx4pm]` --
  `AshEx4pm.Transformers.Persist.transform/1` persists this module into the
  resource's `:simple_notifiers` key (the same persisted key
  `use Ash.Resource, simple_notifiers: [...]` seeds,
  `deps/ash/lib/ash/resource.ex:34,132`), which
  `Ash.Resource.Info.notifiers/1` reads alongside the explicit `notifiers:`
  list (`deps/ash/lib/ash/resource/info.ex:278-281`). No manual `notifiers:`
  declaration is required:

      use Ash.Resource,
        extensions: [AshEx4pm]

  A resource may still list `AshEx4pm.Notifier` explicitly in `notifiers:` --
  the transformer de-duplicates against whatever is already persisted, so
  doing so is harmless, just redundant.

  ## Envelope shape

  Built directly in the real, confirmed wire shape
  `Ex4pm.Stream.Ingest.ingest_envelope/2` expects (a plain map with
  string keys `"schema"`/`"producer"`/`"sequence"`/`"objects"`/`"events"`,
  verified against `~/ex4pm/test/ingest_test.exs:14-46` and
  `~/ex4pm/lib/ex4pm/stream/ingest.ex:19-20`'s real
  `OCEL.validate_envelope/1` call) -- never
  `Ex4pm.OCEL.normalize/1`'s `%Ex4pm.EventLog{}` output, which is a
  DIFFERENT real path (batch/offline normalization for
  discover/conform), not what the real-time ingest function consumes.

  ## Scope: what this notifier can and cannot see

  There are two genuinely distinct limitations here, not one -- they
  used to be bundled under a single "single-object events only" claim,
  which overstated the second one.

  1. **Permanent: no cross-resource/cross-notification correlation.**
     `Ash.Notifier.notify/1`'s callback signature really is
     one-notification-at-a-time, with no accumulator parameter and no
     visibility into sibling `resource_notifications` fired by the same
     top-level action for a *different* resource (e.g. an action that
     itself calls `Ash.create/1` on another resource, or a
     `manage_relationship` whose related resource has its own
     `notifiers:` list and therefore gets its own independent
     notification). A single `Ash.Notifier.Notification` here
     corresponds to exactly one resource/changeset/action firing, and
     `notify/1` cannot reach across to correlate it with any other
     notification from the same transaction. This is a real,
     permanent constraint of the callback shape, not something
     `build_envelope/2` can work around.

  2. **Fixed below, was not actually blocked: relationships resolved by
     `manage_relationship` ON THE PRIMARY CHANGESET.** `build_envelope/2`
     now walks every relationship name present as a key in
     `notification.changeset.relationships` (used only to know *which*
     relationships this action's `manage_relationship` calls touched --
     never for its raw pre-commit values) and reads the real, resolved,
     post-commit related record(s) directly off `notification.data`.
     This works because Ash's own `manage_relationships/4`
     (`deps/ash/lib/ash/actions/managed_relationships.ex:710`) does
     `Map.put(record, relationship.name, new_value)` with the actually
     persisted related struct(s) before that record ever becomes
     `notification.data` (`deps/ash/lib/ash/actions/helpers.ex:435`'s
     `notify/3` calls `resource_notification/3` with that same
     post-managed-relationships record, and `resource_notification/3`
     sets `data: result` directly from it) -- so the data was already
     there on the one notification this callback receives; it was
     simply never read. A relationship name whose resolved value comes
     back `%Ash.NotLoaded{}` (not actually set on this particular
     record) is skipped rather than emitted as an incomplete object.

  If an activity's real cross-resource correlation need is limitation 1
  above (a sibling resource's own independent notification, not a
  `manage_relationship` on THIS action's own changeset), this notifier
  is still the wrong mechanism for it. Add a resource-level
  `Ash.Resource.Change` that builds and returns a manual
  `%Ash.Notifier.Notification{}` carrying the full object/relationship
  set for that action (see `action_input.ex`'s manual-notification
  pattern) -- and note that such a change must itself read the resolved
  data the same way `build_envelope/2` does below (from the post-action
  record's relationship keys), not from a source that doesn't exist.

  ## Declared O2O facts (a third, opt-in mechanism)

  A resource author CAN additionally declare real OCEL 2.0 O2O (object-to-object)
  facts for an activity via nested `object_relationship` entities (see
  `AshEx4pm.ObjectRelationship`) -- e.g.
  `object_relationship :customer, "placed_by"`
  inside `activity :order_placed, on: :create do ... end`. Each declared
  relationship is resolved from the notification's own *already-loaded*
  target record (`Ash.Resource.Info.relationship/2` +
  `Map.get(notification.data, relationship_name)`) and emitted into the
  envelope's real `"object_relationships"` key (`Ex4pm.OCEL`'s genuinely
  accepted `source_id`/`target_id`/`qualifier` shape -- confirmed against
  `~/ex4pm/lib/ex4pm/ocel.ex`'s `normalize_object_relationships/1`). If
  the target record was not loaded onto `notification.data` (e.g. the
  action never selected/loaded that relationship), the fact is skipped
  and logged rather than emitted with a fabricated or nil target id --
  see `resolve_object_relationships/2`.

  This still does not recover unresolved `manage_relationship/3` input,
  and still does not attempt many-object events for actions that touch
  several independently-notified resources at once. For that genuinely
  different case, add a resource-level `Ash.Resource.Change` that builds
  and returns a manual `%Ash.Notifier.Notification{}` carrying the full
  object/relationship set for that action (see `action_input.ex`'s
  manual-notification pattern) rather than relying on this notifier's
  one-primary-object-per-action default.
  """
  use Ash.Notifier
  require Logger

  @impl Ash.Notifier
  def notify(%Ash.Notifier.Notification{} = notification) do
    resource = notification.resource
    action_name = notification.action.name

    matching =
      resource
      |> AshEx4pm.Info.activities()
      |> Enum.find(&(&1.on == action_name))

    case matching do
      nil ->
        :ok

      activity ->
        envelope = build_envelope(activity, notification)

        case Ex4pm.Stream.Ingest.ingest_envelope(envelope) do
          {:ok, _result} -> :ok
          # A refused/failed ingest never blocks the Ash action itself --
          # the action already committed by the time notifiers run
          # (Ash.Notifier fires post-commit). Real, disclosed limitation:
          # this is fire-and-forget, matching Ex4pmDomain.Notifier.OcelNotifier's
          # own real semantics (also post-commit, also non-blocking) --
          # a real BRCE-gated PRE-commit path is AshEx4pm.Changes.BrceGate,
          # a separate, deliberate mechanism (see its own moduledoc). The
          # refusal itself is never silently discarded, though: it can be
          # caused by a bug in build_envelope/2's own output (not just a
          # transient downstream condition), so it is always logged.
          {:error, refusal} -> log_refusal(refusal, resource, action_name)
        end
    end
  end

  def notify(_), do: :ok

  # Public (doc-hidden) so it is directly testable against a real
  # `Ex4pm.Refusal` produced by `Ex4pm.Stream.Ingest.ingest_envelope/1`,
  # without mocking either ex4pm or Logger.
  @doc false
  def log_refusal(refusal, resource, action_name) do
    Logger.warning(
      "AshEx4pm.Notifier: ingest_envelope refused: #{inspect(refusal)}",
      resource: resource,
      action: action_name
    )

    :ok
  end

  # Public (but @doc false) so tests can inspect the real envelope shape
  # directly. Emits the primary object/relationship always, plus one
  # object/relationship pair per real, resolved related record reachable
  # from `manage_relationship` calls on THIS action's own changeset --
  # see the moduledoc's "Scope" section for exactly which relationships
  # that is (and, just as importantly, which it permanently is not).
  @doc false
  def build_envelope(activity, notification) do
    provenance_source =
      AshEx4pm.Info.compiled(notification.resource)[:provenance_source] || :ash_ex4pm

    record_id = record_id(notification.resource, notification.data)
    timestamp = DateTime.utc_now()

    primary_object = object_map(activity, notification.resource, record_id, notification.data)

    primary_relationship = %{
      "objectId" => record_id,
      "qualifier" => to_string(activity.qualifier || "primary")
    }

    {related_objects, related_relationships} = managed_relationship_objects(notification)

    objects =
      [primary_object | related_objects]
      |> Map.new(&{&1["id"], &1})

    object_relationships =
      resolve_object_relationships(activity, notification, record_id)

    %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => to_string(provenance_source),
        "runtime" => "beam",
        "resource" => inspect(notification.resource)
      },
      # Ex4pm.OCEL.validate_envelope/1 (`~/ex4pm/lib/ex4pm/ocel.ex:385`)
      # requires this field to be a real integer -- a UUID/hash string is
      # rejected outright, so it cannot carry the durable-identity fix
      # below. System.os_time(:nanosecond) is still real-BEAM-process-local
      # in the sense that it is not a coordinated distributed sequence, but
      # unlike System.unique_integer/1 it is wall-clock derived: it does
      # NOT reset to 1 on VM restart, and at nanosecond resolution two
      # nodes producing the "same" sequence value requires them to emit
      # within the same nanosecond -- a real, disclosed, and far weaker
      # collision surface than a counter that is guaranteed to start over
      # at 1 on every boot.
      "sequence" => System.os_time(:nanosecond),
      "objects" => objects,
      "object_relationships" => object_relationships,
      "events" => [
        %{
          "id" => event_id(notification.resource, activity, record_id, timestamp),
          "activity" => to_string(activity.name),
          "timestamp" => DateTime.to_iso8601(timestamp),
          "relationships" => [primary_relationship | related_relationships],
          "attributes" => event_attributes(activity, notification)
        }
      ]
    }
  end

  # Builds the OCEL object map for the acting resource. When the firing
  # `activity` declares an `object_type:` that resolves to a real,
  # compiled `AshEx4pm.ObjectType` (AshEx4pm.Transformers.Persist already
  # refused to compile any activity whose `object_type:` does not
  # resolve), the declared type's own `name` is used as the OCEL "type"
  # instead of `resource_type_name/1`'s module-name derivation, and the
  # object's declared attributes are populated from the resource's real,
  # persisted data -- never invented, never silently defaulted for a
  # missing/nil field. `Ex4pm.OCEL.validate_envelope/1`
  # (`~/ex4pm/lib/ex4pm/ocel.ex:139-153`) accepts any non-id/non-type key
  # on an object map as an attribute (`drop_known_object_keys/1`), and
  # also accepts an explicit nested `"attributes"` map
  # (`~/ex4pm/lib/ex4pm/ocel.ex:494`) -- this uses the explicit nested
  # form, confirmed accepted by reading the real downstream validator,
  # not assumed.
  #
  # With no `object_type:` declared (the real, disclosed back-compat
  # path), this falls back to the historical `resource_type_name/1`
  # behavior with no attributes -- unchanged from before this fix, so
  # existing resources with no `object_type` declaration keep emitting
  # exactly the same envelope shape they always did.
  @doc false
  def object_map(activity, resource, record_id, data) do
    case declared_object_type(activity, resource) do
      nil ->
        %{"id" => record_id, "type" => resource_type_name(resource)}

      %AshEx4pm.ObjectType{} = object_type ->
        base = %{"id" => record_id, "type" => to_string(object_type.name)}
        attrs = declared_attributes(object_type, data)

        if map_size(attrs) == 0, do: base, else: Map.put(base, "attributes", attrs)
    end
  end

  defp declared_object_type(%{object_type: nil}, _resource), do: nil

  defp declared_object_type(%{object_type: name}, resource) do
    resource
    |> AshEx4pm.Info.compiled()
    |> case do
      nil -> nil
      compiled -> get_in(compiled, [:object_types, name])
    end
  end

  # Only declared attribute names that are actually present (a real Ash
  # struct field, or a plain map key) AND non-nil are included -- a
  # missing/nil field is omitted rather than emitted as a fabricated
  # `nil`/empty value, the same "present and non-nil" rule `fetch_present/2`
  # (below) applies everywhere else this notifier reads a field off real
  # notification data.
  defp declared_attributes(%AshEx4pm.ObjectType{attributes: attributes}, data)
       when is_map(data) do
    Enum.reduce(attributes, %{}, fn {name, _type}, acc ->
      case fetch_present(data, name) do
        {:ok, value} -> Map.put(acc, to_string(name), value)
        :error -> acc
      end
    end)
  end

  defp declared_attributes(_object_type, _data), do: %{}

  # Populates the emitted event's real OCEL "attributes" map. Composes two
  # mechanisms:
  #
  #   1. `declared_event_attributes/2` -- the activity's compiled
  #      `attributes: [name: type, ...]` schema (AshEx4pm.Transformers.Persist
  #      already refused any unsupported type at compile time -- see
  #      @allowed_attribute_types there), coercing each present value to its
  #      declared type. A declared attribute whose value is nil or absent from
  #      `data`, or whose real value fails coercion to its declared type, is
  #      left out (never silently emitted as a wrong-typed or fabricated
  #      value) and logged so the gap is visible rather than silently
  #      swallowed. This is the only DEFAULT/primary mechanism -- unchanged
  #      behavior for every existing activity.
  #
  #   2. `attribute_change_attributes/2` -- opt-in (`track_attribute_changes?:
  #      true`), `:update`-only, public-attributes-only automatic capture of
  #      whatever raw attribute changes landed on `notification.changeset`
  #      that the activity author did NOT explicitly declare. This closes the
  #      OCEL 2.0 attribute value-time-log gap for undeclared attributes
  #      without leaking private/internal fields.
  #
  # `declared` wins on key collision -- the typed/coerced/public-checked path
  # always takes precedence over the raw automatic-diff path, so merge order
  # is the single source of truth for precedence and no separate
  # declared-name exclusion bookkeeping is needed in
  # `attribute_change_attributes/2`.
  @doc false
  def event_attributes(
        %{attributes: attributes} = activity,
        %Ash.Notifier.Notification{} = notification
      )
      when is_list(attributes) do
    declared = declared_event_attributes(attributes, notification.data)
    history = attribute_change_attributes(activity, notification)
    Map.merge(history, declared)
  end

  def event_attributes(_activity, _notification), do: %{}

  defp declared_event_attributes(attributes, data) do
    attributes
    |> Enum.reduce(%{}, fn {name, type}, acc ->
      case fetch_field(data, name) do
        {:ok, raw_value} ->
          case coerce_attribute(raw_value, type) do
            {:ok, coerced} ->
              Map.put(acc, to_string(name), coerced)

            :error ->
              Logger.warning(
                "AshEx4pm.Notifier: attribute #{inspect(name)} value #{inspect(raw_value)} " <>
                  "does not match declared type #{inspect(type)}; omitting from emitted event"
              )

              acc
          end

        :error ->
          acc
      end
    end)
  end

  # Opt-in (`track_attribute_changes?: true`), `:update`-only, public-only
  # automatic capture of raw attribute changes off `notification.changeset`.
  # A `:create` has no prior value to log a change against, so this never
  # fires there. Filters to `Ash.Resource.Info.public_attributes/1` --
  # a real security floor, never optional -- so private/internal attributes
  # never leak into the emitted OCEL envelope.
  defp attribute_change_attributes(%{track_attribute_changes?: true}, %Ash.Notifier.Notification{
         action: %{type: :update},
         changeset: %Ash.Changeset{attributes: changed},
         resource: resource
       })
       when is_map(changed) do
    public_names = public_attribute_names(resource)

    changed
    |> Enum.filter(fn {name, _value} -> MapSet.member?(public_names, name) end)
    |> Map.new(fn {name, value} -> {to_string(name), value} end)
  end

  defp attribute_change_attributes(_activity, _notification), do: %{}

  defp public_attribute_names(resource) do
    resource |> Ash.Resource.Info.public_attributes() |> MapSet.new(& &1.name)
  rescue
    _ -> MapSet.new()
  end

  # Walks relationship names that were actually touched by
  # `manage_relationship` on THIS notification's own changeset --
  # `changeset.relationships`'s keys are used only to know *which*
  # relationships were involved, never for that map's raw pre-commit
  # values -- and reads the real, resolved, post-commit related
  # record(s) off `notification.data` (the same record Ash's own
  # `Ash.Actions.ManagedRelationships.manage_relationships/4` already
  # attached them to via `Map.put(record, relationship.name,
  # new_value)` before it became `notification.data`; see the
  # moduledoc's "Scope" section for the exact source references). A
  # relationship whose value on this record is `%Ash.NotLoaded{}` (not
  # actually resolved here) is skipped, never emitted as an incomplete
  # object.
  @doc false
  def managed_relationship_objects(%{changeset: %{relationships: relationships}} = notification)
      when is_map(relationships) do
    resource = notification.resource
    data = notification.data

    relationships
    |> Map.keys()
    |> Enum.reduce({[], []}, fn rel_name, {objects_acc, rels_acc} ->
      case related_records(resource, data, rel_name) do
        {:ok, destination, records} ->
          qualifier = to_string(rel_name)

          Enum.reduce(records, {objects_acc, rels_acc}, fn record, {o, r} ->
            related_id = record_id(destination, record)
            object = %{"id" => related_id, "type" => resource_type_name(destination)}
            relationship = %{"objectId" => related_id, "qualifier" => qualifier}
            {[object | o], [relationship | r]}
          end)

        :error ->
          {objects_acc, rels_acc}
      end
    end)
  end

  def managed_relationship_objects(_notification), do: {[], []}

  defp related_records(resource, data, rel_name) do
    with %{destination: destination} <- Ash.Resource.Info.relationship(resource, rel_name),
         true <- is_struct(data),
         value <- Map.get(data, rel_name),
         false <- is_struct(value, Ash.NotLoaded) do
      {:ok, destination, List.wrap(value)}
    else
      _ -> :error
    end
  end

  # Deterministic, globally-unique, restart-stable event id: a SHA-256
  # digest of (resource module, activity name, resolved record id,
  # ISO-8601 timestamp), not System.unique_integer/1 (process-local,
  # resets to 1 on every VM restart, no cross-node uniqueness -- see the
  # confirmed finding this replaces). Same logical event (same resource +
  # activity + record + timestamp) on a retried/duplicate notify/1 firing
  # now produces the SAME id, which is what makes id-based downstream
  # dedup possible; System.unique_integer/1 could never do that because it
  # produces a different value on every call by definition.
  @doc false
  def event_id(resource, activity, record_id, %DateTime{} = timestamp) do
    digest =
      :crypto.hash(
        :sha256,
        [inspect(resource), to_string(activity.name), record_id, DateTime.to_iso8601(timestamp)]
      )
      |> Base.encode16(case: :lower)

    "ev_" <> digest
  end

  defp fetch_field(data, name) when is_struct(data), do: fetch_present(data, name)
  defp fetch_field(data, name) when is_map(data), do: fetch_present(data, to_string(name))
  defp fetch_field(_data, _name), do: :error

  # Shared "present and non-nil" rule: a key that is either missing or set
  # to `nil` is treated identically as :error (absent), everywhere this
  # notifier reads a field off real notification data (declared object
  # attributes, declared event attributes, primary-key values) -- never a
  # silently-fabricated `nil`/empty value standing in for a real one.
  defp fetch_present(map, key) do
    case Map.fetch(map, key) do
      {:ok, nil} -> :error
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  defp coerce_attribute(value, :string) when is_binary(value), do: {:ok, value}
  defp coerce_attribute(value, :string) when is_atom(value), do: {:ok, to_string(value)}

  defp coerce_attribute(value, :integer) when is_integer(value), do: {:ok, value}

  defp coerce_attribute(value, :float) when is_float(value), do: {:ok, value}
  defp coerce_attribute(value, :float) when is_integer(value), do: {:ok, value * 1.0}

  defp coerce_attribute(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp coerce_attribute(value, :atom) when is_atom(value), do: {:ok, to_string(value)}

  defp coerce_attribute(%Date{} = value, :date), do: {:ok, Date.to_iso8601(value)}

  defp coerce_attribute(%DateTime{} = value, :datetime),
    do: {:ok, DateTime.to_iso8601(value)}

  defp coerce_attribute(_value, _type), do: :error

  defp resource_type_name(resource), do: resource |> Module.split() |> List.last()

  # Resolves this activity's declared `object_relationship` entities (see
  # `AshEx4pm.ObjectRelationship`) into the real, `Ex4pm.OCEL`-accepted
  # `"object_relationships"` shape (`source_id`/`target_id`/`qualifier`,
  # confirmed against `normalize_object_relationships/1` in
  # `~/ex4pm/lib/ex4pm/ocel.ex`), using ONLY data already present on the
  # notification -- never a fresh DB load, which would be a real,
  # unauthorized side effect running inside a post-commit notifier.
  #
  # A relationship whose target record isn't loaded onto
  # `notification.data` (the action never selected/loaded it) is skipped
  # and logged -- a real, disclosed gap, never a fabricated or nil target
  # id silently emitted into the envelope.
  @doc false
  def resolve_object_relationships(activity, notification, source_id) do
    activity.object_relationships
    |> Enum.map(&resolve_object_relationship(&1, notification, source_id))
    |> Enum.filter(& &1)
  end

  defp resolve_object_relationship(rel, notification, source_id) do
    resource = notification.resource

    with true <- is_struct(notification.data),
         definition when not is_nil(definition) <-
           relationship_definition(resource, rel.relationship),
         raw_target when not is_nil(raw_target) <- Map.get(notification.data, rel.relationship),
         target when not is_nil(target) <- loaded_target(raw_target),
         target_id when not is_nil(target_id) <- record_id(definition.destination, target) do
      %{
        "source_id" => source_id,
        "target_id" => target_id,
        "qualifier" => rel.qualifier
      }
    else
      _ ->
        Logger.warning(
          "AshEx4pm.Notifier: could not resolve object_relationship " <>
            "#{inspect(rel.relationship)} (qualifier #{inspect(rel.qualifier)}) -- " <>
            "target not loaded on notification data; O2O fact omitted, not fabricated",
          resource: resource,
          activity: activity_name(notification)
        )

        nil
    end
  end

  defp activity_name(%{action: %{name: name}}), do: name
  defp activity_name(_), do: nil

  # A `belongs_to`/`has_one` relationship loads a single struct (or nil,
  # or `%Ash.NotLoaded{}`); `has_many`/`many_to_many` loads a list. This
  # notifier's O2O model is a single source-to-single-target fact per
  # declaration, so only a genuinely-loaded single struct resolves --
  # anything else (a list, `%Ash.NotLoaded{}`, a lazy loader) is treated
  # as unresolved rather than guessed at.
  defp loaded_target(%Ash.NotLoaded{}), do: nil
  defp loaded_target(%_{} = struct), do: struct
  defp loaded_target(_), do: nil

  defp relationship_definition(resource, relationship_name) do
    Ash.Resource.Info.relationship(resource, relationship_name)
  rescue
    _ -> nil
  end

  # Resolve the OCEL object id from the resource's real primary key
  # (Ash.Resource.Info.primary_key/1) rather than assuming an :id
  # attribute -- Ash resources are not required to be named :id and may
  # have a composite primary key. Falls back to a plain "id"/"id" map
  # lookup for notification.data that isn't a persisted resource struct
  # at all (e.g. a hand-built %Ash.Notifier.Notification{} from a
  # generic action's before_action/after_action hook, per
  # Ash.ActionInput's own doctest). A resolved-but-nil primary key, or no
  # resolvable id at all, is a distinct, logged, clearly-synthetic
  # fallback -- never a silently-empty string or an unmarked random id.
  @doc false
  def record_id(resource, data) do
    with true <- is_atom(resource) and is_struct(data),
         [_ | _] = pk <- primary_key(resource),
         values when is_list(values) <- pk_values(data, pk) do
      Enum.map_join(values, ":", &to_string/1)
    else
      _ -> record_id_fallback(resource, data)
    end
  end

  defp primary_key(resource) do
    Ash.Resource.Info.primary_key(resource)
  rescue
    _ -> []
  end

  # Returns the list of primary-key values only if every one is present
  # and non-nil (via fetch_present/2); otherwise :error, so a nil/unset pk
  # field never falls through as an empty string.
  defp pk_values(data, pk) do
    Enum.reduce_while(pk, [], fn field, acc ->
      case fetch_present(data, field) do
        {:ok, value} -> {:cont, [value | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      values -> Enum.reverse(values)
    end
  end

  # Shared prefix for a synthetic, non-reproducible object id -- kept as a
  # single named constant rather than a bare string literal repeated at
  # every generation/inspection site, so a caller elsewhere in the codebase
  # that ever needs to recognize a synthetic id cannot silently desync from
  # this literal.
  @synthetic_id_prefix "synthetic_obj_"

  defp record_id_fallback(resource, data) do
    cond do
      is_map(data) and Map.has_key?(data, :id) and not is_nil(data.id) ->
        to_string(data.id)

      is_map(data) and Map.has_key?(data, "id") and not is_nil(data["id"]) ->
        to_string(data["id"])

      true ->
        Logger.warning(
          "AshEx4pm.Notifier: could not resolve a real primary key for " <>
            "#{inspect(resource)} notification data #{inspect(data)}; " <>
            "using a synthetic, non-reproducible object id"
        )

        @synthetic_id_prefix <> Integer.to_string(System.unique_integer([:positive]))
    end
  end
end
