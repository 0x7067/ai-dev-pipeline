#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook for Edit|Write: enforces that a plan exists before non-trivial edits.
#
# Mode (env: PLAN_GATE_MODE):
#   block (default) - exit 2 to block the tool call
#   warn            - print to stderr but allow
#   off             - skip entirely
#
# Bypass:
#   PLAN_GATE_BYPASS=1 - skip for this invocation
#
# Pass conditions (any one allows the edit):
#   1. workflow-state.json reports phases.plan.completed == true
#   2. docs/plan.md exists and is non-empty
#   3. Edit/Write target is a meta path (.claude/, docs/, scripts/, examples/, README, *.md at root)
#      (so the repo can edit its own pipeline artifacts without self-locking)

mode="${PLAN_GATE_MODE:-block}"

if [ "$mode" = "off" ] || [ "${PLAN_GATE_BYPASS:-0}" = "1" ]; then
  exit 0
fi

payload="$(cat)"
if [ -z "$payload" ]; then
  exit 0
fi

target=""
if command -v jq >/dev/null 2>&1; then
  target="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"
fi

# Allow edits to pipeline meta-files unconditionally; otherwise the repo cannot
# evolve its own rules/templates/skills without a full plan cycle.
case "$target" in
  *.claude/*|*/docs/*|*/scripts/*|*/examples/*|*/templates/*|*/README*|*/CLAUDE.md|*/AGENTS.md|*/CHANGELOG*)
    exit 0
    ;;
esac

state_file="${WORKFLOW_STATE_PATH:-.claude/workflow-state.json}"
if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
  if [ "$(jq -r '.phases.plan.completed // false' "$state_file" 2>/dev/null)" = "true" ]; then
    exit 0
  fi
fi

if [ -s docs/plan.md ]; then
  exit 0
fi

msg="plan-gate: no plan artifact detected (docs/plan.md missing and workflow-state plan phase not completed). Run /plan first, or set PLAN_GATE_BYPASS=1."

case "$mode" in
  warn)
    echo "$msg" >&2
    exit 0
    ;;
  block|*)
    echo "$msg" >&2
    exit 2
    ;;
esac
