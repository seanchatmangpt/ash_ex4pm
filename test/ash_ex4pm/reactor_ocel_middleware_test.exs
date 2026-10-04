defmodule AshEx4pm.Reactor.OcelMiddlewareTest do
  @moduledoc """
  Chicago non-mock verification that `AshEx4pm.Reactor.OcelMiddleware` bridges
  real Reactor step/run lifecycle events onto `:telemetry`.
  """
  use ExUnit.Case, async: true

  defmodule DoubleStep do
    @moduledoc false
    use Reactor.Step

    @impl true
    def run(%{value: value}, _context, _options), do: {:ok, value * 2}
  end

  defmodule SampleReactor do
    @moduledoc false
    use Reactor

    middlewares do
      middleware(AshEx4pm.Reactor.OcelMiddleware)
    end

    input(:value)

    step :double, DoubleStep do
      argument(:value, input(:value))
    end

    return(:double)
  end

  test "emits [:ash_ex4pm, :reactor, ...] telemetry events on Reactor.run/2" do
    ref = make_ref()
    test_pid = self()
    handler_id = "ash-ex4pm-reactor-ocel-test-#{inspect(ref)}"

    :telemetry.attach_many(
      handler_id,
      [
        [:ash_ex4pm, :reactor, :complete],
        [:ash_ex4pm, :reactor, :event]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
      end,
      nil
    )

    try do
      assert {:ok, 8} = Reactor.run(SampleReactor, %{value: 4})
      assert_receive {:telemetry_event, ^ref, [:ash_ex4pm, :reactor, :event], _meas, %{step: :double}}, 1000
      assert_receive {:telemetry_event, ^ref, [:ash_ex4pm, :reactor, :complete], _meas, %{result: 8}}, 1000
    after
      :telemetry.detach(handler_id)
    end
  end
end
