#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "lint-on-edit: $*"
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

if has_package_script "lint"; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
    if ! has_changed_ext '\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte)$'; then
      echo "lint-on-edit: skipped (no relevant JS/TS changes)"
      exit 0
    fi
  fi

  _pm="$(detect_pkg_manager)"
  if [ -n "$_pm" ]; then
    run "$_pm" run --silent lint
    exit $?
  fi

  echo "lint-on-edit: ERROR: package.json has lint script but no supported package manager found"
  exit 1
fi

# Rust
if [ -f Cargo.toml ] && command -v cargo-clippy >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.rs'; then
    echo "lint-on-edit: skipped (no Rust changes)"
    exit 0
  fi
  run cargo clippy -- -D warnings
  exit $?
fi

# Python
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
  if command -v ruff >/dev/null 2>&1; then
    if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
      if has_changed_ext '\.py'; then
        _py_files=()
        while IFS= read -r _f; do _py_files+=("$_f"); done \
          < <(printf '%s\n' "$changed_files_list" | filter_changed_files '\.py$')
        run ruff check "${_py_files[@]}"
        exit $?
      fi
      echo "lint-on-edit: skipped (no Python changes)"
      exit 0
    fi
    run ruff check .
    exit $?
  fi
fi

# Go
if [ -f go.mod ] && command -v golangci-lint >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.go'; then
    echo "lint-on-edit: skipped (no Go changes)"
    exit 0
  fi
  run golangci-lint run
  exit $?
fi

echo "lint-on-edit: skipped (no supported lint command found)"
exit 0
