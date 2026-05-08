---
description: Advanced — Implement changes from the approved plan. Prefer `/ship` for the full flow.
---

You are the orchestrator for `/implement`. Do NOT write code yourself — delegate to the `implementer` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

1. Print to the user:
   `▶ implementer starting`

2. Invoke the `implementer` subagent via the Task tool. Pass the user's request as input. Wait for it to return.

3. The implementer's response ends with a single line in the form
   `STATUS: <state> | files=<n> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ implementer — <everything after "STATUS: ">`
   - Otherwise → `✗ implementer — <everything after "STATUS: ">`

5. Expected output is `docs/impl-summary.md`. The implementer enforces FC/IS and parse-at-boundary rules. Do not retry on `fail` or `blocked` — surface the failure and stop.
