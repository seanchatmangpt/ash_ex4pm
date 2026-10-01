# How to inspect runtime standing

Use the capability registry when you need to know whether a capability is
known to AshEx4pm, then use standing only where the projection exposes an
inspection-only standing callback.

## 1. Confirm projection

~~~elixir
{:ok, capability} = AshEx4pm.capability(:wasm_algorithms)
AshEx4pm.Capabilities.available?(capability)
~~~

available?/1 checks the Ash-facing module/function/arity. It does not execute
the upstream capability and does not promote it to ALIVE.

## 2. Ask for standing

~~~elixir
AshEx4pm.capability_standing(:wasm_algorithms)
~~~

For WasmRuntime this delegates to its inspection-only standing path. For a
capability without a standing callback the result is PROJECTED with an
explanation rather than an invented ALIVE claim.

## 3. Keep authority separate

A planning capability may be available and ALIVE while still declaring:

~~~elixir
capability.boundary == :construct
capability.do_authority? == false
~~~

That is expected. Planning produces candidates.

For consequential Ash mutation, use the separately registered
receipted_action capability and AshEx4pm.Changes.ReceiptedAction.
