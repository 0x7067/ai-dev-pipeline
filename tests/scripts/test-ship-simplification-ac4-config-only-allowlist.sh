#!/usr/bin/env bash
# AC4: When all touched files match the config-only allowlist, the
# orchestrator classifies the change as `config_only` and skips TDD
# pre-phase + tester invocation.
#
# Source-of-truth contract test (Markdown-as-prose-script):
#   ship.md MUST document the config_only classification, the
#   git-diff--name-only authoritative source, and the TDD/tester skip.
#
# Until implementation lands, ship.md only knows about the `trivial`
# carve-out — these assertions are expected to FAIL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SHIP_MD="${REPO_ROOT}/.claude/commands/ship.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$SHIP_MD" ] || { echo "ship.md missing" >&2; exit 2; }

# 1. config_only token introduced in ship.md
if grep -qE '\bconfig_only\b' "$SHIP_MD"; then
  pass "ship.md mentions config_only"
else
  fail "ship.md does not introduce config_only change-class (AC4)"
fi

# 2. Authoritative diff source documented
if grep -qE 'git diff --name-only' "$SHIP_MD"; then
  pass "ship.md documents git diff --name-only as the authoritative source"
else
  fail "ship.md missing git diff --name-only authoritative source (AC4)"
fi

# 3. Skip mechanic for tester / TDD pre-phase under config_only
if grep -qE 'config_only.*(skip|skipped).*(TDD|tester)' "$SHIP_MD" \
   || grep -qE '(TDD|tester).*(skip|skipped).*config_only' "$SHIP_MD"; then
  pass "ship.md documents TDD/tester skip under config_only"
else
  fail "ship.md does not document TDD/tester skip for config_only (AC4)"
fi

# 4. Allowlist surface documented (any of: *.md, *.yaml, *.yml, *.json,
#    .claude/ subtrees). At minimum the .claude/ subtree gate must appear.
if grep -qE '\.claude/(agents|skills|rules|hooks)' "$SHIP_MD"; then
  pass ".claude/ subtree mentioned in allowlist"
else
  fail "config-only allowlist .claude/{agents,skills,rules,hooks} missing in ship.md (AC4)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac4-config-only-allowlist: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac4-config-only-allowlist: OK"
