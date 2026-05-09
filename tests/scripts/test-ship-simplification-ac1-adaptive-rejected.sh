#!/usr/bin/env bash
# AC1: /ship rejects 'adaptive' as a mode token.
#
# Source-of-truth contract test: .claude/commands/ship.md MUST document the
# new closed mode grammar {<empty> | "strict" | "fast" | "research <topic>"}
# and MUST emit a hard-error narration line for `/ship adaptive` whose valid-
# modes list contains "fast" and does NOT contain "adaptive".
#
# Until the simplification lands, ship.md still names `adaptive` as a default
# and lists it as an accepted (rejected-literal) mode — these assertions are
# expected to FAIL on the pre-implementation tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing at $SHIP_MD" >&2; exit 2; }

# 1. Must publish the new error narration with "fast" in valid-modes
if grep -qE 'unrecognized mode .*"adaptive".*valid modes are.*"fast"' "$SHIP_MD"; then
  pass "documented hard-error for adaptive lists fast as valid"
else
  fail "ship.md missing hard-error narration listing fast as valid (AC1)"
fi

# 2. The valid-modes enumeration must NOT include the literal "adaptive"
#    as a valid mode (only as a rejected token, if mentioned at all).
#    We assert that the canonical valid-modes line contains fast but not
#    adaptive in the same enumeration.
valid_modes_line="$(grep -E 'valid modes are' "$SHIP_MD" | head -n1 || true)"
if [ -z "$valid_modes_line" ]; then
  fail "no valid-modes enumeration line found in ship.md (AC1)"
elif printf '%s' "$valid_modes_line" | grep -q '"adaptive"'; then
  fail "valid-modes enumeration still lists adaptive (AC1)"
else
  pass "valid-modes enumeration excludes adaptive"
fi

# 3. The mode-argument grammar section must NOT advertise mode=adaptive
#    as an accepted mode alias (only the rejection message may name it).
if grep -qE '^- `/ship.*\bmode=adaptive\b' "$SHIP_MD"; then
  fail "ship.md still maps a /ship invocation to mode=adaptive (AC1)"
else
  pass "no /ship invocation maps to mode=adaptive"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac1-ship-adaptive-rejected: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac1-ship-adaptive-rejected: OK"
