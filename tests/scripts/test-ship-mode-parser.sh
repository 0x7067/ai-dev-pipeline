#!/usr/bin/env bash
# Contract test for the documented /ship mode grammar.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing at $SHIP_MD" >&2; exit 2; }

if grep -qE "/ship\` or \`/ship auto\`" "$SHIP_MD"; then
  pass "/ship defaults to auto"
else
  fail "/ship auto default not documented"
fi

for accepted in '/ship strict' '/ship research <topic>'; do
  if grep -q "$accepted" "$SHIP_MD"; then
    pass "$accepted accepted"
  else
    fail "$accepted not documented"
  fi
done

if grep -q 'valid modes are: <empty> | "auto" | "strict" | "research <topic>"' "$SHIP_MD"; then
  pass "closed valid-mode enumeration documented"
else
  fail "valid-mode enumeration missing or stale"
fi

for rejected in '/ship fast' '/ship adaptive'; do
  if grep -q "$rejected.*legacy" "$SHIP_MD"; then
    pass "$rejected rejected"
  else
    fail "$rejected rejection not documented"
  fi
done

if [ "$failures" -eq 0 ]; then
  echo "ship-mode-parser: ok"
  exit 0
fi
echo "ship-mode-parser: $failures failure(s)" >&2
exit 1
