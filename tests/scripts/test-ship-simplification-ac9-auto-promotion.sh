#!/usr/bin/env bash
# AC9: When mode=fast and requirement-analysis returns risk=medium|high,
# orchestrator prints `⏵ promoting fast → strict (risk=<tier>)` exactly once
# and applies strict-mode plan-approval gate from that point on.
# Run does NOT abort.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"
RULES_MD="${REPO_ROOT}/.claude/rules/release-and-verification.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

# 1. The exact promotion narration line is present in ship.md
if grep -qE 'promoting fast .*strict.*risk=' "$SHIP_MD"; then
  pass "promotion narration line documented"
else
  fail "ship.md missing 'promoting fast → strict (risk=<tier>)' narration (AC9)"
fi

# 2. Promotion is one-shot / idempotent.
if grep -qE 'exactly once|one[- ]shot|idempoten' "$SHIP_MD"; then
  pass "promotion idempotency / exactly-once documented"
else
  fail "promotion idempotency (exactly once) not documented in ship.md (AC9 / I4)"
fi

# 3. Run does NOT abort on promotion.
if grep -qE 'promot(e|ing).*(no abort|does not abort|continue)' "$SHIP_MD" \
   || grep -qE '(no abort|does not abort).*promot' "$SHIP_MD"; then
  pass "promotion is non-aborting"
else
  fail "non-aborting promotion semantics not documented (AC9)"
fi

# 4. The Human Approval Policy in the rules doc references the new fast→strict
#    promotion (or at minimum the fast mode itself) instead of adaptive.
if [ -f "$RULES_MD" ]; then
  if awk '/^## Human Approval Policy/,/^## /' "$RULES_MD" | grep -qE '\bfast\b'; then
    pass "Human Approval Policy references fast mode"
  else
    fail "Human Approval Policy does not reference fast mode (AC9)"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac9-auto-promotion: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac9-auto-promotion: OK"
