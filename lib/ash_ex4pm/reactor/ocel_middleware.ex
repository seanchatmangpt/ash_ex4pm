defmodule AshEx4pm.Reactor.OcelMiddleware do
  @moduledoc """
  Canonical `Reactor.Middleware` bridging Reactor step/run lifecycle transitions
  into IEEE OCEL 2.0-aligned `:telemetry` events.

  Emits:
  - `[:ash_ex4pm, :reactor, :event]` carrying `%{event: event, step: step_name, context: context}`
  - `[:ash_ex4pm, :reactor, :complete]` carrying `%{result: result, context: context}`
  - `[:ash_ex4pm, :reactor, :error]` carrying `%{errors: errors, context: context}`
  - `[:ash_ex4pm, :reactor, :halt]` carrying `%{context: context}`
  """

  use Reactor.Middleware

  @impl true
  def init(context), do: {:ok, context}

  @impl true
  def complete(result, context) do
    :telemetry.execute(
      [:ash_ex4pm, :reactor, :complete],
      %{system_time: System.system_time()},
      %{result: result, context: context}
    )

    {:ok, result}
  end

  @impl true
  def error(errors, context) do
    :telemetry.execute(
      [:ash_ex4pm, :reactor, :error],
      %{system_time: System.system_time()},
      %{errors: errors, context: context}
    )

    :ok
  end

  @impl true
  def event(event, step, context) do
    :telemetry.execute(
      [:ash_ex4pm, :reactor, :event],
      %{system_time: System.system_time()},
      %{event: event, step: step.name, context: context}
    )

    :ok
  end

  @impl true
  def halt(context) do
    :telemetry.execute(
      [:ash_ex4pm, :reactor, :halt],
      %{system_time: System.system_time()},
      %{context: context}
    )

    {:ok, context}
  end
end
