#!/usr/bin/env bash
# Tests for .claude/hooks/plan-gate.sh — focused on the new bypass branches:
#  - project opt-in detection
#  - trivial-shape bypass (test files, lockfiles, single-line diffs, comment-only diffs)
#
# Each test sets up an isolated cwd with controlled markers, pipes a payload
# to the hook, and asserts the exit code.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/plan-gate.sh"

if [ ! -x "$HOOK" ] && [ ! -f "$HOOK" ]; then
  echo "missing hook: $HOOK" >&2
  exit 2
fi

pass=0; fail=0
fail_names=()

run_case() {
  local name="$1" want_rc="$2" payload="$3" cwd="$4"
  local got_rc=0
  ( cd "$cwd" && printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1 ) || got_rc=$?
  if [ "$got_rc" = "$want_rc" ]; then
    pass=$((pass + 1))
    printf '  ✓ %s (rc=%s)\n' "$name" "$got_rc"
  else
    fail=$((fail + 1))
    fail_names+=("$name (want=$want_rc got=$got_rc)")
    printf '  ✗ %s (want=%s got=%s)\n' "$name" "$want_rc" "$got_rc"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Fixture: non-pipeline project (no approvals.yaml anywhere) ---
NONPIPELINE="$TMP/nonpipeline"
mkdir -p "$NONPIPELINE/src"

# --- Fixture: pipeline project (has approvals.yaml at root) ---
PIPELINE="$TMP/pipeline"
mkdir -p "$PIPELINE/.claude/policy" "$PIPELINE/src"
printf 'plan_gate: {}\n' > "$PIPELINE/.claude/policy/approvals.yaml"

# --- Fixture: pipeline subdir (cwd is nested below approvals.yaml) ---
PIPELINE_SUB="$PIPELINE/packages/shared/src"
mkdir -p "$PIPELINE_SUB"

echo "== plan-gate hook tests =="

# 0a. Non-pipeline repo — every edit should pass even without payload.
run_case "non-pipeline repo: no approvals.yaml -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$NONPIPELINE"'/src/index.js","old_string":"a\nb","new_string":"c\nd"}}' \
  "$NONPIPELINE"

# 0b. Pipeline repo (root cwd): non-trivial multi-line edit on a non-meta path
#     should block.
run_case "pipeline repo: multi-line edit on non-meta path -> blocked" 2 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/src/app.js","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

# 0c. Pipeline subdir: opt-in detection walks up to find approvals.yaml.
run_case "pipeline subdir: walk-up finds approvals.yaml -> still gates" 2 \
  '{"tool_input":{"file_path":"'"$PIPELINE_SUB"'/foo.ts","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE_SUB"

# 1. Trivial: test file
run_case "pipeline repo: edit to *.test.ts -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/src/foo.test.ts","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

run_case "pipeline repo: edit to *_test.go -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/pkg/foo_test.go","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

run_case "pipeline repo: edit under __tests__/ -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/src/__tests__/x.js","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

# 2. Trivial: lockfile
run_case "pipeline repo: pnpm-lock.yaml -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/pnpm-lock.yaml","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

run_case "pipeline repo: package-lock.json -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/package-lock.json","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

run_case "pipeline repo: Cargo.lock -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/Cargo.lock","old_string":"a\nb","new_string":"c\nd"}}' \
  "$PIPELINE"

# 3. Trivial: single-line diff (no \n in either side) on a non-meta, non-test path
run_case "pipeline repo: single-line edit on src/app.js -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/src/app.js","old_string":"foo","new_string":"bar"}}' \
  "$PIPELINE"

# 4. Trivial: comment-only edit (multi-line, but all lines are comments)
run_case "pipeline repo: comment-only // diff -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/src/app.js","old_string":"// hello\n// world","new_string":"// goodbye\n// world"}}' \
  "$PIPELINE"

run_case "pipeline repo: comment-only # diff -> exit 0" 0 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/scripts/foo.py","old_string":"# a\n# b","new_string":"# c\n# d"}}' \
  "$PIPELINE"

# 5. Negative: multi-line code edit in pipeline repo on non-meta path -> blocked
run_case "pipeline repo: multi-line code edit -> blocked" 2 \
  '{"tool_input":{"file_path":"'"$PIPELINE"'/src/app.js","old_string":"function a() {\n  return 1\n}","new_string":"function a() {\n  return 2\n}"}}' \
  "$PIPELINE"

# 6. Bypass env still works in pipeline repo
PLAN_GATE_BYPASS_PAYLOAD='{"tool_input":{"file_path":"'"$PIPELINE"'/src/app.js","old_string":"a\nb","new_string":"c\nd"}}'
got_rc=0
( cd "$PIPELINE" && printf '%s' "$PLAN_GATE_BYPASS_PAYLOAD" | PLAN_GATE_BYPASS=1 bash "$HOOK" >/dev/null 2>&1 ) || got_rc=$?
if [ "$got_rc" = "0" ]; then
  pass=$((pass + 1))
  printf '  ✓ pipeline repo: PLAN_GATE_BYPASS=1 -> exit 0\n'
else
  fail=$((fail + 1))
  fail_names+=("PLAN_GATE_BYPASS=1 (want=0 got=$got_rc)")
  printf '  ✗ pipeline repo: PLAN_GATE_BYPASS=1 -> got %s\n' "$got_rc"
fi

echo
echo "passed: $pass  failed: $fail"
if [ "$fail" -ne 0 ]; then
  printf 'failed:\n'
  for n in "${fail_names[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
exit 0
