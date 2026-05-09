#!/usr/bin/env bash
# AC8: implementer.md, tester.md, verifier.md include Bash timeout guidance
# referencing timeout: 600000 for long-running suites/gate runners.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for agent in implementer tester verifier; do
  F="$REPO_ROOT/.claude/agents/$agent.md"
  if grep -qF '600000' "$F" && grep -qiE 'timeout' "$F"; then
    pass "$agent.md has Bash timeout guidance (600000)"
  else
    fail "$agent.md missing Bash timeout guidance with 600000"
  fi
done

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
