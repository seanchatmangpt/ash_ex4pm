defmodule AshEx4pm.Changes.RunEngine do
  @moduledoc """
  CONSTRUCT-only change: runs the real ex4pm analytical operation for the
  create action and persists the resulting `%Ex4pm.Run{}` envelope.

  Option `:operation` is one of `:discover | :conform | :simulate | :optimize | :plan`.
  Arguments consumed: `:subject`, `:model`, `:problem`, `:engine_opts`.

  A refusal (`{:error, term}` from ex4pm) becomes an `AshEx4pm.Errors.Refused`
  added in `before_action`, so no row is written. There is no BRCE / DO path.
  """
  use Ash.Resource.Change

  alias AshEx4pm.Errors.Refused

  @operations [:discover, :conform, :simulate, :optimize, :plan]

  @impl true
  def change(changeset, opts, _ctx) do
    operation = Keyword.fetch!(opts, :operation)

    unless operation in @operations do
      raise ArgumentError, "unsupported operation #{inspect(operation)}"
    end

    Ash.Changeset.before_action(changeset, fn cs ->
      case run(operation, cs) do
        {:ok, %Ex4pm.Run{} = run} -> persist(cs, run)
        {:error, reason} -> Ash.Changeset.add_error(cs, refused(reason))
      end
    end)
  end

  defp run(operation, cs) do
    subject = Ash.Changeset.get_argument(cs, :subject)
    model = Ash.Changeset.get_argument(cs, :model)
    problem = Ash.Changeset.get_argument(cs, :problem)
    opts = Ash.Changeset.get_argument(cs, :engine_opts) || []

    case operation do
      :discover -> Ex4pm.discover(subject, opts)
      :conform -> Ex4pm.conform(subject, model, opts)
      :simulate -> Ex4pm.simulate(model, opts)
      :optimize -> Ex4pm.optimize(subject, model, opts)
      :plan -> Ex4pm.plan(problem, opts)
    end
  end

  defp persist(cs, %Ex4pm.Run{} = run) do
    engine_result = run.engine_result

    cs
    |> Ash.Changeset.force_change_attribute(:operation, run.operation)
    |> Ash.Changeset.force_change_attribute(:engine, engine_result && engine_result.engine)
    |> Ash.Changeset.force_change_attribute(
      :algorithm,
      engine_result && engine_result.algorithm
    )
    |> Ash.Changeset.force_change_attribute(:subject_hash, run.subject_hash)
    |> Ash.Changeset.force_change_attribute(:standing, run.standing)
    |> Ash.Changeset.force_change_attribute(:value, run.value)
    |> Ash.Changeset.force_change_attribute(:receipt_hash, run.receipt.hash)
    |> Ash.Changeset.force_change_attribute(:pending_hash, run.pending && run.pending.hash)
    |> Ash.Changeset.force_change_attribute(
      :evidence,
      (engine_result && engine_result.evidence) || %{}
    )
  end

  defp refused(%Ex4pm.Refusal{code: code} = refusal),
    do: Refused.exception(reason: code, refusal: refusal)

  defp refused(other), do: Refused.exception(reason: other, refusal: nil)
end
