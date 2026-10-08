# Reference: Process-Mining Binding Layers

AshEx4pm binds to the ex4pm process-intelligence engine through three
distinct layers. This page maps each layer to the files that implement it.

## Layer 1 — Core engine (exact-pinned Hex dependency)

`mix.exs:52` pins `{:ex4pm, "== 26.10.1"}` — an exact pin, not a
range. The pin exists because ex4pm's third CalVer component carries
contract changes: each release's CHANGELOG declares its public contract
(`mix.exs:48-51`). The dependency also ships its ontology in the Hex
package (`priv/ontology/ex4pm.ttl`), which this repo re-queries rather
than forking a second copy, avoiding two-repo drift (`mix.exs:54-61`).

Upstream documentation: the ex4pm repo's own Diátaxis reference
(see `docs/diataxis/index.md`, "Canonical upstream documentation").

## Layer 2 — Ash/Reactor middleware and evidence adapter

### Reactor middleware

`AshEx4pm.Reactor.OcelMiddleware`
(`lib/ash_ex4pm/reactor/ocel_middleware.ex:1`) is a `Reactor.Middleware`
that bridges Reactor step/run lifecycle transitions into OCEL 2.0-aligned
`:telemetry` events:

- `[:ash_ex4pm, :reactor, :event]` — per-step events, with `step.name`
  (`lib/ash_ex4pm/reactor/ocel_middleware.ex:41`)
- `[:ash_ex4pm, :reactor, :complete]` (`complete/2`,
  `lib/ash_ex4pm/reactor/ocel_middleware.ex:19`)
- `[:ash_ex4pm, :reactor, :error]` (`:30`)
- `[:ash_ex4pm, :reactor, :halt]` (`:52`)

Verified against real Reactor runs in
`test/ash_ex4pm/reactor_ocel_middleware_test.exs:1` — Chicago-style:
real Reactor steps, real `:telemetry` attach, no mocks.

### Evidence adapter

`AshEx4pm.Evidence.Ex4pmAdapter`
(`lib/ash_ex4pm/evidence/ex4pm_adapter.ex:1`) converts
`AshEx4pm.Evidence.ProcessEvidence.Event` structs into the canonical
`ash_ex4pm/1` wire envelope and admits them through the real ex4pm
functions `Ex4pm.OCEL.validate_envelope/1` and
`Ex4pm.Stream.Ingest.ingest_envelope/2`
(`lib/ash_ex4pm/evidence/ex4pm_adapter.ex:3-7`).

Guarded: when ex4pm is not loadable, every call returns
`{:error, %{reason: :unsupported, detail: :ex4pm_not_available}}`
(`lib/ash_ex4pm/evidence/ex4pm_adapter.ex:9-11,17-19`).

Realtime fan-out is opt-in via app env `:ash_ex4pm` key `:broadcaster`;
the ring-buffer bridge is `AshEx4pm.Evidence.RealtimeBridge`
(`lib/ash_ex4pm/evidence/realtime_bridge.ex:1`), an ETS ring buffer
GenServer with `push/1`, `drain/0`, `size/0`, `capacity/0`
(`lib/ash_ex4pm/evidence/realtime_bridge.ex:34,88,97,100`).

## Layer 3 — WASM embedding path (external sibling)

The WASM `extern "C"` export boundary over the same ex4pm algorithms
lives in the sibling repository wasm4pm, crate
`wasm4pm-ex4pm-bindings` (`~/wasm4pm/crates/wasm4pm-ex4pm-bindings/`).
Phase 1 exports (discover, conform, simulate, optimize, powl_mine) are
hand-written minimal implementations; Phase 2 exports (survival, markov,
bayesian, ocpq_eval, strips_plan, htn_plan, ctl_check, allen_temporal)
are thin wrappers over wasm4pm workspace crates
(`crates/wasm4pm-ex4pm-bindings/Cargo.toml`, package description).

AshEx4pm consumes WASM-embedded analysis through its runtime seam
`lib/ash_ex4pm/wasm_runtime.ex` — see
[Reference: Public API](api.md) and
[Explanation: Architecture](../explanation/architecture.md).
Upstream: wasm4pm index
(<https://github.com/seanchatmangpt/wasm4pm/blob/main/docs/INDEX.md>).

## Vendored evidence pack (generated — not API)

`priv/ggen/vendor/` is a GENERATED tree, produced by
`priv/ggen/vendor/sync.sh` from `PACKS.lock.json` (declared in
`priv/ggen/vendor/provenance.ttl:1`, which records the pack version and
source Git SHA). It is provenance and gate data for the evidence pack,
not a public API surface — do not code against its contents. The live
modules are the Layer 2 files above; see
[Explanation: Architecture](../explanation/architecture.md) for how the
vendored pack fits the ownership layering.

## See Also

- [Reference: Public API](api.md)
- [Explanation: Architecture](../explanation/architecture.md)
- ex4pm reference:
  <https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md>
- wasm4pm index:
  <https://github.com/seanchatmangpt/wasm4pm/blob/main/docs/INDEX.md>
