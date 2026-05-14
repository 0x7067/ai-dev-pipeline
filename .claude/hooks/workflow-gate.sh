#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: enforces workflow phase prerequisites.
# Blocks agent invocations if required prior phases are incomplete.
# Set WORKFLOW_GATES_SKIP=1 to bypass all checks.

if [ "${WORKFLOW_GATES_SKIP:-0}" = "1" ]; then
  exit 0
fi

# Per-run workflow-state resolution via shared helper in _hook_lib.sh.
HOOK_NAME="workflow-gate" HOOK_LIB_NO_STDIN=1 \
  source "$(dirname "$0")/_hook_lib.sh"
state_file="$(resolve_workflow_state_path)"

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
agent_prompt=""
case "$tool_name" in
  Agent)
    if command -v jq >/dev/null 2>&1; then
      agent_type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"
      agent_prompt="$(printf '%s' "$payload" | jq -r '.tool_input.prompt // empty' 2>/dev/null)"
    fi
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$agent_type" ]; then
  exit 0
fi

# Boundary parse: in-band bypass token.
# Honored only when it appears at the very start (after optional whitespace)
# of the first 200 chars of the agent prompt. The leading ^ anchor prevents
# the token from hiding in pasted content later in the prompt.
# On any parse failure, fall through to the normal gate (fail closed).
bypass_reason=""
if [ -n "$agent_prompt" ]; then
  prompt_head="${agent_prompt:0:200}"
  if [[ "$prompt_head" =~ ^[[:space:]]*\[gate-bypass:[[:space:]]*([^]]+)\] ]]; then
    candidate="${BASH_REMATCH[1]}"
    # Trim leading/trailing whitespace.
    candidate="${candidate#"${candidate%%[![:space:]]*}"}"
    candidate="${candidate%"${candidate##*[![:space:]]}"}"
    if [ -n "$candidate" ]; then
      bypass_reason="$candidate"
    fi
  fi
fi

if [ -n "$bypass_reason" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log_dir="${RUN_DIR:-/tmp}"
  mkdir -p "$log_dir" 2>/dev/null || log_dir="/tmp"
  # Single-line audit record; jq when available, plain otherwise.
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg agent "$agent_type" --arg reason "$bypass_reason" \
      --arg run_id "${RUN_ID:-}" \
      '{timestamp:$ts, agent_type:$agent, reason:$reason, run_id:$run_id}' \
      >> "$log_dir/gate-bypass.log" 2>/dev/null || true
  else
    # No jq: escape backslash and double-quote, then replace newlines with \n.
    _jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | sed 's/[[:cntrl:]]//g'; }
    printf '{"timestamp":"%s","agent_type":"%s","reason":"%s","run_id":"%s"}\n' \
      "$ts" "$(_jstr "$agent_type")" "$(_jstr "$bypass_reason")" "$(_jstr "${RUN_ID:-}")" \
      >> "$log_dir/gate-bypass.log" 2>/dev/null || true
    unset -f _jstr
  fi
  echo "workflow-gate: bypass honored for '$agent_type' (reason: $bypass_reason)" >&2
  exit 0
fi

emit_blocked() {
  local phase="$1" required="$2"
  {
    echo "workflow-gate: BLOCKED — '${phase}' requires '${required}' phase to be completed first."
    echo "Bypass options:"
    echo "  • Prefix the agent prompt with: [gate-bypass: <reason>]   (per-call, audited to \${RUN_DIR}/gate-bypass.log)"
    echo "  • Export WORKFLOW_GATES_SKIP=1                            (session-wide)"
    echo "  • Run /reset                                              (clear stale workflow-state)"
  } >&2
}

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
      emit_blocked "implement" "plan"
      exit 2
    fi
    ;;
  reviewer)
    if ! phase_completed "implement"; then
      emit_blocked "review" "implement"
      exit 2
    fi
    ;;
  tester)
    if ! phase_completed "plan"; then
      emit_blocked "test" "plan"
      exit 2
    fi
    ;;
  verifier)
    if ! phase_completed "review"; then
      emit_blocked "verify" "review"
      exit 2
    fi
    ;;
  planner|researcher|auditor)
    ;;
  *)
    ;;
esac

exit 0
