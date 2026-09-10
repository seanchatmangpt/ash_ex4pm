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

  ## Scope: the primary object, plus any relationship already loaded on
  ## `notification.data`

  `build_envelope/2` always emits the acting resource's own `record_id`
  as the primary OCEL object (`qualifier: "primary"`). It additionally
  walks `Ash.Resource.Info.relationships/1` for the resource and, for
  each relationship whose value on `notification.data` is *actually
  loaded* (not `%Ash.NotLoaded{}`), emits the related struct(s) as
  additional OCEL objects plus event relationships qualified by the
  relationship name.

  This is real, not speculative, because of what `notification.data`
  actually is: for `create`/`update`/`destroy`, Ash's own
  `Ash.Actions.ManagedRelationships.manage_relationships/4`
  (`deps/ash/lib/ash/actions/managed_relationships.ex:710,807`) writes
  the REAL, POST-COMMIT related struct(s) -- not raw pre-commit input --
  back onto the record via `Map.put(record, relationship.name,
  new_value)`, and that same record is exactly what flows through
  `Ash.Actions.Update.Update`/`Create.Create`/`Destroy.Destroy`'s
  `manage_relationships/4` into
  `Ash.Actions.Helpers.resource_notification/3`'s `data: result`
  (`deps/ash/lib/ash/actions/helpers.ex:475-484`). So
  `notification.data.<relationship_name>` genuinely holds real,
  persisted related records with real primary keys whenever
  `manage_relationship` (or an explicit `load:`) touched that
  relationship on this same action -- it does NOT require reading
  `changeset.relationships` (which is raw pre-commit input, correctly
  never used here).

  A relationship that this action did not touch stays `%Ash.NotLoaded{}`
  on `notification.data` and is correctly skipped -- this notifier never
  guesses at, or lazily loads, relationships nothing on this changeset
  actually populated. A loaded-but-empty `has_many`/`many_to_many` (`[]`)
  is also skipped (nothing relational actually happened), while a
  loaded-but-`nil` `belongs_to`/`has_one` is skipped for the same reason.

  What this does NOT do: correlate relationship changes ACROSS sibling
  resources' own separate `resource_notifications` (Ash may fire several
  independent notifications for one action, one per affected resource) --
  that remains a genuinely separate problem from recovering identities
  already sitting on THIS notification's own `data`, and is out of scope
  here. For that cross-resource case, or for attaching real per-object
  `"type"`/`"attributes"` to a related object this walk cannot infer, use
  a resource-level `Ash.Resource.Change` that builds a manual
  `%Ash.Notifier.Notification{}` (see `action_input.ex`'s pattern).
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
  # directly. See the moduledoc's "Scope: the primary object, plus any
  # relationship already loaded on `notification.data`" section for what
  # this does and does not attempt to recover.
  @doc false
  def build_envelope(activity, notification) do
    provenance_source =
      AshEx4pm.Info.compiled(notification.resource)[:provenance_source] || :ash_ex4pm

    record_id = record_id(notification.resource, notification.data)

    related =
      relationship_objects(notification.resource, notification.data)

    objects =
      Map.new(
        [{record_id, resource_type_name(notification.resource), "primary"} | related],
        fn {id, type, _qualifier} -> {id, %{"id" => id, "type" => type}} end
      )

    relationships =
      [%{"objectId" => record_id, "qualifier" => "primary"}] ++
        Enum.map(related, fn {id, _type, qualifier} -> %{"objectId" => id, "qualifier" => qualifier} end)

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
          "relationships" => relationships
        }
      ]
    }
  end

  # Walks the resource's real relationships and, for each one that is
  # actually loaded on `data` (i.e. touched by `manage_relationship` or
  # an explicit `load:` on this same action -- never %Ash.NotLoaded{}),
  # extracts the real persisted related struct(s) as extra OCEL objects.
  # Returns a list of {object_id, type, qualifier} triples so the caller
  # can build both the "objects" map and the event's "relationships"
  # list from the same real, resolved data.
  defp relationship_objects(resource, data) when is_atom(resource) and is_struct(data) do
    resource
    |> relationships()
    |> Enum.flat_map(fn relationship ->
      case Map.get(data, relationship.name) do
        %Ash.NotLoaded{} ->
          []

        nil ->
          []

        [] ->
          []

        value ->
          value
          |> List.wrap()
          |> Enum.filter(&is_struct/1)
          |> Enum.map(fn related_struct ->
            {record_id(relationship.destination, related_struct),
             resource_type_name(relationship.destination), to_string(relationship.name)}
          end)
      end
    end)
    |> Enum.uniq_by(fn {id, _type, qualifier} -> {id, qualifier} end)
  end

  defp relationship_objects(_resource, _data), do: []

  defp relationships(resource) do
    Ash.Resource.Info.relationships(resource)
  rescue
    _ -> []
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
