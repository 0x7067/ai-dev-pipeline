---
name: requirement-analysis
description: Use when the user reports a bug, test failure, regression, unexpected behavior, or a new feature/spec request — phrases like "fix this bug", "this is broken", "something's off", "add a feature for…", "how should we handle…", "design a spec for…" — before proposing any fix or implementation. Produces FC/IS-aligned specs with parse-at-boundary contracts.
---

# Requirement Analysis

## Inputs

- Feature request, bug report, or change objective.
- Existing code and architecture context.

## Workflow

### Step 1: Scope and Impact

- Identify all modules impacted by the change.
- Classify each as `core`, `shell`, or `boundary`.
- Set risk tier (`low | medium | high`) with rationale.

```
| Module | Layer | Impact | Risk |
|--------|-------|--------|------|
| src/core/pricing.py | core | New discount logic | low |
| src/boundary/api.py | boundary | New request parser | medium |
| src/shell/handler.py | shell | Wire new endpoint | low |
```

### Step 2: Boundary Enumeration

For every external ingress/egress point touched by this change:

```
| Boundary | Direction | Parser needed | Domain type |
|----------|-----------|--------------|-------------|
| POST /orders | ingress | parse_order() | Order |
| DB read: users | ingress | parse_user_row() | User |
| webhook callback | egress | serialize_event() | OrderEvent |
```

- Each ingress must have a parser producing a typed domain value.
- Each egress must have a serializer from domain types.

### Step 3: Acceptance Criteria and Invariants

Define what "done" means in testable terms:

```
Acceptance criteria:
- [ ] Discount is applied to all eligible line items.
- [ ] Discount never exceeds original item price (invariant: 0 ≤ result ≤ price).
- [ ] Invalid discount percentage (< 0 or > 100) is rejected at boundary.

Invariants for property-based tests:
- apply_discount(price, 0) == price           (identity)
- apply_discount(price, pct) <= price          (bounded)
- apply_discount(apply_discount(p, a), b) == apply_discount(p, a+b)  (if composable)
```

### Step 4: Testing Scope

Map tests to layers:

| Layer | Test type | What to cover |
|-------|-----------|--------------|
| Core | Unit + property-based | Discount calculation invariants |
| Boundary | Contract | parse_order accept/reject, round-trip |
| Shell | Integration | Endpoint wiring, DB interaction |

### Step 5: Write Output Artifacts

Produce the deliverables below.

## Output Artifacts

- `docs/current-plan.md` — implementation plan with steps, layer classification, and verification order.
- `docs/specs/<feature>.md` — feature spec with sections matching Steps 1-4 above.

### Plan Template

```markdown
# Plan: <Feature Name>

## Risk Tier: low | medium | high
Rationale: ...

## Impacted Modules
(Step 1 table)

## Boundary Map
(Step 2 table)

## Acceptance Criteria
(Step 3 checklist)

## Invariants
(Step 3 invariant list)

## Testing Scope
(Step 4 table)

## Implementation Sequence
1. Add boundary parser → verify: contract tests pass
2. Add core logic → verify: property-based tests pass
3. Wire shell → verify: integration test passes
4. Review → verify: no blocking findings

## Human Approval Checkpoints
- [ ] Plan approved before implementation
- [ ] Elevated-risk changes approved before finalization (required for medium and high risk)
```

## Guardrails

- Do not permit raw external data in core logic.
- Explicitly document parser points for each boundary.
- Every acceptance criterion must be verifiable by a test.
- Risk tier must include rationale, not just a label.
