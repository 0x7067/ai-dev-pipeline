#!/usr/bin/env bash
# Contract tests for the lean workflow artifact checker.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-workflow-artifacts.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() { mktemp -d -t workflow-artifacts-lean-XXXXXX; }

write_required_artifacts() {
  local root="$1"
  mkdir -p "$root"
  printf '%s\n' "# Plan" > "$root/current-plan.md"
  printf '%s\n' "# Review" > "$root/review-report.md"
  printf '%s\n' "# Verify" > "$root/verify-report.md"
}

run_in_workdir() {
  local work="$1"
  shift
  (
    cd "$work" \
      && mkdir -p scripts/lib .claude-plugin \
      && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
      && ln -s "${REPO_ROOT}/scripts/lib/project-root.sh" scripts/lib/project-root.sh \
      && ln -s "$SCRIPT" scripts/check-workflow-artifacts.sh \
      && printf '{"name":"ai-dev-pipeline","version":"0.0.0"}\n' > .claude-plugin/plugin.json \
      && "$@" bash scripts/check-workflow-artifacts.sh >/tmp/wa-lean.out 2>&1
  )
}

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp/runs/run-a
  write_required_artifacts docs/aidp/runs/run-a
)
if run_in_workdir "$work" env RUN_DIR=docs/aidp/runs/run-a WORKFLOW_REQUIRE_ARTIFACTS=1; then
  pass "strict mode accepts required artifacts under RUN_DIR"
else
  fail "strict mode did not resolve artifacts under RUN_DIR"
  sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp/runs/run-b
  write_required_artifacts docs/aidp/runs/run-b
  ln -sfn runs/run-b docs/aidp/latest
)
if run_in_workdir "$work" env WORKFLOW_REQUIRE_ARTIFACTS=1; then
  pass "strict mode falls back to docs/aidp/latest"
else
  fail "strict mode did not resolve artifacts through docs/aidp/latest"
  sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp
  write_required_artifacts docs/aidp
)
if run_in_workdir "$work" env WORKFLOW_REQUIRE_ARTIFACTS=1; then
  pass "strict mode resolves artifacts at AIDP_ARTIFACTS_ROOT when no RUN_DIR/latest"
else
  fail "strict mode did not resolve artifacts at AIDP_ARTIFACTS_ROOT"
  sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp
  write_required_artifacts docs/aidp
)
if run_in_workdir "$work" env WORKFLOW_REQUIRE_ARTIFACTS=1; then
  if grep -q "missing required artifact: .*specs" /tmp/wa-lean.out; then
    fail "missing specs should not fail lean artifact check"
    sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
  else
    pass "specs are optional when absent"
  fi
else
  fail "strict mode failed without optional specs"
  sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp/specs/empty
  write_required_artifacts docs/aidp
  : > docs/aidp/specs/empty/spec.yaml
)
if run_in_workdir "$work" env WORKFLOW_REQUIRE_ARTIFACTS=1; then
  fail "empty present spec should fail strict mode"
  sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
else
  if grep -q "empty/spec.yaml is empty" /tmp/wa-lean.out; then
    pass "present specs are still content-checked"
  else
    fail "empty spec failure message missing"
    sed -e 's/^/    | /' /tmp/wa-lean.out >&2 || true
  fi
fi
rm -rf "$work"

if [ "$failures" -gt 0 ]; then
  echo "test-workflow-artifacts-lean: FAILED ($failures)" >&2
  exit 1
fi

echo "test-workflow-artifacts-lean: OK"
