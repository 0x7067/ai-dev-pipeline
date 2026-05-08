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
if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
  if [ "$(jq -r '.phases.plan.completed // false' "$state_file" 2>/dev/null)" = "true" ]; then
    exit 0
  fi
fi

# Resolve RUN_DIR through the documented precedence:
#   1. env RUN_DIR
#   2. env RUN_ID (compose docs/runs/<id> after parser validation)
#   3. .claude/workflow-state/active (parser-validated id)
#   4. docs/latest (symlink) — readlink target, relative to docs/
#   5. docs/latest.txt (parser-validated id)
#   6. docs/ legacy fallback
resolved_run_dir=""
if [ -n "${RUN_DIR:-}" ]; then
  resolved_run_dir="$RUN_DIR"
elif [ -n "${RUN_ID:-}" ] && [ -f scripts/parse-run-id.sh ] \
  && bash scripts/parse-run-id.sh "$RUN_ID" >/dev/null 2>&1; then
  resolved_run_dir="docs/runs/${RUN_ID}"
elif [ -f .claude/workflow-state/active ] && [ -f scripts/parse-run-id.sh ]; then
  _active=$(head -n1 .claude/workflow-state/active 2>/dev/null | tr -d '[:space:]')
  if [ -n "$_active" ] && bash scripts/parse-run-id.sh "$_active" >/dev/null 2>&1; then
    resolved_run_dir="docs/runs/${_active}"
  fi
  unset _active
fi
if [ -z "$resolved_run_dir" ] && [ -L docs/latest ]; then
  _t=$(readlink docs/latest 2>/dev/null)
  if [ -n "$_t" ]; then
    case "$_t" in
      /*) resolved_run_dir="$_t" ;;
      *)  resolved_run_dir="docs/${_t}" ;;
    esac
  fi
  unset _t
fi
if [ -z "$resolved_run_dir" ] && [ -f docs/latest.txt ] && [ -f scripts/parse-run-id.sh ]; then
  _txt=$(head -n1 docs/latest.txt 2>/dev/null | tr -d '[:space:]')
  if [ -n "$_txt" ] && bash scripts/parse-run-id.sh "$_txt" >/dev/null 2>&1; then
    resolved_run_dir="docs/runs/${_txt}"
  fi
  unset _txt
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
