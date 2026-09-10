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

    primary_object = %{"id" => record_id, "type" => resource_type_name(notification.resource)}
    primary_relationship = %{"objectId" => record_id, "qualifier" => "primary"}

    {related_objects, related_relationships} =
      managed_relationship_objects(notification)

    objects =
      [primary_object | related_objects]
      |> Map.new(&{&1["id"], &1})

    %{
      "schema" => "ash_ex4pm/1",
      "producer" => %{
        "agent_id" => to_string(provenance_source),
        "runtime" => "beam",
        "resource" => inspect(notification.resource)
      },
      "sequence" => System.unique_integer([:positive]),
      "objects" => objects,
      "events" => [
        %{
          "id" => "ev_#{System.unique_integer([:positive])}",
          "activity" => to_string(activity.name),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "relationships" => [primary_relationship | related_relationships]
        }
      ]
    }
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
