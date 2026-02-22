---
description: Auto-run optional research and full delivery chain with approval gates.
agents:
  - researcher
  - planner
  - implementer
  - reviewer
  - tester
  - verifier
context: fork
---

Execute sequential phases:
1. Ask the user whether to run research before planning.
2. Infer a recommendation using risk+scope signals:
   - Risk signals: security/auth/authz, data integrity, release-critical behavior, cross-module refactor.
   - Scope signals: multi-system changes, unclear requirements, boundary parser updates across multiple ingress points.
3. Recommend research when risk or scope is elevated; recommend skipping when both are low and scope is contained.
4. If user confirms research, run researcher.
5. Run planner and classify risk tier (`low|medium|high`).
6. For `medium` or `high` risk, require explicit plan approval before implementation.
7. Run implementer.
8. Run reviewer. If blocking findings exist, return to implementer (max 2 loops).
9. Run tester. Retry flaky failures up to 3 times with triage notes.
10. Run verifier and canonical verification gates.
11. Require explicit release approval before final `Go` decision.

Stop immediately on unresolved blocking issues.
