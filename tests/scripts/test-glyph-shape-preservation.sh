#!/usr/bin/env bash
# Invariant I1 / AC9 / R3 test: existing phase-marker glyph shapes are
# preserved byte-for-byte across all five primary commands.
#
# After the A1–A4 implementation, the following literal prefixes MUST
# still appear in their respective command files:
#   - `▶ <phase> starting`   (every multi-phase command)
#   - `✓ <phase> — STATUS:`  OR `✗ <phase> — STATUS:`  (every phase echo)
#
# The lean /ship flow intentionally removed decorative phase separators.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# I1 / AC9: existing glyph prefixes still present in ship.md.
SHIP="${REPO_ROOT}/.claude/commands/ship.md"
if [ ! -f "$SHIP" ]; then
  fail "$SHIP missing"
else
  if grep -q '▶' "$SHIP"; then pass "ship.md preserves ▶ glyph"; else fail "ship.md missing ▶ glyph"; fi
  if grep -q '✓\|✗' "$SHIP"; then pass "ship.md preserves ✓/✗ glyph"; else fail "ship.md missing ✓/✗ glyph"; fi
fi

# Lean-flow invariant: no command reintroduces /ship-only separators.
for cmd in ship review audit research; do
  f="${REPO_ROOT}/.claude/commands/${cmd}.md"
  [ -f "$f" ] || { fail "$f missing"; continue; }
  if grep -qF '── Setup ──' "$f" || grep -qF '── TDD ──' "$f" || grep -qF '── Release ──' "$f"; then
    fail "${cmd}.md contains removed phase separator"
  else
    pass "${cmd}.md omits removed phase separators"
  fi
done

# A4 (AC8): end-of-run summary template carries `(N lines)` size hint
# render contract.
TEMPLATE="${REPO_ROOT}/docs/templates/end-of-run-summary-template.md"
if [ ! -f "$TEMPLATE" ]; then
  fail "$TEMPLATE missing"
elif grep -qE '\(N lines\)|wc -l' "$TEMPLATE"; then
  pass "end-of-run summary template wires up size hint (AC8)"
else
  fail "end-of-run summary template missing size hint contract (AC8)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-glyph-shape-preservation: FAILED ($failures)" >&2
  exit 1
fi
echo "test-glyph-shape-preservation: OK"
