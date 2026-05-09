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
  # Reads a `change-type: <value>` (or `change-class:`) line from a plan file.
  # Accepts forms:
  #   - YAML-style:        change-type: config
  #   - Bullet/list line:  - change-type: refactor
  #   - Bullet/list line:  - change-class: config_only
  #   - Heading hint line: ## Change Type: feature   -> normalized to "feature"
  # Returns one of: feature|fix|refactor|config|config_only|unknown.
  # Total function: missing/malformed input yields "unknown" (parser totality, I2).
  local file="$1"
  local raw value

  if [ ! -f "$file" ]; then
    printf '%s\n' unknown
    return 0
  fi

  # Allow alphanumerics + underscore in the token (so config_only matches but
  # config_onlyish would be rejected by the case statement below).
  raw="$(grep -iE '^[[:space:]]*(-[[:space:]]+)?change-(type|class):[[:space:]]*[A-Za-z_]+' "$file" 2>/dev/null | head -n1 || true)"
  if [ -z "$raw" ]; then
    raw="$(grep -iE '^[[:space:]]*##[[:space:]]+change[[:space:]]+(type|class):[[:space:]]*[A-Za-z_]+' "$file" 2>/dev/null | head -n1 || true)"
  fi

  if [ -z "$raw" ]; then
    printf '%s\n' unknown
    return 0
  fi

  # Extract the token after the final colon, lowercase, trim.
  value="$(printf '%s' "$raw" | sed -E 's/.*:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

  case "$value" in
    feature|fix|refactor|config|config_only) printf '%s\n' "$value" ;;
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
review_file="${WORKFLOW_REVIEW_PATH:-docs/review-report.md}"
test_file="${WORKFLOW_TEST_PATH:-docs/test-report.md}"
verify_file="${WORKFLOW_VERIFY_PATH:-docs/verify-report.md}"
specs_glob="${WORKFLOW_SPECS_GLOB:-docs/specs/*.md}"

# As of 2026-05 the implementer appends a `## Implementation` section to
# current-plan.md instead of writing a separate impl-summary.md. The legacy
# file path is still consulted as a soft fallback so freshly-cut runs that
# pre-date the fold remain checkable.
check_file "$plan_file"
legacy_summary="${WORKFLOW_SUMMARY_PATH:-docs/impl-summary.md}"
if [ -f "$legacy_summary" ]; then
  check_file "$legacy_summary"
fi

change_type="$(parse_change_type "$plan_file")"

# Review-report skip mechanism: when the plan declares change-class: config_only
# (or change-type: config_only), the standalone review-report.md is folded into
# verify-report and not required as a separate artifact.
review_skip=0
case "$change_type" in
  config_only)
    review_skip=1
    note "review-report requirement skipped (${plan_file} declares change-type: ${change_type})"
    ;;
esac

if [ "$review_skip" = "0" ]; then
  check_file "$review_file"
fi
check_file "$test_file"
check_file "$verify_file"

# Spec-skip mechanism: when the plan declares change-type: config, refactor,
# or config_only, docs/specs/*.md is not required. Default (feature/fix/unknown)
# keeps the spec requirement so silence equals safety.
spec_skip=0
case "$change_type" in
  config|refactor|config_only)
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
