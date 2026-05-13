#!/usr/bin/env bash
# Contract tests for the manifest-aware required-set behavior of
# scripts/check-report-quality.sh.
#
# Cases covered:
#   1. Manifest absent -> legacy strict behavior preserved (test-report.md
#      missing -> fail under REPORT_QUALITY_REQUIRE_CONTENT=1).
#   2. Manifest present and lists test-report.md -> enforced (missing -> fail).
#   3. Manifest present and does NOT list test-report.md -> skipped silently.
#   4. Manifest present but malformed -> parser rejects, falls back to legacy.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-report-quality.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Minimal valid review-report.md and verify-report.md content suitable to pass
# strict checks (sourced shapes from existing tests/fixtures).
write_valid_review_report() {
  local path="$1"
  cat > "$path" <<'EOF'
## Findings (Highest Severity First)
none.

## Blocking Findings (Tool-Derived)
none.

## Advisory Findings (Model)
none.

## Evidence
- Risk tier: low
- Official sources:
  - scripts/check-report-quality.sh
- Unsourced claims rejected: yes
- See https://example.com/spec for full details.

## Residual Risks
none.

## Recommendation
ship.
EOF
}

write_valid_verify_report() {
  local path="$1"
  cat > "$path" <<'EOF'
## Context
- Risk tier: low
- Change type: refactor

## Gate Results
1. Type/compile: pass

## Retry Envelope
- Retry count: 0
- Final exit codes per gate: type=0 lint=0 sec=0 prop=0 contract=0 full=0
- Hint file: docs/.verify-retry.json

## Decision
- [x] Go

## Finding Classification
- Blocking: none

## Human Approval Checkpoints
- Risk tier: low
1. Plan approved: N/A — low-risk auto run
   - Approver: orchestrator
   - Date: 2026-05-09
   - Evidence link: docs/aidp/runs/x/current-plan.md
2. Elevated-risk implementation approved (required for `medium` and `high` risk): N/A
   - Approver: orchestrator
   - Date: 2026-05-09
   - Evidence link: docs/aidp/runs/x/current-plan.md
3. Release approved: N/A — low-risk auto run
   - Approver: orchestrator
   - Date: 2026-05-09
   - Evidence link: docs/aidp/runs/x/current-plan.md

## Residual Risk and Follow-ups
none.
EOF
}

# Build a minimal v1 manifest listing a chosen subset of artifacts.
# $1 = manifest path; remaining args = artifact relpaths.
write_manifest() {
  local path="$1"
  shift
  local entries="["
  local first=1
  for rel in "$@"; do
    if [ "$first" = "0" ]; then entries+=","; fi
    first=0
    entries+="{\"kind\":\"other\",\"path\":\"${rel}\",\"sha256\":\"0\",\"bytes\":1}"
  done
  entries+="]"
  cat > "$path" <<EOF
{"schema":"run-manifest/v1","run_id":"20260509T152345-0dd552-c6","started_at":"2026-05-09T00:00:00Z","ended_at":"2026-05-09T00:00:00Z","command":"ship","mode":"auto","risk_tier":"low","status":"ok","git":{"head":"x","branch":"x","dirty":false},"artifacts":${entries}}
EOF
}

# --- Case 1: manifest absent -> legacy strict failure on missing test-report ---
case1() {
  local work
  work=$(mktemp -d -t crq-case1-XXXXXX)
  local rd="$work/docs/aidp/runs/20260509T152345-0dd552-c6"
  mkdir -p "$rd"
  write_valid_review_report "$rd/review-report.md"
  write_valid_verify_report "$rd/verify-report.md"

  set +e
  RUN_DIR="$rd" \
    REPORT_REVIEW_PATH="$rd/review-report.md" \
    REPORT_TEST_PATH="$rd/test-report.md" \
    REPORT_VERIFY_PATH="$rd/verify-report.md" \
    REPORT_QUALITY_REQUIRE_CONTENT=1 \
    bash "$SCRIPT" >/dev/null 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    pass "case1: manifest absent + missing test-report -> exit nonzero (legacy)"
  else
    fail "case1: expected nonzero exit when manifest absent; got 0"
  fi
  rm -rf "$work"
}

# --- Case 2: manifest lists test-report.md -> enforced -> fail ---
case2() {
  local work
  work=$(mktemp -d -t crq-case2-XXXXXX)
  local rd="$work/docs/aidp/runs/20260509T152345-0dd552-c6"
  mkdir -p "$rd"
  write_valid_review_report "$rd/review-report.md"
  write_valid_verify_report "$rd/verify-report.md"
  write_manifest "$rd/manifest.json" "review-report.md" "verify-report.md" "test-report.md"

  set +e
  RUN_DIR="$rd" \
    REPORT_REVIEW_PATH="$rd/review-report.md" \
    REPORT_TEST_PATH="$rd/test-report.md" \
    REPORT_VERIFY_PATH="$rd/verify-report.md" \
    REPORT_QUALITY_REQUIRE_CONTENT=1 \
    bash "$SCRIPT" >/dev/null 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    pass "case2: manifest lists test-report -> enforced and fails"
  else
    fail "case2: expected nonzero exit; manifest lists test-report.md"
  fi
  rm -rf "$work"
}

# --- Case 3: manifest does NOT list test-report.md -> skipped -> pass ---
case3() {
  local work
  work=$(mktemp -d -t crq-case3-XXXXXX)
  local rd="$work/docs/aidp/runs/20260509T152345-0dd552-c6"
  mkdir -p "$rd"
  write_valid_review_report "$rd/review-report.md"
  write_valid_verify_report "$rd/verify-report.md"
  write_manifest "$rd/manifest.json" "review-report.md" "verify-report.md"

  set +e
  out=$( RUN_DIR="$rd" \
    REPORT_REVIEW_PATH="$rd/review-report.md" \
    REPORT_TEST_PATH="$rd/test-report.md" \
    REPORT_VERIFY_PATH="$rd/verify-report.md" \
    REPORT_QUALITY_REQUIRE_CONTENT=1 \
    bash "$SCRIPT" 2>&1 )
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    pass "case3: manifest omits test-report -> skipped, exit 0"
  else
    fail "case3: expected exit 0; got $rc; output: $out"
  fi
  rm -rf "$work"
}

# --- Case 4: malformed manifest -> parser rejects -> legacy fallback ---
case4() {
  local work
  work=$(mktemp -d -t crq-case4-XXXXXX)
  local rd="$work/docs/aidp/runs/20260509T152345-0dd552-c6"
  mkdir -p "$rd"
  write_valid_review_report "$rd/review-report.md"
  write_valid_verify_report "$rd/verify-report.md"
  printf '{"schema":"bogus"}' > "$rd/manifest.json"

  set +e
  RUN_DIR="$rd" \
    REPORT_REVIEW_PATH="$rd/review-report.md" \
    REPORT_TEST_PATH="$rd/test-report.md" \
    REPORT_VERIFY_PATH="$rd/verify-report.md" \
    REPORT_QUALITY_REQUIRE_CONTENT=1 \
    bash "$SCRIPT" >/dev/null 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    pass "case4: malformed manifest -> legacy strict fallback fails as before"
  else
    fail "case4: expected legacy strict failure; got 0"
  fi
  rm -rf "$work"
}

case1
case2
case3
case4

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures case(s) failed" >&2
  exit 1
fi
echo "OK: all cases passed"
exit 0
