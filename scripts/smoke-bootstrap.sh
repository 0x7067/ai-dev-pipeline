#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

# Smoke runs BEFORE the release decision in `/ship`; tell the report-quality
# gate to accept `pending` for "Release approved" and to allow a missing
# test-report.md (the lean ship path skips the tester phase). Callers in
# legacy/full pipelines override these by exporting non-default values.
: "${REPORT_QUALITY_PHASE:=pre-release}"
: "${REPORT_TEST_OPTIONAL:=1}"
export REPORT_QUALITY_PHASE REPORT_TEST_OPTIONAL

total=0
passed=0
failed=0

run_check() {
  local name="$1"
  shift

  total=$((total + 1))
  echo "==> $name"

  set +e
  "$@"
  local code=$?
  set -e

  if [ "$code" -eq 0 ]; then
    echo "RESULT|${name}|PASS"
    passed=$((passed + 1))
  else
    echo "RESULT|${name}|FAIL|exit_code=${code}"
    failed=$((failed + 1))
  fi

  echo
}

run_check_required_files() {
  local name="$1"
  shift
  total=$((total + 1))
  echo "==> $name"

  local missing=()
  local f
  for f in "$@"; do
    [ -f "$f" ] || missing+=("$f")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "RESULT|${name}|PASS"
    passed=$((passed + 1))
  else
    local list
    list="$(IFS=,; echo "${missing[*]}")"
    echo "RESULT|${name}|FAIL|missing=${list}"
    failed=$((failed + 1))
  fi

  echo
}

run_check "validate_claude_config" bash scripts/validate-claude-config.sh
run_check "report_quality" bash scripts/check-report-quality.sh
run_check "workflow_artifacts" bash scripts/check-workflow-artifacts.sh

# shellcheck disable=SC2016 # the heredoc-style script body is intentionally single-quoted to defer expansion to the child bash
run_check "hooks_executable" bash -c '
  set -euo pipefail
  for f in \
    .claude/hooks/protect-files.sh \
    .claude/hooks/type-check.sh \
    .claude/hooks/lint-on-edit.sh \
    .claude/hooks/format-on-stop.sh; do
    [ -x "$f" ]
  done
'

run_check_required_files "required_bootstrap_files" \
  CLAUDE.md \
  .claude-plugin/plugin.json \
  scripts/validate-claude-config.sh \
  scripts/check-report-quality.sh \
  scripts/check-workflow-artifacts.sh \
  scripts/check-crossrefs.sh \
  scripts/check-boundary-violations.sh \
  scripts/harness-lib.sh \
  scripts/run-verification-gates.sh \
  docs/reference/acceptance-checklist.md \
  docs/templates/workflow-assessment-prompt-template.md \
  docs/templates/workflow-assessment-rubric-template.md \
  docs/templates/workflow-assessment-report-template.md

echo "SUMMARY|total=${total}|passed=${passed}|failed=${failed}"

if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
