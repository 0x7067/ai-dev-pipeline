#!/usr/bin/env bash
# AC3 (regression): /ship strict halts UNCONDITIONALLY at plan-approval gate.
#
# After the simplification, ship.md's plan-approval step MUST keep a strict
# branch that halts unconditionally regardless of risk tier. Verifies the
# canonical narration line is preserved.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

# Strict mode must explicitly halt unconditionally.
if grep -qE 'mode=strict.*halt unconditionally|If `mode=strict`: halt unconditionally' "$SHIP_MD"; then
  pass "strict mode documented to halt unconditionally"
else
  fail "strict-mode unconditional halt branch missing in ship.md (AC3 regression)"
fi

# The strict branch must reference the canonical approval prompt.
if grep -qE 'plan approval required.*mode=strict' "$SHIP_MD"; then
  pass "strict mode plan-approval prompt preserved"
else
  fail "strict-mode plan-approval prompt not preserved (AC3 regression)"
fi

# Must NOT have introduced a low-risk strict short-circuit.
if grep -qE 'mode=strict.*risk=low.*auto-approved' "$SHIP_MD"; then
  fail "strict mode auto-approves on risk=low — violates AC3"
fi

# Cohabitation check: post-simplification the strict branch must coexist
# with the new mode=fast branch (proves the regression survived the rewrite,
# not just the pre-rewrite tree). This is the assertion that fails today.
if grep -qE '`mode=fast`' "$SHIP_MD" && grep -qE '`mode=strict`' "$SHIP_MD"; then
  pass "strict and fast branches coexist post-rewrite"
else
  fail "strict/fast cohabitation absent — pre-rewrite tree (AC3 regression context)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac3-strict-unconditional: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac3-strict-unconditional: OK"
