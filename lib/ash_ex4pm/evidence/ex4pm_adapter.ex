defmodule AshEx4pm.Evidence.Ex4pmAdapter do
  @moduledoc """
  Guarded adapter from `AshEx4pm.Evidence.ProcessEvidence.Event` to the
  canonical `ash_ex4pm/1` wire envelope, admitted by the real
  `Ex4pm.OCEL.validate_envelope/1` and `Ex4pm.Stream.Ingest.ingest_envelope/2`.

  Guarded: with ex4pm/ash_ex4pm absent every call returns
  `{:error, %{reason: :unsupported, detail: :ex4pm_not_available}}`.

  Broadcaster: OPT-IN via app env `:ash_ex4pm` key `:broadcaster`
  (a module implementing `broadcast/1`); when configured it receives every
  validated envelope for realtime fan-out.
  """

  @schema "ash_ex4pm/1"

  def ex4pm_available?,
    do: Code.ensure_loaded?(Ex4pm.OCEL) and Code.ensure_loaded?(Ex4pm.Stream.Ingest)

  def available?, do: ex4pm_available?()

  @doc "Build the envelope map (pure; no ex4pm needed)."
  @spec envelope([AshEx4pm.Evidence.ProcessEvidence.Event.t()], keyword()) :: map()
  def envelope(events, ctx \\ []) when is_list(events) do
    {ctx_objects, ctx_rels} = context_objects(ctx)

    objects =
      events
      |> Enum.flat_map(& &1.objects)
      |> Enum.reduce(ctx_objects, fn {t, id, _q}, acc ->
        Map.put_new(acc, id, %{"id" => id, "type" => t})
      end)

    %{
      "schema" => @schema,
      "producer" => %{
        "agent_id" => "ash_ex4pm",
        "runtime" => "beam",
        "resource" => "AshEx4pm.Evidence.Ex4pmAdapter"
      },
      "sequence" => System.os_time(:nanosecond),
      "objects" => objects,
      "object_relationships" => [],
      "events" => Enum.map(events, &event(&1, ctx, ctx_rels))
    }
  end

  @doc "Validate through the real Ex4pm.OCEL.validate_envelope/1."
  def validate(events, ctx \\ []) do
    if ex4pm_available?(),
      do: apply(Ex4pm.OCEL, :validate_envelope, [envelope(events, ctx)]),
      else: unsupported(:ex4pm_not_available)
  end

  @doc "Ingest through the real Ex4pm.Stream.Ingest.ingest_envelope/2; ctx[:ingest_opts] passes store/miner."
  def ingest(events, ctx \\ []) do
    if ex4pm_available?() do
      env = envelope(events, ctx)

      with {:ok, _normalized} <- apply(Ex4pm.OCEL, :validate_envelope, [env]) do
        result =
          apply(Ex4pm.Stream.Ingest, :ingest_envelope, [env, Keyword.get(ctx, :ingest_opts, [])])

        broadcast(env)
        result
      end
    else
      unsupported(:ex4pm_not_available)
    end
  end

  @doc """
  True when the emitter's own Ash resource declares an ex4pm activity surface.
  """
  def activities(resource) do
    if Code.ensure_loaded?(AshEx4pm.Info) do
      {:ok, apply(AshEx4pm.Info, :activities, [resource])}
    else
      unsupported(:ash_ex4pm_not_available)
    end
  rescue
    e in ArgumentError ->
      {:error, %{reason: :not_an_ex4pm_resource, detail: Exception.message(e)}}
  end

  # -- opt-in broadcaster (app env :broadcaster implementing broadcast/1) -----

  defp broadcast(env) do
    case Application.get_env(:ash_ex4pm, :broadcaster) do
      nil -> :ok
      mod -> apply(mod, :broadcast, [env])
    end
  end

  # -- context objects (subject/task/realization -> OCEL objects + rels) ------

  defp event(%AshEx4pm.Evidence.ProcessEvidence.Event{} = e, ctx, ctx_rels) do
    rels =
      Enum.map(e.objects, fn {_t, id, q} -> %{"objectId" => id, "qualifier" => q} end) ++ ctx_rels

    %{
      "id" => e.id,
      "activity" => e.activity,
      "timestamp" => DateTime.to_iso8601(e.timestamp),
      "relationships" => rels,
      "attributes" =>
        e.attributes
        |> stringify()
        |> Map.merge(context_attributes(ctx))
        |> Map.put("subject_id", e.subject_id || subject_id(ctx))
    }
  end

  defp subject_id(ctx), do: with(%{id: id} <- ctx[:subject], do: id)

  defp context_objects(ctx) do
    [
      subject_obj(ctx[:subject]),
      task_obj(ctx[:subject], ctx[:task]),
      realization_obj(ctx[:realization])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce({Map.new(), []}, fn {type, id, q, attrs}, {o, r} ->
      {Map.put(o, id, %{"id" => id, "type" => type, "attributes" => attrs}),
       r ++ [%{"objectId" => id, "qualifier" => q}]}
    end)
  end

  defp subject_obj(%{id: id} = s),
    do:
      {"WorkflowSubject", id, "subject",
       %{"workflow" => to_string(s[:workflow]), "digest" => s[:digest]}}

  defp subject_obj(_), do: nil

  defp task_obj(subj, task) when not is_nil(task) do
    base = if is_map(subj), do: subj[:id], else: "none"
    corr = with %{correspondence: c} <- subj, do: c[task]

    {"WorkflowTask", "task:#{base}:#{task}", "task",
     %{"task" => to_string(task), "semantic" => is_map(corr) && corr[:semantic]}}
  end

  defp task_obj(_, _), do: nil

  defp realization_obj(%{capability: cap, provider: prov} = r) do
    b = r[:binding] || %{}
    op = b[:op]

    {"Realization", "realization:#{cap}:#{prov}:#{op}", "realization",
     %{
       "capability" => cap,
       "provider" => to_string(prov),
       "adapter" => b[:adapter] && to_string(b[:adapter]),
       "op" => op && to_string(op)
     }}
  end

  defp realization_obj(_), do: nil

  defp context_attributes(ctx) do
    %{}
    |> put_attr("authority", ctx[:authority])
    |> put_attr("evidence", ctx[:evidence])
  end

  defp put_attr(m, _k, nil), do: m
  defp put_attr(m, k, v), do: Map.put(m, k, to_json(v))

  defp to_json(v) when is_map(v) and not is_struct(v), do: stringify(v)
  defp to_json(v) when is_atom(v) and not is_boolean(v) and not is_nil(v), do: Atom.to_string(v)
  defp to_json(v) when is_list(v), do: Enum.map(v, &to_json/1)
  defp to_json(v), do: v

  defp stringify(m), do: Map.new(m, fn {k, v} -> {to_string(k), to_json(v)} end)

  defp unsupported(detail), do: {:error, %{reason: :unsupported, detail: detail}}
end
