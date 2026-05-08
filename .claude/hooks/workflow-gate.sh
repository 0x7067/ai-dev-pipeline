#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: enforces workflow phase prerequisites.
# Blocks agent invocations if required prior phases are incomplete.
# Set WORKFLOW_GATES_SKIP=1 to bypass all checks.

if [ "${WORKFLOW_GATES_SKIP:-0}" = "1" ]; then
  exit 0
fi

# Per-run workflow-state resolution.
#   1. Explicit WORKFLOW_STATE_PATH override wins.
#   2. Otherwise read .claude/workflow-state/active and validate
#      through scripts/parse-run-id.sh.
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

if [ ! -f "$state_file" ]; then
  exit 0
fi

payload="$(cat)"
if [ -z "$payload" ]; then
  exit 0
fi

tool_name=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
fi

if [ -z "$tool_name" ]; then
  exit 0
fi

agent_type=""
case "$tool_name" in
  Agent)
    if command -v jq >/dev/null 2>&1; then
      agent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"
    fi
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$agent_type" ]; then
  exit 0
fi

phase_completed() {
  local phase="$1"
  if command -v jq >/dev/null 2>&1; then
    local val
    val="$(jq -r ".phases.${phase}.completed // false" "$state_file" 2>/dev/null)"
    [ "$val" = "true" ]
  else
    grep -q "\"${phase}\"" "$state_file" && grep -A1 "\"${phase}\"" "$state_file" | grep -q '"completed": true'
  fi
}

case "$agent_type" in
  implementer)
    if ! phase_completed "plan"; then
      echo "workflow-gate: BLOCKED — 'implement' requires 'plan' phase to be completed first."
      echo "Run /plan before /implement, or set WORKFLOW_GATES_SKIP=1 to bypass."
      exit 2
    fi
    ;;
  reviewer)
    if ! phase_completed "implement"; then
      echo "workflow-gate: BLOCKED — 'review' requires 'implement' phase to be completed first."
      echo "Run /implement before /review, or set WORKFLOW_GATES_SKIP=1 to bypass."
      exit 2
    fi
    ;;
  tester)
    if ! phase_completed "implement"; then
      echo "workflow-gate: BLOCKED — 'test' requires 'implement' phase to be completed first."
      echo "Run /implement before /test, or set WORKFLOW_GATES_SKIP=1 to bypass."
      exit 2
    fi
    ;;
  verifier)
    if ! phase_completed "test"; then
      echo "workflow-gate: BLOCKED — 'verify' requires 'test' phase to be completed first."
      echo "Run /test before /verify, or set WORKFLOW_GATES_SKIP=1 to bypass."
      exit 2
    fi
    ;;
  planner|researcher|auditor)
    ;;
  *)
    ;;
esac

exit 0
