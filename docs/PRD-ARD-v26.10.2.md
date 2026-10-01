# AshEx4pm v26.10.2 PRD/ARD

Status: IMPLEMENTED by the v26.10.2 capability/Diátaxis change.

## Product objective

Make the actual AshEx4pm capability graph explicit, navigable and
machine-readable while preserving semantic ownership and authority boundaries.

The release does not add a second wasm or planner implementation.

## Required outcomes

1. README represents wasm4pm and ferroplan projection surfaces already in code.
2. A Diátaxis index routes tutorial, how-to, reference and explanation needs.
3. A canonical capability registry records owner, projection, boundary,
   authority, DO capability, standing probe and documentation.
4. Planning remains CONSTRUCT-only.
5. BrceGate remains admission-only.
6. ReceiptedAction is documented as the real BRCE-wrapped Ash mutation seam.
7. Runtime standing is evidence-bounded and separate from code presence.
8. The exact ex4pm dependency pin remains unchanged unless an upstream contract
   is independently verified.

## Architecture

~~~text
Ash
 -> AshEx4pm projection
 -> ex4pm admitted runtime
 -> wasm4pm / ferroplan semantics
~~~

Consequential execution is not inferred from that chain. The relevant
AshEx4pm change must explicitly cross the authority boundary.

## Capability states

~~~text
KNOWN -> PROJECTED -> AVAILABLE -> ADMITTED -> ALIVE
                                  |
                                  +-- no implication to AUTHORIZED or DO
~~~

Transitions are descriptive, not automatic implications.

## v26.10.2 implementation

- AshEx4pm.Capability descriptor.
- AshEx4pm.Capabilities registry.
- AshEx4pm.capabilities/1, capability/1 and capability_standing/1.
- Federated docs/INDEX.md.
- Four-quadrant Diátaxis starter documents.
- README architecture and capability navigation.
- Registry tests proving unique IDs, real exports, documentation coverage and
  planner/DO separation.
- Package version bump to 26.10.2.
- Exact ex4pm 26.10.1 dependency retained because no newer upstream contract is
  assumed by this release.

## Falsifiers

The release claim is false if:

- a registered projection function does not exist;
- duplicate capability IDs exist;
- a capability has no reference/explanation documentation;
- a ferroplan projection declares DO authority;
- BrceGate is described as the actual mutation receipt seam;
- ReceiptedAction is described as admission-only;
- an upstream capability is claimed ALIVE solely because code exists.

CI tests the first four mechanically; documentation encodes the remaining
boundary distinctions.

## Remaining boundary

ReceiptedAction seals its receipt within Ash around_action. A commit failure
after around_action returns remains unverified for transactional data layers.
This is narrower than the old README gap: the real mutation itself is already
inside BRCE.execute/5.
