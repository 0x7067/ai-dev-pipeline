#!/usr/bin/env bash
# AC6: Under change_class=config_only, verify executes
#   - bash scripts/validate-claude-config.sh
#   - configured lint
#   and property/contract/full-suite gates self-skip via the empty-command
#   path. verify-report.md is still produced.
#
# Source-of-truth contracts:
#   - ship.md documents the env-var profile preset for config_only.
#   - .claude/rules/release-and-verification.md endorses it under
#     "Canonical Gate Runner".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"
RULES_MD="${REPO_ROOT}/.claude/rules/release-and-verification.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }
[ -f "$RULES_MD" ] || { echo "release-and-verification.md missing" >&2; exit 2; }

# 1. ship.md OR rules doc documents the config_only profile preset using
#    the validate-claude-config.sh lint.
if grep -qE 'config_only.*validate-claude-config\.sh|validate-claude-config\.sh.*config_only' "$SHIP_MD" "$RULES_MD" 2>/dev/null; then
  pass "config_only profile preset documents validate-claude-config.sh"
else
  fail "config_only verify-narrowing not documented (AC6)"
fi

# 2. Empty-command self-skip via override env vars (e.g. VERIFY_TYPECHECK_CMD=":"
#    or VERIFY_PROPERTY_CMD=":"). Either ship.md or rules doc must show how
#    config_only narrows the gates.
if grep -qE 'VERIFY_(TYPECHECK|LINT|SECURITY|PROPERTY|CONTRACT)_CMD' "$SHIP_MD" "$RULES_MD" 2>/dev/null; then
  pass "config_only narrowing uses VERIFY_*_CMD overrides"
else
  fail "config_only narrowing does not reference VERIFY_*_CMD env-var profile (AC6)"
fi

# 3. verify-report.md must remain produced. The Output Artifacts contract
#    in release-and-verification.md must continue to list it (regression).
if grep -qE 'docs/verify-report\.md|verify-report\.md' "$RULES_MD"; then
  pass "verify-report.md still in Output Artifacts contract"
else
  fail "verify-report.md output artifact removed (regression I5/AC6)"
fi

# 4. Rules doc explicitly endorses config_only narrowing under
#    "Canonical Gate Runner".
if awk '/^## Canonical Gate Runner/,/^## /' "$RULES_MD" | grep -qE 'config_only'; then
  pass "Canonical Gate Runner section endorses config_only narrowing"
else
  fail "Canonical Gate Runner does not endorse config_only narrowing (AC6)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac6-config-only-verify-narrowing: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac6-config-only-verify-narrowing: OK"
