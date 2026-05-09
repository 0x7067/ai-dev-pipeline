#!/usr/bin/env bash
# AC5: implementer.md, tester.md, verifier.md tools allowlists include TodoWrite.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for agent in implementer tester verifier; do
  F="$REPO_ROOT/.claude/agents/$agent.md"
  tools_line=$(grep -E '^tools:' "$F" || true)
  if printf '%s' "$tools_line" | grep -qE '\bTodoWrite\b'; then
    pass "$agent.md tools includes TodoWrite"
  else
    fail "$agent.md tools missing TodoWrite (line: $tools_line)"
  fi
done

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
