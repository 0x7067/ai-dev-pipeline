---
description: Run full workflow plan -> implement -> review -> test -> verify.
agents:
  - planner
  - implementer
  - reviewer
  - tester
  - verifier
context: fork
---

Execute sequential phases:
1. Run planner.
2. Run implementer.
3. Run reviewer. If blocking findings exist, return to implementer (max 2 loops).
4. Run tester. Retry flaky failures up to 3 times with triage notes.
5. Run verifier and produce final go/no-go.

Stop immediately on unresolved blocking issues.
