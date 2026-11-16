# ash_ex4pm: Lane 6 — Concurrency, OTP Supervision & ETS Storage Architecture

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Joe Armstrong (Erlang Co-Creator & Concurrency Specialist)
- Source: `mix.exs:27-31`, `lib/ash_ex4pm/receipt_store/ets.ex:1-125`, `test/test_helper.exs:7-14`
- Evidence: Survey 2 revealed `ash_ex4pm` lacks an `Application` callback; `test_helper.exs` uses imperative `start_link` to start background ETS stores; missing caller monitoring allows abandoned `:in_flight` claims to deadlock retries.

## Context & Objectives

In Erlang and OTP philosophy:
> "Make it work, then make it beautiful, then if you really, really have to, make it fast. Ninety percent of the time, if the architecture is right, it will already be fast enough."

During the architectural audit of `ash_ex4pm`, four critical concurrency and supervision gaps were uncovered:

1. **No Top-Level Application Callback**:
   - `mix.exs` defines `extra_applications: [:logger]`, but lacks `mod: {AshEx4pm.Application, []}`.
   - Consequently, the core ETS table owner `AshEx4pm.ReceiptStore.Ets` is not supervised by default. If a consuming application fails to imperatively start `AshEx4pm.ReceiptStore.Ets`, every receipted action fails immediately with an unhandled exit.
2. **Missing Caller Monitoring in `ReceiptStore.Ets`**:
   - `ReceiptStore.claim/3` marks a fingerprint as `{:in_flight, pid, claimed_at}`.
   - If that caller process crashes or is killed by a timeout or supervisor before invoking `commit/3` or `release/2`, the fingerprint remains trapped in `:in_flight` forever, permanently blocking all subsequent requests.
   - `ReceiptStore.Ets` must monitor the claimant process via `Process.monitor/1` and automatically release the claim upon `{:DOWN, ref, :process, pid, reason}`.
3. **Elimination of Imperative Test Bootstrapping**:
   - `test/test_helper.exs` contains imperative workarounds:
     ```elixir
     unless Process.whereis(AshEx4pm.ReceiptStore.Ets) do
       {:ok, _} = AshEx4pm.ReceiptStore.Ets.start_link()
     end
     ```
   - With a proper supervision tree, the OTP runtime starts all dependencies automatically upon application boot.

## Work to complete

1. Create `lib/ash_ex4pm/application.ex` implementing `use Application`:
   ```elixir
   defmodule AshEx4pm.Application do
     @moduledoc false
     use Application

     @impl true
     def start(_type, _args) do
       children = [
         {AshEx4pm.ReceiptStore.Ets, []},
         {Task.Supervisor, name: AshEx4pm.TaskSupervisor}
       ]

       opts = [strategy: :one_for_one, name: AshEx4pm.Supervisor]
       Supervisor.start_link(children, opts)
     end
   end
   ```
2. Update `mix.exs:application/0` to declare `mod: {AshEx4pm.Application, []}`.
3. Enhance `AshEx4pm.ReceiptStore.Ets`:
   - Store claimant monitor references: `monitors = Map.put(state.monitors, pid, ref)`.
   - Implement `handle_info({:DOWN, ref, :process, pid, _reason}, state)`: scan the `:in_flight` ETS entries for the matching PID and release them cleanly.
   - Add property-based stress tests verifying that killing 50 concurrent claimants simultaneously releases all 50 locks within 50ms without orphan retention.
4. Clean up `test/test_helper.exs` by removing redundant imperative `start_link` calls.

## Acceptance

- `Application.spec(:ash_ex4pm, :mod)` returns `{AshEx4pm.Application, []}`.
- Killing a claimant process holding an `:in_flight` claim immediately clears the claim in ETS.
- Test suite boots cleanly without manual `start_link` calls in `test_helper.exs`.
- Zero orphaned tables or memory leaks under 100 concurrent worker stress runs.

## History

- 2026-11-11 | OPEN | survey finding | OTP application and supervision tree specification authored by Joe Armstrong.
