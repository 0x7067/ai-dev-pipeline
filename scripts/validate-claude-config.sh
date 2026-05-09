#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

if ! command -v jq >/dev/null 2>&1; then
  echo "validate: ERROR: jq is required" >&2
  echo "validate: install jq (e.g. 'brew install jq' or 'apt-get install jq') and retry" >&2
  exit 1
fi

plugin_manifest=".claude-plugin/plugin.json"

if [ ! -f "$plugin_manifest" ]; then
  echo "validate: ERROR: missing $plugin_manifest" >&2
  exit 1
fi

if ! jq empty "$plugin_manifest" >/dev/null 2>&1; then
  echo "validate: ERROR: $plugin_manifest is not valid JSON" >&2
  exit 1
fi

# Boundary check: forbid .claude/settings.json from re-declaring hook entries
# already owned by .claude-plugin/plugin.json. The plugin manifest is the
# single source of truth; settings.json hook entries are CWD-relative and
# silently break when the plugin is consumed from any other repo.
if [ -f .claude/settings.json ]; then
  if ! jq empty .claude/settings.json >/dev/null 2>&1; then
    echo "validate: ERROR: .claude/settings.json is not valid JSON" >&2
    exit 1
  fi
  settings_hook_count="$(jq '[.hooks // {} | to_entries[] | .value[]?.hooks[]?] | length' .claude/settings.json 2>/dev/null || echo 0)"
  if [ "${settings_hook_count:-0}" -gt 0 ]; then
    echo "validate: ERROR: .claude/settings.json declares $settings_hook_count hook entries" >&2
    echo "validate: hook registration is owned by $plugin_manifest; remove the 'hooks' block from .claude/settings.json (or delete the file if it has no other content)" >&2
    exit 1
  fi
fi

# Boundary check: every hook script referenced by plugin.json must exist on disk.
missing_hooks="$(jq -r '
  [.hooks // {} | to_entries[] | .value[]?.hooks[]?.command]
  | map(capture("\\$\\{CLAUDE_PLUGIN_ROOT\\}/(?<p>\\S+)") | .p)
  | .[]
' "$plugin_manifest" 2>/dev/null | while read -r relpath; do
  [ -z "$relpath" ] && continue
  if [ ! -f "$relpath" ]; then
    echo "$relpath"
  fi
done)"

if [ -n "$missing_hooks" ]; then
  echo "validate: ERROR: $plugin_manifest references missing hook scripts:" >&2
  while IFS= read -r p; do
    echo "  - $p" >&2
  done <<< "$missing_hooks"
  exit 1
fi

echo "validate: plugin.json hook references resolve and settings.json does not duplicate hooks"

# Boundary check: allowlist-only convention from
# .claude/rules/security-baseline.md — no agent file may declare a
# 'disallowedTools:' field. Permissions must be expressed as an explicit
# 'tools:' allowlist.
if ls .claude/agents/*.md >/dev/null 2>&1; then
  disallowed_hits="$(grep -l '^disallowedTools:' .claude/agents/*.md 2>/dev/null || true)"
  if [ -n "$disallowed_hits" ]; then
    echo "validate: ERROR: agent file(s) declare 'disallowedTools:' (forbidden by .claude/rules/security-baseline.md allowlist-only convention):" >&2
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      echo "  - $f" >&2
    done <<< "$disallowed_hits"
    exit 1
  fi
fi

rc=0
bash scripts/check-crossrefs.sh             || rc=1
bash scripts/check-boundary-violations.sh   || rc=1
bash scripts/check-plugin-version-sync.sh   || rc=1
bash scripts/check-skill-triggers.sh        || rc=1
bash scripts/check-write-allowed.sh         || rc=1

if [ "$rc" -ne 0 ]; then
  echo "validate: FAILED — one or more sub-checks reported errors above" >&2
  exit 1
fi

echo "validate: OK"
