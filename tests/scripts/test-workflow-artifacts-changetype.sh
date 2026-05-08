#!/usr/bin/env bash
# Contract tests for scripts/check-workflow-artifacts.sh change-type spec-skip.
#
# Cases covered:
#   (c) spec-skip when plan declares change-type: config (no specs file present).
#   (c') spec-skip when plan declares change-type: refactor.
#   (d) spec required (default note path) when change-type absent.
#   (d') spec required when change-type: feature.
#   strict mode: feature without spec under WORKFLOW_REQUIRE_ARTIFACTS=1 fails.
#   strict mode: config without spec under WORKFLOW_REQUIRE_ARTIFACTS=1 still passes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-workflow-artifacts.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() { mktemp -d -t workflow-artifacts-XXXXXX; }

write_plan() {
  # $1 = path, $2 = change-type line content (or empty for none)
  local path="$1" ctype="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo "# Plan"
    echo
    echo "## Risk Profile"
    echo "- Risk tier: low"
    if [ -n "$ctype" ]; then
      echo "- change-type: ${ctype}"
    fi
  } > "$path"
}

run_case() {
  local label="$1" expected_rc="$2" change_type="$3" strict="$4" expect_substr="$5"
  local work
  work="$(make_workdir)"
  (
    cd "$work" \
      && mkdir -p docs scripts \
      && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
      && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
      && write_plan docs/current-plan.md "$change_type" \
      && printf '%s\n' "stub" > docs/impl-summary.md \
      && printf '%s\n' "stub" > docs/review-report.md \
      && printf '%s\n' "stub" > docs/test-report.md \
      && printf '%s\n' "stub" > docs/verify-report.md \
      && WORKFLOW_REQUIRE_ARTIFACTS="$strict" bash scripts/check-workflow-artifacts.sh >/tmp/wa.out 2>&1
  )
  local rc=$?
  local rc_ok="0"
  if [ "$rc" -ne "$expected_rc" ]; then
    rc_ok="1"
  fi
  local sub_ok="0"
  if [ -n "$expect_substr" ] && ! grep -qF -- "$expect_substr" /tmp/wa.out; then
    sub_ok="1"
  fi
  if [ "$rc_ok" = "0" ] && [ "$sub_ok" = "0" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label expected rc=$expected_rc substr='$expect_substr' got rc=$rc"
    sed -e 's/^/    | /' /tmp/wa.out >&2 || true
  fi
  rm -rf "$work"
}

# (c) change-type: config -> spec skipped (note emitted), default mode passes
run_case "change-type: config -> spec skip note (non-strict)" 0 \
  "config" "0" "spec requirement skipped"

# (c') change-type: refactor -> spec skipped
run_case "change-type: refactor -> spec skip note (non-strict)" 0 \
  "refactor" "0" "spec requirement skipped"

# (d) change-type absent -> spec NOT skipped (no skip note); non-strict passes
run_case "no change-type -> spec required, non-strict passes" 0 \
  "" "0" ""

# (d') change-type: feature -> spec NOT skipped
run_case "change-type: feature -> spec required, non-strict passes" 0 \
  "feature" "0" ""

# strict mode: feature without specs/*.md must fail
run_case "strict + feature + no spec -> fail" 1 \
  "feature" "1" "missing required artifact"

# strict mode: config without specs/*.md must pass (skip honored)
run_case "strict + config + no spec -> pass" 0 \
  "config" "1" "spec requirement skipped"

# Negative regression: skip note must NOT appear when change-type absent
work="$(make_workdir)"
(
  cd "$work" \
    && mkdir -p docs scripts \
    && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
    && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
    && write_plan docs/current-plan.md "" \
    && touch docs/impl-summary.md docs/review-report.md docs/test-report.md docs/verify-report.md \
    && bash scripts/check-workflow-artifacts.sh >/tmp/wa.out 2>&1
)
if grep -qF "spec requirement skipped" /tmp/wa.out; then
  fail "no change-type should NOT emit spec-skip note"
  sed -e 's/^/    | /' /tmp/wa.out >&2 || true
else
  pass "no change-type does not emit spec-skip note"
fi
rm -rf "$work"

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-artifacts-changetype: FAILED ($failures case(s))" >&2
  exit 1
fi
echo "test-workflow-artifacts-changetype: OK"
