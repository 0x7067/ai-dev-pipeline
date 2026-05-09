#!/usr/bin/env bash
# AC2: /ship (no args) selects mode=fast.
#
# ship.md MUST document that the default invocation maps to mode=fast.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

# Must say something like "/ship (no args) — `mode=fast`"
if grep -qE '/ship.*\(no args\).*mode=fast' "$SHIP_MD"; then
  pass "/ship (no args) → mode=fast documented"
else
  fail "default invocation does not map to mode=fast (AC2)"
fi

# And must NOT keep the legacy default of mode=adaptive
if grep -qE '/ship.*\(no args\).*mode=adaptive' "$SHIP_MD"; then
  fail "default invocation still mapped to mode=adaptive (AC2)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac2-default-fast: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac2-default-fast: OK"
