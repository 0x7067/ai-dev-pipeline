---
description: Reset workflow state — clears all phase completions. Optionally name the task.
context: fork
---

Reset the workflow state file at `.claude/workflow-state.json`.

Write this content to `.claude/workflow-state.json`:

```json
{
  "task": "$ARGUMENTS",
  "phases": {
    "plan": { "completed": false },
    "implement": { "completed": false },
    "review": { "completed": false },
    "test": { "completed": false },
    "verify": { "completed": false }
  }
}
```

If `$ARGUMENTS` is empty, set `"task"` to `""`.

After writing, confirm the reset and show the current state.
