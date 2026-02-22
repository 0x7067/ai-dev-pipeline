#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "security-scan: $*"
  "$@"
}

# Node.js: npm audit / pnpm audit / yarn audit / bun audit
if [ -f package.json ]; then
  if command -v bun >/dev/null 2>&1 && [ -f bun.lockb ]; then
    echo "security-scan: skipped (bun audit not yet supported)"
  elif command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then
    run npm audit --omit=dev
    exit $?
  elif command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then
    run pnpm audit --prod
    exit $?
  elif command -v yarn >/dev/null 2>&1 && [ -f yarn.lock ]; then
    run yarn audit --groups dependencies
    exit $?
  fi
fi

# Rust: cargo audit
if [ -f Cargo.toml ] && command -v cargo-audit >/dev/null 2>&1; then
  run cargo audit
  exit $?
fi

# Python: pip-audit
if [ -f requirements.txt ] || [ -f pyproject.toml ]; then
  if command -v pip-audit >/dev/null 2>&1; then
    run pip-audit
    exit $?
  fi
fi

# Go: govulncheck
if [ -f go.mod ] && command -v govulncheck >/dev/null 2>&1; then
  run govulncheck ./...
  exit $?
fi

echo "security-scan: skipped (no supported scanner found)"
exit 0
