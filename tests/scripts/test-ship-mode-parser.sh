#!/usr/bin/env bash
# Contract tests for the /ship mode-argument grammar documented in
# .claude/commands/ship.md.
#
# Closed grammar:
#   /ship           → mode=adaptive  (TDD on)
#   /ship strict    → mode=strict    (TDD on)
#   anything else   → REJECT
#
# We assert these properties by grep'ing the canonical wording out of
# .claude/commands/ship.md (which is the source of truth consumed by the
# orchestrator). This avoids re-implementing the parser; the contract under
# test is "the documented grammar matches the rules above."

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing at $SHIP_MD" >&2; exit 2; }

# 1. /ship (no args) is documented as adaptive
if grep -qE '/ship.*\(no args\).*adaptive' "$SHIP_MD"; then
  pass "/ship (no args) → adaptive"
else
  fail "/ship (no args) → adaptive not documented"
fi

# 2. /ship strict is documented
if grep -qE '/ship strict' "$SHIP_MD"; then
  pass "/ship strict accepted"
else
  fail "/ship strict not documented"
fi

# 3. The closed grammar rejects /ship tdd, /ship adaptive, /ship anything
#    The doc must explicitly call out these as rejected.
for rejected in 'tdd' 'adaptive' 'anything'; do
  if grep -qE "/ship ${rejected}" "$SHIP_MD" && grep -qE 'rejected|unrecognized' "$SHIP_MD"; then
    pass "/ship ${rejected} rejected"
  else
    fail "/ship ${rejected} rejection not documented"
  fi
done

# 4. The grammar is closed: ship.md asserts only two valid modes
if grep -qE 'only two modes are valid|grammar is closed' "$SHIP_MD"; then
  pass "grammar is closed"
else
  fail "closed-grammar assertion missing"
fi

if [ "$failures" -eq 0 ]; then
  echo "ship-mode-parser: ok"
  exit 0
fi
echo "ship-mode-parser: $failures failure(s)" >&2
exit 1
