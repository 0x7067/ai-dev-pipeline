#!/usr/bin/env bash
# Contract test: implementer no-touch list contract drift.
#
# docs/review-report.md WARNING #1 surfaces a latent contract drift:
# the implementer derives the no-touch test-file set from the
# `## TDD-Pre Tests` section of docs/test-report.md, but the
# implementer's STATUS line does NOT echo that list (or its hash) so
# that downstream review can independently verify the implementer
# read and respected it.
#
# This test scans .claude/agents/implementer.md and asserts:
#   (1) The implementer is explicitly obligated to read the
#       `## TDD-Pre Tests` section of docs/test-report.md.
#   (2) The implementer's tdd-post STATUS line shape includes a
#       no-touch echo: a `no_touch=` token (a count, list, or hash)
#       that lets the orchestrator/reviewer verify the contract.
#
# Assertion (1) is expected to PASS today.
# Assertion (2) is expected to FAIL today — it pins the contract
# drift identified in the review report. When the implementer.md
# contract is fixed (e.g. STATUS gains `no_touch_sha=<hex>` or
# `no_touch=N`), this test goes green automatically.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
IMPL_MD="${REPO_ROOT}/.claude/agents/implementer.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$IMPL_MD" ] || { echo "implementer.md missing at $IMPL_MD" >&2; exit 2; }

# (1) Obligation to read the `## TDD-Pre Tests` section.
if grep -qE '## TDD-Pre Tests' "$IMPL_MD" \
   && grep -qiE 'docs/test-report\.md' "$IMPL_MD"; then
  pass "implementer.md references docs/test-report.md '## TDD-Pre Tests'"
else
  fail "implementer.md does not obligate reading '## TDD-Pre Tests' from docs/test-report.md"
fi

# (2) STATUS line echoes the no-touch list (or its hash/count).
# Look for any of these tokens in the documented STATUS shape:
#   no_touch=<n>           (count of no-touch entries)
#   no_touch_sha=<hex>     (hash of the canonicalised list)
#   no_touch_files=<n>     (alternate count name)
#   no_touch_hash=<hex>    (alternate hash name)
#
# Any of these proves the contract has been closed; absence of all
# four is the drift surfaced by review-report.md WARNING #1.
if grep -qE 'no_touch(_sha|_hash|_files)?=' "$IMPL_MD"; then
  pass "implementer STATUS echoes no_touch list (drift closed)"
else
  fail "implementer STATUS does not echo no_touch list — contract drift per review-report.md WARNING #1"
fi

if [ "$failures" -eq 0 ]; then
  echo "implementer-no-touch-contract: ok"
  exit 0
fi
echo "implementer-no-touch-contract: $failures failure(s)" >&2
exit 1
