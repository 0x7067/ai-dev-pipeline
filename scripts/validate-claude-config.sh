#!/usr/bin/env bash
set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "validate: ERROR: jq is required" >&2
  echo "validate: install jq (e.g. 'brew install jq' or 'apt-get install jq') and retry" >&2
  exit 1
fi

if [ ! -f .claude/settings.json ]; then
  echo "validate: ERROR: missing .claude/settings.json" >&2
  echo "validate: run /setup to scaffold, or copy .claude/settings.json from the plugin root" >&2
  exit 1
fi

if ! jq empty .claude/settings.json >/dev/null 2>&1; then
  echo "validate: ERROR: .claude/settings.json is not valid JSON" >&2
  exit 1
fi

echo "validate: settings.json is valid JSON"

rc=0
bash scripts/check-crossrefs.sh             || rc=1
bash scripts/check-boundary-violations.sh   || rc=1
bash scripts/check-plugin-version-sync.sh   || rc=1
bash scripts/check-skill-triggers.sh        || rc=1

if [ "$rc" -ne 0 ]; then
  echo "validate: FAILED — one or more sub-checks reported errors above" >&2
  exit 1
fi

echo "validate: OK"
