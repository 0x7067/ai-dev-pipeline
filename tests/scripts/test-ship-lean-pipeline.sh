#!/usr/bin/env bash
# Contract test for the lean /ship pipeline.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"
RULES_MD="${REPO_ROOT}/.claude/rules/release-and-verification.md"
PLANNER_MD="${REPO_ROOT}/.claude/agents/planner.md"
VERIFY_TPL="${REPO_ROOT}/docs/templates/verify-report-template.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

if grep -q 'optional research -> plan -> implement -> review -> verify -> smoke -> release' "$SHIP_MD"; then
  pass "ship.md documents the lean phase path"
else
  fail "ship.md does not document the lean phase path"
fi

if grep -qE "/ship.*default.*auto|/ship\` or \`/ship auto\`" "$SHIP_MD"; then
  pass "default /ship auto mode documented"
else
  fail "default /ship auto mode missing"
fi

if grep -q '/ship fast.*legacy' "$SHIP_MD" && grep -q '/ship adaptive.*legacy' "$SHIP_MD"; then
  pass "legacy fast/adaptive tokens are rejected"
else
  fail "legacy fast/adaptive rejection missing"
fi

if grep -q 'mandatory TDD' "$SHIP_MD" || grep -q 'config_only' "$SHIP_MD" || grep -q 'fast-low' "$SHIP_MD"; then
  fail "ship.md still contains removed branch language"
else
  pass "removed branch language absent from ship.md"
fi

if grep -q "risk=low" "$RULES_MD" && grep -q "mode is \`auto\`" "$RULES_MD"; then
  pass "rules document low-risk auto release condition"
else
  fail "rules do not document low-risk auto release condition"
fi

if grep -q 'change-class=' "$PLANNER_MD"; then
  fail "planner STATUS still requires removed change-class token"
else
  pass "planner STATUS no longer requires change-class"
fi

if grep -q 'Advisory review findings (folded)' "$VERIFY_TPL"; then
  fail "verify template still contains folded-review section"
else
  pass "verify template no longer contains folded-review section"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ship-lean-pipeline: FAILED ($failures)" >&2
  exit 1
fi

echo "test-ship-lean-pipeline: OK"
