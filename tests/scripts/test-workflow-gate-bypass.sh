#!/usr/bin/env bash
# Verifies the in-band bypass token honored by workflow-gate.sh:
#   - valid token with reason → passes, writes audit log
#   - missing token → blocks normally
#   - malformed token (no reason) → blocks
#   - token beyond the 200-char anchor → blocks
#   - blocked failure message names the bypass

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
cd "$REPO_ROOT" || exit 1

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  skip: jq required" >&2
  echo "test-workflow-gate-bypass: SKIP"
  exit 0
fi

tmpdir="$(mktemp -d -t workflow-gate-bypass.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# State with NO phases completed → implementer would normally be blocked.
state="$tmpdir/empty.json"
printf '{"phases":{"plan":{"completed":false}}}\n' > "$state"

run_gate() {
  local prompt="$1" out="$tmpdir/out"
  local payload
  payload="$(jq -cn --arg p "$prompt" \
    '{tool_name:"Agent", tool_input:{subagent_type:"implementer", prompt:$p}}')"
  printf '%s' "$payload" | \
    WORKFLOW_STATE_PATH="$state" RUN_DIR="$tmpdir" RUN_ID="test-run" \
    bash .claude/hooks/workflow-gate.sh >"$out" 2>&1
  rc=$?
  output="$(cat "$out")"
}

# Case 1: valid token → pass + audit log
rm -f "$tmpdir/gate-bypass.log"
run_gate "[gate-bypass: ad-hoc edit on stale state] do the thing"
if [ "$rc" = 0 ] && [ -s "$tmpdir/gate-bypass.log" ]; then
  if jq -e '.reason == "ad-hoc edit on stale state" and .agent_type == "implementer"' \
       "$tmpdir/gate-bypass.log" >/dev/null 2>&1; then
    pass "valid bypass token honored and audited"
  else
    fail "audit log malformed: $(cat "$tmpdir/gate-bypass.log")"
  fi
else
  fail "valid bypass not honored (rc=$rc, log_size=$(wc -c <"$tmpdir/gate-bypass.log" 2>/dev/null || echo 0))"
fi

# Case 2: no token → blocked with bypass-naming message
run_gate "just implement the feature please"
if [ "$rc" = 2 ] && printf '%s' "$output" | grep -q 'gate-bypass:' && \
   printf '%s' "$output" | grep -q 'WORKFLOW_GATES_SKIP'; then
  pass "no token → blocked with discoverable bypass message"
else
  fail "missing-token case: rc=$rc, output=$output"
fi

# Case 3: malformed token (empty reason) → blocked
run_gate "[gate-bypass: ] empty reason should fail closed"
if [ "$rc" = 2 ]; then
  pass "malformed token (empty reason) fails closed"
else
  fail "malformed token unexpectedly honored (rc=$rc)"
fi

# Case 4: token beyond 200-char anchor → blocked
pad="$(printf 'x%.0s' {1..220})"
run_gate "${pad}[gate-bypass: hidden]"
if [ "$rc" = 2 ]; then
  pass "token past 200-char anchor is ignored"
else
  fail "anchor not enforced (rc=$rc)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-gate-bypass: FAILED ($failures)" >&2
  exit 1
fi

echo "test-workflow-gate-bypass: OK"
