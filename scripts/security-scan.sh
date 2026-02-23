#!/usr/bin/env bash
set -euo pipefail

run() {
  echo "security-scan: $*"
  "$@"
}

require_scan="${SECURITY_SCAN_REQUIRED:-0}"

# Node.js: npm audit / pnpm audit / yarn audit / bun audit
if [ -f package.json ]; then
  if command -v bun >/dev/null 2>&1 && [ -f bun.lockb ]; then
    # bun audit is not yet available (bun does not implement `bun audit` as of the time of writing).
    # Re-evaluate when bun adds native audit support: https://github.com/oven-sh/bun/issues/7440
    echo "security-scan: skipped (bun audit not yet supported)"
  elif command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then
    run npm audit --omit=dev --audit-level=high
    exit $?
  elif command -v pnpm >/dev/null 2>&1 && [ -f pnpm-lock.yaml ]; then
    run pnpm audit --prod --audit-level high
    exit $?
  elif command -v yarn >/dev/null 2>&1 && [ -f yarn.lock ]; then
    run yarn audit --level high --groups dependencies
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
if [ "$require_scan" = "1" ]; then
  echo "security-scan: ERROR: SECURITY_SCAN_REQUIRED=1 but no scanner available"
  exit 1
fi
exit 0
