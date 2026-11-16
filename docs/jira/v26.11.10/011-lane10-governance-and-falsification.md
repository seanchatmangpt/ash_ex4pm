# ash_ex4pm: Lane 10 — Security Governance, POLP Ceilings & Adversarial Falsification

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Security & Governance Auditor (Cryptographic Verification Specialist)
- Source: `lib/ash_ex4pm/capabilities.ex:1-55`, `lib/ash_ex4pm/capability.ex:1-40`, `lib/ash_ex4pm/changes/brce_gate.ex:20-65`, `test/ash_ex4pm/evidence_court.exs:1-127`
- Evidence: Evidence court enforces 5 security invariants; capabilities module tracks standing (`:alive | :candidate | :refused`); authority leases require explicit grants.

## Context & Objectives

In autonomic distributed software systems, safety depends upon strict enforcement of the Principle of Least Privilege (POLP), immutable audit trails, and fail-closed security gates:

1. **Authority Ceilings & Leases**:
   - Every state transition executed through `AshEx4pm.Changes.BrceGate` or `ReceiptedAction` requires an explicit authority parameter (`authority: authority_spec`).
   - If authority is omitted, `NONE`, or expired, the admission gate must refuse the action with `:unauthorized_operation` before any database or engine interaction occurs.
   - Capability standing must adhere to the formal ontology vocabulary: `:alive`, `:candidate`, `:refused`, or `:blocked`. Storing unverified standing as permanent truth is strictly prohibited.

2. **Tamper-Evident Receipts & Invariant Falsification**:
   - Receipts produced by `AshEx4pm.Changes.ReceiptedAction` must be cryptographically bound to both the input parameters and the resulting record state via SHA-256 digests.
   - An adversarial court (`evidence_court.exs`) must actively test anti-vacuity: mutating even a single character in the event payload or digest must flip the receipt validity and trigger immediate refusal.

3. **Credential Containment**:
   - Verify that no environment secrets, API tokens (e.g. `HEX_API_KEY`), private keys, or internal development credentials are ever committed, logged in telemetry events, or included in package tarballs.

4. **Test Suite Health & Regression Prevention**:
   - Ensure the repository test suite maintains 100% green status across all 128 tests with zero failures under parallel ExUnit execution.

## Work to complete

1. Audit `AshEx4pm.Capabilities` and `AshEx4pm.Changes.BrceGate` for POLP compliance:
   - Ensure that unauthorized callers cannot bypass admission gates by passing empty or malformed authority parameters.
   - Verify that `:refused` responses return typed Ash errors with actionable, sanitized refusal reasons.
2. Formalize adversarial falsification tests in `test/ash_ex4pm/adversarial_court_test.exs`:
   - Test payload bit-flipping on OCEL 2.0 JSON events.
   - Test forged receipt hashes and verify rejection by `ReceiptStore.by_receipt/2`.
   - Test replay attacks where an identical idempotency key is submitted with differing parameters, asserting `:idempotency_conflict` refusal.
3. Perform automated static security scan:
   - Verify zero occurrences of plaintext credentials, private keys, or hardcoded auth tokens across `lib/` and `docs/`.
4. Validate that `mix test` passes 100% of non-skipped tests with zero regressions.

## Acceptance

- All admission gates fail closed when presented with missing or invalid authority credentials.
- Invariant evidence court passes 5/5 anti-tamper tests deterministically.
- Zero credentials or internal secrets leak into build artifacts or documentation.
- Test suite executes cleanly: 128 passed, 0 failed.

## History

- 2026-11-11 | OPEN | survey finding | security governance and adversarial falsification specification established by Security Auditor.
