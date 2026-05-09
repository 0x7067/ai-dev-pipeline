#!/usr/bin/env bash
# AC8: When mode=fast AND risk=low AND change_class ∈ {trivial, config_only}:
#   - research phase prints skip narration without prompting
#   - review is folded into verify-report's advisory section (no standalone
#     review-report.md write)
#   - a single approval gate fires at release.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"
VERIFY_TPL="${REPO_ROOT}/docs/templates/verify-report-template.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

# 1. ship.md documents the fast+low+(trivial|config_only) short-circuit.
if grep -qE 'mode=fast.*risk=low.*(trivial|config_only)' "$SHIP_MD" \
   || grep -qE 'fast.*low.*short[- ]circuit' "$SHIP_MD"; then
  pass "fast-low short-circuit documented"
else
  fail "ship.md does not document the fast+low+(trivial|config_only) short-circuit (AC8)"
fi

# 2. Review-fold-into-verify mechanic is documented.
if grep -qE 'fold(ed)?.*review.*verify|review.*folded.*advisory' "$SHIP_MD"; then
  pass "review fold into verify advisory documented"
else
  fail "review fold into verify advisory not documented in ship.md (AC8)"
fi

# 3. Verify-report template has the "Advisory review findings (folded)" section.
if [ -f "$VERIFY_TPL" ]; then
  if grep -qE 'Advisory review findings|folded' "$VERIFY_TPL"; then
    pass "verify-report template has folded-review advisory section"
  else
    fail "verify-report-template.md missing folded review-advisory section (AC8)"
  fi
else
  fail "verify-report-template.md missing entirely (AC8)"
fi

# 4. Single approval at release in short-circuit mode (no plan-approval gate).
if grep -qE 'single approval.*release|skip.*plan[- ]approval.*risk=low' "$SHIP_MD"; then
  pass "single release-only approval documented"
else
  fail "ship.md does not document single approval at release for short-circuit (AC8)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac8-fast-low-shortcircuit: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac8-fast-low-shortcircuit: OK"
