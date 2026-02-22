---
description: Refactor code without behavior change — with pre/post verification gates and human approval.
agents:
  - planner
  - implementer
  - reviewer
  - verifier
context: fork
---

Execute refactoring workflow. The invariant is **no behavior change**.

1. Run pre-refactor verification gate: `bash scripts/run-verification-gates.sh`. Abort if any gate fails — a clean baseline is required.
2. Run `planner` with refactor framing. Output: `docs/current-plan.md`. Plan must describe structural changes only; any functional diff is a blocking violation.
3. Pause for explicit human plan approval before any code edits.
4. Run `implementer`.
5. Run `reviewer`. Confirm diff is structural-only; if a behavior change is detected, treat as blocking and halt.
6. Run `verifier` (post-refactor gate).

Stop immediately on any unresolved blocking finding.
