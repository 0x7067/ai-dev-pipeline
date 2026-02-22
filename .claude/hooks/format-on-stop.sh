#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "format-on-stop: $*"
  "$@"
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

if has_package_script "format"; then
  if command -v bun >/dev/null 2>&1; then
    run bun run -s format
    exit $?
  fi

  if command -v npm >/dev/null 2>&1; then
    run npm run -s format
    exit $?
  fi

  if command -v pnpm >/dev/null 2>&1; then
    run pnpm -s format
    exit $?
  fi

  if command -v yarn >/dev/null 2>&1; then
    run yarn -s format
    exit $?
  fi

  echo "format-on-stop: ERROR: package.json has format script but no supported package manager found"
  exit 1
fi

echo "format-on-stop: skipped (no supported format command found)"
exit 0
