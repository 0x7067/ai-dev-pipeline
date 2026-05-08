---
description: Advanced — Perform upfront research for unclear or high-risk work. Prefer `/ship` for the full flow.
---

You are the orchestrator for `/research`. Do NOT research yourself — delegate to the `researcher` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

1. Print to the user:
   `▶ researcher starting`

2. Invoke the `researcher` subagent via the Task tool. Pass the user's request as input. Wait for it to return.

3. The researcher's response ends with a single line in the form
   `STATUS: <state> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ researcher — <everything after "STATUS: ">`
   - Otherwise → `✗ researcher — <everything after "STATUS: ">`

5. Expected output is `docs/research/<topic>.md`.
