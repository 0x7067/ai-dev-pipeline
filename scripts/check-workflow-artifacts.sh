#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

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

default_artifact_path() {
  local name="$1"
  if [ -n "${RUN_DIR:-}" ]; then
    printf '%s/%s\n' "$RUN_DIR" "$name"
  elif [ -L "docs/latest" ] || [ -d "docs/latest" ]; then
    printf 'docs/latest/%s\n' "$name"
  else
    printf 'docs/%s\n' "$name"
  fi
}

default_specs_glob() {
  if [ -n "${RUN_DIR:-}" ]; then
    printf '%s/specs/*.md\n' "$RUN_DIR"
  elif [ -L "docs/latest" ] || [ -d "docs/latest" ]; then
    printf 'docs/latest/specs/*.md\n'
  else
    printf 'docs/specs/*.md\n'
  fi
}

plan_file="${WORKFLOW_PLAN_PATH:-$(default_artifact_path current-plan.md)}"
review_file="${WORKFLOW_REVIEW_PATH:-$(default_artifact_path review-report.md)}"
test_file="${WORKFLOW_TEST_PATH:-$(default_artifact_path test-report.md)}"
verify_file="${WORKFLOW_VERIFY_PATH:-$(default_artifact_path verify-report.md)}"
specs_glob="${WORKFLOW_SPECS_GLOB:-$(default_specs_glob)}"

# As of 2026-05 the implementer appends a `## Implementation` section to
# current-plan.md instead of writing a separate impl-summary.md. The legacy
# file path is still consulted as a soft fallback so freshly-cut runs that
# pre-date the fold remain checkable.
check_file "$plan_file"
legacy_summary="${WORKFLOW_SUMMARY_PATH:-docs/impl-summary.md}"
if [ -f "$legacy_summary" ]; then
  check_file "$legacy_summary"
fi

check_file "$review_file"
if [ -f "$test_file" ]; then
  check_file "$test_file"
fi
check_file "$verify_file"

# shellcheck disable=SC2206  # $specs_glob is intentional glob expansion
spec_files=($specs_glob)
if [ "${spec_files[0]}" != "$specs_glob" ]; then
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
