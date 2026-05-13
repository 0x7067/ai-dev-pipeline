#!/usr/bin/env bash
# Contract tests for scripts/check-report-quality.sh evidence/citation rules.
#
# Cases covered:
#   1. Backtick-wrapped Risk tier (`low`) in verify report -> pass.
#   2. Sub-bullet `Official sources:` in review report -> pass.
#   3. Local-file-only evidence in review report with risk=low -> pass.
#   4. Local-file-only evidence in review report with risk=medium -> fail.
#   5. Empty `Official sources:` (no inline value, no sub-bullets) -> fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-report-quality.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() {
  mktemp -d -t report-quality-evidence-XXXXXX
}

setup_workdir() {
  # $1 = workdir
  local work="$1"
  mkdir -p "$work/docs/aidp" "$work/scripts/lib" "$work/.claude-plugin"
  ln -s "${REPO_ROOT}/scripts/harness-lib.sh" "$work/scripts/harness-lib.sh"
  ln -s "${REPO_ROOT}/scripts/lib/project-root.sh" "$work/scripts/lib/project-root.sh"
  ln -s "$SCRIPT" "$work/scripts/check-report-quality.sh"
  printf '{"name":"ai-dev-pipeline","version":"0.0.0"}\n' > "$work/.claude-plugin/plugin.json"
}

write_verify_report() {
  # $1 = path, $2 = risk-tier-line literal
  local path="$1" risk_line="$2"
  cat > "$path" <<EOF
## Context
- Risk tier: ${risk_line}
- Change type: refactor
- Reviewer: tester

## Gate Results
1. Type/compile: pass
2. Lint: pass
3. Security: pass
4. Property tests: pass
5. Contract tests: pass
6. Full suite: pass

## Retry Envelope
- Retry count: 0
- Final exit codes per gate: type=0 lint=0 sec=0 prop=0 contract=0 full=0
- Hint file: docs/.verify-retry.json

## Decision
- [x] Go
- [ ] No-Go

## Finding Classification
- Blocking: none
- Advisory: none

## Human Approval Checkpoints
1. Plan approved: N/A — risk=low
   - Approver: tester
   - Date: 2026-05-08
   - Evidence link: docs/current-plan.md
2. Elevated-risk implementation approved (required for \`medium\` and \`high\` risk): N/A — risk=low
   - Approver: tester
   - Date: 2026-05-08
   - Evidence link: docs/current-plan.md
3. Release approved: N/A — risk=low
   - Approver: tester
   - Date: 2026-05-08
   - Evidence link: docs/current-plan.md

## Residual Risk and Follow-ups
- none
EOF
}

write_review_report() {
  # $1 = path, $2 = risk-tier value (or empty), $3 = official_sources block,
  # $4 = evidence-extra block (URLs/local-file lines appended after sources).
  local path="$1" risk="$2" sources="$3" extra="$4"
  local risk_line=""
  if [ -n "$risk" ]; then
    risk_line="- Risk tier: ${risk}"
  fi
  cat > "$path" <<EOF
# Review Report

## Findings (Highest Severity First)
- none

## Blocking Findings (Tool-Derived)
- none

## Advisory Findings (Model)
- none

## Evidence
${risk_line}
${sources}
- Unsourced claims rejected: yes
${extra}

## Residual Risks
- none

## Recommendation
- [x] Approve
EOF
}

# ---- Case 1: backtick-wrapped Risk tier in verify report -> pass ----
case1() {
  local work; work="$(make_workdir)"
  setup_workdir "$work"
  # shellcheck disable=SC2016 # literal backticks are intentional fixture content, no expansion wanted
  write_verify_report "$work/docs/verify-report.md" '`low`'
  ( cd "$work" && bash scripts/check-report-quality.sh ) >/tmp/cq-evidence.out 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "case1: backtick-wrapped Risk tier accepts (rc=0)"
  else
    fail "case1: backtick-wrapped Risk tier rejected (rc=$rc)"
    sed -e 's/^/    | /' /tmp/cq-evidence.out >&2 || true
  fi
  rm -rf "$work"
}

# ---- Case 2: sub-bullet Official sources -> pass ----
case2() {
  local work; work="$(make_workdir)"
  setup_workdir "$work"
  local sources='- Official sources:
  - https://example.com/official
  - .claude/rules/release-and-verification.md'
  write_review_report "$work/docs/aidp/review-report.md" "low" "$sources" ""
  ( cd "$work" && bash scripts/check-report-quality.sh ) >/tmp/cq-evidence.out 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "case2: sub-bullet Official sources accepts (rc=0)"
  else
    fail "case2: sub-bullet Official sources rejected (rc=$rc)"
    sed -e 's/^/    | /' /tmp/cq-evidence.out >&2 || true
  fi
  rm -rf "$work"
}

# ---- Case 3: local-file-only evidence with risk=low -> pass ----
case3() {
  local work; work="$(make_workdir)"
  setup_workdir "$work"
  local sources='- Official sources:
  - .claude/rules/release-and-verification.md
  - docs/templates/review-report-template.md'
  write_review_report "$work/docs/aidp/review-report.md" "low" "$sources" ""
  ( cd "$work" && bash scripts/check-report-quality.sh ) >/tmp/cq-evidence.out 2>&1
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "case3: local-file-only evidence on risk=low accepts (rc=0)"
  else
    fail "case3: local-file-only evidence on risk=low rejected (rc=$rc)"
    sed -e 's/^/    | /' /tmp/cq-evidence.out >&2 || true
  fi
  rm -rf "$work"
}

# ---- Case 4: local-file-only evidence with risk=medium -> fail (URL still required) ----
case4() {
  local work; work="$(make_workdir)"
  setup_workdir "$work"
  local sources='- Official sources:
  - .claude/rules/release-and-verification.md'
  write_review_report "$work/docs/aidp/review-report.md" "medium" "$sources" ""
  ( cd "$work" && bash scripts/check-report-quality.sh ) >/tmp/cq-evidence.out 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "case4: local-file-only evidence on risk=medium rejected (rc=$rc)"
  else
    fail "case4: risk=medium accepted local-file-only evidence (rc=0) — URL should be required"
    sed -e 's/^/    | /' /tmp/cq-evidence.out >&2 || true
  fi
  rm -rf "$work"
}

# ---- Case 5: empty Official sources -> fail ----
case5() {
  local work; work="$(make_workdir)"
  setup_workdir "$work"
  local sources='- Official sources:'
  write_review_report "$work/docs/aidp/review-report.md" "low" "$sources" "  - https://example.com/x"
  ( cd "$work" && bash scripts/check-report-quality.sh ) >/tmp/cq-evidence.out 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "case5: empty Official sources rejected (rc=$rc)"
  else
    fail "case5: empty Official sources accepted (rc=0)"
    sed -e 's/^/    | /' /tmp/cq-evidence.out >&2 || true
  fi
  rm -rf "$work"
}

case1
case2
case3
case4
case5

if [ "$failures" -gt 0 ]; then
  echo "test-report-quality-evidence: FAILED ($failures case(s))" >&2
  exit 1
fi
echo "test-report-quality-evidence: OK"
