# ash_ex4pm: Lane 3 — BRCE Receipted Action Court & Invariant Proofs

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Leslie Lamport (Formal Systems & Distributed Invariants Specialist)
- Source: `lib/ash_ex4pm/changes/brce_gate.ex:1-156`, `lib/ash_ex4pm/changes/receipted_action.ex:1-361`, `test/ash_ex4pm/evidence_court.exs:1-127`
- Evidence: Formal proof analysis of around_action hooks in `receipted_action.ex`; evidence court verifies 5 invariant properties (tamper evidence, digest stability, duplicate idempotency).

## Context & Objectives

In safety-critical distributed systems, execution without a receipt is an unverified hypothesis. The BRCE (Bound, Refused, Consequential Execution) paradigm formalizes two distinct mathematical transitions:

$$\text{Admission} \neq \text{Execution}$$
$$\text{Actuation}(\text{intent}) \xrightarrow{\text{BRCE}} \text{Receipt}(\text{consequence})$$

1. **Admission vs Actuation Invariant**:
   - `AshEx4pm.Changes.BrceGate` acts strictly as an admission gate (`before_action`). It verifies prerequisites, standing, and authority leases. If admitted, it records an admission receipt in changeset context; if refused, it halts the pipeline without side-effects.
   - `AshEx4pm.Changes.ReceiptedAction` acts as the execution and actuation seam (`around_action`). It executes the real state modification inside `Ex4pm.Evidence.BRCE.execute/5` and binds the resulting record digest directly into the cryptographic `artifact_hash`.

2. **Idempotency Key Liveness & Fault Containment**:
   - Analysis of `lib/ash_ex4pm/changes/receipted_action.ex:120-156` reveals that `ReceiptStore.release(claim, store)` is only invoked if `execute/7` returns `{:error, reason}` cleanly.
   - If an unhandled exception, exit signal, or timeout occurs during the in-transaction hook, `release/2` is bypassed, leaving the idempotency key permanently trapped in `{:in_flight, pid, claimed_at}` in ETS.
   - This represents an invariant violation: **A crashed execution must never leave a permanent lock on future retries.**

3. **Transactional Boundary Guard**:
   - Receipts are currently sealed inside the `around_action` callback. On transactional relational backends (e.g., PostgreSQL), a post-hook commit failure would seal the receipt in ETS while the DB row rolls back.
   - Formally document the boundary guarantee: ETS-backed actions provide atomic commit guarantees, while multi-node RDBMS backends require post-commit hooks via `Ash.Changeset.after_transaction/2`.

## Work to complete

1. Refactor `lib/ash_ex4pm/changes/receipted_action.ex` to guarantee idempotency claim cleanup:
   - Wrap `execute_around/4` execution in `try ... after`:
     ```elixir
     case store.claim(fingerprint, action_spec, claim_opts) do
       {:ok, claim} ->
         try do
           run(claim, changeset, instructions, store, opts)
         after
           # If claim is still in_flight (due to crash or unhandled throw), release it
           if store.status(fingerprint, opts) == :in_flight do
             store.release(claim, store)
           end
         end
     ```
2. Ensure process dictionary slot cleanup (`Process.delete(slot)`) is strictly executed in an `after` block to prevent term leakage in pooled worker processes.
3. Formalize the 5 invariant properties verified by `evidence_court.exs`:
   - Property 1 (Validity): Fresh envelopes validate through upstream schema.
   - Property 2 (Deterministic Digest): Canonical JSON serialization produces stable SHA-256 digests.
   - Property 3 (Tamper Evidence): Any 1-bit mutation in envelope payload flips the content digest.
   - Property 4 (Idempotent Deduplication): Identical events produce identical content digests.
   - Property 5 (Fail-Closed Refusal): Malformed or unauthorized events are rejected by the validator.
4. Convert `test/ash_ex4pm/evidence_court.exs` into a standard ExUnit test suite (`test/ash_ex4pm/evidence_court_test.exs`) to eliminate Mix filter warnings while retaining standalone executable capability.

## Acceptance

- Process crashes during `ReceiptedAction` do not leak `:in_flight` claims or process dictionary slots.
- Duplicate action invocations with identical parameters replay cached receipts with `:known_replay`.
- Divergent parameter invocations with identical idempotency keys are refused with `:idempotency_conflict`.
- All 5 formal invariant properties pass deterministically under ExUnit and standalone script execution.

## History

- 2026-11-11 | OPEN | survey finding | formal invariant proofs and claim liveness specification formulated by Leslie Lamport.
