#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

# shellcheck disable=SC2034
HOOK_NAME="type-check"
# shellcheck source=_hook_lib.sh
source "$(dirname "$0")/_hook_lib.sh"

if has_package_script "typecheck"; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
    if ! has_changed_ext '\.(ts|tsx|js|jsx|mjs|cjs)$'; then
      echo "type-check: skipped (no relevant JS/TS changes)"
      exit 0
    fi
  fi

  _pm="$(detect_pkg_manager)"
  if [ -n "$_pm" ]; then
    run_advisory "$_pm" run --silent typecheck
  fi

  echo "type-check: ERROR: package.json has typecheck script but no supported package manager found"
  exit 1
fi

if command -v tsc >/dev/null 2>&1 && [ -f tsconfig.json ]; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.(ts|tsx)$'; then
    echo "type-check: skipped (no TypeScript changes)"
    exit 0
  fi
  run_advisory tsc --noEmit
fi

# Rust
if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.rs'; then
    echo "type-check: skipped (no Rust changes)"
    exit 0
  fi
  run_advisory cargo check
fi

# Python
if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
  if command -v mypy >/dev/null 2>&1; then
    if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
      if has_changed_ext '\.py'; then
        _py_files=()
        while IFS= read -r _f; do _py_files+=("$_f"); done \
          < <(printf '%s\n' "$changed_files_list" | filter_changed_files '\.py$')
        run_advisory mypy "${_py_files[@]}"
      fi
      echo "type-check: skipped (no Python changes)"
      exit 0
    fi
    run_advisory mypy .
  fi
fi

# Go
if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ] && ! has_changed_ext '\.go'; then
    echo "type-check: skipped (no Go changes)"
    exit 0
  fi
  run_advisory go vet ./...
fi

echo "type-check: skipped (no supported typecheck command found)"
exit 0
