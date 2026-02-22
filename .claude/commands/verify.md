---
description: Run verification gates and produce go/no-go decision.
agent: verifier
context: fork
---

Run the `verifier` agent and write outcomes to `docs/verify-report.md`.

Then run strict active-run gates:
- `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/smoke-bootstrap.sh`
