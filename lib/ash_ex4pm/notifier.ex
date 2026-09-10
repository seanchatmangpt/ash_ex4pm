defmodule AshEx4pm.Notifier do
  @moduledoc """
  Real `Ash.Notifier` that emits an OCEL 2.0 event for every Ash action
  matching a compiled `activity` declaration, via
  `Ex4pm.Stream.Ingest.ingest_envelope/1` -- the function that actually
  exists and works, not `Ex4pm.Stream.Ingest.ingest_batch/1` (the dead
  call `Ex4pmDomain.Notifier.OcelNotifier` makes, confirmed nonexistent,
  `~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md` BLOCKER 1).

  Must be added explicitly to a resource's own `notifiers:` list (this
  extension does not inject itself -- see `AshEx4pm`'s moduledoc and the
  PRD's "global notifier injection" non-goal):

      use Ash.Resource,
        notifiers: [AshEx4pm.Notifier],
        extensions: [AshEx4pm]

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

  ## Scope: single primary object, plus declared O2O facts

  `build_envelope/2` always emits exactly one OCEL *event* object -- the
  acting resource's own `record_id` -- and one `"primary"` relationship
  entry pointing at that same id. This is deliberate, not an oversight: a
  single `Ash.Notifier.Notification` here corresponds to a single
  resource/changeset, and `notify/1` has no reliable way to recover the
  *actual persisted* identities of records touched via
  `Ash.Changeset.manage_relationship/3` from that one notification alone
  (`changeset.relationships` holds the raw pre-commit input passed to
  `manage_relationship`, not resolved post-commit related-record ids, and
  a single Ash action with `manage_relationship` can already produce
  several independent `resource_notifications` -- one per affected
  resource -- rather than one combined notification carrying the full
  relationship set).

  A resource author CAN declare real OCEL 2.0 O2O (object-to-object)
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
  # directly -- deliberately single-object/single-relationship, see the
  # moduledoc's "Scope: single-object events only" section for why this
  # notifier does not attempt to recover related-record identities from
  # `manage_relationship` calls on the same changeset.
  @doc false
  def build_envelope(activity, notification) do
    provenance_source =
      AshEx4pm.Info.compiled(notification.resource)[:provenance_source] || :ash_ex4pm

    record_id = record_id(notification.resource, notification.data)

    object_relationships =
      resolve_object_relationships(activity, notification, record_id)

    %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => to_string(provenance_source),
        "runtime" => "beam",
        "resource" => inspect(notification.resource)
      },
      "sequence" => System.unique_integer([:positive]),
      "objects" => %{
        record_id => %{
          "id" => record_id,
          "type" => resource_type_name(notification.resource)
        }
      },
      "object_relationships" => object_relationships,
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
