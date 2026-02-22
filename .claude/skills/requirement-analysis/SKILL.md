---
name: requirement-analysis
description: Analyze feature requirements and produce implementation specs aligned with FC/IS and strict boundary parsing. Use when planning a new feature, analyzing a bug report, or producing implementation specs.
---

# Requirement Analysis

## Inputs
- Feature request, bug report, or change objective.
- Existing code and architecture context.

## Steps
1. Identify impacted modules and classify each as `core`, `shell`, or `boundary`.
2. Enumerate external ingress/egress boundaries and required parsers.
3. Define acceptance criteria and invariants.
4. Define testing scope: unit, property-based, contract, integration.
5. Write output artifacts.

## Output Artifacts
- `docs/current-plan.md`
- `docs/specs/<feature>.md`

## Guardrails
- Do not permit raw external data in core logic.
- Explicitly document parser points for each boundary.
