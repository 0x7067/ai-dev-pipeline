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

## Language Examples

- Python: `@examples/python/property_tests.py`, `@examples/python/contract_tests.py`, `@examples/python/anti_patterns.py`
- Go: `@examples/go/property_tests_test.go`, `@examples/go/contract_tests_test.go`, `@examples/go/anti_patterns.go`
- Rust: `@examples/rust/property_tests.rs`, `@examples/rust/contract_tests.rs`, `@examples/rust/anti_patterns.rs`
- TypeScript: `@examples/typescript/property-tests.ts`, `@examples/typescript/contract-tests.ts`, `@examples/typescript/anti-patterns.ts`
