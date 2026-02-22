#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "validate: ERROR: jq is required"
  exit 1
fi

if [ ! -f .claude/settings.json ]; then
  echo "validate: ERROR: missing .claude/settings.json"
  exit 1
fi

jq empty .claude/settings.json >/dev/null

echo "validate: settings.json is valid JSON"

bash scripts/check-crossrefs.sh
bash scripts/check-boundary-violations.sh

echo "validate: OK"
