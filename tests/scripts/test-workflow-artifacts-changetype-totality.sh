#!/usr/bin/env bash
# Regression tests locking in totality of parse_change_type.
#
# Reviewer advisory: ensure malformed/empty/odd-whitespace `change-type:` lines
# fall through to the safe default (require spec, no skip note emitted).
#
# Cases:
#   1. Empty value:                "change-type:"            -> unknown -> require spec.
#   2. Bogus token:                "change-type: bananas"    -> unknown -> require spec.
#   3. Whitespace-only value:      "change-type:    "        -> unknown -> require spec.
#   4. Leading whitespace + bogus: "    change-type: xyzzy"  -> unknown -> require spec.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-workflow-artifacts.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() { mktemp -d -t workflow-artifacts-tot-XXXXXX; }

# write_plan_raw <path> <raw line content>  -- raw text inserted verbatim under Risk Profile
write_plan_raw() {
  local path="$1" raw="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo "# Plan"
    echo
    echo "## Risk Profile"
    echo "- Risk tier: low"
    if [ -n "$raw" ]; then
      printf '%s\n' "$raw"
    fi
  } > "$path"
}

run_case() {
  local label="$1" raw_line="$2"
  local work
  work="$(make_workdir)"
  (
    cd "$work" \
      && mkdir -p docs scripts \
      && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
      && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
      && write_plan_raw docs/current-plan.md "$raw_line" \
      && printf '%s\n' "stub" > docs/impl-summary.md \
      && printf '%s\n' "stub" > docs/review-report.md \
      && printf '%s\n' "stub" > docs/test-report.md \
      && printf '%s\n' "stub" > docs/verify-report.md \
      && bash scripts/check-workflow-artifacts.sh >/tmp/wa-tot.out 2>&1
  )
  local rc=$?
  # In non-strict mode, missing-artifact and missing-spec do not fail; rc must be 0.
  if [ "$rc" -ne 0 ]; then
    fail "$label expected rc=0, got rc=$rc"
    sed -e 's/^/    | /' /tmp/wa-tot.out >&2 || true
    return
  fi
  # Critical invariant: NO skip note for malformed/unknown values.
  if grep -qF "spec requirement skipped" /tmp/wa-tot.out; then
    fail "$label must NOT emit spec-skip note"
    sed -e 's/^/    | /' /tmp/wa-tot.out >&2 || true
    return
  fi
  pass "$label -> require-spec default (no skip note)"
}

# Strict-mode counterpart: malformed value must fail in strict mode (spec required).
run_case_strict_fail() {
  local label="$1" raw_line="$2"
  local work
  work="$(make_workdir)"
  (
    cd "$work" \
      && mkdir -p docs scripts \
      && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
      && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
      && write_plan_raw docs/current-plan.md "$raw_line" \
      && printf '%s\n' "stub" > docs/impl-summary.md \
      && printf '%s\n' "stub" > docs/review-report.md \
      && printf '%s\n' "stub" > docs/test-report.md \
      && printf '%s\n' "stub" > docs/verify-report.md \
      && WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/check-workflow-artifacts.sh >/tmp/wa-tot.out 2>&1
  )
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "$label (strict) expected non-zero rc, got 0"
    sed -e 's/^/    | /' /tmp/wa-tot.out >&2 || true
    return
  fi
  if grep -qF "spec requirement skipped" /tmp/wa-tot.out; then
    fail "$label (strict) must NOT emit skip note for malformed value"
    sed -e 's/^/    | /' /tmp/wa-tot.out >&2 || true
    return
  fi
  pass "$label (strict) -> fails (no spec, no skip)"
}

# Non-strict: confirm safe default for each malformed shape.
run_case "empty value 'change-type:'"            "- change-type:"
run_case "bogus token 'change-type: bananas'"     "- change-type: bananas"
run_case "whitespace-only value"                  "- change-type:    "
run_case "leading whitespace + bogus"             "    - change-type: xyzzy"

# Strict-mode regression: malformed values must NOT bypass spec requirement.
run_case_strict_fail "strict empty value"          "- change-type:"
run_case_strict_fail "strict bogus token"          "- change-type: bananas"

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-artifacts-changetype-totality: FAILED ($failures case(s))" >&2
  exit 1
fi
echo "test-workflow-artifacts-changetype-totality: OK"
