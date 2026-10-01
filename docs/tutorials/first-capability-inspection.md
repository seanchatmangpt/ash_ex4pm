# Tutorial: inspect your first AshEx4pm capability

This tutorial inspects the capability graph without executing WASM, a planner,
or an Ash mutation.

Start an IEx session:

~~~bash
iex -S mix
~~~

List all projected capabilities:

~~~elixir
AshEx4pm.capabilities()
~~~

Filter to ferroplan-owned projections:

~~~elixir
AshEx4pm.capabilities(owner: :ferroplan)
~~~

Inspect one descriptor:

~~~elixir
{:ok, capability} = AshEx4pm.capability(:ferroplan_plan)

capability.owner
# => :ferroplan

capability.boundary
# => :construct

capability.do_authority?
# => false
~~~

Check whether the Ash-facing function exists:

~~~elixir
AshEx4pm.Capabilities.available?(:ferroplan_plan)
~~~

Then inspect evidence-bounded standing:

~~~elixir
AshEx4pm.capability_standing(:ferroplan_plan)
~~~

The important result is not a particular standing atom. It is that capability
discovery, projection availability and runtime standing remain separate
questions. No call in this tutorial performs a business mutation.
