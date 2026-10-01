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
    unknown: 0,
    escape: 0,
    lookup_byte: 1,
    lookup_activity: 1,
    category: 1,
    encode: 1,
    decode: 1,
    to_event: 3
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

  @doc "Fetch the canonical registry. Result is wrapped so dependency refusal is explicit."
  @spec registry() :: {:ok, map()} | {:error, refusal()}
  def registry do
    with_provider(fn -> {:ok, apply(@provider, :registry, [])} end)
  end

  @spec unknown() :: {:ok, non_neg_integer()} | {:error, refusal()}
  def unknown do
    with_provider(fn -> {:ok, apply(@provider, :unknown, [])} end)
  end

  @spec escape() :: {:ok, non_neg_integer()} | {:error, refusal()}
  def escape do
    with_provider(fn -> {:ok, apply(@provider, :escape, [])} end)
  end

  @spec lookup_byte(non_neg_integer()) :: {:ok, atom()} | {:error, term()}
  def lookup_byte(byte) do
    with_provider(fn -> apply(@provider, :lookup_byte, [byte]) end)
  end

  @spec lookup_activity(atom() | String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def lookup_activity(activity) do
    with_provider(fn -> apply(@provider, :lookup_activity, [activity]) end)
  end

  @spec category(non_neg_integer()) :: atom() | {:error, term()}
  def category(byte) do
    with_provider(fn -> apply(@provider, :category, [byte]) end)
  end

  @spec encode(term()) :: {:ok, binary()} | {:error, term()}
  def encode(activity) do
    with_provider(fn -> apply(@provider, :encode, [activity]) end)
  end

  @spec decode(binary()) :: {:ok, term()} | {:error, term()}
  def decode(frame) when is_binary(frame) do
    with_provider(fn -> apply(@provider, :decode, [frame]) end)
  end

  @doc """
  Project an admitted economic verb into ex4pm's canonical OCEL event IR.

  This remains an observation/manufacturing operation only.  It does not grant
  an Ash action, planner, notifier, model, or caller external DO authority.
  """
  @spec to_event(term(), String.t(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def to_event(activity, event_id, timestamp, opts \\ []) do
    with_provider(fn ->
      apply(@provider, :to_event, [activity, event_id, timestamp, opts])
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

  defp project_decoded({:fixed, byte, canonical_activity}, frame) do
    case category(byte) do
      {:error, _} = error ->
        error

      category ->
        {:ok,
         %{
           opcode: byte,
           activity: canonical_activity,
           category: category,
           semantic_id: nil,
           frame: frame
         }}
    end
  end

  defp project_decoded({:extended, semantic_id}, frame) do
    {:ok,
     %{
       opcode: 0xFF,
       activity: :extended,
       category: :escape,
       semantic_id: semantic_id,
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
