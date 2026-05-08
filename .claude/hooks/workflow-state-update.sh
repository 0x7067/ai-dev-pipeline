#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook: updates workflow state after successful agent completion.

# Per-run workflow-state resolution.
#   1. Explicit WORKFLOW_STATE_PATH override wins.
#   2. Otherwise read .claude/workflow-state/active (the orchestrator
#      writes the active run-id there at /ship step 0); validate it
#      through scripts/parse-run-id.sh before constructing a path.
#   3. Fall back to the legacy single-state file.
state_file="${WORKFLOW_STATE_PATH:-}"
if [ -z "$state_file" ]; then
  if [ -f .claude/workflow-state/active ] && [ -f scripts/parse-run-id.sh ]; then
    _active=$(head -n1 .claude/workflow-state/active 2>/dev/null | tr -d '[:space:]')
    if [ -n "$_active" ] && bash scripts/parse-run-id.sh "$_active" >/dev/null 2>&1; then
      state_file=".claude/workflow-state/${_active}.json"
    fi
    unset _active
  fi
  : "${state_file:=.claude/workflow-state.json}"
fi

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
  tmp="$(mktemp -t workflow-state.XXXXXX)"
  trap 'rm -f "$tmp"' EXIT
  jq --arg phase "$phase" '.phases[$phase].completed = true' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
  echo "workflow-state: marked '$phase' as completed"
else
  echo "workflow-state: jq not available, cannot update state file"
fi

exit 0
