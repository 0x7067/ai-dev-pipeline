# shellcheck shell=bash
# Shared utilities for Claude Code PostToolUse hooks.
# Usage: set HOOK_NAME before sourcing this file.
#   HOOK_NAME="lint-on-edit"
#   source "$(dirname "$0")/_hook_lib.sh"

: "${HOOK_NAME:?HOOK_NAME must be set before sourcing _hook_lib.sh}"

# Early exit: skip files outside project directory
_hook_payload="$(cat)"
_edited_file=""
if [ -n "$_hook_payload" ]; then
  if command -v jq >/dev/null 2>&1; then
    _edited_file="$(printf '%s' "$_hook_payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
  fi
fi
if [ -n "$_edited_file" ]; then
  case "$_edited_file" in
    "$PWD"/*) ;;
    *) echo "${HOOK_NAME}: skipped (file outside project)"; exit 0 ;;
  esac
fi

run() {
  echo "${HOOK_NAME}: $*"
  "$@"
}

# Run a tool advisorily: capture combined output; on failure emit to stderr
# and exit 1 (non-blocking). Never exit 2 (which Claude treats as blocking).
run_advisory() {
  echo "${HOOK_NAME}: $*"
  local _out _rc
  _out="$("$@" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    printf '%s\n' "$_out" >&2
    echo "${HOOK_NAME}: command failed (exit $_rc) — reported as advisory" >&2
    exit 1
  fi
  exit 0
}

has_rg() {
  command -v rg >/dev/null 2>&1
}

has_input_pattern() {
  local pattern="$1"

  if has_rg; then
    rg -q -- "$pattern"
  else
    grep -Eq -- "$pattern"
  fi
}

has_file_pattern() {
  local pattern="$1"
  local file="$2"

  if has_rg; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

filter_changed_files() {
  local pattern="$1"

  if has_rg; then
    rg -- "$pattern"
  else
    grep -E -- "$pattern"
  fi
}

fast_mode="${HOOKS_FAST:-1}"
changed_files_list=""

if [ "$fast_mode" = "1" ] && command -v git >/dev/null 2>&1; then
  changed_files_list="$(
    {
      git diff --name-only --diff-filter=ACM 2>/dev/null || true
      git ls-files -m -o --exclude-standard 2>/dev/null || true
    } | sort -u
  )"
fi

has_changed_ext() {
  local ext_pattern="$1"
  [ -n "$changed_files_list" ] || return 1
  printf '%s\n' "$changed_files_list" | has_input_pattern "${ext_pattern}$"
}

has_package_script() {
  local script_name="$1"

  if [ ! -f package.json ]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -e --arg script_name "$script_name" '.scripts[$script_name] != null' package.json >/dev/null 2>&1
    return $?
  fi

  has_file_pattern "\"${script_name}\"[[:space:]]*:" package.json
}

detect_pkg_manager() {
  # Prefer lockfile — reflects what the project actually uses.
  # Only echo if the corresponding binary is available; otherwise fall through.
  if { [ -f bun.lockb ] || [ -f bun.lock ]; } && command -v bun  >/dev/null 2>&1; then echo bun; return; fi
  if [ -f pnpm-lock.yaml ]                    && command -v pnpm >/dev/null 2>&1; then echo pnpm; return; fi
  if [ -f yarn.lock ]                         && command -v yarn >/dev/null 2>&1; then echo yarn; return; fi
  if [ -f package-lock.json ]                 && command -v npm  >/dev/null 2>&1; then echo npm; return; fi
  # No matching lockfile+binary — fall back to first available binary.
  local _pm
  for _pm in bun pnpm yarn npm; do
    command -v "$_pm" >/dev/null 2>&1 && { echo "$_pm"; return; }
  done
}

# resolve_workflow_state_path: prints the path of the workflow-state JSON
# file the hooks should read/write. Resolution order, fail-soft:
#   1. $WORKFLOW_STATE_PATH if explicitly set (orchestrator override).
#   2. .claude/workflow-state/<active>.json when an active pointer exists
#      AND the active value parses through scripts/parse-run-id.sh.
#   3. .claude/workflow-state.json (legacy single-state default).
# Never echoes an unparsed run-id; falls back to legacy on parse failure.
resolve_workflow_state_path() {
  if [ -n "${WORKFLOW_STATE_PATH:-}" ]; then
    printf '%s\n' "$WORKFLOW_STATE_PATH"
    return 0
  fi
  local active_file=".claude/workflow-state/active"
  local parser="scripts/parse-run-id.sh"
  if [ -f "$active_file" ] && [ -f "$parser" ]; then
    local active
    active=$(head -n1 "$active_file" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$active" ] && bash "$parser" "$active" >/dev/null 2>&1; then
      printf '.claude/workflow-state/%s.json\n' "$active"
      return 0
    fi
  fi
  printf '.claude/workflow-state.json\n'
}

# Detect Python package manager (uv > poetry > pip).
# Lockfile presence + binary availability required; falls back to pip if any Python project marker exists.
detect_py_pkg_manager() {
  if [ -f uv.lock ]      && command -v uv     >/dev/null 2>&1; then echo uv; return; fi
  if [ -f poetry.lock ]  && command -v poetry >/dev/null 2>&1; then echo poetry; return; fi
  if { [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ] || [ -f requirements.txt ]; } \
      && command -v pip >/dev/null 2>&1; then
    echo pip; return
  fi
}
