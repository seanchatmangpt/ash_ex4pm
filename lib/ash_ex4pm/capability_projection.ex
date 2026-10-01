defmodule AshEx4pm.CapabilityProjection do
  @moduledoc """
  Flat, storable projection of an `Ex4pm.Engine.Result` (or typed refusal).

  `admitted` is true only when standing is `:alive`, the wasm replay was
  verified, the artifact sha256 is a binary, and the transport identity was
  observed. Everything else is a projection, never authority.
  """

  defstruct [
    :engine,
    :operation,
    :standing,
    :artifact_sha256,
    :refusal_code,
    :source_sha,
    :request_digest,
    :result_digest,
    admitted: false,
    replay_verified: false
  ]

  @type t :: %__MODULE__{}

  if Code.ensure_loaded?(Ex4pm.Engine.Result) do
    @doc "Project a result, `{:ok, result}`, or `{:error, refusal}`."
    @spec from_result(term()) :: t()
    def from_result({:ok, %Ex4pm.Engine.Result{} = r}), do: from_result(r)

    def from_result(%Ex4pm.Engine.Result{} = r) do
      ev = r.evidence || %{}
      identity = get(ev, :transport_identity) || %{}
      replay? = get(ev, :replay_verified) == true
      sha = get(ev, :wasm_sha256) || get(identity, :wasm_sha256)

      %__MODULE__{
        engine: r.engine,
        operation: r.operation,
        standing: r.standing,
        artifact_sha256: sha,
        replay_verified: replay?,
        admitted:
          r.standing == :alive and replay? and is_binary(sha) and
            get(ev, :identity_observed) == true,
        source_sha: get(ev, :wasm4pm_source_sha),
        request_digest: get(ev, :request_digest),
        result_digest: get(ev, :result_digest)
      }
    end

    def from_result({:error, %Ex4pm.Refusal{} = ref}) do
      %__MODULE__{refusal_code: ref.code, admitted: false, replay_verified: false}
    end

    def from_result({:error, _other}), do: %__MODULE__{refusal_code: :unknown_error}

    @doc "Run `Ex4pm.Engine.execute/3` and project the outcome."
    @spec project(atom(), term(), keyword()) :: t()
    def project(operation, subject, opts \\ []) do
      operation |> Ex4pm.Engine.execute(subject, opts) |> from_result()
    end
  else
    def from_result(_), do: {:error, :ex4pm_unavailable}
    def project(_op, _subject, _opts \\ []), do: {:error, :ex4pm_unavailable}
  end

  @doc "Plain map form, suitable for storing in Ash attributes."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = p), do: Map.from_struct(p)

  defp get(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp get(_, _), do: nil
end
