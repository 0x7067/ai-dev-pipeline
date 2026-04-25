#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: updates workflow state after successful agent completion.

state_file="${WORKFLOW_STATE_PATH:-.claude/workflow-state.json}"

payload="$(cat)"
if [ -z "$payload" ]; then
  exit 0
fi

tool_name=""
agent_type=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
  if [ "$tool_name" = "Agent" ]; then
    agent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"
  fi
fi

if [ -z "$agent_type" ]; then
  exit 0
fi

phase=""
case "$agent_type" in
  planner)    phase="plan" ;;
  implementer) phase="implement" ;;
  reviewer)   phase="review" ;;
  tester)     phase="test" ;;
  verifier)   phase="verify" ;;
  *)          exit 0 ;;
esac

if [ ! -f "$state_file" ]; then
  cat > "$state_file" <<'INIT'
{
  "task": "",
  "phases": {
    "plan": { "completed": false },
    "implement": { "completed": false },
    "review": { "completed": false },
    "test": { "completed": false },
    "verify": { "completed": false }
  }
}
INIT
fi

if command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq --arg phase "$phase" '.phases[$phase].completed = true' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  echo "workflow-state: marked '$phase' as completed"
else
  echo "workflow-state: jq not available, cannot update state file"
fi

exit 0
