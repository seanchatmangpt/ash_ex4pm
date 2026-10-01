defmodule AshEx4pm.EconomicISA do
  @moduledoc """
  Ash-facing adapter over the canonical `Ex4pm.EconomicISA` boundary.

  This module deliberately owns **no economic opcode registry**.  The semantic
  authority remains in `ex4pm`; `ash_ex4pm` only exposes that admitted boundary
  to Ash applications once the installed ex4pm dependency exports the complete
  contract.

  The current package can therefore be compiled against an older ex4pm release
  without silently forking byte meanings.  Until the canonical provider is
  present, calls return a typed dependency refusal and standing is
  `:partial_alive`.

  The economic byte remains only the verb.  Ash resource identity, business
  objects, amounts, provenance, authority, and receipts stay explicit fields or
  relationships and are never collapsed into the opcode.
  """

  @provider Ex4pm.EconomicISA

  @required_contract [
    registry: 0,
    ranges: 0,
    unknown_opcode: 0,
    escape_opcode: 0,
    lookup: 1,
    category: 1,
    encode: 1,
    encode_extended: 1,
    decode: 1,
    to_event: 2
  ]

  @type standing :: :alive | :partial_alive
  @type refusal :: {:economic_isa_unavailable, map()}

  @doc "Canonical provider. Kept explicit so a second registry cannot emerge here."
  @spec provider() :: module()
  def provider, do: @provider

  @doc "The exact provider surface required by this adapter."
  @spec required_contract() :: keyword(non_neg_integer())
  def required_contract, do: @required_contract

  @doc "True only when the installed ex4pm exports the entire economic ISA contract."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(@provider) and
      Enum.all?(@required_contract, fn {name, arity} ->
        function_exported?(@provider, name, arity)
      end)
  end

  @doc "Evidence-bounded standing for the adapter/dependency boundary."
  @spec standing() :: {standing(), map()}
  def standing do
    if available?() do
      {:alive, %{provider: @provider, contract: @required_contract}}
    else
      {:partial_alive,
       %{
         provider: @provider,
         contract: @required_contract,
         missing: missing_contract()
       }}
    end
  end

  @doc "Returns the missing provider functions without inventing replacements."
  @spec missing_contract() :: keyword(non_neg_integer())
  def missing_contract do
    if Code.ensure_loaded?(@provider) do
      Enum.reject(@required_contract, fn {name, arity} ->
        function_exported?(@provider, name, arity)
      end)
    else
      @required_contract
    end
  end

  @doc "Fetch the canonical registry (list of `%{name, opcode, category}`)."
  @spec registry() :: {:ok, [map()]} | {:error, refusal()}
  def registry do
    with_provider(fn -> {:ok, apply(@provider, :registry, [])} end)
  end

  @doc "Canonical category ranges."
  @spec ranges() :: {:ok, term()} | {:error, refusal()}
  def ranges do
    with_provider(fn -> {:ok, apply(@provider, :ranges, [])} end)
  end

  @spec unknown() :: {:ok, non_neg_integer()} | {:error, refusal()}
  def unknown do
    with_provider(fn -> {:ok, apply(@provider, :unknown_opcode, [])} end)
  end

  @spec escape() :: {:ok, non_neg_integer()} | {:error, refusal()}
  def escape do
    with_provider(fn -> {:ok, apply(@provider, :escape_opcode, [])} end)
  end

  @spec lookup_byte(non_neg_integer()) :: {:ok, atom()} | {:error, term()}
  def lookup_byte(byte) when is_integer(byte) do
    with_provider(fn ->
      case apply(@provider, :lookup, [byte]) do
        {:ok, %{name: name}} -> {:ok, name}
        :error -> {:error, {:unknown_economic_opcode, byte}}
      end
    end)
  end

  @spec lookup_activity(atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def lookup_activity(activity) when is_atom(activity) do
    with_provider(fn ->
      case apply(@provider, :lookup, [activity]) do
        {:ok, %{opcode: opcode}} -> {:ok, opcode}
        :error -> {:error, {:unknown_economic_activity, activity}}
      end
    end)
  end

  @spec category(non_neg_integer()) :: {:ok, atom()} | {:error, term()}
  def category(byte) do
    with_provider(fn -> {:ok, apply(@provider, :category, [byte])} end)
  end

  @doc "Encode an activity name to its canonical frame; `{:extended, id}` uses the escape record."
  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode({:extended, semantic_id}) do
    with_provider(fn -> apply(@provider, :encode_extended, [semantic_id]) end)
  end

  def encode(activity) do
    with_provider(fn -> apply(@provider, :encode, [activity]) end)
  end

  @doc "Decode a frame to the canonical `%{name, opcode, category}` map (plus `semantic_id` for escapes)."
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(frame) when is_binary(frame) do
    with_provider(fn -> apply(@provider, :decode, [frame]) end)
  end

  @doc """
  Project an admitted economic verb into ex4pm's canonical OCEL event IR.

  This remains an observation/manufacturing operation only.  It does not grant
  an Ash action, planner, notifier, model, or caller external DO authority.
  Extra `opts` (`:object_ids`, `:relationships`, `:attributes`, `:provenance`,
  `:authority`, `:value`) pass through to the canonical provider.
  """
  @spec to_event(term(), String.t(), String.t() | DateTime.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def to_event(activity, event_id, timestamp, opts \\ []) do
    with_provider(fn ->
      apply(@provider, :to_event, [activity, [id: event_id, timestamp: timestamp] ++ opts])
    end)
  end

  @doc """
  Normalize a canonical economic activity for an Ash attribute/resource surface.

  The returned map is a projection of ex4pm's registry, never a local source of
  meaning.  Extended semantics retain their full semantic identifier.
  """
  @spec project(term()) :: {:ok, map()} | {:error, term()}
  def project(activity) do
    with {:ok, frame} <- encode(activity),
         {:ok, decoded} <- decode(frame) do
      project_decoded(decoded, frame)
    end
  end

  defp project_decoded(%{semantic_id: semantic_id, opcode: opcode, category: category}, frame) do
    {:ok,
     %{
       opcode: opcode,
       activity: :extended,
       category: category,
       semantic_id: semantic_id,
       frame: frame
     }}
  end

  defp project_decoded(%{name: name, opcode: opcode, category: category}, frame) do
    {:ok,
     %{
       opcode: opcode,
       activity: name,
       category: category,
       semantic_id: nil,
       frame: frame
     }}
  end

  defp project_decoded(other, _frame),
    do: {:error, {:unexpected_economic_frame, other}}

  defp with_provider(fun) when is_function(fun, 0) do
    if available?() do
      fun.()
    else
      {:error,
       {:economic_isa_unavailable,
        %{
          provider: @provider,
          missing: missing_contract()
        }}}
    end
  end
end
