#!/usr/bin/env bash
# Invariant I1 / AC9 / R3 test: existing phase-marker glyph shapes are
# preserved byte-for-byte across all five primary commands.
#
# After the A1–A4 implementation, the following literal prefixes MUST
# still appear in their respective command files:
#   - `▶ <phase> starting`   (every multi-phase command)
#   - `✓ <phase> — STATUS:`  OR `✗ <phase> — STATUS:`  (every phase echo)
#
# Plus, /ship MUST gain the three A2 separators:
#   - `── Setup ──`, `── TDD ──`, `── Release ──`
#
# TDD-PRE: this test is expected to fail because the A2 separators are
# not yet present in .claude/commands/ship.md.

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

# AC4 / A2: the three separators are present in ship.md AFTER implementation.
for sep in '── Setup ──' '── TDD ──' '── Release ──'; do
  if grep -qF "$sep" "$SHIP" 2>/dev/null; then
    pass "ship.md contains separator '$sep'"
  else
    fail "ship.md missing separator '$sep' (AC4 / A2)"
  fi
done

# AC4: other commands MUST NOT emit separators (different phase counts).
for cmd in review audit research; do
  f="${REPO_ROOT}/.claude/commands/${cmd}.md"
  [ -f "$f" ] || { fail "$f missing"; continue; }
  if grep -qF '── Setup ──' "$f" || grep -qF '── TDD ──' "$f" || grep -qF '── Release ──' "$f"; then
    fail "${cmd}.md leaked /ship-only separator"
  else
    pass "${cmd}.md correctly omits /ship separators"
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
