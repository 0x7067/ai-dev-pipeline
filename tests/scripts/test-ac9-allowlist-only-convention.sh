#!/usr/bin/env bash
# AC9: All seven agent files use allowlist-only convention — frontmatter has
# tools: field and NO disallowedTools: field. Convention is documented in a
# canonical location (security-baseline.md or agent-tooling-convention.md).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for agent in planner researcher implementer tester reviewer verifier auditor; do
  F="$REPO_ROOT/.claude/agents/$agent.md"
  if grep -qE '^tools:' "$F"; then
    pass "$agent.md has tools: field"
  else
    fail "$agent.md missing tools: field"
  fi
  if grep -qE '^disallowedTools:' "$F"; then
    fail "$agent.md still has disallowedTools: field"
  else
    pass "$agent.md has no disallowedTools: field"
  fi
done

# Convention documented in canonical location
SEC="$REPO_ROOT/.claude/rules/security-baseline.md"
CONV="$REPO_ROOT/.claude/rules/agent-tooling-convention.md"
if { [ -f "$SEC" ] && grep -qiE '(allowlist-only|allowlist only)' "$SEC"; } \
   || [ -f "$CONV" ]; then
  pass "allowlist-only convention documented in canonical location"
else
  fail "allowlist-only convention not documented in security-baseline.md or agent-tooling-convention.md"
fi

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
