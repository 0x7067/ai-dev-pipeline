#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "type-check: $*"
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

if has_package_script "typecheck"; then
  if [ "$fast_mode" = "1" ] && [ -n "$changed_files_list" ]; then
    if ! has_changed_ext '\.(ts|tsx|js|jsx|mjs|cjs)$'; then
      echo "type-check: skipped (no relevant JS/TS changes)"
      exit 0
    fi
  fi

  if command -v bun >/dev/null 2>&1; then
    run bun run -s typecheck
    exit $?
  fi

  if command -v npm >/dev/null 2>&1; then
    run npm run -s typecheck
    exit $?
  fi

  if command -v pnpm >/dev/null 2>&1; then
    run pnpm -s typecheck
    exit $?
  fi

  if command -v yarn >/dev/null 2>&1; then
    run yarn -s typecheck
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
        run mypy $(printf '%s\n' "$changed_files_list" | rg '\.py$' | tr '\n' ' ')
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
