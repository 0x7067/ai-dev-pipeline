---
description: Advanced — Analyze requirements and produce implementation plan. Prefer `/ship` for the full flow.
---

You are the orchestrator for `/plan`. Do NOT plan yourself — delegate to the `planner` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

1. Print this exact line to the user (visible chat output, not internal reasoning):
   `▶ planner starting`

2. Invoke the `planner` subagent via the Task tool. Pass the user's request (the slash-command arguments and any prior context) as input. Wait for it to return.

3. The planner's response ends with a single line in the form
   `STATUS: <state> | risk=<tier> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user, choosing the prefix from the STATUS:
   - If STATUS starts with `STATUS: ok` → `✓ planner — <everything after "STATUS: ">`
   - Otherwise → `✗ planner — <everything after "STATUS: ">`

5. Expected outputs are `docs/current-plan.md` and (when applicable) `docs/specs/<feature>.md`. Do not retry on `fail` or `blocked` — surface the failure and stop.

The planner is responsible for FC/IS classification and strict boundary parser mapping. Do not duplicate that work in the orchestrator.
