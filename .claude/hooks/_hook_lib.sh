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
  # Prefer lockfile — reflects what the project actually uses
  if [ -f bun.lockb ] || [ -f bun.lock ]; then echo bun; return; fi
  if [ -f pnpm-lock.yaml ]; then echo pnpm; return; fi
  if [ -f yarn.lock ]; then echo yarn; return; fi
  if [ -f package-lock.json ]; then echo npm; return; fi
  # No lockfile — fall back to first available binary
  local _pm
  for _pm in bun pnpm yarn npm; do
    command -v "$_pm" >/dev/null 2>&1 && { echo "$_pm"; return; }
  done
}
