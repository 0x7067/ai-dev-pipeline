#!/usr/bin/env bash
set -euo pipefail

errors=0
strict_mode="${WORKFLOW_REQUIRE_ARTIFACTS:-0}"

note() {
  echo "workflow-artifacts: $*"
}

fail() {
  echo "workflow-artifacts: ERROR: $*"
  errors=$((errors + 1))
}

check_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    fail "missing required artifact: $file"
    return
  fi

  if [ ! -s "$file" ]; then
    if [ "$strict_mode" = "1" ]; then
      fail "$file is empty (active run requires populated artifacts)"
    else
      note "skipping content check for empty $file (set WORKFLOW_REQUIRE_ARTIFACTS=1 to enforce)"
    fi
  fi
}

check_file "docs/current-plan.md"
check_file "docs/impl-summary.md"
check_file "docs/review-report.md"
check_file "docs/test-report.md"
check_file "docs/verify-report.md"

if [ "$errors" -gt 0 ]; then
  echo "workflow-artifacts: FAILED with $errors issue(s)"
  exit 1
fi

echo "workflow-artifacts: OK"
exit 0
