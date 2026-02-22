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
