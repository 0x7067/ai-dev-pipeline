---
description: Perform severity-first architecture/security/correctness review.
agent: reviewer
context: fork
---

Run the `reviewer` agent and write findings to `docs/review-report.md`.

After the standard review pass, if the change is classified `medium` or `high`
risk, invoke the `pragmatic-review-checklist` skill for an advisory second
pass. Append its findings to the same report.
