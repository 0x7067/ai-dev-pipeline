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
#   0. The current project has not opted into ai-dev-pipeline (no
#      `.claude/policy/approvals.yaml` reachable by walking up from cwd).
#      The plugin is installed globally; without an opt-in marker this
#      hook must not interfere with unrelated repos.
#   1. The edit is "trivial-shaped": test/spec file, lockfile, single-line
#      diff, or comment-only diff. Trivial edits do not need a plan.
#   2. workflow-state.json reports phases.plan.completed == true.
#   3. ${RUN_DIR}/current-plan.md exists and is non-empty (RUN_DIR resolved
#      via env → .claude/workflow-state/active → docs/ fallback).
#   4. Edit/Write target is a meta path (.claude/, docs/, scripts/,
#      examples/, README, *.md at root) so the repo can evolve its own
#      pipeline artifacts without self-locking.

mode="${PLAN_GATE_MODE:-block}"

if [ "$mode" = "off" ] || [ "${PLAN_GATE_BYPASS:-0}" = "1" ]; then
  exit 0
fi

# Project opt-in detection: walk up from cwd looking for the ai-dev-pipeline
# approvals policy file. If absent anywhere up the tree, this project has
# not opted in and the hook is a no-op. Boundary check only — no parsing.
_aidp_dir="$PWD"
_aidp_opted_in=0
while [ -n "$_aidp_dir" ] && [ "$_aidp_dir" != "/" ]; do
  if [ -f "$_aidp_dir/.claude/policy/approvals.yaml" ]; then
    _aidp_opted_in=1
    break
  fi
  _aidp_dir="$(dirname "$_aidp_dir")"
done
unset _aidp_dir
if [ "$_aidp_opted_in" != "1" ]; then
  exit 0
fi
unset _aidp_opted_in

payload="$(cat)"
if [ -z "$payload" ]; then
  exit 0
fi

target=""
old_string=""
new_string=""
if command -v jq >/dev/null 2>&1; then
  target="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)"
  old_string="$(printf '%s' "$payload" | jq -r '.tool_input.old_string // empty' 2>/dev/null)"
  new_string="$(printf '%s' "$payload" | jq -r '.tool_input.new_string // empty' 2>/dev/null)"
fi

# Allow edits to pipeline meta-files unconditionally; otherwise the repo
# cannot evolve its own rules/templates/skills without a full plan cycle.
case "$target" in
  *.claude/*|*/docs/*|*/scripts/*|*/examples/*|*/templates/*|*/README*|*/CLAUDE.md|*/AGENTS.md|*/CHANGELOG*)
    exit 0
    ;;
esac

# Trivial-shape bypass — a plan is not required for edits whose shape
# precludes meaningful design choice. Each branch is conservative; the
# fallback when none match is "ask for a plan".

# (a) Test/spec files: changing only tests does not change product behavior.
case "$target" in
  *.test.*|*.spec.*|*_test.go|*_test.py|*_test.rs|*/tests/*|*/__tests__/*|*/test/*|*/spec/*)
    exit 0
    ;;
esac

# (b) Lockfiles: machine-generated, no design content.
case "$(basename -- "${target:-}")" in
  pnpm-lock.yaml|package-lock.json|yarn.lock|bun.lockb|bun.lock|go.sum|Cargo.lock|poetry.lock|uv.lock|Pipfile.lock|Gemfile.lock|composer.lock|mix.lock|*.lock)
    exit 0
    ;;
esac

# (c) Single-line Edit diff: no newline on either side of the replacement.
#     `grep $'\n'` is unreliable on macOS BSD grep (treated as empty pattern),
#     so use bash glob matching against a literal-newline char.
_NL=$'\n'
if [ -n "$old_string$new_string" ] \
  && [[ "$old_string" != *"$_NL"* ]] \
  && [[ "$new_string" != *"$_NL"* ]]; then
  exit 0
fi
unset _NL

# (d) Comment-only Edit: every non-blank line on both sides starts with a
#     comment leader (#, //, /*, *, --, ;). Heuristic; covers common langs.
_is_comment_only() {
  local s="$1"
  [ -z "$s" ] && return 0
  if printf '%s\n' "$s" | grep -vE '^[[:space:]]*$' \
       | grep -vqE '^[[:space:]]*(#|//|/\*|\*|--|;)'; then
    return 1
  fi
  return 0
}
if [ -n "$old_string$new_string" ] \
  && _is_comment_only "$old_string" \
  && _is_comment_only "$new_string"; then
  exit 0
fi

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
