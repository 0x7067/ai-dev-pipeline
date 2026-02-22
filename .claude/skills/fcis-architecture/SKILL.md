---
name: fcis-architecture
description: Apply Functional Core / Imperative Shell architecture and enforce parse-at-boundary design. Use when classifying code into core/shell/boundary layers, designing new modules, or enforcing separation of side effects.
---

# FC/IS Architecture

## Objective
Keep business decisions deterministic and side effects isolated.

## Rules
- Core is pure and deterministic.
- Shell handles side effects and orchestration.
- Boundary parses untrusted input into trusted domain types.
- Time/random/id are passed in, not read from ambient APIs in core.

## Deliverable Expectations
- Every proposed change includes layer classification.
- Core invariants are listed for property-based testing.
- Boundary parsers are identified before implementation.

## References
- https://www.destroyallsoftware.com/talks/boundaries
- https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/
