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

  defp build_envelope(activity, notification) do
    provenance_source =
      AshEx4pm.Info.compiled(notification.resource)[:provenance_source] || :ash_ex4pm

    record_id = record_id(notification.data)

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

  defp record_id(data) do
    cond do
      is_struct(data) and Map.has_key?(data, :id) -> to_string(data.id)
      is_map(data) and Map.has_key?(data, :id) -> to_string(data.id)
      is_map(data) and Map.has_key?(data, "id") -> to_string(data["id"])
      true -> "obj_#{System.unique_integer([:positive])}"
    end
  end
end
