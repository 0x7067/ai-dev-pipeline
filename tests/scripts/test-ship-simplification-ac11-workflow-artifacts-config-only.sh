#!/usr/bin/env bash
# AC11: scripts/check-workflow-artifacts.sh accepts change-type: config_only
# (or change-class: config_only) and skips both spec AND review-report
# requirements.
#
# This is the executable contract test for the parser extension. It exercises
# the script directly, the same way test-workflow-artifacts-changetype.sh does.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-workflow-artifacts.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() { mktemp -d -t wa-config-only-XXXXXX; }

write_plan() {
  local path="$1" cline="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo "# Plan"
    echo
    echo "## Risk Profile"
    echo "- Risk tier: low"
    [ -n "$cline" ] && printf '%s\n' "$cline"
  } > "$path"
}

# Case 1: change-type: config_only -> spec skip, review-report skip,
# strict mode passes WITHOUT a docs/review-report.md file present.
work="$(make_workdir)"
(
  cd "$work" \
    && mkdir -p docs scripts \
    && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
    && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
    && write_plan docs/current-plan.md "- change-type: config_only" \
    && printf '%s\n' "stub" > docs/test-report.md \
    && printf '%s\n' "stub" > docs/verify-report.md \
    && WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/check-workflow-artifacts.sh >/tmp/wa-co.out 2>&1
)
rc=$?
if [ "$rc" -eq 0 ] && grep -qF "spec requirement skipped" /tmp/wa-co.out; then
  pass "change-type: config_only -> spec skip + strict pass without review-report.md"
else
  fail "change-type: config_only did not skip spec/review-report under strict (rc=$rc) (AC11)"
  sed -e 's/^/    | /' /tmp/wa-co.out >&2 || true
fi
rm -rf "$work"

# Case 2: change-class: config_only (alternate field name)
work="$(make_workdir)"
(
  cd "$work" \
    && mkdir -p docs scripts \
    && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
    && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
    && write_plan docs/current-plan.md "- change-class: config_only" \
    && printf '%s\n' "stub" > docs/test-report.md \
    && printf '%s\n' "stub" > docs/verify-report.md \
    && WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/check-workflow-artifacts.sh >/tmp/wa-co2.out 2>&1
)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "change-class: config_only -> strict pass without review-report.md"
else
  fail "change-class: config_only did not pass under strict (rc=$rc) (AC11)"
  sed -e 's/^/    | /' /tmp/wa-co2.out >&2 || true
fi
rm -rf "$work"

# Case 3: regression -- missing review-report under non-config-only must
# still fail strict. This locks the gate to ONLY relax for config_only.
work="$(make_workdir)"
(
  cd "$work" \
    && mkdir -p docs scripts \
    && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
    && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
    && write_plan docs/current-plan.md "- change-type: feature" \
    && printf '%s\n' "stub" > docs/test-report.md \
    && printf '%s\n' "stub" > docs/verify-report.md \
    && mkdir -p docs/specs \
    && printf '%s\n' "stub" > docs/specs/feature.md \
    && WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/check-workflow-artifacts.sh >/tmp/wa-co3.out 2>&1
)
rc=$?
if [ "$rc" -ne 0 ] && grep -qiE 'review[- ]report' /tmp/wa-co3.out; then
  pass "feature still requires review-report under strict (regression guard)"
else
  # Either the script doesn't enforce review-report at all yet (current
  # state), or the relaxation is too broad. We require the NEW relaxation
  # to be config_only-scoped.
  if grep -qiE 'review[- ]report' /tmp/wa-co3.out; then
    fail "feature does not require review-report under strict — relaxation too broad (AC11)"
  else
    # Current script doesn't gate on review-report at all. The new code
    # MUST add a config_only-scoped review-report skip mechanism, which
    # by definition introduces enforcement on the non-skipped path.
    fail "review-report enforcement is absent — AC11 requires config_only-scoped skip (which presupposes enforcement)"
  fi
  sed -e 's/^/    | /' /tmp/wa-co3.out >&2 || true
fi
rm -rf "$work"

# Case 4: parser totality -- bogus value must NOT match config_only.
work="$(make_workdir)"
(
  cd "$work" \
    && mkdir -p docs scripts \
    && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
    && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
    && write_plan docs/current-plan.md "- change-type: config_onlyish" \
    && printf '%s\n' "stub" > docs/test-report.md \
    && printf '%s\n' "stub" > docs/verify-report.md \
    && bash scripts/check-workflow-artifacts.sh >/tmp/wa-co4.out 2>&1
)
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qiE 'change-type: config_only\b' /tmp/wa-co4.out; then
  pass "bogus 'config_onlyish' does not match config_only (parser totality)"
else
  fail "bogus 'config_onlyish' incorrectly classified (AC11 / I2)"
  sed -e 's/^/    | /' /tmp/wa-co4.out >&2 || true
fi
rm -rf "$work"

if [ "$failures" -gt 0 ]; then
  echo "test-ac11-workflow-artifacts-config-only: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac11-workflow-artifacts-config-only: OK"
