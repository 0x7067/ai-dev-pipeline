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
#   2. ${RUN_DIR}/current-plan.md exists and is non-empty (RUN_DIR resolved
#      via env → .claude/workflow-state/active → docs/latest → docs/latest.txt
#      → docs/ fallback)
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

# Per-run workflow-state resolution via shared helper in _hook_lib.sh.
HOOK_NAME="plan-gate" HOOK_LIB_NO_STDIN=1 \
  source "$(dirname "$0")/_hook_lib.sh"
state_file="$(resolve_workflow_state_path)"
if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
  if [ "$(jq -r '.phases.plan.completed // false' "$state_file" 2>/dev/null)" = "true" ]; then
    exit 0
  fi
fi

# Resolve RUN_DIR: env RUN_DIR wins, else env RUN_ID composes docs/runs/<id>,
# else the active-pointer-derived state file path tells us the run-id, else
# fail through to docs/. No symlink/text-file ladder — the orchestrator
# guarantees RUN_DIR/RUN_ID is exported in every Task call.
resolved_run_dir=""
if [ -n "${RUN_DIR:-}" ]; then
  resolved_run_dir="$RUN_DIR"
elif [ -n "${RUN_ID:-}" ] && [ -f scripts/parse-run-id.sh ] \
  && bash scripts/parse-run-id.sh "$RUN_ID" >/dev/null 2>&1; then
  resolved_run_dir="docs/runs/${RUN_ID}"
else
  # Derive run-id from the resolved state-file path, if it points into
  # .claude/workflow-state/<id>.json.
  case "$state_file" in
    .claude/workflow-state/*.json)
      _id="${state_file##*/}"; _id="${_id%.json}"
      if [ -n "$_id" ] && bash scripts/parse-run-id.sh "$_id" >/dev/null 2>&1; then
        resolved_run_dir="docs/runs/${_id}"
      fi
      unset _id
      ;;
  esac
fi
if [ -z "$resolved_run_dir" ]; then
  resolved_run_dir="docs"
fi

plan_path="${resolved_run_dir}/current-plan.md"
if [ -s "$plan_path" ]; then
  exit 0
fi

msg="plan-gate: no plan artifact detected (${plan_path} missing or empty, and workflow-state plan phase not completed). Run /plan first, or set PLAN_GATE_BYPASS=1."

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
