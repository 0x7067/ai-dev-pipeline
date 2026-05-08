#!/usr/bin/env bash
# Contract tests for resolve_workflow_state_path (in .claude/hooks/_hook_lib.sh).
#
# Invariant under test: plan/spec invariant 8 — "Workflow-state isolation".
# Hooks resolve .claude/workflow-state/<active>.json at fire time; no two
# concurrent runs target the same path; a malformed active pointer falls
# back to the legacy single-state file rather than echoing an unparsed
# value into a path expression.
#
# Cases:
#   1. Explicit WORKFLOW_STATE_PATH wins over every other source.
#   2. Active pointer with parseable run-id resolves to per-run JSON path.
#   3. Active pointer with malformed content falls back to legacy default
#      (fail-closed: never construct a path from an unparsed run-id).
#   4. Missing active pointer with no override → legacy default.
#   5. Two distinct active pointers (simulated as two cwd sandboxes) yield
#      two distinct resolved paths — concurrent /ship sessions never
#      collide on a single workflow-state JSON.
#   6. Late binding: changing the active pointer between two calls in the
#      same shell yields the new path (resolution happens at fire time,
#      not at hook-load time).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
HOOK_LIB="${REPO_ROOT}/.claude/hooks/_hook_lib.sh"
PARSER="${REPO_ROOT}/scripts/parse-run-id.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$HOOK_LIB" ] || { echo "hook lib missing at $HOOK_LIB" >&2; exit 2; }

# Each case runs in its own sandbox + subshell so cd, env, and pointer
# files never leak. We vendor the parser into the sandbox because the
# resolver in _hook_lib.sh probes scripts/parse-run-id.sh relative to cwd.
make_sandbox() {
  local sb
  sb=$(mktemp -d)
  mkdir -p "$sb/.claude/workflow-state" "$sb/scripts"
  cp "$PARSER" "$sb/scripts/parse-run-id.sh"
  chmod +x "$sb/scripts/parse-run-id.sh"
  printf '%s\n' "$sb"
}

VALID_ID_A="20260508T143022-a1b2c3-7f"
VALID_ID_B="20260509T091500Z-deadbe-01"

# --- Case 1: explicit override wins ---
sb=$(make_sandbox)
got=$(
  cd "$sb" || exit 99
  printf '%s\n' "$VALID_ID_A" > .claude/workflow-state/active
  # shellcheck source=/dev/null
  WORKFLOW_STATE_PATH="/tmp/explicit-override.json" \
    env HOOK_NAME=test bash -c "source '$HOOK_LIB'; resolve_workflow_state_path"
)
if [ "$got" = "/tmp/explicit-override.json" ]; then
  pass "explicit WORKFLOW_STATE_PATH wins over active pointer"
else
  fail "explicit override ignored (got=$got)"
fi
rm -rf "$sb"

# --- Case 2: active pointer with parseable id → per-run path ---
sb=$(make_sandbox)
got=$(
  cd "$sb" || exit 99
  printf '%s\n' "$VALID_ID_A" > .claude/workflow-state/active
  unset WORKFLOW_STATE_PATH
  env HOOK_NAME=test bash -c "source '$HOOK_LIB'; resolve_workflow_state_path"
)
expected=".claude/workflow-state/${VALID_ID_A}.json"
if [ "$got" = "$expected" ]; then
  pass "active pointer with parseable id → $expected"
else
  fail "expected $expected, got $got"
fi
rm -rf "$sb"

# --- Case 3: malformed active content → legacy default (fail-closed) ---
sb=$(make_sandbox)
got=$(
  cd "$sb" || exit 99
  # Path-traversal poison: if the resolver echoed this unparsed, it
  # would land on .claude/workflow-state/../../../../etc/passwd.json.
  printf '%s\n' "../../../../etc/passwd" > .claude/workflow-state/active
  unset WORKFLOW_STATE_PATH
  env HOOK_NAME=test bash -c "source '$HOOK_LIB'; resolve_workflow_state_path"
)
if [ "$got" = ".claude/workflow-state.json" ]; then
  pass "malformed active content falls back to legacy default (no traversal)"
else
  fail "expected legacy fallback, got $got (parse-once invariant violated)"
fi
rm -rf "$sb"

# --- Case 4: missing active pointer + no override → legacy default ---
sb=$(make_sandbox)
got=$(
  cd "$sb" || exit 99
  unset WORKFLOW_STATE_PATH
  env HOOK_NAME=test bash -c "source '$HOOK_LIB'; resolve_workflow_state_path"
)
if [ "$got" = ".claude/workflow-state.json" ]; then
  pass "no active pointer + no override → legacy default"
else
  fail "expected legacy default, got $got"
fi
rm -rf "$sb"

# --- Case 5: two concurrent runs resolve to two distinct paths ---
sb_a=$(make_sandbox)
sb_b=$(make_sandbox)
printf '%s\n' "$VALID_ID_A" > "$sb_a/.claude/workflow-state/active"
printf '%s\n' "$VALID_ID_B" > "$sb_b/.claude/workflow-state/active"
got_a=$( cd "$sb_a" && unset WORKFLOW_STATE_PATH && env HOOK_NAME=test bash -c "source '$HOOK_LIB'; resolve_workflow_state_path" )
got_b=$( cd "$sb_b" && unset WORKFLOW_STATE_PATH && env HOOK_NAME=test bash -c "source '$HOOK_LIB'; resolve_workflow_state_path" )
if [ "$got_a" != "$got_b" ] \
   && [ "$got_a" = ".claude/workflow-state/${VALID_ID_A}.json" ] \
   && [ "$got_b" = ".claude/workflow-state/${VALID_ID_B}.json" ]; then
  pass "two concurrent active pointers resolve to two distinct per-run paths"
else
  fail "isolation violated: a=$got_a b=$got_b"
fi
rm -rf "$sb_a" "$sb_b"

# --- Case 6: late binding (resolution at fire time, not at load time) ---
sb=$(make_sandbox)
got=$(
  cd "$sb" || exit 99
  unset WORKFLOW_STATE_PATH
  printf '%s\n' "$VALID_ID_A" > .claude/workflow-state/active
  env HOOK_NAME=test bash -c "
    source '$HOOK_LIB'
    first=\$(resolve_workflow_state_path)
    printf '%s\n' '$VALID_ID_B' > .claude/workflow-state/active
    second=\$(resolve_workflow_state_path)
    printf '%s|%s\n' \"\$first\" \"\$second\"
  "
)
first="${got%%|*}"
second="${got##*|}"
if [ "$first" = ".claude/workflow-state/${VALID_ID_A}.json" ] \
   && [ "$second" = ".claude/workflow-state/${VALID_ID_B}.json" ]; then
  pass "late binding: pointer change between calls is observed"
else
  fail "late binding broken: first=$first second=$second"
fi
rm -rf "$sb"

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-state-resolver: FAILED ($failures)" >&2
  exit 1
fi
echo "test-workflow-state-resolver: OK"
