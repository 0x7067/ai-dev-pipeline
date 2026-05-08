---
description: Generate/run tests including property-based and boundary contract tests.
---

You are the orchestrator for `/test`. Do NOT write tests yourself — delegate to the `tester` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

1. Print to the user:
   `▶ tester starting`

2. Invoke the `tester` subagent via the Task tool. Pass the user's request as input. Wait for it to return.

3. The tester's response ends with a single line in the form
   `STATUS: <state> | added=<n> failing=<n> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` and includes `failing=0` → `✓ tester — <everything after "STATUS: ">`
   - Otherwise → `✗ tester — <everything after "STATUS: ">`

5. Expected output is `docs/test-report.md`. Do not invoke verification gates here — that is `/verify`'s job.
