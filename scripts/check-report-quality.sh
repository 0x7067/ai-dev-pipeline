#!/usr/bin/env bash
set -euo pipefail

errors=0
strict_mode="${REPORT_QUALITY_REQUIRE_CONTENT:-0}"

fail() {
  echo "report-quality: ERROR: $*"
  errors=$((errors + 1))
}

note() {
  echo "report-quality: $*"
}

has_rg() {
  command -v rg >/dev/null 2>&1
}

match_file() {
  local pattern="$1"
  local file="$2"

  if has_rg; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

match_stdin() {
  local pattern="$1"

  if has_rg; then
    rg -q -- "$pattern"
  else
    grep -Eq -- "$pattern"
  fi
}

count_stdin() {
  local pattern="$1"

  if has_rg; then
    rg -c -- "$pattern" || true
  else
    grep -E -c -- "$pattern" || true
  fi
}

require_heading() {
  local file="$1"
  local heading="$2"

  if ! match_file "^${heading}$" "$file"; then
    fail "$file missing heading: ${heading}"
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! match_file "$pattern" "$file"; then
    fail "$file missing or empty field: ${label}"
  fi
}

normalize_value() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]'
}

is_unset_value() {
  local value
  value="$(normalize_value "$1")"
  [[ "$value" =~ ^$|^tbd$|^todo$|^pending$|^unknown$ ]]
}

validate_approval_value() {
  local file="$1"
  local label="$2"
  local raw_value="$3"
  local allow_not_required="$4"
  local value

  value="$(normalize_value "$raw_value")"

  if is_unset_value "$value"; then
    fail "$file approval gate '${label}' is missing (use approved/rejected and avoid placeholders)"
    return
  fi

  if [[ "$value" =~ ^approved$|^rejected$|^yes$|^no$|^granted$|^denied$|^true$|^false$ ]]; then
    return
  fi

  if [ "$allow_not_required" = "1" ] && [[ "$value" =~ ^n/?a$|^na$|^not[[:space:]]+required$ ]]; then
    return
  fi

  fail "$file approval gate '${label}' has invalid value '$raw_value'"
}

check_review_report() {
  local file="$1"

  require_heading "$file" '## Findings \(Highest Severity First\)'
  require_heading "$file" '## Evidence'
  require_heading "$file" '## Residual Risks'
  require_heading "$file" '## Recommendation'

  require_pattern "$file" '^- Official sources:[[:space:]]+[^[:space:]]' 'Official sources'
  require_pattern "$file" '^- Unsourced claims rejected:[[:space:]]+[^[:space:]]' 'Unsourced claims rejected'

  local evidence_block
  evidence_block="$(awk '/^## Evidence$/{flag=1;next} /^## /&&flag{exit} flag{print}' "$file")"
  if ! printf '%s\n' "$evidence_block" | match_stdin 'https?://'; then
    fail "$file evidence section must include at least one citation URL"
  fi
}

section_has_content() {
  local file="$1"
  local heading="$2"
  local body

  body="$(awk -v h="$heading" '$0 ~ "^"h"$"{flag=1;next} /^## /&&flag{exit} flag{print}' "$file")"
  # Strip blank lines and check for non-whitespace content
  printf '%s\n' "$body" | match_stdin '[^[:space:]]'
}

check_test_report() {
  local file="$1"

  require_heading "$file" '## Summary'
  require_heading "$file" '## Property-Based Tests'
  require_heading "$file" '## Contract Tests'
  require_heading "$file" '## Integration Tests'
  require_heading "$file" '## Blocking Failures'
  require_heading "$file" '## Retry and Triage Notes'

  if ! section_has_content "$file" '## Property-Based Tests'; then
    fail "$file section '## Property-Based Tests' has no content"
  fi
  if ! section_has_content "$file" '## Contract Tests'; then
    fail "$file section '## Contract Tests' has no content"
  fi

  require_pattern "$file" '^- Retry count:[[:space:]]+[^[:space:]]' 'Retry count'
  require_pattern "$file" '^- Flaky tests observed:[[:space:]]+[^[:space:]]' 'Flaky tests observed'
  require_pattern "$file" '^- Root cause notes:[[:space:]]+[^[:space:]]' 'Root cause notes'
}

check_verify_report() {
  local file="$1"

  require_heading "$file" '## Context'
  require_heading "$file" '## Gate Results'
  require_heading "$file" '## Decision'
  require_heading "$file" '## Finding Classification'
  require_heading "$file" '## Human Approval Checkpoints'
  require_heading "$file" '## Residual Risk and Follow-ups'

  require_pattern "$file" '^- Risk tier:[[:space:]]+[^[:space:]]' 'Risk tier'
  require_pattern "$file" '^1\. Plan approved:[[:space:]]+[^[:space:]]' 'Plan approved'
  require_pattern "$file" '^2\. Elevated-risk implementation approved \(required for `medium` and `high` risk\):[[:space:]]+[^[:space:]]' 'Elevated-risk implementation approved'
  require_pattern "$file" '^3\. Release approved:[[:space:]]+[^[:space:]]' 'Release approved'

  local approval_block
  approval_block="$(awk '/^## Human Approval Checkpoints$/{flag=1;next} /^## /&&flag{exit} flag{print}' "$file")"

  local approver_count
  local date_count
  local link_count
  approver_count="$(printf '%s\n' "$approval_block" | count_stdin 'Approver:[[:space:]]+[^[:space:]]')"
  date_count="$(printf '%s\n' "$approval_block" | count_stdin 'Date:[[:space:]]+[^[:space:]]')"
  link_count="$(printf '%s\n' "$approval_block" | count_stdin 'Evidence link:[[:space:]]+[^[:space:]]')"

  if [ "$approver_count" -lt 3 ]; then
    fail "$file human approval checkpoints require approver metadata (3 entries)"
  fi
  if [ "$date_count" -lt 3 ]; then
    fail "$file human approval checkpoints require date metadata (3 entries)"
  fi
  if [ "$link_count" -lt 3 ]; then
    fail "$file human approval checkpoints require evidence links (3 entries)"
  fi

  local risk_tier
  local plan_approval
  local elevated_risk_approval
  local release_approval

  risk_tier="$(sed -n 's/^- Risk tier:[[:space:]]*//p' "$file" | head -n1)"
  risk_tier="$(normalize_value "$risk_tier")"
  plan_approval="$(sed -n 's/^1\. Plan approved:[[:space:]]*//p' "$file" | head -n1)"
  elevated_risk_approval="$(sed -n 's/^2\. Elevated-risk implementation approved (required for `medium` and `high` risk):[[:space:]]*//p' "$file" | head -n1)"
  release_approval="$(sed -n 's/^3\. Release approved:[[:space:]]*//p' "$file" | head -n1)"

  if ! [[ "$risk_tier" =~ ^low$|^medium$|^high$ ]]; then
    fail "$file risk tier must be one of low|medium|high"
    return
  fi

  validate_approval_value "$file" "Plan approved" "$plan_approval" 0
  validate_approval_value "$file" "Release approved" "$release_approval" 0

  if [[ "$risk_tier" = "medium" || "$risk_tier" = "high" ]]; then
    validate_approval_value "$file" "Elevated-risk implementation approved" "$elevated_risk_approval" 0
  else
    validate_approval_value "$file" "Elevated-risk implementation approved" "$elevated_risk_approval" 1
  fi
}

check_one() {
  local file="$1"
  local label="$2"

  if [ ! -f "$file" ]; then
    if [ "$strict_mode" = "1" ]; then
      fail "missing report file: $file"
    else
      note "skipping $label checks for missing $file (set REPORT_QUALITY_REQUIRE_CONTENT=1 to enforce)"
    fi
    return
  fi

  if [ ! -s "$file" ]; then
    if [ "$strict_mode" = "1" ]; then
      fail "$file is empty (strict mode)"
    else
      note "skipping $label checks for empty $file (set REPORT_QUALITY_REQUIRE_CONTENT=1 to enforce)"
    fi
    return
  fi

  case "$label" in
    review) check_review_report "$file" ;;
    test) check_test_report "$file" ;;
    verify) check_verify_report "$file" ;;
    *) fail "unknown report label: $label" ;;
  esac
}

check_one "docs/review-report.md" review
check_one "docs/test-report.md" test
check_one "docs/verify-report.md" verify

if [ "$errors" -gt 0 ]; then
  echo "report-quality: FAILED with $errors issue(s)"
  exit 1
fi

echo "report-quality: OK"
exit 0
