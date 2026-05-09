#!/usr/bin/env bash
# Verifies lean phase prerequisites enforced by workflow-gate.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
cd "$REPO_ROOT" || exit 1

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  skip: jq not installed; workflow-gate strict path requires jq" >&2
  echo "test-workflow-gate-lean-order: SKIP"
  exit 0
fi

tmpdir="$(mktemp -d -t workflow-gate-lean.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

state_with() {
  local path="$1"
  shift
  local phases=(plan implement review test verify)
  {
    printf '{"phases":{'
    local first=1
    local phase completed
    for phase in "${phases[@]}"; do
      completed=false
      for done_phase in "$@"; do
        [ "$done_phase" = "$phase" ] && completed=true
      done
      [ "$first" -eq 0 ] && printf ','
      first=0
      printf '"%s":{"completed":%s}' "$phase" "$completed"
    done
    printf '}}\n'
  } > "$path"
}

payload_for() {
  printf '{"tool_name":"Agent","tool_input":{"subagent_type":"%s"}}\n' "$1"
}

run_gate() {
  local state="$1" agent="$2" out="$tmpdir/out"
  payload_for "$agent" | WORKFLOW_STATE_PATH="$state" bash .claude/hooks/workflow-gate.sh >"$out" 2>&1
  rc=$?
  output="$(cat "$out")"
}

state="$tmpdir/plan.json"
state_with "$state" plan
run_gate "$state" implementer
if [ "$rc" = 0 ]; then pass "implementer permitted after plan"; else fail "implementer blocked after plan: $output"; fi

state="$tmpdir/implement.json"
state_with "$state" plan implement
run_gate "$state" reviewer
if [ "$rc" = 0 ]; then pass "reviewer permitted after implement"; else fail "reviewer blocked after implement: $output"; fi

run_gate "$state" verifier
if [ "$rc" != 0 ] && printf '%s' "$output" | grep -q "requires 'review'"; then
  pass "verifier blocked before review"
else
  fail "verifier was not blocked before review (rc=$rc out=$output)"
fi

state="$tmpdir/review.json"
state_with "$state" plan implement review
run_gate "$state" verifier
if [ "$rc" = 0 ]; then pass "verifier permitted after review"; else fail "verifier blocked after review: $output"; fi

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-gate-lean-order: FAILED ($failures)" >&2
  exit 1
fi

echo "test-workflow-gate-lean-order: OK"
