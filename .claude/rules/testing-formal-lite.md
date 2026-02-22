# Testing Rule: Lightweight Formal Verification

## Objective
Adopt high-ROI formal rigor without heavy proof tooling.

## Required Checks
- Property-based tests for FC/IS core invariants.
- Contract tests for boundary parsing/serialization contracts.
- Regression tests for previously failing counterexamples.

## Invariant Examples
- Idempotency
- Round-trip consistency
- Invariant preservation
- Monotonic behavior where expected

## Scope for v1
- Mandatory: property-based + contract tests.
- Optional (v2+): model checking for high-risk protocols.
