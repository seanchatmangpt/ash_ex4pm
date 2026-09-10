defmodule AshEx4pm.Changes.BrceGate do
  @moduledoc """
  Real Ash.Resource.Change gating a state-changing action behind
  `Ex4pm.Evidence.BRCE.execute/4` -- resolves the PRD's previously
  UNVERIFIED FR8 (`~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md` §3.8):
  `Ex4pm.Evidence.BRCE.execute/4,5` and `.admit/2` are real, confirmed
  public functions (`~/ex4pm/lib/ex4pm/evidence.ex:222-344`) with no
  Ash-specific glue of their own -- this module is that glue.

  ## Usage

      create :create do
        change {AshEx4pm.Changes.BrceGate, operation: :create_order}
      end

  The `authority` map BRCE requires (`%{capabilities: [...]} |
  %{allow: [...]}`, `evidence.ex:240-254`) is built from the changeset's
  real Ash actor/context -- never invented ambient authority. By
  default, an actor's own `:capabilities` field (if present) is used
  directly; pass `authority_from: fun` (arity 1, changeset -> map) to
  override.

  A BRCE refusal (`{:error, %Ex4pm.Refusal{}}`) becomes a real Ash
  changeset error via `Ash.Changeset.add_error/2` -- the action is
  refused before the underlying Ash mutation ever runs, matching BRCE's
  own real short-circuit (`execute/4` never calls `fun` on refusal,
  `evidence.ex:229`).

  ## Honest scope limitation

  `BRCE.execute/4`'s `fun` argument here is a pure admission placeholder
  (`fn -> :admitted end`), not the real database write -- Ash's own
  action pipeline performs the actual mutation separately, after this
  `before_action` hook returns. This means BRCE's outcome receipt
  reflects real ADMISSION success/failure, not real DB-write
  success/failure; a DB error after admission is not captured in the
  BRCE receipt chain. Wrapping the real Ash mutation itself inside
  `fun` would require calling into Ash's changeset-apply internals from
  a `before_action` hook, which was not attempted this pass -- named
  honestly as a real, unresolved gap rather than silently claimed as
  full DO-authority coverage.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    operation = Keyword.fetch!(opts, :operation)
    authority = authority_for(changeset, opts, context)

    Ash.Changeset.before_action(changeset, fn changeset ->
      subject_hash = Ex4pm.Core.Hash.digest(%{resource: changeset.resource, operation: operation})

      case Ex4pm.Evidence.BRCE.execute(subject_hash, operation, authority, fn -> :admitted end) do
        {:ok, %{receipt: receipt}} ->
          Ash.Changeset.put_context(changeset, :ash_ex4pm_brce_receipt, receipt)

        {:error, %Ex4pm.Refusal{} = refusal} ->
          Ash.Changeset.add_error(changeset, field: :base, message: refusal.message)

        {:error, %{error: _error, receipt: receipt}} ->
          Ash.Changeset.put_context(changeset, :ash_ex4pm_brce_receipt, receipt)
          |> Ash.Changeset.add_error(field: :base, message: "BRCE-gated operation failed")
      end
    end)
  end

  defp authority_for(changeset, opts, context) do
    case Keyword.get(opts, :authority_from) do
      fun when is_function(fun, 1) ->
        fun.(changeset)

      nil ->
        actor = context.actor

        cond do
          is_map(actor) and Map.has_key?(actor, :capabilities) ->
            %{capabilities: normalize_capabilities(actor.capabilities)}

          is_map(actor) and Map.has_key?(actor, "capabilities") ->
            %{capabilities: normalize_capabilities(actor["capabilities"])}

          true ->
            %{}
        end
    end
  end

  # `Ex4pm.Evidence.BRCE.admit/2` evaluates `:do in capabilities` directly
  # (`ex4pm/lib/ex4pm/evidence.ex:245`), which raises for any non-list right-hand
  # side (Protocol.UndefinedError / BadMapError). A malformed or attacker-controlled
  # actor (e.g. a JSON-decoded actor whose `capabilities` came through as a bare
  # string) must never crash this `before_action` hook with an unhandled exception
  # -- it must always resolve to a controlled BRCE refusal instead. Normalize any
  # non-list value to `[]` here, before the authority map is ever built.
  defp normalize_capabilities(capabilities) when is_list(capabilities), do: capabilities
  defp normalize_capabilities(_capabilities), do: []
end
