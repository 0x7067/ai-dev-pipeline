#!/usr/bin/env bash
set -euo pipefail

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
    *) echo "type-check: skipped (file outside project)"; exit 0 ;;
  esac
fi

run() {
  echo "type-check: $*"
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
  for _pm in bun pnpm yarn npm; do
    command -v "$_pm" >/dev/null 2>&1 && { echo "$_pm"; return; }
  done
}

if has_package_script "typecheck"; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
    if ! has_changed_ext '\.(ts|tsx|js|jsx|mjs|cjs)$'; then
      echo "type-check: skipped (no relevant JS/TS changes)"
      exit 0
    fi
  fi

  _pm="$(detect_pkg_manager)"
  if [ -n "$_pm" ]; then
    run "$_pm" run --silent typecheck
    exit $?
  fi

  echo "type-check: ERROR: package.json has typecheck script but no supported package manager found"
  exit 1
fi

if command -v tsc >/dev/null 2>&1 && [ -f tsconfig.json ]; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.(ts|tsx)$'; then
    echo "type-check: skipped (no TypeScript changes)"
    exit 0
  fi
  run tsc --noEmit
  exit $?
fi

# Rust
if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.rs'; then
    echo "type-check: skipped (no Rust changes)"
    exit 0
  fi
  run cargo check
  exit $?
fi

# Python
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
  if command -v mypy >/dev/null 2>&1; then
    if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
      if has_changed_ext '\.py'; then
        _py_files=()
        while IFS= read -r _f; do _py_files+=("$_f"); done \
          < <(printf '%s\n' "$changed_files_list" | filter_changed_files '\.py$')
        run mypy "${_py_files[@]}"
        exit $?
      fi
      echo "type-check: skipped (no Python changes)"
      exit 0
    fi
    run mypy .
    exit $?
  fi
fi

# Go
if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.go'; then
    echo "type-check: skipped (no Go changes)"
    exit 0
  fi
  run go vet ./...
  exit $?
fi

echo "type-check: skipped (no supported typecheck command found)"
exit 0
