---
description: Review existing code, a diff, or a PR — severity-first architecture, security, and correctness findings. Use standalone when you want a review without running the full ship pipeline.
---

You are the orchestrator for `/review`. Do NOT review yourself — delegate to the `reviewer` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

1. Print to the user:
   `▶ reviewer starting`

2. Invoke the `reviewer` subagent via the Task tool. Pass the user's request as input. Wait for it to return.

3. The reviewer's response ends with a single line in the form
   `STATUS: <state> | blocking=<n> advisory=<n> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ reviewer — <everything after "STATUS: ">`
   - Otherwise → `✗ reviewer — <everything after "STATUS: ">`

5. Expected output is `docs/review-report.md`. The reviewer runs the pragmatic-review-checklist second pass automatically for `medium`/`high` risk changes; do not invoke it from here.
