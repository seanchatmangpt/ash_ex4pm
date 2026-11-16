# ash_ex4pm: Lane 7 — Realtime Telemetry, Reactor Middleware & Ring Buffer Architecture

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Chris McCord (Phoenix Framework Creator & Realtime Specialist)
- Source: `lib/ash_ex4pm/evidence/realtime_bridge.ex:1-150`, `lib/ash_ex4pm/reactor/ocel_middleware.ex:1-61`, `lib/ash_ex4pm/notifier.ex:11, 42-78`
- Evidence: `RealtimeBridge` uses `:persistent_term` for active event ring buffering; `Notifier` moduledoc confirms broadcaster crashes bubble up through caller transactions as `Ash.Error.Unknown`.

## Context & Objectives

As the creator of Phoenix and Phoenix LiveView, high-throughput, low-latency concurrent message dispatch is fundamental to my engineering philosophy. Two severe anti-patterns exist in `ash_ex4pm`'s event dispatch pipeline:

1. **Catastrophic `:persistent_term` Misuse in `RealtimeBridge`**:
   - In `lib/ash_ex4pm/evidence/realtime_bridge.ex`, the event ring buffer is stored in `:persistent_term`:
     ```elixir
     @persistent_term_key {__MODULE__, :ring}

     def push(event) do
       cur = :persistent_term.get(@persistent_term_key, default_state())
       :persistent_term.put(@persistent_term_key, %{cur | pending: :queue.in(event, cur.pending)})
     end
     ```
   - `:persistent_term` is intended for terms that almost never change (e.g. routing tables). Writing to `:persistent_term` on every event forces the BEAM VM to perform a global stop-the-world garbage collection pass across all process heaps on the node.
   - Furthermore, `push/1` is an uncoordinated read-modify-write without CAS locks. Concurrent calls from multiple worker processes silently drop events.
   - Eviction currently converts the entire buffer to a list with `:ets.tab2list/1` and sorts it in memory on every push.

2. **Broadcaster Failure Bubbling in `Notifier`**:
   - `AshEx4pm.Notifier.notify/1` executes synchronously on the caller's process post-commit.
   - If an external broadcaster (e.g., Phoenix Channel, PubSub, Webhook) crashes, raises an exception, or times out, the exception bubbles up through the Ash action and raises `Ash.Error.Unknown`, causing callers to believe the action failed even though the database transaction committed.

3. **Reactor Pipeline Telemetry Bridge**:
   - `AshEx4pm.Reactor.OcelMiddleware` provides lifecycle tracing for Reactor workflows (`[:ash_ex4pm, :reactor, :event]`, `:complete`, `:error`, `:halt`). Ensure this telemetry aligns with standard `:telemetry` conventions with zero overhead when detached.

## Work to complete

1. Refactor `lib/ash_ex4pm/evidence/realtime_bridge.ex`:
   - Replace `:persistent_term` with a dedicated GenServer owning an `:ordered_set` ETS table with monotonic 64-bit integer keys.
   - Make `push/1` atomic using `:ets.update_counter/4` for monotonic sequence generation.
   - Replace `:ets.tab2list/1` full table scans with `:ets.first/1` and `:ets.take/2` for $O(1)$ ring buffer eviction.
2. Decouple `AshEx4pm.Notifier` broadcaster dispatch:
   - Provide an option `async_broadcast?: true` to dispatch broadcaster invocations via `Task.Supervisor.start_child/2`.
   - Wrap broadcaster invocations in a `rescue` block that captures errors, emits telemetry event `[:ash_ex4pm, :notifier, :broadcast_error]`, and logs a warning without crashing the caller transaction.
3. Add stress tests in `test/ash_ex4pm/realtime_bridge_test.exs` verifying 10,000 concurrent events pushed from 50 worker processes without dropped events or scheduler latency pauses.

## Acceptance

- Zero occurrences of `:persistent_term` in `lib/ash_ex4pm/evidence/realtime_bridge.ex`.
- Concurrent event writes maintain strict monotonic ordering with $O(1)$ bounded ring eviction.
- External broadcaster exceptions do not bubble up or fail caller Ash actions.
- Reactor middleware telemetry passes all unit tests cleanly.

## History

- 2026-11-11 | OPEN | survey finding | realtime ring buffer and broadcaster decoupling architecture designed by Chris McCord.
