#!/usr/bin/env bash
set -euo pipefail

PROTECTED_REGEX='(^|/)(\.env|\.env\.|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb|Cargo\.lock|Pipfile\.lock|poetry\.lock|Gemfile\.lock|.*\.(pem|key|p12|jks|keystore))$'

payload="${1:-}"
if [ -z "$payload" ] && [ ! -t 0 ]; then
  payload="$(cat || true)"
fi

if echo "$payload" | rg -N -q "$PROTECTED_REGEX"; then
  echo "protect-files: blocked edit/write on protected file"
  exit 2
fi

exit 0
