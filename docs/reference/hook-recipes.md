# Hook Recipes

Reusable Claude Code hook patterns for the `ai-dev-pipeline` workflow. These are
**recipes**, not enabled hooks — copy them into the consuming repo's
`.claude/settings.json` to opt in.

Reference: [Anthropic Hooks reference](https://docs.anthropic.com/en/docs/claude-code/hooks).

## 1. Plan-gate (`PreToolUse`)

Block (or warn) `Edit`/`Write` when no plan artifact exists. **Shipped in this
repo** as `.claude/hooks/plan-gate.sh` and wired in `.claude/settings.json`.

The hook passes when any of the following holds:

- `docs/plan.md` exists and is non-empty
- `.claude/workflow-state.json` reports `phases.plan.completed == true`
- the edit target is a pipeline meta-path (`.claude/`, `docs/`, `scripts/`,
  `examples/`, `templates/`, `README*`, `CLAUDE.md`, `AGENTS.md`)

Configuration:

- `PLAN_GATE_MODE=block|warn|off` — default `block`
- `PLAN_GATE_BYPASS=1` — one-shot bypass

To adopt in a consuming repo, copy the hook script and add to
`.claude/settings.json`:

```jsonc
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/plan-gate.sh"
          }
        ]
      }
    ]
  }
}
```

For a soft rollout, set `PLAN_GATE_MODE=warn` in the team's shell profile or
the harness env until the workflow is internalized.

Source: codeongrass, "How to Build Human-in-the-Loop Approval Gates for AI Coding
Agents" (2026-04-25).

## 2. Intent-routing (`UserPromptSubmit`)

Inject a reminder that proactive pipeline-skill invocation is required, anchored
to `using-pipeline`.

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '↳ Intent check: if this is a coding intent, invoke the matching pipeline skill before any other tool call (see using-pipeline).'"
          }
        ]
      }
    ]
  }
}
```

Reference: [Anthropic, "Extend Claude with skills"](https://docs.anthropic.com/en/docs/claude-code/skills).

## 3. Gate-sequencing (`PostToolBatch`)

After every tool batch that touched code, surface the canonical gate runner so
the model is reminded that verification is a separate, deterministic step.

```jsonc
{
  "hooks": {
    "PostToolBatch": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "git diff --quiet --exit-code && exit 0 || echo 'verify-gates available: bash scripts/run-verification-gates.sh'"
          }
        ]
      }
    ]
  }
}
```

## Notes

- Hooks fire deterministically; prompts are advisory. Prefer hooks for
  invariants you want enforced regardless of model choice.
- These recipes use Claude Code tool names (`Edit`, `Write`, `Bash`) that exist
  today. Confirm names against the current Hooks reference before deploying.
- For unattended runs, see codeongrass on async permission forwarding.
