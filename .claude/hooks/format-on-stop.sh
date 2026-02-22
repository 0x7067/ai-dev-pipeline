#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "format-on-stop: $*"
  "$@"
}

has_rg() {
  command -v rg >/dev/null 2>&1
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
    run pnpm run --silent format
    exit $?
  fi

  if command -v yarn >/dev/null 2>&1; then
    run yarn run --silent format
    exit $?
  fi

  echo "format-on-stop: ERROR: package.json has format script but no supported package manager found"
  exit 1
fi

echo "format-on-stop: skipped (no supported format command found)"
exit 0
