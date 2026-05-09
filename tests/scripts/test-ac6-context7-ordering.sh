#!/usr/bin/env bash
# AC6: researcher.md <source-policy> documents that resolve-library-id MUST be
# called before query-docs.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
F="$REPO_ROOT/.claude/agents/researcher.md"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

block=$(awk '/<source-policy>/,/<\/source-policy>/' "$F")
if [ -z "$block" ]; then
  fail "researcher.md missing <source-policy> block"
else
  pass "<source-policy> block present"
  if printf '%s' "$block" | grep -qF 'resolve-library-id' \
     && printf '%s' "$block" | grep -qF 'query-docs'; then
    pass "<source-policy> names both Context7 tools"
  else
    fail "<source-policy> does not name both Context7 tools"
  fi
  # Ordering language: resolve-library-id MUST be called before query-docs
  if printf '%s' "$block" | grep -qiE 'resolve-library-id.{0,200}before.{0,200}query-docs|MUST.{0,80}resolve-library-id.{0,200}query-docs'; then
    pass "<source-policy> documents resolve-before-query ordering"
  else
    fail "<source-policy> does not document resolve-before-query ordering"
  fi
fi

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
