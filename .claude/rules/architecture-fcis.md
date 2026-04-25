# Architecture Rule: Functional Core / Imperative Shell

## Objective
Separate business logic from side effects to improve correctness and reuse.

## Layer Definitions
- `core`: pure, deterministic business logic.
- `shell`: I/O, framework bindings, network, storage, process interactions.
- `boundary`: parsing/decoding/encoding layer between untrusted data and domain values.

## Mandatory Constraints
- Core never imports shell modules.
- Core functions do not read ambient state or perform I/O.
- Core accepts explicit parameters for time/random/id generation.
- Shell orchestrates calls and executes side effects.

## Verification Expectations
- Core logic must be unit/property testable in isolation.
- Shell is validated mostly through integration tests.

## Language Examples

- Python: `@examples/python/fcis_layers.py`, `@examples/python/end_to_end_scenario.py`
- Go: `@examples/go/fcis_layers.go`, `@examples/go/end_to_end_scenario.go`
- Rust: `@examples/rust/fcis_layers.rs`, `@examples/rust/end_to_end_scenario.rs`
- TypeScript: `@examples/typescript/fcis-layers.ts`, `@examples/typescript/end-to-end-scenario.ts`
