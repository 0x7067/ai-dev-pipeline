#!/usr/bin/env bash
# Contract tests for scripts/check-report-quality.sh approval-slot semantics.
#
# Cases covered:
#   (a) N/A — rationale accepted for risk=low Plan/Release approvals.
#   (b) Bare N/A rejected for risk=low Plan/Release approvals.
#   (c) N/A rejected for risk=medium Plan/Release approvals.
#   (d) Concrete approved values pass for any risk tier.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-report-quality.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() {
  mktemp -d -t report-quality-XXXXXX
}

write_verify_report() {
  # $1 = path, $2 = risk, $3 = plan-approved value, $4 = elevated value, $5 = release value
  local path="$1" risk="$2" plan="$3" elevated="$4" release="$5"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
## Context
- Risk tier: ${risk}
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
1. Plan approved: ${plan}
   - Approver: tester
   - Date: 2026-05-08
   - Evidence link: docs/current-plan.md
2. Elevated-risk implementation approved (required for \`medium\` and \`high\` risk): ${elevated}
   - Approver: tester
   - Date: 2026-05-08
   - Evidence link: docs/current-plan.md
3. Release approved: ${release}
   - Approver: tester
   - Date: 2026-05-08
   - Evidence link: docs/current-plan.md

## Residual Risk and Follow-ups
- none
EOF
}

run_case() {
  local label="$1" expected_rc="$2" risk="$3" plan="$4" elevated="$5" release="$6"
  local work
  work="$(make_workdir)"
  ( cd "$work" \
    && mkdir -p docs scripts \
    && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
    && ln -s "$SCRIPT" scripts/check-report-quality.sh \
    && write_verify_report docs/verify-report.md "$risk" "$plan" "$elevated" "$release" \
    && bash scripts/check-report-quality.sh >/tmp/cq.out 2>&1
  )
  local rc=$?
  if [ "$rc" -eq "$expected_rc" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label expected rc=$expected_rc got rc=$rc"
    sed -e 's/^/    | /' /tmp/cq.out >&2 || true
  fi
  rm -rf "$work"
}

# (a) risk=low + N/A — rationale should pass
run_case "risk=low Plan/Release N/A with rationale -> pass" 0 \
  "low" "N/A — risk=low" "N/A — risk=low" "N/A — risk=low"

# (b) risk=low + bare N/A on Plan should fail
run_case "risk=low Plan bare N/A -> fail" 1 \
  "low" "N/A" "N/A — risk=low" "N/A — risk=low"

# (b') risk=low + bare N/A on Release should fail
run_case "risk=low Release bare N/A -> fail" 1 \
  "low" "N/A — risk=low" "N/A — risk=low" "N/A"

# (c) risk=medium + N/A — rationale should fail (medium requires real approvals)
run_case "risk=medium Plan N/A -> fail" 1 \
  "medium" "N/A — risk=low" "approved" "approved"

# (d) concrete approved values pass for low and medium
run_case "risk=low all approved -> pass" 0 \
  "low" "approved" "approved" "approved"
run_case "risk=medium all approved -> pass" 0 \
  "medium" "approved" "approved" "approved"

if [ "$failures" -gt 0 ]; then
  echo "test-report-quality-approvals: FAILED ($failures case(s))" >&2
  exit 1
fi
echo "test-report-quality-approvals: OK"
