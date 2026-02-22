---
name: test-gen
description: Generate tests with a focus on property-based core invariants and boundary contract behavior.
---

# Test Generation

## Strategy
- Core: unit + property-based tests.
- Boundary: contract tests for parse accept/reject and round-trip behavior.
- Shell: integration tests for orchestration and wiring.

## Steps
1. List invariants for each core function.
2. Define data generators for valid/invalid inputs.
3. Add contract tests per boundary parser.
4. Add targeted regression tests for known failures.

## Output
- `docs/test-report.md` with coverage summary and failures.
