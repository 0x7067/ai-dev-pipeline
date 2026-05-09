#!/usr/bin/env bash
# AC2: researcher.md has explicit tools: allowlist with required entries;
# disallowedTools removed; body documents Exa MCP conditional addition.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
F="$REPO_ROOT/.claude/agents/researcher.md"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

tools_line=$(grep -E '^tools:' "$F" || true)
if [ -z "$tools_line" ]; then
  fail "researcher.md has no tools: line"
else
  pass "researcher.md has tools: line"
  for entry in Read Glob Grep Write AskUserQuestion WebSearch WebFetch \
               'mcp__plugin_context7_context7__resolve-library-id' \
               'mcp__plugin_context7_context7__query-docs'; do
    if printf '%s' "$tools_line" | grep -qF "$entry"; then
      pass "tools includes $entry"
    else
      fail "tools missing $entry"
    fi
  done
fi

if grep -qE '^disallowedTools:' "$F"; then
  fail "researcher.md still has disallowedTools: line"
else
  pass "researcher.md disallowedTools removed"
fi

if grep -qiE 'Exa' "$F"; then
  pass "researcher.md body documents Exa MCP conditional"
else
  fail "researcher.md body does not mention Exa MCP"
fi

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
