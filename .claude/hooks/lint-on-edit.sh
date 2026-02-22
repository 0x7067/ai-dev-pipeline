#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "lint-on-edit: $*"
  "$@"
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
  printf '%s\n' "$changed_files_list" | rg -q "${ext_pattern}$"
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

  rg -q "\"${script_name}\"[[:space:]]*:" package.json
}

if has_package_script "lint"; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
    if ! has_changed_ext '\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte)$'; then
      echo "lint-on-edit: skipped (no relevant JS/TS changes)"
      exit 0
    fi
  fi

  if command -v bun >/dev/null 2>&1; then
    run bun run -s lint
    exit $?
  fi

  if command -v npm >/dev/null 2>&1; then
    run npm run -s lint
    exit $?
  fi

  if command -v pnpm >/dev/null 2>&1; then
    run pnpm -s lint
    exit $?
  fi

  if command -v yarn >/dev/null 2>&1; then
    run yarn -s lint
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
        run ruff check $(printf '%s\n' "$changed_files_list" | rg '\.py$' | tr '\n' ' ')
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
