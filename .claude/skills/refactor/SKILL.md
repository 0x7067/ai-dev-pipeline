---
name: refactor
description: Use when the user says "refactor", "clean up", "restructure", "extract", "rename", "split this up", "tidy up", "this is messy", or otherwise asks to change code shape without changing behavior. Engages pre/post verification gates and human approval before finalizing. Blocks on any observable behavior change. Do not invoke for feature work or bug fixes (use `/cycle`).
---

# Refactor

**Core invariant:** No behavior change. Every observable output before refactoring must remain identical after.

**Default risk tier:** `medium`. Escalate to `high` for cross-module moves, auth/authz paths, or data-integrity logic.

## 1. Scope Analysis

Before any code changes:

1. List every file or symbol targeted for refactoring.
2. Classify each as `core`, `shell`, or `boundary` (per FC/IS rules).
3. Identify all callers and dependents of changed symbols.
4. Note any cross-layer movements — these require extra reviewer scrutiny.

```
# Example scope table
| Symbol | File | Layer | Callers |
|--------|------|-------|---------|
| parseOrder | src/boundary/order.ts:12 | boundary | shell/api.ts:34, shell/queue.ts:88 |
| applyDiscount | src/core/pricing.ts:45 | core | shell/checkout.ts:20 |
```

If scope is unclear, stop and ask before proceeding.

## 2. Pre-Refactor Gate

Run the canonical verification gate to establish a clean baseline:

```bash
bash scripts/run-verification-gates.sh
```

**Abort if any gate fails.** A failing baseline means tests or types are already broken. Fix the baseline before refactoring — do not proceed with a dirty starting state.

Record baseline results (pass/fail per gate) in `docs/refactor-report.md`.

## 3. Planning

Produce `docs/current-plan.md` with:

- What structural changes will be made (rename, extract, move, inline, etc.)
- Which FC/IS layers are touched and whether any cross-layer movement occurs
- A list of all affected call sites and how they will be updated
- Explicit statement that no functional diff is intended

The plan must not introduce new behavior, new error handling for new scenarios, or new abstractions beyond what is needed for the structural goal.

## 4. Human Approval Gate

**Stop here. Do not write any code until the human approves the plan.**

Present the scope table and `docs/current-plan.md` to the user. Wait for explicit approval. If rejected, revise the plan and re-present.

## 5. Implementation

Apply the approved structural changes:

- Rename/move/extract as planned.
- Update all call sites identified in scope analysis.
- Do not add new logic, new error handling, or new tests for new behavior.
- If a previously untested invariant is exposed during refactoring, note it in the report but do not add tests for new behavior — only add tests that verify the existing behavior is preserved.

The `implementer` agent handles any preservation tests inline; the `tester` agent is intentionally excluded from this workflow since no new behavior is being added.

## 6. Post-Refactor Gate

Run the same verification gate:

```bash
bash scripts/run-verification-gates.sh
```

All gates that passed in the baseline must still pass. No new failures are acceptable.

**If any gate regresses:** treat as blocking, revert the change that caused the regression, and resolve before continuing.

Compare the structural diff:
- `git diff --stat -M` should show only renamed/moved/restructured files.
- No new exported symbols with new behavior.
- No removed safety checks or error paths.

## 7. Output

Write `docs/refactor-report.md` using template: `docs/templates/refactor-report-template.md`.

## Blocking Conditions

- Pre-refactor gate fails → abort before any code changes.
- Behavior change detected in review → halt and revert.
- Post-refactor gate regresses any previously passing check → blocking.
- Cross-layer move that violates FC/IS (e.g., core now imports shell) → blocking.
