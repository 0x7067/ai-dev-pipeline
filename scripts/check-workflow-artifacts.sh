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
    if [ "$strict_mode" = "1" ]; then
      fail "missing required artifact: $file"
    else
      note "skipping missing artifact check for $file (set WORKFLOW_REQUIRE_ARTIFACTS=1 to enforce)"
    fi
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

spec_files=(docs/specs/*.md)
if [ "${spec_files[0]}" = "docs/specs/*.md" ]; then
  if [ "$strict_mode" = "1" ]; then
    fail "missing required artifact: docs/specs/<feature>.md"
  else
    note "skipping spec check (no docs/specs/*.md found, set WORKFLOW_REQUIRE_ARTIFACTS=1 to enforce)"
  fi
else
  if [ "$strict_mode" = "1" ]; then
    for spec_file in "${spec_files[@]}"; do
      if [ ! -s "$spec_file" ]; then
        fail "$spec_file is empty (active run requires populated specs)"
      fi
    done
  fi
fi

if [ "$errors" -gt 0 ]; then
  echo "workflow-artifacts: FAILED with $errors issue(s)"
  exit 1
fi

echo "workflow-artifacts: OK"
exit 0
