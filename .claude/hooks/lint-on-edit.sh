#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

# shellcheck disable=SC2034
HOOK_NAME="lint-on-edit"
# shellcheck source=_hook_lib.sh
source "$(dirname "$0")/_hook_lib.sh"

if has_package_script "lint"; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
    if ! has_changed_ext '\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte)$'; then
      echo "lint-on-edit: skipped (no relevant JS/TS changes)"
      exit 0
    fi
  fi

  _pm="$(detect_pkg_manager)"
  if [ -n "$_pm" ]; then
    run_advisory "$_pm" run --silent lint
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
  run_advisory cargo clippy -- -D warnings
fi

# Python
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
  if command -v ruff >/dev/null 2>&1; then
    if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
      if has_changed_ext '\.py'; then
        _py_files=()
        while IFS= read -r _f; do _py_files+=("$_f"); done \
          < <(printf '%s\n' "$changed_files_list" | filter_changed_files '\.py$')
        run_advisory ruff check "${_py_files[@]}"
      fi
      echo "lint-on-edit: skipped (no Python changes)"
      exit 0
    fi
    run_advisory ruff check .
  fi
fi

# Go
if [ -f go.mod ] && command -v golangci-lint >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.go'; then
    echo "lint-on-edit: skipped (no Go changes)"
    exit 0
  fi
  run_advisory golangci-lint run
fi

echo "lint-on-edit: skipped (no supported lint command found)"
exit 0
