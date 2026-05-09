#!/usr/bin/env bash
# AC1: planner.md `tools` line includes `AskUserQuestion`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
F="$REPO_ROOT/.claude/agents/planner.md"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

tools_line=$(grep -E '^tools:' "$F" || true)
if [ -z "$tools_line" ]; then
  fail "planner.md missing tools: line"
elif printf '%s' "$tools_line" | grep -q 'AskUserQuestion'; then
  pass "planner tools includes AskUserQuestion"
else
  fail "planner tools does not include AskUserQuestion: $tools_line"
fi

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
