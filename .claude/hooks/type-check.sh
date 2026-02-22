#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "type-check: $*"
  "$@"
}

if command -v bun >/dev/null 2>&1 && [ -f package.json ]; then
  if bun run -s typecheck >/dev/null 2>&1; then
    run bun run -s typecheck
    exit $?
  fi
fi

if command -v npm >/dev/null 2>&1 && [ -f package.json ]; then
  if npm run -s typecheck >/dev/null 2>&1; then
    run npm run -s typecheck
    exit $?
  fi
fi

if command -v pnpm >/dev/null 2>&1 && [ -f package.json ]; then
  if pnpm -s typecheck >/dev/null 2>&1; then
    run pnpm -s typecheck
    exit $?
  fi
fi

if command -v yarn >/dev/null 2>&1 && [ -f package.json ]; then
  if yarn -s typecheck >/dev/null 2>&1; then
    run yarn -s typecheck
    exit $?
  fi
fi

if command -v tsc >/dev/null 2>&1; then
  run tsc --noEmit
  exit $?
fi

echo "type-check: skipped (no supported typecheck command found)"
exit 0
