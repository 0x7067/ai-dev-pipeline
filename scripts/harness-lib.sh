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

# ------------------------------------------------------------------------------
# Plugin-root resolver (zero-setup install support).
#
# These helpers are total functions over (PWD, CLAUDE_PLUGIN_ROOT, filesystem):
# they classify untrusted env input into a typed "domain value" and resolve
# plugin-shipped artifacts with repo-local precedence. They never mutate the
# environment and never cache state.
#
# Boundary parser:
#   harness_parse_plugin_root [value] -> stdout absolute dir | exit 1 (Unset/Invalid)
#
# Resolver (core decision; filesystem probe is the only I/O):
#   harness_resolve_artifact <relative-path> -> stdout absolute path | exit 1
#     1. PWD-relative match (vendored repo wins)
#     2. ${CLAUDE_PLUGIN_ROOT}/<relative-path> if a valid plugin root is set
#     3. otherwise: print structured "searched=[...]" error to stderr, exit 1
#
# Mode classifier:
#   harness_classify_install_mode -> stdout "Vendored"|"ZeroSetup"|"Broken"
# ------------------------------------------------------------------------------

# harness_parse_plugin_root: validates CLAUDE_PLUGIN_ROOT (or an explicit arg).
# Accepts: non-empty path that is an existing directory containing
# ".claude-plugin/plugin.json". On accept, prints the canonicalized absolute
# path and returns 0. On reject (unset, empty, missing dir, missing manifest),
# returns non-zero with no stdout. Errors are intentionally silent so callers
# can compose: parsing failure is a normal control-flow signal here, not a bug.
harness_parse_plugin_root() {
  local raw="${1-${CLAUDE_PLUGIN_ROOT-}}"
  if [ -z "${raw}" ]; then
    return 1
  fi
  if [ ! -d "${raw}" ]; then
    return 1
  fi
  if [ ! -f "${raw}/.claude-plugin/plugin.json" ]; then
    return 1
  fi
  ( cd "${raw}" >/dev/null 2>&1 && pwd -P ) || return 1
}

# harness_resolve_artifact: returns the absolute path of a plugin-shipped
# artifact, preferring a repo-local copy over the plugin-root copy. The
# argument MUST be a relative path. Absolute paths are rejected (exit 2)
# because they bypass the precedence contract.
harness_resolve_artifact() {
  local rel="${1-}"
  if [ -z "${rel}" ]; then
    printf 'harness_resolve_artifact: ERROR: missing relative path argument\n' >&2
    return 2
  fi
  case "${rel}" in
    /*)
      printf 'harness_resolve_artifact: ERROR: argument must be relative, got: %s\n' "${rel}" >&2
      return 2
      ;;
  esac
  # Reject path-traversal segments per boundary-parse-don't-validate: the
  # argument is untrusted input, and ".." would let a caller escape both the
  # repo root and the plugin root. We reject ANY `..` path component, not just
  # leading ones, so "subdir/../etc" is also denied. This is stricter than
  # strictly necessary for the in-tree callers but keeps the parser total.
  case "/${rel}/" in
    *"/../"*)
      printf 'harness_resolve_artifact: ERROR: path traversal not allowed (no ".." segments), got: %s\n' "${rel}" >&2
      return 2
      ;;
  esac

  local searched=()
  local local_path="${PWD}/${rel}"
  searched+=("${local_path}")
  if [ -e "${local_path}" ]; then
    printf '%s\n' "${local_path}"
    return 0
  fi

  local plugin_root
  if plugin_root="$(harness_parse_plugin_root)"; then
    local plugin_path="${plugin_root}/${rel}"
    searched+=("${plugin_path}")
    if [ -e "${plugin_path}" ]; then
      printf '%s\n' "${plugin_path}"
      return 0
    fi
  fi

  {
    printf 'harness_resolve_artifact: NotFound: %s\n' "${rel}"
    printf '  searched=[\n'
    local p
    for p in "${searched[@]}"; do
      printf '    %s\n' "${p}"
    done
    printf '  ]\n'
  } >&2
  return 1
}

# harness_classify_install_mode: probes the filesystem to classify the
# current install. Pure decision over two existence checks.
#   Vendored  : repo-local scripts/run-verification-gates.sh exists.
#   ZeroSetup : repo-local missing, but plugin root resolves and contains it.
#   Broken    : neither side has the canonical gate runner.
harness_classify_install_mode() {
  local probe="scripts/run-verification-gates.sh"
  if [ -f "${PWD}/${probe}" ]; then
    printf 'Vendored\n'
    return 0
  fi
  local plugin_root
  if plugin_root="$(harness_parse_plugin_root)" && [ -f "${plugin_root}/${probe}" ]; then
    printf 'ZeroSetup\n'
    return 0
  fi
  printf 'Broken\n'
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
