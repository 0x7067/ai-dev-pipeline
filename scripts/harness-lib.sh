#!/usr/bin/env bash
# Shared helpers for repository verification scripts.

harness_script_dir() {
  local source_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  cd "$(dirname "$source_path")" >/dev/null 2>&1 && pwd -P
}

harness_repo_root_from_script_dir() {
  local script_dir="$1"
  cd "${script_dir}/.." >/dev/null 2>&1 && pwd -P
}

harness_cd_repo_root() {
  local script_dir
  script_dir="$(harness_script_dir)"
  cd "$(harness_repo_root_from_script_dir "$script_dir")" || return 1
}

harness_has_command() {
  command -v "$1" >/dev/null 2>&1
}

harness_is_non_negative_int() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

harness_detect_js_package_manager() {
  if [ -n "${HARNESS_JS_PACKAGE_MANAGER:-}" ]; then
    if harness_has_command "$HARNESS_JS_PACKAGE_MANAGER"; then
      printf '%s\n' "$HARNESS_JS_PACKAGE_MANAGER"
      return 0
    fi
    return 1
  fi

  if { [ -f bun.lockb ] || [ -f bun.lock ]; } && harness_has_command bun; then printf '%s\n' bun; return 0; fi
  if [ -f pnpm-lock.yaml ] && harness_has_command pnpm; then printf '%s\n' pnpm; return 0; fi
  if [ -f yarn.lock ] && harness_has_command yarn; then printf '%s\n' yarn; return 0; fi
  if [ -f package-lock.json ] && harness_has_command npm; then printf '%s\n' npm; return 0; fi

  local pm
  for pm in bun pnpm yarn npm; do
    if harness_has_command "$pm"; then
      printf '%s\n' "$pm"
      return 0
    fi
  done

  return 1
}

harness_run_package_script() {
  local script_name="$1"
  local pm

  pm="$(harness_detect_js_package_manager)" || return 127

  case "$pm" in
    bun)  "$pm" run -s "$script_name" ;;
    npm)  "$pm" run -s "$script_name" ;;
    pnpm) "$pm" run -s "$script_name" ;;
    yarn) "$pm" run -s "$script_name" ;;
    *) return 127 ;;
  esac
}
