#!/usr/bin/env bash
# AC4: verifier.md and auditor.md tools allowlists include Write;
# disallowedTools line removed; <deliverable> prefers Write with heredoc as
# legacy fallback.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for agent in verifier auditor; do
  F="$REPO_ROOT/.claude/agents/$agent.md"
  tools_line=$(grep -E '^tools:' "$F" || true)
  if printf '%s' "$tools_line" | grep -qE '\bWrite\b'; then
    pass "$agent.md tools includes Write"
  else
    fail "$agent.md tools missing Write"
  fi
  if grep -qE '^disallowedTools:' "$F"; then
    fail "$agent.md still has disallowedTools: line"
  else
    pass "$agent.md disallowedTools removed"
  fi
  # deliverable prefers Write
  block=$(awk '/<deliverable/,/<\/deliverable>/' "$F")
  if [ -z "$block" ]; then
    block=$(awk '/<deliverables>/,/<\/deliverables>/' "$F")
  fi
  if printf '%s' "$block" | grep -qiE '(prefer.*Write|use Write|via Write)'; then
    pass "$agent.md deliverable prefers Write"
  else
    fail "$agent.md deliverable does not prefer Write"
  fi
  if printf '%s' "$block" | grep -qiE '(heredoc.*(legacy|fallback)|legacy.*heredoc|fallback.*heredoc)'; then
    pass "$agent.md deliverable marks heredoc as legacy/fallback"
  else
    fail "$agent.md deliverable does not mark heredoc as legacy/fallback"
  fi
done

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
