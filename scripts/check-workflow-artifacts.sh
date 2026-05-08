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

parse_change_type() {
  # Reads a `change-type: <value>` line from a plan file.
  # Accepts forms:
  #   - YAML-style:        change-type: config
  #   - Bullet/list line:  - change-type: refactor
  #   - Heading hint line: ## Change Type: feature   -> normalized to "feature"
  # Returns one of: feature|fix|refactor|config|unknown.
  # Total function: missing/malformed input yields "unknown".
  local file="$1"
  local raw value

  if [ ! -f "$file" ]; then
    printf '%s\n' unknown
    return 0
  fi

  raw="$(grep -iE '^[[:space:]]*(-[[:space:]]+)?change-type:[[:space:]]*[A-Za-z]+' "$file" 2>/dev/null | head -n1 || true)"
  if [ -z "$raw" ]; then
    raw="$(grep -iE '^[[:space:]]*##[[:space:]]+change[[:space:]]+type:[[:space:]]*[A-Za-z]+' "$file" 2>/dev/null | head -n1 || true)"
  fi

  if [ -z "$raw" ]; then
    printf '%s\n' unknown
    return 0
  fi

  # Extract the token after the final colon, lowercase, trim.
  value="$(printf '%s' "$raw" | sed -E 's/.*:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  case "$value" in
    feature|fix|refactor|config) printf '%s\n' "$value" ;;
    *) printf '%s\n' unknown ;;
  esac
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

plan_file="${WORKFLOW_PLAN_PATH:-docs/current-plan.md}"
summary_file="${WORKFLOW_SUMMARY_PATH:-docs/impl-summary.md}"
review_file="${WORKFLOW_REVIEW_PATH:-docs/review-report.md}"
test_file="${WORKFLOW_TEST_PATH:-docs/test-report.md}"
verify_file="${WORKFLOW_VERIFY_PATH:-docs/verify-report.md}"
specs_glob="${WORKFLOW_SPECS_GLOB:-docs/specs/*.md}"

check_file "$plan_file"
check_file "$summary_file"
check_file "$review_file"
check_file "$test_file"
check_file "$verify_file"

change_type="$(parse_change_type "$plan_file")"

# Spec-skip mechanism: when the plan declares change-type: config or refactor,
# docs/specs/*.md is not required. Default (feature/fix/unknown) keeps the spec
# requirement so silence equals safety.
spec_skip=0
case "$change_type" in
  config|refactor)
    spec_skip=1
    note "spec requirement skipped (${plan_file} declares change-type: ${change_type})"
    ;;
esac

# shellcheck disable=SC2206  # $specs_glob is intentional glob expansion
spec_files=($specs_glob)
if [ "${spec_files[0]}" = "$specs_glob" ]; then
  if [ "$spec_skip" = "1" ]; then
    : # skip per change-type declaration
  elif [ "$strict_mode" = "1" ]; then
    fail "missing required artifact: ${specs_glob} (no files matched)"
  else
    note "skipping spec check (no ${specs_glob} found, set WORKFLOW_REQUIRE_ARTIFACTS=1 to enforce)"
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
