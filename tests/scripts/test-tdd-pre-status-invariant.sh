#!/usr/bin/env bash
# Contract test: tdd-pre tester STATUS line invariant.
#
# Per docs/specs/tdd-mode.md and docs/current-plan.md invariant #11:
#   In tdd-pre mode, `expected_failing == failing == added > 0`.
#
# This test encodes the invariant as a string-grammar check against a
# small set of hand-crafted STATUS lines. A STATUS line claiming
# `expected_failing=N` is INVALID unless `failing=N` AND `added=N`.
#
# This pins the latent contract drift surfaced in docs/review-report.md
# (WARNING: orchestrator currently checks expected_failing==failing only,
# not expected_failing==added).

set -uo pipefail

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Pure-shell parser: extract added=N, failing=N, expected_failing=N from a
# STATUS line and decide whether the tdd-pre invariant holds.
#
# Returns:
#   0 = invariant holds (added == failing == expected_failing > 0)
#   1 = invariant violated
#   2 = malformed (missing required field for tdd-pre)
check_tdd_pre_invariant() {
  local line="$1"
  local added failing expected
  added=$(printf '%s\n' "$line" | grep -oE 'added=[0-9]+' | head -1 | cut -d= -f2)
  failing=$(printf '%s\n' "$line" | grep -oE 'failing=[0-9]+' | head -1 | cut -d= -f2)
  expected=$(printf '%s\n' "$line" | grep -oE 'expected_failing=[0-9]+' | head -1 | cut -d= -f2)
  if [ -z "$added" ] || [ -z "$failing" ] || [ -z "$expected" ]; then
    return 2
  fi
  if [ "$added" -le 0 ]; then
    return 1
  fi
  if [ "$added" = "$failing" ] && [ "$failing" = "$expected" ]; then
    return 0
  fi
  return 1
}

# --- Cases ---

# Valid: 4 added, 4 failing, 4 expected_failing
line='STATUS: ok | added=4 failing=4 expected_failing=4 | red tests written | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 0 ]; then pass "valid: added=failing=expected_failing=4"
else fail "valid case rejected (rc=$rc): $line"; fi

# Drift case from review-report.md: added=5, failing=4, expected_failing=4.
# Orchestrator currently passes; per spec invariant #11 this MUST be rejected.
line='STATUS: ok | added=5 failing=4 expected_failing=4 | one test passes accidentally | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 1 ]; then pass "drift rejected: added=5 failing=4 expected_failing=4"
else fail "drift case not rejected (rc=$rc): $line"; fi

# Inverse drift: more failing than added — also a violation.
line='STATUS: ok | added=3 failing=4 expected_failing=4 | impossible counts | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 1 ]; then pass "rejected: failing > added"
else fail "failing>added not rejected (rc=$rc)"; fi

# Zero-added: tdd-pre with zero new tests is `blocked` per invariant #11.
line='STATUS: ok | added=0 failing=0 expected_failing=0 | nothing to write | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 1 ]; then pass "rejected: added=0 in tdd-pre"
else fail "added=0 not rejected (rc=$rc)"; fi

# Missing expected_failing in a tdd-pre status line: malformed.
line='STATUS: ok | added=4 failing=4 | missing expected_failing | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 2 ]; then pass "malformed: missing expected_failing"
else fail "missing expected_failing not flagged malformed (rc=$rc)"; fi

# Expected_failing != failing: orchestrator already catches this; encode anyway.
line='STATUS: ok | added=4 failing=4 expected_failing=3 | inconsistent | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 1 ]; then pass "rejected: expected_failing != failing"
else fail "expected_failing != failing not rejected (rc=$rc)"; fi

# Token-order independence: order of added/failing/expected_failing tokens
# must not affect the decision.
line='STATUS: ok | expected_failing=2 added=2 failing=2 | order shuffled | report=docs/test-report.md'
check_tdd_pre_invariant "$line"
rc=$?
if [ "$rc" = 0 ]; then pass "valid regardless of token order"
else fail "token order changed decision (rc=$rc)"; fi

if [ "$failures" -eq 0 ]; then
  echo "tdd-pre-status-invariant: ok"
  exit 0
fi
echo "tdd-pre-status-invariant: $failures failure(s)" >&2
exit 1
