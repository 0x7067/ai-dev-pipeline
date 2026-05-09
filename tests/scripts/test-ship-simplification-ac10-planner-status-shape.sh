#!/usr/bin/env bash
# AC10: Planner STATUS line includes `change-class=<trivial|config_only|standard>`
# token between `risk=` and the summary segment.
#
# Source-of-truth: .claude/agents/planner.md STATUS shape definition.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PLANNER_MD="${REPO_ROOT}/.claude/agents/planner.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PLANNER_MD" ] || { echo "planner.md missing" >&2; exit 2; }

# 1. STATUS shape includes change-class= token.
if grep -qE 'STATUS:.*risk=.*change-class=' "$PLANNER_MD"; then
  pass "STATUS shape includes change-class= token between risk= and summary"
else
  fail "planner STATUS shape does not include change-class=<...> (AC10)"
fi

# 2. Enum surface mentions all three classes.
for cls in trivial config_only standard; do
  if grep -qE "\\b${cls}\\b" "$PLANNER_MD"; then
    pass "planner.md mentions class '$cls'"
  else
    fail "planner.md missing class '$cls' (AC10)"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "test-ac10-planner-status-shape: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac10-planner-status-shape: OK"
