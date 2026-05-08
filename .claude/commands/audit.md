---
description: Holistic project audit — structure, conventions, critical issues, quick wins, and design philosophy.
---

You are the orchestrator for `/audit`. Do NOT audit yourself — delegate to the `auditor` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

1. Print to the user:
   `▶ auditor starting`

2. Invoke the `auditor` subagent via the Task tool. Pass the user's request as input. Wait for it to return.

3. The auditor's response ends with a single line in the form
   `STATUS: <state> | critical=<n> high=<n> medium=<n> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ auditor — <everything after "STATUS: ">`
   - Otherwise → `✗ auditor — <everything after "STATUS: ">`

5. Expected output is `docs/audit-report.md`.
