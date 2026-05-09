#!/usr/bin/env bash
# AC5: Any file outside the config-only allowlist forces change_class=standard
# (Resolution #3 fail-closed). ship.md MUST document the fail-closed posture.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

# 1. Mixed diff fail-closed clause documented
if grep -qE '(mixed|any file|outside).*(allowlist|config[_ -]only).*(standard|fail[- ]closed)' "$SHIP_MD" \
   || grep -qE 'fail[- ]closed.*standard' "$SHIP_MD" \
   || grep -qE 'Resolution #3' "$SHIP_MD"; then
  pass "fail-closed mixed-diff clause present"
else
  fail "ship.md does not document mixed-diff → standard fail-closed posture (AC5)"
fi

# 2. config_only must be a sibling tier, not a default
if ! grep -qE '\bstandard\b' "$SHIP_MD"; then
  fail "ship.md does not enumerate the standard sibling class (AC5)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac5-mixed-diff-fail-closed: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac5-mixed-diff-fail-closed: OK"
