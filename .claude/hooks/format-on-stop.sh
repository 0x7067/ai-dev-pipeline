#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "format-on-stop: $*"
  "$@"
}

if command -v bun >/dev/null 2>&1 && [ -f package.json ]; then
  if bun run -s format >/dev/null 2>&1; then
    run bun run -s format
    exit $?
  fi
fi

if command -v npm >/dev/null 2>&1 && [ -f package.json ]; then
  if npm run -s format >/dev/null 2>&1; then
    run npm run -s format
    exit $?
  fi
fi

if command -v pnpm >/dev/null 2>&1 && [ -f package.json ]; then
  if pnpm -s format >/dev/null 2>&1; then
    run pnpm -s format
    exit $?
  fi
fi

if command -v yarn >/dev/null 2>&1 && [ -f package.json ]; then
  if yarn -s format >/dev/null 2>&1; then
    run yarn -s format
    exit $?
  fi
fi

echo "format-on-stop: skipped (no supported format command found)"
exit 0
