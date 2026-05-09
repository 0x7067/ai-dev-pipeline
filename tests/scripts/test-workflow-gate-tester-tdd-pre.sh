#!/usr/bin/env bash
# Regression test: .claude/hooks/workflow-gate.sh tester gate.
#
# The tester agent runs in two positions under /ship: tdd-pre (after plan,
# before implement) and tdd-post (after implement). The hook gates `tester`
# on `phase_completed("plan")` so both positions are allowed; the orchestrator
# (ship.md) enforces the stricter ordering.
#
# This test pins:
#   1. tester is PERMITTED when only `plan` is completed.
#   2. tester is BLOCKED when nothing is completed.
#   3. tester is PERMITTED when both `plan` and `implement` are completed
#      (tdd-post case).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
HOOK="${REPO_ROOT}/.claude/hooks/workflow-gate.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

if [ ! -f "$HOOK" ]; then
  fail "hook missing: $HOOK"
  echo "test-workflow-gate-tester-tdd-pre: FAILED ($failures)" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "  skip: jq not installed; the hook's strict gate path requires jq" >&2
  echo "test-workflow-gate-tester-tdd-pre: SKIP"
  exit 0
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

write_state() {
  # $1 = path, remaining args = phase names that should be completed=true
  local path="$1"; shift
  local entries=()
  for ph in plan implement test review verify; do
    local done="false"
    for c in "$@"; do
      if [ "$c" = "$ph" ]; then done="true"; fi
    done
    entries+=("\"$ph\": {\"completed\": $done}")
  done
  local joined
  joined=$(IFS=,; echo "${entries[*]}")
  printf '{"phases": {%s}}\n' "$joined" > "$path"
}

run_gate() {
  # $1 = state file, $2 = agent type
  local sf="$1" agent="$2"
  local payload
  payload=$(printf '{"tool_name":"Agent","tool_input":{"subagent_type":"%s"}}' "$agent")
  printf '%s' "$payload" | WORKFLOW_STATE_PATH="$sf" bash "$HOOK"
  return $?
}

# --- Case 1: only plan completed → tester PERMITTED ---
state1="$sandbox/state-plan-only.json"
write_state "$state1" plan
out=$(run_gate "$state1" tester 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "tester permitted when only 'plan' is completed (tdd-pre position)"
else
  fail "tester unexpectedly blocked at tdd-pre (rc=$rc, out=$out)"
fi

# --- Case 2: nothing completed → tester BLOCKED ---
state2="$sandbox/state-empty.json"
write_state "$state2"
out=$(run_gate "$state2" tester 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "tester blocked when no phase is completed"
else
  fail "tester not blocked at empty state (rc=$rc, out=$out)"
fi
if printf '%s' "$out" | grep -q "BLOCKED"; then
  pass "tester block message includes 'BLOCKED'"
else
  fail "tester block message missing 'BLOCKED' marker (out=$out)"
fi

# --- Case 3: plan + implement completed → tester PERMITTED (tdd-post) ---
state3="$sandbox/state-plan-impl.json"
write_state "$state3" plan implement
out=$(run_gate "$state3" tester 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "tester permitted at tdd-post (plan+implement complete)"
else
  fail "tester unexpectedly blocked at tdd-post (rc=$rc, out=$out)"
fi

# --- Case 4 (control): implementer still requires plan, blocked when empty ---
out=$(run_gate "$state2" implementer 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "control: implementer still blocked when nothing completed"
else
  fail "control: implementer gate broken (rc=$rc, out=$out)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-gate-tester-tdd-pre: FAILED ($failures)" >&2
  exit 1
fi
echo "test-workflow-gate-tester-tdd-pre: OK"
