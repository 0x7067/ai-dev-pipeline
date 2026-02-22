#!/usr/bin/env bash
set -uo pipefail

total=0
passed=0
failed=0

run_check() {
  local name="$1"
  shift

  total=$((total + 1))
  echo "==> $name"

  if "$@"; then
    echo "RESULT|${name}|PASS"
    passed=$((passed + 1))
  else
    local code=$?
    echo "RESULT|${name}|FAIL|exit_code=${code}"
    failed=$((failed + 1))
  fi

  echo
}

run_check "validate_claude_config" bash scripts/validate-claude-config.sh
run_check "report_quality" bash scripts/check-report-quality.sh
run_check "workflow_artifacts" bash scripts/check-workflow-artifacts.sh

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

run_check "required_bootstrap_files" bash -c '
  set -euo pipefail
  for f in \
    CLAUDE.md \
    .claude/settings.json \
    scripts/validate-claude-config.sh \
    scripts/check-report-quality.sh \
    scripts/check-workflow-artifacts.sh \
    scripts/check-crossrefs.sh \
    scripts/check-boundary-violations.sh \
    scripts/run-verification-gates.sh \
    docs/verification/acceptance-checklist.md \
    docs/templates/workflow-assessment-prompt-template.md \
    docs/templates/workflow-assessment-rubric-template.md \
    docs/templates/workflow-assessment-report-template.md; do
    [ -f "$f" ]
  done
'

echo "SUMMARY|total=${total}|passed=${passed}|failed=${failed}"

if [ "$failed" -gt 0 ]; then
  exit 1
fi

exit 0
