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

  ## Scope: single-object events only

  `build_envelope/2` always emits exactly one OCEL object -- the acting
  resource's own `record_id` -- and one relationship entry
  (`qualifier: "primary"` pointing at that same id). This is deliberate,
  not an oversight: a single `Ash.Notifier.Notification` here corresponds
  to a single resource/changeset, and `notify/1` has no reliable way to
  recover the *actual persisted* identities of records touched via
  `Ash.Changeset.manage_relationship/3` from that one notification alone
  (`changeset.relationships` holds the raw pre-commit input passed to
  `manage_relationship`, not resolved post-commit related-record ids, and
  a single Ash action with `manage_relationship` can already produce
  several independent `resource_notifications` -- one per affected
  resource -- rather than one combined notification carrying the full
  relationship set).

  If an activity is genuinely relational (e.g. an order-to-line-item
  append that should be modeled as one multi-object OCEL event), this
  notifier is the wrong mechanism for it. Instead, add a resource-level
  `Ash.Resource.Change` that builds and returns a manual
  `%Ash.Notifier.Notification{}` carrying the full object/relationship
  set for that action (see `action_input.ex`'s manual-notification
  pattern) rather than relying on this notifier's one-object-per-action
  default.
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
  # directly -- deliberately single-object/single-relationship, see the
  # moduledoc's "Scope: single-object events only" section for why this
  # notifier does not attempt to recover related-record identities from
  # `manage_relationship` calls on the same changeset.
  @doc false
  def build_envelope(activity, notification) do
    provenance_source =
      AshEx4pm.Info.compiled(notification.resource)[:provenance_source] || :ash_ex4pm

    record_id = record_id(notification.resource, notification.data)

    %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => to_string(provenance_source),
        "runtime" => "beam",
        "resource" => inspect(notification.resource)
      },
      "sequence" => System.unique_integer([:positive]),
      "objects" => %{
        record_id => object_map(activity, notification.resource, record_id, notification.data)
      },
      "events" => [
        %{
          "id" => "ev_#{System.unique_integer([:positive])}",
          "activity" => to_string(activity.name),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "relationships" => [%{"objectId" => record_id, "qualifier" => "primary"}]
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
  # `nil`/empty value, the same "never a silently-empty fallback"
  # discipline `pk_values/2` already applies to primary-key resolution
  # below.
  defp declared_attributes(%AshEx4pm.ObjectType{attributes: attributes}, data)
       when is_map(data) do
    Enum.reduce(attributes, %{}, fn {name, _type}, acc ->
      case Map.fetch(data, name) do
        {:ok, nil} -> acc
        {:ok, value} -> Map.put(acc, to_string(name), value)
        :error -> acc
      end
    end)
  end

  defp declared_attributes(_object_type, _data), do: %{}

  defp resource_type_name(resource), do: resource |> Module.split() |> List.last()

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
  # and non-nil; otherwise :error, so a nil/unset pk field never falls
  # through as an empty string.
  defp pk_values(data, pk) do
    Enum.reduce_while(pk, [], fn field, acc ->
      case Map.fetch(data, field) do
        {:ok, nil} -> {:halt, :error}
        {:ok, value} -> {:cont, [value | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      values -> Enum.reverse(values)
    end
  end

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

        "synthetic_obj_#{System.unique_integer([:positive])}"
    end
  end
end
