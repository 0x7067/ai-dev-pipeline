#!/usr/bin/env bash
# Integration test: zero-setup install path.
#
# Simulates a freshly-cloned consuming repo that has the plugin installed but
# has NOT run /setup. Verifies that the resolver finds plugin-shipped artifacts
# via the CLAUDE_PLUGIN_ROOT fallback, and returns a structured NotFound when
# the artifact is absent on both sides.
#
# This complements tests/scripts/test-resolver.sh (which uses fake plugin
# roots). Here we point CLAUDE_PLUGIN_ROOT at the real repo to prove the
# real shipped artifacts are reachable from a fresh CWD.
#
# macOS note: $TMPDIR resolves under /var/folders/... which is a symlink to
# /private/var/folders/... The resolver uses pwd -P internally, so we
# canonicalize PWD with `cd "$(pwd -P)"` after entering the tmp dir to keep
# string comparisons honest.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
LIB="${REPO_ROOT}/scripts/harness-lib.sh"

# shellcheck source=scripts/harness-lib.sh disable=SC1091
source "${LIB}"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Track every tmp dir we create so we clean up on ANY exit path (success,
# failure, or interrupt). Without this, a mid-case `fail` that bails out of
# a subshell early would leak the tmp dir until reboot.
TMP_DIRS=()
# shellcheck disable=SC2329 # invoked via `trap cleanup_tmp_dirs EXIT INT TERM`
cleanup_tmp_dirs() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [ -n "${d}" ] && [ -d "${d}" ] && rm -rf "${d}"
  done
}
trap cleanup_tmp_dirs EXIT INT TERM

# Build a tmp consuming repo with NO scripts/ and NO docs/templates/.
make_fresh_consumer() {
  local d
  d="$(mktemp -d -t zero-setup-consumer-XXXXXX)"
  TMP_DIRS+=("${d}")
  ( cd "${d}" >/dev/null 2>&1 && pwd -P )
}

case_template_resolves_via_plugin() {
  local consumer
  consumer="$(make_fresh_consumer)"

  if (
    cd "${consumer}" || exit 1
    # canonicalize PWD to match resolver's pwd -P semantics on macOS.
    cd "$(pwd -P)" || exit 1
    # shellcheck disable=SC2030,SC2031 # subshell env scoping is intentional per case
    export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"
    got="$(harness_resolve_artifact docs/templates/review-report-template.md 2>/dev/null)"
    [ "${got}" = "${REPO_ROOT}/docs/templates/review-report-template.md" ]
  ); then
    pass "fresh consumer resolves docs/templates/review-report-template.md via plugin root"
  else
    fail "template did not resolve via plugin-root fallback"
  fi

  rm -rf "${consumer}"
}

case_gate_runner_resolves_via_plugin() {
  local consumer
  consumer="$(make_fresh_consumer)"

  if (
    cd "${consumer}" || exit 1
    cd "$(pwd -P)" || exit 1
    # shellcheck disable=SC2030,SC2031 # subshell env scoping is intentional per case
    export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"
    got="$(harness_resolve_artifact scripts/run-verification-gates.sh 2>/dev/null)"
    [ "${got}" = "${REPO_ROOT}/scripts/run-verification-gates.sh" ] && [ -x "${got}" ]
  ); then
    pass "fresh consumer resolves scripts/run-verification-gates.sh via plugin root"
  else
    fail "gate runner did not resolve via plugin-root fallback"
  fi

  rm -rf "${consumer}"
}

case_missing_artifact_is_not_found() {
  local consumer
  consumer="$(make_fresh_consumer)"

  if (
    cd "${consumer}" || exit 1
    cd "$(pwd -P)" || exit 1
    # shellcheck disable=SC2030,SC2031 # subshell env scoping is intentional per case
    export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"
    err="$(harness_resolve_artifact docs/templates/__definitely-missing__.md 2>&1 1>/dev/null)"
    rc=$?
    [ "${rc}" -ne 0 ] || exit 1
    case "${err}" in
      *NotFound*searched=*) exit 0 ;;
      *) exit 1 ;;
    esac
  ); then
    pass "missing artifact yields structured NotFound and non-zero exit"
  else
    fail "missing artifact did not produce structured NotFound"
  fi

  rm -rf "${consumer}"
}

case_no_plugin_root_no_local_is_not_found() {
  # When neither repo-local nor a valid CLAUDE_PLUGIN_ROOT contains the
  # artifact, resolver must reject. We unset CLAUDE_PLUGIN_ROOT entirely.
  local consumer
  consumer="$(make_fresh_consumer)"

  if (
    cd "${consumer}" || exit 1
    cd "$(pwd -P)" || exit 1
    unset CLAUDE_PLUGIN_ROOT
    err="$(harness_resolve_artifact scripts/run-verification-gates.sh 2>&1 1>/dev/null)"
    rc=$?
    [ "${rc}" -ne 0 ] || exit 1
    case "${err}" in
      *NotFound*) exit 0 ;;
      *) exit 1 ;;
    esac
  ); then
    pass "no plugin root + no repo copy => NotFound"
  else
    fail "expected NotFound when neither plugin root nor repo has artifact"
  fi

  rm -rf "${consumer}"
}

echo "test-zero-setup: starting"
case_template_resolves_via_plugin
case_gate_runner_resolves_via_plugin
case_missing_artifact_is_not_found
case_no_plugin_root_no_local_is_not_found

if [ "${failures}" -eq 0 ]; then
  echo "test-zero-setup: all cases passed"
  exit 0
fi

echo "test-zero-setup: ${failures} failure(s)" >&2
exit 1
