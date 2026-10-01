# Architecture and authority boundaries

AshEx4pm v26.10.2 makes an already-existing runtime topology explicit.

~~~text
PUBLIC SEMANTICS
      |
 +----+-----+
 |          |
 v          v
wasm4pm  ferroplan
 |          |
 +----+-----+
      |
      v
    ex4pm
 runtime / evidence / admission / replay
      |
      v
  AshEx4pm
 projection / DSL / notifier / Ash changes
      |
  +---+------------------+
  |                      |
  v                      v
OBSERVE / ANALYZE     CONSTRUCT
  |                      |
  +----------+-----------+
             |
      explicit authority
             |
             v
            DO
~~~

## Semantic ownership

wasm4pm owns its process-intelligence, cognition and portable compute
semantics. ferroplan owns planning semantics. ex4pm owns provider admission,
runtime integration, receipts, replay and the execution boundary. AshEx4pm
does not recreate any of those systems; it projects them into Ash.

## BrceGate versus ReceiptedAction

These are deliberately separate.

BrceGate is admission-only. It uses BRCE with a pure admission placeholder
before the Ash mutation. Its receipt proves the admission decision.

ReceiptedAction installs an outermost around_action and runs the actual Ash
mutation as the BRCE callback. Its outcome receipt therefore binds the
consequence digest. Subject checks and idempotency are part of that seam.

The remaining qualification boundary is transactional commit behavior after
around_action returns. The implementation documents that as unverified for
transactional data layers rather than generalizing from ETS.

## Planner boundary

FerroplanRuntime and FerroplanSessions are CONSTRUCT-side seams. Their output
does not mutate business state. This stays true even when the planner itself is
healthy and its artifact is admitted.

## Standing boundary

Code presence is not ALIVE. The registry therefore distinguishes static
projection metadata from runtime standing callbacks. A capability without a
runtime standing probe stays PROJECTED rather than being promoted by prose.
