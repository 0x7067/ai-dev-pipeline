#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "version-sync: ERROR: jq is required"
  exit 1
fi

plugin_json=".claude-plugin/plugin.json"
marketplace_json=".claude-plugin/marketplace.json"

if [ ! -f "$plugin_json" ]; then
  echo "version-sync: ERROR: missing $plugin_json"
  exit 1
fi

if [ ! -f "$marketplace_json" ]; then
  echo "version-sync: ERROR: missing $marketplace_json"
  exit 1
fi

plugin_version="$(jq -r '.version' "$plugin_json")"
marketplace_version="$(jq -r '.plugins[0].version' "$marketplace_json")"

if [ "$plugin_version" != "$marketplace_version" ]; then
  echo "version-sync: ERROR: version mismatch — plugin.json=$plugin_version marketplace.json=$marketplace_version"
  exit 1
fi

echo "version-sync: OK ($plugin_version)"
