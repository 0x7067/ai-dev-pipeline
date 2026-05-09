#!/usr/bin/env bash
# AC7: implementer.md and auditor.md body include parallel-tool-call guidance:
# independent Read/Glob/Grep calls should be batched in one turn.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for agent in implementer auditor; do
  F="$REPO_ROOT/.claude/agents/$agent.md"
  if grep -qiE '(parallel.{0,10}tool|batch.{0,40}(one turn|single turn)|independent.{0,40}(Read|Glob|Grep).{0,80}(batch|parallel|one turn))' "$F"; then
    pass "$agent.md has parallel-tool-call guidance"
  else
    fail "$agent.md missing parallel-tool-call guidance"
  fi
done

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
